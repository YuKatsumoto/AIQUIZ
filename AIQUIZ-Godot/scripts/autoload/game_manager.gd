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
const EnvFile := preload("res://scripts/core/env_file.gd")
## 5: ハート（HP）・4択のボス壁・回転のこぎり・スコアタワーに合わせ、操作キーを3Dで示す版。
## 6: 前後左右の移動を1ステップに、ジャンプを独立、エモートは3つすべて、
##    2Pはゴール後にスコアタワーの勝敗判定まで進み、得点の計算方法を説明する版。
const CURRENT_TUTORIAL_VERSION := 6
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
## 設定画面の「FPS上限」で選べる値（Engine.max_fps）。0 は制限なし（垂直同期だけが上限）。
const MAX_FPS_CHOICES: Array[int] = [30, 60, 120, 144, 240, 0]
## モバイル（GraphicsQuality.is_mobile_target()）で選べる値。パネルは最大 120Hz なので 144/240 は意味がなく、
## 「制限なし」は発熱と電池を食うだけなので出さない。既定は DEFAULT_MAX_FPS（60）のまま。
const MOBILE_MAX_FPS_CHOICES: Array[int] = [30, 60, 120]
## 「FPS上限」の既定値。プレイヤーが選ぶまではこの値で動く。
const DEFAULT_MAX_FPS := 60
## 設定画面の「FPS上限」。起動時と変更時に Engine.max_fps へ渡す。
var max_fps: int = DEFAULT_MAX_FPS
## プレイヤーが設定画面で FPS上限を選んだか。選ぶ前の設定ファイルに残る max_fps
## （既定が「制限なし」だった頃に自動で書かれた 0）は使わず、既定値で動かす。
var max_fps_chosen: bool = false
## ローカル2P「10問」の引き分けを地下神殿のサドンデスで決着させる（既定オン、
## docs/sudden_death_underground.md 第1章）。メインメニューが試合開始の直前に
## QuizGameState.sudden_death_enabled へ渡す。
var sudden_death_enabled: bool = true
## オンライン対戦のマッチング演出を「みじかい」にする（docs/online_match_staging/spec.md D11。既定は「ふつう」）。
var online_staging_short: bool = false
## オンライン対戦で相手に見せるプリセットのニックネーム ID（NetNicknames）。-1 は未選択。
var online_nickname: int = -1
## オンライン対戦で相手に見せる名前（自分で入力するか、サイコロの二つ名）。空なら未設定。
var online_name: String = ""
## チュートリアルの練習コースのスタンプ（docs/new_tutorial/foundation_design.md 5章）。
## コースID（"c1" など）→ {"star": bool}。押してあるコースだけ入る。
var practice_stamps: Dictionary = {}
## 初回起動の「はじめまして！ ハテナと れんしゅう する？」を出し終えたか。
var practice_intro_seen := false
## タッチ端末で、正解・ぶつかり・脱落などの手応えを短い振動で返す（設定画面でオン／オフ）。
var haptics_enabled: bool = true
## タッチ操作のボタンの大きさ（1.0 が標準）。設定画面で 0.8〜1.3 から選ぶ。
var touch_controls_scale: float = 1.0
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
	Engine.max_fps = effective_max_fps()
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


## 設定画面の「FPS上限」。available_max_fps_choices() にない値は既定値として扱う。
func set_max_fps(value: int) -> void:
	var normalized := normalize_max_fps(value)
	Engine.max_fps = normalized
	if max_fps == normalized and max_fps_chosen:
		return
	max_fps = normalized
	max_fps_chosen = true
	_save_user_settings()


static func normalize_max_fps(value: int) -> int:
	return value if available_max_fps_choices().has(value) else DEFAULT_MAX_FPS


## The saved value is kept as chosen (a desktop 144 must survive a phone-sized
## preview session); only the cap handed to the engine follows this platform.
func effective_max_fps() -> int:
	return normalize_max_fps(max_fps)


## 設定画面の「FPS上限」に並べる値。デスクトップは MAX_FPS_CHOICES、モバイルは MOBILE_MAX_FPS_CHOICES。
static func available_max_fps_choices() -> Array[int]:
	return MOBILE_MAX_FPS_CHOICES if GraphicsQuality.is_mobile_target() else MAX_FPS_CHOICES


func set_online_name(value: String) -> void:
	if online_name == value:
		return
	online_name = value
	_save_user_settings()


func set_online_nickname(value: int) -> void:
	if online_nickname == value:
		return
	online_nickname = value
	_save_user_settings()


