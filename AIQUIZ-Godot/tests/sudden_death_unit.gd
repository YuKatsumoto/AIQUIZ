extends Node

## 2Pサドンデス「早押し水没リフト」のルール検証（docs/sudden_death_underground.md 第3・4章）。
## 起動: Godot --headless --path . --script res://tests/sudden_death_bootstrap.gd

class EmptyBankProvider extends QuizProvider:
	func _load_bank() -> Dictionary:
		return {}


## Online generation stand-in: keeps the callbacks so the test decides when (and what) arrives.
class GeneratingProvider extends EmptyBankProvider:
	var accept := true
	var requests := 0
	var requested_count := 0
	var excluded: Array[String] = []
	var on_progress: Callable
	var on_done: Callable

	func request_sudden_death_quizzes(count: int, exclude_texts: Array[String], progress: Callable,
			done: Callable) -> bool:
		requests += 1
		if not accept:
			return false
		requested_count = count
		excluded = exclude_texts.duplicate()
		on_progress = progress
		on_done = done
		return true

const OUT := "res://artifacts/sudden_death/"
const Phase := SuddenDeathState.Phase
## A question 16 characters long (2.0 s to reveal at 8 characters a second).
const TEXT_16 := "あいうえおかきくけこさしすせそた"

var checks := 0
var failures: Array[String] = []
var metrics := {}
var _providers: Array[QuizProvider] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	QuizManager.player_analytics = null
	for path in ["res://scripts/core/sudden_death/sudden_death_tuning.gd",
			"res://scripts/core/sudden_death/sudden_death_state.gd", "res://scripts/core/sudden_death/sudden_death_questions.gd",
			"res://scripts/world/sudden_death/sudden_death_director.gd", "res://scripts/world/game_world.gd",
			"res://scripts/world/camera_controller.gd", "res://scripts/world/player_controller.gd",
			"res://scripts/ui/gameplay_hud.gd", "res://scripts/world/sudden_death/cistern_flow.gd",
			"res://scripts/world/result_ceremony_director.gd", "res://scripts/world/result_finale/result_finale_stage.gd",
			"res://scripts/core/sudden_death/sudden_death_descent.gd", "res://scripts/world/sudden_death/sudden_death_layout.gd",
			"res://scripts/world/sudden_death/shaft_descent.gd", "res://scripts/world/sudden_death/cistern_stage.gd",
			"res://scripts/world/sudden_death/sudden_death_loader.gd", "res://scripts/world/sudden_death/sudden_death_audio.gd",
			"res://scripts/world/sudden_death/surface_drain.gd", "res://scripts/ui/sudden_death_hud.gd",
			"res://scripts/ui/result_finale_hud.gd", "res://scripts/world/stage_environment.gd",
			"res://scripts/world/match_reel/match_reel.gd", "res://scripts/world/sudden_death/flood_tumble.gd",
			"res://scripts/core/online_fetch.gd", "res://scripts/core/buffered_provider.gd", "res://scripts/core/quiz_provider.gd"]:
		var script := load(path) as Script
		check(script != null and script.can_instantiate(), "compiles " + path)
	_key_cases()
	for fps in [30, 60, 120]:
		_countdown_case(fps)
		_reveal_case(fps)
		for player in [1, 2]:
			_correct_case(fps, player)
			_wrong_case(fps, player)
		_late_case(fps)
		_timeout_case(fps)
		_win_case(fps)
		_same_frame_case(fps)
	_tie_cases()
	_extra_question_case()
	_never_both_case()
	_frame_rate_case()
	_question_cases()
	for fps in [30, 60, 120]:
		_integration_case(fps)
		_hold_case(fps)
		_abort_case(fps, true)
	_abort_case(60, false)
	_disabled_case()
	_unavailable_case()
	_finale_sink_case()
	_descent_cases()
	_assemble_cases()
	_descent_waiting_cases()
	for fps in [30, 60]:
		_generation_case(fps)
	_generation_fallback_cases()
	_stage_cases()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "metrics": metrics}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT + "unit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SUDDEN_DEATH_UNIT " + JSON.stringify({"passed": report.passed, "checks": checks, "failures": failures}))
	for provider in _providers:
		provider.free()
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ fixtures

func _quiz(answer: int, label: String, text := TEXT_16, count := 4) -> QuizItem:
	var choices := PackedStringArray()
	for index in range(count):
		choices.append("%s-%d" % [label, index])
	return QuizItem.create(text, choices, answer, "", "OFFLINE")


## Eight questions; the answers go 0, 1, 2, 3, 0, ...
func _state(with_intro := false) -> SuddenDeathState:
	var quizzes: Array[QuizItem] = []
	for index in range(SuddenDeathTuning.QUESTION_COUNT):
		quizzes.append(_quiz(index % 4, str(index)))
	var sd := SuddenDeathState.new()
	sd.setup(quizzes, with_intro)
	return sd


## Presses scripted at absolute times (seconds since step 0): [time, player, "buzz" | choice].
class Script_:
	var presses: Array = []

	func input_for(t: float, dt: float) -> Dictionary:
		var input := {"buzz": [-1.0, -1.0], "choice": [-1, -1], "choice_offset": [0.0, 0.0]}
		for press: Array in presses:
			var at := float(press[0])
			if at < t - 0.0000001 or at >= t + dt - 0.0000001:
				continue
			var slot := int(press[1]) - 1
			if str(press[2]) == "buzz":
				if float(input.buzz[slot]) < 0.0:
					input.buzz[slot] = at - t
			elif int(input.choice[slot]) < 0:
				input.choice[slot] = int(press[2])
				input.choice_offset[slot] = at - t
		return input


## Steps [param sd] at [param fps] for [param seconds] with the scripted presses; returns the events.
func _run(sd: SuddenDeathState, fps: int, seconds: float, script: Script_ = null, start := 0.0) -> Array[Dictionary]:
	var dt := 1.0 / float(fps)
	var events: Array[Dictionary] = []
	var t := start
	var frames := int(round(seconds * float(fps)))
	for _frame in range(frames):
		sd.step(dt, script.input_for(t, dt) if script != null else {})
		t += dt
		events.append_array(sd.events)
		sd.events.clear()
	return events


func _kinds(events: Array[Dictionary]) -> Array[String]:
	var kinds: Array[String] = []
	for event: Dictionary in events:
		kinds.append(str(event.kind))
	return kinds


func _first(events: Array[Dictionary], kind: String) -> Dictionary:
	for event: Dictionary in events:
		if str(event.kind) == kind:
			return event
	return {}


## Seconds (state time) from GO to the start of the reading of question 1.
func _reading_at(sd: SuddenDeathState) -> float:
	return sd.tuning.countdown + sd.tuning.question_intro


# ------------------------------------------------------------------ rules (第3章)

