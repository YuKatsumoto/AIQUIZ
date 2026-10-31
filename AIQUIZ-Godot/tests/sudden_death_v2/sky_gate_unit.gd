extends Node

## 「つきやぶれ！スカイゲート」のルール（SkyGateGame、docs/sudden_death_v2/sky_gate.md 第2・3章、skygate_build_plan.md 4.5）を
## ヘッドレスで確かめる。2026-10-25 から時間制限は無く、4 枚のボードの列が一定の速さで上がってきて、当たった瞬間に判定する。
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/sudden_death_v2/sky_gate_unit_bootstrap.gd
## 結果は標準出力の SKY_GATE_UNIT {...}（checks・failures）。

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
	_test_contract()
	_test_column()
	_test_correct()
	_test_wrong()
	_test_impact()
	_test_timeout_position()
	_test_same_panel_push()
	_test_bounds()
	_test_gaps()
	_test_both_out_revive()
	_test_both_out_last_gate()
	_test_round_flow()
	_test_overtime_and_speed()
	_test_speed_tie()
	_test_frame_rate_scripted()
	_test_frame_rate_autopilot()
	_test_keys_ignored()
	_test_extra_questions()
	_test_state_input()
	print("SKY_GATE_UNIT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ helpers

func _quizzes(count := SkyGateGame.QUESTION_COUNT) -> Array[QuizItem]:
	var out: Array[QuizItem] = []
	for i in range(count):
		out.append(QuizItem.create("問題%d" % i, PackedStringArray(["あ%d" % i, "い", "う", "え"]), (i * 3 + 1) % 4, "", "TEST"))
	return out


func _game(seed_value := 7, count := SkyGateGame.QUESTION_COUNT) -> SkyGateGame:
	var game := SkyGateGame.new()
	game.setup(_quizzes(count), seed_value)
	game.extra_question = func() -> QuizItem:
		return QuizItem.create("足し算", PackedStringArray(["1", "2", "3", "4"]), 2, "", "TEST")
	game.start()
	return game


func _moves(p1 := Vector2.ZERO, p2 := Vector2.ZERO) -> Dictionary:
	return {"move": [p1, p2]}


## 目標の点（ボードの座標）へ向かう押しっぱなしの向き。近ければ離す。
static func _steer(game: SkyGateGame, slot: int, target: Vector2) -> Vector2:
	var d := target - game.pos[slot]
	if d.length() < 0.25:
		return Vector2.ZERO
	return d.normalized() * clampf(d.length() / 1.5, 0.35, 1.0)


## パネルの中心（ボードの座標、今のずれと大きさで）。
static func _panel_point(game: SkyGateGame, panel: int) -> Vector2:
	return SkyGateBoard.PANEL_CENTERS[panel] * game.board_scale() + Vector2(game.board_offset(), 0.0)


## 2人がそれぞれのパネルへ向かいながら、今のゲートの判定まで進める（-1 = 動かない）。返り値はそのゲートの gate_pass。
## 当たった（gate_impact）あと、つき破る動きの間（impact）も進めて判定を待つ。
func _play_gate(game: SkyGateGame, p1_panel: int, p2_panel: int, fps := 60, offsets := [Vector2.ZERO, Vector2.ZERO]) -> Dictionary:
	var dt := 1.0 / float(fps)
	var index := game.gate_index
	var guard := 0
	while not game.finished and game.phase in ["gate", "impact"] and game.gate_index == index and guard < 20000:
		guard += 1
		var moves := [Vector2.ZERO, Vector2.ZERO]
		for slot in [0, 1]:
			var panel: int = [p1_panel, p2_panel][slot]
			if panel >= 0:
				moves[slot] = _steer(game, slot, _panel_point(game, panel) + (offsets[slot] as Vector2) * game.board_scale())
		game.step(dt, _moves(moves[0], moves[1]))
		for i in range(game.events.size()):
			if str(game.events[i].kind) == "gate_pass":
				# 判定より後の出来事（out・decided・both_out）は残す
				var found := game.events[i]
				game.events = game.events.slice(i + 1)
				return found
		game.events.clear()
	return {}


## 判定のあと、次のゲート（または次の段階）まで進める。
func _until_next(game: SkyGateGame, fps := 60) -> Array[Dictionary]:
	var dt := 1.0 / float(fps)
	var seen: Array[Dictionary] = []
	var guard := 0
	while not game.finished and game.phase != "gate" and game.phase != "landing" and guard < 20000:
		guard += 1
		game.step(dt, _moves())
		seen.append_array(game.events)
		game.events.clear()
	return seen


func _kinds(events: Array) -> Array[String]:
	var out: Array[String] = []
	for event: Dictionary in events:
		out.append(str(event.kind))
	return out


func _wrong(game: SkyGateGame) -> int:
	return (game.correct_choice() + 1) % 4


## 2人とも正解してラウンドを終える（ROUND 5 は延長に入ったところで止める）。
func _clear_round(game: SkyGateGame) -> void:
	while not game.finished and game.phase == "gate" and not game.overtime:
		var right := game.correct_choice()
		_play_gate(game, right, right)
		_until_next(game)


# ------------------------------------------------------------------ tests

func _test_contract() -> void:
	var game := SkyGateGame.new()
	check(game.kind == "sky_gate", "kind is sky_gate")
	check(game is SuddenDeathGame, "SkyGateGame extends SuddenDeathGame")
	game.setup(_quizzes(), 3)
	check(game.waiting_for_start and not game.is_running(), "waits for start()")
	game.step(0.5, _moves(Vector2.RIGHT, Vector2.LEFT))
	check(game.events.is_empty() and game.pos[0] == SkyGateGame.spawn_point(1), "no clock before start()")
	game.start()
	var kinds := _kinds(game.events)
	check(kinds == ["round_start", "gate"], "start emits round_start and gate: %s" % str(kinds))
	var rs: Dictionary = game.events[0]
	check(int(rs.round) == 1 and int(rs.gates) == 4 and is_equal_approx(float(rs.speed), 8.0), "round_start fields")
	check(is_equal_approx(float(rs.gap), SkyGateGame.BOARD_GAP) and is_equal_approx(float(rs.first_depth), SkyGateGame.FIRST_DEPTH),
		"round_start carries the column")
	check(rs.board_size == Vector2(17.0, 12.2), "round 1 board is 17 x 12.2")
	var listed: Array = rs.get("questions", [])
	check(listed.size() == 4 and str((listed[3] as Dictionary).question) == "問題3", "round_start lists the 4 questions: %d" % listed.size())
	var gate: Dictionary = game.events[1]
	for key: String in ["round", "index", "question", "choices", "correct", "depth", "speed"]:
		check(gate.has(key), "gate event has " + key)
	check(not gate.has("time"), "no time limit in the gate event")
	check(int(gate.index) == 0 and str(gate.question) == "問題0" and (gate.choices as Array).size() == 4, "gate carries the question")
	check(int(gate.correct) == game.correct_choice(), "gate carries the correct choice")
	check(game.pos[0].x < 0.0 and game.pos[1].x > 0.0, "P1 starts on the left, P2 on the right")
	check(SkyGateGame.QUESTION_COUNT == 20, "5 rounds x 4 questions")
	check(game.board_offset() == 0.0, "round 1 board does not move")


## 4 枚の列：始まる前から問題がそろっていて、一定の速さで上がってきて、紙に触れた瞬間に当たる。
func _test_column() -> void:
	var game := SkyGateGame.new()
	var quizzes := _quizzes()
	game.setup(quizzes, 3)
	check(game.board_count() == 4, "4 boards from the start")
	for k in range(4):
		check(game.column_quiz(k) == quizzes[k], "board %d carries question %d before the start" % [k, k])
		check(is_equal_approx(game.board_depth(k), SkyGateGame.FIRST_DEPTH + float(k) * SkyGateGame.BOARD_GAP), "board %d hangs below in a column" % k)
	game.step(2.0, _moves())
	check(is_equal_approx(game.board_depth(0), SkyGateGame.FIRST_DEPTH), "the column waits before start()")
	# 始まる前に問題が差し替わったら（AI の問題）、列はそれを読む
	var swapped := _quizzes()
	swapped[1] = QuizItem.create("差し替え", PackedStringArray(["a", "b", "c", "d"]), 0, "", "TEST")
	game.quizzes = swapped.duplicate()
	check(game.column_quiz(1).q == "差し替え", "the column reads swapped questions")
	game.start()
	game.events.clear()
	var right := game.correct_choice()
	var dt := 1.0 / 60.0
	var t := 0.0
	var start_depth := game.board_depth(0)
	for _i in range(60):
		game.step(dt, _moves(_steer(game, 0, _panel_point(game, right)), _steer(game, 1, _panel_point(game, right))))
		t += dt
	check(absf(start_depth - game.board_depth(0) - 8.0) < 0.01, "the column rises 8 m/s in round 1 (%.3f)" % (start_depth - game.board_depth(0)))
	check(absf(game.board_depth(1) - game.board_depth(0) - SkyGateGame.BOARD_GAP) < 0.0001, "the boards keep their gap")
	check(absf(game.time_to_contact() - (game.board_depth(0) - SkyGateImpact.CONTACT) / 8.0) < 0.0001, "time to contact")
	var progress := game.gate_progress()
	check(progress > 0.08 and progress < 0.14, "gate progress after 1 s (%.3f)" % progress)
	var impact := {}
	while game.phase == "gate" and t < 30.0:
		game.step(dt, _moves(_steer(game, 0, _panel_point(game, right)), _steer(game, 1, _panel_point(game, right))))
		t += dt
		for event: Dictionary in game.events:
			if str(event.kind) == "gate_impact":
				impact = event
		game.events.clear()
	var expected := (SkyGateGame.FIRST_DEPTH - SkyGateImpact.CONTACT) / 8.0
	check(not impact.is_empty() and absf(t - expected) < dt + 0.001, "contact after %.2f s (%.3f)" % [expected, t])
	check(int(impact.get("mode", -1)) == SkyGateImpact.ALL_BURST, "both right: all burst")
	check(game.board_depth(0) <= SkyGateImpact.CONTACT + 0.0001 and game.board_depth(0) > SkyGateImpact.CONTACT - 0.2,
		"the board is at the bodies at contact (%.3f)" % game.board_depth(0))
	# 全員が正解：列は止まらず、BURST_IMPACT_TIME で判定 → すぐ次のボード
	var fall := game.column_fall
	var waited := 0.0
	var next := {}
	while game.phase == "impact" and waited < 2.0:
		game.step(dt, _moves())
		waited += dt
		for event: Dictionary in game.events:
			if str(event.kind) == "gate":
				next = event
		game.events.clear()
	check(absf(waited - SkyGateGame.BURST_IMPACT_TIME) < dt + 0.001, "all burst: verdict after %.1f s (%.3f)" % [SkyGateGame.BURST_IMPACT_TIME, waited])
	check(game.column_fall > fall + 1.5, "the column keeps rising through the burst")
	var next_depth := SkyGateGame.FIRST_DEPTH + SkyGateGame.BOARD_GAP - (SkyGateGame.FIRST_DEPTH - SkyGateImpact.CONTACT + 8.0 * SkyGateGame.BURST_IMPACT_TIME)
	check(game.phase == "gate" and int(next.get("index", -1)) == 1, "the next board right after the verdict")
	check(absf(float(next.get("depth", 0.0)) - next_depth) < 0.01, "the next board was already below (%.2f m)" % float(next.get("depth", 0.0)))
	check(game.column_quiz(1).q == "差し替え" and str(next.get("question", "")) == "差し替え", "the next board is the second of the column")


func _test_correct() -> void:
	var game := _game()
	var right := game.correct_choice()
	var pass_event := _play_gate(game, right, right)
	check(not pass_event.is_empty(), "gate_pass arrives")
	check(pass_event.results == ["burst", "burst"], "both on the right panel burst: %s" % str(pass_event.get("results")))
	check(pass_event.panels == [right, right], "panels are the panels under them")
	check(game.phase == "gate" and game.gate_index == 1, "next gate right after the verdict (no waiting)")
	check(_kinds(game.events) == ["gate"], "only the next gate: %s" % str(_kinds(game.events)))
	check(game.passes == [1, 1], "passes counted")


func _test_wrong() -> void:
	var game := _game()
	var right := game.correct_choice()
	var wrong := _wrong(game)
	var pass_event := _play_gate(game, right, wrong)
	check(pass_event.results == ["burst", "boom"], "P2 on a wrong panel booms")
	check(game.finished and game.winner == 1 and game.decided_by == "out", "P1 wins by out")
	check(game.loser == 2, "loser is P2")
	var kinds := _kinds(game.events)
	check(kinds == ["out", "decided"], "out then decided: %s" % str(kinds))
	var decided: Dictionary = game.events[1]
	check(int(decided.winner) == 1 and str(decided.by) == "out" and int(decided.round) == 1 and int(decided.index) == 0, "decided fields")
	var out: Dictionary = game.events[0]
	check(int(out.player) == 2, "out names the player")
	game.events.clear()
	game.step(1.0, _moves(Vector2.RIGHT, Vector2.RIGHT))
	check(game.events.is_empty(), "nothing after the decision")
	# P1 だけまちがい
	var game2 := _game()
	_play_gate(game2, _wrong(game2), game2.correct_choice())
	check(game2.winner == 2 and game2.decided_by == "out", "P2 wins when P1 booms")


## 当たる → 脱落のスロー（SkyGateImpact.wasted_real_time）→ 判定。当たった瞬間に位置が止まり、正解かどうかは gate_impact で
## 決まっているが、判定（gate_pass・out・decided）は動きを見せ終えてから出る。まちがいがいる間は列が止まる。
func _test_impact() -> void:
	var game := _game()
	var right := game.correct_choice()
	var wrong := _wrong(game)
	var dt := 1.0 / 60.0
	var impact := {}
	var early_verdict := false
	var guard := 0
	while game.phase == "gate" and guard < 2000:
		guard += 1
		game.step(dt, _moves(_steer(game, 0, _panel_point(game, right)), _steer(game, 1, _panel_point(game, wrong))))
		for event: Dictionary in game.events:
			if str(event.kind) == "gate_impact":
				impact = event
			elif str(event.kind) in ["gate_pass", "out", "decided"]:
				early_verdict = true
		game.events.clear()
	check(game.phase == "impact" and not impact.is_empty(), "contact: gate_impact and the impact phase")
	check(not early_verdict and not game.finished, "no verdict at the contact")
	check(int(impact.get("mode", -1)) == SkyGateImpact.MIXED, "one right, one wrong: mixed")
	check(impact.get("results", []) == ["burst", "boom"], "the impact already knows who breaks through: %s" % str(impact.get("results")))
	check(impact.get("panels", []) == [right, wrong], "the impact names the panels under them")
	var at := [game.pos[0], game.pos[1]]
	var fall := game.column_fall
	var waited := 0.0
	var verdict := {}
	var kinds: Array[String] = []
	while game.phase == "impact" and waited < 8.0:
		game.step(dt, _moves(Vector2.RIGHT, Vector2.LEFT))
		waited += dt
		kinds.append_array(_kinds(game.events))
		for event: Dictionary in game.events:
			if str(event.kind) == "gate_pass":
				verdict = event
		game.events.clear()
	var boom_time := SkyGateImpact.wasted_real_time(SkyGateImpact.BOOM_JUDGE_AT, SkyGateImpact.MIXED)
	check(absf(waited - boom_time) < 0.02, "verdict %.2f s after the contact (%.3f)" % [boom_time, waited])
	check(boom_time > 2.5 and boom_time < 5.0, "the wasted slow-mo takes %.2f s" % boom_time)
	check(game.column_fall == fall, "the column holds while someone is wrong")
	check(kinds == ["gate_pass", "out", "decided"], "then the verdict: %s" % str(kinds))
	check(verdict.get("results", []) == impact.get("results", []) and verdict.get("panels", []) == impact.get("panels", []),
		"the verdict matches the impact")
	check(game.pos[0] == at[0] and game.pos[1] == at[1], "positions frozen during the impact")
	check(game.finished and game.winner == 1, "P1 wins after the verdict")
	check(SkyGateImpact.EXPLODE_AT < SkyGateImpact.BOOM_JUDGE_AT, "the explosion comes before the verdict")
	check(absf(SkyGateImpact.wasted_scale(0.4, SkyGateImpact.MIXED) - SkyGateImpact.WASTED_SLOW) < 0.001, "slow-mo right after the hit")
	check(absf(SkyGateImpact.wasted_scale(SkyGateImpact.EXPLODE_AT, SkyGateImpact.ALL_BOOM) - SkyGateImpact.WASTED_SLOW) < 0.001,
		"still slow at the explosion")
	check(SkyGateImpact.wasted_scale(SkyGateImpact.BOOM_JUDGE_AT, SkyGateImpact.MIXED) > 0.999, "back to full speed by the verdict")
	check(SkyGateImpact.wasted_scale(0.4, SkyGateImpact.ALL_BURST) == 1.0, "no slow-mo when all break through")
	check(SkyGateImpact.wasted_amount(0.4, SkyGateImpact.MIXED) > 0.99 and SkyGateImpact.wasted_amount(0.4, SkyGateImpact.ALL_BURST) == 0.0,
		"colour drains only with a boom")
	var scene := SkyGateImpact.wasted_scene_time(boom_time, SkyGateImpact.MIXED)
	check(absf(scene - SkyGateImpact.BOOM_JUDGE_AT) < 0.02, "scene time and real time agree (%.3f)" % scene)
	check(SkyGateImpact.through_alpha(0.6, 8.0) < 0.01 and SkyGateImpact.through_alpha(0.05, 8.0) > 0.99, "an all-burst board fades as it passes")
	check(SkyGateImpact.rel_height(true, SkyGateImpact.THROUGH_END) < -3.0, "the right panel lets the body through")
	check(SkyGateImpact.body_height(true, SkyGateImpact.ALL_BURST, 0.8) == 0.0, "the body that breaks through stays in place (the board moves)")
	check(SkyGateImpact.board_alpha(SkyGateImpact.MIXED, SkyGateImpact.EXPLODE_AT) > 0.99, "with a boom, the board stays until the explosion")
	check(SkyGateImpact.rel_height(false, SkyGateImpact.BOUNCE_END) > 3.0, "the wrong panel throws the body back up")
	check(SkyGateImpact.dent(false, SkyGateImpact.STRETCH_END) > 0.6, "the wrong panel stretches but holds")


## 当たった瞬間の位置で判定：正解のパネルにいても、最後に離れたら外れ。最後に入れば当たり。
func _test_timeout_position() -> void:
	var game := _game()
	var right := game.correct_choice()
	var wrong := _wrong(game)
	var dt := 1.0 / 60.0
	# P1：初めは正解、最後の 1.2 秒でまちがいへ。P2：初めはまちがい、最後の 1.2 秒で正解へ。
	var guard := 0
	var pass_event := {}
	while game.phase in ["gate", "impact"] and guard < 2000:
		guard += 1
		var late := game.phase == "gate" and game.time_to_contact() < 1.2
		var m1 := _steer(game, 0, _panel_point(game, wrong if late else right))
		var m2 := _steer(game, 1, _panel_point(game, right if late else wrong))
		game.step(dt, _moves(m1, m2))
		for event: Dictionary in game.events:
			if str(event.kind) == "gate_pass":
				pass_event = event
		game.events.clear()
	check(pass_event.get("results", []) == ["boom", "burst"], "judged where they are at the contact: %s" % str(pass_event.get("results")))
	check(game.winner == 2, "the late mover onto the right panel wins")
	# 動かなければ真下のパネル（はじめの位置）で判定
	var game2 := _game()
	var still := SkyGateGame.panel_for_local(game2.local_point(0))
	var still2 := SkyGateGame.panel_for_local(game2.local_point(1))
	var event2 := _play_gate(game2, -1, -1)
	check(event2.get("panels", []) == [still, still2], "no input: the panels under the spawn points")


func _test_same_panel_push() -> void:
	var game := _game()
	var right := game.correct_choice()
	var min_gap := INF
	var dt := 1.0 / 60.0
	var pass_event := {}
	while game.phase in ["gate", "impact"] and game.gate_index == 0:
		var target := _panel_point(game, right)
		game.step(dt, _moves(_steer(game, 0, target), _steer(game, 1, target)))
		min_gap = minf(min_gap, game.pos[0].distance_to(game.pos[1]))
		for event: Dictionary in game.events:
			if str(event.kind) == "gate_pass":
				pass_event = event
		game.events.clear()
	check(min_gap >= SkyGateGame.BODY_GAP - 0.01, "bodies push apart (closest %.3f m)" % min_gap)
	check(pass_event.get("panels", []) == [right, right], "both can choose the same panel")
	check(pass_event.get("results", []) == ["burst", "burst"], "both burst the same panel")
	# ぴったり重ねても P1 が左へ
	var game2 := _game()
	game2.pos[0] = Vector2(1.0, -1.0)
	game2.pos[1] = Vector2(1.0, -1.0)
	game2.step(SkyGateGame.TICK, _moves())
	check(game2.pos[0].x < game2.pos[1].x and game2.pos[0].distance_to(game2.pos[1]) >= SkyGateGame.BODY_GAP - 0.001, "exact overlap: P1 goes left")


func _test_bounds() -> void:
	var game := _game()
	var area := game.play_rect()
	var inside := true
	for i in range(240):
		var t := float(i) / 60.0
		var m1 := Vector2(-1.0, 1.0) if t < 2.0 else Vector2(1.0, -1.0)
		var m2 := Vector2(1.0, 1.0) if t < 2.0 else Vector2(-1.0, -1.0)
		game.step(1.0 / 60.0, _moves(m1, m2))
		game.events.clear()
		for slot in [0, 1]:
			if not area.grow(0.0001).has_point(game.pos[slot]):
				inside = false
	check(inside, "never leaves the board (panel area)")
	check(game.pos[0].distance_to(area.end) > 1.0 or game.pos[0].x >= area.position.x, "clamped")
	# 縁にいる人の真下はかならずパネル（-1 にならない）
	for corner: Vector2 in [area.position, area.end, Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.position.y)]:
		check(SkyGateGame.panel_for_local(game.to_local(corner)) >= 0, "corner %s is over a panel" % str(corner))
	# 速さ：端から端（14 m）を約 1.4 秒
	var game2 := _game()
	game2.pos[0] = Vector2(area.position.x, -1.0)
	game2.pos[1] = Vector2(area.end.x, 2.0)
	var t2 := 0.0
	while game2.pos[0].x < area.end.x - 0.05 and t2 < 5.0:
		game2.step(1.0 / 60.0, _moves(Vector2.RIGHT, Vector2.ZERO))
		game2.events.clear()
		t2 += 1.0 / 60.0
	check(t2 > 1.3 and t2 < 2.2, "across the board in about 1.7 s (%.2f s)" % t2)
	# 離すとすぐ止まる（ふわっと）
	game2.pos[0] = Vector2(-2.0, -1.0)
	for _i in range(30):
		game2.step(1.0 / 60.0, _moves(Vector2.RIGHT, Vector2.ZERO))
	var x0 := game2.pos[0].x
	for _i in range(30):
		game2.step(1.0 / 60.0, _moves())
	check(game2.pos[0].x - x0 < 1.3 and absf(game2.vel[0].x) < 0.1, "stops within 0.5 s of letting go (%.2f m)" % (game2.pos[0].x - x0))


