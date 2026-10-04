extends Node

signal game_started
signal game_over(is_cleared: bool)
signal graphics_quality_changed(quality: String)
signal startup_finished

## Session-only cache: never persist a 'warmed' flag across GPU/driver changes.
var startup_loading: bool = false
var startup_resources: Array[Resource] = []
var startup_report: Dictionary = {}

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
## 5: ハート（HP）・4択のボス壁・回転のこぎり・スコアタワーに合わせ、操作キーを3Dで示す版。
const CURRENT_TUTORIAL_VERSION := 5
## コースごとの完了記録を持たない設定ファイルは、版4での完了として読む。
const LEGACY_COURSE_COMPLETED_VERSION := 4
const TUTORIAL_COURSE_SOLO := "SOLO"
const TUTORIAL_COURSE_LOCAL_2P := "LOCAL_2P"

var tutorial_completed: bool = false
var tutorial_dismissed: bool = false
var tutorial_completed_version: int = 0
var tutorial_dismissed_version: int = 0
var tutorial_prompt_seen_version: int = 0
var tutorial_solo_completed: bool = false
var tutorial_local_2p_completed: bool = false
## コースを完了したときのチュートリアルの版。今の版より古ければ「更新あり」と表示する。
var tutorial_solo_completed_version: int = 0
var tutorial_local_2p_completed_version: int = 0
var graphics_quality: String = GraphicsQuality.BALANCED
## ローカル2P「10問」の引き分けを地下神殿のサドンデスで決着させる（既定オン、
## docs/sudden_death_underground.md 第1章）。メインメニューが試合開始の直前に
## QuizGameState.sudden_death_enabled へ渡す。
var sudden_death_enabled: bool = true
## Tests point the settings file somewhere else (never the player's own).
var settings_path: String = USER_SETTINGS_PATH
var _user_settings: Dictionary = {}

func _ready() -> void:
	print("GameManager initialized.")
	# メニュー LED の戦績とハイライトのリプレイは起動のたびにリセットする。
	MatchHistory.clear()
	HighlightStore.clear()
	_load_user_settings()
	GraphicsQuality.apply_rendering_server(graphics_quality)
	_load_env()

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
		tutorial_local_2p_completed_version = CURRENT_TUTORIAL_VERSION
	else:
		tutorial_solo_completed = true
		tutorial_solo_completed_version = CURRENT_TUTORIAL_VERSION
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
	tutorial_solo_completed_version = CURRENT_TUTORIAL_VERSION
	tutorial_local_2p_completed_version = CURRENT_TUTORIAL_VERSION
	tutorial_completed = true
	tutorial_dismissed = true
	tutorial_prompt_seen_version = CURRENT_TUTORIAL_VERSION
	tutorial_completed_version = CURRENT_TUTORIAL_VERSION
	tutorial_dismissed_version = CURRENT_TUTORIAL_VERSION
	_save_user_settings()


func is_tutorial_course_completed(course: String) -> bool:
	return tutorial_local_2p_completed if course == TUTORIAL_COURSE_LOCAL_2P else tutorial_solo_completed


## そのコースを今の版で完了しているか。前の版だけを完了しているときは false。
func is_tutorial_course_current(course: String) -> bool:
	var version := (
		tutorial_local_2p_completed_version
		if course == TUTORIAL_COURSE_LOCAL_2P
		else tutorial_solo_completed_version
	)
	return is_tutorial_course_completed(course) and version >= CURRENT_TUTORIAL_VERSION


## コース選択などの表示用。"done" = 今の版で完了、"updated" = 前の版で完了、"todo" = 未完了。
func tutorial_course_badge(course: String) -> String:
	if is_tutorial_course_current(course):
		return "done"
	return "updated" if is_tutorial_course_completed(course) else "todo"


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
	tutorial_solo_completed_version = 0
	tutorial_local_2p_completed_version = 0
	_save_user_settings()


func set_graphics_quality(value: String) -> void:
	var normalized: String = GraphicsQuality.normalize(value)
	if graphics_quality == normalized:
		return
	graphics_quality = normalized
	_save_user_settings()
	GraphicsQuality.apply_rendering_server(graphics_quality)
	graphics_quality_changed.emit(graphics_quality)


## 設定画面のサドンデスのオン／オフ。保存し、進行中のゲーム状態にもすぐ反映する。
func set_sudden_death_enabled(value: bool) -> void:
	var changed := sudden_death_enabled != value
	sudden_death_enabled = value
	_push_sudden_death_setting()
	if changed:
		_save_user_settings()


## Hands the setting to the long-lived QuizGameState (QuizManager.game_state).
func _push_sudden_death_setting() -> void:
	var quiz_manager := get_node_or_null("/root/QuizManager")
	if quiz_manager == null:
		return
	var state: Variant = quiz_manager.get("game_state")
	if state is QuizGameState:
		(state as QuizGameState).sudden_death_enabled = sudden_death_enabled


func _load_user_settings() -> void:
	_user_settings.clear()
	if FileAccess.file_exists(settings_path):
		var file := FileAccess.open(settings_path, FileAccess.READ)
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
	var legacy_v3_complete := tutorial_completed_version >= 3
	tutorial_solo_completed = bool(_user_settings.get("tutorial_solo_completed", legacy_v3_complete))
	tutorial_local_2p_completed = bool(_user_settings.get("tutorial_local_2p_completed", legacy_v3_complete))
	tutorial_solo_completed_version = int(_user_settings.get(
		"tutorial_solo_completed_version",
		LEGACY_COURSE_COMPLETED_VERSION if tutorial_solo_completed else 0
	))
	tutorial_local_2p_completed_version = int(_user_settings.get(
		"tutorial_local_2p_completed_version",
		LEGACY_COURSE_COMPLETED_VERSION if tutorial_local_2p_completed else 0
	))
	tutorial_completed = tutorial_solo_completed and tutorial_local_2p_completed
	tutorial_dismissed = tutorial_prompt_seen_version >= CURRENT_TUTORIAL_VERSION
	graphics_quality = GraphicsQuality.normalize(str(_user_settings.get("graphics_quality", GraphicsQuality.BALANCED)))
	sudden_death_enabled = bool(_user_settings.get("sudden_death_enabled", true))

func _save_user_settings() -> void:
	_user_settings["tutorial_completed"] = tutorial_completed
	_user_settings["tutorial_dismissed"] = tutorial_dismissed
	_user_settings["tutorial_completed_version"] = tutorial_completed_version
	_user_settings["tutorial_dismissed_version"] = tutorial_dismissed_version
	_user_settings["tutorial_prompt_seen_version"] = tutorial_prompt_seen_version
	_user_settings["tutorial_solo_completed"] = tutorial_solo_completed
	_user_settings["tutorial_local_2p_completed"] = tutorial_local_2p_completed
	_user_settings["tutorial_solo_completed_version"] = tutorial_solo_completed_version
	_user_settings["tutorial_local_2p_completed_version"] = tutorial_local_2p_completed_version
	_user_settings["graphics_quality"] = graphics_quality
	_user_settings["sudden_death_enabled"] = sudden_death_enabled
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_user_settings, "  "))
		file.close()

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
	SceneTransition.change_scene("res://scenes/game_world.tscn")

# NOTE: Result handling is done via game_state signals, not scene transitions.

func back_to_menu() -> void:
	SceneTransition.change_scene("res://ui/main_menu.tscn")
