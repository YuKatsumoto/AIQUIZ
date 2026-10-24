extends Node

## 自動モードの壁速度（WallSpeedPlanner と QuizGameState への組み込み）を確かめる。
## godot --headless --path . --script res://tests/wall_speed_bootstrap.gd

class TestProvider extends QuizProvider:
	func _load_bank() -> Dictionary:
		return {}
	func submit_result(_quiz: QuizItem, _correct: bool) -> void:
		pass

const OUT := "res://artifacts/wall_speed/"
## 旧ロジック（AI の t をそのまま使い、回の後半で一律 15% 速くする）。比較用。
const OLD_MOVE_BUFFER := 28.0 / GameTuning.WALL_SPEED_AUTO_DEFAULT - 4.0

var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var providers: Array[QuizProvider] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func quiz(q: String, choices: Array, ai_seconds := 4.0) -> QuizItem:
	return QuizItem.create(q, PackedStringArray(choices), 0, "", "GEMINI_POOL", "", PackedStringArray(), ai_seconds)


func old_speed(ai_seconds: float, progress: float) -> float:
	return 28.0 / (ai_seconds + OLD_MOVE_BUFFER) * (1.0 + 0.15 * progress)


func run() -> void:
	var analytics = QuizManager.player_analytics
	QuizManager.player_analytics = null
	_estimates()
	_ai_hint_only_slows()
	_round_progress_keeps_thinking_time()
	_distance_and_clamp()
	_pace()
	_game_state()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "rows": rows}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT + "unit.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WALL_SPEED_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	QuizManager.player_analytics = analytics
	for provider in providers:
		provider.free()
	get_tree().quit(0 if failures.is_empty() else 1)


func _estimates() -> void:
	# 実際に出た問題。AI の t はどれも 4.0 で、旧ロジックでは同じ速さだった。
	var easy := quiz("ドングリが実るのは、どの季節？", ["秋", "冬"])
	var recall := quiz("月にある、丸い穴のような地形を何という？", ["クレーター", "砂丘"])
	var volume := quiz("たて10cm横5cm高さ4cmの箱と、1辺6cmの立方体の体積の差は何cm³？", ["16cm³", "26cm³"])
	var borrow := quiz("「82－37」のひき算で、一の位「2－7」ができないとき、どうすればよい？", ["十の位から1繰り下げる", "7から2をひく"])
	var clock := quiz("Aさんは2じ10ふんから40ふんかん、Bさんは3じ40ふんから4じ30ふんべんきょうしました。正しいものは？",
		["Aさんのほうが10ふんながい", "ふたりとも 同じ ながさ", "Aさんのほうが20ふんながい", "Bさんのほうが10ふんながい"])
	var cases := [
		["easy", easy, "理科", 2, "普通", 2],
		["recall", recall, "理科", 6, "普通", 2],
		["volume", volume, "算数", 5, "普通", 2],
		["borrow", borrow, "算数", 3, "普通", 2],
		["clock_hard", clock, "算数", 2, "難しい", 4],
	]
	var speeds := {}
	for c: Array in cases:
		var planner := WallSpeedPlanner.new()
		var speed := planner.plan(c[1], c[2], c[3], c[4], c[5], 29.6, 1.0)
		speeds[c[0]] = speed
		rows.append({
			"case": c[0], "answer_seconds": snappedf(planner.last_answer_seconds, 0.01),
			"budget_seconds": snappedf(planner.last_budget_seconds, 0.01), "speed": snappedf(speed, 0.001),
			"old_speed_last_question": snappedf(old_speed(4.0, 1.0), 0.001),
		})
		check(planner.last_budget_seconds >= WallSpeedPlanner.FASTEST_SECONDS
			and planner.last_budget_seconds <= WallSpeedPlanner.SLOWEST_SECONDS, "time to the wall in auto range: " + c[0])
	check(speeds.volume < speeds.easy * 0.8, "multi-step volume problem is clearly slower than a one-word recall")
	check(speeds.borrow < speeds.recall * 0.8, "borrowing subtraction is clearly slower than a short recall")
	check(speeds.clock_hard < speeds.volume, "long four-choice clock problem is the slowest")
	# 終盤の難問は旧ロジック（t=4.0 → 2.9 × 1.15）より確実に遅い。
	for key: String in ["volume", "borrow", "clock_hard"]:
		check(speeds[key] < old_speed(4.0, 1.0) * 0.8, "late hard question slower than the old formula: " + key)
	check(speeds.easy > speeds.volume, "short recall question keeps a brisk wall")
	var carry := WallSpeedPlanner.estimate_answer_seconds(quiz("9 + 5 は いくつですか。", ["14", "13"], 0.0), "算数", 1, "普通", 2)
	var no_carry := WallSpeedPlanner.estimate_answer_seconds(quiz("4 + 5 は いくつですか。", ["9", "8"], 0.0), "算数", 1, "普通", 2)
	check(carry > no_carry + 0.4, "carrying addition takes longer")
	var with_borrow := WallSpeedPlanner.estimate_answer_seconds(quiz("52 - 27 はいくつ？", ["25", "35"], 0.0), "算数", 2, "普通", 2)
	var without_borrow := WallSpeedPlanner.estimate_answer_seconds(quiz("58 - 27 はいくつ？", ["31", "41"], 0.0), "算数", 2, "普通", 2)
	check(with_borrow > without_borrow + 0.4, "borrowing subtraction takes longer")
	var unknown := WallSpeedPlanner._arithmetic_seconds(WallSpeedPlanner._operations("23 × □ ＝ 69"), "23 × □ ＝ 69", 4)
	var known := WallSpeedPlanner._arithmetic_seconds(WallSpeedPlanner._operations("23 × 3 ＝ 69"), "23 × 3 ＝ 69", 4)
	check(unknown > known + 0.4, "solving for the box takes longer")
	check(WallSpeedPlanner._operations("12 + 3 - 4 × 2").size() == 3, "chained operations are all counted")


