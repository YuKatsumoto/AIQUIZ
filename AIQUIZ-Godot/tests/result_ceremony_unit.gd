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
			"res://scripts/world/result_finale/result_finale_camera.gd",
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
			# Half points: 9 × (1 + 0.5) = 13.5 and 7 × (3 + 0.5) = 24.5.
			check(gs.result_p1_score == 27 and gs.result_p2_score == 49 and gs.result_ghost_mask == 0, "frozen totals")
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
			check(gs.message_text.contains("9 × 1.5 = 13.5") and gs.message_text.contains("7 × 3.5 = 24.5"), "final text uses survival bonus product")
			gs._reset_result_ceremony_state()
			check(not gs.result_presentation_active and gs.goal_reached_mask == 0 and gs.result_p1_hp == 0, "reset snapshots and latch")
	# [p1 correct, p1 HP, p2 correct, p2 HP, winner]; 6×2.5=15 beats 4×3.5=14, 5×3.5 ties 7×2.5.
	for example in [[8, 3, 9, 1, 1], [6, 2, 4, 3, 1], [0, 3, 0, 1, 0], [5, 3, 7, 2, 0]]:
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
		check(gs.result_p1_score == example[0] * (2 * example[1] + 1) and gs.result_winner == example[4], "snapshot immutable; long frame")
		# A draw holds for the sudden death descent (tests/sudden_death_unit.gd covers the rest).
		var expected_end := QuizGameState.SUDDEN_DEATH_DESCENT_TIME if gs.sudden_death_pending else gs.get_result_ceremony_total_duration()
		check(is_equal_approx(gs.result_ceremony_elapsed, expected_end), "long frame clamps at result")
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
	check_scoring()
	check_opponent_dies_while_waiting()
	check_ghost_finalist()
	check_elimination()
	for first in [1, 2]:
		var gs := fixture(first)
		gs.result_ceremony_enabled = false
		gs.update(1.0 / 60.0)
		kill(gs, 3 - first)
		gs.update(1.0 / 60.0)
		check(gs.game_state == Constants.STATE_CLEAR and gs.goal_winner == first and not gs.result_presentation_active, "gate off keeps sole-survivor result")
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


func kill(gs: QuizGameState, player_index: int, clock := 0.001) -> void:
	gs._set_player_hp(player_index, 0)
	if player_index == 1:
		gs.p1_alive = false
		gs.game_over_timer = clock
	else:
		gs.p2_alive = false
		gs.player2_game_over_timer = clock


## Frames until the finale starts (-1 if it never does within the limit).
func frames_until_ceremony(gs: QuizGameState, limit: int, dt := 1.0 / 60.0) -> int:
	for frame in range(limit):
		if gs.result_presentation_active:
			return frame
		gs.update(dt)
	return limit if gs.result_presentation_active else -1


func check_scoring() -> void:
	check(QuizGameState.result_half_points(9, 1, true) == 27 and QuizGameState.result_half_points(7, 3, true) == 49, "living finalist scores correct × (HP + 0.5)")
	check(QuizGameState.result_half_points(9, 3, false) == 18 and QuizGameState.result_half_points(0, 3, true) == 0, "ghost scores correct answers only")
	check(QuizGameState.format_result_points(27) == "13.5" and QuizGameState.format_result_points(18) == "9"
		and QuizGameState.format_result_points(0) == "0" and QuizGameState.format_result_points(1) == "0.5", "half points format")
	check(QuizGameState.format_result_points(18, true) == "9.0" and QuizGameState.format_result_points(27, true) == "13.5", "counter format keeps one decimal")
	check(QuizGameState.format_result_hp_factor(2) == "2.5" and QuizGameState.format_result_hp_factor(0) == "0.5", "HP factor text")


