extends RefCounted
class_name QuizGameState

const DuoTutorialFlowScript = preload("res://scripts/core/tutorial/duo_tutorial_flow.gd")
const SoloTutorialFlowScript = preload("res://scripts/core/tutorial/solo_tutorial_flow.gd")

## ゲーム状態管理クラス
## Python版 game_state.py の QuizGameState (638行) を移植

signal state_changed(new_state: String)
signal quiz_loaded(quiz: QuizItem)
signal correct_answer
signal wrong_answer(message: String)
signal game_cleared(message: String)
signal player_entered_ocean(player_index: int, local_position: Vector3)
signal player_scrolled_out(player_index: int)
signal tutorial_presentation_requested(presentation_id: String, context: Dictionary)
signal tutorial_presentation_finished(presentation_id: String)
signal tutorial_task_completed(player_index: int, task_id: String)
signal tutorial_customize_handoff_requested

var provider: QuizProvider
var use_english_ui: bool = false
var tuning: GameTuning

# --- Settings ---
var subject: String = "算数"
var grade: int = 3
var difficulty: String = "普通"
var mode: String = Constants.MODE_TEN
var llm_mode: String = "ONLINE"
var menu_step: String = Constants.MENU_STEP_MODE

# --- Pre-Tutorial State Backup ---
var pre_tutorial_subject: String = "算数"
var pre_tutorial_grade: int = 3
var pre_tutorial_difficulty: String = "普通"
var pre_tutorial_mode: String = Constants.MODE_TEN
var pre_tutorial_llm_mode: String = "ONLINE"
var pre_tutorial_num_players: int = 1
var _tutorial_backup_valid: bool = false

# --- Tutorial ---
## 海に落ちてサメに襲われた後、安全な位置へ戻すまでに見せる演出の長さ。
## 壁への激突（WALL_DEATH_SEQUENCE_DURATION）より短くして間延びを避ける。
const TUTORIAL_OCEAN_RECOVERY_DURATION := 2.4

var tutorial_ui_revision: int = 0
## 1Pは SoloTutorialFlow、ローカル2Pは DuoTutorialFlow。同じメソッド面を持つ。
var tutorial_flow: RefCounted = null
## 死亡演出やミスからの復帰先。クイズ中は現在の壁の手前、それ以外はステップ開始位置。
var _tutorial_safe_z: float = 0.0
## 1Pの実践終了後、メニュー内カスタマイズツアーへ引き継ぐセッション内フラグ。
var _pending_solo_customize_tour: bool = false

# --- Player 1 ---
var score: int = 0
var current_index: int = 0
var quiz_list: Array[QuizItem] = []
var current_quiz: QuizItem = null

var game_state: String = Constants.STATE_MENU
var choice_locked: bool = false
var message_timer: float = 0.0

var player_x: float = 0.0
var player_y: float = 0.0
var player_z: float = 0.0
var player_vel_y: float = 0.0
var player_vel_z: float = 0.0
var world_scroll_z: float = 0.0
var current_wall_index: int = 0

var message_text: String = ""
var status_text: String = ""
var game_over_timer: float = 0.0
var game_over_base_msg: String = ""

var correct_flash: float = 0.0
var wrong_flash: float = 0.0
var camera_shake: float = 0.0
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var preload_wait_sec: float = 0.0
var min_preload_sec: float = 0.35
var target_count: int = 10
var sfx_volume: float = 1.0
var bgm_volume: float = 0.5
var recent_results: Array[bool] = []
var rating_target_quiz: QuizItem = null
var rating_feedback: String = ""

# --- Streak & Stats ---
var current_streak: int = 0
var max_streak: int = 0
var play_time: float = 0.0
var total_answered: int = 0
var total_wrong: int = 0

# --- 案3: 回答時間計測 ---
var _quiz_shown_time: float = 0.0  # 問題表示時刻 (Time.get_ticks_msec())
var recent_response_times: Array[float] = [] # 直近の回答時間履歴 (パフォーマンス連動速度用)

# --- Quiz History (for game-over review) ---
var quiz_history: Array[Dictionary] = []  # [{quiz: QuizItem, correct: bool, rated: String}]
var countdown_timer: float = 3.0

# --- Flyover (10問モードのカメラ演出) ---
var flyover_timer: float = 0.0
var flyover_duration: float = 3.8  # フライオーバー全体の秒数 (ドリーインのみ)
var flyover_total_walls: int = 10

# --- Multiplayer ---
var num_players: int = 1
var p1_alive: bool = true
var p1_wall_impact: bool = false
## 地面にいるプレイヤーが有効な床を外れたら、リセットまで落下を確定する。
## 入力で床範囲へ戻っても空中から再接地させないための履歴フラグ。
var p1_fall_committed: bool = false
var p1_waiting_for_shark: bool = false
var p1_shark_killed: bool = false
var p1_ocean_float_time: float = 0.0
var p1_ocean_local_z: float = 0.0
var p1_emote: int = 0

var player2_x: float = 0.0
var player2_y: float = 0.0
var player2_z: float = 0.0
var player2_score: int = 0
var player2_vel_y: float = 0.0
var player2_vel_z: float = 0.0
var p2_alive: bool = true
var p2_wall_impact: bool = false
var p2_fall_committed: bool = false
var p2_waiting_for_shark: bool = false
var p2_shark_killed: bool = false
var p2_ocean_float_time: float = 0.0
var p2_ocean_local_z: float = 0.0
var p2_emote: int = 0
var p1_moving_back: bool = false
var p2_moving_back: bool = false
var p1_external_velocity: Vector2 = Vector2.ZERO
var p2_external_velocity: Vector2 = Vector2.ZERO
var p1_external_control_lock: float = 0.0
var p2_external_control_lock: float = 0.0
## 走行FBXの speed_scale 倍率（メニュープレビュー前進時など）
var p1_run_anim_speed_mult: float = 1.0
var p2_run_anim_speed_mult: float = 1.0
var p1_emote_lock_timer: float = 0.0
var p2_emote_lock_timer: float = 0.0
var p1_hat: int = 0
var p2_hat: int = 0
var p1_emote_selected: int = 0  # メニューで選択したデフォルトエモートID
var p2_emote_selected: int = 0
# エモートスロット: P1はキー1,2,3 / P2はキー8,9,0 にそれぞれエモートIDを割り当て
var p1_emote_slots: Array[int] = [1, 5, 13]  # Step Hip Hop, Moonwalk, YMCA
var p2_emote_slots: Array[int] = [2, 8, 17]  # Gangnam, Swing, Running Man

var player2_game_over_timer: float = 0.0

# --- Goal Race (2P 10問モード) ---
var goal_z: float = 0.0
var goal_winner: int = 0  # 0=未確定, 1=P1, 2=P2

var p1_jump_trigger: bool = false
var p2_jump_trigger: bool = false

# --- Dynamic wall speed ---
var _active_wall_speed: float = 6.0

# --- Physics Constants ---
const GRAVITY: float = 18.0
const JUMP_FORCE: float = 7.0
const FLOOR_HALF_WIDTH: float = 12.0
const FLOOR_BACK_Z: float = -12.5
const FLOOR_PLAY_FRONT_Z: float = 139.5
const FLOOR_RACE_FRONT_Z: float = 400.0
const SCROLL_OUT_LIMIT: float = 14.0
const PLAYER_BODY_RADIUS: float = 0.62
const PLAYER_BODY_HEIGHT: float = 1.9
const PLAYER_BODY_COLLISION_EPSILON: float = 0.0001
const EXTERNAL_IMPULSE_DECELERATION: float = 10.0
const WALL_RAGDOLL_DURATION: float = 2.0
const WALL_LIMB_SCATTER_DURATION: float = 2.0
const WALL_DEATH_SEQUENCE_DURATION: float = WALL_RAGDOLL_DURATION + WALL_LIMB_SCATTER_DURATION


func _init(quiz_provider: QuizProvider = null) -> void:
	if quiz_provider:
		provider = quiz_provider
	else:
		provider = QuizProvider.new()
	tuning = GameTuning.new()
	_install_tutorial_flow(GameManager.TUTORIAL_COURSE_SOLO)
	refresh_status_text()


## コースに対応したフロー実装へ差し替える。1Pと2Pは別クラスだが、
## QuizGameState からは同じメソッド面で呼ばれる。
func _install_tutorial_flow(selected_course: String) -> void:
	var wants_duo := selected_course == GameManager.TUTORIAL_COURSE_LOCAL_2P
	if tutorial_flow != null:
		var already_duo: bool = tutorial_flow.get_script() == DuoTutorialFlowScript
		if already_duo == wants_duo:
			return
		tutorial_flow.presentation_requested.disconnect(_on_tutorial_presentation_requested)
		tutorial_flow.presentation_finished.disconnect(_on_tutorial_presentation_finished)
		tutorial_flow.task_completed.disconnect(_on_tutorial_task_completed)
	if wants_duo:
		tutorial_flow = DuoTutorialFlowScript.new()
	else:
		tutorial_flow = SoloTutorialFlowScript.new()
	tutorial_flow.presentation_requested.connect(_on_tutorial_presentation_requested)
	tutorial_flow.presentation_finished.connect(_on_tutorial_presentation_finished)
	tutorial_flow.task_completed.connect(_on_tutorial_task_completed)


# ---------- Properties ----------

func is_coop_mode() -> bool:
	return mode == Constants.MODE_COOP

var num_choices: int:
	get:
		if is_coop_mode():
			return 2  # Coop uses 2 doors per player (4 total, but 2+2 split)
		if difficulty == "難しい":
			if current_quiz and current_quiz.c.size() < 4:
				return current_quiz.c.size()
			return 4
		return 2

var wall_z: float:
	get:
		return tuning.wall_start_z + current_wall_index * tuning.wall_spacing

var player_local_z: float:
	get:
		return player_z - world_scroll_z

var player2_local_z: float:
	get:
		return player2_z - world_scroll_z

func _is_fixed_count_mode() -> bool:
	return mode == Constants.MODE_TEN or mode == Constants.MODE_COOP or mode == Constants.MODE_TUTORIAL

func _is_tutorial_mode() -> bool:
	return mode == Constants.MODE_TUTORIAL

func is_solo_tutorial() -> bool:
	return (
		_is_tutorial_mode()
		and tutorial_flow != null
		and tutorial_flow.get_script() == SoloTutorialFlowScript
	)


func is_duo_tutorial() -> bool:
	return (
		_is_tutorial_mode()
		and tutorial_flow != null
		and tutorial_flow.get_script() == DuoTutorialFlowScript
	)


## 脱落したプレイヤーがゴーストシャークに乗れる状況か。
## チュートリアル中は指定ステップだけ許可し、それ以外は乗せない。
func allows_tutorial_ghost_ride() -> bool:
	if not _is_tutorial_mode():
		return true
	return tutorial_flow != null and tutorial_flow.allows_ghost_ride()


## 2人が意図的に離れるステップでは、待機側が画面外へ切れないようカメラを引く。
func tutorial_splits_camera() -> bool:
	return (
		_is_tutorial_mode()
		and tutorial_flow != null
		and tutorial_flow.splits_camera_for_hazard()
	)


func get_tutorial_course() -> String:
	return tutorial_flow.course if tutorial_flow != null else GameManager.TUTORIAL_COURSE_SOLO


func get_tutorial_step_id() -> String:
	return tutorial_flow.current_step_id() if tutorial_flow != null else ""


func has_pending_solo_customize_tour() -> bool:
	return _pending_solo_customize_tour


func complete_solo_customize_tour() -> void:
	if not _pending_solo_customize_tour:
		return
	_pending_solo_customize_tour = false
	GameManager.mark_tutorial_course_completed(GameManager.TUTORIAL_COURSE_SOLO)
	tutorial_ui_revision += 1


func abort_solo_customize_tour() -> void:
	if not _pending_solo_customize_tour:
		return
	_pending_solo_customize_tour = false
	tutorial_ui_revision += 1


## 誘導されたステップでは片方だけが前進するので、通常の2P分断ルールを止める。
func is_scroll_out_death_enabled() -> bool:
	return not (
		_is_tutorial_mode()
		and tutorial_flow != null
		and tutorial_flow.blocks_scroll_out_death()
	)


func get_tutorial_overlay_model() -> Dictionary:
	if not _is_tutorial_mode() or tutorial_flow == null:
		return {"visible": false}
	return tutorial_flow.get_overlay_model()


func is_tutorial_presentation_locked() -> bool:
	return _is_tutorial_mode() and tutorial_flow != null and tutorial_flow.presentation_locked


func is_tutorial_ghost_practice() -> bool:
	return _is_tutorial_mode() and tutorial_flow != null and tutorial_flow.is_ghost_practice()


func get_tutorial_ghost_player() -> int:
	return tutorial_flow.designated_ghost_player() if is_tutorial_ghost_practice() else 0


func get_tutorial_wall_count() -> int:
	if not _is_tutorial_mode() or tutorial_flow == null:
		return target_count
	return tutorial_flow.wall_count()


## 現在のステップで壁を出さないなら true。空の走路で操作だけを教えたいときに使う。
func are_tutorial_walls_hidden() -> bool:
	return _is_tutorial_mode() and tutorial_flow != null and tutorial_flow.walls_hidden()


func complete_tutorial_presentation(presentation_id: String = "") -> void:
	if not _is_tutorial_mode() or tutorial_flow == null:
		return
	var auto_advance: bool = tutorial_flow.current_step_advances_after_presentation()
	if not tutorial_flow.finish_presentation(presentation_id):
		return
	tutorial_ui_revision += 1
	if auto_advance:
		_advance_tutorial_step()
		return
	if tutorial_flow.is_final_step() and tutorial_flow.should_clear_after_presentation():
		clear_game()


func register_tutorial_ghost_aim(player_index: int) -> void:
	if not is_tutorial_ghost_practice() or player_index != get_tutorial_ghost_player():
		return
	tutorial_flow.complete_task(player_index, "aim")


func register_tutorial_ghost_charge(player_index: int, hit: bool, _power: float) -> bool:
	if not is_tutorial_ghost_practice() or player_index != get_tutorial_ghost_player():
		return false
	tutorial_flow.complete_task(player_index, "charge")
	if hit:
		tutorial_flow.complete_task(player_index, "hit")
	return tutorial_flow.all_tasks_complete()