func _test_gaps() -> void:
	for i in range(4):
		check(SkyGateGame.panel_for_local(SkyGateBoard.PANEL_CENTERS[i]) == i, "panel %d center" % i)
	check(SkyGateGame.panel_for_local(Vector2(-0.05, 1.5)) == 0, "vertical divider, left side → panel 0")
	check(SkyGateGame.panel_for_local(Vector2(0.05, 1.5)) == 1, "vertical divider, right side → panel 1")
	check(SkyGateGame.panel_for_local(Vector2(-3.0, -0.97)) == 0, "horizontal divider near the back row → 0")
	check(SkyGateGame.panel_for_local(Vector2(3.0, -1.13)) == 3, "horizontal divider near the front row → 3")
	check(SkyGateGame.panel_for_local(Vector2(0.0, 3.6)) == -1, "the question strip is not a panel")
	check(SkyGateGame.panel_for_local(Vector2(9.0, 0.0)) == -1, "outside the board")


func _test_both_out_revive() -> void:
	var game := _game()
	var wrong := _wrong(game)
	var pass_event := _play_gate(game, wrong, wrong)
	check(pass_event.results == ["boom", "boom"], "both boom")
	check(not game.finished and game.phase == "both_out", "nobody wins when both boom")
	check(_kinds(game.events) == ["both_out"], "both_out emitted: %s" % str(_kinds(game.events)))
	var at := [game.pos[0], game.pos[1]]
	var fall := game.column_fall
	game.events.clear()
	var waited := 0.0
	var held := true
	while game.phase == "both_out" and waited < 3.0:
		game.step(1.0 / 60.0, _moves(Vector2.RIGHT, Vector2.RIGHT))
		waited += 1.0 / 60.0
		if game.phase == "both_out":
			check(game.events.is_empty(), "quiet while reviving")
			held = held and game.column_fall == fall
		else:
			break
	check(absf(waited - SkyGateGame.REVIVE_TIME) < 0.02, "revive after 1.0 s (%.3f)" % waited)
	check(held, "the column holds while they revive")
	var kinds := _kinds(game.events)
	check(kinds == ["revive", "gate"], "revive then the next gate: %s" % str(kinds))
	check(int(game.events[0].index) == 0, "revive names the gate")
	check(game.gate_index == 1, "continues from the next gate")
	check(game.pos[0].distance_to(at[0]) < 0.2 and game.pos[1].distance_to(at[1]) < 0.2, "revives where they were")
	check(game.revives == 1 and game.booms == [1, 1], "counted")