func _key_cases() -> void:
	var gs := QuizGameState
	check(gs.sudden_death_choice_for_key(gs.SUDDEN_DEATH_KEY_LEFT, 2) == 0 and gs.sudden_death_choice_for_key(gs.SUDDEN_DEATH_KEY_RIGHT, 2) == 1
		and gs.sudden_death_choice_for_key(gs.SUDDEN_DEATH_KEY_UP, 2) == -1, "keys: 2 choices are left and right")
	check(gs.sudden_death_choice_for_key(gs.SUDDEN_DEATH_KEY_UP, 3) == 1 and gs.sudden_death_choice_for_key(gs.SUDDEN_DEATH_KEY_DOWN, 3) == -1,
		"keys: 3 choices are left, up, right")
	var ordered := true
	for choice in range(4):
		ordered = ordered and gs.sudden_death_choice_for_key(gs.sudden_death_key_for_choice(choice, 4), 4) == choice
	check(ordered and gs.sudden_death_key_for_choice(0, 4) == gs.SUDDEN_DEATH_KEY_LEFT and gs.sudden_death_key_for_choice(3, 4) == gs.SUDDEN_DEATH_KEY_RIGHT,
		"keys: 4 choices read left to right as left, up, down, right")
	var tuning := SuddenDeathTuning.new()
	check(is_equal_approx(tuning.lift_height(tuning.start_margin), tuning.water_level + 3.0) and tuning.sunk_height() < tuning.water_level,
		"lift: starts 3 m over the water and sinks under it")


func _countdown_case(fps: int) -> void:
	var sd := _state(true)
	var events := _run(sd, fps, 2.0)
	check(sd.phase == Phase.INTRO and events.is_empty(), "countdown: nothing before the intro ends %d" % fps)
	sd.start_countdown()
	check(sd.phase == Phase.COUNTDOWN and _kinds(sd.events) == ["countdown"], "countdown: starts %d" % fps)
	sd.events.clear()
	events = _run(sd, fps, sd.tuning.countdown - 0.1)
	check(sd.phase == Phase.COUNTDOWN and events.is_empty(), "countdown: 1.8 s %d" % fps)
	events = _run(sd, fps, 0.2)
	check(_kinds(events) == ["go", "question"] and sd.phase == Phase.QUESTION and sd.question_index == 0, "countdown: GO and question 1 %d" % fps)
	check(sd.time >= 0.0 and sd.time < 0.2, "countdown: the duel clock starts at GO %d" % fps)


func _reveal_case(fps: int) -> void:
	var sd := _state()
	var script := Script_.new()
	# An early press during the "question 1" card does not count, nor does holding on.
	script.presses = [[sd.tuning.countdown + 0.5, 1, "buzz"]]
	_run(sd, fps, _reading_at(sd) + 0.05, script)
	check(sd.phase == Phase.READING and sd.buzzer == 0, "reveal: an early buzz is ignored %d" % fps)
	_run(sd, fps, 0.95, null, _reading_at(sd))
	check(absi(sd.revealed_count() - 8) <= 1 and not sd.is_fully_revealed(), "reveal: 8 characters a second (%d) %d" % [sd.revealed_count(), fps])
	check(is_equal_approx(sd.think_fraction(), 1.0), "reveal: the think bar is full while the text comes %d" % fps)
	_run(sd, fps, 1.2)
	check(sd.is_fully_revealed() and sd.revealed_count() == TEXT_16.length() and sd.think_fraction() < 1.0, "reveal: whole question after 2 s %d" % fps)


## Reach READING on question 1 and buzz [param player] at reading + 0.75 s, answering at + 1.25 s.
func _buzz_and_answer(sd: SuddenDeathState, fps: int, player: int, choice: int) -> Array[Dictionary]:
	var script := Script_.new()
	var buzz_at := _reading_at(sd) + 0.75
	script.presses = [[buzz_at, player, "buzz"], [buzz_at + 0.5, player, choice]]
	return _run(sd, fps, buzz_at + 0.6, script)


func _correct_case(fps: int, player: int) -> void:
	var sd := _state()
	var events := _buzz_and_answer(sd, fps, player, 0)
	var buzz := _first(events, "buzz")
	check(int(buzz.get("player", 0)) == player and absi(int(buzz.revealed) - 6) <= 1, "correct: P%d buzzed with 6 characters shown %d" % [player, fps])
	check(sd.phase == Phase.RESULT and sd.result == "correct" and sd.answer == 0, "correct: P%d judged right %d" % [player, fps])
	var other := 3 - player
	check(sd.margin[other - 1] == sd.tuning.start_margin - sd.tuning.penalty and sd.margin[player - 1] == sd.tuning.start_margin,
		"correct: the rival's lift sinks a step %d" % fps)
	var sink := _first(events, "sink")
	check(int(sink.get("player", 0)) == other and str(sink.reason) == "correct", "correct: sink event %d" % fps)
	check(sd.revealed_count() == TEXT_16.length(), "correct: the whole question shows with the result %d" % fps)
	_run(sd, fps, sd.tuning.result_hold + 0.05)
	check(sd.phase == Phase.QUESTION and sd.question_index == 1 and sd.buzzer == 0 and sd.answer == -1, "correct: on to question 2 %d" % fps)


func _wrong_case(fps: int, player: int) -> void:
	var sd := _state()
	_buzz_and_answer(sd, fps, player, 2)
	check(sd.result == "wrong" and sd.margin[player - 1] == sd.tuning.start_margin - sd.tuning.penalty
		and sd.margin[2 - player] == sd.tuning.start_margin, "wrong: P%d's own lift sinks %d" % [player, fps])
	check(sd.wrong_count[player - 1] == 1 and sd.correct_count == [0, 0], "wrong: counted %d" % fps)


func _late_case(fps: int) -> void:
	var sd := _state()
	var script := Script_.new()
	var buzz_at := _reading_at(sd) + 0.5
	# The other player's keys do not answer for the buzzer.
	script.presses = [[buzz_at, 2, "buzz"], [buzz_at + 0.3, 1, 0]]
	_run(sd, fps, buzz_at + sd.tuning.answer_time - 0.05, script)
	check(sd.phase == Phase.ANSWERING and sd.buzzer == 2, "late: still answering just before 4 s %d" % fps)
	var events := _run(sd, fps, 0.1)
	check(sd.result == "late" and sd.margin == [4, 2] and bool(_first(events, "answer").get("late", false)), "late: no answer sinks the buzzer %d" % fps)


func _timeout_case(fps: int) -> void:
	var sd := _state()
	var deadline := _reading_at(sd) + sd.tuning.reveal_seconds(TEXT_16) + sd.tuning.think_time
	_run(sd, fps, deadline - 0.05)
	check(sd.phase == Phase.READING, "timeout: reading until the think time is up %d" % fps)
	var events := _run(sd, fps, 0.1)
	check(sd.result == "timeout" and sd.margin == [3, 3] and "timeout" in _kinds(events), "timeout: both sink half a step %d" % fps)
	# Down to the floor: time-outs never sink anyone below the last half step.
	sd.margin = [1, 3]
	for _question in range(3):
		_run(sd, fps, sd.tuning.result_hold + sd.tuning.question_intro + sd.tuning.reveal_seconds(TEXT_16) + sd.tuning.think_time + 0.05)
	check(sd.margin == [1, 1] and sd.winner == 0 and sd.phase != Phase.DECIDED, "timeout: stops at the water's edge, nobody loses %d (%s)" % [fps, str(sd.margin)])