## ゴーストシャーク練習を終えた後の後片付け。脱落していたプレイヤーを復活させ、
## 次のステップ（クイズなら問題の用意まで）へ進める。
func finish_tutorial_ghost_step() -> void:
	if not is_tutorial_ghost_practice() or not tutorial_flow.all_tasks_complete():
		return
	_reset_tutorial_players_for_step(false)
	if not tutorial_flow.advance_step():
		return
	tutorial_ui_revision += 1
	game_state = Constants.STATE_PLAYING
	if tutorial_flow.is_quiz_step():
		_prepare_tutorial_quiz_step()
	message_text = ""
	choice_locked = false
	refresh_status_text()
	state_changed.emit(game_state)


func _on_tutorial_presentation_requested(presentation_id: String, context: Dictionary) -> void:
	tutorial_presentation_requested.emit(presentation_id, context)


func _on_tutorial_presentation_finished(presentation_id: String) -> void:
	tutorial_presentation_finished.emit(presentation_id)


func _on_tutorial_task_completed(player_index: int, task_id: String) -> void:
	tutorial_ui_revision += 1
	tutorial_task_completed.emit(player_index, task_id)

func _provider_mode() -> String:
	return Constants.MODE_TEN if is_coop_mode() else mode

func _is_on_track_floor(x_pos: float, local_z: float, player_num: int, front_z: float = -1.0) -> bool:
	if local_z < FLOOR_BACK_Z:
		return false
	if front_z > 0.0 and local_z > front_z:
		return false
	if absf(x_pos) > FLOOR_HALF_WIDTH:
		return false
	if is_coop_mode():
		if player_num == 1:
			return x_pos >= tuning.coop_lane_gap_half_width
		if player_num == 2:
			return x_pos <= -tuning.coop_lane_gap_half_width
	return true


## 床を外れた後の落下を不可逆にする。ジャンプ中（y > 0）は確定させないので、
## 正規のジャンプで縁を越えて床へ戻る動きは維持する。
func _commit_fall_if_unsupported(
	player_num: int,
	x_pos: float,
	y_pos: float,
	local_z: float,
	front_z: float = -1.0
) -> bool:
	var already_committed := p1_fall_committed if player_num == 1 else p2_fall_committed
	if already_committed:
		return true
	if y_pos > 0.0 or _is_on_track_floor(x_pos, local_z, player_num, front_z):
		return false
	if player_num == 1:
		p1_fall_committed = true
	else:
		p2_fall_committed = true
	return true


# ---------- Menu ----------

func select_mode_and_continue(selected_mode: String) -> void:
	if selected_mode in [Constants.MODE_TEN, Constants.MODE_ENDLESS, Constants.MODE_COOP]:
		mode = selected_mode
	menu_step = Constants.MENU_STEP_CONFIG
	refresh_status_text()

func back_to_mode_select() -> void:
	menu_step = Constants.MENU_STEP_MODE
	refresh_status_text()

func open_settings() -> void:
	menu_step = Constants.MENU_STEP_SETTINGS
	refresh_status_text()

func back_from_settings() -> void:
	menu_step = Constants.MENU_STEP_MODE
	refresh_status_text()

# set_wall_speed() は廃止。壁速度はAI予測解答時間から自動算出される。

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	AudioManager.set_sfx_volume(sfx_volume)

func set_bgm_volume(vol: float) -> void:
	bgm_volume = clampf(vol, 0.0, 1.0)
	AudioManager.set_bgm_volume(bgm_volume)

func update_grade(delta: int) -> void:
	grade = clampi(grade + delta, 1, 6)
	refresh_status_text()

func cycle_subject(delta: int) -> void:
	var idx := Constants.SUBJECTS.find(subject)
	if idx < 0:
		idx = 0
	subject = Constants.SUBJECTS[(idx + delta) % Constants.SUBJECTS.size()]
	refresh_status_text()

func cycle_difficulty(delta: int) -> void:
	var idx := Constants.DIFFICULTY_LEVELS.find(difficulty)
	if idx < 0:
		idx = 1
	difficulty = Constants.DIFFICULTY_LEVELS[(idx + delta) % Constants.DIFFICULTY_LEVELS.size()]
	refresh_status_text()




# ---------- Game lifecycle ----------

func start_game() -> void:
	_reset_ocean_shark_state()
	_reset_external_impulses()
	if is_coop_mode():
		num_players = 2
	score = 0
	current_index = 0
	quiz_history.clear()
	player_x = 6.0 if is_coop_mode() else (1.5 if num_players == 2 else 0.0)
	player_y = 0.0
	player_z = -8.0 if num_players == 1 else 0.0
	player_vel_y = 0.0
	player_vel_z = 0.0
	world_scroll_z = 0.0
	camera_yaw = 0.0
	camera_pitch = 0.0
	current_wall_index = 0
	game_over_timer = 0.0
	p1_alive = true
	p1_wall_impact = false
	p1_fall_committed = false
	p1_emote_lock_timer = 0.0
	# Player 2 reset
	player2_x = -6.0 if is_coop_mode() else -1.5
	player2_y = 0.0
	player2_z = 0.0
	player2_score = 0
	player2_vel_y = 0.0
	player2_vel_z = 0.0
	p2_alive = true
	p2_wall_impact = false
	p2_fall_committed = false
	p2_emote_lock_timer = 0.0
	player2_game_over_timer = 0.0
	goal_winner = 0

	# Streak & stats reset
	current_streak = 0
	max_streak = 0
	play_time = 0.0
	total_answered = 0
	total_wrong = 0
	recent_response_times.clear()
	# Dynamic wall speed reset（手動オーバーライドがあればそれを使用）
	if tuning.wall_speed_override > 0:
		_active_wall_speed = tuning.wall_speed_override
	else:
		_active_wall_speed = 28.0 / (4.0 + 3.5)  # VISIBLE_DISTANCE / (default_est + buffer)
	var count: int = 10 if _is_fixed_count_mode() else 1
	target_count = count

	var provider_mode := _provider_mode()
	provider.begin_round(subject, grade, difficulty, provider_mode, count)

	# オンライン時は AI 応答を待つ（緊急オフラインキャッシュで先埋めしない）
	quiz_list.clear()
	_prepare_coop_quiz_list()
	message_text = ""
	game_state = Constants.STATE_PRELOADING
	preload_wait_sec = 0.0
	refresh_status_text()
	state_changed.emit(game_state)

func _prepare_coop_quiz_list() -> void:
	if not is_coop_mode():
		return
	for i: int in range(quiz_list.size()):
		var quiz := quiz_list[i]
		if quiz and _should_rebuild_coop_quiz(quiz):
			var coop_quiz := CoopQuizBuilder.build_coop_quiz(quiz, subject, grade, i)
			if coop_quiz:
				quiz_list[i] = coop_quiz

func _should_rebuild_coop_quiz(quiz: QuizItem) -> bool:
	if not quiz:
		return false
	if not quiz.has_coop_data():
		return true
	return quiz.coop_p1_label.contains("解答セット") \
		or quiz.coop_p2_label.contains("解答セット") \
		or quiz.coop_p1_label.contains("ヒント") \
		or quiz.coop_p2_label.contains("ヒント")

func start_tutorial(course: String = GameManager.TUTORIAL_COURSE_SOLO) -> void:
	_reset_ocean_shark_state()
	_reset_external_impulses()
	_pending_solo_customize_tour = false
	if not _tutorial_backup_valid:
		pre_tutorial_subject = subject
		pre_tutorial_grade = grade
		pre_tutorial_difficulty = difficulty
		pre_tutorial_mode = mode
		pre_tutorial_llm_mode = llm_mode
		pre_tutorial_num_players = num_players
		_tutorial_backup_valid = true

	mode = Constants.MODE_TUTORIAL
	llm_mode = "OFFLINE"
	subject = "チュートリアル"
	grade = 3
	difficulty = "普通"
	var selected_course: String = (
		GameManager.TUTORIAL_COURSE_LOCAL_2P
		if course == GameManager.TUTORIAL_COURSE_LOCAL_2P
		else GameManager.TUTORIAL_COURSE_SOLO
	)
	_install_tutorial_flow(selected_course)
	num_players = 2 if selected_course == GameManager.TUTORIAL_COURSE_LOCAL_2P else 1
	score = 0
	current_index = 0
	quiz_history.clear()
	player_x = 1.5 if num_players >= 2 else 0.0
	player_y = 0.0
	player_z = -8.0 if num_players == 1 else 0.0
	player_vel_y = 0.0
	player_vel_z = 0.0
	world_scroll_z = 0.0
	camera_yaw = 0.0
	camera_pitch = 0.0
	current_wall_index = 0
	game_over_timer = 0.0
	p1_alive = true
	p1_wall_impact = false
	p1_fall_committed = false
	player2_x = -1.5 if num_players >= 2 else 0.0
	player2_y = 0.0
	player2_z = 0.0
	player2_score = 0
	player2_vel_y = 0.0
	player2_vel_z = 0.0
	p2_alive = num_players >= 2
	p2_wall_impact = false
	p2_fall_committed = false
	player2_game_over_timer = 0.0
	goal_winner = 0
	current_streak = 0
	max_streak = 0
	play_time = 0.0
	total_answered = 0
	total_wrong = 0
	recent_results.clear()
	recent_response_times.clear()
	rating_target_quiz = null
	rating_feedback = ""
	choice_locked = false
	message_text = ""
	status_text = ""
	_tutorial_safe_z = 0.0
	tutorial_ui_revision += 1
	tutorial_flow.start(selected_course)
	target_count = tutorial_flow.target_quiz_count()
	quiz_list = tutorial_flow.build_quiz_items()
	_active_wall_speed = 3.8
	game_state = Constants.STATE_WAITING_START
	load_current_quiz()
	refresh_status_text()
	state_changed.emit(game_state)


func restart_tutorial() -> void:
	var course := get_tutorial_course()
	start_tutorial(course)

func _advance_tutorial_step() -> void:
	if not _is_tutorial_mode() or tutorial_flow == null:
		return
	var previous_was_quiz: bool = tutorial_flow.is_quiz_step()
	if not tutorial_flow.advance_step():
		return
	tutorial_ui_revision += 1
	if tutorial_flow.starts_customize_tour():
		_begin_solo_customize_handoff()
		return
	if tutorial_flow.starts_goal_race():
		_start_goal_race()
		return
	# 完了ステップでは必ずゴールレースから抜ける。抜けないと完了演出の裏で
	# ゴール判定と物理が動き続けてしまう。
	game_state = Constants.STATE_PLAYING
	if tutorial_flow.is_final_step():
		choice_locked = true
		current_quiz = null
		_tutorial_safe_z = world_scroll_z
		message_text = "コース完了！"
		refresh_status_text()
		state_changed.emit(game_state)
		return
	if tutorial_flow.is_quiz_step():
		_prepare_tutorial_quiz_step(not previous_was_quiz)
	else:
		current_quiz = null
		_tutorial_safe_z = world_scroll_z
	choice_locked = false
	message_text = ""
	refresh_status_text()
	state_changed.emit(game_state)


func _begin_solo_customize_handoff() -> void:
	if not is_solo_tutorial() or not tutorial_flow.starts_customize_tour():
		return
	_pending_solo_customize_tour = true
	reset_to_menu()
	tutorial_customize_handoff_requested.emit()


## 座標・生死・演出タイマーをステップ開始状態へ戻す。1Pと2Pの共通土台。
func _reset_tutorial_stage(reset_z: float) -> void:
	_reset_ocean_shark_state()
	_reset_external_impulses()
	world_scroll_z = reset_z
	player_x = 1.5 if num_players >= 2 else 0.0
	player_y = 0.0
	player_z = reset_z
	player_vel_y = 0.0
	player_vel_z = 0.0
	p1_alive = true
	p1_wall_impact = false
	p1_fall_committed = false
	game_over_timer = 0.0
	p1_emote = 0
	if num_players >= 2:
		player2_x = -1.5
		player2_y = 0.0
		player2_z = reset_z
		player2_vel_y = 0.0
		player2_vel_z = 0.0
		p2_alive = true
		p2_wall_impact = false
		p2_fall_committed = false
		player2_game_over_timer = 0.0
		p2_emote = 0
	else:
		p2_alive = false
	choice_locked = false
	_tutorial_safe_z = reset_z


## やり直しの戻り先。クイズ中は現在の壁の手前、それ以外はステップ開始位置が入っている。
func _tutorial_reset_z() -> float:
	return _tutorial_safe_z


func _reset_tutorial_players_at(reset_z: float) -> void:
	_reset_tutorial_stage(reset_z)
	camera_shake = 0.0


func _reset_tutorial_players_for_step(move_past_wall: bool = false) -> void:
	if move_past_wall:
		current_wall_index += 1
	_reset_tutorial_players_at(float(current_wall_index) * tuning.wall_spacing)


func _prepare_tutorial_quiz_step(reset_players: bool = true) -> void:
	var quiz_index: int = tutorial_flow.quiz_index() if tutorial_flow != null else current_index
	if quiz_index < 0:
		current_quiz = null
		return
	current_index = quiz_index
	if reset_players:
		current_wall_index = quiz_index
		_reset_tutorial_players_at(float(current_wall_index) * tuning.wall_spacing)
	_tutorial_safe_z = float(current_wall_index) * tuning.wall_spacing
	current_quiz = quiz_list[quiz_index] if quiz_index < quiz_list.size() else null
	if current_quiz:
		_quiz_shown_time = Time.get_ticks_msec()
		quiz_loaded.emit(current_quiz)


func _complete_tutorial_quiz_step() -> void:
	if not _is_tutorial_mode() or tutorial_flow == null or not tutorial_flow.is_quiz_step():
		return
	current_wall_index += 1
	current_index += 1
	current_quiz = null
	if p1_alive:
		game_over_timer = 0.0
	if p2_alive or num_players < 2:
		player2_game_over_timer = 0.0
	# 1問のステップと複数問のステップがある。残っているなら同じステップ内で次へ。
	if not tutorial_flow.on_quiz_cleared():
		_prepare_tutorial_quiz_step(false)
		tutorial_ui_revision += 1
		game_state = Constants.STATE_PLAYING
		choice_locked = false
		message_text = ""
		refresh_status_text()
		state_changed.emit(game_state)
		return
	_advance_tutorial_step()

