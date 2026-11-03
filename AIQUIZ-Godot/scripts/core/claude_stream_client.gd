extends Node
class_name ClaudeStreamClient

## プロキシの /claude-stream を受け取る SSE ストリーミングクライアント
##
## HTTPClient を使ってチャンク単位でレスポンスを受信し、
## SSE (Server-Sent Events) の `data: {...}` 行をリアルタイムにパースして
## テキスト差分を即座に通知する。プロキシが送る行は次の 3 種類（aiquiz-proxy/claude-live.js）:
##   data: {"type":"text","text":"..."}   … 本文の続き
##   data: {"type":"done","stop_reason":"..."}
##   data: {"type":"error","error":"..."} … 途中で止まった（それまでの本文は使ってよい）
## 考えているあいだはプロキシが `: keep-alive` のコメント行を送るので、無通信タイムアウトにはならない。
##
## 使い方:
##   var client = ClaudeStreamClient.new()
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
var _byte_buffer: PackedByteArray = PackedByteArray()  # UTF-8デコード途中の生バイトバッファ

var _start_time: float = 0.0
var _last_chunk_time: float = 0.0

var _http_ok: bool = false
## プロキシが error を送ってきた（拒否・途中の失敗）
var stream_error: String = ""
## 最後に受信した HTTP ステータス（429 判定などに使用）
var response_code: int = 0


## ── パブリックメソッド ──

## ストリーミングリクエストを開始する
## url: 完全なURL (https://... を含む)
## headers: ヘッダー配列 (["Content-Type: application/json", ...])
## body: リクエストボディ (JSON文字列)
func start_stream(url: String, headers: PackedStringArray, body: String) -> void:
	if _state != State.IDLE:
		push_error("[ClaudeStreamClient] Already running, cannot start another stream")
		return

	# URL をパースする
	var parsed := _parse_url(url)
	if parsed.is_empty():
		push_error("[ClaudeStreamClient] Failed to parse URL: " + url)
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
	_byte_buffer = PackedByteArray()
	_start_time = Time.get_ticks_msec() / 1000.0
	_last_chunk_time = _start_time

	# HTTPClient を初期化して接続開始
	_http = HTTPClient.new()
	# チャンクサイズを大きめに設定して効率化
	_http.read_chunk_size = 4096

	print("[%d] [ClaudeStreamClient] Connecting to %s:%d (TLS=%s)..." % [Time.get_ticks_msec(), _host, _port, str(_use_tls)])
	var err: int
	if _use_tls:
		var tls_opts := TLSOptions.client()
		err = _http.connect_to_host(_host, _port, tls_opts)
	else:
		err = _http.connect_to_host(_host, _port)
	if err != OK:
		push_error("[ClaudeStreamClient] connect_to_host failed: %d" % err)
		_finish(false)
		return

	_state = State.CONNECTING


func _process(_delta: float) -> void:
	if _state == State.IDLE or _state == State.DONE or _state == State.ERROR:
		return

	# HTTPClient をポーリング
	var err := _http.poll()
	if err != OK:
		push_error("[ClaudeStreamClient] poll() error: %d" % err)
		_finish(false)
		return

	var now := Time.get_ticks_msec() / 1000.0

	# グローバルタイムアウト
	if now - _start_time > TIMEOUT_SECONDS:
		push_warning("[ClaudeStreamClient] Global timeout (%.1f s)" % TIMEOUT_SECONDS)
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


## 途中でやめる（ラウンド終了時の OnlineFetch.cancel_all から）。stream_finished は出さない。
func cancel_request() -> void:
	if _state == State.DONE or _state == State.ERROR:
		return
	_state = State.DONE
	if _http:
		_http.close()
		_http = null


## ── 内部状態ハンドラ ──

func _handle_connecting(status: int, _now: float) -> void:
	match status:
		HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING:
			# まだ接続中 → 次フレームを待つ
			pass
		HTTPClient.STATUS_CONNECTED:
			# 接続完了 → リクエスト送信
			print("[%d] [ClaudeStreamClient] Connected, sending request..." % Time.get_ticks_msec())
			var err := _http.request(
				HTTPClient.METHOD_POST,
				_path,
				_headers,
				_body
			)
			if err != OK:
				push_error("[ClaudeStreamClient] request() failed: %d" % err)
				_finish(false)
				return
			_state = State.REQUESTING
		HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE:
			push_error("[ClaudeStreamClient] Connection failed: status=%d" % status)
			_finish(false)
		_:
			# 予期しない状態
			if status == HTTPClient.STATUS_CONNECTION_ERROR:
				push_error("[ClaudeStreamClient] Connection error")
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
			print("[%d] [ClaudeStreamClient] Response code: %d" % [Time.get_ticks_msec(), resp_code])
			if not _http_ok:
				push_error("[ClaudeStreamClient] Non-200 response: %d" % resp_code)
				_state = State.BODY  # ボディを読みきってから finish
				return
			_last_chunk_time = _now
			_state = State.BODY
		HTTPClient.STATUS_CONNECTED:
			# リクエスト完了→ヘッダー待ち遷移（一部環境でこの状態になる場合がある）
			_state = State.HEADERS
		_:
			if status == HTTPClient.STATUS_CONNECTION_ERROR:
				push_error("[ClaudeStreamClient] Connection error during request")
				_finish(false)


