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
var llm_mode: String = "OFFLINE"
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

# --- Multiplayer ---
var num_players: int = 1
var p1_alive: bool = true
var player2_x: float = 0.0
var player2_y: float = 0.0
var player2_z: float = 0.0
var player2_score: int = 0
var player2_vel_y: float = 0.0
var p2_alive: bool = true
var player2_game_over_timer: float = 0.0

# --- Dynamic wall speed ---
var _active_wall_speed: float = 6.8

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

var num_choices: int:
	get:
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

func set_wall_speed(speed: float) -> void:
	tuning.wall_speed = clampf(speed, 3.0, 12.0)

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
	player_x = -1.5 if num_players == 2 else 0.0
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
	player2_x = 1.5
	player2_y = 0.0
	player2_z = 0.0
	player2_score = 0
	player2_vel_y = 0.0
	p2_alive = true
	player2_game_over_timer = 0.0
	# Dynamic wall speed reset
	_active_wall_speed = tuning.wall_speed
	var count: int = 10 if mode == Constants.MODE_TEN else 1
	target_count = count

	provider.begin_round(subject, grade, difficulty, mode, count)

	quiz_list = provider.get_quizzes(subject, grade, difficulty, mode, count)
	message_text = ""
	game_state = Constants.STATE_PRELOADING
	preload_wait_sec = 0.0
	refresh_status_text()
	state_changed.emit(game_state)

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
	refresh_status_text()
	state_changed.emit(game_state)


# ---------- Quiz loading ----------

func load_current_quiz() -> void:
	if mode == Constants.MODE_TEN:
		if current_index >= quiz_list.size():
			clear_game()
			return
		current_quiz = quiz_list[current_index]
	else:
		if quiz_list.is_empty():
			quiz_list = provider.get_quizzes(subject, grade, difficulty,
				Constants.MODE_ENDLESS, 1)
		# Guard: if buffer is still empty, transition to PRELOADING
		if quiz_list.is_empty():
			game_state = Constants.STATE_PRELOADING
			preload_wait_sec = 0.0
			message_text = "Loading quizzes..." if use_english_ui else "次の問題を準備中..."
			refresh_status_text()
			state_changed.emit(game_state)
			return
		current_quiz = quiz_list[0]

	choice_locked = false
	message_text = ""
	_recalc_wall_speed()
	refresh_status_text()
	quiz_loaded.emit(current_quiz)

func _recalc_wall_speed() -> void:
	var base: float = tuning.wall_speed
	var q_text: String = ""
	if current_quiz:
		q_text = current_quiz.q if current_quiz.q else ""
		if current_quiz.c.size() > 0:
			for ch: String in current_quiz.c:
				q_text += ch
	var text_len: int = q_text.length()
	var length_factor: float = clampf(1.0 - (text_len - 20) * 0.0045, 0.55, 1.0)
	var final_speed: float = base * length_factor
	_active_wall_speed = clampf(final_speed, tuning.wall_speed_min, tuning.wall_speed_max)


# ---------- Frame update ----------

func update(dt: float, axis_p1: Vector2 = Vector2.ZERO, axis_p2: Vector2 = Vector2.ZERO, jump_p1: bool = false, jump_p2: bool = false) -> void:
	correct_flash = maxf(0.0, correct_flash - dt * 1.5)
	wrong_flash = maxf(0.0, wrong_flash - dt * 1.2)
	camera_shake = maxf(0.0, camera_shake - dt * 2.8)

	if game_state == Constants.STATE_MENU:
		return

	if game_state == Constants.STATE_PRELOADING:
		_update_preloading(dt)
		return

	if game_state == Constants.STATE_PLAYING:
		_update_playing(dt, axis_p1, axis_p2, jump_p1, jump_p2)
		return

	if game_state == Constants.STATE_CORRECT:
		_update_correct(dt)
		return

	if game_state == Constants.STATE_GAME_OVER:
		_update_game_over(dt)

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
	if mode == Constants.MODE_TEN and quiz_list.size() >= target_count:
		ready = true
	elif mode == Constants.MODE_ENDLESS and quiz_list.size() >= 1:
		ready = true

	if ready and preload_wait_sec >= min_preload_sec:
		game_state = Constants.STATE_PLAYING
		load_current_quiz()
		state_changed.emit(game_state)
	elif not ready and preload_wait_sec >= 4.0 and quiz_list.size() > 0:
		if mode == Constants.MODE_TEN:
			target_count = quiz_list.size()
		game_state = Constants.STATE_PLAYING
		load_current_quiz()
		state_changed.emit(game_state)
	else:
		message_text = "Loading quizzes..." if use_english_ui else "クイズを準備中..."
		refresh_status_text()