func _win_case(fps: int) -> void:
	var sd := _state()
	var script := Script_.new()
	var first := _reading_at(sd) + 0.6
	var question_length := sd.tuning.result_hold + sd.tuning.question_intro
	# P1 answers question 1 (answer 0) and question 2 (answer 1) right.
	script.presses = [[first, 1, "buzz"], [first + 0.4, 1, 0]]
	var second := first + 0.4 + question_length + 0.6
	script.presses.append_array([[second, 1, "buzz"], [second + 0.4, 1, 1]])
	var events := _run(sd, fps, second + 0.5, script)
	var decided := _first(events, "decided")
	check(sd.phase == Phase.DECIDED and sd.winner == 1 and sd.loser == 2 and sd.decided_by == "correct", "win: P1 by two right answers %d" % fps)
	check(int(decided.get("index", -1)) == 1 and sd.margin == [4, 0], "win: decided on question 2 %d" % fps)
	check(is_equal_approx(sd.lift_target(2), sd.tuning.sunk_height()) and is_equal_approx(sd.lift_target(1), sd.tuning.lift_height(4)),
		"win: the loser's lift goes under %d" % fps)
	events = _run(sd, fps, sd.tuning.plunge_time + 0.05)
	check(sd.caught == [false, true] and "caught" in _kinds(events), "win: the water takes the loser after the plunge %d" % fps)
	check(absf(sd.caught_time[1] - (float(decided.time) + sd.tuning.plunge_time)) < 1.0 / fps + 0.0001, "win: caught on time %d" % fps)
	_run(sd, fps, sd.tuning.decided_hold + 0.05)
	check(sd.finished, "win: finished after the hold %d" % fps)
	# Losing by one's own wrong answers.
	var own := _state()
	var wrong := Script_.new()
	wrong.presses = [[first, 2, "buzz"], [first + 0.4, 2, 3], [second, 2, "buzz"], [second + 0.4, 2, 3]]
	_run(own, fps, second + 0.5, wrong)
	check(own.winner == 1 and own.decided_by == "wrong" and own.margin == [4, 0], "win: P2 loses by two wrong answers %d" % fps)


func _same_frame_case(fps: int) -> void:
	var dt := 1.0 / float(fps)
	var sd := _state()
	_run(sd, fps, _reading_at(sd) + 0.5)
	# Both buzz in one frame: the earlier press wins.
	sd.step(dt, {"buzz": [dt * 0.95, dt * 0.05]})
	check(sd.buzzer == 2, "same frame: the earlier buzz wins %d" % fps)
	# Buzz and answer in one frame: an answer before the buzz does not count, one after it does.
	var other := _state()
	_run(other, fps, _reading_at(other) + 0.5)
	other.step(dt, {"buzz": [dt * 0.5, -1.0], "choice": [0, -1], "choice_offset": [dt * 0.2, 0.0]})
	check(other.phase == Phase.ANSWERING and other.answer == -1, "same frame: an answer before the buzz is ignored %d" % fps)
	var third := _state()
	_run(third, fps, _reading_at(third) + 0.5)
	third.step(dt, {"buzz": [dt * 0.2, -1.0], "choice": [0, -1], "choice_offset": [dt * 0.6, 0.0]})
	check(third.phase == Phase.RESULT and third.result == "correct", "same frame: buzz then answer %d" % fps)


func _tie_cases() -> void:
	var dt := 1.0 / 60.0
	var tie := 0.5 / 240.0
	var sd := _state()
	_run(sd, 60, _reading_at(sd) + 0.5)
	sd.margin = [4, 2]
	sd.step(dt, {"buzz": [0.004, 0.004 + tie]})
	check(sd.buzzer == 2, "tie: within 1/240 s the lift in more danger buzzes first")
	var even := _state()
	_run(even, 60, _reading_at(even) + 0.5)
	even.step(dt, {"buzz": [0.004 + tie, 0.004]})
	check(even.buzzer == 1, "tie: level lifts alternate (question 1: P1)")
	var apart := _state()
	_run(apart, 60, _reading_at(apart) + 0.5)
	apart.step(dt, {"buzz": [0.004 + 2.0 / 240.0, 0.004]})
	check(apart.buzzer == 2, "tie: more than 1/240 s apart is not a tie")


func _extra_question_case() -> void:
	var sd := _state()
	var asked := [0]
	sd.extra_question = func() -> QuizItem:
		asked[0] += 1
		return _quiz(1, "extra%d" % asked[0])
	sd.question_index = SuddenDeathTuning.QUESTION_COUNT - 1
	sd.phase = Phase.RESULT
	sd.phase_time = 0.0
	_run(sd, 60, sd.tuning.result_hold + 0.05)
	check(asked[0] == 1 and sd.question != null and sd.question.c[0] == "extra1-0" and sd.quizzes.size() == SuddenDeathTuning.QUESTION_COUNT + 1,
		"extra: past the eighth question the generator supplies the next")


## Random duels: nobody ever loses together, and every decided duel has one loser at 0 or below.
func _never_both_case() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261003
	var decided := 0
	var bad := 0
	for duel in range(200):
		var sd := _state()
		var t := 0.0
		var dt := 1.0 / 60.0
		var guard := 0
		while sd.phase != Phase.DECIDED and guard < 60 * 400:
			guard += 1
			var input := {}
			if sd.phase == Phase.READING and rng.randf() < 0.02:
				input = {"buzz": [dt * rng.randf() if rng.randf() < 0.6 else -1.0, dt * rng.randf() if rng.randf() < 0.6 else -1.0]}
			elif sd.phase == Phase.ANSWERING and rng.randf() < 0.05:
				var slot := sd.buzzer - 1
				var choice: Array = [-1, -1]
				choice[slot] = rng.randi_range(0, 3)
				input = {"choice": choice, "choice_offset": [0.0, 0.0]}
			sd.step(dt, input)
			sd.events.clear()
			t += dt
		if sd.phase == Phase.DECIDED:
			decided += 1
			if (sd.margin[0] <= 0) == (sd.margin[1] <= 0) or sd.margin[sd.loser - 1] > 0 or sd.margin[sd.winner - 1] <= 0:
				bad += 1
	metrics["random_duels_decided"] = decided
	check(decided >= 150 and bad == 0, "random duels: one loser each time (%d decided, %d bad)" % [decided, bad])


## The same presses at 30, 60 and 120 fps decide the same way at the same time.
func _frame_rate_case() -> void:
	var results: Array = []
	for fps in [30, 60, 120]:
		var sd := _state()
		var script := Script_.new()
		var r := _reading_at(sd)
		var step := sd.tuning.result_hold + sd.tuning.question_intro
		script.presses = [[r + 1.013, 2, "buzz"], [r + 1.211, 2, 1], [r + 1.211 + step + 0.507, 1, "buzz"],
			[r + 1.211 + step + 0.507, 2, "buzz"], [r + 1.211 + step + 0.9, 1, 1]]
		var events := _run(sd, fps, 14.0, script)
		var decided := _first(events, "decided")
		results.append([sd.winner, sd.margin.duplicate(), float(decided.get("time", -1.0))])
	check(results[0][0] == results[1][0] and results[1][0] == results[2][0] and results[0][1] == results[2][1],
		"frame rate: same winner and lifts at 30/60/120 fps %s" % str(results))
	var times := [float(results[0][2]), float(results[1][2]), float(results[2][2])]
	check(times.max() - times.min() < 1.0 / 30.0 + 0.0001 and float(times[0]) > 0.0, "frame rate: decided at the same time %s" % str(times))
	metrics["frame_rate_results"] = results