func _test_both_out_last_gate() -> void:
	var game := _game()
	for _i in range(3):
		var right := game.correct_choice()
		_play_gate(game, right, right)
		_until_next(game)
	check(game.gate_index == 3, "on the last gate")
	var wrong := _wrong(game)
	_play_gate(game, wrong, wrong)
	var events := _until_next(game)
	check(_kinds(events) == ["both_out", "revive", "round_clear"], "both out on the last gate → revive and round_clear: %s" % str(_kinds(events)))
	check(game.phase == "landing" and not game.finished, "both go down to the float")


func _test_round_flow() -> void:
	var game := _game()
	_clear_round(game)
	check(game.phase == "landing" and game.current_round == 1, "round 1 cleared")
	game.events.clear()
	game.step(5.0, _moves(Vector2.RIGHT, Vector2.RIGHT))
	check(game.phase == "landing" and game.events.is_empty(), "waits on the float until begin_round()")
	check(game.board_count() == 4 and game.column_round == 1, "the passed column stays until the next one is placed")
	game.place_for_next_round()
	check(game.column_round == 2 and game.column_quiz(0) == game.quizzes[4], "the next round's column is ready before its countdown")
	check(is_equal_approx(game.board_depth(0), SkyGateGame.FIRST_DEPTH) and game.gate_index == -1, "the new column starts at the top")
	check(game.begin_round(), "begin_round starts round 2")
	check(not game.begin_round(), "begin_round only once")
	var kinds := _kinds(game.events)
	check(kinds == ["round_start", "gate"], "round 2 starts: %s" % str(kinds))
	check(game.current_round == 2 and is_equal_approx(game.fall_speed, 10.0), "round 2 column rises 10 m/s")
	check(game.current_quiz() == game.quizzes[4], "round 2 starts with its first board")
	check(game.pos[0] == SkyGateGame.spawn_point(1) and game.pos[1] == SkyGateGame.spawn_point(2), "spawn again")
	var moved := false
	for _i in range(120):
		game.step(1.0 / 60.0, _moves())
		if absf(game.board_offset()) > 0.5:
			moved = true
	check(moved, "round 2 board moves sideways")
	game.events.clear()
	# ずれたボードでも、パネルの上なら正解できる
	var right := game.correct_choice()
	var event := _play_gate(game, right, right)
	check(event.get("results", []) == ["burst", "burst"], "moving board: both follow and burst")
	_until_next(game)
	_clear_round(game)
	game.begin_round()
	check(game.current_round == 3 and is_equal_approx(game.fall_speed, 13.0), "round 3 column rises 13 m/s")
	check(game.board_size() == Vector2(12.2, 8.6), "round 3 board is 12.2 x 8.6")
	check(game.play_rect().size.x < 12.2, "smaller play area")
	game.events.clear()
	right = game.correct_choice()
	event = _play_gate(game, right, right)
	check(event.get("results", []) == ["burst", "burst"], "small board: both burst")


