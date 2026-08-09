extends Node

signal game_started
signal game_over(is_cleared: bool)
signal graphics_quality_changed(quality: String)

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
const CURRENT_TUTORIAL_VERSION := 3
const TUTORIAL_COURSE_SOLO := "SOLO"
const TUTORIAL_COURSE_LOCAL_2P := "LOCAL_2P"

var tutorial_completed: bool = false
var tutorial_dismissed: bool = false
var tutorial_completed_version: int = 0
var tutorial_dismissed_version: int = 0
var tutorial_prompt_seen_version: int = 0
var tutorial_solo_completed: bool = false
var tutorial_local_2p_completed: bool = false
var graphics_quality: String = GraphicsQuality.BALANCED
var _user_settings: Dictionary = {}

func _ready() -> void:
	print("GameManager initialized.")
	_load_user_settings()
	_load_env()
	_start_dashboard_server()

func should_show_tutorial_on_start() -> bool:
	return tutorial_prompt_seen_version < CURRENT_TUTORIAL_VERSION

func has_tutorial_update() -> bool:
	return (
		tutorial_completed_version > 0
		and tutorial_completed_version < CURRENT_TUTORIAL_VERSION
	)

func mark_tutorial_course_completed(course: String) -> void:
	if course == TUTORIAL_COURSE_LOCAL_2P:
		tutorial_local_2p_completed = true
	else:
		tutorial_solo_completed = true
	tutorial_prompt_seen_version = CURRENT_TUTORIAL_VERSION
	tutorial_dismissed_version = CURRENT_TUTORIAL_VERSION
	tutorial_dismissed = true
	tutorial_completed = tutorial_solo_completed and tutorial_local_2p_completed
	if tutorial_completed:
		tutorial_completed_version = CURRENT_TUTORIAL_VERSION
	else:
		tutorial_completed_version = mini(tutorial_completed_version, CURRENT_TUTORIAL_VERSION - 1)
	_save_user_settings()


func mark_tutorial_completed() -> void:
	# Compatibility helper for older callers. V3 completion requires both course badges.
	tutorial_solo_completed = true
	tutorial_local_2p_completed = true
	tutorial_completed = true
	tutorial_dismissed = true
	tutorial_prompt_seen_version = CURRENT_TUTORIAL_VERSION
	tutorial_completed_version = CURRENT_TUTORIAL_VERSION
	tutorial_dismissed_version = CURRENT_TUTORIAL_VERSION
	_save_user_settings()


func is_tutorial_course_completed(course: String) -> bool:
	return tutorial_local_2p_completed if course == TUTORIAL_COURSE_LOCAL_2P else tutorial_solo_completed


func dismiss_tutorial() -> void:
	tutorial_dismissed = true
	tutorial_prompt_seen_version = CURRENT_TUTORIAL_VERSION
	tutorial_dismissed_version = CURRENT_TUTORIAL_VERSION
	_save_user_settings()

func reset_tutorial_prompt() -> void:
	tutorial_completed = false
	tutorial_dismissed = false
	tutorial_completed_version = 0
	tutorial_dismissed_version = 0
	tutorial_prompt_seen_version = 0
	tutorial_solo_completed = false
	tutorial_local_2p_completed = false
	_save_user_settings()


func set_graphics_quality(value: String) -> void:
	var normalized: String = GraphicsQuality.normalize(value)
	if graphics_quality == normalized:
		return
	graphics_quality = normalized
	_save_user_settings()
	graphics_quality_changed.emit(graphics_quality)


func _load_user_settings() -> void:
	_user_settings.clear()
	if FileAccess.file_exists(USER_SETTINGS_PATH):
		var file := FileAccess.open(USER_SETTINGS_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_user_settings = parsed
			file.close()
	var legacy_completed := bool(_user_settings.get("tutorial_completed", false))
	var legacy_dismissed := bool(_user_settings.get("tutorial_dismissed", false))
	tutorial_completed_version = int(_user_settings.get(
		"tutorial_completed_version",
		1 if legacy_completed else 0
	))
	tutorial_dismissed_version = int(_user_settings.get(
		"tutorial_dismissed_version",
		1 if legacy_dismissed else 0
	))
	tutorial_prompt_seen_version = int(_user_settings.get(
		"tutorial_prompt_seen_version",
		tutorial_dismissed_version
	))
	var legacy_v3_complete := tutorial_completed_version >= CURRENT_TUTORIAL_VERSION
	tutorial_solo_completed = bool(_user_settings.get("tutorial_solo_completed", legacy_v3_complete))
	tutorial_local_2p_completed = bool(_user_settings.get("tutorial_local_2p_completed", legacy_v3_complete))
	tutorial_completed = tutorial_solo_completed and tutorial_local_2p_completed
	tutorial_dismissed = tutorial_prompt_seen_version >= CURRENT_TUTORIAL_VERSION
	graphics_quality = GraphicsQuality.normalize(str(_user_settings.get("graphics_quality", GraphicsQuality.BALANCED)))

func _save_user_settings() -> void:
	_user_settings["tutorial_completed"] = tutorial_completed
	_user_settings["tutorial_dismissed"] = tutorial_dismissed
	_user_settings["tutorial_completed_version"] = tutorial_completed_version
	_user_settings["tutorial_dismissed_version"] = tutorial_dismissed_version
	_user_settings["tutorial_prompt_seen_version"] = tutorial_prompt_seen_version
	_user_settings["tutorial_solo_completed"] = tutorial_solo_completed
	_user_settings["tutorial_local_2p_completed"] = tutorial_local_2p_completed
	_user_settings["graphics_quality"] = graphics_quality
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