func _question_cases() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261002
	var source := QuizItem.create("元の問題", PackedStringArray(["A案", "B案", "C案", "D案", "E案"]), 2, "", "OFFLINE")
	var prepared := SuddenDeathQuestions.prepare(source, rng)
	check(prepared != null and prepared.c.size() == 4 and prepared.c[prepared.a] == "C案", "questions: five choices cut to four, answer kept")
	var two := SuddenDeathQuestions.prepare(QuizItem.create("2択", PackedStringArray(["はい", "いいえ"]), 1), rng)
	check(two != null and two.c.size() == 2 and two.c[two.a] == "いいえ", "questions: two choices stay two")
	var with_image := QuizItem.create("画像", PackedStringArray(["1", "2", "3", "4"]), 0, "", "OFFLINE", "res://x.png")
	check(not SuddenDeathQuestions.is_usable(with_image), "questions: image questions are skipped")
	var provider := QuizProvider.new()
	_providers.append(provider)
	var offline := provider.offline_candidates("算数", 3, "普通")
	var played: Array = [offline[0], offline[1]]
	var tuning := SuddenDeathTuning.new()
	var quizzes := SuddenDeathQuestions.collect(provider, "算数", 3, "普通", played, tuning, rng)
	check(quizzes.size() == SuddenDeathTuning.QUESTION_COUNT, "questions: eight from the offline bank")
	var seen := {}
	var played_keys := {QuizDedup.exact_key(offline[0].q): true, QuizDedup.exact_key(offline[1].q): true}
	var all_ok := true
	for quiz: QuizItem in quizzes:
		var key := QuizDedup.exact_key(quiz.q)
		all_ok = all_ok and quiz.c.size() >= 2 and quiz.c.size() <= 4 and quiz.a >= 0 and quiz.a < quiz.c.size() \
			and not played_keys.has(key) and not seen.has(key)
		seen[key] = true
	check(all_ok, "questions: 2-4 choices, new to the match, no repeats")
	var empty := EmptyBankProvider.new()
	_providers.append(empty)
	var fallback := SuddenDeathQuestions.collect(empty, "算数", 3, "普通", [], tuning, rng)
	check(fallback.size() == SuddenDeathTuning.QUESTION_COUNT and fallback[7].c.size() >= 2, "questions: arithmetic fallback fills them all")
	check(SuddenDeathQuestions.fallback(empty, "算数", 3, rng) != null, "questions: one more arithmetic question on demand")


func _fixture() -> QuizGameState:
	var provider := EmptyBankProvider.new()
	_providers.append(provider)
	var gs := QuizGameState.new(provider)
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.subject = "算数"
	gs.game_state = Constants.STATE_PLAYING
	gs.target_count = 10
	gs.tuning.wall_speed_override = 2.9
	gs.result_ceremony_enabled = true
	gs._reset_health()
	for index in range(10):
		var choices := PackedStringArray(["正解", "不正解", "別", "他"]) if gs.num_choices_for_index(index) == 4 else PackedStringArray(["正解", "不正解"])
		gs.quiz_list.append(QuizItem.create("本編 %d" % index, choices, 0, "", "OFFLINE"))
	gs.load_current_quiz()
	return gs


func _integration_case(fps: int) -> void:
	var dt := 1.0 / float(fps)
	var gs := _fixture()
	gs.local_push_transport_enabled = true
	var requests: Array[bool] = []
	gs.sudden_death_transition_requested.connect(func(entering: bool) -> void: requests.append(entering))
	check(gs.debug_force_draw_finish() and gs.result_winner == 0 and gs.sudden_death_pending, "forced draw prepares the sudden death %d" % fps)
	check(not gs._result_round_closed, "round stays open for the sudden death %d" % fps)
	var t := 0.0
	while requests.is_empty() and t < 15.0:
		gs.update(dt)
		t += dt
	check(requests == [true] and absf(gs.result_ceremony_elapsed - QuizGameState.SUDDEN_DEATH_DESCENT_TIME) < 0.0001, "draw finale holds for the descent at 11.0 s %d" % fps)
	for _frame in range(10):
		gs.update(dt)
	var scroll := gs.world_scroll_z
	check(gs.begin_sudden_death() and gs.game_state == Constants.STATE_SUDDEN_DEATH, "begin underground %d" % fps)
	check(gs.world_scroll_z == 0.0 and gs.p1_alive and gs.p2_alive and not gs.result_presentation_active, "fresh underground start %d" % fps)
	var sd := gs.sudden_death
	check(sd.phase == Phase.INTRO and gs.sudden_death_presentation_lock and sd.quizzes.size() == SuddenDeathTuning.QUESTION_COUNT,
		"the duel waits through the descent and intro %d" % fps)
	check(not gs.uses_local_push() and not gs.is_sudden_death_runner_active(1), "nobody pushes or runs underground %d" % fps)
	gs.submit_sudden_death_key(1, "buzz", -1, 0.0)
	for _frame in range(30):
		gs.update(dt, Vector2(1.0, 1.0), Vector2(-1.0, 1.0), true, true)
	check(sd.phase == Phase.INTRO and sd.buzzer == 0 and is_equal_approx(gs.player_x, QuizGameState.SUDDEN_DEATH_START_X), "keys do nothing before the countdown %d" % fps)
	gs.start_sudden_death_countdown()
	check(sd.phase == Phase.COUNTDOWN and not gs.sudden_death_presentation_lock, "countdown after the intro %d" % fps)
	var events: Array[String] = []
	gs.sudden_death_event.connect(func(event: Dictionary) -> void: events.append(str(event.kind)))
	t = 0.0
	var flinched := false
	while requests.size() == 1 and t < 40.0:
		if sd.phase == Phase.READING and sd.revealed_count() >= 4:
			gs.submit_sudden_death_key(1, "buzz", -1, dt * 0.5)
		elif sd.phase == Phase.ANSWERING and sd.buzzer == 1:
			var key := QuizGameState.sudden_death_key_for_choice(sd.question.a, sd.question.c.size())
			gs.submit_sudden_death_key(1, "answer", key, dt * 0.25)
		gs.update(dt)
		flinched = flinched or gs.p2_damage_time > 0.0
		t += dt
	check(requests == [true, false] and sd.winner == 1 and sd.decided_by == "correct", "P1 wins with two right answers %d" % fps)
	check(flinched, "the rider of a sinking lift flinches %d" % fps)
	check("go" in events and "buzz" in events and "answer" in events and "sink" in events and "decided" in events and "caught" in events,
		"events reach the presentation %d" % fps)
	check(gs.is_flood_caught(2) and not gs.p2_alive and gs.p1_alive, "the loser goes under %d" % fps)
	check(gs.end_sudden_death(), "return to the surface %d" % fps)
	check(gs.game_state == Constants.STATE_RESULT_CEREMONY and gs.result_presentation_active and gs.result_winner == 1, "verdict replays with the winner %d" % fps)
	check(gs.sudden_death_question_count == 2 and gs.sudden_death_decided_by == "correct", "the record keeps the questions and how %d" % fps)
	check(is_equal_approx(gs.world_scroll_z, scroll) and gs.p1_alive and gs.p2_alive and not gs.is_flood_caught(2), "surface state restored %d" % fps)
	check(gs.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.EFFECT and is_equal_approx(gs.result_ceremony_elapsed, QuizGameState.RESULT_VERDICT_TIME), "from the verdict %d" % fps)
	t = 0.0
	while gs.game_state != Constants.STATE_CLEAR and t < 10.0:
		gs.update(dt)
		t += dt
	check(gs.game_state == Constants.STATE_CLEAR and gs.message_text.contains("サドンデスで P1"), "result text names the sudden death %d" % fps)
	check(absf(t - (QuizGameState.RESULT_TOTAL_DURATION - QuizGameState.RESULT_VERDICT_TIME)) < 2.0 * dt, "controls after the winner celebration %d" % fps)
	check(gs._result_round_closed, "round closed at the end %d" % fps)