func _ai_hint_only_slows() -> void:
	var q := "水を熱し続けると、出てくるあわの正体は？"
	var c := ["水蒸気", "湯気"]
	var local := WallSpeedPlanner.estimate_answer_seconds(quiz(q, c, 0.0), "理科", 4, "普通", 2)
	var low := WallSpeedPlanner.estimate_answer_seconds(quiz(q, c, 2.0), "理科", 4, "普通", 2)
	var typical := WallSpeedPlanner.estimate_answer_seconds(quiz(q, c, 4.0), "理科", 4, "普通", 2)
	var high := WallSpeedPlanner.estimate_answer_seconds(quiz(q, c, 9.0), "理科", 4, "普通", 2)
	check(is_equal_approx(low, local) and is_equal_approx(typical, local), "a low AI estimate never speeds up the wall")
	check(high > local + 2.0, "a high AI estimate slows the wall")
	var short := quiz("「山」の読みは？", ["やま", "かわ"], 2.0)
	check(WallSpeedPlanner.estimate_answer_seconds(short, "国語", 4, "普通", 2) >= WallSpeedPlanner.ANSWER_MIN, "answer floor")


func _round_progress_keeps_thinking_time() -> void:
	var q := quiz("1Lのジュースを4人で等分しました。1人分は何Lですか？", ["1/4L", "4/1L"])
	var planner := WallSpeedPlanner.new()
	planner.plan(q, "算数", 3, "普通", 2, 29.6, 0.0)
	var start_answer := planner.last_answer_seconds
	var start_budget := planner.last_budget_seconds
	planner.plan(q, "算数", 3, "普通", 2, 29.6, 1.0)
	check(is_equal_approx(planner.last_answer_seconds, start_answer), "round progress does not cut thinking time")
	check(is_equal_approx(start_budget - planner.last_budget_seconds,
		WallSpeedPlanner.MARGIN_START - WallSpeedPlanner.MARGIN_END), "round progress only trims the margin")


