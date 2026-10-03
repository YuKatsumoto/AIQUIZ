class_name SuddenDeathState
extends RefCounted

## 2Pサドンデス「早押し水没リフト」のルール（docs/sudden_death_underground.md 第3章）。
## 2人はスコアタワーのリフトに乗って、流れる水の上に立つ。問題文が1文字ずつ流れる間に早押しし、
## 押した人だけが方向キーで答える。正解なら相手のリフトが、不正解（押してから答えずに時間切れも）
## なら自分のリフトが1段沈む。誰も押さずに時間切れなら両方が半段沈む（水面ぎりぎりで止まる）。
## 余裕（水面からの高さ）がなくなって水に沈んだほうの負け。1問で沈むのは多くても1人なので、
## 同時に負けることはない。
##
## 入力（早押しと回答のキー、フレームの中の時刻つき）は QuizGameState が渡す。表示は持たない。
## 出来事は events に積み、取り出した側が clear する。

## INTRO：降下・着地・導入の間（判定なし）。演出が start_countdown() で COUNTDOWN へ進める。
## QUESTION：「第N問」と選択肢が出る（早押しは無効）。READING：問題文が流れる・出きって考える（早押しできる）。
## ANSWERING：押した人が答える。RESULT：判定を見せる。DECIDED：決着（負けたリフトが沈む）。
enum Phase { NONE, INTRO, COUNTDOWN, QUESTION, READING, ANSWERING, RESULT, DECIDED }

var tuning := SuddenDeathTuning.new()
var quizzes: Array[QuizItem] = []
## 問題が尽きたときに次の1問を返す（QuizGameState が算数の自動生成をつなぐ）。無効なら最初から使い回す。
var extra_question: Callable

var phase := Phase.NONE
var phase_time := 0.0
## 本戦開始（「第1問」の直前のGO）からの時間。
var time := 0.0
## 今の問題の番号（0始まり、始まる前は -1）と、その問題。
var question_index := -1
var question: QuizItem = null
## 余裕（半段）。0以下で負け。
var margin: Array[int] = [4, 4]
## 早押しした人（1 / 2、まだなら 0）、その時刻（time）と、そのとき出ていた文字数。
var buzzer := 0
var buzz_time := INF
var revealed_at_buzz := 0
## 選んだ選択肢（-1 は未回答・時間切れ）と判定："correct" / "wrong" / "late"（押して答えずに時間切れ）/
## "timeout"（誰も押さずに時間切れ）。
var answer := -1
var result := ""
var winner := 0
var loser := 0
## 決着の理由："correct"（勝者の正解）/ "wrong"（敗者の不正解）/ "late"（敗者が答えずに時間切れ）。
var decided_by := ""
var caught: Array[bool] = [false, false]
var caught_time: Array[float] = [INF, INF]
var finished := false
var correct_count: Array[int] = [0, 0]
var wrong_count: Array[int] = [0, 0]
var buzz_count: Array[int] = [0, 0]
var timeouts := 0
## 表示側へ渡す出来事。取り出した側が clear する。
var events: Array[Dictionary] = []

var _started := false


func setup(question_list: Array[QuizItem], with_intro := false) -> void:
	quizzes = question_list.duplicate()
	phase = Phase.INTRO if with_intro else Phase.COUNTDOWN
	phase_time = 0.0
	time = 0.0
	question_index = -1
	question = null
	margin = [tuning.start_margin, tuning.start_margin]
	buzzer = 0
	buzz_time = INF
	revealed_at_buzz = 0
	answer = -1
	result = ""
	winner = 0
	loser = 0
	decided_by = ""
	caught = [false, false]
	caught_time = [INF, INF]
	finished = false
	correct_count = [0, 0]
	wrong_count = [0, 0]
	buzz_count = [0, 0]
	timeouts = 0
	events.clear()
	_started = false


## 導入の終わり（docs 2.2）：カウントダウンを始める。
func start_countdown() -> void:
	if phase == Phase.INTRO:
		phase = Phase.COUNTDOWN
		phase_time = 0.0
		events.append({"kind": "countdown"})


## 問題が出ている間（「第N問」から判定まで）。
func is_running() -> bool:
	return phase in [Phase.QUESTION, Phase.READING, Phase.ANSWERING, Phase.RESULT]


func is_active() -> bool:
	return phase != Phase.NONE


func current_quiz() -> QuizItem:
	return question if phase in [Phase.QUESTION, Phase.READING, Phase.ANSWERING, Phase.RESULT, Phase.DECIDED] else null


func current_choices() -> int:
	return question.c.size() if question != null else 0


func countdown_remaining() -> float:
	return maxf(0.0, tuning.countdown - phase_time) if phase == Phase.COUNTDOWN else 0.0


## 今出ている問題文の文字数。判定の後は全文。
func revealed_count() -> int:
	if question == null:
		return 0
	match phase:
		Phase.READING:
			return mini(question.q.length(), int(floor(phase_time * tuning.reveal_rate + 0.0001)))
		Phase.ANSWERING:
			return revealed_at_buzz
		Phase.RESULT, Phase.DECIDED:
			return question.q.length()
	return 0