## end_sudden_death(true): the ceremony waits at the verdict until released.
func _hold_case(fps: int) -> void:
	var dt := 1.0 / float(fps)
	var gs := _fixture()
	check(gs.debug_force_draw_finish() and gs.sudden_death_pending, "hold: draw %d" % fps)
	var t := 0.0
	while gs.result_ceremony_elapsed < QuizGameState.SUDDEN_DEATH_DESCENT_TIME - 0.0001 and t < 15.0:
		gs.update(dt)
		t += dt
	check(gs.begin_sudden_death(), "hold: underground %d" % fps)
	gs.start_sudden_death_countdown()
	gs.sudden_death.winner = 2
	gs.sudden_death.decided_by = "wrong"
	check(gs.end_sudden_death(true) and gs.result_return_hold and is_equal_approx(gs.result_return_regrow, 0.0), "hold: back up held %d" % fps)
	check(gs.result_winner == 2 and gs.sudden_death_lift == Vector2.ZERO, "hold: winner kept %d" % fps)
	for _frame in range(fps * 3):
		gs.update(dt)
	check(is_equal_approx(gs.result_ceremony_elapsed, QuizGameState.RESULT_VERDICT_TIME) and gs.game_state == Constants.STATE_RESULT_CEREMONY, "hold: the verdict waits %d" % fps)
	gs.release_result_return_hold()
	t = 0.0
	while gs.game_state != Constants.STATE_CLEAR and t < 10.0:
		gs.update(dt)
		t += dt
	check(gs.game_state == Constants.STATE_CLEAR and gs.message_text.contains("サドンデスで P2"), "hold: released to the controls %d" % fps)
	check(absf(t - (QuizGameState.RESULT_TOTAL_DURATION - QuizGameState.RESULT_VERDICT_TIME)) < 2.0 * dt, "hold: the celebration keeps its length %d" % fps)


## A failed or late descent ends as the plain draw (before or after begin).
func _abort_case(fps: int, after_begin: bool) -> void:
	var dt := 1.0 / float(fps)
	var gs := _fixture()
	var label := "%d %s" % [fps, "after" if after_begin else "before"]
	check(gs.debug_force_draw_finish() and gs.sudden_death_pending, "abort: draw " + label)
	var t := 0.0
	while gs.result_ceremony_elapsed < QuizGameState.SUDDEN_DEATH_DESCENT_TIME - 0.0001 and t < 15.0:
		gs.update(dt)
		t += dt
	var scroll := gs.world_scroll_z
	if after_begin:
		check(gs.begin_sudden_death(), "abort: underground " + label)
	check(gs.abort_sudden_death(true), "abort: called " + label)
	check(gs.game_state == Constants.STATE_RESULT_CEREMONY and gs.result_winner == 0 and gs.sudden_death_aborted
		and not gs.sudden_death_pending and gs.result_presentation_active, "abort: back to the draw " + label)
	check(is_equal_approx(gs.world_scroll_z, scroll) and is_equal_approx(gs.result_ceremony_elapsed, QuizGameState.SUDDEN_DEATH_ABORT_RESUME_TIME), "abort: surface restored " + label)
	check(gs._result_round_closed, "abort: round closed " + label)
	for _frame in range(fps):
		gs.update(dt)
	check(is_equal_approx(gs.result_ceremony_elapsed, QuizGameState.SUDDEN_DEATH_ABORT_RESUME_TIME), "abort: held while the towers regrow " + label)
	gs.release_result_return_hold()
	t = 0.0
	while gs.game_state != Constants.STATE_CLEAR and t < 5.0:
		gs.update(dt)
		t += dt
	check(gs.game_state == Constants.STATE_CLEAR and gs.result_winner == 0 and not gs.message_text.contains("サドンデス"), "abort: the draw ends as before " + label)
	check(absf(t - (QuizGameState.RESULT_DRAW_TOTAL_DURATION - QuizGameState.SUDDEN_DEATH_ABORT_RESUME_TIME)) < 2.0 * dt, "abort: controls at 11.2 s " + label)


func _disabled_case() -> void:
	var gs := _fixture()
	gs.sudden_death_enabled = false
	var requests: Array[bool] = []
	gs.sudden_death_transition_requested.connect(func(entering: bool) -> void: requests.append(entering))
	check(gs.debug_force_draw_finish() and not gs.sudden_death_pending, "disabled: plain draw")
	var t := 0.0
	while gs.game_state != Constants.STATE_CLEAR and t < 15.0:
		gs.update(1.0 / 60.0)
		t += 1.0 / 60.0
	check(requests.is_empty() and gs.game_state == Constants.STATE_CLEAR and gs.result_winner == 0, "disabled: the draw ends as before")


## Switched off for now (docs 20): the setting stays on, yet the draw ends as before.
func _unavailable_case() -> void:
	QuizGameState.sudden_death_available = false
	var gs := _fixture()
	var requests: Array[bool] = []
	gs.sudden_death_transition_requested.connect(func(entering: bool) -> void: requests.append(entering))
	check(gs.sudden_death_enabled and not gs.uses_sudden_death(), "unavailable: the setting alone does not turn it on")
	check(gs.debug_force_draw_finish() and not gs.sudden_death_pending, "unavailable: plain draw")
	var t := 0.0
	while gs.game_state != Constants.STATE_CLEAR and t < 15.0:
		gs.update(1.0 / 60.0)
		t += 1.0 / 60.0
	check(requests.is_empty() and gs.game_state == Constants.STATE_CLEAR and gs.result_winner == 0, "unavailable: the draw ends as before")
	QuizGameState.sudden_death_available = true


func _finale_sink_case() -> void:
	var motion := ResultFinaleMotion
	check(absf(motion.tower_height(12, 12, 9.2) - motion.stop_height(12)) < 0.01, "a draw keeps both towers up")
	check(motion.tower_height(12, 12, 9.2, true) < 0.1, "the sudden death loser sinks on a level score")
	var heights := motion.side_heights(12, 12, 1, 9.2, 2)
	check(heights.x > 1.0 and heights.y < 0.1, "camera heights follow the sunk loser")
	heights = motion.side_heights(12, 12, 1, QuizGameState.RESULT_VERDICT_TIME, 2)
	check(heights.y < 0.1, "the sudden death loser stays sunk when the verdict replays")
	var sink := QuizGameState.SUDDEN_DEATH_SINK_TIME
	check(absf(motion.branch_height(12, 12, sink - 0.1, sink) - motion.stop_height(12)) < 0.01, "branch: both towers stand before 9.0 s")
	check(motion.branch_height(12, 12, sink + 0.7, sink) < motion.stop_height(12) - 0.3, "branch: both sink together")
	check(absf(motion.branch_height(12, 12, QuizGameState.SUDDEN_DEATH_IRIS_TIME, sink) - float(motion.heights().collar)) < 0.02, "branch: sunk to the collar by the iris (10.4 s)")
	check(absf(motion.branch_height(0, 0, QuizGameState.SUDDEN_DEATH_DESCENT_TIME, sink) - float(motion.heights().collar)) < 0.02, "branch: a 0-0 draw sinks too")


