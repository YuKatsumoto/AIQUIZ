extends RefCounted
class_name QuizGameState

## ゲーム状態管理クラス
## Python版 game_state.py の QuizGameState (638行) を移植

signal state_changed(new_state: String)
signal quiz_loaded(quiz: QuizItem)
signal correct_answer
signal wrong_answer(message: String)
signal game_cleared(message: String)

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
var flyover_duration: float = 8.5  # フライオーバー全体の秒数 (2フェーズ)
var flyover_total_walls: int = 10

# --- Multiplayer ---
var num_players: int = 1
var p1_alive: bool = true
var p1_emote: int = 0

var player2_x: float = 0.0
var player2_y: float = 0.0
var player2_z: float = 0.0
var player2_score: int = 0
var player2_vel_y: float = 0.0
var p2_alive: bool = true
var p2_emote: int = 0
var p1_moving_back: bool = false
var p2_moving_back: bool = false
var p1_hat: int = 0
var p2_hat: int = 0
var p1_emote_selected: int = 0  # メニューで選択したデフォルトエモートID
var p2_emote_selected: int = 0
# エモートスロット: P1はキー1,2,3 / P2はキー8,9,0 にそれぞれエモートIDを割り当て
var p1_emote_slots: Array[int] = [1, 2, 3]  # デフォルト: Step Hip Hop, Gangnam, Slide
var p2_emote_slots: Array[int] = [1, 2, 3]

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


func _init(quiz_provider: QuizProvider = null) -> void:
	if quiz_provider:
		provider = quiz_provider
	else:
		provider = QuizProvider.new()
	tuning = GameTuning.new()
	refresh_status_text()


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
	return mode == Constants.MODE_TEN or mode == Constants.MODE_TUTORIAL

func _is_tutorial_mode() -> bool:
	return mode == Constants.MODE_TUTORIAL


# ---------- Menu ----------

func select_mode_and_continue(selected_mode: String) -> void:
	if selected_mode in [Constants.MODE_TEN, Constants.MODE_ENDLESS]:
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

func set_bgm_volume(vol: float) -> void:
	bgm_volume = clampf(vol, 0.0, 1.0)

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
	score = 0
	current_index = 0
	quiz_history.clear()
	player_x = 1.5 if num_players == 2 else 0.0
	player_y = 0.0
	player_z = 0.0
	player_vel_y = 0.0
	world_scroll_z = 0.0
	camera_yaw = 0.0
	camera_pitch = 0.0
	current_wall_index = 0
	game_over_timer = 0.0
	p1_alive = true
	# Player 2 reset
	player2_x = -1.5
	player2_y = 0.0
	player2_z = 0.0
	player2_score = 0
	player2_vel_y = 0.0
	p2_alive = true
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
		_active_wall_speed = 28.0 / (4.0 + 1.5)  # VISIBLE_DISTANCE / (default_est + buffer)
	var count: int = 10 if mode == Constants.MODE_TEN else 1
	target_count = count

	provider.begin_round(subject, grade, difficulty, mode, count)

	quiz_list = provider.get_quizzes(subject, grade, difficulty, mode, count)
	message_text = ""
	game_state = Constants.STATE_PRELOADING
	preload_wait_sec = 0.0
	refresh_status_text()
	state_changed.emit(game_state)

func start_tutorial(tutorial_players: int = 1) -> void:
	mode = Constants.MODE_TUTORIAL
	llm_mode = "OFFLINE"
	subject = "チュートリアル"
	grade = 3
	difficulty = "普通"
	num_players = clampi(tutorial_players, 1, 2)
	score = 0
	current_index = 0
	quiz_history.clear()
	player_x = 1.5 if num_players >= 2 else 0.0
	player_y = 0.0
	player_z = 0.0
	player_vel_y = 0.0
	world_scroll_z = 0.0
	camera_yaw = 0.0
	camera_pitch = 0.0
	current_wall_index = 0
	game_over_timer = 0.0
	p1_alive = true
	player2_x = -1.5 if num_players >= 2 else 0.0
	player2_y = 0.0
	player2_z = 0.0
	player2_score = 0
	player2_vel_y = 0.0
	p2_alive = num_players >= 2
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
	target_count = 3
	quiz_list = _build_tutorial_quizzes()
	_active_wall_speed = 3.8
	game_state = Constants.STATE_WAITING_START
	load_current_quiz()
	refresh_status_text()
	state_changed.emit(game_state)

