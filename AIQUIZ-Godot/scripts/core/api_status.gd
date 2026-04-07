extends Node
class_name ApiStatus

var internet_ok: Variant = null # bool or null
var internet_msg: String = "未チェック"

var openai_key_set: bool = false
var openai_model: String = "gpt-4o"
var openai_status: Variant = null
var openai_msg: String = "未チェック"

var gemini_key_set: bool = false
var gemini_model: String = "gemini-2.5-flash"
var gemini_status: Variant = null
var gemini_msg: String = "未チェック"

var offline_count: int = 0
var checking: bool = false

var env_vars: Dictionary = {}

signal check_completed

func _init() -> void:
	_load_env()
	_update_config()

func _load_env() -> void:
	# Try loading from .env file
	if FileAccess.file_exists("res://.env"):
		var f := FileAccess.open("res://.env", FileAccess.READ)
		if f:
			while not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line.is_empty() or line.begins_with("#"):
					continue
				var parts := line.split("=", true, 1)
				if parts.size() == 2:
					var k := parts[0].strip_edges()
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
	return default_val

func _update_config() -> void:
	openai_key_set = not get_env("OPENAI_API_KEY").is_empty()
	openai_model = get_env("OPENAI_MODEL", "gpt-4o")
	var g_key := get_env("GOOGLE_API_KEY")
	if g_key.is_empty():
		g_key = get_env("GEMINI_API_KEY")
	gemini_key_set = not g_key.is_empty()
	gemini_model = get_env("GEMINI_MODEL", "gemini-2.5-flash")

func set_offline_count(count: int) -> void:
	offline_count = count

func run_connectivity_check() -> void:
	if checking:
		return
	checking = true
	_update_config()

	# Start checks concurrently
	_check_internet()
	_check_openai()
	_check_gemini()
	
	# Usually we would await them, but for UI we can just emit completed when we guess they're done.
	# Or emit immediately and let UI poll.
	# We'll emit check_completed on a delay.
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(func(): 
		checking = false
		check_completed.emit()
	)

func _check_internet() -> void:
	internet_msg = "チェック中..."
	internet_ok = null
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 5.0
	http.request_completed.connect(func(result: int, response_code: int, _h, _b):
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			internet_ok = true
			internet_msg = "接続OK"
		else:
			internet_ok = false
			internet_msg = "接続失敗"
		http.queue_free()
	)
	var err := http.request("https://checkonline.home-assistant.io/generate_204")
	if err != OK:
		internet_ok = false
		internet_msg = "接続失敗"
		http.queue_free()

func _check_openai() -> void:
	if not openai_key_set:
		openai_status = false
		openai_msg = "APIキー未設定"
		return
	openai_msg = "チェック中..."
	openai_status = null

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 8.0
	var key := get_env("OPENAI_API_KEY")
	var headers := ["Content-Type: application/json", "Authorization: Bearer " + key]
	var body := JSON.stringify({
		"model": get_env("OPENAI_FAST_MODEL", "gpt-4o-mini"),
		"messages": [{"role": "user", "content": "Reply with just OK"}],
		"max_tokens": 5
	})
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			openai_status = true
			openai_msg = "接続OK"
		else:
			openai_status = false
			var err_txt: String = "応答なし"
			if response_code >= 400:
				err_txt = "エラー: " + str(response_code)
			openai_msg = err_txt
		http.queue_free()
	)
	http.request("https://api.openai.com/v1/chat/completions", headers, HTTPClient.METHOD_POST, body)

func _check_gemini() -> void:
	var g_key := get_env("GOOGLE_API_KEY")
	if g_key.is_empty():
		g_key = get_env("GEMINI_API_KEY")
	if g_key.is_empty():
		gemini_status = false
		gemini_msg = "APIキー未設定"
		return

	gemini_msg = "チェック中..."
	gemini_status = null

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 8.0
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({
		"contents": [{"parts": [{"text": "Reply with just OK"}]}],
		"generationConfig": {"temperature": 0.0, "maxOutputTokens": 5}
	})
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [gemini_model, g_key]
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			gemini_status = true
			gemini_msg = "接続OK"
		else:
			gemini_status = false
			var err_txt: String = "応答なし"
			if response_code >= 400:
				err_txt = "エラー: " + str(response_code)
			gemini_msg = err_txt
		http.queue_free()
	)
	http.request(url, headers, HTTPClient.METHOD_POST, body)