func reset_to_menu() -> void:
	_reset_ocean_shark_state()
	_reset_external_impulses()
	provider.end_round()
	if mode == Constants.MODE_TUTORIAL:
		subject = pre_tutorial_subject
		grade = pre_tutorial_grade
		difficulty = pre_tutorial_difficulty
		mode = pre_tutorial_mode
		llm_mode = pre_tutorial_llm_mode
		num_players = pre_tutorial_num_players
		_tutorial_backup_valid = false

	game_state = Constants.STATE_MENU
	menu_step = Constants.MENU_STEP_MODE
	player_x = 0.0
	player_y = 0.0
	player_z = 0.0
	player_vel_y = 0.0
	player_vel_z = 0.0
	world_scroll_z = 0.0
	current_wall_index = 0
	message_text = ""
	correct_flash = 0.0
	wrong_flash = 0.0
	camera_shake = 0.0
	camera_yaw = 0.0
	camera_pitch = 0.0
	game_over_timer = 0.0
	p1_alive = true
	p1_wall_impact = false
	p1_fall_committed = false
	player2_x = 0.0
	player2_y = 0.0
	player2_z = 0.0
	player2_score = 0
	player2_vel_y = 0.0
	player2_vel_z = 0.0
	p2_alive = true
	p2_wall_impact = false
	p2_fall_committed = false
	p2_emote_lock_timer = 0.0
	player2_game_over_timer = 0.0
	rating_target_quiz = null
	rating_feedback = ""
	quiz_history.clear()
	refresh_status_text()
	state_changed.emit(game_state)


# ---------- Quiz loading ----------

func load_current_quiz() -> void:
	if _is_tutorial_mode() and current_index >= quiz_list.size():
		current_quiz = null
		choice_locked = false
		message_text = ""
		refresh_status_text()
		return
	if _is_fixed_count_mode():
		if current_index >= quiz_list.size():
			if current_index >= target_count:
				# チュートリアルは冒頭で早期returnするのでここには来ない。
				# 進行は _advance_tutorial_step が持つ。
				if num_players >= 2 and mode == Constants.MODE_TEN:
					_start_goal_race()
				else:
					clear_game()
				return
			else:
				# 途中でバッファが尽きた場合は再度プレロード待ちへ
				game_state = Constants.STATE_PRELOADING
				preload_wait_sec = 0.0
				message_text = "Loading quizzes..." if use_english_ui else "次の問題を準備中..."
				refresh_status_text()
				state_changed.emit(game_state)
				return
		current_quiz = quiz_list[current_index]
	else:
		if quiz_list.is_empty():
			# バッファから3問ずつ引き出し、ローカルキューに保持
			quiz_list = provider.get_quizzes(subject, grade, difficulty,
				Constants.MODE_ENDLESS, 3)
		# Guard: if buffer is still empty, transition to PRELOADING
		if quiz_list.is_empty():
			game_state = Constants.STATE_PRELOADING
			preload_wait_sec = 0.0
			message_text = "Loading quizzes..." if use_english_ui else "次の問題を準備中..."
			refresh_status_text()
			state_changed.emit(game_state)
			return
		current_quiz = quiz_list[0]

	# Handle 4-to-2 conversion for offline quizzes or any quiz with too many choices.
	# Coop keeps the original choices so each player can receive a different answer set.
	if not is_coop_mode() and num_choices == 2 and current_quiz.c.size() > 2:
		var correct_text: String = current_quiz.c[current_quiz.a]
		var wrong_texts: PackedStringArray = []
		for i: int in range(current_quiz.c.size()):
			if i != current_quiz.a:
				wrong_texts.append(current_quiz.c[i])

		# Pick one random wrong answer
		var chosen_wrong: String = wrong_texts[randi() % wrong_texts.size()]

		var new_c := PackedStringArray([correct_text, chosen_wrong])
		# Shuffle them
		if randf() > 0.5:
			new_c = PackedStringArray([chosen_wrong, correct_text])

		var new_a: int = 0 if new_c[0] == correct_text else 1

		current_quiz = QuizItem.create(
			current_quiz.q, new_c, new_a, current_quiz.e, current_quiz.src,
			current_quiz.img, current_quiz.choice_img
		)

	if is_coop_mode() and current_quiz and _should_rebuild_coop_quiz(current_quiz):
		current_quiz = CoopQuizBuilder.build_coop_quiz(current_quiz, subject, grade, current_index)
	if _is_fixed_count_mode() and current_index < quiz_list.size():
		quiz_list[current_index] = current_quiz
	elif not _is_fixed_count_mode() and quiz_list.size() > 0:
		quiz_list[0] = current_quiz

	choice_locked = false
	message_text = ""
	_recalc_wall_speed()
	# 案3: 問題表示時刻を記録
	_quiz_shown_time = Time.get_ticks_msec()
	refresh_status_text()
	quiz_loaded.emit(current_quiz)

func _recalc_wall_speed() -> void:
	## AI予測解答時間から壁速度を逆算する
	## speed = 可視距離 ÷ (予測秒数 + 移動バッファ)
	## + ステージ加速（緊張感演出）

	if _is_tutorial_mode():
		_active_wall_speed = 3.8
		return

	# --- 手動オーバーライドモード ---
	if tuning.wall_speed_override > 0:
		_active_wall_speed = tuning.wall_speed_override
		return

	# --- AI予測解答時間を取得 ---
	var est_sec: float = 4.0  # デフォルト
	if current_quiz:
		est_sec = current_quiz.estimated_seconds

	# --- 壁が見えてからプレイヤーに到達するまでの距離 ---
	const VISIBLE_DISTANCE: float = 28.0  # wall_start_z(22) - hit_z(-6)
	const MOVE_BUFFER: float = 3.5        # ドアまで移動する余白（秒）

	var target_time: float = est_sec + MOVE_BUFFER
	var base_speed: float = VISIBLE_DISTANCE / target_time

	# --- ステージ加速 ---
	var stage_factor: float = 1.0
	if _is_fixed_count_mode() and not _is_tutorial_mode():
		# 10問モード: 問題番号 0〜9 で 0%〜15% 加速
		var progress: float = clampf(float(current_index) / 9.0, 0.0, 1.0)
		stage_factor = 1.0 + progress * 0.15
	else:
		# エンドレスモード: 5問周期で微加速、最大+20%
		var cycle_pos: float = float(total_answered % 5) / 4.0
		stage_factor = 1.0 + minf(cycle_pos * 0.15, 0.20)

	var final_speed: float = base_speed * stage_factor
	_active_wall_speed = clampf(final_speed, tuning.wall_speed_min, tuning.wall_speed_max)


# ---------- Frame update ----------

func update(dt: float, axis_p1: Vector2 = Vector2.ZERO, axis_p2: Vector2 = Vector2.ZERO, jump_p1: bool = false, jump_p2: bool = false, emote_p1: int = 0, emote_p2: int = 0) -> void:
	correct_flash = maxf(0.0, correct_flash - dt * 1.5)
	wrong_flash = maxf(0.0, wrong_flash - dt * 1.2)
	camera_shake = maxf(0.0, camera_shake - dt * 2.8)

	if game_state == Constants.STATE_MENU:
		return
	if _is_tutorial_mode() and tutorial_flow != null:
		tutorial_flow.tick(dt)
		if tutorial_flow.consume_input_gate(
			axis_p1, axis_p2, jump_p1, jump_p2, emote_p1, emote_p2
		):
			# 演出ロック中と中立入力待ちは操作を止めるが、死亡演出だけは進め続ける。
			# ここで全部止めるとラグドールが空中で固まる。
			if not p1_alive and game_over_timer > 0.0:
				game_over_timer += dt
			if num_players >= 2 and not p2_alive and player2_game_over_timer > 0.0:
				player2_game_over_timer += dt
			_process_dead_player_physics(dt)
			_sink_ocean_players(dt)
			return

	p1_jump_trigger = false
	p2_jump_trigger = false

	# Emote logic: Loop until jump. Can move while emoting.
	if jump_p1:
		p1_emote = 0
	elif emote_p1 > 0 and p1_alive and player_vel_y == 0.0:
		p1_emote = emote_p1

	if jump_p2:
		p2_emote = 0
	elif emote_p2 > 0 and p2_alive and player2_vel_y == 0.0:
		p2_emote = emote_p2

	if game_state == Constants.STATE_PRELOADING:
		_update_preloading(dt)
		return

	if game_state == Constants.STATE_WAITING_START:
		_update_waiting_start(dt, axis_p1, axis_p2, jump_p1, jump_p2, emote_p1, emote_p2)
		return

	if game_state == Constants.STATE_FLYOVER:
		_update_flyover(dt, emote_p1, emote_p2)
		return

	if game_state == Constants.STATE_COUNTDOWN:
		_update_countdown(dt, emote_p1, emote_p2)
		return

	if game_state == Constants.STATE_PLAYING:
		_update_playing(dt, axis_p1, axis_p2, jump_p1, jump_p2, emote_p1, emote_p2)
		return

	if game_state == Constants.STATE_GOAL_RACE:
		_update_goal_race(dt, axis_p1, axis_p2, jump_p1, jump_p2, emote_p1, emote_p2)
		return

	if game_state == Constants.STATE_CORRECT:
		_update_correct(dt)
		return

	if game_state == Constants.STATE_GAME_OVER:
		_update_game_over(dt)
		return

func _update_preloading(dt: float) -> void:
	preload_wait_sec += dt
	var missing: int
	if _is_fixed_count_mode():
		missing = maxi(0, target_count - quiz_list.size())
	else:
		missing = 1
	if missing > 0:
		var new_quizzes := provider.get_quizzes(subject, grade, difficulty, _provider_mode(), missing)
		quiz_list.append_array(new_quizzes)
		_prepare_coop_quiz_list()

	var ready: bool = false
	# ゲーム開始前（current_index == 0）は全問揃うのを待つ
	# ゲーム中の再プレロード（current_index > 0）は次の1問があれば即再開
	var is_mid_game: bool = current_index > 0

	if is_mid_game:
		# 中盤プレロード: 次の問題が1つでもあればすぐ再開
		if quiz_list.size() > current_index:
			ready = true
	else:
		# 初期プレロード: 全問揃うのが理想
		if _is_fixed_count_mode() and quiz_list.size() >= target_count:
			ready = true
		elif mode == Constants.MODE_ENDLESS and quiz_list.size() >= 1:
			ready = true

	if ready and preload_wait_sec >= min_preload_sec:
		print("[GameState] Preload complete: %d quizzes in %.1fs (mid_game=%s)" % [quiz_list.size(), preload_wait_sec, str(is_mid_game)])
		if is_mid_game:
			# 中盤: PLAYINGに復帰して次の問題を表示
			game_state = Constants.STATE_PLAYING
			load_current_quiz()
			state_changed.emit(game_state)
		else:
			game_state = Constants.STATE_WAITING_START
			load_current_quiz()
			state_changed.emit(game_state)
	elif not ready and preload_wait_sec >= 2.5 and not _is_fixed_count_mode() and quiz_list.size() > current_index:
		# タイムアウト: エンドレス等では全問揃わなくても一部があれば開始（2.5秒で打ち切り）
		print("[GameState] Preload timeout (%.1fs): starting with %d/%d quizzes" % [preload_wait_sec, quiz_list.size(), target_count])
		if is_mid_game:
			game_state = Constants.STATE_PLAYING
			load_current_quiz()
			state_changed.emit(game_state)
		else:
			game_state = Constants.STATE_WAITING_START
			load_current_quiz()
			state_changed.emit(game_state)
	else:
		if is_mid_game:
			message_text = "Loading quizzes..." if use_english_ui else "次の問題を準備中..."
		else:
			if _is_fixed_count_mode():
				var q_count = mini(quiz_list.size(), target_count)
				message_text = "Generating quizzes... (%d/%d)" % [q_count, target_count] if use_english_ui else "AIクイズ生成中... (%d/%d)" % [q_count, target_count]
			else:
				message_text = "Loading quizzes..." if use_english_ui else "クイズを準備中..."
		refresh_status_text()

func _update_waiting_start(dt: float, axis_p1: Vector2, axis_p2: Vector2, jump_p1: bool, jump_p2: bool, emote_p1: int = 0, emote_p2: int = 0) -> void:
	pass
func trigger_start() -> void:
	if game_state == Constants.STATE_WAITING_START:
		if _is_tutorial_mode():
			# Tutorials begin with their first instruction instead of the normal
			# challenge-mode course flyover.
			game_state = Constants.STATE_COUNTDOWN
			countdown_timer = 3.0
			state_changed.emit(game_state)
			return
		game_state = Constants.STATE_FLYOVER
		flyover_timer = 0.0

		if _is_fixed_count_mode():
			# 10問 / チュートリアル: 全壁を見せる
			flyover_total_walls = maxi(target_count, 1)
			flyover_duration = 3.8
		else:
			# エンドレスモード: 見えなくなるくらい遠くまで壁を並べる
			flyover_total_walls = 25
			flyover_duration = 3.8
		state_changed.emit(game_state)

func _update_flyover(dt: float, emote_p1: int = 0, emote_p2: int = 0) -> void:
	flyover_timer += dt
	if flyover_timer >= flyover_duration:
		# フライオーバー完了 → カウントダウンへ
		game_state = Constants.STATE_COUNTDOWN
		countdown_timer = 3.99
		state_changed.emit(game_state)

func _update_countdown(dt: float, emote_p1: int = 0, emote_p2: int = 0) -> void:
	countdown_timer -= dt
	if countdown_timer <= 0:
		game_state = Constants.STATE_PLAYING
		_begin_tutorial_gameplay_after_countdown()
		state_changed.emit(game_state)


## 本編と同じ開始演出の直後から操作練習に入れるよう、導入ステップを飛ばす。
func _begin_tutorial_gameplay_after_countdown() -> void:
	if not _is_tutorial_mode() or tutorial_flow == null:
		return
	if tutorial_flow.advances_after_countdown():
		tutorial_flow.advance_step()
		tutorial_ui_revision += 1
	message_text = ""