func _build_tutorial_quizzes() -> Array[QuizItem]:
	if num_players >= 2:
		return [
			QuizItem.create(
				"2人練習1: 2人で左ドアへ",
				PackedStringArray(["左", "右"]),
				0,
				"P1はA、P2は←で左へ移動します。2人とも左ドアを抜けましょう。",
				"TUTORIAL",
				"",
				PackedStringArray(),
				7.0
			),
			QuizItem.create(
				"2人練習2: 2人で右ドアへ",
				PackedStringArray(["左", "右"]),
				1,
				"P1はD、P2は→で右へ移動します。今度は2人とも右ドアです。",
				"TUTORIAL",
				"",
				PackedStringArray(),
				7.0
			),
			QuizItem.create(
				"2人練習3: 正解ドアを一緒に抜けよう",
				PackedStringArray(["協力して進む", "止まる"]),
				0,
				"2人とも正解ドアを抜けると、壁が壊れてクリアできます。",
				"TUTORIAL",
				"",
				PackedStringArray(),
				7.0
			)
		]
	return [
		QuizItem.create(
			"練習1: 2 + 3 = ?",
			PackedStringArray(["5", "6"]),
			0,
			"2に3を足すと5です。左のドアへ移動して抜けましょう。",
			"TUTORIAL",
			"",
			PackedStringArray(),
			7.0
		),
		QuizItem.create(
			"練習2: 右のドアに入ってみよう",
			PackedStringArray(["左", "右"]),
			1,
			"今度は右側のドアを選ぶ練習です。",
			"TUTORIAL",
			"",
			PackedStringArray(),
			7.0
		),
		QuizItem.create(
			"練習3: 正解ドアを通るとどうなる？",
			PackedStringArray(["次へ進める", "ゲームが止まる"]),
			0,
			"正解ドアを抜けると壁が壊れて次へ進めます。",
			"TUTORIAL",
			"",
			PackedStringArray(),
			7.0
		)
	]

func reset_to_menu() -> void:
	provider.end_round()
	game_state = Constants.STATE_MENU
	menu_step = Constants.MENU_STEP_MODE
	player_x = 0.0
	player_y = 0.0
	player_z = 0.0
	player_vel_y = 0.0
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
	player2_x = 0.0
	player2_y = 0.0
	player2_z = 0.0
	player2_score = 0
	player2_vel_y = 0.0
	p2_alive = true
	player2_game_over_timer = 0.0
	rating_target_quiz = null
	rating_feedback = ""
	quiz_history.clear()
	refresh_status_text()
	state_changed.emit(game_state)


# ---------- Quiz loading ----------

func load_current_quiz() -> void:
	if _is_fixed_count_mode():
		if current_index >= quiz_list.size():
			if current_index >= target_count:
				# 2P: ゴールラインまでのレースへ移行
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

	# Handle 4-to-2 conversion for offline quizzes or any quiz with too many choices
	if num_choices == 2 and current_quiz.c.size() > 2:
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

	# 協力モード: CoopQuizBuilder で P1/P2 分担データを生成
	if is_coop_mode() and current_quiz and not current_quiz.has_coop_data():
		current_quiz = CoopQuizBuilder.build_coop_quiz(current_quiz, subject, grade)

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
	const MOVE_BUFFER: float = 1.5        # ドアまで移動する余白（秒）

	var target_time: float = est_sec + MOVE_BUFFER
	var base_speed: float = VISIBLE_DISTANCE / target_time

	# --- ステージ加速 ---
	var stage_factor: float = 1.0
	if mode == Constants.MODE_TEN:
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

	p1_jump_trigger = false
	p2_jump_trigger = false

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
	if mode == Constants.MODE_TEN:
		missing = maxi(0, target_count - quiz_list.size())
	else:
		missing = 1
	if missing > 0:
		var new_quizzes := provider.get_quizzes(subject, grade, difficulty, mode, missing)
		quiz_list.append_array(new_quizzes)

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
		if mode == Constants.MODE_TEN and quiz_list.size() >= target_count:
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
	elif not ready and preload_wait_sec >= 2.5 and mode != Constants.MODE_TEN and quiz_list.size() > current_index:
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
			if mode == Constants.MODE_TEN:
				var q_count = mini(quiz_list.size(), target_count)
				message_text = "Generating quizzes... (%d/%d)" % [q_count, target_count] if use_english_ui else "AIクイズ生成中... (%d/%d)" % [q_count, target_count]
			else:
				message_text = "Loading quizzes..." if use_english_ui else "クイズを準備中..."
		refresh_status_text()

func _update_waiting_start(dt: float, axis_p1: Vector2, axis_p2: Vector2, jump_p1: bool, jump_p2: bool, emote_p1: int = 0, emote_p2: int = 0) -> void:
	p1_emote = emote_p1
	p2_emote = emote_p2