## Decision: the other player dies while the first finisher waits. The soul
## leaves after the death hold and leaps straight to the podium (no shark ride).
func check_opponent_dies_while_waiting() -> void:
	for first in [1, 2]:
		var other: int = 3 - first
		var gs := fixture(first)
		gs.update(1.0 / 60.0)
		check(gs.has_player_reached_goal(first), "finisher waits %d" % first)
		kill(gs, other)
		for frame in range(110):
			gs.update(1.0 / 60.0)
		check(gs.result_ghost_arrival_player == 0 and gs.result_ghost_mask == 0 and gs.game_state == Constants.STATE_GOAL_RACE, "death hold before the soul leaves %d" % first)
		for frame in range(15):
			if gs.result_ghost_arrival_player != 0:
				break
			gs.update(1.0 / 60.0)
		var correct := 9 if other == 1 else 7
		var ghost_score := gs.result_p1_score if other == 1 else gs.result_p2_score
		var ghost_hp := gs.result_p1_hp if other == 1 else gs.result_p2_hp
		check(gs.result_ghost_arrival_player == other and gs.is_result_ghost(other) and ghost_hp == 0 and ghost_score == correct * 2, "soul leaves after the death hold %d" % first)
		check(gs.game_state == Constants.STATE_GOAL_RACE and gs.message_text.contains("魂"), "arrival stays in the goal race %d" % first)
		var frames := frames_until_ceremony(gs, 120)
		check(frames >= 83 and frames <= 86, "ghost arrival lasts %.1f s (%d frames) %d" % [QuizGameState.RESULT_GHOST_ARRIVAL_DURATION, frames, first])
		# P1 alive 9 × 1.5 = 13.5 beats ghost P2 7; P2 alive 7 × 3.5 = 24.5 beats ghost P1 9.
		check(gs.result_winner == first and gs.game_state == Constants.STATE_RESULT_CEREMONY, "living finisher wins on points %d" % first)
		var landing := Vector3(QuizGameState.RESULT_PLAYER_X if other == 1 else -QuizGameState.RESULT_PLAYER_X, 0.0, gs.goal_z + QuizGameState.RESULT_GOAL_WAIT_OFFSET)
		var ghost_position := gs.result_p1_position if other == 1 else gs.result_p2_position
		check(ghost_position.is_equal_approx(landing), "ghost starts where it landed %d" % first)
		for frame in range(roundi(QuizGameState.RESULT_ASSEMBLE_DURATION * 60.0) + 1):
			gs.update(1.0 / 60.0)
		ghost_position = gs.result_p1_position if other == 1 else gs.result_p2_position
		check(absf(ghost_position.z - (gs.goal_z + QuizGameState.RESULT_WALK_ENTRY_OFFSET)) < 0.05 and is_equal_approx(ghost_position.x, landing.x), "ghost walks with the finalists %d" % first)
		gs.update(20.0)
		check(gs.game_state == Constants.STATE_CLEAR and gs.message_text.contains("(脱落)") and gs.is_wall_death_sequence_complete(), "ghost result text and controls %d" % first)
		check(not gs.p1_alive if other == 1 else not gs.p2_alive, "finale does not revive the ghost %d" % first)