func _update_playing(dt: float, axis_p1: Vector2, axis_p2: Vector2, jump_p1: bool, jump_p2: bool) -> void:
	world_scroll_z += _active_wall_speed * dt
	
	# Player 1 movement
	if p1_alive:
		var yaw: float = camera_yaw if num_players == 1 else 0.0
		var move_x: float = axis_p1.x * cos(yaw) + axis_p1.y * sin(yaw)
		var move_z: float = axis_p1.y * cos(yaw) - axis_p1.x * sin(yaw)
		
		player_x += move_x * tuning.player_speed * dt
		player_x = clampf(player_x, tuning.min_x, tuning.max_x)
		
		player_z += _active_wall_speed * dt # Carry forward with world scroll
		player_z += move_z * tuning.player_speed * dt
		
		# Constrain local position on the treadmill (Only front is constrained!)
		var loc1 := player_z - world_scroll_z
		loc1 = minf(loc1, 8.0)
		player_z = world_scroll_z + loc1
		
		if jump_p1 and player_y <= 0.0 and loc1 >= -4.0:
			player_vel_y = JUMP_FORCE
		
		player_vel_y -= GRAVITY * dt
		player_y += player_vel_y * dt
		
		if player_y <= 0.0 and loc1 >= -4.0:
			player_y = 0.0
			player_vel_y = 0.0
			
		if player_y < -9.5:
			player_y = -9.5
			player_vel_y = 0.0
			p1_alive = false
			game_over_timer = 0.001
			if num_players == 1 or not p2_alive:
				if current_quiz and not choice_locked:
					choice_locked = true
					provider.submit_result(current_quiz, false)
				_game_over("マグマに落ちてしまった！" if not use_english_ui else "Fell into magma!")
				wrong_answer.emit(message_text)
	else:
		if game_over_timer > 0.0:
			# Stay at same local offset
			pass
			
	# Player 2 movement
	if num_players >= 2 and p2_alive:
		player2_x += axis_p2.x * tuning.player_speed * dt
		player2_x = clampf(player2_x, tuning.min_x, tuning.max_x)
		
		player2_z += _active_wall_speed * dt
		player2_z += axis_p2.y * tuning.player_speed * dt
		
		var loc2 := player2_z - world_scroll_z
		loc2 = minf(loc2, 8.0)
		player2_z = world_scroll_z + loc2
		
		if jump_p2 and player2_y <= 0.0 and loc2 >= -4.0:
			player2_vel_y = JUMP_FORCE
		
		player2_vel_y -= GRAVITY * dt
		player2_y += player2_vel_y * dt
		
		if player2_y <= 0.0 and loc2 >= -4.0:
			player2_y = 0.0
			player2_vel_y = 0.0
			
		if player2_y < -9.5:
			player2_y = -9.5
			player2_vel_y = 0.0
			p2_alive = false
			player2_game_over_timer = 0.001
			if not p1_alive:
				if current_quiz and not choice_locked:
					choice_locked = true
					provider.submit_result(current_quiz, false)
				_game_over("マグマに落ちてしまった！" if not use_english_ui else "Fell into magma!")
				wrong_answer.emit(message_text)
			
	# Check collisions with wall
	if player_z >= wall_z - 0.45 or (num_players >= 2 and player2_z >= wall_z - 0.45):
		# Prevent clipping through
		if player_z >= wall_z - 0.45: player_z = wall_z - 0.45
		if num_players >= 2 and player2_z >= wall_z - 0.45: player2_z = wall_z - 0.45
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