func _distance_and_clamp() -> void:
	var q := quiz("1Lのジュースを4人で等分しました。1人分は何Lですか？", ["1/4L", "4/1L"])
	var planner := WallSpeedPlanner.new()
	var solo := planner.plan(q, "算数", 3, "普通", 2, 29.6, 0.0)
	var solo_budget := planner.last_budget_seconds
	var duo := planner.plan(q, "算数", 3, "普通", 2, 21.6, 0.0)
	check(solo_budget > WallSpeedPlanner.FASTEST_SECONDS and solo_budget < WallSpeedPlanner.SLOWEST_SECONDS, "distance case is not clamped")
	check(is_equal_approx(planner.last_budget_seconds, solo_budget), "same time to the wall from a shorter start")
	check(is_equal_approx(duo / solo, 21.6 / 29.6), "speed follows the real distance")
	check(is_equal_approx(planner.plan(q, "算数", 3, "普通", 2, 0.0, 0.0), solo * 30.0 / 29.6), "bad distance uses the wall spacing")
	var huge := quiz("ゆうとさんは「ふとい」と「ほそい」を仲間の言葉だと考えました。まちがいの理由は？いくつかの文を読んで、正しいものをすべて選んだときの組み合わせを考えましょう。",
		["ふとい・ほそいは太さの正反対だから", "どちらも「〜い」で終わるから", "どちらもものの長さをあらわすから", "どちらも色の仲間の言葉だから"])
	planner.plan(huge, "国語", 1, "難しい", 4, 29.6, 0.0)
	check(is_equal_approx(planner.last_budget_seconds, WallSpeedPlanner.SLOWEST_SECONDS), "very long question stops at the slow limit")
	var tiny := quiz("1+1は？", ["2", "3"], 0.0)
	var tiny_speed := planner.plan(tiny, "算数", 6, "簡単", 2, 29.6, 1.0)
	check(is_equal_approx(planner.last_budget_seconds, WallSpeedPlanner.FASTEST_SECONDS), "tiny question stops at the fast limit")
	check(is_equal_approx(tiny_speed, 29.6 / WallSpeedPlanner.FASTEST_SECONDS), "fast limit is a time, not a speed")


func _pace() -> void:
	var q := quiz("1Lのジュースを4人で等分しました。1人分は何Lですか？", ["1/4L", "4/1L"])
	var planner := WallSpeedPlanner.new()
	var base_speed := planner.plan(q, "算数", 3, "普通", 2, 29.6, 0.0)
	planner.track(planner.last_budget_seconds * 0.95, false)
	planner.record_result(false)
	check(is_equal_approx(planner.pace, 1.0 + WallSpeedPlanner.PACE_WRONG), "a late wrong answer gives more time")
	var slower := planner.plan(q, "算数", 3, "普通", 2, 29.6, 0.0)
	check(slower < base_speed, "more time means a slower wall")
	planner.track(planner.last_budget_seconds * 0.3, false)
	planner.record_result(false)
	check(is_equal_approx(planner.pace, 1.0 + WallSpeedPlanner.PACE_WRONG), "a rushed wrong answer is not a time problem")
	planner.plan(q, "算数", 3, "普通", 2, 29.6, 0.0)
	planner.track(1.0, true)
	planner.record_result(true)
	check(is_equal_approx(planner.pace, 1.0 + WallSpeedPlanner.PACE_WRONG + WallSpeedPlanner.PACE_RETREAT), "backing off to read gives more time")
	planner.reset()
	for i in range(20):
		planner.plan(q, "算数", 3, "普通", 2, 29.6, 0.0)
		planner.track(planner.last_budget_seconds * 0.3, false)
		planner.record_result(true)
	check(is_equal_approx(planner.pace, WallSpeedPlanner.PACE_MIN), "quick correct answers speed up only to the limit")
	for i in range(20):
		planner.plan(q, "算数", 3, "普通", 2, 29.6, 0.0)
		planner.track(planner.last_budget_seconds, true)
		planner.record_result(false)
	check(is_equal_approx(planner.pace, WallSpeedPlanner.PACE_MAX), "struggling slows down only to the limit")
	planner.begin_round()
	check(is_equal_approx(planner.pace, lerpf(WallSpeedPlanner.PACE_MAX, 1.0, WallSpeedPlanner.PACE_CARRY_OVER)), "next round keeps half of the pace")