## Pattern 1: the opponent has long been riding the ghost shark when the survivor
## finishes. The ghost leaps off in the same frame; HP is ignored for it.
func check_ghost_finalist() -> void:
	var gs := fixture(1)
	kill(gs, 2, 10.0)
	gs.update(1.0 / 60.0)
	check(gs.result_ghost_arrival_player == 2 and gs.is_result_ghost(2) and gs.result_p2_score == 14, "ghost leaps off as the survivor finishes")
	check(is_equal_approx(gs.get_result_ghost_arrival_progress(2), 0.0) and is_equal_approx(gs.get_result_ghost_arrival_progress(1), 0.0), "arrival progress starts at zero")
	var frames := frames_until_ceremony(gs, 120)
	check(frames >= 83 and frames <= 86 and gs.result_winner == 1, "survivor finale after the leap (%d frames)" % frames)
	# A ghost with more correct answers can still tie: 9 (dead) vs 6 × 1.5 = 9.
	var tie := fixture(1)
	tie.score = 6
	tie.player2_score = 9
	kill(tie, 2, 10.0)
	frames_until_ceremony(tie, 120)
	check(tie.result_presentation_active and tie.result_p1_score == 18 and tie.result_p2_score == 18 and tie.result_winner == 0, "ghost scores its correct answers only (draw)")
	var clockless := fixture(1)
	kill(clockless, 2, 0.0)
	clockless.update(1.0 / 60.0)
	check(clockless.result_ghost_arrival_player == 2, "a death without a clock does not block the finale")
	# Still alive in the ocean: nothing happens until the shark completes the attack.
	var ocean := fixture(1)
	ocean.update(1.0 / 60.0)
	ocean.player2_x = 30.0
	ocean.p2_waiting_for_shark = true
	for frame in range(180):
		ocean.update(1.0 / 60.0)
	check(ocean.result_ghost_mask == 0 and ocean.game_state == Constants.STATE_GOAL_RACE, "no ghost while the opponent floats")
	ocean.complete_ocean_shark_attack(2)
	check(not ocean.p2_alive and ocean.game_state == Constants.STATE_GOAL_RACE, "shark death while the finisher waits")
	for frame in range(110):
		ocean.update(1.0 / 60.0)
	check(ocean.result_ghost_mask == 0, "shark death is shown before the soul leaves")
	check(frames_until_ceremony(ocean, 120) > 0 and ocean.is_result_ghost(2), "shark victim reaches the podium as a ghost")


