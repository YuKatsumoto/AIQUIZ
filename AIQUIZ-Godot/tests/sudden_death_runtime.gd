extends Node

## 2Pサドンデス「早押し水没リフト」を実際の GameWorld（Forward+）で通しで動かす。
## 引き分けの決着演出 → 分岐（笛・カットイン・タワーが沈む・アイリス）→ 縦穴の降下（別スレッドの読み込み）
## → 着地と導入（リフトのタワーへ歩いて乗る・タワーがせり上がる・トンネルから鉄砲水・ルールカード）
## → 早押しの本戦 → 敗者のタワーが水に沈む → 昇降台で帰還 → 地表で勝者の演出 → 操作可能。暗転は使わない。
## 実キー入力（InputEventKey）で早押し（P1 Space、P2 右Ctrl）と回答（P1 A/W/S/D、P2 矢印）をし、要所の
## 画像と状態を保存する。水は GPU の流体シミュレーションを読み戻して確かめる。
## Godot --path . --script res://tests/sudden_death_runtime.gd は直接起動できないので
## Godot --path . --script res://tests/sudden_death_bootstrap.gd --fixed-fps 60 -- runtime case=correct
## case: correct | p2 | timeout | slow_load | load_fail | generate
## realtime: drive the director by the wall clock (default: frame time, deterministic captures).

const OUT_ROOT := "res://artifacts/sudden_death/runtime/"
const Phase := SuddenDeathState.Phase

## Per question, who buzzes and how: "p1" / "p2" (buzz and answer right), "p1x" / "p2x" (buzz and answer
## wrong), "p1late" / "p2late" (buzz, then no answer), "none" (nobody buzzes).
const PLANS := {
	"correct": ["p1", "p1"],
	"p2": ["p1x", "p2"],
	"timeout": ["none", "p1late", "p2"],
	"slow_load": ["p1", "p1"],
	"load_fail": [],
	"generate": ["p2", "p1x"],
}
const EXPECTED := {
	"correct": [1, "correct"], "p2": [2, "correct"], "timeout": [2, "correct"], "slow_load": [1, "correct"],
	"load_fail": [0, ""], "generate": [2, "wrong"],
}
## Margins (half steps) after each planned question.
const MARGINS := {
	"correct": [[4, 2], [4, 0]], "p2": [[2, 4], [0, 4]], "timeout": [[3, 3], [1, 3], [-1, 3]],
	"slow_load": [[4, 2], [4, 0]], "generate": [[2, 4], [0, 4]],
}
## generate: the online questions arrive this long after the deck starts down (the descent keeps going).
const GENERATE_DELAY := 11.0
## Answer keys by QuizGameState.SUDDEN_DEATH_KEY_* (left, up, down, right): P1, P2.
const ANSWER_KEYS := [[KEY_A, KEY_W, KEY_S, KEY_D], [KEY_LEFT, KEY_UP, KEY_DOWN, KEY_RIGHT]]
## The planned buzzer presses once this many characters are up (or the whole question).
const BUZZ_AFTER_CHARS := 7
## ...and answers this long after buzzing.
const ANSWER_AFTER := 0.6


## Online generation stand-in (docs 第4章): delivers ten short questions after GENERATE_DELAY.
class GeneratingProvider extends QuizProvider:
	var delay := GENERATE_DELAY
	var requests := 0
	var delivered_msec := 0

	func _load_bank() -> Dictionary:
		return {}

	func request_sudden_death_quizzes(count: int, _exclude: Array[String], on_progress: Callable,
			on_done: Callable) -> bool:
		requests += 1
		var tree := Engine.get_main_loop() as SceneTree
		tree.create_timer(delay * 0.5, true, false, true).timeout.connect(func() -> void:
			on_progress.call(count / 2, count))
		tree.create_timer(delay, true, false, true).timeout.connect(func() -> void:
			delivered_msec = Time.get_ticks_msec()
			var items: Array[QuizItem] = []
			for index in range(count):
				var item := QuizItem.create("生成問題 %d 日本で一番高い山は富士山ですが、二番目に高い山はどれ？" % index,
					PackedStringArray(["北岳", "奥穂高岳", "間ノ岳", "槍ヶ岳"]), 0, "", "GEMINI_STREAM")
				item.estimated_seconds = 3.0
				items.append(item)
			on_done.call(items))
		return true
## slow_load: the cistern reports ready this late (the shaft slows down and looks straight down).
const SLOW_LOAD_DELAY := 11.0