func _fixture(players: int, mode: String) -> QuizGameState:
	var provider := TestProvider.new()
	providers.append(provider)
	var gs := QuizGameState.new(provider)
	gs.num_players = players
	gs.mode = mode
	gs.llm_mode = "OFFLINE"
	gs.subject = "算数"
	gs.grade = 5
	gs.difficulty = "普通"
	gs.target_count = 10
	gs.tuning.wall_speed_override = 0.0
	gs.game_state = Constants.STATE_PLAYING
	gs.player_z = -8.0 if players == 1 else 0.0
	gs.player2_z = 0.0
	gs.p2_alive = players == 2
	return gs


func _game_state() -> void:
	var hard := quiz("たて10cm横5cm高さ4cmの箱と、1辺6cmの立方体の体積の差は何cm³？", ["16cm³", "26cm³"])
	var easy := quiz("正五角形の辺の数は？", ["5", "6"])
	for players in [1, 2]:
		var gs := _fixture(players, Constants.MODE_TEN)
		for i in range(10):
			if gs.num_choices_for_index(i) == 4:
				gs.quiz_list.append(quiz("ボス %d: 12×3+8 はいくつ？" % i, ["44", "42", "46", "40"]))
			else:
				gs.quiz_list.append(hard if i % 2 == 0 else easy)
		gs.load_current_quiz()
		var first_hard := gs._active_wall_speed
		var expected_distance := gs.wall_z - 0.4 - gs.player_z
		check(is_equal_approx(gs._distance_to_current_wall(), expected_distance), "distance from the front player %dP" % players)
		gs.player_z = gs.wall_z - 0.4
		gs.player2_z = gs.wall_z - 0.4
		gs.advance_after_correct()
		var then_easy := gs._active_wall_speed
		check(first_hard < then_easy * 0.8, "hard question slower than the next easy one %dP" % players)
		check(first_hard < old_speed(4.0, 0.0) * 0.85, "first hard question slower than before %dP" % players)
		rows.append({"case": "game_%dp" % players, "hard": snappedf(first_hard, 0.001), "easy": snappedf(then_easy, 0.001)})
		# 最後の問題まで進めても、難問の速さは「余裕を縮めた分」しか上がらない。
		for i in range(7):
			gs.player_z = gs.wall_z - 0.4
			gs.player2_z = gs.wall_z - 0.4
			gs.advance_after_correct()
		check(gs.current_index == 8 and gs.current_quiz == hard, "reached the late hard question")
		var late_hard := gs._active_wall_speed
		var late_budget := gs.wall_speed_planner.last_budget_seconds
		check(late_budget >= gs.wall_speed_planner.last_answer_seconds + WallSpeedPlanner.MOVE_TWO_CHOICES, "late hard question keeps full thinking time")
		check(late_hard < old_speed(4.0, 8.0 / 9.0) * 0.8, "late hard question much slower than the old formula %dP" % players)
		rows.append({"case": "game_late_%dp" % players, "hard": snappedf(late_hard, 0.001)})
	# 手動の速さはそのまま使う。
	var manual := _fixture(1, Constants.MODE_TEN)
	manual.tuning.wall_speed_override = 5.0
	manual.quiz_list.append(hard)
	manual.load_current_quiz()
	check(is_equal_approx(manual._active_wall_speed, 5.0), "manual speed overrides the planner")
	# 答えの結果が次の問題の速さに効く。
	var adapt := _fixture(1, Constants.MODE_ENDLESS)
	for i in range(6):
		adapt.quiz_list.append(hard.duplicate(true))
	adapt.load_current_quiz()
	var before := adapt._active_wall_speed
	var before_budget := adapt.wall_speed_planner.last_budget_seconds
	for i in range(3):
		adapt.update(0.1)
	check(is_equal_approx(adapt.wall_speed_planner._elapsed, 0.3), "playing frames are timed for the planner")
	adapt.wall_speed_planner.track(before_budget * 0.9, false)
	adapt._record_answer_timing(false)
	adapt.player_z = adapt.wall_z - 0.4
	adapt.advance_after_correct()
	check(adapt.wall_speed_planner.pace > 1.0, "late wrong answer in play raises the pace")
	check(adapt.wall_speed_planner.last_budget_seconds > before_budget, "the next wall gives more time after a struggle")
	check(adapt._active_wall_speed < before, "the next wall comes slower after a struggle")