func _handle_headers(status: int, _now: float) -> void:
	match status:
		HTTPClient.STATUS_BODY:
			var resp_code := _http.get_response_code()
			response_code = resp_code
			_http_ok = resp_code == 200
			print("[%d] [ClaudeStreamClient] Response code (headers): %d" % [Time.get_ticks_msec(), resp_code])
			if not _http_ok:
				push_error("[ClaudeStreamClient] Non-200 response: %d" % resp_code)
			_last_chunk_time = _now
			_state = State.BODY
		_:
			if status == HTTPClient.STATUS_CONNECTION_ERROR:
				push_error("[ClaudeStreamClient] Connection error during headers")
				_finish(false)


func _handle_body(status: int, now: float) -> void:
	if status == HTTPClient.STATUS_CONNECTION_ERROR:
		push_error("[ClaudeStreamClient] Connection error during body read")
		_finish(false)
		return

	if status == HTTPClient.STATUS_BODY:
		# ボディチャンクを読み取る
		var chunk := _http.read_response_body_chunk()
		if chunk.size() > 0:
			_last_chunk_time = now
			# 生バイトをバッファに追加し、完全なUTF-8シーケンスだけをデコードする。
			# マルチバイト文字（日本語など）がチャンク境界で分断されても
			# 途中で �(U+FFFD) にデコードされるのを防ぐ。
			var chunk_str := _decode_utf8_streaming(chunk)
			if not chunk_str.is_empty():
				_process_sse_chunk(chunk_str)
		else:
			# チャンクがまだ来ていない → アイドルタイムアウトをチェック
			if now - _last_chunk_time > MAX_IDLE_SECONDS:
				push_warning("[ClaudeStreamClient] Idle timeout (%.1f s without data)" % MAX_IDLE_SECONDS)
				_finish(not _accumulated_text.is_empty())
				return

	# ボディ読み取り完了の判定
	if status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_DISCONNECTED:
		# 接続が閉じられた（レスポンス完了）
		# バイトバッファに残った分をデコード（末尾に不完全バイトが残っていれば置換文字になるが、
		# 正常終了時は完全なUTF-8で終わるため通常は空か完全なテキスト）
		if _byte_buffer.size() > 0:
			var tail := _byte_buffer.get_string_from_utf8()
			_byte_buffer = PackedByteArray()
			if not tail.is_empty():
				_process_sse_chunk(tail)
		# 残りの行バッファを処理
		if not _line_buffer.is_empty():
			_process_sse_line(_line_buffer)
			_line_buffer = ""
		print("[%d] [ClaudeStreamClient] Stream completed. Total text length: %d" % [Time.get_ticks_msec(), _accumulated_text.length()])
		var ok := _http_ok and not _accumulated_text.is_empty()
		_finish(ok)


## ── UTF-8 ストリーミングデコード ──

## 生バイトチャンクを内部バッファに追加し、完全なUTF-8シーケンスまでをデコードして返す。
## 末尾に途中で切れたマルチバイト文字が残っていれば、それはバッファに保持し
## 次回のチャンクと連結してからデコードする（文字化け �(U+FFFD) の防止）。
func _decode_utf8_streaming(new_bytes: PackedByteArray) -> String:
	_byte_buffer.append_array(new_bytes)
	var size := _byte_buffer.size()
	if size == 0:
		return ""

	# 末尾から最大4バイトを調べ、不完全なマルチバイト列の開始位置を探す
	var split := size
	var scanned := 0
	var i := size - 1
	while i >= 0 and scanned < 4:
		var b := _byte_buffer[i]
		if b < 0x80:
			# ASCII単独バイト → 末尾は完全。全体をデコード可能
			break
		elif b >= 0xC0:
			# マルチバイトの先頭バイト → 必要バイト数を判定
			var expected := 2
			if b >= 0xF0:
				expected = 4
			elif b >= 0xE0:
				expected = 3
			var have := size - i
			if have < expected:
				# シーケンスが未完成 → この位置以降を次回に持ち越す
				split = i
			break
		# 継続バイト(0x80-0xBF) → さらに前方の先頭バイトを探す
		i -= 1
		scanned += 1

	if split <= 0:
		return ""

	var decodable := _byte_buffer.slice(0, split)
	_byte_buffer = _byte_buffer.slice(split)
	return decodable.get_string_from_utf8()


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
## SSE形式: "data: {JSON}" → type が text なら本文に足す
func _process_sse_line(line: String) -> void:
	if not line.begins_with("data: "):
		# "data:" 以外の行（": keep-alive" のコメント、"event:" 等）は無視
		return

	var json_str := line.substr(6).strip_edges()  # "data: " の後を取得

	# JSONパース
	var json := JSON.new()
	var parse_err := json.parse(json_str)
	if parse_err != OK:
		# パースに失敗しても致命的ではない（部分データの場合がある）
		push_warning("[ClaudeStreamClient] JSON parse warning on SSE line (ignoring): %s" % json_str.left(100))
		return

	var data = json.get_data()
	if not (data is Dictionary):
		return

	match str(data.get("type", "")):
		"text":
			var text = data.get("text", "")
			if not (text is String) or text.is_empty():
				return
			# テキストチャンクを蓄積してシグナルを発行
			_accumulated_text += text
			text_chunk_received.emit(_accumulated_text, text)
		"error":
			stream_error = str(data.get("error", "error"))
			push_warning("[ClaudeStreamClient] Proxy reported an error: %s" % stream_error)


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
		push_error("[ClaudeStreamClient] URL must start with http:// or https://")
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
