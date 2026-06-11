extends Node
class_name GeminiStreamClient

## Gemini API SSE ストリーミングクライアント
##
## HTTPClient を使ってチャンク単位でレスポンスを受信し、
## SSE (Server-Sent Events) の `data: {...}` 行をリアルタイムにパースして
## テキスト差分を即座に通知する。
##
## 使い方:
##   var client = GeminiStreamClient.new()
##   add_child(client)
##   client.text_chunk_received.connect(_on_text_chunk)
##   client.stream_finished.connect(_on_finished)
##   client.start_stream(url, headers, body)
##
## ライフサイクル:
##   start_stream() → _process()でポーリング → text_chunk_received × N → stream_finished → queue_free()

## ── シグナル ──

## 新しいテキストチャンクが到着するたびに発火
## accumulated_text: ストリーム開始からの累積テキスト全体
## chunk_text: この回で新たに追加されたテキスト差分
signal text_chunk_received(accumulated_text: String, chunk_text: String)

## ストリーム完了時に発火（成功・失敗問わず）
## success: 正常に完了したかどうか
## accumulated_text: 最終的に累積されたテキスト全体
signal stream_finished(success: bool, accumulated_text: String)

## ── 定数 ──
const TIMEOUT_SECONDS: float = 90.0
const MAX_IDLE_SECONDS: float = 20.0  # チャンクが来なくなってから切断するまで

## ── 内部状態 ──

enum State {
	IDLE,
	CONNECTING,
	REQUESTING,
	HEADERS,
	BODY,
	DONE,
	ERROR
}

var _state: State = State.IDLE
var _http: HTTPClient = null
var _host: String = ""
var _port: int = 443
var _path: String = ""
var _use_tls: bool = true
var _headers: PackedStringArray = []
var _body: String = ""

var _accumulated_text: String = ""
var _line_buffer: String = ""  # SSE行の途中バッファ

var _start_time: float = 0.0
var _last_chunk_time: float = 0.0

var _is_proxy: bool = false  # プロキシ経由かどうか
var _http_ok: bool = false
## 最後に受信した HTTP ステータス（429 判定などに使用）
var response_code: int = 0


## ── パブリックメソッド ──

## ストリーミングリクエストを開始する
## url: 完全なURL (https://... を含む)
## headers: ヘッダー配列 (["Content-Type: application/json", ...])
## body: リクエストボディ (JSON文字列)
func start_stream(url: String, headers: PackedStringArray, body: String) -> void:
	if _state != State.IDLE:
		push_error("[GeminiStreamClient] Already running, cannot start another stream")
		return

	# URL をパースする
	var parsed := _parse_url(url)
	if parsed.is_empty():
		push_error("[GeminiStreamClient] Failed to parse URL: " + url)
		_finish(false)
		return

	_host = parsed["host"]
	_port = parsed["port"]
	_path = parsed["path"]
	_use_tls = parsed["tls"]
	_headers = headers
	_body = body

	_accumulated_text = ""
	_line_buffer = ""
	_start_time = Time.get_ticks_msec() / 1000.0
	_last_chunk_time = _start_time

	# HTTPClient を初期化して接続開始
	_http = HTTPClient.new()
	# チャンクサイズを大きめに設定して効率化
	_http.read_chunk_size = 4096

	print("[%d] [GeminiStreamClient] Connecting to %s:%d (TLS=%s)..." % [Time.get_ticks_msec(), _host, _port, str(_use_tls)])
	var err: int
	if _use_tls:
		var tls_opts := TLSOptions.client()
		err = _http.connect_to_host(_host, _port, tls_opts)
	else:
		err = _http.connect_to_host(_host, _port)
	if err != OK:
		push_error("[GeminiStreamClient] connect_to_host failed: %d" % err)
		_finish(false)
		return

	_state = State.CONNECTING


