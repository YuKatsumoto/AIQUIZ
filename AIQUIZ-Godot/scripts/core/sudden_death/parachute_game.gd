class_name ParachuteGame
extends SuddenDeathGame

## サドンデス「ひらけ！パラシュート」のルール（docs/sudden_death_v2/parachute.md 第3章・4.2〜4.4節）。
## 2人は落ちながら同じ4択に同時に答える。正解でパラシュートが1段開き、不正解で1段しぼむ（0段ならそのまま）、
## 答えなければそのまま。先に3段（全開）になった方の勝ち。同じ問題で2人とも3段に届いたら、先に正解を押した方。
## 高度が150mになったら「最後の1問」：先に正解した方の勝ち。外した方はその問題に答えられない。
## 時計はルールの時計（実時間）。最後の1問のスローは見せ方だけで、ルールの時計は遅くしない（高度の減りだけ遅くする）。

const QUESTION_COUNT := 8
const STAGES_TO_WIN := 3
## 問題パネルが下りてくる間（答えは受け付ける）。
const PANEL_IN := 0.25
const ANSWER_TIME := 8.0
const REVEAL_TIME := 1.6
const ALTITUDE_START := 2000.0
const FALL_SPEED := 40.0
const FINAL_ALTITUDE := 150.0
const FINAL_INTRO := 0.6
## 最後の1問の間の高度の減り方（見せ方のスローと同じ割合）と、それより下へは減らない高さ。
const FINAL_SLOW := 0.3
const FINAL_FLOOR := 30.0

## "idle"（導入）、"question"、"reveal"、"final_intro"、"decided"
var phase := "idle"
var phase_time := 0.0
var time := 0.0
var altitude := ALTITUDE_START
## パラシュートの段（0〜3）[P1, P2]。
var stage: Array[int] = [0, 0]
## 最後の1問に入った。
var final := false
## この問題で選んだ選択肢（-1 = 答えていない）と、答えた時刻（問題の頭からの秒）。
var picks: Array[int] = [-1, -1]
var pick_time: Array[float] = [-1.0, -1.0]
## 答え合わせの結果："correct" / "wrong" / "none"（最後の1問の外れは "wrong"）。
var results: Array[String] = ["", ""]
## 最後の1問で外した（その問題にはもう答えられない）。
var final_locked: Array[bool] = [false, false]
var correct_count: Array[int] = [0, 0]
var wrong_count: Array[int] = [0, 0]


func _init() -> void:
	kind = "parachute"


func setup(questions: Array[QuizItem], seed_value: int) -> void:
	super.setup(questions, seed_value)
	phase = "idle"
	phase_time = 0.0
	time = 0.0
	altitude = ALTITUDE_START
	stage = [0, 0]
	final = false
	correct_count = [0, 0]
	wrong_count = [0, 0]
	_clear_answers()


## カウントダウンが終わった：1問目を出す。
func start() -> void:
	super.start()
	_next_question()


## 一時停止はルールの時計を止めるだけ（step が呼ばれない）。答えた分はそのまま残す。
func interrupt() -> void:
	pass


## 答えを受け付けている（HUD のカーソル・テスト用）。
func is_answering() -> bool:
	return phase == "question" and not finished


## 回答時間の残り（0〜1）。
func time_left_ratio() -> float:
	if phase != "question":
		return 0.0
	return clampf(1.0 - (phase_time - PANEL_IN) / ANSWER_TIME, 0.0, 1.0)


func correct_choice() -> int:
	var quiz := current_quiz()
	return quiz.a if quiz != null else -1


func record() -> Dictionary:
	var data := super.record()
	data["detail"] = {"stages": stage.duplicate(), "final": final, "altitude": snappedf(altitude, 0.1),
		"correct": correct_count.duplicate(), "wrong": wrong_count.duplicate()}
	return data


func get_debug_snapshot() -> Dictionary:
	var data := super.get_debug_snapshot()
	data.merge({"phase": phase, "phase_time": snappedf(phase_time, 0.001), "time": snappedf(time, 0.001),
		"altitude": snappedf(altitude, 0.01), "stage": stage.duplicate(), "final": final, "picks": picks.duplicate(),
		"results": results.duplicate(), "final_locked": final_locked.duplicate()}, true)
	return data


# ------------------------------------------------------------------ the clock