# ------------------------------------------------------------------ online generation (第4章)

func _generated(count: int, label: String, seconds := 3.0) -> Array[QuizItem]:
	var items: Array[QuizItem] = []
	for index in range(count):
		var item := QuizItem.create("%s %d" % [label, index], PackedStringArray(["正解", "誤答A", "誤答B", "誤答C"]), 0, "", "GEMINI_STREAM")
		item.estimated_seconds = seconds
		items.append(item)
	return items


func _assemble_cases() -> void:
	var tuning := SuddenDeathTuning.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fallback: Array[QuizItem] = []
	for index in range(SuddenDeathTuning.QUESTION_COUNT):
		fallback.append(SuddenDeathQuestions.prepare(_generated(1, "予備%d" % index)[0], rng))
	var played: Array = [QuizItem.create("生成 2", PackedStringArray(["a", "b", "c", "d"]), 0, "", "X")]
	var generated := _generated(10, "生成")
	generated.append_array(_generated(2, "長い", 9.5))
	var result := SuddenDeathQuestions.assemble(generated, fallback, played, tuning, rng)
	var questions: Array = result.questions
	check(questions.size() == SuddenDeathTuning.QUESTION_COUNT and int(result.generated) == 8, "assemble: eight generated questions %s" % str(result.generated))
	var texts: Array[String] = []
	var answers_ok := true
	for quiz: QuizItem in questions:
		texts.append(quiz.q)
		answers_ok = answers_ok and quiz.c.size() == 4 and quiz.c[quiz.a] == "正解"
	check(answers_ok, "assemble: choices kept, answer kept")
	check(not texts.has("生成 2") and not texts.any(func(t: String) -> bool: return t.begins_with("長い")), "assemble: skips played and long questions %s" % str(texts))
	var short := SuddenDeathQuestions.assemble(_generated(2, "少し"), fallback, [], tuning, rng)
	var short_questions: Array = short.questions
	check(int(short.generated) == 2 and (short_questions[2] as QuizItem).q == fallback[2].q and (short_questions[7] as QuizItem).q == fallback[7].q,
		"assemble: the collected questions fill the rest")
	var none := SuddenDeathQuestions.assemble([] as Array[QuizItem], fallback, [], tuning, rng)
	check(int(none.generated) == 0 and (none.questions as Array).size() == 8 and (none.questions[0] as QuizItem).q == fallback[0].q,
		"assemble: nothing generated keeps the collected questions")
	var duplicate := _generated(1, "予備0")
	check(int(SuddenDeathQuestions.assemble(duplicate, fallback, [], tuning, rng).generated) == 0, "assemble: no question repeats a collected one")


func _generation_case(fps: int) -> void:
	var dt := 1.0 / float(fps)
	var gs := _fixture()
	var provider := GeneratingProvider.new()
	_providers.append(provider)
	gs.provider = provider
	check(gs.debug_force_draw_finish() and gs.sudden_death_pending, "generation: draw %d" % fps)
	check(provider.requests == 0 and gs.is_sudden_death_question_ready(), "generation: nothing asked during the ceremony %d" % fps)
	var t := 0.0
	while provider.requests == 0 and t < 15.0:
		gs.update(dt)
		t += dt
	check(absf(gs.result_ceremony_elapsed - QuizGameState.SUDDEN_DEATH_DESCENT_TIME) < 0.0001, "generation: asked at the descent, not before %d" % fps)
	check(provider.requests == 1 and provider.requested_count == QuizGameState.SUDDEN_DEATH_GENERATION_COUNT, "generation: requested as the deck starts down (11.0 s) %d" % fps)
	check(provider.excluded.has("本編 0") and provider.excluded.has("本編 9"), "generation: the round's questions are excluded %d" % fps)
	check(gs.sudden_death_generation == "generating" and not gs.is_sudden_death_question_ready(), "generation: the descent waits %d" % fps)
	provider.on_progress.call(5, QuizGameState.SUDDEN_DEATH_GENERATION_COUNT)
	check(absf(gs.sudden_death_question_progress() - 0.45) < 0.001, "generation: progress follows the arrivals %d" % fps)
	for _frame in range(fps):
		gs.update(dt)
	check(provider.requests == 1, "generation: asked once %d" % fps)
	check(gs.begin_sudden_death() and gs.sudden_death.phase == Phase.INTRO, "generation: underground while generating %d" % fps)
	var collected_first := gs.sudden_death.quizzes[0].q
	provider.on_done.call(_generated(10, "生成"))
	check(gs.is_sudden_death_question_ready() and gs.sudden_death_generation == "done" and gs.sudden_death_generated_count == 8, "generation: done, eight questions %d" % fps)
	var all_generated := true
	for quiz: QuizItem in gs.sudden_death.quizzes:
		all_generated = all_generated and quiz.q.begins_with("生成")
	check(all_generated and collected_first != gs.sudden_death.quizzes[0].q, "generation: the duel uses the new questions %d" % fps)
	gs.start_sudden_death_countdown()
	provider.on_done.call(_generated(10, "遅れ"))
	check(gs.sudden_death.quizzes[0].q.begins_with("生成"), "generation: a late answer changes nothing %d" % fps)


## Run a forced draw to the descent (11.0 s), where the generation is requested.
func _reach_descent(gs: QuizGameState) -> void:
	gs.debug_force_draw_finish()
	var t := 0.0
	while not gs._sudden_death_requested and t < 15.0:
		gs.update(1.0 / 60.0)
		t += 1.0 / 60.0


func _generation_fallback_cases() -> void:
	# Nothing usable arrives: the collected questions stay.
	var gs := _fixture()
	var provider := GeneratingProvider.new()
	_providers.append(provider)
	gs.provider = provider
	_reach_descent(gs)
	var collected: Array[String] = []
	for quiz: QuizItem in gs._sudden_death_questions:
		collected.append(quiz.q)
	provider.on_done.call(_generated(3, "長い", 9.0))
	var kept: Array[String] = []
	for quiz: QuizItem in gs._sudden_death_questions:
		kept.append(quiz.q)
	check(gs.sudden_death_generation == "failed" and gs.is_sudden_death_question_ready() and kept == collected, "generation: nothing usable keeps the collected questions")
	# The provider never answers: give up after the limit.
	var slow := _fixture()
	var silent := GeneratingProvider.new()
	_providers.append(silent)
	slow.provider = silent
	_reach_descent(slow)
	slow.update(1.0 / 60.0)
	check(not slow.is_sudden_death_question_ready(), "generation: waits within the limit")
	slow._sudden_death_generation_started_msec -= QuizGameState.SUDDEN_DEATH_GENERATION_LIMIT_MSEC + 1
	slow.update(1.0 / 60.0)
	check(slow.is_sudden_death_question_ready() and slow.sudden_death_generation == "failed", "generation: gives up after %d ms" % QuizGameState.SUDDEN_DEATH_GENERATION_LIMIT_MSEC)
	silent.on_done.call(_generated(10, "生成"))
	check(slow.sudden_death_generated_count == 0, "generation: a reply after giving up is ignored")
	# Offline or no API: nothing to wait for.
	var offline := _fixture()
	var refusing := GeneratingProvider.new()
	refusing.accept = false
	_providers.append(refusing)
	offline.provider = refusing
	_reach_descent(offline)
	check(refusing.requests == 1 and offline.sudden_death_generation == "" and offline.is_sudden_death_question_ready(), "generation: offline does not wait")
	# Aborting the descent drops the request.
	var aborted := _fixture()
	var dropped := GeneratingProvider.new()
	_providers.append(dropped)
	aborted.provider = dropped
	_reach_descent(aborted)
	aborted.abort_sudden_death(false)
	dropped.on_done.call(_generated(10, "生成"))
	check(aborted.sudden_death_generated_count == 0 and aborted.is_sudden_death_question_ready(), "generation: an aborted descent ignores the reply")


