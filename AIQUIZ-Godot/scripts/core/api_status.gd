extends Node
class_name ApiStatus

var internet_ok: Variant = null # bool or null
var internet_msg: String = "未チェック"

var proxy_configured: bool = false
var proxy_status: Variant = null
var proxy_msg: String = "未チェック"

## 互換用（PROXY_URL 設定と同義）
var openai_key_set: bool = false
var openai_model: String = "gpt-4o"
var openai_status: Variant = null
var openai_msg: String = "未チェック"

var gemini_key_set: bool = false
var gemini_model: String = "gemini-3-flash-preview"
var user_selected_gemini_model: String = ""
var gemini_status: Variant = null
var gemini_msg: String = "未チェック"

var firebase_configured: bool = false
var firebase_status: Variant = null
var firebase_msg: String = "未チェック"

var offline_count: int = 0
var checking: bool = false

var env_vars: Dictionary = {}

## 予算切れの 503 を受けてから、オンライン生成を止めておく秒数
const ONLINE_PAUSE_SEC := 300.0
var _online_paused_until_ms: int = 0
var _missing_secret_warned: bool = false

## 端末ごとの許可証（device_session.gd）。401 のあと取り直すまで生成を止める秒数
const DEVICE_TOKEN_RETRY_PAUSE_SEC := 30.0
## ラウンド開始時の「新作の数」の問い合わせを待つ上限（準備画面の間に返る想定）
const ROUND_PLAN_TIMEOUT_SEC := 3.0
const DeviceSessionScript := preload("res://scripts/core/device_session.gd")
const EnvFile := preload("res://scripts/core/env_file.gd")
var device_session: Node = null

signal check_completed
## 個々のチェックが返るたびに出る（画面をすぐ更新するため）
signal status_changed

## インターネット疎通の確認先（204 を返す軽い URL）
const INTERNET_CHECK_URL := "https://www.gstatic.com/generate_204"
## どれかの要求が返らなくてもチェックを締める秒数（各 HTTPRequest の timeout より長く）
const CHECK_SAFETY_TIMEOUT_SEC := 10.0
var _checks_pending: int = 0

func _init() -> void:
	_load_env()
	_update_config()


func _ready() -> void:
	device_session = DeviceSessionScript.new()
	device_session.name = "DeviceSession"
	add_child(device_session)

func _load_env() -> void:
	# Determine .env path: prefer external file next to exe (desktop export; never on
	# Android/iOS), then res://.env (editor run), then res://config/app_env.cfg (env_file.gd).
	var env_path := EnvFile.resolve_path()

	if env_path.is_empty():
		return

	var f := FileAccess.open(env_path, FileAccess.READ)
	if f:
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line.is_empty() or line.begins_with("#"):
				continue
			var parts := line.split("=", true, 1)
			if parts.size() == 2:
				# メモ帳などが付ける UTF-8 BOM がキーの先頭に残ると読めないので外す
				var k := parts[0].strip_edges().trim_prefix("﻿")
				var v := parts[1].strip_edges()
				if v.begins_with('"') and v.ends_with('"'):
					v = v.substr(1, v.length() - 2)
				env_vars[k] = v
		f.close()

func get_env(key: String, default_val: String = "") -> String:
	# Priority: OS Env -> .env file -> default
	var os_val := OS.get_environment(key)
	if not os_val.is_empty():
		return os_val
	if env_vars.has(key):
		return env_vars[key]
		
	# Fallbacks for running without .env
	# APP_SECRET は公開リポジトリに置かない。.env（書き出し時に同梱）か環境変数で渡す。
	match key:
		"PROXY_URL": return "https://aiquiz-proxy-818033448758.asia-northeast1.run.app"
		"FIREBASE_DB_URL": return "https://aiquiz-a12f6-default-rtdb.asia-southeast1.firebasedatabase.app"
		"FIREBASE_RATINGS_PATH": return "quiz_ratings/shared"
		"OPENAI_MODEL": return "gpt-4o"
		"OPENAI_FAST_MODEL": return "gpt-4o-mini"
		"GEMINI_MODEL": return "gemini-3-flash-preview"
		"GEMINI_IMAGE_MODEL": return "gemini-2.5-flash-image"
		
	return default_val

func get_proxy_url() -> String:
	return get_env("PROXY_URL").strip_edges()