var scenario := "correct"
var fps := 60
var quality := "balanced"
var out := OUT_ROOT
var gs: QuizGameState
var world: Node
var helper: Node
var checks := 0
var failures: Array[String] = []
var log_rows: Array[Dictionary] = []
var events: Array[Dictionary] = []
var captured: Array[String] = []
var frame_times: Array[float] = []
var slow_frames: Array[Dictionary] = []
var _last_event := ""
## perf: no screenshots, so frame times are not inflated by PNG saves.
var _perf_only := false
var _held := {}
var _pending_captures: Array[String] = []
## tag -> frames left before the capture (the camera settles after a beat).
var _delayed_captures := {}
var _plan: Array = []
var _realtime := false
var director: SuddenDeathDirector
var _descent_shots := {}
## film: every FILM_EVERY-th frame from the branch to a few seconds into the descent, at half size,
## plus the camera and director state of every frame (film/log.json), to judge the continuity.
const FILM_FROM := 8.0
const FILM_EVERY := 3
var _film := false
var _capture_poses := {}
var _film_on := false
var _film_frame := 0
var _film_log: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("case="): scenario = arg.trim_prefix("case=")
		if arg.begins_with("fps="): fps = int(arg.trim_prefix("fps="))
		if arg.begins_with("quality="): quality = arg.trim_prefix("quality=")
		if arg == "perf": _perf_only = true
		if arg == "realtime": _realtime = true
		if arg == "film": _film = true
	_plan = PLANS.get(scenario, PLANS.correct)
	out = OUT_ROOT + scenario + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	GameManager.graphics_quality = quality
	get_tree().root.size = Vector2i(1280, 720)
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	gs.sudden_death_event.connect(_on_event)
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world.get_node("Player") as PlayerController).prepare_for_loading(gs)
	director = world.get("_sudden_death_director") as SuddenDeathDirector
	director.use_real_time = _realtime
	var generator: GeneratingProvider = null
	if scenario == "generate":
		generator = GeneratingProvider.new()
		get_tree().root.add_child(generator)
		gs.provider = generator
	if scenario == "slow_load":
		director.debug_load_delay = SLOW_LOAD_DELAY
	if scenario == "load_fail":
		director.debug_load_fail = true
	await frames(fps)
	world.call("_clear_preview_walls")
	gs.current_index = 10
	gs.current_wall_index = 10
	gs.load_current_quiz()
	check(gs.game_state == Constants.STATE_GOAL_RACE, "ten questions route to the goal")
	gs.world_scroll_z = gs.goal_z - 24.0
	gs.player_z = gs.goal_z - 10.0
	gs.player2_z = gs.goal_z - 10.0
	await frames(maxi(3, fps / 4))
	# The debug F9 path: cover, finish as a draw at the goal, reveal.
	world.call("_debug_force_draw_finish")
	check(await until(func() -> bool: return gs.result_presentation_active, 5.0), "forced draw starts the finale")
	check(gs.result_winner == 0 and gs.sudden_death_pending, "a draw prepares the sudden death")
	await until(func() -> bool: return gs.result_ceremony_elapsed >= 7.2, 12.0)
	capture("01_draw_verdict")
	var stage_env := world.get_node("StageEnvironment") as Node3D
	var camera := get_viewport().get_camera_3d()
	check(director.act_name() == "BRANCH", "the director takes the branch (%s)" % director.act_name())
	await until(func() -> bool: return gs.result_ceremony_elapsed >= 8.75, 4.0)
	capture("02_cut_in")
	check(bool(director.get_debug_snapshot().hud.get("cut_in", {}).get("visible", false)), "SUDDEN DEATH cut-in at 8.6 s")
	await until(func() -> bool: return gs.result_ceremony_elapsed >= 10.25, 4.0)
	capture("03_towers_sunk")
	var sunk: Dictionary = world.get("_result_ceremony_director").get_debug_snapshot().get("heights", {})
	check(float(sunk.get(1, 9.0)) < 0.3 and float(sunk.get(2, 9.0)) < 0.3, "both towers sank into the deck %s" % str(sunk))
	await until(func() -> bool: return gs.result_ceremony_elapsed >= 10.9, 4.0)
	capture("04_iris_open")
	check(await until(func() -> bool: return director.act_name() == "DESCENT", 4.0), "the deck starts down at 11.0 s")
	check(gs.game_state == Constants.STATE_RESULT_CEREMONY and not SceneTransition.is_transitioning(), "no screen cover on the way down")
	await until(func() -> bool: return director.descent().t >= 1.0, 4.0)
	capture("05_entry")
	if scenario == "generate":
		var entry_panel := world.get_node("GameplayHUD/PreloadPanel") as Control
		var entry_status := world.get_node("GameplayHUD/PreloadPanel/Status") as Label
		check(generator.requests == 1 and entry_panel.visible and entry_status.text.begins_with("AIクイズ生成中"),
			"generation starts with the descent and its panel shows on the way in (%s)" % entry_status.text)
	check(float(director.get_debug_snapshot().stage_drop) > 0.3, "the finale stage rides the deck down")
	if scenario == "load_fail":
		await _run_abort(stage_env, camera)
		return
	check(await until(func() -> bool: return gs.game_state == Constants.STATE_SUDDEN_DEATH, 6.0), "the runners take over on the deck")
	check(gs.sudden_death.phase == Phase.INTRO and gs.sudden_death_lift.x > 100.0, "riding the deck high above the cistern (lift %.1f)" % gs.sudden_death_lift.x)
	check(stage_env != null and not stage_env.visible, "surface hidden underground")
	check(camera != null and camera.environment != null, "shaft environment on the camera")
	await frames(maxi(2, fps / 4))
	capture("06_cruise_B")
	var landed := await _watch_descent()
	check(landed, "landed in the cistern")
	capture("09_landed")
	if scenario == "generate":
		check(generator.requests == 1 and gs.sudden_death_generation == "done" and gs.sudden_death_generated_count == 8,
			"the generated questions were used (%s, %d)" % [gs.sudden_death_generation, gs.sudden_death_generated_count])
		check(gs.sudden_death.quizzes[0].q.begins_with("生成問題"), "the first question is a generated one")
	check(absf(gs.sudden_death_lift.x - SuddenDeathLayout.PAD_TOP) < 0.05, "deck on the floor (lift %.2f)" % gs.sudden_death_lift.x)
	var loader: Dictionary = director.get_debug_snapshot().loader
	check(str(loader.get("stage", "")) == "ready", "cistern ready before the arrival %s" % str(loader.get("stage", "")))
	var cistern_snapshot: Dictionary = director.get_debug_snapshot().cistern
	check(int(cistern_snapshot.get("towers", {}).get("built", 0)) == 2 and bool(cistern_snapshot.get("flow", {}).get("built", false)),
		"both lift towers and the water are built")
	check(bool(cistern_snapshot.get("flow", {}).get("gpu", false)) and bool(cistern_snapshot.get("flow", {}).get("ready", false)),
		"the water runs on the GPU fluid simulation %s" % str(cistern_snapshot.get("flow", {})))
	await until(func() -> bool: return director.act_time() >= SuddenDeathDirector.INTRO_SHOUT + 0.3, 3.0)
	capture("10_shout")
	await until(func() -> bool: return director.act_time() >= SuddenDeathDirector.INTRO_GATE - 0.25, 4.0)
	capture("10b_walk")
	check(gs.is_sudden_death_runner_active(1) and gs.is_sudden_death_runner_active(2), "both walk to their towers")
	check(await until(func() -> bool: return director.shot_name() == "intro_tunnel", 4.0), "the intro cuts to the tunnel as the flood bursts out")
	await frames(maxi(1, int(fps * 0.6)))
	capture("11a_flood_tunnel")
	check(bool(director.get_debug_snapshot().cistern.flow.flooding), "the flood is out")
	await until(func() -> bool: return director.act_time() >= SuddenDeathDirector.INTRO_RISE + 0.7, 4.0)
	capture("10c_rise")
	var tower_p1 := SuddenDeathLayout.lift_position(1)
	check(absf(gs.player_x - tower_p1.x) < 0.01 and absf(gs.player_z - tower_p1.z) < 0.01 and absf(gs.player2_x + tower_p1.x) < 0.01,
		"each stands on their own tower (P1 at +X)")
	check(gs.sudden_death_lift.x > 1.0 and absf(gs.sudden_death_lift.x - gs.sudden_death_lift.y) < 0.01, "the towers lift them (%.2f m)" % gs.sudden_death_lift.x)
	await until(func() -> bool: return director.act_time() >= SuddenDeathDirector.INTRO_WALK.y + 0.6, 3.0)
	check(absf(gs.sudden_death_facing - PI) < 0.01, "both turned round toward the duel camera")
	var duel_eye := SuddenDeathDirector.duel_wide_shot().origin
	var player_node := world.get_node("Player") as PlayerController
	for player_index in [1, 2]:
		var parts: Dictionary = player_node.p1_parts if player_index == 1 else player_node.p2_parts
		var pelvis := parts.get("pelvis") as Node3D
		if pelvis != null:
			var front := pelvis.global_basis.z
			var to_camera := duel_eye - pelvis.global_position
			check(Vector2(front.x, front.z).dot(Vector2(to_camera.x, to_camera.z)) > 0.0, "P%d faces the duel camera (%s)" % [player_index, str(front)])
	await until(func() -> bool: return director.shot_name() == "intro_duel", 4.0)
	await frames(maxi(1, int(fps * 0.8)))
	capture("11b_flood_arrives")
	await until(func() -> bool: return director.act_time() >= SuddenDeathDirector.INTRO_RULES + 0.5, 4.0)
	capture("11c_rules")
	var start_height := gs.sudden_death.tuning.lift_height(gs.sudden_death.tuning.start_margin)
	check(absf(gs.sudden_death_lift.x - start_height) < 0.02, "the towers stand %.1f m over the floor (%.2f)" % [start_height, gs.sudden_death_lift.x])
	# The rule card waits for Enter: nothing starts on its own.
	await until(func() -> bool: return director.act_time() >= SuddenDeathDirector.INTRO_RULES + 2.0, 4.0)
	var held: Dictionary = director.get_debug_snapshot().hud.get("rule_card", {})
	check(bool(held.get("visible", false)) and bool(held.get("hold", false)), "the rule card is still up %.1f s in, waiting for Enter" % director.act_time())
	check(gs.sudden_death.phase == Phase.INTRO, "no countdown before Enter")
	check((held.get("lines", []) as Array).size() == 4, "four rules (buzz, keys, sink, lose)")
	_key(KEY_ENTER, true)
	await frames(2)
	_key(KEY_ENTER, false)
	check(not bool(director.get_debug_snapshot().hud.get("rule_card", {}).get("hold", true)), "Enter lets the held rule card go")
	check(await until(func() -> bool: return gs.sudden_death.phase == Phase.COUNTDOWN, 6.0), "countdown after the intro")
	var flood_time := float(director.get_debug_snapshot().cistern.flow.flood_time)
	check(flood_time >= SuddenDeathDirector.FLOOD_LEAD - 0.05, "the countdown waits for the flood to fill the view (%.2f s)" % flood_time)
	await frames(maxi(1, fps / 3))
	capture("12_countdown")
	var started := Time.get_ticks_usec()
	var guard := 0.0
	var last_usec := Time.get_ticks_usec()
	var last_compiles := _pipeline_compiles()
	var question_captures := {}
	while gs.game_state == Constants.STATE_SUDDEN_DEATH and guard < 120.0:
		var sd := gs.sudden_death
		if sd == null:
			break
		_drive(sd)
		var number := sd.question_index + 1
		if sd.phase == Phase.READING and sd.revealed_count() >= 4 and not question_captures.has("r%d" % number):
			question_captures["r%d" % number] = true
			capture("20_q%d_reading" % number)
			if number == 2:
				# The readback stalls the GPU for a frame: not counted as a game frame.
				await _check_water("question 2")
				last_usec = Time.get_ticks_usec()
			var quiz: Dictionary = director.get_debug_snapshot().hud.get("quiz", {})
			check(bool(quiz.get("visible", false)) and int(quiz.get("number", 0)) == number and str(quiz.get("phase", "")) == "reading"
				and int(quiz.get("revealed", 0)) >= 4 and int(quiz.get("revealed", 0)) < sd.question.q.length(),
				"Q%d: the question comes up character by character %s" % [number, str(quiz)])
		for tag in _pending_captures:
			capture(tag)
		_pending_captures.clear()
		for tag: String in _delayed_captures.keys():
			_delayed_captures[tag] = int(_delayed_captures[tag]) - 1
			if int(_delayed_captures[tag]) <= 0:
				_delayed_captures.erase(tag)
				capture(tag)
		if int(guard * fps) % maxi(1, fps / 4) == 0:
			_log(sd)
		if director.act_name() == "RETURN":
			var stage := director.return_stage()
			if not _descent_shots.has("ret_" + stage):
				_descent_shots["ret_" + stage] = true
				# The pickup reads best as the deck lands and the winner walks on.
				var delay := 1.9 if stage == "pickup" else 0.4
				_delayed_captures["3%d_return_%s" % [_descent_shots.size() % 10, stage]] = maxi(1, int(fps * delay))
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if sd.phase not in [Phase.INTRO, Phase.COUNTDOWN]:
			var frame_ms := float(now - last_usec) / 1000.0
			frame_times.append(frame_ms)
			if frame_ms > 40.0:
				slow_frames.append({"ms": snappedf(frame_ms, 0.1), "t": snappedf(sd.time, 0.01),
					"phase": Phase.keys()[sd.phase], "question": sd.question_index, "after": _last_event, "shot": director.shot_name(),
					"compiles": _pipeline_compiles() - last_compiles})
		last_usec = now
		last_compiles = _pipeline_compiles()
		guard += 1.0 / float(fps)
	_release_all()
	_check_margins()
	var expected: Array = EXPECTED.get(scenario, EXPECTED.correct)
	check(gs.sudden_death_winner == int(expected[0]) and gs.sudden_death_decided_by == str(expected[1]),
		"winner P%d by %s (got P%d by %s)" % [expected[0], expected[1], gs.sudden_death_winner, gs.sudden_death_decided_by])
	check(gs.sudden_death_question_count == (PLANS[scenario] as Array).size(), "decided on question %d (%d)" % [(PLANS[scenario] as Array).size(), gs.sudden_death_question_count])

	check(gs.result_presentation_active and gs.game_state == Constants.STATE_RESULT_CEREMONY and gs.result_return_hold, "back on the surface, holding at the verdict")
	check(_descent_shots.has("ret_slowmo") and _descent_shots.has("ret_pickup") and _descent_shots.has("ret_ascent"), "the return: plunge, pickup, ascent %s" % str(_descent_shots.keys()))
	check(stage_env.visible and not SceneTransition.is_transitioning(), "daylight without a screen cover")
	await until(func() -> bool: return director.return_stage() == "surface" and director.stage_time() >= 0.35, 3.0)
	capture("33_surface_rise")
	await until(func() -> bool: return director.stage_time() >= SuddenDeathDirector.SURFACE_DRAIN + 0.35, 4.0)
	capture("34_drain_eruption")
	await until(func() -> bool: return director.stage_time() >= SuddenDeathDirector.SURFACE_DRAIN + SuddenDeathDirector.DRAIN_FLIGHT + 0.2, 4.0)
	capture("35_loser_landed")
	var regrow: Dictionary = world.get("_result_ceremony_director").get_debug_snapshot().get("heights", {})
	check(float(regrow.get(3 - gs.result_winner, 9.0)) < 0.2 and float(regrow.get(gs.result_winner, 0.0)) > 0.4, "winner tower grows back, loser stays sunk %s" % str(regrow))
	check(await until(func() -> bool: return not gs.result_return_hold, 4.0), "the verdict resumes")
	await frames(2)
	check(camera.environment == null and director.act_name() == "DONE" and not camera_has_director_pose(), "surface restored")
	check(gs.result_winner == gs.sudden_death_winner, "the finale crowns the sudden death winner")
	await until(func() -> bool: return gs.result_ceremony_elapsed >= 8.2, 6.0)
	capture("30_winner_verdict")
	var stage_snapshot: Dictionary = world.get("_result_ceremony_director").get_debug_snapshot()
	var heights: Dictionary = stage_snapshot.get("heights", {})
	var loser := 3 - gs.result_winner
	await until(func() -> bool: return gs.result_ceremony_elapsed >= 10.4, 6.0)
	stage_snapshot = world.get("_result_ceremony_director").get_debug_snapshot()
	heights = stage_snapshot.get("heights", {})
	check(float(heights.get(loser, 9.0)) < 0.2 and float(heights.get(gs.result_winner, 0.0)) > 0.5, "loser tower sank, winner tower stands %s" % str(heights))
	capture("31_winner_final")
	check(await until(func() -> bool: return gs.game_state == Constants.STATE_CLEAR, 6.0), "controls after the celebration")
	check(gs.message_text.contains("サドンデスで P%d" % gs.sudden_death_winner), "result text")
	_write_report(float(Time.get_ticks_usec() - started) / 1000000.0)
	get_tree().quit(0 if failures.is_empty() else 1)