# ------------------------------------------------------------------ the stage (第6・7章)

## The duel camera, the towers, the flow's view of the hall.
func _stage_cases() -> void:
	var shot := SuddenDeathDirector.duel_wide_shot()
	var view := shot.affine_inverse()
	var p1 := view * (SuddenDeathLayout.lift_position(1) + Vector3(0.0, 4.0, 0.0))
	var p2 := view * (SuddenDeathLayout.lift_position(2) + Vector3(0.0, 4.0, 0.0))
	check(p1.z < 0.0 and p2.z < 0.0 and p1.x < 0.0 and p2.x > 0.0, "duel shot: P1 on the left, P2 on the right, both in front (%s %s)" % [str(p1), str(p2)])
	var forward := -shot.basis.z
	check(forward.z > 0.9 and shot.origin.z < SuddenDeathLayout.LIFT_Z, "duel shot: from upstream, looking down the hall past the towers")
	var half_fov := deg_to_rad(SuddenDeathDirector.DUEL_FOV * 0.5)
	var in_frame := true
	for point: Vector3 in [p1, p2]:
		in_frame = in_frame and absf(point.y / -point.z) < tan(half_fov) and absf(point.x / -point.z) < tan(half_fov) * 16.0 / 9.0
	check(in_frame, "duel shot: both riders in frame at 16:9")
	var bed := CisternFlow.bed_heights()
	check(bed.size() == CisternFlow.GRID.x * CisternFlow.GRID.y, "flow: one floor height per cell")
	# line 8 (z = 0, the landing's line) has a pillar in the row v = -7
	var pillar := CisternFlow.cell_of(Vector2(SuddenDeathLayout.pillar_xs(8)[3], SuddenDeathLayout.line_z(8)))
	var tower := CisternFlow.cell_of(Vector2(SuddenDeathLayout.LIFT_X, SuddenDeathLayout.LIFT_Z))
	var tunnel := CisternFlow.cell_of(Vector2(0.0, -29.8))
	check(bed[pillar.y * CisternFlow.GRID.x + pillar.x] >= 20.0, "flow: the pillars are solid")
	check(bed[tower.y * CisternFlow.GRID.x + tower.x] == 0.0 and bed[tunnel.y * CisternFlow.GRID.x + tunnel.x] == 0.0, "flow: open floor at the towers and the tunnel mouth")
	# pillars inside the side walls (the grid reaches past the walls, which are solid too)
	var solid := 0
	for j in range(CisternFlow.GRID.y):
		var z := CisternFlow.ORIGIN.y + (float(j) + 0.5) * CisternFlow.CELL
		var wall := SuddenDeathLayout.wall_half_width(z)
		for i in range(CisternFlow.GRID.x):
			var x := CisternFlow.ORIGIN.x + (float(i) + 0.5) * CisternFlow.CELL
			if absf(x) < wall and bed[j * CisternFlow.GRID.x + i] >= 20.0:
				solid += 1
	metrics["flow_solid_cells"] = solid
	check(solid > 0 and solid < bed.size() / 10, "flow: pillars take a small part of the hall (%d cells)" % solid)
	check(CisternFlow.MAX_SPEED * CisternFlow.SIM_DT < 0.5 * CisternFlow.CELL, "flow: under half a cell a step")
	var level := SuddenDeathTuning.new().water_level
	check(SuddenDeathTuning.new().sunk_height() < level and SuddenDeathTuning.new().lift_height(1) > level, "lift: a step above the water until it goes under")


## The cistern is ready but the questions are still being generated: keep cruising.
func _descent_waiting_cases() -> void:
	for fps in [30, 60, 120]:
		var dt := 1.0 / float(fps)
		for case: Array in [[20.0, "long"], [32.0, "past the timeout"], [1.0, "short"]]:
			var done_at: float = case[0]
			var descent := SuddenDeathDescent.new()
			var decel_at := -1.0
			var down_at := -1.0
			var aborted := false
			var guard := 0
			while not descent.is_finished() and guard < 100000:
				guard += 1
				descent.set_preparation(0.5, descent.t >= 1.0, false, descent.t < done_at)
				descent.advance(dt)
				aborted = aborted or descent.is_aborting()
				if descent.stage == SuddenDeathDescent.Stage.DECEL and decel_at < 0.0:
					decel_at = descent.t - descent.stage_time
				if descent.shot == SuddenDeathDescent.Shot.DOWN and down_at < 0.0:
					down_at = descent.t
			var expected := maxf(done_at, SuddenDeathDescent.ENTRY_TIME + SuddenDeathDescent.ACCEL_TIME + SuddenDeathDescent.MIN_CRUISE)
			check(not aborted and descent.is_landed(), "waiting %s: lands, never aborts %d" % [case[1], fps])
			check(decel_at >= expected - 0.0001 and decel_at < expected + dt + 0.001, "waiting %s: decelerates once the questions are in %d (%.3f)" % [case[1], fps, decel_at])
			if done_at > 12.0:
				check(absf(down_at - (2.4 + SuddenDeathDescent.SLOW_AFTER)) < dt + 0.0001, "waiting %s: looks straight down after 8 s %d" % [case[1], fps])
	# Waiting does not excuse a cistern that never loads: still aborted at 25 s.
	var stuck := SuddenDeathDescent.new()
	while not stuck.is_aborting() and stuck.t < 40.0:
		stuck.set_preparation(0.2, false, false, true)
		stuck.advance(1.0 / 60.0)
	check(stuck.is_aborting() and absf(stuck.t - SuddenDeathDescent.TIMEOUT) < 0.05, "waiting: an unloaded cistern still times out at 25 s")


# ------------------------------------------------------------------ descent timeline (第5章)