func trigger_start() -> void:
	if game_state == Constants.STATE_WAITING_START:
		if _is_tutorial_mode():
			game_state = Constants.STATE_COUNTDOWN
			countdown_timer = 3.99
			state_changed.emit(game_state)
			return

		game_state = Constants.STATE_FLYOVER
		flyover_timer = 0.0

		if mode == Constants.MODE_TEN:
			# 10問モード: 全壁を見せる
			flyover_total_walls = target_count
			flyover_duration = 8.5
		else:
			# エンドレスモード: 見えなくなるくらい遠くまで壁を並べる
			flyover_total_walls = 25
			flyover_duration = 8.5
		state_changed.emit(game_state)

func _update_flyover(dt: float, emote_p1: int = 0, emote_p2: int = 0) -> void:
	p1_emote = emote_p1
	p2_emote = emote_p2
	flyover_timer += dt
	if flyover_timer >= flyover_duration:
		# フライオーバー完了 → カウントダウンへ
		game_state = Constants.STATE_COUNTDOWN
		countdown_timer = 3.99
		state_changed.emit(game_state)

func _update_countdown(dt: float, emote_p1: int = 0, emote_p2: int = 0) -> void:
	p1_emote = emote_p1
	p2_emote = emote_p2
	countdown_timer -= dt
	if countdown_timer <= 0:
		game_state = Constants.STATE_PLAYING
		state_changed.emit(game_state)


func _update_playing(dt: float, axis_p1: Vector2, axis_p2: Vector2, jump_p1: bool, jump_p2: bool, emote_p1: int = 0, emote_p2: int = 0) -> void:
	play_time += dt
	world_scroll_z += _active_wall_speed * dt

	p1_emote = emote_p1
	p2_emote = emote_p2
	p1_moving_back = axis_p1.y < -0.1
	p2_moving_back = axis_p2.y < -0.1

	# Player 1 movement
	if p1_alive:
		var yaw: float = camera_yaw if num_players == 1 else 0.0
		var move_x: float = axis_p1.x * cos(yaw) + axis_p1.y * sin(yaw)
		var move_z: float = axis_p1.y * cos(yaw) - axis_p1.x * sin(yaw)

		player_x += move_x * tuning.player_speed * dt
		# Removed clamp to allow falling off sides

		player_z += _active_wall_speed * dt # Carry forward with world scroll
		player_z += move_z * tuning.player_speed * dt

		# Removed forward limit to allow running ahead
		var loc1 := player_z - world_scroll_z

		var is_on_floor = (absf(player_x) <= 12.0) and (loc1 >= -4.5 and loc1 <= 139.5)

		if jump_p1 and player_y <= 0.0 and is_on_floor:
			p1_jump_trigger = true
			player_vel_y = JUMP_FORCE

		player_vel_y -= GRAVITY * dt
		player_y += player_vel_y * dt

		if player_y <= 0.0 and is_on_floor:
			player_y = 0.0
			player_vel_y = 0.0

		if player_y < -8.0:
			if _is_tutorial_mode():
				if num_players >= 2:
					_reset_tutorial_attempt("P1が床から落ちました。2人ともスタート位置へ戻して、同じ壁でもう一度練習しましょう。")
				else:
					_reset_tutorial_attempt("床から落ちました。中央に戻して、同じ壁でもう一度練習しましょう。")
				return
			player_y = -8.0
			player_vel_y = 0.0
			p1_alive = false
			game_over_timer = 0.001
			if num_players == 1 or not p2_alive:
				if current_quiz and not choice_locked:
					choice_locked = true
					provider.submit_result(current_quiz, false)
					quiz_history.append({"quiz": current_quiz, "correct": false, "rated": ""})
				_game_over("マグマに落ちてしまった！" if not use_english_ui else "Fell into magma!")
				wrong_answer.emit(message_text)
	else:
		if game_over_timer > 0.0:
			# Tick explosion timer for dead P1 while game continues (2P)
			game_over_timer += dt

	# Player 2 movement
	if num_players >= 2 and p2_alive:
		player2_x += axis_p2.x * tuning.player_speed * dt
		# Removed clamp

		player2_z += _active_wall_speed * dt
		player2_z += axis_p2.y * tuning.player_speed * dt

		# Removed forward limit
		var loc2 := player2_z - world_scroll_z

		var p2_is_on_floor = (absf(player2_x) <= 12.0) and (loc2 >= -4.5 and loc2 <= 139.5)

		if jump_p2 and player2_y <= 0.0 and p2_is_on_floor:
			p2_jump_trigger = true
			player2_vel_y = JUMP_FORCE

		player2_vel_y -= GRAVITY * dt
		player2_y += player2_vel_y * dt

		if player2_y <= 0.0 and p2_is_on_floor:
			player2_y = 0.0
			player2_vel_y = 0.0

		if player2_y < -8.0:
			if _is_tutorial_mode():
				_reset_tutorial_attempt("P2が床から落ちました。2人ともスタート位置へ戻して、同じ壁でもう一度練習しましょう。")
				return
			player2_y = -8.0
			player2_vel_y = 0.0
			p2_alive = false
			player2_game_over_timer = 0.001
			if not p1_alive:
				if current_quiz and not choice_locked:
					choice_locked = true
					provider.submit_result(current_quiz, false)
					quiz_history.append({"quiz": current_quiz, "correct": false, "rated": ""})
				_game_over("マグマに落ちてしまった！" if not use_english_ui else "Fell into magma!")
				wrong_answer.emit(message_text)
	elif num_players >= 2 and not p2_alive:
		if player2_game_over_timer > 0.0:
			# Tick explosion timer for dead P2 while game continues
			player2_game_over_timer += dt

	# Check collisions with wall
	if player_z >= wall_z - 0.8 or (num_players >= 2 and player2_z >= wall_z - 0.8):
		# Prevent clipping through
		if player_z >= wall_z - 0.8: player_z = wall_z - 0.8
		if num_players >= 2 and player2_z >= wall_z - 0.8: player2_z = wall_z - 0.8
		resolve_collision()

