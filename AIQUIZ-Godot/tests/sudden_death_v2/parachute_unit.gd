extends Node

## 「ひらけ！パラシュート」のルール（ParachuteGame、docs/sudden_death_v2/parachute.md 第3章）をヘッドレスで確かめる。
##   Godot --headless --path . --script res://tests/sudden_death_v2/parachute_unit_bootstrap.gd

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _run() -> void:
	_test_three_correct()
	_test_wrong_and_none()
	_test_both_full_faster()
	_test_timeout()
	_test_one_answer_per_question()
	_test_altitude_shots()
	_test_final()
	_test_final_both_wrong()
	_test_frame_rate()
	_test_extra_questions()
	print("PARACHUTE_UNIT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ helpers

func _quizzes(count := 8) -> Array[QuizItem]:
	var out: Array[QuizItem] = []
	for i in range(count):
		out.append(QuizItem.create("問題%d" % i, PackedStringArray(["あ", "い", "う", "え"]), i % 4, "", "TEST"))
	return out


func _game(count := 8) -> ParachuteGame:
	var game := ParachuteGame.new()
	game.setup(_quizzes(count), 7)
	game.extra_question = func() -> QuizItem:
		return QuizItem.create("足し算", PackedStringArray(["1", "2", "3", "4"]), 1, "", "TEST")
	game.start()
	return game


func _presses(p1 := -1, p2 := -1, p1_at := 0.0, p2_at := 0.0) -> Dictionary:
	return {"answer": [p1, p2], "answer_offset": [p1_at, p2_at], "action": [-1.0, -1.0]}


## Runs the game for [param seconds] at [param fps], no presses.
func _run_for(game: ParachuteGame, seconds: float, fps := 60) -> void:
	var dt := 1.0 / float(fps)
	var t := 0.0
	while t < seconds - 0.000001 and not game.finished:
		game.step(dt, {})
		t += dt


## Waits until the game asks a question (answering), at most [param seconds].
func _until_question(game: ParachuteGame, seconds := 20.0) -> bool:
	var t := 0.0
	while t < seconds and not game.finished:
		if game.phase == "question":
			return true
		game.step(1.0 / 60.0, {})
		t += 1.0 / 60.0
	return game.phase == "question"


func _right(game: ParachuteGame) -> int:
	return game.correct_choice()


func _wrong(game: ParachuteGame) -> int:
	return (game.correct_choice() + 1) % 4


func _kinds(game: ParachuteGame) -> Array[String]:
	var out: Array[String] = []
	for event: Dictionary in game.events:
		out.append(str(event.kind))
	return out


# ------------------------------------------------------------------ cases

func _test_three_correct() -> void:
	var game := _game()
	check(game.phase == "question" and game.question_index == 0, "start asks the first question")
	for q in range(3):
		_until_question(game)
		game.step(1.0 / 60.0, _presses(_right(game), _wrong(game), 0.002, 0.004))
		if q < 2:
			check(game.phase == "reveal", "both answered: reveal at once (Q%d)" % (q + 1))
	check(game.finished and game.winner == 1 and game.decided_by == "chute", "P1 three right in a row wins by the chute (%d %s)" % [game.winner, game.decided_by])
	check(game.stage == [3, 0], "stages 3 and 0 (%s)" % str(game.stage))
	var kinds := _kinds(game)
	check(kinds.count("reveal") == 3 and kinds.back() == "decided", "events end with decided (%s)" % str(kinds))
	check(int(game.record().questions) == 3 and game.record().detail.stages == [3, 0], "record %s" % str(game.record()))


func _test_wrong_and_none() -> void:
	var game := _game()
	game.step(0.1, _presses(_right(game), -1, 0.01))
	_run_for(game, ParachuteGame.ANSWER_TIME + 0.5)
	check(game.stage == [1, 0], "right +1, no answer stays (%s)" % str(game.stage))
	check(game.results == ["correct", "none"], "results correct/none (%s)" % str(game.results))
	_until_question(game)
	game.step(0.1, _presses(_wrong(game), _wrong(game), 0.01, 0.02))
	check(game.stage == [0, 0], "wrong -1 and never below 0 (%s)" % str(game.stage))
	check(game.results == ["wrong", "wrong"], "results wrong/wrong (%s)" % str(game.results))


func _test_both_full_faster() -> void:
	var game := _game()
	for q in range(3):
		_until_question(game)
		# P2 answers first in the last question.
		var p1_at := 0.010 if q < 2 else 0.012
		var p2_at := 0.011 if q < 2 else 0.003
		game.step(1.0 / 60.0, _presses(_right(game), _right(game), p1_at, p2_at))
	check(game.finished and game.winner == 2 and game.decided_by == "faster", "both full on one question: the faster one (%d %s)" % [game.winner, game.decided_by])
	check(game.stage == [3, 3], "both at 3 (%s)" % str(game.stage))


func _test_timeout() -> void:
	var game := _game()
	_run_for(game, ParachuteGame.PANEL_IN + ParachuteGame.ANSWER_TIME - 0.05)
	check(game.phase == "question", "still answering just before the time runs out")
	_run_for(game, 0.1)
	check(game.phase == "reveal" and game.results == ["none", "none"], "time out reveals with no answers (%s %s)" % [game.phase, str(game.results)])


func _test_one_answer_per_question() -> void:
	var game := _game()
	game.step(0.05, _presses(_wrong(game), -1, 0.01))
	game.step(0.05, _presses(_right(game), -1, 0.01))
	check(game.picks[0] == _wrong(game), "the first press is kept (%s)" % str(game.picks))


func _test_altitude_shots() -> void:
	var game := _game()
	var shots: Array[int] = []
	var t := 0.0
	while t < 60.0 and not game.finished and not game.final:
		game.step(1.0 / 60.0, {})
		for event: Dictionary in game.events:
			if str(event.kind) == "altitude_shot":
				shots.append(int(event.index))
		game.events.clear()
		t += 1.0 / 60.0
	# 高度の見下ろしの画は 2026-10-18 にやめた：問題と答え合わせだけが続く
	check(shots.is_empty(), "no altitude shots between questions (%s)" % str(shots))


func _test_final() -> void:
	var game := _game()
	var t := 0.0
	while t < 120.0 and not game.final:
		game.step(1.0 / 60.0, {})
		t += 1.0 / 60.0
	check(game.final and game.altitude <= ParachuteGame.FINAL_ALTITUDE, "nobody answers: the final question comes at 150 m (%.1f m, %.1f s)" % [game.altitude, t])
	check(_kinds(game).has("final"), "a final event")
	var before_q := game.question_index
	_until_question(game)
	check(game.question_index == before_q + 1 and game.final, "the final question is a new one")
	game.step(1.0 / 60.0, _presses(-1, _wrong(game), 0.0, 0.005))
	check(game.final_locked[1] and not game.finished, "P2 wrong in the final: locked out")
	game.step(1.0 / 60.0, _presses(_wrong(game), _right(game), 0.0, 0.004))
	check(game.final_locked[0] and not game.finished, "P1 wrong too: locked, and P2's second press is ignored")
	check(game.phase == "reveal", "both out: reveal (%s)" % game.phase)


func _test_final_both_wrong() -> void:
	var game := _game()
	var t := 0.0
	while t < 120.0 and not game.final:
		game.step(1.0 / 60.0, {})
		t += 1.0 / 60.0
	_until_question(game)
	var first := game.question_index
	game.step(1.0 / 60.0, _presses(_wrong(game), _wrong(game), 0.003, 0.004))
	check(game.phase == "reveal" and game.stage == [0, 0], "final both wrong: no stage change")
	_until_question(game)
	check(game.question_index == first + 1 and game.final, "then another final question")
	var alt := game.altitude
	game.step(1.0 / 60.0, _presses(-1, _right(game), 0.0, 0.006))
	check(game.finished and game.winner == 2 and game.decided_by == "final", "first right in the final wins (%d %s)" % [game.winner, game.decided_by])
	check(alt >= ParachuteGame.FINAL_FLOOR, "the altitude stays above the floor (%.1f)" % alt)


## The same presses at 30 / 60 / 120 fps give the same result.
func _test_frame_rate() -> void:
	var outcomes: Array[String] = []
	for fps: int in [30, 60, 120]:
		var game := _game()
		var dt := 1.0 / float(fps)
		var t := 0.0
		var plan := {0: [1.30, 2.10], 1: [0.70, 3.00], 2: [2.00, 1.10], 3: [0.40, 0.80]}
		var done := {}
		while t < 60.0 and not game.finished:
			var input := {}
			var index := game.question_index
			if game.phase == "question" and plan.has(index) and not done.has(index):
				var times: Array = plan[index]
				var frame_end := game.phase_time + dt
				var p1 := -1
				var p2 := -1
				var p1_at := 0.0
				var p2_at := 0.0
				if game.picks[0] < 0 and float(times[0]) < frame_end:
					p1 = _right(game) if index != 1 else _wrong(game)
					p1_at = clampf(float(times[0]) - game.phase_time, 0.0, dt)
				if game.picks[1] < 0 and float(times[1]) < frame_end:
					p2 = _right(game)
					p2_at = clampf(float(times[1]) - game.phase_time, 0.0, dt)
				if p1 >= 0 or p2 >= 0:
					input = _presses(p1, p2, p1_at, p2_at)
				if (game.picks[0] >= 0 or p1 >= 0) and (game.picks[1] >= 0 or p2 >= 0):
					done[index] = true
			game.step(dt, input)
			t += dt
		outcomes.append("%d %s q%d %.2f" % [game.winner, game.decided_by, game.question_index, snappedf(game.time, 0.05)])
	check(outcomes[0] == outcomes[1] and outcomes[1] == outcomes[2], "30/60/120 fps agree (%s)" % str(outcomes))


func _test_extra_questions() -> void:
	var game := _game(2)
	var t := 0.0
	while t < 40.0 and game.question_index < 3:
		game.step(1.0 / 60.0, {})
		t += 1.0 / 60.0
	check(game.question_index >= 3 and game.quizzes.size() >= 4 and game.current_quiz() != null, "past the prepared questions the generator adds more")