func camera_has_director_pose() -> bool:
	var rig := world.get_node("CameraController")
	return rig.has_director_pose()


## Shots and frame times on the way down; true once the deck has landed.
func _watch_descent() -> bool:
	var limit := int(40.0 * fps)
	var shots_seen := {}
	var last := Time.get_ticks_usec()
	for _frame in range(limit):
		var descent := director.descent()
		var shot := director.shot_name()
		if not shots_seen.has(shot):
			shots_seen[shot] = snappedf(descent.t, 0.01)
			if shot == "C_down":
				capture("07_down_C")
		if descent.stage == SuddenDeathDescent.Stage.CRUISE and descent.cruise_time >= 2.2 and not _descent_shots.has("cruise_late"):
			_descent_shots["cruise_late"] = true
			capture("06b_cruise_late")
		if scenario == "generate" and descent.stage == SuddenDeathDescent.Stage.CRUISE and descent.cruise_time >= 6.5 and not _descent_shots.has("generating"):
			_descent_shots["generating"] = true
			var panel := world.get_node("GameplayHUD/PreloadPanel") as Control
			var status := world.get_node("GameplayHUD/PreloadPanel/Status") as Label
			check(not descent.can_land() and panel.visible and status.text.begins_with("AIクイズ生成中") and not bool(director.get_debug_snapshot().hud.depth_meter.visible),
				"the match-start preparing panel shows the generation, no depth meter (%s)" % status.text)
			capture("07b_generating")
		if scenario == "slow_load" and descent.stage == SuddenDeathDescent.Stage.CRUISE and descent.cruise_time >= 5.0 and not _descent_shots.has("stage_panel"):
			_descent_shots["stage_panel"] = true
			var stage_status := world.get_node("GameplayHUD/PreloadPanel/Status") as Label
			check((world.get_node("GameplayHUD/PreloadPanel") as Control).visible and stage_status.text == "地下神殿を準備中...", "a slow cistern shows the preparing panel (%s)" % stage_status.text)
		if descent.stage == SuddenDeathDescent.Stage.DECEL and not _descent_shots.has("panel_gone"):
			_descent_shots["panel_gone"] = true
			check(not (world.get_node("GameplayHUD/PreloadPanel") as Control).visible, "the preparing panel goes once the deck slows to land")
		if descent.stage == SuddenDeathDescent.Stage.ARRIVAL and descent.stage_time >= 1.6 and not _descent_shots.has("arrival"):
			_descent_shots["arrival"] = true
			capture("08_arrival")
		if director.act_name() == "INTRO":
			var snapshot: Dictionary = director.get_debug_snapshot()
			_descent_shots = {"shots": shots_seen, "landed_at": descent.t, "loader": snapshot.loader,
				"cruise_frame_max_ms": snapshot.cruise_frame_max_ms, "cruise_frame_p95_ms": snapshot.cruise_frame_p95_ms,
				"cruise_ready_frames": snapshot.cruise_ready_frames, "cruise_ready_frame_max_ms": snapshot.cruise_ready_frame_max_ms}
			if _realtime and _perf_only:
				check(float(snapshot.cruise_ready_frame_max_ms) < 50.0, "no frame over 50 ms after the preparation (%.1f ms)" % float(snapshot.cruise_ready_frame_max_ms))
			shots_seen = director.shot_log().duplicate()
			_descent_shots["shots"] = shots_seen
			check(shots_seen.has("A_entry") and shots_seen.has("B_cruise") and shots_seen.has("D_arrival"), "descent shots A, B, D %s" % str(shots_seen))
			if scenario == "slow_load":
				check(shots_seen.has("C_down"), "long wait looks straight down")
				check(descent.t > SLOW_LOAD_DELAY, "lands after the slow load")
			elif scenario == "generate":
				check(shots_seen.has("C_down"), "waiting for the questions looks straight down")
				check(gs.is_sudden_death_question_ready() and descent.t > GENERATE_DELAY, "lands only after the questions arrived (t %.1f)" % descent.t)
			else:
				check(not shots_seen.has("C_down"), "no long-wait shot on a normal load")
			return true
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - last) / 1000.0)
		last = now
	return false