func _update_playing(dt: float, axis_p1: Vector2, axis_p2: Vector2, jump_p1: bool, jump_p2: bool, _emote_p1: int = 0, _emote_p2: int = 0) -> void:
	play_time += dt
	var p1_axis := Vector2.ZERO if p1_external_control_lock > 0.0 else axis_p1
	var p2_axis := Vector2.ZERO if p2_external_control_lock > 0.0 else axis_p2
	var p1_jump_allowed := jump_p1 and p1_external_control_lock <= 0.0
	var p2_jump_allowed := jump_p2 and p2_external_control_lock <= 0.0
	p1_external_control_lock = maxf(0.0, p1_external_control_lock - dt)
	p2_external_control_lock = maxf(0.0, p2_external_control_lock - dt)
	if (
		_is_tutorial_mode()
		and tutorial_flow != null
		and tutorial_flow.is_input_practice_step()
		and tutorial_flow.update_input_practice(
			axis_p1, axis_p2, jump_p1, jump_p2, _emote_p1, _emote_p2, dt
		)
	):
		if tutorial_flow.is_final_step():
			clear_game()
			return
		if tutorial_flow.resets_players_on_advance():
			_reset_tutorial_players_for_step(false)
		_advance_tutorial_step()
		return
	if _update_tutorial_special_step(dt):
		return
	var world_speed := _active_wall_speed
	if _is_tutorial_mode() and tutorial_flow != null:
		world_speed *= tutorial_flow.world_speed_scale()
	if is_tutorial_ghost_practice():
		var ghost_player: int = get_tutorial_ghost_player()
		if ghost_player == 1:
			p2_axis = Vector2.ZERO
			p2_jump_allowed = false
		else:
			p1_axis = Vector2.ZERO
			p1_jump_allowed = false
	world_scroll_z += world_speed * dt
	var p1_body_start := Vector2(player_x, player_z)
	var p2_body_start := Vector2(player2_x, player2_z)

	p1_moving_back = p1_axis.y < -0.1
	p2_moving_back = p2_axis.y < -0.1

	# Player 1 movement
	if p1_alive and not p1_waiting_for_shark:
		# 入力を適用する前にも確認し、前フレームで崖を越えたプレイヤーが
		# 1フレームの横移動だけで床範囲へ戻る抜け道を塞ぐ。
		_commit_fall_if_unsupported(1, player_x, player_y, player_z - world_scroll_z)
		var yaw: float = 0.0
		var move_x: float = p1_axis.x * cos(yaw) + p1_axis.y * sin(yaw)
		var move_z: float = p1_axis.y * cos(yaw) - p1_axis.x * sin(yaw)

		player_x += move_x * tuning.player_speed * dt
		# Removed clamp to allow falling off sides

		player_z += world_speed * dt # Carry forward with world scroll
		player_z += move_z * tuning.player_speed * dt
		player_x += p1_external_velocity.x * dt
		player_z += p1_external_velocity.y * dt
		p1_external_velocity = p1_external_velocity.move_toward(Vector2.ZERO, EXTERNAL_IMPULSE_DECELERATION * dt)

		# Removed forward limit to allow running ahead
		var loc1 := player_z - world_scroll_z

		var is_on_floor := (
			not _commit_fall_if_unsupported(1, player_x, player_y, loc1)
			and _is_on_track_floor(player_x, loc1, 1)
		)

		if p1_jump_allowed and player_y <= 0.0 and is_on_floor:
			p1_jump_trigger = true
			player_vel_y = JUMP_FORCE

		player_vel_y -= GRAVITY * dt
		player_y += player_vel_y * dt
		if _commit_fall_if_unsupported(1, player_x, player_y, loc1):
			is_on_floor = false

		if player_y <= 0.0 and is_on_floor:
			player_y = 0.0
			player_vel_y = 0.0

		if player_y < StageConstants.OCEAN_ENTRY_Y:
			if _is_tutorial_mode() and not _is_expected_tutorial_ocean_entry(1):
				_reset_tutorial_attempt("今は海の練習ではありません。安全な位置からこのステップをやり直します。")
				tutorial_flow.restart_current_step(false)
				return
			if _is_tutorial_mode():
				message_text = "海に落ちました！ サメが近づいてきます。"
				tutorial_flow.set_hint(message_text, 4.0)
				tutorial_ui_revision += 1
			_begin_ocean_shark_wait(1)
	elif p1_alive and p1_waiting_for_shark:
		_update_ocean_float(1, dt)
	elif game_over_timer > 0.0:
		# Tick explosion timer for dead P1 while game continues (2P)
		game_over_timer += dt

	# Player 2 movement
	if num_players >= 2 and p2_alive and not p2_waiting_for_shark:
		_commit_fall_if_unsupported(2, player2_x, player2_y, player2_z - world_scroll_z)
		player2_x += p2_axis.x * tuning.player_speed * dt
		# Removed clamp

		player2_z += world_speed * dt
		player2_z += p2_axis.y * tuning.player_speed * dt
		player2_x += p2_external_velocity.x * dt
		player2_z += p2_external_velocity.y * dt
		p2_external_velocity = p2_external_velocity.move_toward(Vector2.ZERO, EXTERNAL_IMPULSE_DECELERATION * dt)

		# Removed forward limit
		var loc2 := player2_z - world_scroll_z

		var p2_is_on_floor := (
			not _commit_fall_if_unsupported(2, player2_x, player2_y, loc2)
			and _is_on_track_floor(player2_x, loc2, 2)
		)

		if p2_jump_allowed and player2_y <= 0.0 and p2_is_on_floor:
			p2_jump_trigger = true
			player2_vel_y = JUMP_FORCE

		player2_vel_y -= GRAVITY * dt
		player2_y += player2_vel_y * dt
		if _commit_fall_if_unsupported(2, player2_x, player2_y, loc2):
			p2_is_on_floor = false

		if player2_y <= 0.0 and p2_is_on_floor:
			player2_y = 0.0
			player2_vel_y = 0.0

		if player2_y < StageConstants.OCEAN_ENTRY_Y:
			if _is_tutorial_mode() and not _is_expected_tutorial_ocean_entry(2):
				_reset_tutorial_attempt("今はP2が海へ落ちるステップではありません。安全な位置からやり直します。")
				tutorial_flow.restart_current_step(false)
				return
			if _is_tutorial_mode():
				message_text = "P2は海でサメを待機中です。P1のメイン画面は継続し、右下のDeathWipeで演出を確認できます。"
				tutorial_ui_revision += 1
			_begin_ocean_shark_wait(2)
	elif num_players >= 2 and p2_alive and p2_waiting_for_shark:
		_update_ocean_float(2, dt)
	elif num_players >= 2 and not p2_alive:
		if player2_game_over_timer > 0.0:
			# Tick explosion timer for dead P2 while game continues
			player2_game_over_timer += dt

	_resolve_two_player_body_collision(p1_body_start, p2_body_start)
	_sink_ocean_players(dt)

	# スクロールアウト死 (画面外に取り残された場合の脱落)
	if (
		num_players >= 2
		and p1_alive
		and p2_alive
		and not p1_waiting_for_shark
		and not p2_waiting_for_shark
		and is_scroll_out_death_enabled()
	):
		if player_z - player2_z > SCROLL_OUT_LIMIT:
			# P2 が遅れて画面外に消えた
			if _is_tutorial_mode():
				_reset_tutorial_attempt("P2が画面外に取り残されました。2人ともスタート位置へ戻します。")
				return
			if is_coop_mode():
				_fail_coop_immediately("P2が画面外に取り残されました。協力失敗です。")
				return
			p2_alive = false
			player2_game_over_timer = 0.001
			player_scrolled_out.emit(2)
		elif player2_z - player_z > SCROLL_OUT_LIMIT:
			# P1 が遅れて画面外に消えた
			if _is_tutorial_mode():
				_reset_tutorial_attempt("P1が画面外に取り残されました。2人ともスタート位置へ戻します。")
				return
			if is_coop_mode():
				_fail_coop_immediately("P1が画面外に取り残されました。協力失敗です。")
				return
			p1_alive = false
			game_over_timer = 0.001
			player_scrolled_out.emit(1)

	# Check collisions with wall
	# 壁を出さない操作練習ステップでは、見えない壁との衝突判定も止める。
	if are_tutorial_walls_hidden():
		return
	# コース外へ落下中のプレイヤーは、壁の横を通過しているだけなので
	# クイズ壁との衝突にしない。ここで壁死扱いにすると alive が先に false になり、
	# 後続の落水検知とサメ襲撃が開始されなくなる。
	var p1_hit: bool = (
		p1_alive
		and not p1_waiting_for_shark
		and _is_on_track_floor(player_x, player_z - world_scroll_z, 1)
		and player_z >= wall_z - 0.4
	)
	var p2_hit: bool = (
		num_players >= 2
		and p2_alive
		and not p2_waiting_for_shark
		and _is_on_track_floor(player2_x, player2_z - world_scroll_z, 2)
		and player2_z >= wall_z - 0.4
	)

	if p1_hit or p2_hit:
		# Prevent clipping through
		if p1_hit: player_z = wall_z - 0.4
		if p2_hit: player2_z = wall_z - 0.4
		resolve_collision(p1_hit, p2_hit)


func _is_expected_tutorial_ocean_entry(player_index: int) -> bool:
	if not _is_tutorial_mode() or tutorial_flow == null:
		return true
	return tutorial_flow.allows_ocean_entry(player_index)


func _update_tutorial_special_step(dt: float) -> bool:
	if not _is_tutorial_mode() or tutorial_flow == null:
		return false
	# 海やミスによる死亡演出は最後まで見せてから復帰させる。
	if tutorial_flow.is_awaiting_death_recovery():
		game_over_timer += dt
		_process_dead_player_physics(dt)
		_sink_ocean_players(dt)
		if game_over_timer >= tutorial_flow.death_recovery_duration():
			_recover_tutorial_from_death()
		return true
	if tutorial_flow.is_ghost_practice():
		var ghost_player: int = tutorial_flow.designated_ghost_player()
		var ghost_alive: bool = p1_alive if ghost_player == 1 else p2_alive
		var survivor_index: int = 2 if ghost_player == 1 else 1
		var survivor_alive: bool = p2_alive if ghost_player == 1 else p1_alive
		if not survivor_alive:
			# 標的側が落ちてもゴーストの練習は続けたいので、標的だけを復帰させる。
			# ステップ全体をやり直すとゴースト側も復活してしまい、練習が始められない。
			_revive_tutorial_player(survivor_index)
			var hint := "P%dを復帰させました。ゴーストシャークの練習を続けましょう。" % survivor_index
			message_text = hint
			tutorial_flow.set_hint(hint, 3.0)
			tutorial_ui_revision += 1
			refresh_status_text()
			state_changed.emit(game_state)
			return true
		if not ghost_alive:
			_process_dead_player_physics(dt)
	return false


## 片方のプレイヤーだけを安全な位置へ復帰させる。相手の脱落状態は保つ。
func _revive_tutorial_player(player_index: int) -> void:
	var reset_z := _tutorial_reset_z()
	if player_index == 1:
		p1_waiting_for_shark = false
		p1_shark_killed = false
		p1_ocean_float_time = 0.0
		p1_external_velocity = Vector2.ZERO
		p1_external_control_lock = 0.0
		player_x = 1.5
		player_y = 0.0
		player_z = reset_z
		player_vel_y = 0.0
		player_vel_z = 0.0
		p1_alive = true
		p1_wall_impact = false
		p1_fall_committed = false
		game_over_timer = 0.0
		p1_emote = 0
		return
	p2_waiting_for_shark = false
	p2_shark_killed = false
	p2_ocean_float_time = 0.0
	p2_external_velocity = Vector2.ZERO
	p2_external_control_lock = 0.0
	player2_x = -1.5
	player2_y = 0.0
	player2_z = reset_z
	player2_vel_y = 0.0
	player2_vel_z = 0.0
	p2_alive = true
	p2_wall_impact = false
	p2_fall_committed = false
	player2_game_over_timer = 0.0
	p2_emote = 0


## 死亡演出を最後まで見せ終えた後の復帰。同じ問題を再挑戦させるか、次のステップへ進む。
func _recover_tutorial_from_death() -> void:
	var outcome: Dictionary = tutorial_flow.finish_death_recovery()
	var retry: bool = bool(outcome.get("retry", false))
	_reset_tutorial_stage(_tutorial_reset_z())
	correct_flash = 0.0 if retry else 1.0
	wrong_flash = 0.0
	camera_shake = 0.16
	message_text = str(outcome.get("message", ""))
	tutorial_flow.set_hint(message_text, 3.2)
	tutorial_ui_revision += 1
	if not retry:
		_advance_tutorial_step()
		return
	if tutorial_flow.is_quiz_step():
		_prepare_tutorial_quiz_step(false)
	refresh_status_text()
	state_changed.emit(game_state)


## 2Pの立ち姿をXZ平面のカプセルとして扱い、めり込みを等分して押し戻す。
## 見た目だけのPlayerControllerではなく座標の権威側で解決するため、ローカル2Pと
## ホスト権威のオンライン2Pで同じ結果になり、1Pには一切影響しない。
func _resolve_two_player_body_collision(p1_start: Vector2, p2_start: Vector2) -> bool:
	if (
		num_players < 2
		or not p1_alive
		or not p2_alive
		or p1_waiting_for_shark
		or p2_waiting_for_shark
		or absf(player_y - player2_y) >= PLAYER_BODY_HEIGHT
	):
		return false

	var previous_separation := p2_start - p1_start
	var separation := Vector2(player2_x - player_x, player2_z - player_z)
	var relative_motion := separation - previous_separation
	var minimum_distance := PLAYER_BODY_RADIUS * 2.0
	var minimum_distance_squared := minimum_distance * minimum_distance
	var epsilon_squared := PLAYER_BODY_COLLISION_EPSILON * PLAYER_BODY_COLLISION_EPSILON
	var distance_squared := separation.length_squared()
	var normal := Vector2.ZERO

	# 大きなdtでも互いをすり抜けて左右が入れ替わらないよう、前フレームからの
	# 相対移動線分とカプセル円の最初の接点も調べる。
	var motion_squared := relative_motion.length_squared()
	if previous_separation.length_squared() >= minimum_distance_squared and motion_squared > epsilon_squared:
		var closest_t := clampf(-previous_separation.dot(relative_motion) / motion_squared, 0.0, 1.0)
		var closest_separation := previous_separation + relative_motion * closest_t
		if closest_separation.length_squared() < minimum_distance_squared:
			var quadratic_b := 2.0 * previous_separation.dot(relative_motion)
			var quadratic_c := previous_separation.length_squared() - minimum_distance_squared
			var discriminant := quadratic_b * quadratic_b - 4.0 * motion_squared * quadratic_c
			if discriminant >= 0.0:
				var contact_t := clampf((-quadratic_b - sqrt(discriminant)) / (2.0 * motion_squared), 0.0, 1.0)
				var contact_separation := previous_separation + relative_motion * contact_t
				if contact_separation.length_squared() > epsilon_squared:
					normal = contact_separation.normalized()

	if normal == Vector2.ZERO:
		if distance_squared >= minimum_distance_squared:
			return false
		if distance_squared > epsilon_squared:
			normal = separation / sqrt(distance_squared)
		elif previous_separation.length_squared() > epsilon_squared:
			normal = previous_separation.normalized()
		else:
			# 完全に同位置から始まった場合もP1/P2を決定的な方向へ分離する。
			normal = Vector2.LEFT

	var center := Vector2(player_x + player2_x, player_z + player2_z) * 0.5
	var half_separation := normal * (PLAYER_BODY_RADIUS + PLAYER_BODY_COLLISION_EPSILON)
	var resolved_p1 := center - half_separation
	var resolved_p2 := center + half_separation
	player_x = resolved_p1.x
	player_z = resolved_p1.y
	player2_x = resolved_p2.x
	player2_z = resolved_p2.y
	return true