func _test_overtime_and_speed() -> void:
	var game := _game()
	for number in range(1, SkyGateGame.ROUNDS + 1):
		check(game.current_round == number, "round %d" % number)
		_clear_round(game)
		if number < SkyGateGame.ROUNDS:
			check(game.phase == "landing", "round %d cleared" % number)
			game.begin_round()
	check(game.overtime and game.phase == "gate", "after round 5: overtime without landing")
	check(game.gate_index == 4 and game.board_count() == 8, "overtime: the column goes on below (%d boards)" % game.board_count())
	check(game.column_quiz(7) != null, "overtime boards have questions ahead")
	var speeds: Array[float] = []
	speeds.append(game.fall_speed)
	var right := game.correct_choice()
	var pass_event := _play_gate(game, right, right)
	var events := game.events.duplicate()
	speeds.append(game.fall_speed)
	right = game.correct_choice()
	_play_gate(game, right, right)
	speeds.append(game.fall_speed)
	check(speeds == [13.0, 15.5, 18.0], "overtime speeds 13 → 15.5 → 18: %s" % str(speeds))
	check(not pass_event.is_empty() and not _kinds(events).has("round_clear"), "no landing in overtime")
	# 18 m/秒のボード：2人とも正解。P2 は 1.0 秒まで別のパネル → P1 が早い
	right = game.correct_choice()
	var wrong := _wrong(game)
	var dt := 1.0 / 60.0
	var guard := 0
	while game.phase in ["gate", "impact"] and guard < 1000:
		guard += 1
		var m1 := _steer(game, 0, _panel_point(game, right))
		var m2 := _steer(game, 1, _panel_point(game, wrong if game.gate_clock() < 1.0 else right))
		game.step(dt, _moves(m1, m2))
	check(game.finished and game.decided_by == "speed" and game.winner == 1, "fastest board: the earlier one wins by speed")
	check(game.speed_times[0] < game.speed_times[1], "speed times recorded %s" % str(game.speed_times))
	var decided := {}
	for event: Dictionary in game.events:
		if str(event.kind) == "decided":
			decided = event
	check(str(decided.get("by", "")) == "speed" and int(decided.get("winner", 0)) == 1, "decided by speed")
	check(not _kinds(game.events).has("out"), "no out in a speed decision")