func _advance(span: float) -> void:
	var left := span
	# 段階が変わるたびに残りの時間を次の段階へ配る（1フレームが段階をまたいでも同じ結果になる）。
	var guard := 0
	while left > 0.0 and not finished and guard < 32:
		guard += 1
		var limit := _phase_length()
		var step := minf(left, maxf(limit - phase_time, 0.0)) if is_finite(limit) else left
		phase_time += step
		time += step
		left -= step
		if phase != "idle":
			altitude = maxf(altitude - FALL_SPEED * (FINAL_SLOW if final else 1.0) * step, FINAL_FLOOR if final else 0.0)
		if is_finite(limit) and phase_time >= limit - 0.000001:
			_end_phase()


func _phase_length() -> float:
	match phase:
		"question":
			return PANEL_IN + ANSWER_TIME
		"reveal":
			return REVEAL_TIME
		"final_intro":
			return FINAL_INTRO
	return INF


func _end_phase() -> void:
	match phase:
		"question":
			_reveal()
		"reveal":
			if not final and altitude <= FINAL_ALTITUDE:
				final = true
				_set_phase("final_intro")
				_emit("final", {"altitude": altitude, "stages": stage.duplicate()})
			else:
				_next_question()
		"final_intro":
			_next_question()


func _set_phase(next: String) -> void:
	phase = next
	phase_time = 0.0


func _clear_answers() -> void:
	picks = [-1, -1]
	pick_time = [-1.0, -1.0]
	results = ["", ""]
	final_locked = [false, false]


func _next_question() -> void:
	_clear_answers()
	_next_quiz()
	_set_phase("question")
	_emit("question", {"index": question_index, "final": final, "altitude": altitude,
		"choices": current_choices(), "stages": stage.duplicate()})


# ------------------------------------------------------------------ answers

func _apply_press(press: Dictionary) -> void:
	if str(press.type) != "answer" or phase != "question":
		return
	var slot := int(press.player) - 1
	var choice := int(press.value)
	if slot < 0 or slot > 1 or choice < 0:
		return
	if final:
		_final_press(slot, choice)
		return
	if picks[slot] >= 0:
		return
	picks[slot] = choice
	pick_time[slot] = phase_time
	_emit("answered", {"player": slot + 1, "index": question_index, "at": phase_time})
	if picks[0] >= 0 and picks[1] >= 0:
		_reveal()


## 最後の1問：先に正解した方の勝ち。外したらこの問題はもう答えられない。
func _final_press(slot: int, choice: int) -> void:
	if final_locked[slot] or picks[slot] >= 0:
		return
	picks[slot] = choice
	pick_time[slot] = phase_time
	if choice == correct_choice():
		results[slot] = "correct"
		correct_count[slot] += 1
		var other := 1 - slot
		if results[other] == "":
			results[other] = "none"
		_emit("reveal", {"index": question_index, "correct": correct_choice(), "picks": picks.duplicate(),
			"results": results.duplicate(), "stages": stage.duplicate(), "final": true})
		_decide(slot + 1, "final")
		return
	results[slot] = "wrong"
	wrong_count[slot] += 1
	final_locked[slot] = true
	_emit("final_wrong", {"player": slot + 1, "index": question_index, "choice": choice})
	if final_locked[0] and final_locked[1]:
		_reveal()


func _reveal() -> void:
	var answer := correct_choice()
	if final:
		# 最後の1問で誰も正解しなかった（2人とも外したか、時間切れ）。段は変えない。
		for slot in [0, 1]:
			if results[slot] == "":
				results[slot] = "none"
	else:
		for slot in [0, 1]:
			if picks[slot] < 0:
				results[slot] = "none"
			elif picks[slot] == answer:
				results[slot] = "correct"
				correct_count[slot] += 1
				stage[slot] = mini(stage[slot] + 1, STAGES_TO_WIN)
			else:
				results[slot] = "wrong"
				wrong_count[slot] += 1
				stage[slot] = maxi(stage[slot] - 1, 0)
	_set_phase("reveal")
	_emit("reveal", {"index": question_index, "correct": answer, "picks": picks.duplicate(),
		"results": results.duplicate(), "stages": stage.duplicate(), "final": final})
	if final:
		return
	var full: Array[int] = []
	for slot in [0, 1]:
		if stage[slot] >= STAGES_TO_WIN:
			full.append(slot)
	if full.size() == 1:
		_decide(full[0] + 1, "chute")
	elif full.size() == 2:
		# 同じ問題で2人とも全開：先に正解を押した方。
		var first := 0 if pick_time[0] < pick_time[1] else 1
		if is_equal_approx(pick_time[0], pick_time[1]):
			first = rng.randi_range(0, 1)
		_decide(first + 1, "faster")


func _decide(player: int, by: String) -> void:
	winner = player
	decided_by = by
	_set_phase("decided")
	finished = true
	_emit("decided", {"winner": winner, "by": by, "stages": stage.duplicate(), "altitude": altitude, "index": question_index})