## READING：問題文が出きったか（考える時間に入ったか）。
func is_fully_revealed() -> bool:
	return question != null and revealed_count() >= question.q.length()


## READING の残り時間（秒）と、考える時間の残りの割合（問題文が流れている間は 1）。
func reading_remaining() -> float:
	if phase != Phase.READING or question == null:
		return 0.0
	return maxf(0.0, _reading_deadline() - phase_time)


func think_fraction() -> float:
	if phase != Phase.READING or question == null:
		return 1.0
	return clampf(reading_remaining() / maxf(tuning.think_time, 0.001), 0.0, 1.0)


## ANSWERING の残りの割合（1 → 0）。
func answer_fraction() -> float:
	if phase != Phase.ANSWERING:
		return 0.0
	return clampf(1.0 - phase_time / maxf(tuning.answer_time, 0.001), 0.0, 1.0)


## 早押しできるか（問題文が流れている間と考える時間）。
func can_buzz() -> bool:
	return phase == Phase.READING


## リフトの天面の高さ（床から、m）。負けたリフトは沈みきった高さ。
func lift_target(player_index: int) -> float:
	var slot := player_index - 1
	if phase == Phase.DECIDED and player_index == loser:
		return tuning.sunk_height()
	return tuning.lift_height(maxi(margin[slot], 0))


## [param input]（このフレームの入力。どれも省略できる）:
## "buzz": [P1, P2] 早押しキーを押したフレーム内の時刻（秒、0〜dt）。押していなければ -1。
## "choice": [P1, P2] 押した回答キーの選択肢番号（-1 なし）、"choice_offset": その時刻（秒）。
## 押しっぱなしは数えない（GameWorld が押した瞬間だけを渡す）。
func step(dt: float, input: Dictionary = {}) -> void:
	if dt <= 0.0 or phase in [Phase.NONE, Phase.INTRO]:
		return
	var cursor := 0.0
	var guard := 0
	# A frame may cross several phases (the countdown ends, the question appears, someone buzzes and
	# answers): each part of the frame goes to the phase it belongs to, in order.
	while cursor < dt - 0.0000001 and guard < 32:
		guard += 1
		var was_started := _started
		var used := _step_phase(dt - cursor, cursor, input)
		if was_started:
			time += used
		cursor += used
		if phase in [Phase.NONE, Phase.INTRO]:
			break


## Runs the current phase for at most [param left] seconds starting [param offset] into the frame.
## Returns the seconds used (less than [param left] when the phase changed on the way).
func _step_phase(left: float, offset: float, input: Dictionary) -> float:
	match phase:
		Phase.COUNTDOWN:
			var need := tuning.countdown - phase_time
			if left < need:
				phase_time += left
				return left
			_started = true
			time = 0.0
			events.append({"kind": "go"})
			_begin_question()
			return maxf(need, 0.0)
		Phase.QUESTION:
			var need := tuning.question_intro - phase_time
			if left < need:
				phase_time += left
				return left
			phase = Phase.READING
			phase_time = 0.0
			events.append({"kind": "reading", "index": question_index})
			return maxf(need, 0.0)
		Phase.READING:
			var need := _reading_deadline() - phase_time
			var span := minf(left, maxf(need, 0.0))
			var press := _first_buzz(input, offset, offset + span)
			if press.player > 0:
				var used := clampf(float(press.offset) - offset, 0.0, span)
				phase_time += used
				_buzz(int(press.player), time + used)
				return used
			if left < need:
				phase_time += left
				return left
			phase_time += maxf(need, 0.0)
			_resolve_timeout()
			return maxf(need, 0.0)
		Phase.ANSWERING:
			var need := tuning.answer_time - phase_time
			var span := minf(left, maxf(need, 0.0))
			var slot := buzzer - 1
			var choice := _input_int(input, "choice", slot, -1)
			var choice_at := _input_float(input, "choice_offset", slot, 0.0)
			if choice >= 0 and choice_at >= offset - 0.0000001 and choice_at <= offset + span + 0.0000001:
				var used := clampf(choice_at - offset, 0.0, span)
				phase_time += used
				_judge(choice, false)
				return used
			if left < need:
				phase_time += left
				return left
			phase_time += maxf(need, 0.0)
			_judge(-1, true)
			return maxf(need, 0.0)
		Phase.RESULT:
			var need := tuning.result_hold - phase_time
			if left < need:
				phase_time += left
				return left
			_begin_question()
			return maxf(need, 0.0)
		Phase.DECIDED:
			phase_time += left
			var slot := loser - 1
			if slot >= 0 and not caught[slot] and phase_time >= tuning.plunge_time:
				caught[slot] = true
				caught_time[slot] = time + left - (phase_time - tuning.plunge_time)
				events.append({"kind": "caught", "player": loser, "time": caught_time[slot]})
			if slot >= 0 and caught[slot] and phase_time >= tuning.plunge_time + tuning.decided_hold:
				finished = true
			return left
	return left


func _reading_deadline() -> float:
	return tuning.reveal_seconds(question.q if question != null else "") + tuning.think_time