func _update_correct(dt: float) -> void:
	message_timer -= dt
	# Tick explosion for dead players
	if not p1_alive and game_over_timer > 0:
		game_over_timer += dt
	if num_players >= 2 and not p2_alive and player2_game_over_timer > 0:
		player2_game_over_timer += dt
	if message_timer <= 0:
		advance_after_correct()

func _update_game_over(dt: float) -> void:
	game_over_timer += dt
	if num_players >= 2 and not p2_alive:
		player2_game_over_timer += dt

	# Update message with async explanation
	if current_quiz:
		var explain: String = current_quiz.e if current_quiz.e else \
			("No explanation" if use_english_ui else "解説なし")
		var msg: String = "%s\n%s" % [game_over_base_msg, explain]
		if num_players >= 2:
			var score_line := "P1: %d  P2: %d" % [score, player2_score]
			message_text = "GAME OVER\n\n%s\n\n%s" % [msg, score_line]
		else:
			message_text = "GAME OVER\n\n%s" % msg


# ---------- Goal Race (2P 10問モード) ----------

func _start_goal_race() -> void:
	# ゴールラインは最後の壁の先に配置
	goal_z = tuning.wall_start_z + target_count * tuning.wall_spacing + 15.0
	goal_winner = 0
	game_state = Constants.STATE_GOAL_RACE
	message_text = "GOAL へ走れ！" if not use_english_ui else "Race to the GOAL!"
	state_changed.emit(game_state)