# ---------- Collision ----------

func is_within_door(x_pos: float, side: int) -> bool:
	if num_choices == 4:
		var cx: float = tuning.door4_xs[side]
		return absf(x_pos - cx) <= tuning.door4_half_width
	var center: float = tuning.left_door_x if side == 0 else tuning.right_door_x
	return absf(x_pos - center) <= tuning.door_half_width

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

func resolve_collision() -> void:
	if not current_quiz or choice_locked:
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
		elif door == answer:
			score += 1
			p1_correct = true
			recent_results.append(true)
			if recent_results.size() > 12:
				recent_results.remove_at(0)
		else:
			p1_alive = false
			game_over_timer = 0.001
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
		game_state = Constants.STATE_CORRECT
		message_timer = tuning.correct_hold_sec
		message_text = "Correct!" if use_english_ui else "正解！"
		correct_flash = 1.0
		camera_shake = 0.22
		correct_answer.emit()
		state_changed.emit(game_state)
	else:
		var nc: int = num_choices
		var ans_label: String
		if nc == 4:
			var labels := ["A", "B", "C", "D"]
			ans_label = labels[answer] if answer >= 0 and answer < 4 else "?"
		else:
			ans_label = "左" if answer == 0 else "右"
		_game_over("不正解！ 正解は %s" % ans_label)
		wrong_answer.emit(message_text)

func advance_after_correct() -> void:
	current_wall_index += 1
	game_over_timer = 0.0
	player2_game_over_timer = 0.0
	if mode == Constants.MODE_TEN:
		current_index += 1
		load_current_quiz()
	else:
		quiz_list = provider.get_quizzes(subject, grade, difficulty,
			Constants.MODE_ENDLESS, 1)
		load_current_quiz()
	if game_state != Constants.STATE_PRELOADING:
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

func clear_game() -> void:
	game_state = Constants.STATE_CLEAR
	rating_target_quiz = current_quiz
	rating_feedback = ""
	if num_players >= 2:
		if use_english_ui:
			message_text = "CLEAR! Congrats\n10 questions done\nP1 Score: %d/10  P2 Score: %d/10" % [score, player2_score]
		else:
			message_text = "CLEAR! おめでとう\n10問完走\nP1 正解数: %d/10  P2 正解数: %d/10" % [score, player2_score]
	else:
		if use_english_ui:
			message_text = "CLEAR! Congrats\n10 questions done  Score: %d/10" % score
		else:
			message_text = "CLEAR! おめでとう\n10問完走  正解数: %d/10" % score
	correct_flash = 1.0
	refresh_status_text()
	game_cleared.emit(message_text)
	state_changed.emit(game_state)


# ---------- Rating ----------

func rate_last_question(good: bool) -> void:
	if not rating_target_quiz:
		return
	if good:
		rating_feedback = "Rated: Good" if use_english_ui else "評価: 良い問題"
	else:
		rating_feedback = "Rated: Bad" if use_english_ui else "評価: 悪い問題"
		
	# Save rating to file
	var path := "user://quiz_ratings.json"
	var ratings := []
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var txt := f.get_as_text()
			f.close()
			if not txt.is_empty():
				var parsed = JSON.parse_string(txt)
				if parsed is Array:
					ratings = parsed
	
	ratings.append({
		"q": rating_target_quiz.q,
		"c": rating_target_quiz.c,
		"a": rating_target_quiz.a,
		"good": good,
		"src": rating_target_quiz.src
	})
	
	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(ratings, "  "))
		fw.close()


# ---------- Display helpers ----------

func question_text() -> String:
	if not current_quiz:
		return ""
	return "Q: %s" % current_quiz.q

func choices_text() -> PackedStringArray:
	if not current_quiz:
		return PackedStringArray(["", ""])
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