func _begin_question() -> void:
	question_index += 1
	question = _quiz_at(question_index)
	buzzer = 0
	buzz_time = INF
	revealed_at_buzz = 0
	answer = -1
	result = ""
	phase = Phase.QUESTION
	phase_time = 0.0
	events.append({"kind": "question", "index": question_index,
		"choices": question.c.size() if question != null else 0, "answer": question.a if question != null else -1})


func _quiz_at(index: int) -> QuizItem:
	if index < quizzes.size():
		return quizzes[index]
	if extra_question.is_valid():
		var extra: Variant = extra_question.call()
		if extra is QuizItem:
			quizzes.append(extra as QuizItem)
			return extra as QuizItem
	return quizzes[index % quizzes.size()] if not quizzes.is_empty() else null


## The earliest buzz in [from, to] of the frame: {"player", "offset"}. Two buzzes within the tie
## window go to the player with less margin (the one in more danger), then alternate by question.
func _first_buzz(input: Dictionary, from: float, to: float) -> Dictionary:
	var presses: Array[float] = [_input_float(input, "buzz", 0, -1.0), _input_float(input, "buzz", 1, -1.0)]
	var valid: Array[bool] = []
	for slot in range(2):
		valid.append(presses[slot] >= from - 0.0000001 and presses[slot] <= to + 0.0000001)
	if valid[0] and valid[1]:
		if absf(presses[0] - presses[1]) <= tuning.tie_window:
			var first := 0
			if margin[0] != margin[1]:
				first = 0 if margin[0] < margin[1] else 1
			else:
				first = question_index % 2
			return {"player": first + 1, "offset": minf(presses[0], presses[1])}
		var earlier := 0 if presses[0] < presses[1] else 1
		return {"player": earlier + 1, "offset": presses[earlier]}
	for slot in range(2):
		if valid[slot]:
			return {"player": slot + 1, "offset": presses[slot]}
	return {"player": 0, "offset": -1.0}


func _buzz(player_index: int, at_time: float) -> void:
	buzzer = player_index
	buzz_time = at_time
	revealed_at_buzz = revealed_count()
	buzz_count[player_index - 1] += 1
	phase = Phase.ANSWERING
	phase_time = 0.0
	events.append({"kind": "buzz", "player": player_index, "time": at_time, "revealed": revealed_at_buzz,
		"index": question_index})


func _judge(choice: int, late: bool) -> void:
	var slot := buzzer - 1
	var other := 1 - slot
	var correct := not late and question != null and choice == question.a
	answer = choice
	if correct:
		result = "correct"
		correct_count[slot] += 1
	else:
		result = "late" if late else "wrong"
		wrong_count[slot] += 1
	events.append({"kind": "answer", "player": buzzer, "choice": choice, "correct": correct, "late": late,
		"answer": question.a if question != null else -1, "index": question_index, "time": time})
	phase = Phase.RESULT
	phase_time = 0.0
	if correct:
		_sink(other, tuning.penalty, "correct")
	else:
		_sink(slot, tuning.penalty, result)


func _resolve_timeout() -> void:
	result = "timeout"
	timeouts += 1
	events.append({"kind": "timeout", "index": question_index, "answer": question.a if question != null else -1})
	phase = Phase.RESULT
	phase_time = 0.0
	for slot in range(2):
		if margin[slot] > tuning.timeout_floor:
			_sink(slot, mini(tuning.timeout_penalty, margin[slot] - tuning.timeout_floor), "timeout")


func _sink(slot: int, amount: int, reason: String) -> void:
	if amount <= 0:
		return
	var before := margin[slot]
	margin[slot] = before - amount
	events.append({"kind": "sink", "player": slot + 1, "from": before, "to": margin[slot], "reason": reason,
		"index": question_index})
	if margin[slot] <= 0 and winner == 0:
		_decide(2 - slot, reason)


func _decide(winner_index: int, by: String) -> void:
	winner = winner_index
	loser = 3 - winner_index
	decided_by = by
	phase = Phase.DECIDED
	phase_time = 0.0
	events.append({"kind": "decided", "winner": winner, "loser": loser, "by": by, "index": question_index,
		"time": time})


static func _input_float(input: Dictionary, key: String, slot: int, fallback: float) -> float:
	var values: Variant = input.get(key, null)
	if values is Array and slot < (values as Array).size():
		return float((values as Array)[slot])
	return fallback


static func _input_int(input: Dictionary, key: String, slot: int, fallback: int) -> int:
	var values: Variant = input.get(key, null)
	if values is Array and slot < (values as Array).size():
		return int((values as Array)[slot])
	return fallback


func get_debug_snapshot() -> Dictionary:
	return {
		"phase": Phase.keys()[phase], "time": snappedf(time, 0.0001), "question": question_index,
		"margin": margin.duplicate(), "buzzer": buzzer, "answer": answer, "result": result,
		"revealed": revealed_count(), "winner": winner, "decided_by": decided_by, "caught": caught.duplicate(),
		"correct": correct_count.duplicate(), "wrong": wrong_count.duplicate(), "timeouts": timeouts,
		"finished": finished,
	}
