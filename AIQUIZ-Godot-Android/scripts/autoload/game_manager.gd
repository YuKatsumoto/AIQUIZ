extends Node

signal game_started
signal game_over(is_cleared: bool)

# ゲーム全体の設定
var is_2p_mode: bool = false
var selected_difficulty: String = "Normal"
var selected_subject: String = "ALL"
var selected_grade: String = "ALL"
var is_endless_mode: bool = false
var questions_to_clear: int = 10

var current_score: int = 0
var current_question_index: int = 0

const USER_SETTINGS_PATH := "user://settings.json"

var tutorial_completed: bool = false
var tutorial_dismissed: bool = false
var _user_settings: Dictionary = {}

func _ready() -> void:
	print("GameManager initialized.")
	_load_user_settings()
	_load_env()
	_start_dashboard_server()

func should_show_tutorial_on_start() -> bool:
	return not tutorial_completed and not tutorial_dismissed

func mark_tutorial_completed() -> void:
	tutorial_completed = true
	tutorial_dismissed = true
	_save_user_settings()

func dismiss_tutorial() -> void:
	tutorial_dismissed = true
	_save_user_settings()

func reset_tutorial_prompt() -> void:
	tutorial_completed = false
	tutorial_dismissed = false
	_save_user_settings()

func _load_user_settings() -> void:
	_user_settings.clear()
	if FileAccess.file_exists(USER_SETTINGS_PATH):
		var file := FileAccess.open(USER_SETTINGS_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_user_settings = parsed
			file.close()
	tutorial_completed = bool(_user_settings.get("tutorial_completed", false))
	tutorial_dismissed = bool(_user_settings.get("tutorial_dismissed", false))

func _save_user_settings() -> void:
	_user_settings["tutorial_completed"] = tutorial_completed
	_user_settings["tutorial_dismissed"] = tutorial_dismissed
	var file := FileAccess.open(USER_SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_user_settings, "  "))
		file.close()

func _start_dashboard_server() -> void:
	if OS.has_feature("windows"):
		var dash_dir := ProjectSettings.globalize_path("res://../aiquiz-dashboard")
		if DirAccess.dir_exists_absolute(dash_dir):
			# open_consoleフラグをfalseにしてcmd経由で実行することで、完全にバックグラウンド(非表示)で動作させる
			var args = ["/c", "cd /d \"" + dash_dir + "\" && npm run dev"]
			OS.create_process("cmd.exe", args, false)

func _load_env() -> void:
	# .envファイルの簡易パース
	# エクスポートビルド: exe と同じフォルダの .env を優先
	# エディター実行: res://.env にフォールバック
	var env_path := ""
	var exe_dir := OS.get_executable_path().get_base_dir()
	var external_env := exe_dir.path_join(".env")
	if FileAccess.file_exists(external_env):
		env_path = external_env
	elif FileAccess.file_exists("res://.env"):
		env_path = "res://.env"

	if env_path.is_empty():
		return

	var file = FileAccess.open(env_path, FileAccess.READ)
	if file:
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if line.is_empty() or line.begins_with("#"):
				continue
			var parts = line.split("=", true, 1)
			if parts.size() == 2:
				OS.set_environment(parts[0].strip_edges(), parts[1].strip_edges())
		file.close()

func start_game() -> void:
	current_score = 0
	current_question_index = 0
	emit_signal("game_started")
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")

# NOTE: Result handling is done via game_state signals, not scene transitions.

func back_to_menu() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