func _test_speed_tie() -> void:
	var game := _game()
	for number in range(1, SkyGateGame.ROUNDS + 1):
		_clear_round(game)
		if number < SkyGateGame.ROUNDS:
			game.begin_round()
	for _i in range(2):
		var right := game.correct_choice()
		_play_gate(game, right, right)
		_until_next(game)
	check(is_equal_approx(game.fall_speed, SkyGateGame.SPEED_WIN_SPEED), "on the fastest board")
	# 2人とも最初からずっと同じパネルの上（入った時刻が同じ）→ もう1枚
	var right := game.correct_choice()
	var center := SkyGateBoard.PANEL_CENTERS[right] * game.board_scale() + Vector2(game.board_offset(), 0.0)
	game.pos[0] = center + Vector2(-0.8, 0.0)
	game.pos[1] = center + Vector2(0.8, 0.0)
	var index := game.gate_index
	game.under = [-1, -1]
	game.under_tick = [0, 0]
	game.call("_track_under")
	var guard := 0
	var stayed := true
	while game.phase in ["gate", "impact"] and game.gate_index == index and guard < 2000:
		guard += 1
		# ボードは横へ動くので、パネルの上に居続けるようについていく
		var c := SkyGateBoard.PANEL_CENTERS[right] * game.board_scale() + Vector2(game.board_offset(), 0.0)
		game.step(1.0 / 60.0, _moves(_steer(game, 0, c + Vector2(-0.8, 0.0)), _steer(game, 1, c + Vector2(0.8, 0.0))))
		if game.phase == "gate" and game.gate_index == index and (game.under[0] != right or game.under[1] != right):
			stayed = false
	check(stayed, "both stayed on the right panel")
	check(not game.finished and game.phase == "gate", "same time: no winner, another board (%s %s)" % [game.phase, str(game.under_tick)])
	check(game.gate_index == index + 1 and is_equal_approx(game.fall_speed, SkyGateGame.SPEED_WIN_SPEED), "another fastest board")