func _update_correct(dt: float) -> void:
	message_timer -= dt
	# Tick explosion for dead players
	if not p1_alive and game_over_timer > 0:
		game_over_timer += dt
	if num_players >= 2 and not p2_alive and player2_game_over_timer > 0:
		player2_game_over_timer += dt
	_sink_ocean_players(dt)
	if message_timer <= 0:
		advance_after_correct()

func _update_game_over(dt: float) -> void:
	game_over_timer += dt
	if num_players >= 2 and not p2_alive:
		player2_game_over_timer += dt

	_process_dead_player_physics(dt)
	_sink_ocean_players(dt)

	# Update message with async explanation
	if current_quiz:
		var explain: String
		if current_quiz.e and not current_quiz.e.strip_edges().is_empty():
			explain = current_quiz.e
		else:
			explain = ("解説を読み込み中…" if not use_english_ui else "Loading explanation...")
		var msg: String = "%s\n%s" % [game_over_base_msg, explain]
		if num_players >= 2:
			var score_line := "P1: %d  P2: %d" % [score, player2_score]
			message_text = "GAME OVER\n\n%s\n\n%s" % [msg, score_line]
		else:
			message_text = "GAME OVER\n\n%s" % msg


# ---------- Goal Race (2P tutorial legacy) ----------

func _start_goal_race() -> void:
	var revived_players := false
	if _is_tutorial_mode() and tutorial_flow != null and tutorial_flow.revives_players():
		# 実戦で脱落したプレイヤーもレースには参加させる。
		revived_players = not p1_alive or (num_players >= 2 and not p2_alive)
		_reset_tutorial_stage(world_scroll_z)
	# ゴールラインは最後の壁の先に配置
	goal_z = tuning.wall_start_z + target_count * tuning.wall_spacing + 15.0
	if _is_tutorial_mode():
		goal_z = maxf(goal_z, world_scroll_z + 28.0)
	goal_winner = 0
	if _is_tutorial_mode():
		_tutorial_safe_z = world_scroll_z
		tutorial_ui_revision += 1
	game_state = Constants.STATE_GOAL_RACE
	message_text = "GOAL へ走れ！" if not use_english_ui else "Race to the GOAL!"
	if revived_players:
		message_text = "脱落したプレイヤーも復活！ GOAL へ走れ！"
		if tutorial_flow != null:
			tutorial_flow.set_hint(message_text, 3.0)
	refresh_status_text()
	state_changed.emit(game_state)

func _update_goal_race(dt: float, axis_p1: Vector2, axis_p2: Vector2, jump_p1: bool, jump_p2: bool, emote_p1: int = 0, emote_p2: int = 0) -> void:
	play_time += dt
	var p1_axis := Vector2.ZERO if p1_external_control_lock > 0.0 else axis_p1
	var p2_axis := Vector2.ZERO if p2_external_control_lock > 0.0 else axis_p2
	var p1_jump_allowed := jump_p1 and p1_external_control_lock <= 0.0
	var p2_jump_allowed := jump_p2 and p2_external_control_lock <= 0.0
	p1_external_control_lock = maxf(0.0, p1_external_control_lock - dt)
	p2_external_control_lock = maxf(0.0, p2_external_control_lock - dt)
	# world_scroll_z += _active_wall_speed * dt  # ゴールの動きを止めるためスクロールを停止

	p1_emote = emote_p1
	p2_emote = emote_p2
	p1_moving_back = p1_axis.y < -0.1
	p2_moving_back = p2_axis.y < -0.1
	var p1_body_start := Vector2(player_x, player_z)
	var p2_body_start := Vector2(player2_x, player2_z)

	# Player 1 movement
	if p1_alive and not p1_waiting_for_shark:
		_commit_fall_if_unsupported(
			1, player_x, player_y, player_z - world_scroll_z, FLOOR_RACE_FRONT_Z
		)
		player_x += p1_axis.x * tuning.player_speed * dt
		player_z += _active_wall_speed * dt
		player_z += p1_axis.y * tuning.player_speed * dt
		player_x += p1_external_velocity.x * dt
		player_z += p1_external_velocity.y * dt
		p1_external_velocity = p1_external_velocity.move_toward(Vector2.ZERO, EXTERNAL_IMPULSE_DECELERATION * dt)

		var loc1 := player_z - world_scroll_z
		var is_on_floor := (
			not _commit_fall_if_unsupported(1, player_x, player_y, loc1, FLOOR_RACE_FRONT_Z)
			and _is_on_track_floor(player_x, loc1, 1, FLOOR_RACE_FRONT_Z)
		)

		if p1_jump_allowed and player_y <= 0.0 and is_on_floor:
			p1_jump_trigger = true
			player_vel_y = JUMP_FORCE
		player_vel_y -= GRAVITY * dt
		player_y += player_vel_y * dt
		if _commit_fall_if_unsupported(1, player_x, player_y, loc1, FLOOR_RACE_FRONT_Z):
			is_on_floor = false
		if player_y <= 0.0 and is_on_floor:
			player_y = 0.0
			player_vel_y = 0.0
		if player_y < StageConstants.OCEAN_ENTRY_Y:
			_begin_ocean_shark_wait(1)
	elif p1_alive and p1_waiting_for_shark:
		_update_ocean_float(1, dt)

	# Player 2 movement
	if p2_alive and not p2_waiting_for_shark:
		_commit_fall_if_unsupported(
			2, player2_x, player2_y, player2_z - world_scroll_z, FLOOR_RACE_FRONT_Z
		)
		player2_x += p2_axis.x * tuning.player_speed * dt
		player2_z += _active_wall_speed * dt
		player2_z += p2_axis.y * tuning.player_speed * dt
		player2_x += p2_external_velocity.x * dt
		player2_z += p2_external_velocity.y * dt
		p2_external_velocity = p2_external_velocity.move_toward(Vector2.ZERO, EXTERNAL_IMPULSE_DECELERATION * dt)

		var loc2 := player2_z - world_scroll_z
		var p2_is_on_floor := (
			not _commit_fall_if_unsupported(2, player2_x, player2_y, loc2, FLOOR_RACE_FRONT_Z)
			and _is_on_track_floor(player2_x, loc2, 2, FLOOR_RACE_FRONT_Z)
		)

		if p2_jump_allowed and player2_y <= 0.0 and p2_is_on_floor:
			p2_jump_trigger = true
			player2_vel_y = JUMP_FORCE
		player2_vel_y -= GRAVITY * dt
		player2_y += player2_vel_y * dt
		if _commit_fall_if_unsupported(2, player2_x, player2_y, loc2, FLOOR_RACE_FRONT_Z):
			p2_is_on_floor = false
		if player2_y <= 0.0 and p2_is_on_floor:
			player2_y = 0.0
			player2_vel_y = 0.0
		if player2_y < StageConstants.OCEAN_ENTRY_Y:
			_begin_ocean_shark_wait(2)
	elif p2_alive and p2_waiting_for_shark:
		_update_ocean_float(2, dt)

	_resolve_two_player_body_collision(p1_body_start, p2_body_start)

	# Tick explosion timers for dead players
	if not p1_alive and game_over_timer > 0:
		game_over_timer += dt
	if not p2_alive and player2_game_over_timer > 0:
		player2_game_over_timer += dt

	_sink_ocean_players(dt)

	# ゴール判定
	var p1_reached := p1_alive and not p1_waiting_for_shark and player_z >= goal_z
	var p2_reached := p2_alive and not p2_waiting_for_shark and player2_z >= goal_z

	if p1_reached or p2_reached:
		if p1_reached and p2_reached:
			# 同時ゴール — スコアで勝敗を決定
			if score > player2_score:
				goal_winner = 1
			elif player2_score > score:
				goal_winner = 2
			else:
				goal_winner = 0  # 完全同点
		elif p1_reached:
			goal_winner = 1
		else:
			goal_winner = 2
		if _is_tutorial_mode() and tutorial_flow != null and tutorial_flow.starts_goal_race():
			if p1_reached:
				tutorial_flow.complete_task(1, "goal")
			if p2_reached:
				tutorial_flow.complete_task(2, "goal")
			_advance_tutorial_step()
			return
		clear_game()
		return

	# 両方死んだ場合
	if not p1_alive and not p2_alive:
		goal_winner = 0
		if _is_tutorial_mode() and tutorial_flow != null:
			# チュートリアルのレースは失敗で終わらせず、2人を復活させて再スタートする。
			_reset_tutorial_attempt("2人ともゴール前に脱落しました。もう一度レースします。")
			return
		var defeat_message := (
			"全員がゴール前に脱落しました。"
			if not use_english_ui
			else "All players were eliminated before reaching the goal."
		)
		_game_over(defeat_message)
		wrong_answer.emit(message_text)
		return


# ---------- Collision ----------

func is_within_door(x_pos: float, side: int) -> bool:
	if num_choices == 4:
		var cx: float = tuning.door4_xs[side]
		return absf(x_pos - cx) <= tuning.door4_half_width
	var center: float = tuning.left_door_x if side == 0 else tuning.right_door_x
	return absf(x_pos - center) <= tuning.door_half_width

func _is_within_coop_door(x_pos: float, door_xs: Array[float], idx: int) -> bool:
	## Coop用ドア判定 (P1用ドアまたはP2用ドア)
	if idx < 0 or idx >= door_xs.size():
		return false
	return absf(x_pos - door_xs[idx]) <= tuning.coop_door_half_width

func _check_coop_p1_door(px: float) -> int:
	## P1用ドア（左半分=正のX）の判定。 0 or 1、-1=壁
	var hits: Array[int] = []
	for i: int in range(tuning.coop_p1_door_xs.size()):
		if _is_within_coop_door(px, tuning.coop_p1_door_xs, i):
			hits.append(i)
	if hits.is_empty():
		return -1
	if hits.size() > 1:
		return -2
	return hits[0]

func _check_coop_p2_door(px: float) -> int:
	## P2用ドア（右半分=負のX）の判定。 0 or 1、-1=壁
	var hits: Array[int] = []
	for i: int in range(tuning.coop_p2_door_xs.size()):
		if _is_within_coop_door(px, tuning.coop_p2_door_xs, i):
			hits.append(i)
	if hits.is_empty():
		return -1
	if hits.size() > 1:
		return -2
	return hits[0]

func _check_player_door(px: float) -> int:
	## Return door index (0..N-1), -1=wall, -2=ambiguous
	var nc: int = num_choices
	var hits: Array[int] = []
	for i: int in range(nc):
		if is_within_door(px, i):
			hits.append(i)
	if hits.is_empty():
		return -1
	if hits.size() > 1:
		return -2
	return hits[0]

func _resolve_tutorial_collision() -> void:
	if num_players >= 2:
		_resolve_tutorial_collision_2p()
		return
	if not tutorial_flow.is_quiz_step() or current_quiz == null:
		_reset_tutorial_attempt("このステップの案内に沿って進みましょう。")
		return

	var door := _check_player_door(player_x)
	if door == current_quiz.a:
		choice_locked = true
		score += 1
		tutorial_flow.complete_task(1, "answer")
		correct_flash = 1.0
		camera_shake = 0.18
		message_text = "正解！"
		correct_answer.emit()
		_complete_tutorial_quiz_step()
		return

	var hint := _tutorial_miss_hint(door, current_quiz.a)
	# 誘導ありの問題では優しくやり直させ、誘導なしの実戦だけ本編と同じ結末を見せる。
	if not tutorial_flow.punishes_mistakes():
		_reset_tutorial_attempt(hint)
		return
	choice_locked = true
	p1_alive = false
	p1_wall_impact = true
	game_over_timer = 0.001
	player_vel_y = JUMP_FORCE * 0.8
	player_vel_z = -12.0
	camera_shake = 0.35
	message_text = hint
	tutorial_flow.set_hint(hint, WALL_DEATH_SEQUENCE_DURATION)
	tutorial_flow.begin_death_recovery(WALL_DEATH_SEQUENCE_DURATION, true)
	tutorial_ui_revision += 1
	wrong_answer.emit(message_text)


func _tutorial_miss_hint(door: int, answer: int) -> String:
	if door == -2:
		return "ドアの境目でぶつかりました。どちらかのドアの中央をねらいましょう。"
	if door < 0:
		return "ドアを外して壁に激突しました。正解は%sのドアでした。" % _tutorial_answer_label(answer)
	return "不正解のドアでした。正解は%sのドアです。" % _tutorial_answer_label(answer)

func _resolve_tutorial_collision_2p() -> void:
	var p1_at_wall := p1_alive and not p1_waiting_for_shark and player_z >= wall_z - 0.4
	var p2_at_wall := p2_alive and not p2_waiting_for_shark and player2_z >= wall_z - 0.4
	if not tutorial_flow.is_quiz_step() or current_quiz == null:
		# 壁を使わないステップで壁に触れてしまった場合は、案内の位置へ戻す。
		_reset_tutorial_attempt("このステップの案内に沿って進みましょう。")
		tutorial_flow.restart_current_step(false)
		return
	if tutorial_flow.requires_both_correct():
		_resolve_tutorial_guided_wall_2p(p1_at_wall, p2_at_wall)
		return
	_resolve_tutorial_free_wall_2p(p1_at_wall, p2_at_wall)


