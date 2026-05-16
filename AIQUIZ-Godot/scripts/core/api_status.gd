extends Node
class_name ApiStatus

var internet_ok: Variant = null # bool or null
var internet_msg: String = "未チェック"

var openai_key_set: bool = false
var openai_model: String = "gpt-4o"
var openai_status: Variant = null
var openai_msg: String = "未チェック"

var gemini_key_set: bool = false
var gemini_model: String = "gemini-3-flash-preview"
var gemini_status: Variant = null
var gemini_msg: String = "未チェック"

var firebase_configured: bool = false
var firebase_status: Variant = null
var firebase_msg: String = "未チェック"

var offline_count: int = 0
var checking: bool = false

var env_vars: Dictionary = {}

signal check_completed

func _init() -> void:
	_load_env()
	_update_config()

func _load_env() -> void:
	# Determine .env path: prefer external file next to exe (exported build),
	# then fall back to res://.env (editor run).
	var env_path := ""
	var exe_dir := OS.get_executable_path().get_base_dir()
	var external_env := exe_dir.path_join(".env")
	if FileAccess.file_exists(external_env):
		env_path = external_env
	elif FileAccess.file_exists("res://.env"):
		env_path = "res://.env"

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
		
	# Fallbacks for running without .env
	match key:
		"PROXY_URL": return "https://aiquiz-proxy-818033448758.asia-northeast1.run.app"
		"APP_SECRET": return "PEkewaUv6Irgmb8t1zCFMR9Y0Qlo3jOx7hfAyGZiDs2dT4JnBLN5HWcuVpqXKS"
		"FIREBASE_DB_URL": return "https://aiquiz-a12f6-default-rtdb.asia-southeast1.firebasedatabase.app"
		"FIREBASE_RATINGS_PATH": return "quiz_ratings/shared"
		"OPENAI_MODEL": return "gpt-4o"
		"OPENAI_FAST_MODEL": return "gpt-4o-mini"
		"GEMINI_MODEL": return "gemini-3-flash-preview"
		"GEMINI_IMAGE_MODEL": return "gemini-2.5-flash-image"
		
	return default_val

func get_proxy_headers() -> PackedStringArray:
	## プロキシリクエスト用のヘッダー配列を返す（APP_SECRET 付き）
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var secret := get_env("APP_SECRET")
	if not secret.is_empty():
		headers.append("X-App-Secret: " + secret)
	return headers

func _update_config() -> void:
	var proxy := get_env("PROXY_URL")
	if not proxy.is_empty():
		openai_key_set = true
		gemini_key_set = true
	else:
		openai_key_set = not get_env("OPENAI_API_KEY").is_empty()
		var g_key := get_env("GOOGLE_API_KEY")
		if g_key.is_empty():
			g_key = get_env("GEMINI_API_KEY")
		gemini_key_set = not g_key.is_empty()
	
	openai_model = get_env("OPENAI_MODEL", "gpt-4o")
	gemini_model = get_env("GEMINI_MODEL", "gemini-3-flash-preview")
	firebase_configured = not get_env("FIREBASE_DB_URL").is_empty()

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
	_check_firebase()
	
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
	
	var proxy := get_env("PROXY_URL")
	var headers: PackedStringArray
	var url: String
	if not proxy.is_empty():
		headers = get_proxy_headers()
		url = proxy + "/openai"
	else:
		var key := get_env("OPENAI_API_KEY")
		headers = ["Content-Type: application/json", "Authorization: Bearer " + key]
		url = "https://api.openai.com/v1/chat/completions"

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
	http.request(url, headers, HTTPClient.METHOD_POST, body)

func _check_gemini() -> void:
	var proxy := get_env("PROXY_URL")
	var g_key := ""
	if proxy.is_empty():
		g_key = get_env("GOOGLE_API_KEY")
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
	var headers: PackedStringArray
	if not proxy.is_empty():
		headers = get_proxy_headers()
	else:
		headers = ["Content-Type: application/json"]
	var body := JSON.stringify({
		"contents": [{"parts": [{"text": "Reply with just OK"}]}],
		"generationConfig": {"temperature": 0.0, "maxOutputTokens": 5}
	})
	
	var url: String
	if not proxy.is_empty():
		url = proxy + "/gemini?model=" + gemini_model
	else:
		url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [gemini_model, g_key]
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

func _check_firebase() -> void:
	if not firebase_configured:
		firebase_status = false
		firebase_msg = "URL未設定"
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
		else:
			firebase_status = false
			firebase_msg = "接続失敗"
		http.queue_free()
	)
	http.request(url + "/.json?shallow=true", [], HTTPClient.METHOD_GET)