## 同じ入力（1/30 秒ごとに変わる）なら、30 / 60 / 120fps で位置も出来事もまったく同じ。
func _test_frame_rate_scripted() -> void:
	var logs := []
	var finals := []
	for fps in [30, 60, 120]:
		var game := _game(11)
		var log: Array[String] = []
		var dt := 1.0 / float(fps)
		var frame := 0
		while not game.finished and frame < fps * 60:
			var t := float(frame) * dt
			var k := int(floor(t * 30.0 + 0.000001))
			# 1/30 秒ごとに決まる入力（時刻だけで決まる。状態を見ない）
			var m1 := Vector2(sin(float(k) * 0.07), cos(float(k) * 0.05)) * (0.6 + 0.4 * sin(float(k) * 0.011))
			var m2 := Vector2(cos(float(k) * 0.06 + 1.0), sin(float(k) * 0.045 + 2.0))
			game.step(dt, _moves(m1, m2))
			for event: Dictionary in game.events:
				log.append("%s|%s|%s|%s" % [event.kind, str(event.get("index", "")), str(event.get("results", "")), str(event.get("winner", ""))])
			game.events.clear()
			if game.phase == "landing":
				game.begin_round()
			frame += 1
		logs.append(log)
		finals.append([game.ticks, game.pos[0], game.pos[1], game.winner, game.gate_index, game.current_round])
	check(logs[0] == logs[1] and logs[1] == logs[2], "events identical at 30/60/120 fps")
	check(finals[0] == finals[1] and finals[1] == finals[2], "positions identical at 30/60/120 fps: %s" % str(finals))
	check((logs[0] as Array).size() > 3, "the scripted run had gates (%d events)" % (logs[0] as Array).size())