func _update_goal_race(dt: float, axis_p1: Vector2, axis_p2: Vector2, jump_p1: bool, jump_p2: bool, emote_p1: int = 0, emote_p2: int = 0) -> void:
	play_time += dt
	# world_scroll_z += _active_wall_speed * dt  # ゴールの動きを止めるためスクロールを停止

	p1_emote = emote_p1
	p2_emote = emote_p2
	p1_moving_back = axis_p1.y < -0.1
	p2_moving_back = axis_p2.y < -0.1

	# Player 1 movement
	if p1_alive:
		player_x += axis_p1.x * tuning.player_speed * dt
		player_z += _active_wall_speed * dt
		player_z += axis_p1.y * tuning.player_speed * dt

		var loc1 := player_z - world_scroll_z
		var is_on_floor = (absf(player_x) <= 12.0) and (loc1 >= -4.5 and loc1 <= 400.0)

		if jump_p1 and player_y <= 0.0 and is_on_floor:
			p1_jump_trigger = true
			player_vel_y = JUMP_FORCE
		player_vel_y -= GRAVITY * dt
		player_y += player_vel_y * dt
		if player_y <= 0.0 and is_on_floor:
			player_y = 0.0
			player_vel_y = 0.0
		if player_y < -8.0:
			player_y = -8.0
			player_vel_y = 0.0
			p1_alive = false
			game_over_timer = 0.001

	# Player 2 movement
	if p2_alive:
		player2_x += axis_p2.x * tuning.player_speed * dt
		player2_z += _active_wall_speed * dt
		player2_z += axis_p2.y * tuning.player_speed * dt

		var loc2 := player2_z - world_scroll_z
		var p2_is_on_floor = (absf(player2_x) <= 12.0) and (loc2 >= -4.5 and loc2 <= 400.0)

		if jump_p2 and player2_y <= 0.0 and p2_is_on_floor:
			p2_jump_trigger = true
			player2_vel_y = JUMP_FORCE
		player2_vel_y -= GRAVITY * dt
		player2_y += player2_vel_y * dt
		if player2_y <= 0.0 and p2_is_on_floor:
			player2_y = 0.0
			player2_vel_y = 0.0
		if player2_y < -8.0:
			player2_y = -8.0
			player2_vel_y = 0.0
			p2_alive = false
			player2_game_over_timer = 0.001

	# Tick explosion timers for dead players
	if not p1_alive and game_over_timer > 0:
		game_over_timer += dt
	if not p2_alive and player2_game_over_timer > 0:
		player2_game_over_timer += dt

	# ゴール判定
	var p1_reached := p1_alive and player_z >= goal_z
	var p2_reached := p2_alive and player2_z >= goal_z

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
		clear_game()
		return

	# 両方死んだ場合
	if not p1_alive and not p2_alive:
		# スコアで勝敗を決定
		if score > player2_score:
			goal_winner = 1
		elif player2_score > score:
			goal_winner = 2
		else:
			goal_winner = 0
		clear_game()
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

	choice_locked = true
	var door := _check_player_door(player_x)
	if door == current_quiz.a:
		score += 1
		current_streak += 1
		max_streak = maxi(max_streak, current_streak)
		total_answered += 1
		recent_results.append(true)
		if recent_results.size() > 12:
			recent_results.remove_at(0)
		quiz_history.append({"quiz": current_quiz, "correct": true, "rated": "tutorial"})
		correct_flash = 1.0
		camera_shake = 0.18
		message_text = _tutorial_correct_message()
		correct_answer.emit()
		advance_after_correct()
		return

	total_answered += 1
	total_wrong += 1
	current_streak = 0
	recent_results.append(false)
	if recent_results.size() > 12:
		recent_results.remove_at(0)

	var hint := ""
	if door < 0:
		hint = "ドアから外れて壁にぶつかりました。ドアの中央をねらって、もう一度進みましょう。"
	else:
		var labels := ["左", "右"]
		var correct_label: String = "正解"
		if current_quiz.a >= 0 and current_quiz.a < labels.size():
			correct_label = labels[current_quiz.a]
		hint = "そのドアは不正解です。今回は %s のドアをねらってみましょう。" % correct_label
	_reset_tutorial_attempt(hint)

func _resolve_tutorial_collision_2p() -> void:
	var p1_at_wall := p1_alive and player_z >= wall_z - 0.8
	var p2_at_wall := p2_alive and player2_z >= wall_z - 0.8
	if not (p1_at_wall and p2_at_wall):
		choice_locked = false
		if p1_at_wall:
			message_text = "P1はドア前で待機中です。P2も同じドアへ進みましょう。"
		elif p2_at_wall:
			message_text = "P2はドア前で待機中です。P1も同じドアへ進みましょう。"
		return

	choice_locked = true
	var p1_door := _check_player_door(player_x)
	var p2_door := _check_player_door(player2_x)
	var answer := current_quiz.a
	var p1_correct := p1_door == answer
	var p2_correct := p2_door == answer
	if p1_correct and p2_correct:
		score += 1
		player2_score += 1
		current_streak += 1
		max_streak = maxi(max_streak, current_streak)
		total_answered += 1
		recent_results.append(true)
		if recent_results.size() > 12:
			recent_results.remove_at(0)
		quiz_history.append({"quiz": current_quiz, "correct": true, "rated": "tutorial"})
		correct_flash = 1.0
		camera_shake = 0.18
		message_text = _tutorial_correct_message()
		correct_answer.emit()
		advance_after_correct()
		return

	total_answered += 1
	total_wrong += 1
	current_streak = 0
	recent_results.append(false)
	if recent_results.size() > 12:
		recent_results.remove_at(0)

	var misses: Array[String] = []
	if not p1_correct:
		misses.append(_tutorial_player_miss_text("P1", p1_door, answer))
	if not p2_correct:
		misses.append(_tutorial_player_miss_text("P2", p2_door, answer))
	var hint := misses[0]
	if misses.size() > 1:
		hint += " / " + misses[1]
	hint += " 今回は %s ドアを2人で抜けましょう。" % _tutorial_answer_label(answer)
	_reset_tutorial_attempt(hint)

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