## load_fail: stop, go back up and end as the plain draw.
func _run_abort(stage_env: Node3D, camera: Camera3D) -> void:
	check(await until(func() -> bool: return director.descent().is_aborting(), 8.0), "the failed load turns the deck back")
	capture("06_abort_stop")
	check(await until(func() -> bool: return director.act_name() == "ABORT", 20.0), "back at the surface")
	check(gs.game_state == Constants.STATE_RESULT_CEREMONY and gs.result_winner == 0 and gs.sudden_death_aborted, "the draw resumes")
	check(stage_env.visible, "surface shown again")
	await until(func() -> bool: return director.stage_time() >= 1.0, 3.0)
	capture("07_abort_surface")
	check(await until(func() -> bool: return gs.game_state == Constants.STATE_CLEAR, 8.0), "controls after the aborted descent")
	check(gs.result_winner == 0 and not gs.message_text.contains("サドンデス"), "plain draw result")
	check(camera.environment == null and director.act_name() == "DONE", "surface environment restored")
	capture("08_abort_final")
	_write_report(0.0)
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ driving

## Pipeline compilations so far (mesh + surface + draw), to tell shader hitches from other work.
static func _pipeline_compiles() -> int:
	return (RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH)
		+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE)
		+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW))


## Plays the plan with real key presses: the planned buzzer buzzes once a few characters are up, then
## answers (right, wrong or not at all) a moment later. Keys go down for one frame and come back up.
func _drive(sd: SuddenDeathState) -> void:
	_release_all()
	var index := sd.question_index
	if index < 0 or index >= _plan.size():
		return
	var plan := str(_plan[index])
	if plan == "none":
		return
	var player := 1 if plan.begins_with("p1") else 2
	if sd.phase == Phase.READING and (sd.revealed_count() >= BUZZ_AFTER_CHARS or sd.is_fully_revealed()):
		if not _pressed_buzz.has(index):
			_pressed_buzz[index] = true
			if player == 1:
				_key(KEY_SPACE, true)
			else:
				_key(KEY_CTRL, true, KEY_LOCATION_RIGHT)
	elif sd.phase == Phase.ANSWERING and sd.buzzer == player and sd.phase_time >= ANSWER_AFTER and not plan.ends_with("late"):
		if not _pressed_answer.has(index):
			_pressed_answer[index] = true
			var count := sd.question.c.size()
			var choice := sd.question.a if not plan.ends_with("x") else (sd.question.a + 1) % count
			var key := QuizGameState.sudden_death_key_for_choice(choice, count)
			_key(ANSWER_KEYS[player - 1][key], true)