## 状態を見て動く（自動操縦）でも、30 / 60 / 120fps で判定は同じ。
func _test_frame_rate_autopilot() -> void:
	var results := []
	for fps in [30, 60, 120]:
		var game := _game(5)
		var dt := 1.0 / float(fps)
		var log: Array[String] = []
		var guard := 0
		while not game.finished and guard < fps * 200:
			guard += 1
			var right := game.correct_choice()
			# P1 はいつも正解へ。P2 は 3 枚目でまちがいへ
			var p2 := right if game.passes[1] < 2 else (right + 2) % 4
			var m1 := _steer(game, 0, _panel_point(game, right)) if game.phase == "gate" else Vector2.ZERO
			var m2 := _steer(game, 1, _panel_point(game, p2)) if game.phase == "gate" else Vector2.ZERO
			game.step(dt, _moves(m1, m2))
			for event: Dictionary in game.events:
				if str(event.kind) in ["gate_pass", "decided", "out"]:
					log.append("%s|%s|%s|%s" % [event.kind, str(event.get("index", "")), str(event.get("results", "")), str(event.get("winner", ""))])
			game.events.clear()
		results.append(log)
	check(results[0] == results[1] and results[1] == results[2], "autopilot judgments identical at 30/60/120 fps: %s" % str(results[0]))
	check(str(results[0][-1]).begins_with("decided") and str(results[0][-1]).ends_with("|1"), "P1 wins the autopilot run")