func _reset_tutorial_attempt(hint: String) -> void:
	var reset_z := float(current_wall_index) * tuning.wall_spacing
	player_x = 1.5 if num_players >= 2 else 0.0
	player_y = 0.0
	player_z = reset_z
	player_vel_y = 0.0
	world_scroll_z = reset_z
	p1_alive = true
	game_over_timer = 0.0
	if num_players >= 2:
		player2_x = -1.5
		player2_y = 0.0
		player2_z = reset_z
		player2_vel_y = 0.0
		p2_alive = true
		player2_game_over_timer = 0.0
	else:
		p2_alive = false
	choice_locked = false
	wrong_flash = 1.0
	camera_shake = 0.16
	message_text = hint
	refresh_status_text()
	state_changed.emit(game_state)

func _tutorial_correct_message() -> String:
	if num_players >= 2:
		if current_index == 0:
			return "2人とも左ドアを抜けました。次は右ドアを練習します。"
		if current_index == 1:
			return "いい連携です。最後は問題を読んで同じ正解ドアへ進みましょう。"
		return "2人プレイ チュートリアル完了！"
	if current_index == 0:
		return "正解！ ドアを抜けられました。次は右のドアを練習します。"
	if current_index == 1:
		return "いい感じです。最後は本番に近い問題を抜けましょう。"
	return "チュートリアル完了！"

func _resolve_coop_collision() -> void:
	## 協力モード専用の衝突判定
	## P1は左半分（coop_p1_door_xs）、P2は右半分（coop_p2_door_xs）で個別判定
	## 両方正解して初めてクリア
	if not current_quiz or not current_quiz.has_coop_data():
		# フォールバック: 通常の判定
		choice_locked = true
		return
	
	choice_locked = true
	var p1_correct := false
	var p2_correct := false
	
	# --- P1 判定（式/ヒント/読み を選ぶ側） ---
	if p1_alive:
		var p1_door: int = _check_coop_p1_door(player_x)
		if p1_door < 0:
			# 壁にぶつかった
			p1_alive = false
			game_over_timer = 0.001
		elif p1_door == current_quiz.coop_p1_answer:
			p1_correct = true
			score += 1
		else:
			# 不正解ドア
			p1_alive = false
			game_over_timer = 0.001
	
	# --- P2 判定（答え/名称/漢字 を選ぶ側） ---
	if p2_alive:
		var p2_door: int = _check_coop_p2_door(player2_x)
		if p2_door < 0:
			p2_alive = false
			player2_game_over_timer = 0.001
		elif p2_door == current_quiz.coop_p2_answer:
			p2_correct = true
			player2_score += 1
		else:
			p2_alive = false
			player2_game_over_timer = 0.001
	
	# 協力モード: 両方正解で進行、片方でも不正解なら両方不正解扱い
	var both_correct: bool = p1_correct and p2_correct
	
	# 記録
	total_answered += 1
	if not both_correct:
		total_wrong += 1
		current_streak = 0
	else:
		current_streak += 1
		if current_streak > max_streak:
			max_streak = current_streak
	recent_results.append(both_correct)
	if recent_results.size() > 12:
		recent_results.remove_at(0)
	
	provider.submit_result(current_quiz, both_correct)
	quiz_history.append({"quiz": current_quiz, "correct": both_correct, "rated": ""})
	
	QuizManager.quiz_optimizer.evaluate_history(quiz_history, subject, grade, difficulty)
	
	if current_quiz:
		var response_time: float = (Time.get_ticks_msec() - _quiz_shown_time) / 1000.0
		recent_response_times.append(response_time)
		if recent_response_times.size() > 5:
			recent_response_times.pop_front()
	
	if both_correct:
		# 両方正解！ 進行
		correct_flash = 1.0
		camera_shake = 0.22
		message_text = "協力成功！"
		correct_answer.emit()
		advance_after_correct()
	elif p1_correct and not p2_correct:
		# P1は正解したがP2が失敗 → 協力失敗、P1も道連れ
		p1_alive = false
		game_over_timer = 0.001
		_game_over("P2が不正解！ 協力失敗...")
		wrong_answer.emit(message_text)
	elif p2_correct and not p1_correct:
		# P2は正解したがP1が失敗 → 協力失敗、P2も道連れ
		p2_alive = false
		player2_game_over_timer = 0.001
		_game_over("P1が不正解！ 協力失敗...")
		wrong_answer.emit(message_text)
	else:
		# 両方不正解
		_game_over("両方不正解！ 協力失敗...")
		wrong_answer.emit(message_text)