func _process(_delta: float) -> void:
	if _state == State.IDLE or _state == State.DONE or _state == State.ERROR:
		return

	# HTTPClient をポーリング
	var err := _http.poll()
	if err != OK:
		push_error("[GeminiStreamClient] poll() error: %d" % err)
		_finish(false)
		return

	var now := Time.get_ticks_msec() / 1000.0

	# グローバルタイムアウト
	if now - _start_time > TIMEOUT_SECONDS:
		push_warning("[GeminiStreamClient] Global timeout (%.1f s)" % TIMEOUT_SECONDS)
		_finish(false)
		return

	var status := _http.get_status()

	match _state:
		State.CONNECTING:
			_handle_connecting(status, now)
		State.REQUESTING:
			_handle_requesting(status, now)
		State.HEADERS:
			_handle_headers(status, now)
		State.BODY:
			_handle_body(status, now)


## ── 内部状態ハンドラ ──

func _handle_connecting(status: int, _now: float) -> void:
	match status:
		HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING:
			# まだ接続中 → 次フレームを待つ
			pass
		HTTPClient.STATUS_CONNECTED:
			# 接続完了 → リクエスト送信
			print("[%d] [GeminiStreamClient] Connected, sending request..." % Time.get_ticks_msec())
			var err := _http.request(
				HTTPClient.METHOD_POST,
				_path,
				_headers,
				_body
			)
			if err != OK:
				push_error("[GeminiStreamClient] request() failed: %d" % err)
				_finish(false)
				return
			_state = State.REQUESTING
		HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE:
			push_error("[GeminiStreamClient] Connection failed: status=%d" % status)
			_finish(false)
		_:
			# 予期しない状態
			if status == HTTPClient.STATUS_CONNECTION_ERROR:
				push_error("[GeminiStreamClient] Connection error")
				_finish(false)


func _handle_requesting(status: int, _now: float) -> void:
	match status:
		HTTPClient.STATUS_REQUESTING:
			# リクエスト送信中 → 待つ
			pass
		HTTPClient.STATUS_BODY:
			# レスポンスのヘッダーを受信し、ボディ受信開始
			var resp_code := _http.get_response_code()
			response_code = resp_code
			_http_ok = resp_code == 200
			print("[%d] [GeminiStreamClient] Response code: %d" % [Time.get_ticks_msec(), resp_code])
			if not _http_ok:
				push_error("[GeminiStreamClient] Non-200 response: %d" % resp_code)
				_state = State.BODY  # ボディを読みきってから finish
				return
			_last_chunk_time = _now
			_state = State.BODY
		HTTPClient.STATUS_CONNECTED:
			# リクエスト完了→ヘッダー待ち遷移（一部環境でこの状態になる場合がある）
			_state = State.HEADERS
		_:
			if status == HTTPClient.STATUS_CONNECTION_ERROR:
				push_error("[GeminiStreamClient] Connection error during request")
				_finish(false)


func _handle_headers(status: int, _now: float) -> void:
	match status:
		HTTPClient.STATUS_BODY:
			var resp_code := _http.get_response_code()
			response_code = resp_code
			_http_ok = resp_code == 200
			print("[%d] [GeminiStreamClient] Response code (headers): %d" % [Time.get_ticks_msec(), resp_code])
			if not _http_ok:
				push_error("[GeminiStreamClient] Non-200 response: %d" % resp_code)
			_last_chunk_time = _now
			_state = State.BODY
		_:
			if status == HTTPClient.STATUS_CONNECTION_ERROR:
				push_error("[GeminiStreamClient] Connection error during headers")
				_finish(false)


func _handle_body(status: int, now: float) -> void:
	if status == HTTPClient.STATUS_CONNECTION_ERROR:
		push_error("[GeminiStreamClient] Connection error during body read")
		_finish(false)
		return

	if status == HTTPClient.STATUS_BODY:
		# ボディチャンクを読み取る
		var chunk := _http.read_response_body_chunk()
		if chunk.size() > 0:
			_last_chunk_time = now
			var chunk_str := chunk.get_string_from_utf8()
			_process_sse_chunk(chunk_str)
		else:
			# チャンクがまだ来ていない → アイドルタイムアウトをチェック
			if now - _last_chunk_time > MAX_IDLE_SECONDS:
				push_warning("[GeminiStreamClient] Idle timeout (%.1f s without data)" % MAX_IDLE_SECONDS)
				_finish(not _accumulated_text.is_empty())
				return

	# ボディ読み取り完了の判定
	if status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_DISCONNECTED:
		# 接続が閉じられた（レスポンス完了）
		# 残りのバッファを処理
		if not _line_buffer.is_empty():
			_process_sse_line(_line_buffer)
			_line_buffer = ""
		print("[%d] [GeminiStreamClient] Stream completed. Total text length: %d" % [Time.get_ticks_msec(), _accumulated_text.length()])
		var ok := _http_ok and not _accumulated_text.is_empty()
		_finish(ok)