## 誘導ありの問題。2人が揃って正解したときだけ通過させ、ミスは優しくやり直す。
func _resolve_tutorial_guided_wall_2p(p1_at_wall: bool, p2_at_wall: bool) -> void:
	if not (p1_at_wall and p2_at_wall):
		choice_locked = false
		if p1_at_wall:
			message_text = "P1はドアに到着。P2も光るドアへ進みましょう。"
		elif p2_at_wall:
			message_text = "P2はドアに到着。P1も光るドアへ進みましょう。"
		return

	choice_locked = true
	var answer := current_quiz.a
	var p1_door := _check_player_door(player_x)
	var p2_door := _check_player_door(player2_x)
	if p1_door != answer or p2_door != answer:
		var misses: Array[String] = []
		for miss_text: String in [
			_tutorial_player_miss_text("P1", p1_door, answer),
			_tutorial_player_miss_text("P2", p2_door, answer),
		]:
			if not miss_text.is_empty():
				misses.append(miss_text)
		var hint := " / ".join(misses)
		hint += " 正解は%sドアです。2人とももう一度選びましょう。" % _tutorial_answer_label(answer)
		_reset_tutorial_attempt(hint)
		return

	score += 1
	player2_score += 1
	tutorial_flow.complete_task(1, "answer")
	tutorial_flow.complete_task(2, "answer")
	correct_flash = 1.0
	camera_shake = 0.18
	message_text = "2人とも正解！ P1・P2それぞれに得点が入りました。"
	correct_answer.emit()
	_complete_tutorial_quiz_step()


## 誘導なしの実戦。本編と同じ個別判定で、間違えた側だけが本当に脱落して
## ゴーストシャークへ回り、正解した側は止まらず次の問題へ進む。
func _resolve_tutorial_free_wall_2p(p1_at_wall: bool, p2_at_wall: bool) -> void:
	if not (p1_at_wall or p2_at_wall):
		return
	var answer := current_quiz.a
	var p1_correct := false
	var p2_correct := false
	var misses: Array[String] = []

	if p1_at_wall:
		var p1_door := _check_player_door(player_x)
		if p1_door == answer:
			p1_correct = true
			score += 1
			tutorial_flow.complete_task(1, "answer")
		else:
			_apply_tutorial_wall_death(1)
			misses.append(_tutorial_player_miss_text("P1", p1_door, answer))
	if p2_at_wall:
		var p2_door := _check_player_door(player2_x)
		if p2_door == answer:
			p2_correct = true
			player2_score += 1
			tutorial_flow.complete_task(2, "answer")
		else:
			_apply_tutorial_wall_death(2)
			misses.append(_tutorial_player_miss_text("P2", p2_door, answer))

	var miss_summary := " / ".join(misses)
	if p1_correct or p2_correct:
		choice_locked = true
		correct_flash = 1.0
		camera_shake = 0.18
		var correct_label := (
			"2人とも正解！"
			if p1_correct and p2_correct
			else "P%d正解！ %s" % [1 if p1_correct else 2, miss_summary]
		)
		message_text = correct_label.strip_edges()
		tutorial_flow.set_hint(message_text, 3.0)
		tutorial_ui_revision += 1
		correct_answer.emit()
		_complete_tutorial_quiz_step()
		return

	if not p1_alive and not p2_alive:
		# 2人とも脱落したときだけ、激突演出を見せ切ってから同じ問題をやり直す。
		choice_locked = true
		message_text = "2人とも不正解。正解は%sのドアでした。" % _tutorial_answer_label(answer)
		tutorial_flow.set_hint(message_text, WALL_DEATH_SEQUENCE_DURATION)
		tutorial_flow.begin_death_recovery(WALL_DEATH_SEQUENCE_DURATION, true)
		tutorial_ui_revision += 1
		wrong_answer.emit(message_text)
		return

	# 片方だけが脱落。残ったプレイヤーの回答を待つので、判定は閉じない。
	choice_locked = false
	message_text = "%s 残ったプレイヤーは自分でドアを選びましょう。" % miss_summary
	tutorial_flow.set_hint(message_text, 3.4)
	tutorial_ui_revision += 1
	wrong_answer.emit(message_text)


## 本編と同じ壁激突の脱落処理。ラグドールとゴーストシャークはこの状態から始まる。
func _apply_tutorial_wall_death(player_index: int) -> void:
	camera_shake = 0.35
	if player_index == 1:
		p1_alive = false
		p1_wall_impact = true
		game_over_timer = 0.001
		player_vel_y = JUMP_FORCE * 0.8
		player_vel_z = -12.0
		return
	p2_alive = false
	p2_wall_impact = true
	player2_game_over_timer = 0.001
	player2_vel_y = JUMP_FORCE * 0.8
	player2_vel_z = -12.0

func _tutorial_player_miss_text(player_label: String, door: int, answer: int) -> String:
	if door == -2:
		return "%sはドアの境目にいます" % player_label
	if door < 0:
		return "%sはドアから外れています" % player_label
	if door == answer:
		return ""
	return "%sは逆のドアです" % player_label

func _tutorial_answer_label(answer: int) -> String:
	var labels := ["左", "右"]
	if answer >= 0 and answer < labels.size():
		return labels[answer]
	return "正解"

## やり直し。死亡演出を挟まずに安全な位置へ戻す軽いリセット。
func _reset_tutorial_attempt(hint: String) -> void:
	_reset_tutorial_stage(_tutorial_reset_z())
	wrong_flash = 1.0
	camera_shake = 0.16
	message_text = hint
	if tutorial_flow != null:
		tutorial_flow.set_hint(hint)
	tutorial_ui_revision += 1
	refresh_status_text()
	state_changed.emit(game_state)

func _coop_wait_message(p1_at_wall: bool, p2_at_wall: bool) -> String:
	if p1_at_wall and not p2_at_wall:
		return "P1はカード選択完了。P2も自分のカードへ進んでください。"
	if p2_at_wall and not p1_at_wall:
		return "P2はカード選択完了。P1も自分のカードへ進んでください。"
	return "式・根拠カードと答えカードを組み合わせて、2人で突破しましょう。"

func _register_coop_result(correct: bool, p1_door: int = -1, p2_door: int = -1) -> void:
	if not current_quiz:
		return
	if correct:
		score += 1
		player2_score += 1
		current_streak += 1
		max_streak = maxi(max_streak, current_streak)
	else:
		total_wrong += 1
		current_streak = 0
	total_answered += 1
	recent_results.append(correct)
	if recent_results.size() > 12:
		recent_results.remove_at(0)

	provider.submit_result(current_quiz, correct)
	quiz_history.append({
		"quiz": current_quiz,
		"correct": correct,
		"rated": "",
		"p1_choice": p1_door,
		"p2_choice": p2_door
	})

	var response_time: float = (Time.get_ticks_msec() - _quiz_shown_time) / 1000.0
	recent_response_times.append(response_time)
	if recent_response_times.size() > 5:
		recent_response_times.pop_front()

	if correct:
		QuizManager.quiz_optimizer.evaluate_history(quiz_history, subject, grade, difficulty)

func _coop_choice_label(player: int, door: int) -> String:
	if door == -2:
		return "ドアの境目"
	if door < 0:
		return "壁"
	if not current_quiz or not current_quiz.has_coop_data():
		return "?"
	var choices := current_quiz.coop_p1_choices if player == 1 else current_quiz.coop_p2_choices
	if door >= 0 and door < choices.size():
		return choices[door]
	return "?"

func _coop_correct_label(player: int) -> String:
	if not current_quiz or not current_quiz.has_coop_data():
		return "?"
	var choices := current_quiz.coop_p1_choices if player == 1 else current_quiz.coop_p2_choices
	var answer := current_quiz.coop_p1_answer if player == 1 else current_quiz.coop_p2_answer
	if answer >= 0 and answer < choices.size():
		return choices[answer]
	return "?"

func _coop_failure_message(p1_door: int, p2_door: int) -> String:
	var lines: Array[String] = ["協力失敗"]
	if p1_door != current_quiz.coop_p1_answer:
		lines.append("P1: %s / 正解: %s" % [
			_coop_choice_label(1, p1_door),
			_coop_correct_label(1)
		])
	if p2_door != current_quiz.coop_p2_answer:
		lines.append("P2: %s / 正解: %s" % [
			_coop_choice_label(2, p2_door),
			_coop_correct_label(2)
		])
	return "\n".join(lines)

func apply_external_impulse(
	player_index: int,
	horizontal_velocity: Vector2,
	vertical_velocity: float,
	control_lock_seconds: float
) -> void:
	if player_index == 1:
		if not p1_alive or p1_waiting_for_shark:
			return
		p1_external_velocity = horizontal_velocity.limit_length(18.0)
		player_vel_y = maxf(player_vel_y, vertical_velocity)
		p1_external_control_lock = maxf(p1_external_control_lock, control_lock_seconds)
	else:
		if not p2_alive or p2_waiting_for_shark:
			return
		p2_external_velocity = horizontal_velocity.limit_length(18.0)
		player2_vel_y = maxf(player2_vel_y, vertical_velocity)
		p2_external_control_lock = maxf(p2_external_control_lock, control_lock_seconds)
	camera_shake = maxf(camera_shake, 0.45)


func _reset_external_impulses() -> void:
	p1_external_velocity = Vector2.ZERO
	p2_external_velocity = Vector2.ZERO
	p1_external_control_lock = 0.0
	p2_external_control_lock = 0.0


func _reset_ocean_shark_state() -> void:
	p1_waiting_for_shark = false
	p2_waiting_for_shark = false
	p1_shark_killed = false
	p2_shark_killed = false
	p1_ocean_float_time = 0.0
	p2_ocean_float_time = 0.0
	p1_ocean_local_z = 0.0
	p2_ocean_local_z = 0.0


func _begin_ocean_shark_wait(player_index: int) -> void:
	if player_index == 1:
		if p1_waiting_for_shark or not p1_alive:
			return
		p1_waiting_for_shark = true
		p1_shark_killed = false
		p1_ocean_float_time = 0.0
		p1_ocean_local_z = player_local_z
		player_y = StageConstants.OCEAN_FLOAT_Y
		player_vel_y = 0.0
		player_vel_z = 0.0
		p1_external_velocity = Vector2.ZERO
		p1_external_control_lock = 0.0
		p1_moving_back = false
		p1_jump_trigger = false
	else:
		if p2_waiting_for_shark or not p2_alive:
			return
		p2_waiting_for_shark = true
		p2_shark_killed = false
		p2_ocean_float_time = 0.0
		p2_ocean_local_z = player2_local_z
		player2_y = StageConstants.OCEAN_FLOAT_Y
		player2_vel_y = 0.0
		player2_vel_z = 0.0
		p2_external_velocity = Vector2.ZERO
		p2_external_control_lock = 0.0
		p2_moving_back = false
		p2_jump_trigger = false
	_emit_player_entered_ocean(player_index)


func _update_ocean_float(player_index: int, dt: float) -> void:
	if player_index == 1:
		p1_ocean_float_time += dt
		player_y = StageConstants.OCEAN_FLOAT_Y + sin(p1_ocean_float_time * 2.35) * 0.12
		player_z = world_scroll_z + p1_ocean_local_z
		player_vel_y = 0.0
		player_vel_z = 0.0
		p1_moving_back = false
		p1_jump_trigger = false
	else:
		p2_ocean_float_time += dt
		player2_y = StageConstants.OCEAN_FLOAT_Y + sin(p2_ocean_float_time * 2.35 + 1.1) * 0.12
		player2_z = world_scroll_z + p2_ocean_local_z
		player2_vel_y = 0.0
		player2_vel_z = 0.0
		p2_moving_back = false
		p2_jump_trigger = false


func is_player_waiting_for_shark(player_index: int) -> bool:
	return p1_waiting_for_shark if player_index == 1 else p2_waiting_for_shark


func get_ocean_player_local_position(player_index: int) -> Vector3:
	if player_index == 1:
		return Vector3(player_x, StageConstants.OCEAN_SURFACE_Y, p1_ocean_local_z)
	return Vector3(player2_x, StageConstants.OCEAN_SURFACE_Y, p2_ocean_local_z)