## Run a descent with frame time `dt`; `ready_at` < 0 = never; `fail_at` < 0 = never.
## `stall` = [time, seconds] one long frame.
func _descend(dt: float, ready_at: float, fail_at := -1.0, stall := [-1.0, 0.0]) -> Dictionary:
	var descent := SuddenDeathDescent.new()
	var log := {"stages": [], "max_speed_step": 0.0, "max_down_step": 0.0, "display_ok": true, "monotonic": true,
		"slow_shot_at": -1.0, "landed_at": -1.0, "aborted_at": -1.0, "decel_at": -1.0, "decel_display": 0.0}
	var stalled := false
	var last_stage := -1
	var guard := 0
	while not descent.is_finished() and guard < 200000:
		guard += 1
		var step := dt
		if not stalled and float(stall[0]) >= 0.0 and descent.t >= float(stall[0]):
			step = float(stall[1])
			stalled = true
		var progress := clampf(descent.t / maxf(ready_at, 0.1), 0.0, 0.95) if ready_at > 0.0 else clampf(descent.t / 40.0, 0.0, 0.9)
		descent.set_preparation(progress, ready_at >= 0.0 and descent.t >= ready_at, fail_at >= 0.0 and descent.t >= fail_at)
		var before_speed := descent.speed
		var before_distance := descent.distance
		descent.advance(step)
		if step <= dt * 1.01:
			log.max_speed_step = maxf(log.max_speed_step, absf(descent.speed - before_speed))
		if not descent.is_aborting() and descent.distance < before_distance - 0.0001:
			log.monotonic = false
		if descent.stage in [SuddenDeathDescent.Stage.ENTRY, SuddenDeathDescent.Stage.ACCEL, SuddenDeathDescent.Stage.CRUISE]:
			if descent.display_depth > SuddenDeathDescent.DISPLAY_SOFT + SuddenDeathDescent.DISPLAY_PROGRESS * descent.progress + 0.001:
				log.display_ok = false
		if descent.shot == SuddenDeathDescent.Shot.DOWN and log.slow_shot_at < 0.0:
			log.slow_shot_at = descent.t
		if descent.stage == SuddenDeathDescent.Stage.DECEL and log.decel_at < 0.0:
			log.decel_at = descent.t - descent.stage_time
			log.decel_display = descent.display_depth
		if descent.stage != last_stage:
			last_stage = descent.stage
			(log.stages as Array).append(SuddenDeathDescent.Stage.keys()[descent.stage])
	log.landed_at = descent.t if descent.is_landed() else -1.0
	log.aborted_at = descent.t if descent.stage == SuddenDeathDescent.Stage.ABORTED else -1.0
	log.final_display = descent.display_depth
	log.final_distance = descent.distance
	log.cruise = descent.cruise_time
	log.speed = descent.speed
	return log


func _descent_cases() -> void:
	var tolerance := 1.0 / 30.0
	var landed_times: Array[float] = []
	for fps in [30, 60, 120]:
		var dt := 1.0 / float(fps)
		# Ready early: the minimum 3.0 s cruise, then decel 1.2 s and the 2.6 s arrival.
		var fast := _descend(dt, 1.0)
		var expected_decel := SuddenDeathDescent.ENTRY_TIME + SuddenDeathDescent.ACCEL_TIME + SuddenDeathDescent.MIN_CRUISE
		check(absf(float(fast.decel_at) - expected_decel) < dt + 0.0001, "descent: minimum cruise %d (%.3f)" % [fps, fast.decel_at])
		check(absf(float(fast.landed_at) - (expected_decel + SuddenDeathDescent.DECEL_TIME + SuddenDeathDescent.ARRIVAL_TIME)) < 2.0 * dt, "descent: lands after decel + arrival %d" % fps)
		check(absf(float(fast.decel_display) - 54.0) < 1.5, "descent: about 54 m shown when ready at the shortest %d (%.1f)" % [fps, fast.decel_display])
		check(is_equal_approx(float(fast.final_display), SuddenDeathDescent.DISPLAY_FINAL), "descent: 70 m at the bottom %d" % fps)
		check(bool(fast.monotonic) and bool(fast.display_ok), "descent: steady and the meter honours the soft cap %d" % fps)
		check(float(fast.max_speed_step) < 25.0 * dt + 0.05, "descent: speed changes smoothly %d (%.3f)" % [fps, fast.max_speed_step])
		check((fast.stages as Array) == ["ENTRY", "ACCEL", "CRUISE", "DECEL", "ARRIVAL", "LANDED"], "descent: stage order %d" % fps)
		check(float(fast.slow_shot_at) < 0.0, "descent: no long-wait shot when ready %d" % fps)
		landed_times.append(float(fast.landed_at))
		# A long wait slows to 6 m/s and looks straight down after 8 s of cruise.
		var slow := _descend(dt, 14.0)
		check(absf(float(slow.slow_shot_at) - (2.4 + SuddenDeathDescent.SLOW_AFTER)) < dt + 0.0001, "descent: long wait shot after 8 s %d" % fps)
		check(float(slow.decel_at) >= 14.0 - 0.0001 and float(slow.decel_at) < 14.0 + dt + 0.001, "descent: decelerates as soon as ready %d" % fps)
		check(float(slow.landed_at) > 0.0 and is_equal_approx(float(slow.final_display), SuddenDeathDescent.DISPLAY_FINAL), "descent: slow load still lands %d" % fps)
		# Never ready: give up at 25 s, stop, go back up to the surface.
		var timeout := _descend(dt, -1.0)
		check((timeout.stages as Array).has("ABORT_STOP") and float(timeout.aborted_at) > SuddenDeathDescent.TIMEOUT, "descent: timeout returns %d" % fps)
		check(is_zero_approx(float(timeout.final_distance)) and is_zero_approx(float(timeout.final_display)) and is_zero_approx(float(timeout.speed)), "descent: back at the surface %d" % fps)
		# A failed load turns back at the cruise start.
		var failed := _descend(dt, -1.0, 0.5)
		check((failed.stages as Array).slice(0, 4) == ["ENTRY", "ACCEL", "CRUISE", "ABORT_STOP"] or (failed.stages as Array).slice(0, 3) == ["ENTRY", "ACCEL", "ABORT_STOP"], "descent: failure turns back %d" % fps)
		check(float(failed.aborted_at) > 0.0 and float(failed.aborted_at) < 15.0, "descent: failure returns quickly %d (%.2f)" % [fps, failed.aborted_at])
	check(landed_times.max() - landed_times.min() < 2.0 * tolerance, "descent: same landing time at 30/60/120 fps")
	# A 2.1 s stall jumps ahead without losing time (docs 5.5).
	var stalled := _descend(1.0 / 60.0, 1.0, -1.0, [3.0, 2.1])
	check(absf(float(stalled.landed_at) - landed_times[1]) < 2.0 / 60.0, "descent: a stalled frame keeps the timetable (%.3f)" % stalled.landed_at)
	var cross := _descend(1.0 / 60.0, 1.0, -1.0, [5.0, 3.0])
	check((cross.stages as Array).has("LANDED") and absf(float(cross.landed_at) - landed_times[1]) < 2.0 / 60.0, "descent: one frame across decel and arrival still lands on time")
	var anchor := SuddenDeathDescent.new()
	check(absf(SuddenDeathDescent.entry_total() - 6.2) < 0.001 and absf(SuddenDeathDescent.decel_distance(10.0) - 7.2) < 0.001, "descent: entry and decel distances")
	anchor.set_preparation(1.0, true, false)
	while anchor.stage != SuddenDeathDescent.Stage.DECEL:
		anchor.advance(1.0 / 60.0)
	var start_distance := anchor.distance
	var remaining := anchor.remaining_decel()
	while anchor.stage == SuddenDeathDescent.Stage.DECEL:
		anchor.advance(1.0 / 60.0)
	check(absf(start_distance + remaining - (anchor.distance - anchor.arrival_drop())) < 0.02, "descent: remaining decel lands at the ceiling")
	metrics["descent_landed_at"] = landed_times