func _test_keys_ignored() -> void:
	var game := _game()
	var before := [game.pos[0], game.pos[1]]
	game.events.clear()
	game.step(1.0 / 60.0, {"answer": [2, 3], "answer_offset": [0.0, 0.0], "action": [0.0, 0.0]})
	check(game.events.is_empty() and game.pos[0] == before[0] and game.pos[1] == before[1], "answer keys and Space do nothing")


func _test_extra_questions() -> void:
	var game := _game(9, 2)
	var right := game.correct_choice()
	_play_gate(game, right, right)
	_until_next(game)
	right = game.correct_choice()
	_play_gate(game, right, right)
	_until_next(game)
	check(game.current_quiz() != null and game.current_quiz().q == "足し算", "extra question after the prepared ones run out")
	check(game.question_index == 2, "question index keeps counting")
	var record := game.record()
	check(str(record.game) == "sky_gate" and int(record.questions) == 3, "record")


## QuizGameState.set_sudden_death_move（GameWorld が毎フレーム呼ぶ口）がルールの "move" に届く。Space はルールを動かさない。
func _test_state_input() -> void:
	var state := QuizGameState.new()
	var game := _game()
	state.sudden_death_game = game
	state.game_state = Constants.STATE_SUDDEN_DEATH
	game.events.clear()
	var x0 := game.pos[0].x
	var y1 := game.pos[1].y
	for _i in range(30):
		state.set_sudden_death_move(1, Vector2(1.0, 0.0))
		state.set_sudden_death_move(2, Vector2(0.0, 3.0))
		state.submit_sudden_death_key(1, "buzz", -1, 0.0)
		state.call("_update_sudden_death", 1.0 / 60.0)
	check(game.pos[0].x > x0 + 1.0, "P1 moved right through the state (%.2f)" % (game.pos[0].x - x0))
	check(game.pos[1].y > y1 + 1.0, "P2 moved forward through the state")
	check(game.vel[1].length() <= SkyGateGame.MOVE_SPEED + 0.001, "move is limited to length 1")
	state.call("_update_sudden_death", 1.0 / 60.0)
	var vx := game.vel[0].x
	state.call("_update_sudden_death", 0.25)
	check(game.vel[0].x < vx * 0.2, "no move this frame = let go")
	state.sudden_death_presentation_lock = true
	state.set_sudden_death_move(1, Vector2(-1.0, 0.0))
	check(not (state.get("_sudden_death_input") as Dictionary).has("move"), "locked during the intro")