func complete_ocean_shark_attack(player_index: int) -> void:
	if not is_player_waiting_for_shark(player_index):
		return

	if player_index == 1:
		p1_waiting_for_shark = false
		p1_shark_killed = true
		p1_alive = false
		p1_wall_impact = false
		player_y = StageConstants.OCEAN_FLOAT_Y
		player_vel_y = 0.0
		game_over_timer = 0.001
	else:
		p2_waiting_for_shark = false
		p2_shark_killed = true
		p2_alive = false
		p2_wall_impact = false
		player2_y = StageConstants.OCEAN_FLOAT_Y
		player2_vel_y = 0.0
		player2_game_over_timer = 0.001

	camera_shake = 0.75
	if _is_tutorial_mode():
		tutorial_ui_revision += 1
		if (
			is_tutorial_ghost_practice()
			and tutorial_flow.designated_hazard_player() == player_index
			and tutorial_flow.designated_ghost_player() == player_index
		):
			message_text = "サメ演出完了。魂がゴーストシャークへ移るまで待ちましょう。"
			refresh_status_text()
			state_changed.emit(game_state)
			return
		if (
			tutorial_flow.is_ocean_hazard_step()
			and tutorial_flow.designated_hazard_player() == player_index
		):
			tutorial_flow.complete_task(player_index, "ocean")
			if tutorial_flow.hands_off_to_ghost_after_hazard():
				# 復活させず、そのままゴーストシャークの練習ステップへ引き継ぐ。
				message_text = "サメに襲われて脱落。ここからはゴーストシャークで反撃します。"
				tutorial_flow.set_hint(message_text, 4.0)
				_advance_tutorial_step()
				return
			# 壁への激突と同じく、サメ演出も最後まで見せてから復帰させる。
			tutorial_flow.begin_death_recovery(TUTORIAL_OCEAN_RECOVERY_DURATION, false)
			message_text = "サメに襲われました。コースの外は危険です。"
			tutorial_flow.set_hint(message_text, TUTORIAL_OCEAN_RECOVERY_DURATION)
			refresh_status_text()
			state_changed.emit(game_state)
			return
		if tutorial_flow.punishes_mistakes() or tutorial_flow.starts_goal_race():
			# 実戦と最終レースでは本編と同じ結末。全滅時のやり直しは
			# 実戦は死亡復帰、最終レースは _update_goal_race 側で扱う。
			var all_defeated: bool = not p1_alive and (num_players < 2 or not p2_alive)
			if all_defeated and tutorial_flow.punishes_mistakes():
				message_text = "2人とも脱落しました。もう一度挑戦しましょう。"
				tutorial_flow.set_hint(message_text, WALL_DEATH_SEQUENCE_DURATION)
				tutorial_flow.begin_death_recovery(WALL_DEATH_SEQUENCE_DURATION, true)
			else:
				message_text = "P%dが海でサメに襲われました。" % player_index
				tutorial_flow.set_hint(message_text, 3.4)
			refresh_status_text()
			state_changed.emit(game_state)
			return
		_reset_tutorial_attempt("海の練習を安全な位置からやり直します。")
		return
	# 片方が先にサメに倒されても、もう片方の海上・サメ襲撃演出を完走させる。
	# 両者が倒れた後だけ、協力プレイの失敗処理へ進む。
	if is_coop_mode() and not p1_alive and not p2_alive:
		var coop_message: String = (
			"P%dがサメに襲われました。協力失敗です。" % player_index
			if not use_english_ui
			else "P%d was caught by a shark. Co-op failed." % player_index
		)
		_fail_coop_immediately(coop_message)
		return

	var all_players_defeated: bool = (
		not p1_alive
		and (num_players < 2 or not p2_alive)
	)
	if not all_players_defeated:
		return

	if current_quiz and not choice_locked:
		choice_locked = true
		provider.submit_result(current_quiz, false)
		quiz_history.append({"quiz": current_quiz, "correct": false, "rated": ""})
	var message: String = (
		"海でサメに襲われた！"
		if not use_english_ui
		else "A shark caught you in the ocean!"
	)
	_game_over(message)
	wrong_answer.emit(message_text)


func _sink_ocean_players(dt: float) -> void:
	if p1_shark_killed:
		player_y = StageConstants.OCEAN_FLOAT_Y
		player_vel_y = 0.0
	elif not p1_alive and game_over_timer > 0.0 and player_y <= StageConstants.OCEAN_ENTRY_Y:
		player_y = move_toward(player_y, StageConstants.OCEAN_SINK_Y, StageConstants.OCEAN_SINK_SPEED * dt)
		player_vel_y = 0.0
	if p2_shark_killed:
		player2_y = StageConstants.OCEAN_FLOAT_Y
		player2_vel_y = 0.0
	elif num_players >= 2 and not p2_alive and player2_game_over_timer > 0.0 and player2_y <= StageConstants.OCEAN_ENTRY_Y:
		player2_y = move_toward(player2_y, StageConstants.OCEAN_SINK_Y, StageConstants.OCEAN_SINK_SPEED * dt)
		player2_vel_y = 0.0


func _emit_player_entered_ocean(player_index: int) -> void:
	var local_position: Vector3
	if player_index == 1:
		local_position = Vector3(player_x, StageConstants.OCEAN_SURFACE_Y, player_local_z)
	else:
		local_position = Vector3(player2_x, StageConstants.OCEAN_SURFACE_Y, player2_local_z)
	player_entered_ocean.emit(player_index, local_position)


func _process_dead_player_physics(dt: float) -> void:
	if not p1_alive and game_over_timer > 0.0 and game_over_timer < 2.5 and player_y > StageConstants.OCEAN_ENTRY_Y:
		player_vel_y -= GRAVITY * dt
		player_y += player_vel_y * dt
		player_vel_z = move_toward(player_vel_z, 0.0, dt * 15.0)
		player_z += player_vel_z * dt
		var local_z = player_z - world_scroll_z
		var is_on_floor = local_z >= FLOOR_BACK_Z and abs(player_x) <= FLOOR_HALF_WIDTH
		var limit_y: float = 0.0 if is_on_floor else StageConstants.OCEAN_ENTRY_Y
		
		if player_y <= limit_y and player_vel_y < 0.0:
			player_y = limit_y
			player_vel_y = 0.0
			if is_on_floor:
				player_vel_z = 0.0
			
	if num_players >= 2 and not p2_alive and player2_game_over_timer > 0.0 and player2_game_over_timer < 2.5 and player2_y > StageConstants.OCEAN_ENTRY_Y:
		player2_vel_y -= GRAVITY * dt
		player2_y += player2_vel_y * dt
		player2_vel_z = move_toward(player2_vel_z, 0.0, dt * 15.0)
		player2_z += player2_vel_z * dt
		var local2_z = player2_z - world_scroll_z
		var is2_on_floor = local2_z >= FLOOR_BACK_Z and abs(player2_x) <= FLOOR_HALF_WIDTH
		var limit2_y: float = 0.0 if is2_on_floor else StageConstants.OCEAN_ENTRY_Y
		
		if player2_y <= limit2_y and player2_vel_y < 0.0:
			player2_y = limit2_y
			player2_vel_y = 0.0
			if is2_on_floor:
				player2_vel_z = 0.0


## 壁衝突の「ラグドール -> 四肢分散」が終わるまでは結果画面や離脱を許可しない。
func is_wall_death_sequence_complete() -> bool:
	if p1_wall_impact and not p1_alive and game_over_timer < WALL_DEATH_SEQUENCE_DURATION:
		return false
	if p2_wall_impact and not p2_alive and player2_game_over_timer < WALL_DEATH_SEQUENCE_DURATION:
		return false
	return true

func _fail_coop_immediately(msg: String) -> void:
	if choice_locked:
		return
	choice_locked = true
	p1_waiting_for_shark = false
	p2_waiting_for_shark = false
	p1_alive = false
	p2_alive = false
	p1_wall_impact = false
	p2_wall_impact = false
	game_over_timer = 0.001
	player2_game_over_timer = 0.001
	_register_coop_result(false)
	_game_over(msg)
	wrong_answer.emit(message_text)

func _resolve_coop_collision() -> void:
	if current_quiz and _should_rebuild_coop_quiz(current_quiz):
		current_quiz = CoopQuizBuilder.build_coop_quiz(current_quiz, subject, grade, current_index)
	if not current_quiz or not current_quiz.has_coop_data():
		_fail_coop_immediately("協力問題の準備に失敗しました。")
		return

	var p1_at_wall := p1_alive and player_z >= wall_z - 0.41
	var p2_at_wall := p2_alive and player2_z >= wall_z - 0.41
	if not (p1_at_wall and p2_at_wall):
		choice_locked = false
		message_text = _coop_wait_message(p1_at_wall, p2_at_wall)
		return

	choice_locked = true
	var p1_door := _check_coop_p1_door(player_x)
	var p2_door := _check_coop_p2_door(player2_x)
	var p1_correct := p1_door == current_quiz.coop_p1_answer
	var p2_correct := p2_door == current_quiz.coop_p2_answer
	var both_correct := p1_correct and p2_correct

	_register_coop_result(both_correct, p1_door, p2_door)

	if both_correct:
		correct_flash = 1.0
		camera_shake = 0.22
		message_text = "協力成功！"
		correct_answer.emit()
		advance_after_correct()
	else:
		p1_alive = false
		p2_alive = false
		p1_wall_impact = true
		p2_wall_impact = true
		game_over_timer = 0.001
		player2_game_over_timer = 0.001
		player_vel_y = JUMP_FORCE * 0.8
		player_vel_z = -12.0
		player2_vel_y = JUMP_FORCE * 0.8
		player2_vel_z = -12.0
		_game_over(_coop_failure_message(p1_door, p2_door))
		wrong_answer.emit(message_text)

func resolve_collision(p1_hit: bool = false, p2_hit: bool = false) -> void:
	if choice_locked:
		return
	if _is_tutorial_mode():
		_resolve_tutorial_collision()
		return
	if not current_quiz:
		return
	if is_coop_mode():
		_resolve_coop_collision()
		return

	var answer: int = current_quiz.a

	var p1_correct: bool = false
	var p2_correct: bool = false
	var evaluated_anyone: bool = false

	# --- Player 1 ---
	if p1_hit:
		evaluated_anyone = true
		var door: int = _check_player_door(player_x)
		if door < 0:
			# 壁に衝突
			p1_alive = false
			p1_wall_impact = true
			game_over_timer = 0.001
			player_vel_y = JUMP_FORCE * 0.8
			player_vel_z = -12.0
			current_streak = 0
			total_answered += 1
			total_wrong += 1
			recent_results.append(false)
			if recent_results.size() > 12:
				recent_results.remove_at(0)
		elif door == answer:
			score += 1
			p1_correct = true
			current_streak += 1
			if current_streak > max_streak:
				max_streak = current_streak
			total_answered += 1
			recent_results.append(true)
			if recent_results.size() > 12:
				recent_results.remove_at(0)
		else:
			# 不正解ドア
			p1_alive = false
			p1_wall_impact = true
			game_over_timer = 0.001
			player_vel_y = JUMP_FORCE * 0.8
			player_vel_z = -12.0
			current_streak = 0
			total_answered += 1
			total_wrong += 1
			recent_results.append(false)
			if recent_results.size() > 12:
				recent_results.remove_at(0)

	# --- Player 2 ---
	if num_players >= 2 and p2_hit:
		evaluated_anyone = true
		var door2: int = _check_player_door(player2_x)
		if door2 < 0:
			p2_alive = false
			p2_wall_impact = true
			player2_game_over_timer = 0.001
			player2_vel_y = JUMP_FORCE * 0.8
			player2_vel_z = -12.0
		elif door2 == answer:
			player2_score += 1
			p2_correct = true
		else:
			p2_alive = false
			p2_wall_impact = true
			player2_game_over_timer = 0.001
			player2_vel_y = JUMP_FORCE * 0.8
			player2_vel_z = -12.0

	if not evaluated_anyone:
		return

	var any_correct: bool = p1_correct or p2_correct
	var any_alive: bool = p1_alive or (num_players >= 2 and p2_alive)

	# 全員不正解（全滅）か、誰かが正解した場合のみ処理を完了させる
	if any_correct or not any_alive:
		choice_locked = true
		provider.submit_result(current_quiz, any_correct)
		quiz_history.append({"quiz": current_quiz, "correct": any_correct, "rated": ""})

		# 確実に問題を解き終わったあとにFirebaseへ保存する（バックグラウンド評価を即時キック）
		QuizManager.quiz_optimizer.evaluate_history(quiz_history, subject, grade, difficulty)

		# パフォーマンスと行動データを記録
		if current_quiz:
			var response_time: float = (Time.get_ticks_msec() - _quiz_shown_time) / 1000.0
			recent_response_times.append(response_time)
			if recent_response_times.size() > 5:
				recent_response_times.pop_front()

			if QuizManager.player_analytics != null:
				var chosen_door: int = _check_player_door(player_x) if p1_hit or not p1_correct else current_quiz.a
				QuizManager.player_analytics.record(
					current_quiz, response_time, any_correct, chosen_door,
					subject, grade, difficulty
				)

		if any_correct:
			# No-stop: stay in STATE_PLAYING and advance immediately
			correct_flash = 1.0
			camera_shake = 0.22
			message_text = "Correct!" if use_english_ui else "正解！"
			correct_answer.emit()
			advance_after_correct()
		else:
			var nc: int = num_choices
			var ans_label: String
			if nc == 4:
				var labels := ["A", "B", "C", "D"]
				ans_label = labels[answer] if answer >= 0 and answer < 4 else "?"
			else:
				if use_english_ui:
					ans_label = "Left" if answer == 0 else "Right"
				else:
					ans_label = "左" if answer == 0 else "右"
			if use_english_ui:
				_game_over("Wrong! Answer was %s" % ans_label)
			else:
				_game_over("不正解！ 正解は %s" % ans_label)
			wrong_answer.emit(message_text)

func advance_after_correct() -> void:
	current_wall_index += 1
	if p1_alive:
		game_over_timer = 0.0
	if p2_alive or num_players < 2:
		player2_game_over_timer = 0.0

	if _is_fixed_count_mode():
		current_index += 1
		var missing := maxi(0, target_count - quiz_list.size())
		if missing > 0 and not _is_tutorial_mode():
			var new_quizzes := provider.get_quizzes(subject, grade, difficulty, _provider_mode(), missing)
			quiz_list.append_array(new_quizzes)
			_prepare_coop_quiz_list()
		load_current_quiz()
	else:
		# 現在の問題を消費してローカルキューから除去
		if quiz_list.size() > 0:
			quiz_list.pop_front()
		# ローカルキューが空になったら3問ずつ補充
		if quiz_list.is_empty():
			quiz_list = provider.get_quizzes(subject, grade, difficulty,
				Constants.MODE_ENDLESS, 3)
		load_current_quiz()
	if game_state not in [Constants.STATE_PRELOADING, Constants.STATE_WAITING_START, Constants.STATE_COUNTDOWN, Constants.STATE_CLEAR, Constants.STATE_GAME_OVER, Constants.STATE_GOAL_RACE]:
		game_state = Constants.STATE_PLAYING
		message_text = ""
		state_changed.emit(game_state)


# ---------- Game over / clear ----------

func _game_over(msg: String) -> void:
	game_state = Constants.STATE_GAME_OVER
	provider.end_round()
	rating_target_quiz = current_quiz
	rating_feedback = ""
	game_over_base_msg = msg
	var explain: String
	if current_quiz and current_quiz.e and not current_quiz.e.strip_edges().is_empty():
		explain = current_quiz.e
	else:
		explain = ("解説を読み込み中…" if not use_english_ui else "Loading explanation...")
	var full_msg: String = "%s\n%s" % [msg, explain]
	if num_players >= 2:
		var score_line := "P1: %d  P2: %d" % [score, player2_score]
		message_text = "GAME OVER\n\n%s\n\n%s" % [full_msg, score_line]
	else:
		message_text = "GAME OVER\n\n%s" % full_msg
	wrong_flash = 1.0
	camera_shake = 0.35
	refresh_status_text()
	state_changed.emit(game_state)
	QuizManager.quiz_optimizer.evaluate_history(quiz_history, subject, grade, difficulty)