func is_proxy_available() -> bool:
	return not get_proxy_url().is_empty()


func gemini_endpoint(model: String, streaming: bool = false) -> String:
	var base := get_proxy_url()
	if base.is_empty():
		return ""
	if streaming:
		return base + "/gemini-stream?model=" + model
	return base + "/gemini?model=" + model


func openai_endpoint() -> String:
	var base := get_proxy_url()
	if base.is_empty():
		return ""
	return base + "/openai"


## プロキシリクエスト用のヘッダー（APP_SECRET と、あれば端末の許可証）
func get_proxy_headers() -> PackedStringArray:
	var headers := get_app_headers()
	if device_session != null and device_session.has_valid_token():
		headers.append("X-Device-Token: " + device_session.token)
	return headers


## APP_SECRET だけのヘッダー（許可証を取りに行くとき用）
func get_app_headers() -> PackedStringArray:
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var secret := get_env("APP_SECRET")
	if not secret.is_empty():
		headers.append("X-App-Secret: " + secret)
	elif not _missing_secret_warned:
		_missing_secret_warned = true
		push_warning("[ApiStatus] APP_SECRET が未設定です（.env に APP_SECRET=... を書く）。プロキシは 403 を返します")
	return headers


## プロキシが予算切れ（503）で生成を止めたことを記録する。その間は新しい生成を送らず、
## BufferedQuizProvider がそのラウンドを共有バンクの問題で続ける。
func notify_online_generation_paused(seconds: float = ONLINE_PAUSE_SEC) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	if until > _online_paused_until_ms:
		_online_paused_until_ms = until
		print("[ApiStatus] Online generation paused for %.0fs (proxy budget or device token)" % seconds)


## 予算切れで止めている間と、初回の許可証を取りに行っている間はオンライン生成を送らない
func is_online_generation_paused() -> bool:
	if Time.get_ticks_msec() < _online_paused_until_ms:
		return true
	return device_session != null and device_session.is_waiting_for_token()


## フェーズ C1: このラウンドで何問を Gemini で新しく作るかをプロキシに聞く。
## {level, round_index, new_count, endless_new_ratio}。聞けなかったら空の辞書（呼び出し側は従来どおり）。
func request_round_plan(mode: String) -> Dictionary:
	var base := get_proxy_url().trim_suffix("/")
	if base.is_empty():
		return {}
	var http := HTTPRequest.new()
	http.timeout = ROUND_PLAN_TIMEOUT_SEC
	add_child(http)
	var err := http.request(base + "/round-plan", get_proxy_headers(), HTTPClient.METHOD_POST,
		JSON.stringify({"mode": mode}))
	if err != OK:
		http.queue_free()
		return {}
	var result: Array = await http.request_completed
	http.queue_free()
	var code := int(result[1])
	if code == 401:
		notify_device_token_rejected()
	if code != 200:
		print("[ApiStatus] Round plan unavailable (code=%d)" % code)
		return {}
	var data: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return data if data is Dictionary else {}


## プロキシが許可証を受け付けなかった（401）。取り直す間はそのラウンドを共有バンクで続ける。
func notify_device_token_rejected() -> void:
	notify_online_generation_paused(DEVICE_TOKEN_RETRY_PAUSE_SEC)
	if device_session != null:
		device_session.reject_token()

func _update_config() -> void:
	proxy_configured = is_proxy_available()
	openai_key_set = proxy_configured
	gemini_key_set = proxy_configured
	
	openai_model = get_env("OPENAI_MODEL", "gpt-4o")
	if user_selected_gemini_model.is_empty():
		gemini_model = get_env("GEMINI_MODEL", "gemini-3-flash-preview")
	else:
		gemini_model = user_selected_gemini_model
	firebase_configured = not get_env("FIREBASE_DB_URL").is_empty()

func set_offline_count(count: int) -> void:
	offline_count = count

func run_connectivity_check() -> void:
	if checking:
		return
	checking = true
	_checks_pending = 3
	_update_config()

	# 3 つを同時に投げ、それぞれ返った時点で status_changed、全部そろったら check_completed。
	_check_internet()
	_check_proxy_gateway()
	_check_firebase()
	# 万一どれかが返らなくても「チェック中」のまま止まらないように。
	var timer := get_tree().create_timer(CHECK_SAFETY_TIMEOUT_SEC)
	timer.timeout.connect(_finish_connectivity_check)


