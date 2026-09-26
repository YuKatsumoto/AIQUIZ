extends Node

var OUT := "res://artifacts/result_ceremony/"
var helper: Node
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func fixture(first := 1) -> QuizGameState:
	var gs: QuizGameState = helper.fixture()
	gs.result_ceremony_enabled = true
	gs.score = 9
	gs.player2_score = 7
	gs._set_player_hp(1, 1)
	gs._set_player_hp(2, 3)
	gs._start_goal_race()
	gs.player_x = 2.2
	gs.player2_x = -2.2
	gs.player_z = gs.goal_z - (0.01 if first == 1 else 3.0)
	gs.player2_z = gs.goal_z - (0.01 if first == 2 else 3.0)
	return gs

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	helper = load("res://tests/hp_unit.gd").new()
	QuizManager.player_analytics = null
	# Load the actual visual scripts with autoloads available, too.
	for path in ["res://scripts/ui/result_finale_hud.gd", "res://scripts/world/result_ceremony_director.gd",
			"res://scripts/world/result_finale/result_finale_stage.gd", "res://scripts/world/result_finale/result_finale_motion.gd",
			"res://scripts/world/result_finale/result_finale_effects.gd", "res://scripts/world/result_finale/result_finale_referee.gd",
			"res://scripts/world/camera_controller.gd", "res://scripts/world/game_world.gd", "res://tests/result_ceremony_runtime.gd"]:
		var script := load(path) as Script
		check(script != null and script.can_instantiate(), "compiles " + path)
	check_score_tower()
	for fps in [30, 60, 120]:
		var dt := 1.0 / float(fps)
		for first in [1, 2]:
			var gs := fixture(first)
			gs.update(dt)
			check(gs.has_player_reached_goal(first), "first arrival recorded %d/%d" % [first, fps])
			check(not gs.result_presentation_active and gs.game_state == Constants.STATE_GOAL_RACE, "first waits")
			var first_hp := gs.get_player_hp(first)
			for frame in range(fps):
				gs.update(dt, Vector2(1, -1), Vector2(-1, -1), true, true)
			check(gs.get_player_hp(first) == first_hp and gs.p1_alive and gs.p2_alive, "safe wait under held inputs")
			gs.player_z = gs.goal_z + 0.05
			gs.player2_z = gs.goal_z + 0.05
			gs.player_y = 0
			gs.player2_y = 0
			gs.update(dt)
			check(gs.result_presentation_active and gs.result_winner == 2, "HP reverses correct count winner")
			check(gs.result_p1_score == 9 and gs.result_p2_score == 21, "frozen totals")
			var phases: Array[int] = []
			gs.result_ceremony_phase_changed.connect(func(phase: int): phases.append(phase))
			var presentation_frames := roundi(fps * QuizGameState.RESULT_TOTAL_DURATION)
			for frame in range(presentation_frames):
				gs.update(dt, Vector2.ONE, -Vector2.ONE, true, true, 1, 2)
				if frame < presentation_frames - 1:
					check(gs.game_state != Constants.STATE_CLEAR, "no early controls at %d/%d" % [frame, fps])
			check(gs.game_state == Constants.STATE_CLEAR and is_equal_approx(gs.result_ceremony_elapsed, QuizGameState.RESULT_TOTAL_DURATION), "slower presentation finish")
			check(phases.size() == 6 and phases.count(QuizGameState.ResultCeremonyPhase.EFFECT) == 1, "each phase exactly once")
			check(gs.p1_hp == 1 and gs.p2_hp == 3 and gs.p1_alive and gs.p2_alive, "presentation preserves health and life")
			check(gs.message_text.contains("21") and gs.message_text.contains("9"), "final text uses product")
			gs._reset_result_ceremony_state()
			check(not gs.result_presentation_active and gs.goal_reached_mask == 0 and gs.result_p1_hp == 0, "reset snapshots and latch")
	for example in [[8, 3, 9, 1, 1], [6, 2, 4, 3, 0], [0, 3, 0, 1, 0]]:
		var gs := fixture()
		gs.score = example[0]
		gs.p1_hp = example[1]
		gs.player2_score = example[2]
		gs.p2_hp = example[3]
		gs.player_z = gs.goal_z + 0.01
		gs.player2_z = gs.goal_z + 0.01
		gs.update(1.0 / 60.0)
		check(gs.result_winner == example[4], "simultaneous finish " + str(example))
		gs.score = 99
		gs.p1_hp = 0
		gs.update(20.0)
		check(gs.result_p1_score == example[0] * example[1] and gs.result_winner == example[4], "snapshot immutable; long frame")
		check(is_equal_approx(gs.result_ceremony_elapsed, gs.get_result_ceremony_total_duration()), "long frame clamps at result")
	var airborne := fixture()
	airborne.player_y = 1.2
	airborne.player_vel_y = 2.0
	airborne.player2_z = airborne.goal_z + 0.01
	airborne.update(1.0 / 60.0)
	check(airborne.goal_reached_mask == 3 and airborne.player_y > 1.0 and not airborne.result_presentation_active, "airborne crossing is not snapped to ground")
	for frame in range(90):
		if airborne.result_presentation_active:
			break
		airborne.update(1.0 / 60.0)
	check(airborne.result_presentation_active and airborne.player_y == 0.0 and airborne.result_ceremony_elapsed == 0.0, "timer begins only after landing")
	for first in [1, 2]:
		var gs := fixture(first)
		gs.update(1.0 / 60.0)
		if first == 1:
			gs.p2_alive = false
		else:
			gs.p1_alive = false
		gs.update(1.0 / 60.0)
		check(gs.game_state == Constants.STATE_CLEAR and gs.goal_winner == first and not gs.result_presentation_active, "waiting opponent eliminated; legacy result")
	var legacy := fixture()
	var fallen := fixture()
	fallen.player_x = 100.0
	fallen.update(1.0 / 60.0)
	check(fallen.p1_fall_committed and not fallen.has_player_reached_goal(1), "out-of-bounds crossing cannot revive a falling player")
	legacy.result_ceremony_enabled = false
	legacy.update(1.0 / 60.0)
	check(legacy.game_state == Constants.STATE_CLEAR and legacy.goal_winner == 1, "transport excluded keeps first-goal contract")
	for mode in [Constants.MODE_ENDLESS, Constants.MODE_TUTORIAL, Constants.MODE_COOP]:
		var gs := fixture()
		gs.mode = mode
		check(not gs.uses_local_result_ceremony(), "mode excluded " + mode)
	var replay := fixture()
	replay.is_replay = true
	check(not replay.uses_local_result_ceremony(), "replay excluded")
	replay.is_replay = false
	replay.num_players = 1
	check(not replay.uses_local_result_ceremony(), "solo excluded")
	var floor_test := fixture()
	for state in [Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE, Constants.STATE_CLEAR]:
		floor_test.game_state = state
		floor_test.result_ceremony_enabled = false
		var baseline := floor_test.get_floor_front_z()
		floor_test.result_ceremony_enabled = true
		check(is_equal_approx(floor_test.get_floor_front_z(), baseline), "gate does not shorten floor " + state)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	OUT = "res://artifacts/result_finale/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT + "unit.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("RESULT_CEREMONY_UNIT " + JSON.stringify(report))
	for provider: QuizProvider in helper.providers:
		provider.free()
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)