func clear_game() -> void:
	game_state = Constants.STATE_CLEAR
	provider.end_round()
	rating_target_quiz = current_quiz
	rating_feedback = ""
	if _is_tutorial_mode():
		rating_target_quiz = null
		var summary := PackedStringArray(["TUTORIAL CLEAR!"])
		if tutorial_flow != null:
			summary.append_array(tutorial_flow.clear_summary_lines())
		message_text = "\n".join(summary)
		correct_flash = 1.0
		GameManager.mark_tutorial_course_completed(get_tutorial_course())
		refresh_status_text()
		game_cleared.emit(message_text)
		state_changed.emit(game_state)
		return
	if is_coop_mode():
		if use_english_ui:
			message_text = "COOP CLEAR!\n10 questions cleared together\nTeam Score: %d/10" % score
		else:
			message_text = "COOP CLEAR!\n2人で10問突破\n協力成功: %d/10" % score
		correct_flash = 1.0
		refresh_status_text()
		game_cleared.emit(message_text)
		state_changed.emit(game_state)
		QuizManager.quiz_optimizer.evaluate_history(quiz_history, subject, grade, difficulty)
		return
	if num_players >= 2:
		var winner_text: String
		if goal_winner == 1:
			winner_text = "🏆 P1 WIN!" if use_english_ui else "🏆 P1 の勝ち！"
		elif goal_winner == 2:
			winner_text = "🏆 P2 WIN!" if use_english_ui else "🏆 P2 の勝ち！"
		else:
			winner_text = "DRAW!" if use_english_ui else "引き分け！"
		if use_english_ui:
			message_text = "CLEAR! Congrats\n%s\n10 questions done\nP1 Score: %d/10  P2 Score: %d/10" % [winner_text, score, player2_score]
		else:
			message_text = "CLEAR! おめでとう\n%s\n10問完走\nP1 正解数: %d/10  P2 正解数: %d/10" % [winner_text, score, player2_score]
	else:
		if use_english_ui:
			message_text = "CLEAR! Congrats\n10 questions done  Score: %d/10" % score
		else:
			message_text = "CLEAR! おめでとう\n10問完走  正解数: %d/10" % score
	correct_flash = 1.0
	refresh_status_text()
	game_cleared.emit(message_text)
	state_changed.emit(game_state)
	QuizManager.quiz_optimizer.evaluate_history(quiz_history, subject, grade, difficulty)


# ---------- Rating ----------

func rate_last_question(good: bool) -> void:
	if not rating_target_quiz:
		return
	if good:
		rating_feedback = "Rated: Good" if use_english_ui else "評価: 良い問題"
	else:
		rating_feedback = "Rated: Bad" if use_english_ui else "評価: 悪い問題"
	# Send to Firebase via QuizManager
	QuizManager.firebase_ratings.send_rating(
		rating_target_quiz, good, subject, grade, difficulty
	)

func rate_quiz_at(index: int, good: bool) -> void:
	"""Rate a specific question in the history by its index."""
	if index < 0 or index >= quiz_history.size():
		return
	var entry: Dictionary = quiz_history[index]
	var quiz: QuizItem = entry["quiz"]
	entry["rated"] = "good" if good else "bad"
	entry["player_rated"] = true
	quiz_history[index] = entry
	# Send to Firebase
	QuizManager.firebase_ratings.send_rating(
		quiz, good, subject, grade, difficulty
	)


# ---------- Display helpers ----------

func question_text() -> String:
	if not current_quiz:
		return ""
	return "Q: %s" % current_quiz.q

func choices_text() -> PackedStringArray:
	if not current_quiz:
		return PackedStringArray(["", ""])
	if is_coop_mode() and current_quiz.has_coop_data():
		return PackedStringArray([
			"%s A: %s" % [current_quiz.coop_p1_label, current_quiz.coop_p1_choices[0]],
			"%s B: %s" % [current_quiz.coop_p1_label, current_quiz.coop_p1_choices[1]],
			"%s A: %s" % [current_quiz.coop_p2_label, current_quiz.coop_p2_choices[0]],
			"%s B: %s" % [current_quiz.coop_p2_label, current_quiz.coop_p2_choices[1]],
		])
	if num_choices == 4 and current_quiz.c.size() >= 4:
		return PackedStringArray([
			"A: %s" % current_quiz.c[0],
			"B: %s" % current_quiz.c[1],
			"C: %s" % current_quiz.c[2],
			"D: %s" % current_quiz.c[3],
		])
	if use_english_ui:
		return PackedStringArray([
			"Left [A]: %s" % current_quiz.c[0],
			"Right [D]: %s" % current_quiz.c[1],
		])
	return PackedStringArray([
		"左ドア [A]: %s" % current_quiz.c[0],
		"右ドア [D]: %s" % current_quiz.c[1],
	])

func refresh_status_text() -> void:
	if game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]:
		if _is_tutorial_mode():
			status_text = "チュートリアル完了  |  [R] でメニューへ戻る"
			return
		if use_english_ui:
			if is_coop_mode():
				status_text = "Team Score: %d  |  Press [R] for menu" % score
			else:
				status_text = "Score: %d  |  Press [R] for menu" % score
		elif is_coop_mode():
			status_text = "協力成功: %d  |  [R] でメニューへ戻る" % score
		else:
			status_text = "正解数: %d  |  [R] でメニューへ戻る" % score
		return

	if game_state == Constants.STATE_MENU:
		if use_english_ui:
			if menu_step == Constants.MENU_STEP_MODE:
				status_text = "Step 1/3: Select mode"
			else:
				var mode_label: String = "Co-op" if is_coop_mode() else ("10 Q" if mode == Constants.MODE_TEN else "Endless")
				status_text = "Step 2/3: Set grade/subject  |  Mode:%s Subject:%s Grade:%d" % [
					mode_label,
					Constants.SUBJECT_EN.get(subject, subject),
					grade
				]
		else:
			if menu_step == Constants.MENU_STEP_MODE:
				status_text = "手順 1/3: モードを選択"
			else:
				var mode_label: String = "2人協力" if is_coop_mode() else ("10問チャレンジ" if mode == Constants.MODE_TEN else "エンドレス")
				status_text = "手順 2/3: 学年・教科を設定  |  モード:%s  教科:%s  学年:%d" % [
					mode_label, subject, grade
				]
		return

	if game_state == Constants.STATE_PRELOADING:
		if use_english_ui:
			if _is_fixed_count_mode():
				status_text = "Loading quizzes... %d/%d (Subject:%s Grade:%d)" % [
					quiz_list.size(), target_count,
					Constants.SUBJECT_EN.get(subject, subject), grade
				]
			else:
				status_text = "Loading quiz... buffered:%d (Subject:%s Grade:%d)" % [
					quiz_list.size(),
					Constants.SUBJECT_EN.get(subject, subject), grade
				]
		else:
			if _is_fixed_count_mode():
				status_text = "クイズ準備中... %d/%d 教科:%s 学年:%d" % [
					quiz_list.size(), target_count, subject, grade
				]
			else:
				status_text = "クイズ準備中... バッファ:%d 教科:%s 学年:%d" % [
					quiz_list.size(), subject, grade
				]
		return

	# Playing state
	if _is_tutorial_mode():
		var overlay := get_tutorial_overlay_model()
		var phase_label := str(overlay.get("title", "チュートリアル"))
		var progress_label := "%d/%d" % [
			int(overlay.get("step_number", 1)), int(overlay.get("step_count", 1))
		]
		if num_players >= 2:
			status_text = "2P チュートリアル  %s  %s  P1:%d  P2:%d" % [
				progress_label, phase_label, score, player2_score
			]
		else:
			status_text = "チュートリアル  %s  %s" % [progress_label, phase_label]
		return

	if use_english_ui:
		var mode_label: String = "Co-op" if is_coop_mode() else ("10 Q" if mode == Constants.MODE_TEN else "Endless")
		var progress: String = "%d/10" % (current_index + 1) if _is_fixed_count_mode() else "inf"
		var subj: String = Constants.SUBJECT_EN.get(subject, subject)
		var diff: String = Constants.DIFFICULTY_EN.get(difficulty, difficulty)
		status_text = "Subject:%s Grade:%d Diff:%s Mode:%s Progress:%s Score:%d" % [
			subj, grade, diff, mode_label, progress, score
		]
	else:
		var mode_label: String = "2人協力" if is_coop_mode() else ("10問チャレンジ" if mode == Constants.MODE_TEN else "エンドレス")
		var progress: String = "%d/10" % (current_index + 1) if _is_fixed_count_mode() else "∞"
		var score_name := "協力成功" if is_coop_mode() else "正解数"
		status_text = "教科:%s  学年:%d  難易度:%s  モード:%s  進行:%s  %s:%d" % [
			subject, grade, difficulty, mode_label, progress, score_name, score
		]

# ===========================================================================
# Network snapshot serialization (used by net_game_state.gd)
# ===========================================================================

func to_snapshot() -> Dictionary:
	"""ホスト側: 現在のゲーム状態をDictionaryにシリアライズ (クライアントに送信用)"""
	return {
		# Player 1
		"p1x": player_x,
		"p1y": player_y,
		"p1z": player_z,
		"p1vy": player_vel_y,
		"p1a": p1_alive,
		"p1wi": p1_wall_impact,
		"p1fc": p1_fall_committed,
		"p1sw": p1_waiting_for_shark,
		"p1sk": p1_shark_killed,
		"p1oft": p1_ocean_float_time,
		"p1olz": p1_ocean_local_z,
		"p1e": p1_emote,
		"p1mb": p1_moving_back,
		"s1": score,
		# Player 2
		"p2x": player2_x,
		"p2y": player2_y,
		"p2z": player2_z,
		"p2vy": player2_vel_y,
		"p2a": p2_alive,
		"p2wi": p2_wall_impact,
		"p2fc": p2_fall_committed,
		"p2sw": p2_waiting_for_shark,
		"p2sk": p2_shark_killed,
		"p2oft": p2_ocean_float_time,
		"p2olz": p2_ocean_local_z,
		"p2e": p2_emote,
		"p2mb": p2_moving_back,
		"s2": player2_score,
		# World
		"ws": world_scroll_z,
		"wi": current_wall_index,
		"ci": current_index,
		"gs": game_state,
		# Effects
		"cf": correct_flash,
		"wf": wrong_flash,
		"cs": camera_shake,
		"cy": camera_yaw,
		"cp": camera_pitch,
		# Timers
		"got1": game_over_timer,
		"got2": player2_game_over_timer,
		"mt": message_timer,
		"ct": countdown_timer,
		# Text
		"msg": message_text,
		# Goal race
		"gz": goal_z,
		"gw": goal_winner,
		# Streaks & stats
		"st": current_streak,
		"ms": max_streak,
		"ta": total_answered,
		"tw": total_wrong,
		# Wall speed
		"aws": _active_wall_speed,
		# Jump triggers
		"p1j": p1_jump_trigger,
		"p2j": p2_jump_trigger,
	}


func apply_snapshot(data: Dictionary) -> void:
	"""クライアント側: 受信したスナップショットをローカル状態に適用"""
	# Player 1
	player_x = data.get("p1x", player_x)
	player_y = data.get("p1y", player_y)
	player_z = data.get("p1z", player_z)
	player_vel_y = data.get("p1vy", player_vel_y)
	p1_alive = data.get("p1a", p1_alive)
	p1_wall_impact = data.get("p1wi", p1_wall_impact)
	p1_fall_committed = data.get("p1fc", p1_fall_committed)
	p1_waiting_for_shark = data.get("p1sw", p1_waiting_for_shark)
	p1_shark_killed = data.get("p1sk", p1_shark_killed)
	p1_ocean_float_time = data.get("p1oft", p1_ocean_float_time)
	p1_ocean_local_z = data.get("p1olz", p1_ocean_local_z)
	p1_emote = data.get("p1e", p1_emote)
	p1_moving_back = data.get("p1mb", p1_moving_back)
	score = int(data.get("s1", score))
	# Player 2
	player2_x = data.get("p2x", player2_x)
	player2_y = data.get("p2y", player2_y)
	player2_z = data.get("p2z", player2_z)
	player2_vel_y = data.get("p2vy", player2_vel_y)
	p2_alive = data.get("p2a", p2_alive)
	p2_wall_impact = data.get("p2wi", p2_wall_impact)
	p2_fall_committed = data.get("p2fc", p2_fall_committed)
	p2_waiting_for_shark = data.get("p2sw", p2_waiting_for_shark)
	p2_shark_killed = data.get("p2sk", p2_shark_killed)
	p2_ocean_float_time = data.get("p2oft", p2_ocean_float_time)
	p2_ocean_local_z = data.get("p2olz", p2_ocean_local_z)
	p2_emote = data.get("p2e", p2_emote)
	p2_moving_back = data.get("p2mb", p2_moving_back)
	player2_score = int(data.get("s2", player2_score))
	# World
	world_scroll_z = data.get("ws", world_scroll_z)
	current_wall_index = int(data.get("wi", current_wall_index))
	current_index = int(data.get("ci", current_index))
	var new_state: String = data.get("gs", game_state)
	if new_state != game_state:
		game_state = new_state
		state_changed.emit(new_state)
	# Effects
	correct_flash = data.get("cf", correct_flash)
	wrong_flash = data.get("wf", wrong_flash)
	camera_shake = data.get("cs", camera_shake)
	camera_yaw = data.get("cy", camera_yaw)
	camera_pitch = data.get("cp", camera_pitch)
	# Timers
	game_over_timer = data.get("got1", game_over_timer)
	player2_game_over_timer = data.get("got2", player2_game_over_timer)
	message_timer = data.get("mt", message_timer)
	countdown_timer = data.get("ct", countdown_timer)
	# Text
	message_text = data.get("msg", message_text)
	# Goal race
	goal_z = data.get("gz", goal_z)
	goal_winner = int(data.get("gw", goal_winner))
	# Streaks & stats
	current_streak = int(data.get("st", current_streak))
	max_streak = int(data.get("ms", max_streak))
	total_answered = int(data.get("ta", total_answered))
	total_wrong = int(data.get("tw", total_wrong))
	# Wall speed
	_active_wall_speed = data.get("aws", _active_wall_speed)
	# Jump triggers
	p1_jump_trigger = data.get("p1j", p1_jump_trigger)
	p2_jump_trigger = data.get("p2j", p2_jump_trigger)