func resolve_collision() -> void:
	if not current_quiz or choice_locked:
		return
	if _is_tutorial_mode():
		_resolve_tutorial_collision()
		return
	if is_coop_mode():
		_resolve_coop_collision()
		return
	choice_locked = true
	var answer: int = current_quiz.a

	var p1_correct: bool = false
	var p2_correct: bool = false

	# --- Player 1 ---
	if p1_alive:
		var door: int = _check_player_door(player_x)
		if door < 0:
			p1_alive = false
			game_over_timer = 0.001
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
			p1_alive = false
			game_over_timer = 0.001
			current_streak = 0
			total_answered += 1
			total_wrong += 1
			recent_results.append(false)
			if recent_results.size() > 12:
				recent_results.remove_at(0)

	# --- Player 2 ---
	if num_players >= 2 and p2_alive:
		var door2: int = _check_player_door(player2_x)
		if door2 < 0:
			p2_alive = false
			player2_game_over_timer = 0.001
		elif door2 == answer:
			player2_score += 1
			p2_correct = true
		else:
			p2_alive = false
			player2_game_over_timer = 0.001

	var any_correct: bool = p1_correct or p2_correct
	var any_alive: bool = p1_alive or (num_players >= 2 and p2_alive)

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
			var chosen_door: int = _check_player_door(player_x) if p1_alive or not p1_correct else current_quiz.a
			QuizManager.player_analytics.record(
				current_quiz, response_time, any_correct, chosen_door,
				subject, grade, difficulty
			)

	if not any_alive:
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
	elif any_correct:
		# No-stop: stay in STATE_PLAYING and advance immediately
		correct_flash = 1.0
		camera_shake = 0.22
		message_text = "Correct!" if use_english_ui else "正解！"
		correct_answer.emit()
		advance_after_correct()
	else:
		var nc2: int = num_choices
		var ans_label2: String
		if nc2 == 4:
			var labels2 := ["A", "B", "C", "D"]
			ans_label2 = labels2[answer] if answer >= 0 and answer < 4 else "?"
		else:
			ans_label2 = "左" if answer == 0 else "右"
		_game_over("不正解！ 正解は %s" % ans_label2)
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
		if missing > 0 and mode == Constants.MODE_TEN:
			var new_quizzes := provider.get_quizzes(subject, grade, difficulty, mode, missing)
			quiz_list.append_array(new_quizzes)
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
	rating_target_quiz = current_quiz
	rating_feedback = ""
	game_over_base_msg = msg
	var explain: String = current_quiz.e if current_quiz else \
		("No explanation" if use_english_ui else "解説なし")
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
	rating_target_quiz = current_quiz
	rating_feedback = ""
	if _is_tutorial_mode():
		rating_target_quiz = null
		if num_players >= 2:
			message_text = "TUTORIAL CLEAR!\n2人で3つの壁を抜けました\nメニューからいつでも復習できます"
		else:
			message_text = "TUTORIAL CLEAR!\n3つの壁を抜けました\nメニューからいつでも復習できます"
		correct_flash = 1.0
		GameManager.mark_tutorial_completed()
		refresh_status_text()
		game_cleared.emit(message_text)
		state_changed.emit(game_state)
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
			status_text = "Score: %d  |  Press [R] for menu" % score
		else:
			status_text = "正解数: %d  |  [R] でメニューへ戻る" % score
		return

	if game_state == Constants.STATE_MENU:
		if use_english_ui:
			if menu_step == Constants.MENU_STEP_MODE:
				status_text = "Step 1/3: Select mode"
			else:
				var mode_label: String = "10 Q" if mode == Constants.MODE_TEN else "Endless"
				status_text = "Step 2/3: Set grade/subject  |  Mode:%s Subject:%s Grade:%d" % [
					mode_label,
					Constants.SUBJECT_EN.get(subject, subject),
					grade
				]
		else:
			if menu_step == Constants.MENU_STEP_MODE:
				status_text = "手順 1/3: モードを選択"
			else:
				var mode_label: String = "10問チャレンジ" if mode == Constants.MODE_TEN else "エンドレス"
				status_text = "手順 2/3: 学年・教科を設定  |  モード:%s  教科:%s  学年:%d" % [
					mode_label, subject, grade
				]
		return

	if game_state == Constants.STATE_PRELOADING:
		if use_english_ui:
			if mode == Constants.MODE_TEN:
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
			if mode == Constants.MODE_TEN:
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
		var progress_tutorial := "%d/%d" % [mini(current_index + 1, target_count), target_count]
		if num_players >= 2:
			status_text = "2P 3Dチュートリアル  進行:%s  P1:%d  P2:%d" % [
				progress_tutorial, score, player2_score
			]
		else:
			status_text = "3Dチュートリアル  進行:%s  正解:%d" % [progress_tutorial, score]
		return

	if use_english_ui:
		var mode_label: String = "10 Q" if mode == Constants.MODE_TEN else "Endless"
		var progress: String = "%d/10" % (current_index + 1) if mode == Constants.MODE_TEN else "inf"
		var subj: String = Constants.SUBJECT_EN.get(subject, subject)
		var diff: String = Constants.DIFFICULTY_EN.get(difficulty, difficulty)
		status_text = "Subject:%s Grade:%d Diff:%s Mode:%s Progress:%s Score:%d" % [
			subj, grade, diff, mode_label, progress, score
		]
	else:
		var mode_label: String = "10問チャレンジ" if mode == Constants.MODE_TEN else "エンドレス"
		var progress: String = "%d/10" % (current_index + 1) if mode == Constants.MODE_TEN else "∞"
		status_text = "教科:%s  学年:%d  難易度:%s  モード:%s  進行:%s  正解数:%d" % [
			subject, grade, difficulty, mode_label, progress, score
		]