## Score Tower Finale data and rules (Blender motion, After Effects HUD, timing).
func check_score_tower() -> void:
	var data := M.data()
	check(int(data.get("fps", 0)) == 60 and int(data.get("last_frame", 0)) == 672, "finale motion is 60 fps, 0-11.2 s")
	check(is_equal_approx(M.end_time(), QuizGameState.RESULT_TOTAL_DURATION), "controls arrive when the authored performance ends")
	check(is_equal_approx(M.VERDICT, QuizGameState.RESULT_VERDICT_TIME) and is_equal_approx(M.beat("verdict"), M.VERDICT), "verdict beat is shared")
	var phase_end := QuizGameState.RESULT_ASSEMBLE_DURATION + QuizGameState.RESULT_WALK_DURATION + QuizGameState.RESULT_SCORE_ROLL_DURATION
	check(is_equal_approx(phase_end, M.beat("climb_end")), "score roll phase ends when the leading tower tops out")
	check(is_equal_approx(phase_end + QuizGameState.RESULT_VERDICT_DURATION, M.VERDICT), "verdict phase starts on the verdict beat")
	for side in ["WIN", "LOSE"]:
		var actor: Dictionary = data.actors[side]
		check((actor.actor as Array).size() == 673 and (actor.fist as Array).size() == 673, "%s track covers every frame" % side)
		for joint in M.joints():
			check((actor.joints[joint] as Array).size() == 673, "%s %s sampled" % [side, joint])
	var previous := -1.0
	var monotonic := true
	for frame in range(673):
		var c := M.climb(frame / 60.0)
		monotonic = monotonic and c >= previous - 0.00001
		previous = c
	check(monotonic and is_zero_approx(M.climb(0.0)) and is_equal_approx(M.climb(6.4), 1.0), "climb progress rises 0 -> 1 without reversing")
	var loser_lock := M.lock_time(9, 21)
	var winner_lock := M.lock_time(21, 21)
	check(loser_lock < winner_lock and winner_lock <= 6.31, "lower total locks first; leader reaches the top")
	check(M.display_count(9, 21, loser_lock) == 9 and M.display_count(9, 21, loser_lock - 0.05) < 9, "loser counter stops exactly at its total")
	check(M.display_count(21, 21, 6.35) == 21 and M.display_count(21, 21, 4.0) == 0, "leader counts from zero to total")
	var h: Dictionary = M.heights()
	check(absf(M.tower_height(21, 21, false, 6.6) - float(h.top)) < 0.01, "leader tower reaches the top")
	check(absf(M.tower_height(9, 21, false, 6.6) - M.stop_height(9, 21)) < 0.01, "loser tower holds its proportional height")
	check(absf(M.tower_height(9, 21, false, 9.2) - float(h.collar)) < 0.02, "loser tower sinks back into the collar")
	check(absf(M.tower_height(12, 12, true, 6.6) - float(h.top)) < 0.01, "draw lifts both towers to the top")
	check(M.tower_height(0, 0, true, 6.6) <= float(h.pop) + 0.001, "a scoreless draw stays at pad height")
	check(M.tower_height(0, 9, false, 5.0) <= float(h.pop) + LOCK_TOLERANCE, "zero total never climbs")
	check(is_equal_approx(M.performance_time(11.2), 11.2) and M.performance_time(12.37) >= float(data.loop_start) and M.performance_time(12.37) <= 11.2, "performance loops after the controls appear")
	var hud: Variant = JSON.parse_string(FileAccess.get_file_as_string(ResultFinaleHud.HUD_PATH))
	check(hud is Dictionary and (hud.comps as Dictionary).has("FINALE_HUD_Win") and (hud.comps as Dictionary).has("FINALE_HUD_Draw"), "After Effects HUD samples load")
	for folder in [["burst", 24], ["lock_ring", 15]]:
		check(ResourceLoader.exists("res://assets/result_finale/fx/%s/%s_%02d.png" % [folder[0], folder[0], int(folder[1]) - 1]), "After Effects %s frames imported" % folder[0])


const M = preload("res://scripts/world/result_finale/result_finale_motion.gd")
const LOCK_TOLERANCE := 0.061  # ResultFinaleMotion.LOCK_BUMP plus float slack