## Pattern 2: both players are out. The deaths play out without a GAME OVER card,
## then GameWorld wipes and the finale starts at the goal with two ghosts.
func check_elimination() -> void:
	var gs: QuizGameState = helper.fixture()
	gs.result_ceremony_enabled = true
	gs.score = 4
	gs.player2_score = 6
	gs._set_player_hp(1, 1)
	gs._set_player_hp(2, 1)
	var wrong_messages: Array[String] = []
	gs.wrong_answer.connect(func(message: String): wrong_messages.append(message))
	var requests := [0]
	gs.result_transition_requested.connect(func(): requests[0] += 1)
	helper.answer(gs, false, false)
	check(gs.game_state == Constants.STATE_GAME_OVER and gs.is_elimination_result_pending(), "elimination holds instead of GAME OVER")
	check(not gs.message_text.begins_with("GAME OVER") and gs.message_text.contains("結果発表へ"), "no GAME OVER text")
	check(wrong_messages.size() == 1 and gs._result_round_closed and gs.quiz_history.size() == 1, "round closed once, history kept")
	for frame in range(200):
		gs.update(1.0 / 60.0)
	check(not gs.is_elimination_result_ready() and requests[0] == 0, "wall deaths play out before the wipe")
	for frame in range(60):
		gs.update(1.0 / 60.0)
	check(gs.is_elimination_result_ready() and requests[0] == 1, "wipe requested after the death sequence")
	for frame in range(30):
		gs.update(1.0 / 60.0)
	check(requests[0] == 1 and gs.game_state == Constants.STATE_GAME_OVER, "wipe requested once")
	var scroll_before := gs.world_scroll_z
	check(gs.begin_elimination_result_ceremony(), "finale starts under the cover")
	check(gs.game_state == Constants.STATE_RESULT_CEREMONY and gs.result_ghost_mask == 3 and gs.result_from_elimination, "both players join as ghosts")
	check(gs.goal_z > 0.0 and is_equal_approx(gs.goal_z, gs.get_local_result_goal_z()), "finish line placed")
	check(is_equal_approx(gs.world_scroll_z, maxf(scroll_before, gs.goal_z - QuizGameState.RESULT_ELIMINATION_GOAL_AHEAD)), "scroll moved to the finish")
	check(gs.result_p1_score == 8 and gs.result_p2_score == 12 and gs.result_winner == 2, "ghosts ranked by correct answers")
	check(not gs.begin_elimination_result_ceremony() and not gs.is_elimination_result_pending(), "elimination finale starts once")
	gs.update(20.0)
	check(gs.game_state == Constants.STATE_CLEAR and gs.message_text.count("(脱落)") == 2, "elimination finale ends on the result controls")
	check(gs.is_wall_death_sequence_complete(), "result controls usable after elimination")
	# Everyone drowned during the goal race.
	var race := fixture()
	race.player_z = race.goal_z - 10.0
	race.player2_z = race.goal_z - 10.0
	race.p1_waiting_for_shark = true
	race.complete_ocean_shark_attack(1)
	check(race.game_state == Constants.STATE_GOAL_RACE, "first drowning keeps the race")
	race.p2_waiting_for_shark = true
	race.complete_ocean_shark_attack(2)
	check(race.game_state == Constants.STATE_GAME_OVER and race.is_elimination_result_pending(), "race elimination holds")
	var goal_before := race.goal_z
	for frame in range(185):
		race.update(1.0 / 60.0)
	check(race.is_elimination_result_ready(), "shark deaths hold %.1f s" % QuizGameState.RESULT_ELIMINATION_HOLD)
	check(race.begin_elimination_result_ceremony() and is_equal_approx(race.goal_z, goal_before) and race.result_winner == 1, "race elimination finale")
	# Other modes keep the GAME OVER card.
	for setup in [[2, Constants.MODE_ENDLESS, true], [1, Constants.MODE_TEN, true], [2, Constants.MODE_TEN, false]]:
		var other: QuizGameState = helper.fixture(setup[0], setup[1])
		other.result_ceremony_enabled = setup[2]
		other._set_player_hp(1, 1)
		other._set_player_hp(2, 1)
		helper.answer(other, false, false)
		check(other.game_state == Constants.STATE_GAME_OVER and not other.is_elimination_result_pending() and other.message_text.begins_with("GAME OVER"), "GAME OVER kept " + str(setup))
	var retry: QuizGameState = helper.fixture()
	retry.result_ceremony_enabled = true
	retry._set_player_hp(1, 1)
	retry._set_player_hp(2, 1)
	helper.answer(retry, false, false)
	retry.start_game()
	check(not retry.is_elimination_result_pending() and retry.result_ghost_mask == 0 and not retry.result_from_elimination and retry.result_ghost_arrival_player == 0, "retry clears elimination state")


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
	# Totals are half-points: one 0.3 m tier per point (2 half-points).
	check(is_equal_approx(M.stop_height(0), float(h.pop)) and is_equal_approx(M.stop_height(4) - M.stop_height(2), M.TIER_HEIGHT), "every point adds one 0.3 m tier")
	check(is_equal_approx(M.stop_height(70), float(h.pop) + 35.0 * M.TIER_HEIGHT) and M.TIER_COUNT >= 35, "a perfect 35 points stands 35 tiers tall on a long enough column")
	check(absf(M.tower_height(21, 21, 6.6) - M.stop_height(21)) < 0.01, "leader tower stops at its own tier height")
	check(absf(M.tower_height(56, 56, 6.6) - M.stop_height(56)) < 0.01 and M.stop_height(56) > float(h.top) + 1.0, "a high total climbs past the old fixed top")
	check(absf(M.tower_height(9, 21, 6.6) - M.stop_height(9)) < 0.01, "loser tower holds its own tier height")
	check(is_equal_approx(M.tower_height(9, 21, 6.6), M.tower_height(9, 60, 6.6)), "a tower's height does not depend on the other score")
	check(absf(M.tower_height(9, 21, 9.2) - float(h.collar)) < 0.02, "loser tower sinks back into the collar")
	check(absf(M.tower_height(12, 12, 9.2) - M.stop_height(12)) < 0.01, "draw keeps both towers up")
	check(M.tower_height(0, 0, 6.6) <= float(h.pop) + 0.001, "a scoreless draw stays at pad height")
	check(M.tower_height(0, 9, 5.0) <= float(h.pop) + LOCK_TOLERANCE, "zero total never climbs")
	var climbing := true
	# From the bottom of the authored anticipation dip until the counter locks.
	for frame in range(int(4.2 * 60.0), int(M.lock_time(40, 56) * 60.0)):
		climbing = climbing and M.tower_height(40, 56, (frame + 1) / 60.0) >= M.tower_height(40, 56, frame / 60.0) - 0.0001
	check(climbing and absf(M.tower_height(40, 56, 4.18) - M.winner_lift(4.18)) < 0.01, "towers rise steadily from the pad pop")
	# The column is stacked from the Blender tier modules: one tier per point, gold every 5th.
	var column := ResultFinaleStage.tier_column_mesh()
	var names := []
	for surface in range(column.get_surface_count()):
		names.append(column.surface_get_material(surface).resource_name)
	check(absf(column.get_aabb().size.y - M.TIER_COUNT * M.TIER_HEIGHT) < 0.01 and absf(column.get_aabb().end.y - ResultFinaleStage.COLUMN_TOP) < 0.01,
		"tier column is %d stacked 0.3 m tiers under the platform" % M.TIER_COUNT)
	check("FIN_TowerBody" in names and "FIN_TowerAccent" in names and "FIN_TierGold" in names, "tier column carries body, accent ring and gold milestone surfaces %s" % [names])
	# A double-sided surface is lit inside out under the P2 mirror (the tower went grey).
	var holder := Node3D.new()
	var tower: Node3D = ResultFinaleStage.create_tower(2, holder).root
	var double_sided := []
	for node: Node in tower.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material != null and material.cull_mode != BaseMaterial3D.CULL_BACK:
				double_sided.append(material.resource_name)
	check(double_sided.is_empty(), "score tower has no double-sided surfaces to light inside out when mirrored %s" % [double_sided])
	holder.free()
	check_tall_camera()
	check(is_equal_approx(M.performance_time(11.2), 11.2) and M.performance_time(12.37) >= float(data.loop_start) and M.performance_time(12.37) <= 11.2, "performance loops after the controls appear")
	var hud: Variant = JSON.parse_string(FileAccess.get_file_as_string(ResultFinaleHud.HUD_PATH))
	check(hud is Dictionary and (hud.comps as Dictionary).has("FINALE_HUD_Win") and (hud.comps as Dictionary).has("FINALE_HUD_Draw"), "After Effects HUD samples load")
	for folder in [["burst", 24], ["lock_ring", 15]]:
		check(ResourceLoader.exists("res://assets/result_finale/fx/%s/%s_%02d.png" % [folder[0], folder[0], int(folder[1]) - 1]), "After Effects %s frames imported" % folder[0])