func tutorial_instruction_text() -> String:
	if not _is_tutorial_mode():
		return ""
	if game_state == Constants.STATE_WAITING_START:
		if num_players >= 2:
			return "2人プレイ チュートリアル: 同じ正解ドアを抜ける練習"
		return "3Dチュートリアル: 実際に壁を抜ける練習"
	if game_state == Constants.STATE_COUNTDOWN:
		if num_players >= 2:
			return "P1はWASD、P2は矢印キーで動きます"
		return "カウントダウン後、壁が近づいてきます"
	if game_state == Constants.STATE_PLAYING:
		if num_players >= 2:
			match current_index:
				0:
					return "練習1: P1はA、P2は←で左ドアへ"
				1:
					return "練習2: P1はD、P2は→で右ドアへ"
				_:
					return "練習3: 2人で問題を読んで正解ドアへ"
		else:
			match current_index:
				0:
					return "練習1: A / ← で左の正解ドアへ移動"
				1:
					return "練習2: D / → で右の正解ドアへ移動"
				_:
					return "練習3: 問題を読んで正解ドアへ移動"
	if game_state == Constants.STATE_CLEAR:
		if num_players >= 2:
			return "2人プレイ チュートリアル完了"
		return "チュートリアル完了"
	return ""

func tutorial_detail_text() -> String:
	if not _is_tutorial_mode():
		return ""
	if game_state == Constants.STATE_WAITING_START:
		if num_players >= 2:
			return "任意のキーで開始です。上のガイドでエモートキーと設定方法も確認できます。"
		return "任意のキーを押すと、3秒後に練習開始です。上のガイドでエモートキーと設定方法も確認できます。"
	if game_state == Constants.STATE_COUNTDOWN:
		if num_players >= 2:
			return "P1はSpace、P2はCtrlまたはNum0でジャンプ。エモートはP1:1/2/3、P2:8/9/0です。"
		return "問題文は画面上、答えは壁のドアに表示されます。エモートは1/2/3で出せます。"
	if game_state == Constants.STATE_PLAYING:
		if not message_text.is_empty() and (wrong_flash > 0.0 or num_players >= 2):
			return message_text
		if num_players >= 2:
			match current_index:
				0:
					return "左のドアに2人とも入ります。P1はA、P2は←を押して寄りましょう。"
				1:
					return "今度は右のドアです。P1はD、P2は→で右へ寄りましょう。"
				_:
					return "壁の表示を見て、2人とも同じ正解ドアを抜けましょう。"
		else:
			match current_index:
				0:
					return "2 + 3 の答え「5」は左ドアです。左へ寄って壁を抜けましょう。"
				1:
					return "今度は右側のドアを選びます。右へ移動して通過しましょう。"
				_:
					return "正解ドアを抜けると壁が壊れ、次へ進めることを確認しましょう。"
	if game_state == Constants.STATE_CLEAR:
		if num_players >= 2:
			return "メニューに戻って、2人プレイの10問チャレンジにも挑戦できます。"
		return "メニューに戻って、10問チャレンジやエンドレスに挑戦できます。"
	return ""

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
		"p1e": p1_emote,
		"p1mb": p1_moving_back,
		"s1": score,
		# Player 2
		"p2x": player2_x,
		"p2y": player2_y,
		"p2z": player2_z,
		"p2vy": player2_vel_y,
		"p2a": p2_alive,
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
	p1_emote = data.get("p1e", p1_emote)
	p1_moving_back = data.get("p1mb", p1_moving_back)
	score = int(data.get("s1", score))
	# Player 2
	player2_x = data.get("p2x", player2_x)
	player2_y = data.get("p2y", player2_y)
	player2_z = data.get("p2z", player2_z)
	player2_vel_y = data.get("p2vy", player2_vel_y)
	p2_alive = data.get("p2a", p2_alive)
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