var _pressed_buzz := {}
var _pressed_answer := {}


## After each planned question the lifts stand where the plan puts them.
func _check_margins() -> void:
	var want: Array = MARGINS.get(scenario, [])
	var margins := [4, 4]
	var after: Array = []
	var current := -1
	for event: Dictionary in events:
		if str(event.kind) == "sink":
			margins[int(event.player) - 1] = int(event.to)
		if str(event.kind) == "question" and current >= 0:
			after.append(margins.duplicate())
		if str(event.kind) == "question":
			current = int(event.index)
	after.append(margins.duplicate())
	check(after.size() == want.size(), "%d questions played (%d)" % [want.size(), after.size()])
	for index in range(mini(after.size(), want.size())):
		check(after[index] == want[index], "after Q%d the lifts are at %s (%s)" % [index + 1, str(want[index]), str(after[index])])


## The simulated water at [param when]: it reaches the towers and stands at the level around them.
func _check_water(when: String) -> void:
	var cistern := director.get("_loader").cistern() as CisternStage if director.get("_loader") != null else null
	var flow := cistern.flow() if cistern != null else null
	if flow == null or not flow.debug_request_readback():
		check(false, "water readback at the %s" % when)
		return
	await frames(3)
	var level := gs.sudden_death.tuning.water_level
	var totals := flow.debug_totals()
	var gap := flow.debug_depth_at(Vector2(0.0, SuddenDeathLayout.LIFT_Z))
	var p1_tower := flow.debug_depth_at(Vector2(SuddenDeathLayout.LIFT_X, SuddenDeathLayout.LIFT_Z))
	var p1_side := flow.debug_depth_at(Vector2(SuddenDeathLayout.LIFT_X + 2.0, SuddenDeathLayout.LIFT_Z))
	var p2_side := flow.debug_depth_at(Vector2(-SuddenDeathLayout.LIFT_X - 2.0, SuddenDeathLayout.LIFT_Z))
	var wake := flow.debug_sample(Vector2(SuddenDeathLayout.LIFT_X, SuddenDeathLayout.LIFT_Z + 2.0))
	_water[when] = {"totals": totals, "gap": snappedf(gap, 0.001), "p1_tower": snappedf(p1_tower, 0.001),
		"p1_side": snappedf(p1_side, 0.001), "p2_side": snappedf(p2_side, 0.001),
		"wake": [snappedf(wake.x, 0.001), snappedf(wake.y, 0.01), snappedf(wake.z, 0.01), snappedf(wake.w, 0.01)]}
	check(absf(gap - level) < 0.5 and absf(p1_side - level) < 0.5 and absf(p2_side - level) < 0.5,
		"%s: the water stands about %.1f m deep round the towers %s" % [when, level, str(_water[when])])
	check(p1_tower < 0.01, "%s: no water on a standing tower's platform (%.3f)" % [when, p1_tower])
	check(float(totals.get("fastest", 0.0)) > 1.0, "%s: the water flows (fastest %.2f m/s)" % [when, float(totals.get("fastest", 0.0))])