## A towering winner: the finale camera leaves the baked shot for a low side shot
## beside the loser looking up at the winner (a draw: a low front two-shot). Every
## framing point stays in the free part of a 16:9 frame.
func check_tall_camera() -> void:
	check(is_zero_approx(C.tall_weight(Vector2(2.6, 1.0))) and is_equal_approx(C.tall_weight(Vector2(1.0, 3.6)), 1.0), "tall shot takes over between 2.6 m and 3.6 m")
	var towers_stop := M.lock_time(70, 70) + M.LOCK_BUMP_TIME
	check(C.SIDE_IN.x >= towers_stop - 0.01 and is_zero_approx(C.side_weight(1, towers_stop)) and is_equal_approx(C.side_weight(2, C.SIDE_IN.y), 1.0),
		"the camera stays in front until the towers stop (%.2f s)" % towers_stop)
	check(is_zero_approx(C.side_weight(0, 10.0)), "a draw stays in front")
	var original_size: Vector2i = get_viewport().size
	var size := Vector2(1280, 720)
	get_viewport().size = Vector2i(size)
	# [P1 half-points, P2 half-points, winner, time]; wins before C.SIDE_IN are still
	# the front two-shot, after it the side shot.
	for spec: Array in [[70, 6, 1, 5.5], [70, 6, 1, 6.4], [70, 6, 1, 8.2], [70, 6, 1, 10.0], [6, 70, 2, 10.0], [56, 27, 1, 5.5],
			[56, 27, 1, 7.3], [56, 27, 1, 10.0], [49, 46, 1, 7.3], [49, 46, 1, 10.0], [30, 10, 1, 9.5], [60, 60, 0, 6.5], [60, 60, 0, 10.0]]:
		var winner: int = spec[2]
		var time: float = spec[3]
		var heights := M.side_heights(spec[0], spec[1], winner, time)
		check(heights.x > heights.y - 0.001 or winner == 0, "winner's tower is on the stage's -X side")
		var side := C.side_weight(winner, time)
		check(side == 0.0 or side == 1.0, "spec %s is not mid-handover" % [spec])
		var framed := winner if side > 0.0 else 0
		var shot: Dictionary = C.shot(heights, winner, time)
		var pose: Transform3D = shot.transform
		var camera := Camera3D.new()
		camera.fov = shot.fov
		add_child(camera)
		camera.global_transform = pose
		var free := C.margins(framed, time)
		var inside := true
		for point in C.framing_points(heights, framed, time):
			var screen := camera.unproject_position(point)
			inside = inside and not camera.is_position_behind(point) \
				and screen.x >= size.x * (free.x - 0.01) and screen.x <= size.x * (1.01 - free.x) \
				and screen.y >= size.y * (free.y - 0.01) and screen.y <= size.y * (1.01 - free.z)
		camera.free()
		var forward := -pose.basis.z
		check(inside, "tall shot keeps the players clear of the title and cards %s" % [spec])
		check(forward.y > 0.05, "tall shot looks up (%.3f) %s" % [forward.y, spec])
		if framed == 0:
			check(pose.origin.z > 0.0 and forward.z < 0.0 and is_zero_approx(pose.origin.x), "front two-shot faces the stage, centred %s" % [spec])
			continue
		var loser_head := Vector3(M.TOWER_X, heights.y + 1.7, 0.0)
		var winner_head := Vector3(-M.TOWER_X, heights.x + 1.7, 0.0)
		check(pose.origin.distance_to(loser_head) < pose.origin.distance_to(winner_head), "side shot stands nearer the loser than the winner %s" % [spec])
		check(pose.origin.x > M.TOWER_X and pose.origin.z > 0.0 and forward.x < 0.0, "side shot looks across from the loser's front-outer side %s" % [spec])
		check(pose.origin.y < heights.x + 1.0, "side shot sits below the winner %s" % [spec])
	get_viewport().size = original_size
	# Once the title and cards are out of the way the lens moves right in beside the loser.
	for spec: Array in [[70, 6, 10.0], [56, 27, 10.0], [56, 27, 8.3], [49, 46, 8.3]]:
		var heights := M.side_heights(spec[0], spec[1], 1, spec[2])
		var close: Transform3D = C.shot(heights, 1, spec[2]).transform
		var loser_hip := Vector3(M.TOWER_X, heights.y + lerpf(C.SIDE_EYE_HEIGHT, C.SIDE_EYE_KNEEL_HEIGHT, C.kneel(spec[2])), 0.0)
		check(close.origin.distance_to(loser_hip) <= C.SIDE_DISTANCE + 0.01, "side shot stays %.1f m from the loser %s (%.2f)" % [C.SIDE_DISTANCE, spec, close.origin.distance_to(loser_hip)])
	var landslide: Transform3D = C.shot(M.side_heights(70, 6, 1, 10.0), 1, 10.0).transform
	check(-landslide.basis.z.y > 0.5, "a landslide is shot steeply upward (%.3f)" % -landslide.basis.z.y)


const M = preload("res://scripts/world/result_finale/result_finale_motion.gd")
const C = preload("res://scripts/world/result_finale/result_finale_camera.gd")
const LOCK_TOLERANCE := 0.061  # ResultFinaleMotion.LOCK_BUMP plus float slack
