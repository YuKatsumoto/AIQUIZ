extends Node

## LiveConfigManager (Autoload)
## Firebaseからlive_configノードのデータを取得し、ゲーム全体に提供する

signal config_updated

var announcement: String = ""
var event_theme: String = ""
var is_active: bool = false
var last_updated: int = 0

var _db_url: String = ""

func _ready() -> void:
	# APIステータスチェック完了後にURLを取得して初期化
	if ApiStatusAutoload.firebase_configured:
		_initialize()
	else:
		ApiStatusAutoload.check_completed.connect(_on_api_check_completed)

func _on_api_check_completed() -> void:
	if ApiStatusAutoload.firebase_configured and _db_url.is_empty():
		_initialize()

func _initialize() -> void:
	_db_url = ApiStatusAutoload.get_env("FIREBASE_DB_URL", "")
	if not _db_url.is_empty():
		if not _db_url.ends_with("/"):
			_db_url += "/"
		fetch_config()

func fetch_config() -> void:
	if _db_url.is_empty():
		return
		
	var url := _db_url + "live_config.json"
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 5.0
	http.request_completed.connect(_on_fetch_completed.bind(http))
	
	var err := http.request(url)
	if err != OK:
		push_warning("[LiveConfigManager] HTTP request failed to start: %d" % err)
		http.queue_free()

func _on_fetch_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
			var data = json.data
			announcement = data.get("announcement", "")
			event_theme = data.get("event_theme", "")
			is_active = data.get("is_active", false)
			last_updated = data.get("updated_at", 0)
			
			print("[LiveConfigManager] Config updated. Active: %s, Theme: %s" % [is_active, event_theme])
			config_updated.emit()
		else:
			push_warning("[LiveConfigManager] Failed to parse JSON response")
	else:
		push_warning("[LiveConfigManager] Fetch failed: result=%d code=%d" % [result, response_code])