## ── SSEパース ──

## 受信したチャンクをSSE行に分割して処理する
func _process_sse_chunk(chunk: String) -> void:
	# バッファに追加してから行ごとに処理
	_line_buffer += chunk

	while true:
		var newline_pos := _line_buffer.find("\n")
		if newline_pos == -1:
			break  # 完全な行がまだない → 次のチャンクを待つ

		var line := _line_buffer.substr(0, newline_pos).strip_edges()
		_line_buffer = _line_buffer.substr(newline_pos + 1)

		if line.is_empty():
			continue  # SSEの空行（イベント区切り）はスキップ

		_process_sse_line(line)


## 1つのSSE行を処理する
## SSE形式: "data: {JSON}" → candidates[0].content.parts[0].text を抽出
func _process_sse_line(line: String) -> void:
	if not line.begins_with("data: "):
		# "data:" 以外の行（"event:", "id:", コメント行 等）は無視
		return

	var json_str := line.substr(6).strip_edges()  # "data: " の後を取得

	# "[DONE]" などの終了マーカー
	if json_str == "[DONE]":
		return

	# JSONパース
	var json := JSON.new()
	var parse_err := json.parse(json_str)
	if parse_err != OK:
		# パースに失敗しても致命的ではない（部分データの場合がある）
		push_warning("[GeminiStreamClient] JSON parse warning on SSE line (ignoring): %s" % json_str.left(100))
		return

	var data = json.get_data()
	if not (data is Dictionary):
		return

	# Gemini API の SSE レスポンス構造:
	# { "candidates": [{ "content": { "parts": [{ "text": "..." }] } }] }
	var candidates = data.get("candidates", [])
	if not (candidates is Array) or candidates.is_empty():
		return

	var candidate = candidates[0]
	if not (candidate is Dictionary):
		return

	var content = candidate.get("content", {})
	if not (content is Dictionary):
		return

	var parts = content.get("parts", [])
	if not (parts is Array) or parts.is_empty():
		return

	var first_part = parts[0]
	if not (first_part is Dictionary):
		return

	var text = first_part.get("text", "")
	if not (text is String) or text.is_empty():
		return

	# テキストチャンクを蓄積してシグナルを発行
	_accumulated_text += text
	text_chunk_received.emit(_accumulated_text, text)


## ── 完了処理 ──

func _finish(success: bool) -> void:
	_state = State.DONE if success else State.ERROR

	if _http:
		_http.close()
		_http = null

	stream_finished.emit(success, _accumulated_text)

	# 自分自身をクリーンアップ（次フレームで）
	call_deferred("queue_free")


## ── URLパーサー ──

## URLをパースして { host, port, path, tls } を返す
func _parse_url(url: String) -> Dictionary:
	var result := {}

	var tls := false
	var working := url

	if working.begins_with("https://"):
		tls = true
		working = working.substr(8)
	elif working.begins_with("http://"):
		tls = false
		working = working.substr(7)
	else:
		push_error("[GeminiStreamClient] URL must start with http:// or https://")
		return {}

	# パスを分離
	var path_start := working.find("/")
	var host_port: String
	var path: String
	if path_start == -1:
		host_port = working
		path = "/"
	else:
		host_port = working.substr(0, path_start)
		path = working.substr(path_start)

	# ポートを分離
	var host: String
	var port: int
	var colon_pos := host_port.find(":")
	if colon_pos != -1:
		host = host_port.substr(0, colon_pos)
		port = int(host_port.substr(colon_pos + 1))
	else:
		host = host_port
		port = 443 if tls else 80

	result["host"] = host
	result["port"] = port
	result["path"] = path
	result["tls"] = tls
	return result
