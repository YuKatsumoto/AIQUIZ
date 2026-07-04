extends RefCounted
class_name DemoAIDriver

## メインメニュー背景のアトラクトデモ用AIプレイヤー
## game_world (demo_mode) が毎フレーム compute(dt) を呼び、
## 返り値の axis/jump/emote をそのまま game_state.update() に渡す。
## 状態遷移(trigger_start/リスタート)もここが面倒を見る。

const RESTART_DELAY: float = 4.5     # GAME_OVER/CLEAR からリスタートまでの間
const START_DELAY: float = 1.5       # WAITING_START で開始を押すまでの間
const DEMO_FLYOVER_SEC: float = 2.0  # デモではフライオーバーを短縮
const DEMO_COUNTDOWN_SEC: float = 1.8

var gs: QuizGameState

var _round_count: int = 0
var _wait_timer: float = 0.0
var _restart_timer: float = 0.0
var _reaction_timer: float = 0.0     # 出題後の「考えている」間
var _wobble_time: float = 0.0
var _jump_queued: bool = false
var _prev_state: String = ""
var _emote_timer: float = 0.0
var _current_emote: int = 0
# 一定問数でわざと間違える → ラグドール爆発 → リスタートで教科・難易度が変わる
# (エンドレスの1ランを有限にして演出と内容のローテーションを回すため)
var _questions_until_miss: int = 12
var _miss_this_question: bool = false

func setup(state: QuizGameState) -> void:
	gs = state
	gs.quiz_loaded.connect(_on_quiz_loaded)
	gs.correct_answer.connect(_on_correct)

func restart_game() -> void:
	gs.mode = Constants.MODE_ENDLESS
	gs.num_players = 1
	gs.llm_mode = "OFFLINE"
	gs.subject = Constants.SUBJECTS[_round_count % Constants.SUBJECTS.size()]
	gs.grade = randi_range(1, 6)
	gs.difficulty = "難しい" if _round_count % 3 == 2 else "普通"
	_round_count += 1
	_questions_until_miss = randi_range(10, 14)
	_miss_this_question = false
	_wait_timer = 0.0
	_restart_timer = 0.0
	_reaction_timer = 0.0
	print("[Demo] ラン開始: %s 小%d %s" % [gs.subject, gs.grade, gs.difficulty])
	gs.start_game()

func compute(dt: float) -> Dictionary:
	var axis := Vector2.ZERO
	var jump := false
	var emote := 0
	if gs == null:
		return {"axis": axis, "jump": jump, "emote": emote}

	match gs.game_state:
		Constants.STATE_WAITING_START:
			_wait_timer += dt
			emote = _idle_emote(dt)
			if _wait_timer >= START_DELAY:
				_wait_timer = 0.0
				gs.trigger_start()
				# trigger_start が 3.8 を再セットするため呼び出し後に短縮
				gs.flyover_duration = DEMO_FLYOVER_SEC
		Constants.STATE_FLYOVER:
			emote = _idle_emote(dt)
		Constants.STATE_COUNTDOWN:
			if _prev_state != Constants.STATE_COUNTDOWN:
				gs.countdown_timer = minf(gs.countdown_timer, DEMO_COUNTDOWN_SEC)
		Constants.STATE_PLAYING:
			axis = _steer(dt)
			if _jump_queued:
				jump = true
				_jump_queued = false
		Constants.STATE_GAME_OVER, Constants.STATE_CLEAR:
			_restart_timer += dt
			if _restart_timer >= RESTART_DELAY:
				_restart_timer = 0.0
				restart_game()

	_prev_state = gs.game_state
	return {"axis": axis, "jump": jump, "emote": emote}

func _on_quiz_loaded(quiz: QuizItem) -> void:
	# 「読んで考えている」風の間。難しい問題ほど少し長く迷う
	_reaction_timer = randf_range(0.6, 1.4)
	if quiz:
		_reaction_timer += clampf((quiz.estimated_seconds - 4.0) * 0.15, 0.0, 0.8)
	_miss_this_question = _questions_until_miss <= 0

func _on_correct() -> void:
	_questions_until_miss -= 1
	print("[Demo] 正解 score=%d (miss まで残り %d 問)" % [gs.score, _questions_until_miss])
	if randf() < 0.25:
		_jump_queued = true

func _steer(dt: float) -> Vector2:
	if gs.current_quiz == null:
		return Vector2.ZERO
	if _reaction_timer > 0.0:
		_reaction_timer -= dt
		return Vector2.ZERO

	_wobble_time += dt
	var door_idx: int = gs.current_quiz.a
	if _miss_this_question:
		door_idx = (door_idx + 1) % gs.num_choices
	var target_x: float = _door_x(door_idx)

	var diff: float = target_x - gs.player_x
	var time_left: float = (gs.wall_z - 0.4 - gs.player_z) / maxf(gs._active_wall_speed, 0.1)
	if time_left <= 1.2:
		# 壁が近い: 揺らぎなしで確実にドアへ
		return Vector2(clampf(diff * 2.5, -1.0, 1.0), 0.0)

	var ax: float = clampf(diff * 1.2, -1.0, 1.0)
	if absf(diff) < 0.35:
		# 目標付近では小さく揺れて待つ(棒立ち防止)
		ax = sin(_wobble_time * 3.7) * 0.12
	return Vector2(ax, 0.0)

func _door_x(door_idx: int) -> float:
	if gs.num_choices == 4:
		return gs.tuning.door4_xs[clampi(door_idx, 0, gs.tuning.door4_xs.size() - 1)]
	return gs.tuning.left_door_x if door_idx == 0 else gs.tuning.right_door_x

func _idle_emote(dt: float) -> int:
	# 待機中にたまにエモートダンス
	_emote_timer -= dt
	if _emote_timer <= 0.0:
		_emote_timer = randf_range(2.5, 5.0)
		if gs.p1_emote_slots.size() > 0 and randf() < 0.7:
			_current_emote = gs.p1_emote_slots.pick_random()
		else:
			_current_emote = 0
	return _current_emote