var _water := {}


func _key(code: Key, pressed: bool, location := KEY_LOCATION_UNSPECIFIED) -> void:
	if bool(_held.get(code, false)) == pressed:
		return
	_held[code] = pressed
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.location = location
	event.pressed = pressed
	Input.parse_input_event(event)


func _release_all() -> void:
	for code: Variant in _held.keys():
		_key(code, false, KEY_LOCATION_RIGHT if code == KEY_CTRL else KEY_LOCATION_UNSPECIFIED)


func _on_event(event: Dictionary) -> void:
	events.append(event.duplicate())
	var kind := str(event.kind)
	_last_event = kind
	var number := int(event.get("index", gs.sudden_death.question_index if gs.sudden_death != null else 0)) + 1
	match kind:
		"buzz":
			_delayed_captures["21_q%d_buzz_p%d" % [number, int(event.player)]] = maxi(1, int(fps * 0.35))
		"answer", "timeout":
			_delayed_captures["22_q%d_%s" % [number, "timeout" if kind == "timeout" else ("right" if bool(event.correct) else "wrong")]] = maxi(1, int(fps * 0.5))
			_delayed_captures["23_q%d_sink" % number] = maxi(1, int(fps * 1.2))
		"decided":
			_pending_captures.append("24_decided_p%d" % int(event.get("winner", 0)))
		"caught":
			_pending_captures.append("25_caught_p%d" % int(event.get("player", 0)))
			_delayed_captures["26_caught_later"] = maxi(1, int(fps * 0.7))