## 設定画面の「オンラインの えんしゅつ」（ふつう／みじかい）。
func set_online_staging_short(value: bool) -> void:
	if online_staging_short == value:
		return
	online_staging_short = value
	_save_user_settings()


func set_haptics_enabled(value: bool) -> void:
	if haptics_enabled == value:
		return
	haptics_enabled = value
	_save_user_settings()


func set_touch_controls_scale(value: float) -> void:
	var clamped := clampf(value, 0.8, 1.3)
	if is_equal_approx(touch_controls_scale, clamped):
		return
	touch_controls_scale = clamped
	_save_user_settings()


## 設定画面のサドンデスのオン／オフ。保存し、進行中のゲーム状態にもすぐ反映する。
func set_sudden_death_enabled(value: bool) -> void:
	var changed := sudden_death_enabled != value
	sudden_death_enabled = value
	_push_sudden_death_setting()
	if changed:
		_save_user_settings()


func has_practice_stamp(course_id: String) -> bool:
	return practice_stamps.has(course_id)


func practice_stamp_star(course_id: String) -> bool:
	var stamp: Variant = practice_stamps.get(course_id)
	return stamp is Dictionary and bool((stamp as Dictionary).get("star", false))


## コースのスタンプを押して保存する。★は一度付いたら消さない。
func mark_practice_stamp(course_id: String, star: bool) -> void:
	if course_id.is_empty():
		return
	var next_star := star or practice_stamp_star(course_id)
	if has_practice_stamp(course_id) and practice_stamp_star(course_id) == next_star:
		return
	practice_stamps[course_id] = {"star": next_star}
	_save_user_settings()


## 初回の案内を出したことを保存する（［する］でも［あとで］でも呼ぶ）。
func mark_practice_intro_seen() -> void:
	if practice_intro_seen:
		return
	practice_intro_seen = true
	_save_user_settings()


## 設定ファイルのスタンプを読む。形の崩れた項目は捨て、{"star": bool} だけにそろえる。
static func _parse_practice_stamps(source: Variant) -> Dictionary:
	var stamps := {}
	if not source is Dictionary:
		return stamps
	for key: Variant in (source as Dictionary).keys():
		var entry: Variant = (source as Dictionary)[key]
		if entry is Dictionary and not str(key).is_empty():
			stamps[str(key)] = {"star": bool((entry as Dictionary).get("star", false))}
	return stamps


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
	max_fps_chosen = bool(_user_settings.get("max_fps_chosen", false))
	max_fps = DEFAULT_MAX_FPS
	if max_fps_chosen:
		var saved_fps := int(_user_settings.get("max_fps", DEFAULT_MAX_FPS))
		var known := MAX_FPS_CHOICES.has(saved_fps) or MOBILE_MAX_FPS_CHOICES.has(saved_fps)
		max_fps = saved_fps if known else DEFAULT_MAX_FPS
	sudden_death_enabled = bool(_user_settings.get("sudden_death_enabled", true))
	online_staging_short = bool(_user_settings.get("online_staging_short", false))
	online_nickname = int(_user_settings.get("online_nickname", -1))
	online_name = str(_user_settings.get("online_name", ""))
	practice_stamps = _parse_practice_stamps(_user_settings.get("practice_stamps", {}))
	practice_intro_seen = bool(_user_settings.get("practice_intro_seen", false))
	haptics_enabled = bool(_user_settings.get("haptics_enabled", true))
	touch_controls_scale = clampf(float(_user_settings.get("touch_controls_scale", 1.0)), 0.8, 1.3)

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
	_user_settings["max_fps"] = max_fps
	_user_settings["max_fps_chosen"] = max_fps_chosen
	_user_settings["sudden_death_enabled"] = sudden_death_enabled
	_user_settings["online_staging_short"] = online_staging_short
	_user_settings["online_nickname"] = online_nickname
	_user_settings["online_name"] = online_name
	_user_settings["practice_stamps"] = practice_stamps.duplicate(true)
	_user_settings["practice_intro_seen"] = practice_intro_seen
	_user_settings["haptics_enabled"] = haptics_enabled
	_user_settings["touch_controls_scale"] = touch_controls_scale
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_user_settings, "  "))
		file.close()

func _load_env() -> void:
	# .envファイルの簡易パース
	# エクスポートビルド: exe と同じフォルダの .env を優先（Android/iOS では探さない）
	# エディター実行: res://.env、無ければ res://config/app_env.cfg にフォールバック（env_file.gd）
	var env_path := EnvFile.resolve_path()

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