## 1 つのチェックが終わった。全部終わったら check_completed を出す。
func _on_check_done() -> void:
	status_changed.emit()
	_checks_pending -= 1
	if _checks_pending <= 0:
		_finish_connectivity_check()


func _finish_connectivity_check() -> void:
	if not checking:
		return
	checking = false
	_checks_pending = 0
	if internet_ok == null:
		internet_ok = false
		internet_msg = "応答なし"
	if proxy_status == null:
		proxy_status = false
		proxy_msg = "応答なし"
	if firebase_status == null:
		firebase_status = false
		firebase_msg = "応答なし"
	check_completed.emit()


## プロキシか Firebase に届いたなら、インターネットにはつながっている。
func _mark_internet_reachable() -> void:
	if internet_ok != true:
		internet_ok = true
		internet_msg = "接続OK"


func _check_internet() -> void:
	internet_msg = "チェック中..."
	internet_ok = null

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 5.0
	http.request_completed.connect(func(result: int, response_code: int, _h, _b):
		# generate_204 は 204 を返す。2xx / 3xx ならつながっている。
		if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 400:
			internet_ok = true
			internet_msg = "接続OK"
		elif internet_ok != true:
			internet_ok = false
			internet_msg = "接続失敗"
		http.queue_free()
		_on_check_done()
	)
	var err := http.request(INTERNET_CHECK_URL)
	if err != OK:
		if internet_ok != true:
			internet_ok = false
			internet_msg = "接続失敗"
		http.queue_free()
		_on_check_done()

func _check_proxy_gateway() -> void:
	if not proxy_configured:
		proxy_status = false
		proxy_msg = "PROXY_URL未設定"
		openai_status = false
		openai_msg = "PROXY_URL未設定"
		gemini_status = false
		gemini_msg = "PROXY_URL未設定"
		_on_check_done.call_deferred()
		return

	proxy_msg = "チェック中..."
	proxy_status = null
	openai_msg = "チェック中..."
	openai_status = null
	gemini_msg = "チェック中..."
	gemini_status = null

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 8.0
	var headers := get_proxy_headers()
	# Gemini は呼ばない。200 ならプロキシに届き、APP_SECRET も正しい（違えば 403）。
	var url := get_proxy_url().trim_suffix("/") + "/health"
	http.request_completed.connect(func(result: int, response_code: int, _h, _b: PackedByteArray):
		var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == 200
		proxy_status = ok
		gemini_status = ok
		openai_status = ok
		if ok:
			proxy_msg = "接続OK"
			_mark_internet_reachable()
			gemini_msg = "接続OK (Gateway)"
			openai_msg = "接続OK (Gateway)"
		else:
			var err_txt := "エラー: " + str(response_code) if response_code >= 400 else "応答なし"
			proxy_msg = err_txt
			gemini_msg = err_txt
			openai_msg = err_txt
		http.queue_free()
		_on_check_done()
	)
	if http.request(url, headers, HTTPClient.METHOD_GET) != OK:
		proxy_status = false
		gemini_status = false
		openai_status = false
		proxy_msg = "接続失敗"
		gemini_msg = "接続失敗"
		openai_msg = "接続失敗"
		http.queue_free()
		_on_check_done()

func _check_firebase() -> void:
	if not firebase_configured:
		firebase_status = false
		firebase_msg = "URL未設定"
		_on_check_done.call_deferred()
		return
	firebase_msg = "チェック中..."
	firebase_status = null

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 5.0
	
	var url := get_env("FIREBASE_DB_URL")
	if url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
		
	http.request_completed.connect(func(result: int, response_code: int, _h, _b):
		if result == HTTPRequest.RESULT_SUCCESS and response_code != 0:
			# Realtime DB returns 200 (OK) or 401 (Unauthorized - no auth parameter), 
			# both of which successfully prove network reachability to the Firebase host.
			firebase_status = true
			firebase_msg = "接続OK"
			_mark_internet_reachable()
		else:
			firebase_status = false
			firebase_msg = "接続失敗"
		http.queue_free()
		_on_check_done()
	)
	if http.request(url + "/.json?shallow=true", [], HTTPClient.METHOD_GET) != OK:
		firebase_status = false
		firebase_msg = "接続失敗"
		http.queue_free()
		_on_check_done()