# ------------------------------------------------------------------ output

func _log(sd: SuddenDeathState) -> void:
	log_rows.append({
		"t": snappedf(sd.time, 0.01), "phase": Phase.keys()[sd.phase], "question": sd.question_index,
		"margin": sd.margin.duplicate(), "buzzer": sd.buzzer, "revealed": sd.revealed_count(), "result": sd.result,
		"lift": [snappedf(gs.sudden_death_lift.x, 0.01), snappedf(gs.sudden_death_lift.y, 0.01)],
		"caught": sd.caught.duplicate(), "shot": director.shot_name(),
	})


func _process(_delta: float) -> void:
	if not _film or gs == null or director == null:
		return
	if not _film_on:
		_film_on = gs.result_presentation_active and gs.result_ceremony_elapsed >= FILM_FROM
		if _film_on:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + "film/"))
		return
	var act := director.act_name()
	if act not in ["BRANCH", "DESCENT", "IDLE"] or (act == "DESCENT" and director.descent().t > 6.0):
		_film = false
		var file := FileAccess.open(out + "film/log.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(_film_log, "	"))
		file.close()
		return
	var camera := get_viewport().get_camera_3d()
	var row := {"frame": _film_frame, "act": act, "shot": director.shot_name(),
		"elapsed": snappedf(gs.result_ceremony_elapsed, 0.001),
		"descent_t": snappedf(director.descent().t, 0.001) if act == "DESCENT" else -1.0}
	if camera != null:
		var forward := -camera.global_transform.basis.z
		row["cam"] = [snappedf(camera.global_position.x, 0.01), snappedf(camera.global_position.y, 0.01), snappedf(camera.global_position.z, 0.01)]
		row["fwd"] = [snappedf(forward.x, 0.001), snappedf(forward.y, 0.001), snappedf(forward.z, 0.001)]
		row["fov"] = snappedf(camera.fov, 0.01)
		var environment := camera.environment if camera.environment != null else (camera.get_world_3d().environment if camera.get_world_3d() != null else null)
		row["exposure"] = snappedf(environment.tonemap_exposure, 0.001) if environment != null else -1.0
	if _film_frame % FILM_EVERY == 0:
		var image := get_viewport().get_texture().get_image()
		image.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		image.save_jpg(out + "film/f_%04d.jpg" % _film_frame, 0.85)
		row["saved"] = true
	_film_log.append(row)
	_film_frame += 1


func capture(tag: String) -> void:
	if _perf_only:
		return
	captured.append(tag)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var forward := -camera.global_transform.basis.z
		_capture_poses[tag] = {"eye": [snappedf(camera.global_position.x, 0.01), snappedf(camera.global_position.y, 0.01), snappedf(camera.global_position.z, 0.01)],
			"forward": [snappedf(forward.x, 0.01), snappedf(forward.y, 0.01), snappedf(forward.z, 0.01)],
			"shot": director.shot_name() if director != null else "", "act": director.act_name() if director != null else ""}
	get_viewport().get_texture().get_image().save_png(out + tag + ".png")


func _write_report(seconds: float) -> void:
	var sorted := frame_times.duplicate()
	sorted.sort()
	var perf := {}
	if not sorted.is_empty():
		perf = {"frames": sorted.size(), "p50_ms": sorted[sorted.size() / 2], "p95_ms": sorted[int(sorted.size() * 0.95)],
			"max_ms": sorted[sorted.size() - 1]}
	var report := {"case": scenario, "passed": failures.is_empty(), "checks": checks, "failures": failures,
		"winner": gs.sudden_death_winner, "decided_by": gs.sudden_death_decided_by, "events": events,
		"captures": captured, "frame_ms": perf, "slow_frames": slow_frames, "wall_seconds": seconds, "quality": quality, "log": log_rows,
		"descent": _descent_shots, "director": director.get_debug_snapshot() if director != null else {},
		"capture_poses": _capture_poses, "water": _water, "plan": _plan}
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SUDDEN_DEATH_RUNTIME " + JSON.stringify({"case": scenario, "passed": report.passed, "checks": checks,
		"failures": failures, "winner": report.winner, "by": report.decided_by, "frame_ms": perf, "slow": slow_frames}))


func frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func until(predicate: Callable, seconds: float) -> bool:
	var limit := int(seconds * fps)
	for _frame in range(limit):
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()
