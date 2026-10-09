extends Node

## Score Tower Finale in the real GameWorld: ten-question finish -> goal walk ->
## towers climb with the real totals -> verdict, confetti, crown / sinking tower,
## controls. Captures beats and optional frames for review.
## Args: case=p1|p2|draw|landslide|ghost_p2|ghost_win|elimination fps=30|60|120
##       quality=low|balanced|high record hats
##       sizes routes emote=<id> all_emotes audible out=<folder>
##       programme (1080p; keeps the result screen open and captures the scoreboard's
##       AIQUIZ VISION programme; add `reel` to play this match's own record; the
##       highlight replay is not played on the board)

var OUT := "res://artifacts/result_finale/runtime/"
var helper: Node
var gs: QuizGameState
var world: Node
var pc: PlayerController
var fps := 60
var scenario := "p1"
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var captured: Array[String] = []
var movie_frame := 0
var verify_routes := false
var verify_sizes := false
var verify_programme := false
var record_frames := false
var test_hats := false
var verify_all_emotes := false
var selected_emote := 0
var quality := "balanced"
var ceremony_start_frame := -1
var ghost_leap := {}
var elimination_seen := {}

# [P1 correct, P1 HP, P2 correct, P2 HP, winner]. Living finalists score
# correct × (HP + 0.5); ghosts (HP 0 here) score their correct answers only.
const SCENARIOS := {
	"p1": [8, 3, 9, 1, 1],          # 28 vs 13.5
	"landslide": [10, 3, 2, 1, 1],  # 35 vs 3: a 17.5-tier tower over a 1.5-tier one
	"p2": [9, 1, 7, 3, 2],          # 13.5 vs 24.5
	"draw": [5, 3, 7, 2, 0],        # 17.5 vs 17.5
	"ghost_p2": [8, 2, 9, 0, 1],    # 20 vs ghost 9 (P2 drowned, rides the ghost shark)
	"ghost_win": [3, 1, 7, 0, 2],   # 4.5 vs ghost 7: the ghost takes the crown
	"elimination": [5, 0, 3, 0, 1], # both out mid-quiz: ghosts 5 vs 3
}

const BEATS := [[0.2, "assemble"], [1.2, "walk"], [2.3, "hop"], [2.9, "correct"], [3.6, "formula"],
	[3.7, "hp_bonus"], [4.0, "hp_merged"], [4.6, "climb_early"], [5.5, "climb_mid"], [6.5, "hush"], [6.93, "verdict"], [7.1, "burst"],
	[7.45, "jump"], [7.75, "crown"], [8.4, "celebrate"], [9.0, "sinking"], [9.8, "orz"],
	[10.6, "final"]]


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	var audio_config_existed := FileAccess.file_exists(AudioManager.SETTINGS_PATH)
	var original_audio_config := FileAccess.get_file_as_string(AudioManager.SETTINGS_PATH) if audio_config_existed else ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("case="): scenario = arg.trim_prefix("case=")
		if arg.begins_with("fps="): fps = int(arg.trim_prefix("fps="))
		if arg == "record": record_frames = true
		if arg == "hats": test_hats = true
		if arg == "all_emotes": verify_all_emotes = true
		if arg.begins_with("emote="): selected_emote = int(arg.trim_prefix("emote="))
		if arg.begins_with("quality="): quality = arg.trim_prefix("quality=")
		if arg.begins_with("out="): OUT = "res://artifacts/result_finale/runtime/" + arg.trim_prefix("out=") + "/"
		if arg == "routes": verify_routes = true
		if arg == "sizes": verify_sizes = true
		if arg == "programme": verify_programme = true
		if arg == "audible":
			# Recording-only override; never write the user's audio preferences.
			AudioManager.set_sfx_volume(0.8, false)
			AudioManager.set_bgm_volume(0.10, false)
	if "reel" in OS.get_cmdline_user_args():
		# Run with the menu LED's match reel recording, as a real match does (its
		# capture camera re-renders the world); storage stays out of the player's history.
		MatchHistory.path_override = "user://test_ceremony_reel/match_history.json"
		HighlightStore.dir_override = "user://test_ceremony_reel/highlights"
		# Every run starts with an empty history (it is this test's own storage).
		for path: String in [MatchHistory.path(), HighlightStore.index_path()]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameManager.graphics_quality = quality
	get_tree().root.size = Vector2i(1920, 1080) if verify_programme else Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + scenario + "_frames"))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
	# The draw finale as it plays when the sudden death is off; the branch into the
	# sudden death is covered by tests/sudden_death_runtime.gd.
	gs.sudden_death_enabled = false
	if selected_emote > 0:
		gs.p1_emote_slots[0] = selected_emote
		gs.p2_emote_slots[0] = selected_emote
	if test_hats:
		gs.p1_hat = HatData.HAT_BOUSI
		gs.p2_hat = HatData.HAT_SOMBRERO
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	pc = world.get_node("Player") as PlayerController
	pc.prepare_for_loading(gs)
	await frames(fps)
	world.call("_clear_preview_walls")
	var setup: Array = SCENARIOS.get(scenario, SCENARIOS.p1)
	var ghost_case := scenario.begins_with("ghost")
	var eliminated := scenario == "elimination"
	gs.score = setup[0]
	gs.player2_score = setup[2]
	var expected_winner: int = setup[4]
	var marks_z := 0.0
	if eliminated:
		await eliminate_both_mid_quiz()
	else:
		gs.current_index = 10
		gs.current_wall_index = 10
		gs.load_current_quiz()
		check(gs.game_state == Constants.STATE_GOAL_RACE, "actual ten-question completion routes to goal")
		gs.world_scroll_z = gs.goal_z - 24.0
		gs.player_z = gs.goal_z - 10.0
		gs.player2_z = gs.goal_z - 10.0
		await frames(maxi(3, fps / 4))
		marks_z = gs.get_local_result_goal_z() + QuizGameState.RESULT_WALK_FINISH_OFFSET - gs.world_scroll_z
		var waiter := world.get_node_or_null("GoalLine/GoalWaitingReferee") as Node3D
		check(waiter != null and waiter.visible, "flag referee waits beyond the goal before the finish")
		if waiter != null:
			var rig := waiter.find_child("RIG_Referee", true, false) as Node3D
			check(rig != null and absf(rig.global_position.z - (marks_z + 1.0)) < 0.05, "waiting referee stands 1 m behind the finishing marks")
			check(rig != null and absf(rig.global_position.y + 1.2) < 0.3, "waiting referee stands on the conveyor")
			await capture("goal_approach")
		gs.player_x = 2.2
		gs.player2_x = -2.2
		gs.player_y = 0.0
		gs.player2_y = 0.0
		gs.p1_alive = true
		gs.p1_hp = setup[1]
		if ghost_case:
			await drown_p2_onto_ghost_shark()
		else:
			gs.p2_alive = true
			gs.p2_hp = setup[3]
			gs.player2_z = gs.goal_z - (0.3 if scenario in ["p1", "landslide"] else 1.6)
		gs.player_x = 2.2
		gs.player_z = gs.goal_z - (1.6 if scenario in ["p1", "landslide"] else 0.3)
	var expected_hp := [gs.p1_hp, gs.p2_hp]
	var expected_alive := [not eliminated, not eliminated and not ghost_case]
	gs.result_ceremony_phase_changed.connect(func(phase: int): phases.append({"phase": phase, "time": gs.result_ceremony_elapsed}))
	var overlay: Control = world.get_node("GameplayHUD/ResultCeremonyOverlay")
	var director: Node3D = world.get("_result_ceremony_director")
	var ceremony_frames := 0
	var interactive_frames := 0
	for frame in range(fps * 24):
		await RenderingServer.frame_post_draw
		if ghost_case:
			await observe_ghost_leap(director)
		if eliminated:
			await observe_elimination()
		if gs.result_presentation_active:
			if ceremony_start_frame < 0:
				# Movie Maker writes one frame per drawn frame; used to trim review videos.
				ceremony_start_frame = Engine.get_frames_drawn()
			ceremony_frames += 1
			var time := gs.result_ceremony_elapsed
			if record_frames and ceremony_frames % maxi(1, fps / 30) == 0:
				get_viewport().get_texture().get_image().save_png(OUT + scenario + "_frames/frame_%04d.png" % movie_frame)
				movie_frame += 1
			for point in BEATS:
				if time >= float(point[0]) - 0.00001 and not String(point[1]) in captured:
					await capture(String(point[1]))
			if gs.game_state != Constants.STATE_CLEAR:
				check(not overlay.get_debug_snapshot().actions_visible, "no early actions")
		if gs.game_state == Constants.STATE_CLEAR and gs.result_presentation_active:
			interactive_frames += 1
			if interactive_frames == fps:
				await capture("buttons_settled")
			if interactive_frames >= fps * 2:
				await capture("loop_living")
				break
		await get_tree().process_frame
	var final: Dictionary = director.get_debug_snapshot()
	var hud: Dictionary = overlay.get_debug_snapshot()
	var programme_report := {}
	if verify_programme:
		programme_report = await observe_programme()
	# The elimination finale moves the round to the finish line under the wipe.
	marks_z = gs.get_local_result_goal_z() + QuizGameState.RESULT_WALK_FINISH_OFFSET - gs.world_scroll_z
	check(gs.result_winner == expected_winner, "winner based on goal products")
	check(gs.game_state == Constants.STATE_CLEAR and is_equal_approx(gs.result_ceremony_elapsed, QuizGameState.RESULT_TOTAL_DURATION), "interactive after the authored performance")
	check([gs.p1_hp, gs.p2_hp] == expected_hp and [gs.p1_alive, gs.p2_alive] == expected_alive, "finale preserves authoritative HP and life")
	check(hud.motion_loaded and hud.actions_visible and hud.buttons.size() == 3, "After Effects HUD and three controls visible")
	var decimal := (gs.result_p1_score & 1) == 1 or (gs.result_p2_score & 1) == 1
	check(hud.totals == [QuizGameState.format_result_points(gs.result_p1_score, decimal), QuizGameState.format_result_points(gs.result_p2_score, decimal)], "cards show the frozen products")
	check_steady_counter(decimal)
	check_hp_bonus()
	if ghost_case or eliminated:
		check_ghost_finale(overlay, director)
	check(hud.verdict == ("DRAW!" if expected_winner == 0 else "WIN!"), "verdict word matches outcome")
	check(final.built and final.visible and final.cast_visible and final.winner == expected_winner, "finale stage built in the game world")
	check(final.referee_animation == ["FinaleDraw", "FinaleWin", "FinaleWinP2"][expected_winner], "referee plays the outcome's animation")
	check(world.get_node("StageEnvironment/Floor").visible and world.get_node("StageEnvironment/Grandstands").visible, "real conveyor and stadium stay visible")
	check(absf(float(final.stage_origin.y) + 1.2) < 0.01 and absf(float(final.stage_origin.z) - marks_z) < 0.05, "stage anchored at the finishing marks")
	check(bool(final.mirrored) == (expected_winner == 2), "only a P2 win mirrors the stage")
	var unmirrored := samples.all(func(sample: Dictionary) -> bool:
		return not sample.director.get("built", false) or float(sample.director.get("referee_rig_determinant", 1.0)) > 0.0)
	check(unmirrored and float(final.referee_rig_determinant) > 0.0, "the referee is never drawn mirrored (a mirrored plush reads dark)")
	check_referee_flags(final, expected_winner)
	var heights: Dictionary = sample_of("hush").director.heights
	var h: Dictionary = ResultFinaleMotion.heights()
	var totals := [gs.result_p1_score, gs.result_p2_score]
	for player_index in [1, 2]:
		# One 0.3 m tier per 2 points, plus the 2 cm pad clearance.
		var expected := ResultFinaleMotion.stop_height(totals[player_index - 1]) + ResultFinaleStage.PAD_CLEARANCE
		check(absf(float(heights[player_index]) - expected) < 0.08, "P%d tower height matches its total at the hush (%.2f / %.2f)" % [player_index, float(heights[player_index]), expected])
	check_tall_framing()
	for actor: Dictionary in sample_of("formula").director.actors:
		check(absf(float(actor.lowest) - float(actor.platform_y)) < 0.06, "P%d stands on the pad (contact %.3f)" % [actor.player, float(actor.lowest) - float(actor.platform_y)])
		check(absf(absf(float(actor.tower_x)) - 2.2) < 0.01 and signf(float(actor.tower_x)) == (1.0 if int(actor.player) == 1 else -1.0), "P%d tower stays in its own lane" % actor.player)
		check(int(actor.hat) == (gs.p1_hat if int(actor.player) == 1 else gs.p2_hat), "actor keeps selected hat")
	for actor: Dictionary in sample_of("hush").director.actors:
		check(absf(float(actor.lowest) - float(actor.platform_y)) < 0.08, "P%d rides the tower top" % actor.player)
	# Resting pads sit clear of the collar ring (they used to share its depth plane).
	for tag in ["assemble", "walk"]:
		for player_index in [1, 2]:
			var rest := float(sample_of(tag).director.heights[player_index])
			check(rest >= float(h.collar) + ResultFinaleStage.PAD_CLEARANCE - 0.001, "%s: P%d pad clears the collar (%.3f)" % [tag, player_index, rest])
	await check_goal_stand(expected_winner, marks_z, not eliminated)
	var verdict_sample: Dictionary = sample_of("burst")
	check(int(verdict_sample.hud.burst_frame) >= 0, "After Effects verdict burst plays")
	var events: Array = final.effects
	var bursts := events.filter(func(event): return event.kind == "confetti_burst")
	check(bursts.size() == (2 if expected_winner == 0 else 1), "cannon confetti fires from the winning tower(s)")
	check(events.filter(func(event): return event.kind == "firework").size() == 4, "four fireworks light the sky")
	check(float(bursts[0].time) >= ResultFinaleMotion.VERDICT if not bursts.is_empty() else false, "confetti waits for the verdict")
	if expected_winner != 0:
		var crown: Dictionary = sample_of("celebrate").director.crown
		check(crown.visible and absf(float(crown.above_mount) - float(crown.offset)) < 0.15 and float(crown.offset) < 0.9, "crown rests on the winner's head or hat (%.3f / %.3f)" % [float(crown.above_mount), float(crown.offset)])
		check(not sample_of("orz").director.has("cloud") and events.filter(func(event): return event.kind == "rain").is_empty(), "no rain cloud over the loser")
		check(float(sample_of("orz").director.heights[3 - expected_winner]) < 0.12, "loser's tower sinks back to the floor")
		var dance: Dictionary = final.dances[expected_winner]
		check(dance.ready and int(dance.emote) == EmoteData.normalize_emote_id(gs.get_result_winner_emote(expected_winner)), "winner plays the equipped emote on the tower")
		var end_actors: Array = sample_of("final").director.actors
		var winner_actor: Dictionary = end_actors.filter(func(actor): return int(actor.player) == expected_winner)[0]
		var loser_actor: Dictionary = end_actors.filter(func(actor): return int(actor.player) != expected_winner)[0]
		var area := Rect2(Vector2.ZERO, Vector2(1280, 720))
		check(area.grow(4).encloses(winner_actor.screen_bounds), "winner stays in the final frame")
		check(area.intersects(loser_actor.screen_bounds), "loser remains visible in the final frame")
		check(float(winner_actor.head_world.y) > float(loser_actor.head_world.y) + 1.5, "winner stands high above the kneeling loser")
		check(events.filter(func(event): return event.kind == "confetti_rain").size() == 1, "confetti keeps falling over the winner")
	else:
		check(final.crown.is_empty() and events.filter(func(event): return event.kind == "rain").is_empty(), "draw has no crown or rain")
		check((final.dances as Dictionary).size() == 2, "both players dance on a draw")
	# The pre-verdict shot is symmetric: P1 left, P2 right in every outcome.
	for tag in ["correct", "climb_mid"]:
		var actors: Array = sample_of(tag).director.actors
		var p1: Dictionary = actors.filter(func(actor): return int(actor.player) == 1)[0]
		var p2: Dictionary = actors.filter(func(actor): return int(actor.player) == 2)[0]
		check(float(p1.head.x) < 640.0 and float(p2.head.x) > 640.0, "%s keeps P1 left and P2 right before the verdict" % tag)
	# The plush's face shares its body mesh: only rigid moves and arm bends are allowed.
	var worst_bend := 0.0
	for sample: Dictionary in samples:
		if sample.director.has("referee_body_bend"):
			worst_bend = maxf(worst_bend, float(sample.director.referee_body_bend))
	check(worst_bend >= 0.0 and worst_bend < 0.5, "referee head/body bones never bend (max %.3f deg)" % worst_bend)
	var living_a: Dictionary = sample_of("buttons_settled").director
	var living_b: Dictionary = sample_of("loop_living").director
	check(not is_equal_approx(float(living_a.referee_time), float(living_b.referee_time)), "cast keeps living while the controls wait")
	check(float(living_b.performance) >= ResultFinaleMotion.data().loop_start and float(living_b.performance) <= ResultFinaleMotion.end_time() + 0.001, "performance loops within its authored tail")
	if verify_sizes:
		for extent in [Vector2i(1920, 1080), Vector2i(1024, 768)]:
			get_tree().root.size = extent
			await frames(4)
			var snapshot: Dictionary = overlay.get_debug_snapshot()
			var area := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
			check(area.encloses(snapshot.canvas_rect), "HUD canvas fits %s" % extent)
			for player_index in [1, 2]:
				check(area.encloses(snapshot.cards[player_index].rect), "card P%d stays inside %s" % [player_index, extent])
			await capture("size_%dx%d" % [extent.x, extent.y])
		get_tree().root.size = Vector2i(1280, 720)
		await frames(4)
	(world.get_node("GameplayHUD") as CanvasLayer).call("_open_history")
	await frames(2)
	check(not overlay.visible, "history suppresses the finale HUD")
	(world.get_node("GameplayHUD") as CanvasLayer).call("_close_history")
	await frames(2)
	check(overlay.visible, "history returns to the finale")
	if verify_all_emotes and expected_winner > 0:
		for emote in EmoteData.get_playable_emote_ids():
			if expected_winner == 1: gs.p1_emote_slots[0] = emote
			else: gs.p2_emote_slots[0] = emote
			var stage: ResultFinaleStage = director.get("_stage")
			stage.build(expected_winner)
			await frames(6)
			var shot: Dictionary = stage.get_debug_snapshot()
			check(shot.dances[expected_winner].ready and int(shot.dances[expected_winner].emote) == emote, "selected emote loads: %d" % emote)
			await capture("emote_%02d" % emote)
	director.force_cleanup()
	gs._reset_result_ceremony_state()
	gs.game_state = Constants.STATE_WAITING_START
	await frames(3)
	check(not world.get("camera_controller").get("_result_camera_active"), "camera releases result latch")
	check(not director.get_debug_snapshot().built and pc.visible, "reset frees the finale stage and restores players")
	await capture("restored")
	if verify_routes:
		await check_scene_routes()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "case": scenario, "fps": fps,
		"quality": quality, "hats": test_hats, "renderer": RenderingServer.get_current_rendering_method(),
		"phases": phases, "samples": samples, "movie_frames": movie_frame, "ceremony_start_frame": ceremony_start_frame,
		"programme": programme_report}
	FileAccess.open(OUT + "runtime_" + scenario + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("RESULT_FINALE_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "case": scenario, "fps": fps,
		"ceremony_start_frame": ceremony_start_frame, "failures": failures}))
	if audio_config_existed:
		FileAccess.open(AudioManager.SETTINGS_PATH, FileAccess.WRITE).store_string(original_audio_config)
	world.queue_free()
	await frames(2)
	for provider in helper.providers: provider.free()
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)


## Keeps the result screen open and watches the scoreboard hand over from the winner's
## cut-in to the AIQUIZ VISION programme and play it to the logo. Saves a frame of the
## real view and the board's own 1400 x 600 picture for each segment, and times the
## frame the programme starts on. Add `reel` to play this match's own record (the
## highlight replay is left out on the board); without it the programme shows the
## invitation segment.
func observe_programme() -> Dictionary:
	var stand := world.get("_goal_stand") as GoalStand
	var board := stand.scoreboard
	var dir := OUT + scenario + "_programme/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var segments: Array[String] = []
	var shots := 0
	var last_key := ""
	var key_clock := 0.0
	var shot_clock := -100.0
	var shot_pending := false
	var started_clock := -1.0
	var last_usec := Time.get_ticks_usec()
	var worst_start_msec := 0.0
	var start_frame_msec := 0.0
	var worst_msec := 0.0
	var cutin_after_start := false
	for _frame in range(fps * 150):
		await RenderingServer.frame_post_draw
		var now_usec := Time.get_ticks_usec()
		var frame_msec := float(now_usec - last_usec) / 1000.0
		last_usec = now_usec
		if not board.is_programme_started():
			await get_tree().process_frame
			continue
		var programme := board.programme()
		if started_clock < 0.0:
			started_clock = programme.clock
			start_frame_msec = frame_msec
		# Frames that saved screenshots (below) restart the timer, so they never count.
		worst_msec = maxf(worst_msec, frame_msec)
		if programme.clock - started_clock < 2.0:
			worst_start_msec = maxf(worst_start_msec, frame_msec)
		if board.is_programme_playing() and board.is_cutin_playing():
			cutin_after_start = true
		var info := board.programme_segment()
		var key := "%s|%s" % [str(info.get("comp", "")), str(info.get("title", ""))]
		if key != last_key:
			last_key = key
			key_clock = programme.clock
			shot_pending = true
			segments.append(key)
		# Late enough for the segment's own reveal and count-ups to have settled.
		var wanted := shot_pending and programme.clock - key_clock >= 2.2
		wanted = wanted or (key.begins_with("REPLAY") and programme.clock - shot_clock >= 6.0 and programme.clock - key_clock >= 0.9)
		if wanted and not board.programme().is_lead_in():
			shot_pending = false
			shot_clock = programme.clock
			var tag := "%02d_%s" % [shots, key.replace("|", "_").replace("/", "_")]
			get_viewport().get_texture().get_image().save_png(dir + tag + "_view.png")
			board.viewport.get_texture().get_image().save_png(dir + tag + "_board.png")
			shots += 1
			last_usec = Time.get_ticks_usec()
		if key.begins_with("LED_LogoLoop") and programme.clock - key_clock >= 1.5:
			break
		await get_tree().process_frame
	check(board.is_programme_started(), "the scoreboard handed over to the programme on the result screen")
	check(not cutin_after_start, "the winner's cut-in never came back under the programme")
	check(not segments.is_empty() and segments[segments.size() - 1].begins_with("LED_LogoLoop"), "the programme played through to the logo: %s" % [segments])
	# The highlight replay is left out on the board (GoalStandScoreboard.PLAY_REPLAY).
	check(segments.all(func(key: String) -> bool: return not key.begins_with("REPLAY") and not key.ends_with("HIGHLIGHTS")),
		"no highlight replay on the board: %s" % [segments])
	if world.get("_match_reel") != null:
		check(segments[0] == "LED_Sting|RECORDS", "with this match saved the programme starts at RECORDS: %s" % [segments])
	var report := {"segments": segments, "shots": shots, "worst_frame_msec": snappedf(worst_msec, 0.1),
		"start_frame_msec": snappedf(start_frame_msec, 0.1), "worst_start_frame_msec": snappedf(worst_start_msec, 0.1),
		"setup_msec": snappedf(board.programme_setup_msec, 0.1), "match_reel": world.get("_match_reel") != null}
	print("PROGRAMME_OBSERVED " + JSON.stringify(report))
	return report


## Finish grandstand beyond the conveyor: placement, cast, moods, eggs and boards.
func check_goal_stand(expected_winner: int, marks_z: float, raced := true) -> void:
	var stand := world.get("_goal_stand") as GoalStand
	check(stand != null and stand.is_populated(), "goal stand is built and fully populated")
	if stand == null:
		return
	var goal_local := gs.get_local_result_goal_z() - gs.world_scroll_z
	check(absf(stand.global_position.z - (goal_local + GoalStand.GOAL_OFFSET)) < 0.05 and absf(stand.global_position.y + 1.2) < 0.01, "stand sits past the conveyor end")
	check(stand.global_position.z > marks_z + 20.0, "stand is behind the finale towers")
	var shot := stand.get_debug_snapshot()
	check(int(shot.spectators) >= 40, "stand holds a crowd (%d)" % int(shot.spectators))
	var kinds: Dictionary = shot.kinds
	for kind in ["HOTHEAD", "DANCER", "SIGN", "FLAG", "FOAM", "FAN"]:
		check(int(kinds.get(kind, 0)) > 0, "crowd includes %s" % kind)
	if raced:
		check(String(sample_of("goal_approach").stand.get("mood", "")) == "hype", "crowd is hyped while the players race to the goal")
	check(String(sample_of("climb_mid").stand.get("mood", "")) == "nervous", "crowd holds its breath while the towers climb")
	var end: Dictionary = sample_of("loop_living").stand
	check(String(end.get("mood", "")) == "verdict", "crowd reacts to the verdict")
	# The scoreboard holds its grid until the verdict "WIN", then shows the winner's cut-in.
	var board_cutin := GoalStandScoreboard.DRAW if expected_winner == 0 else expected_winner
	check(int(sample_of("hush").stand.scoreboard.cutin) == 0, "scoreboard keeps the grid before the verdict")
	check(int(sample_of("burst").stand.scoreboard.cutin) == board_cutin, "scoreboard cut-in comes up with the verdict")
	check(int(sample_of("final").stand.scoreboard.cutin) == board_cutin and not sample_of("final").stand.scoreboard.programme,
		"scoreboard holds the winner's cut-in until the result screen opens")
	# On the result screen the AIQUIZ VISION programme takes over once the match is saved
	# (at once when there is no reel), and the cut-in does not come back.
	check(bool(end.scoreboard.programme) or int(end.scoreboard.cutin) == board_cutin, "scoreboard shows the cut-in or hands over to the programme")
	check(not (bool(end.scoreboard.programme_playing) and int(end.scoreboard.cutin) != 0), "the cut-in is gone once the programme plays")
	# Cost of the crowd in the busiest shot: draw calls with and without the stand.
	var calls_with := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	stand.visible = false
	await frames(3)
	var calls_without := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	stand.visible = true
	await frames(2)
	print("GOAL_STAND_COST " + JSON.stringify({"draw_calls_with": calls_with, "draw_calls_without": calls_without,
		"update_usec": snappedf(float(stand.get_debug_snapshot().update_usec), 0.1), "spectators": int(shot.spectators), "quality": quality}))
	check(int(end.eggs_launched) >= 4 and int(end.eggs_hit) >= 1, "hotheads pelt the %s with eggs (%d thrown, %d hit)" % ["referee" if expected_winner == 0 else "loser", int(end.eggs_launched), int(end.eggs_hit)])
	var dancing := 0
	for clip: String in (end.clips as Dictionary):
		if clip.begins_with("SPEC_Dance"):
			dancing += int(end.clips[clip])
	check(dancing >= 3, "party people dance the game's emotes (%d)" % dancing)
	var celebrating := int(end.clips.get("SPEC_Cheer", 0)) + int(end.clips.get("SPEC_SignUp", 0)) + int(end.clips.get("SPEC_Wave", 0))
	check(celebrating >= 5, "winning fans celebrate (%d)" % celebrating)
	if expected_winner != 0:
		check(int(end.boo_signs) >= 1, "losing fans flip their boards to boo")
		check(int(end.clips.get("SPEC_Despair", 0)) + int(end.clips.get("SPEC_ShakeHead", 0)) + int(end.clips.get("SPEC_FoldArms", 0)) >= 3, "losing fans despair")
	else:
		check(int(end.boo_signs) == 0, "a draw leaves every board cheering")


## Pattern 1 setup: P2 falls into the sea during the goal race, the real shark
## takes them, and they ride the ghost shark until P1 reaches the goal.
func drown_p2_onto_ghost_shark() -> void:
	var ride: GhostSharkRideController = world.get("_ghost_shark_ride_controller")
	gs.player2_x = -(QuizGameState.FLOOR_HALF_WIDTH + 2.5)
	gs.player2_z = gs.goal_z - 12.0
	gs._begin_ocean_shark_wait(2)
	var aiming := false
	for frame in range(fps * 45):
		gs.player_z = gs.goal_z - 10.0
		await get_tree().process_frame
		if ride.phase == GhostSharkRideController.Phase.AIMING:
			aiming = true
			break
	check(not gs.p2_alive and gs.p2_shark_killed and aiming, "P2 drowned and rides the ghost shark")
	for frame in range(40):
		gs.player_z = gs.goal_z - 10.0
		await get_tree().process_frame
	ghost_leap["shark"] = ride.get("_shark")
	await capture("ghost_on_shark")


## Samples the leap from the ghost shark onto the result lane.
func observe_ghost_leap(director: Node) -> void:
	var ride: GhostSharkRideController = world.get("_ghost_shark_ride_controller")
	if gs.result_ghost_mask != 0 and ride.get_debug_state().return_portal_active:
		ghost_leap["portal"] = true
	var ghost: Node3D = director.call("get_result_ghost", 2)
	if ghost == null or gs.result_ghost_arrival_player != 2:
		return
	var progress := gs.get_result_ghost_arrival_progress(2)
	var landing: Vector3 = (world as Node3D).to_global(gs.get_result_ghost_landing_local_position(2))
	if not ghost_leap.has("start"):
		ghost_leap["start"] = ghost.global_position
		ghost_leap["ride_inactive"] = ride.phase == GhostSharkRideController.Phase.INACTIVE
		ghost_leap["parent"] = String(ghost.get_parent().name)
		await capture("ghost_leap_start")
	elif progress >= 0.5 and not "ghost_leap_mid" in captured:
		var start: Vector3 = ghost_leap.start
		var straight := start.lerp(landing, smoothstep(0.0, 1.0, progress))
		ghost_leap["arc_lift"] = ghost.global_position.y - straight.y
		var wipe := world.get_node_or_null("DeathWipeLayer/DeathWipe")
		ghost_leap["wipe_hidden"] = wipe == null or not bool(wipe.get("_active")) or bool(wipe.get("_is_hiding"))
		ghost_leap["p2_debris"] = (pc.get("_p2_explosion_bodies") as Array).size() + int(not (pc.get("_p2_ragdoll") as Dictionary).is_empty())
		await capture("ghost_leap_mid")
	elif progress >= 1.0 and not "ghost_landed" in captured and (not gs.result_presentation_active or gs.result_ceremony_elapsed < 0.05):
		ghost_leap["landing_error"] = ghost.global_position.distance_to(landing)
		await capture("ghost_landed")


## Pattern 2 setup: both players are knocked out at a wall in the middle of the quiz.
func eliminate_both_mid_quiz() -> void:
	gs.current_index = 3
	gs.current_wall_index = 3
	gs.game_state = Constants.STATE_PLAYING
	gs.load_current_quiz()
	# Keep the wall a few metres ahead so no real door is crossed before the
	# scripted wrong answers (different wrong doors keep the two bodies apart).
	var wall_z := gs.tuning.wall_start_z + 3 * gs.tuning.wall_spacing
	gs.world_scroll_z = wall_z - 7.0
	gs.player_z = gs.world_scroll_z + 0.5
	gs.player2_z = gs.world_scroll_z + 0.5
	await frames(3)
	await capture("elim_playing")
	gs._set_player_hp(1, 1)
	gs._set_player_hp(2, 1)
	var wrong_a := (gs.current_quiz.a + 1) % gs.num_choices
	var wrong_b := (gs.current_quiz.a + 2) % gs.num_choices if gs.num_choices > 2 else wrong_a
	gs.player_x = gs.tuning.door4_xs[wrong_a] if gs.num_choices == 4 else (gs.tuning.left_door_x if wrong_a == 0 else gs.tuning.right_door_x)
	gs.player2_x = gs.tuning.door4_xs[wrong_b] if gs.num_choices == 4 else (gs.tuning.left_door_x if wrong_b == 0 else gs.tuning.right_door_x)
	gs.resolve_collision(true, true)
	check(gs.score == 5 and gs.player2_score == 3, "scripted wrong answers keep the correct counts")
	check(gs.game_state == Constants.STATE_GAME_OVER and gs.is_elimination_result_pending(), "both out mid-quiz hold for the finale")
	check(not gs.message_text.begins_with("GAME OVER"), "no GAME OVER text when both are out")


## Watches the hold, the wipe and the reveal of the elimination finale.
func observe_elimination() -> void:
	var hud := world.get_node("GameplayHUD")
	if (hud.get("game_over_panel") as Control).visible:
		elimination_seen["panel"] = true
	if not is_instance_valid(world.get("_goal_stand")):
		elimination_seen["stand_lost"] = true
	if gs.is_elimination_result_pending():
		elimination_seen["pending_frames"] = int(elimination_seen.get("pending_frames", 0)) + 1
		if int(elimination_seen.pending_frames) == fps:
			await capture("elim_death_hold")
	if SceneTransition.is_fully_covered() and not "elim_cover" in captured and not elimination_seen.has("revealed"):
		await capture("elim_cover")
	if gs.result_presentation_active and not elimination_seen.has("started"):
		elimination_seen["started"] = true
		elimination_seen["covered_at_start"] = SceneTransition.is_fully_covered()
	var camera_rig: Node = world.get("camera_controller")
	if gs.result_presentation_active and bool(camera_rig.get("_result_camera_active")) and not elimination_seen.has("camera_cut"):
		# First finale camera frame: already on the Blender shot, no swoop from the death.
		var camera: Camera3D = get_viewport().get_camera_3d()
		var start_eye: Vector3 = camera_rig.get("_result_winner_start_eye")
		elimination_seen["camera_cut"] = camera.global_position.distance_to(start_eye) if camera != null else INF
	if elimination_seen.has("started") and not elimination_seen.has("revealed") and not SceneTransition.is_transitioning():
		elimination_seen["revealed"] = true
		elimination_seen["walls"] = (world.get("_active_walls") as Array).size()
		elimination_seen["debris"] = (pc.get("_p1_explosion_bodies") as Array).size() + (pc.get("_p2_explosion_bodies") as Array).size()
		elimination_seen["ragdolls"] = int(not (pc.get("_p1_ragdoll") as Dictionary).is_empty()) + int(not (pc.get("_p2_ragdoll") as Dictionary).is_empty())
		await capture("elim_reveal")


## Ghost finalists: translucent stand-ins, "OUT" cards and the leap / wipe evidence.
func check_ghost_finale(overlay: Control, director: Node) -> void:
	var named: Dictionary = overlay.get("_named")
	for actor: Dictionary in sample_of("hop").director.actors:
		var player_index := int(actor.player)
		check(bool(actor.get("ghost", false)) == gs.is_result_ghost(player_index), "P%d stand-in look matches ghost state" % player_index)
	for player_index in [1, 2]:
		var prefix: String = overlay.call("_card_prefix", player_index)
		var hp_layer: Variant = named.get(prefix + "/HpValue")
		var caption: Variant = named.get(prefix + "/CaptionHp")
		if gs.is_result_ghost(player_index):
			check(hp_layer != null and String(hp_layer.text) == "—" and caption != null and String(caption.text) == "脱落", "P%d card shows OUT instead of HP" % player_index)
			var ghost: Node3D = director.call("get_result_ghost", player_index)
			check(ghost != null and not ghost.visible, "P%d ghost hands over to the stand-in" % player_index)
		else:
			check(hp_layer != null and String(hp_layer.text).ends_with(".5"), "P%d card shows HP + 0.5" % player_index)
	check(gs.message_text.count("(脱落)") == int(gs.is_result_ghost(1)) + int(gs.is_result_ghost(2)), "result text marks the ghosts")
	if scenario.begins_with("ghost"):
		check(ghost_leap.has("start") and "ghost_leap_mid" in captured and "ghost_landed" in captured, "ghost leap observed")
		check(bool(ghost_leap.get("ride_inactive", false)) and String(ghost_leap.get("parent", "")) == "ResultGhosts", "rider leaves the ghost shark for the finale")
		check(float(ghost_leap.get("arc_lift", 0.0)) > 1.5, "ghost arcs above a straight path (%.2f m)" % float(ghost_leap.get("arc_lift", 0.0)))
		check(float(ghost_leap.get("landing_error", INF)) < 0.1, "ghost lands on its own lane (%.3f m)" % float(ghost_leap.get("landing_error", INF)))
		check(bool(ghost_leap.get("wipe_hidden", false)), "death picture-in-picture closes for the leap")
		check(int(ghost_leap.get("p2_debris", -1)) == 0, "the drowned body leaves the stage")
		check(not ghost_leap.get("portal", false), "shark never returns through a portal by the podium")
		var shark: Node3D = ghost_leap.get("shark")
		check(shark != null and is_instance_valid(shark) and shark.global_position.y < StageConstants.OCEAN_SURFACE_Y, "ghost shark dives back under")
	else:
		check(not elimination_seen.get("panel", false), "GAME OVER card never shows")
		check(not elimination_seen.get("stand_lost", false), "goal stand stays through the hold")
		check(int(elimination_seen.get("pending_frames", 0)) >= roundi(fps * 3.9), "deaths play out before the wipe (%d frames)" % int(elimination_seen.get("pending_frames", 0)))
		check(bool(elimination_seen.get("covered_at_start", false)), "finale starts under the wipe")
		check(int(elimination_seen.get("walls", -1)) == 0 and int(elimination_seen.get("debris", -1)) == 0 and int(elimination_seen.get("ragdolls", -1)) == 0, "walls and bodies cleared for the finale")
		check(float(elimination_seen.get("camera_cut", INF)) < 0.3, "finale opens on the finale camera (%.2f)" % float(elimination_seen.get("camera_cut", INF)))
		check("elim_cover" in captured and "elim_reveal" in captured, "wipe observed")


## HP value text and survival bonus visibility on each card (AE layers by name).
func card_texts(overlay: Node) -> Dictionary:
	var named: Dictionary = overlay.get("_named")
	var cards := {}
	for player_index in [1, 2]:
		var prefix: String = overlay.call("_card_prefix", player_index)
		var hp_layer: Variant = named.get(prefix + "/HpValue")
		var chip: Variant = named.get(prefix + "/HpBonusChip")
		var total_layer: Variant = named.get(prefix + "/TotalValue")
		cards[player_index] = {"hp": String(hp_layer.text) if hp_layer != null else "",
			"total": String(total_layer.text) if total_layer != null else "",
			"total_right": float(total_layer.right_edge) if total_layer != null else NAN,
			"bonus": chip != null and bool(chip.visible), "bonus_alpha": float(chip.modulate.a) if chip != null else 0.0}
	return cards


## Counting totals keep one format (one decimal whenever any total has a half) and
## a fixed right edge, so the digits do not jump while the towers climb.
func check_steady_counter(decimal: bool) -> void:
	for player_index in [1, 2]:
		var rights := []
		for tag in ["climb_early", "climb_mid", "hush", "final"]:
			var card: Dictionary = sample_of(tag).get("cards", {}).get(player_index, {})
			var text := String(card.get("total", ""))
			if tag != "final" and text != "":
				check(text.contains(".") == decimal, "P%d counter keeps its format at %s (%s)" % [player_index, tag, text])
			rights.append(float(card.get("total_right", NAN)))
		check(not is_nan(rights[0]) and rights.all(func(value): return is_equal_approx(value, rights[0])), "P%d counter keeps its right edge %s" % [player_index, str(rights)])


## The After Effects "+0.5" chip shows on living cards and lands at the merge beat.
func check_hp_bonus() -> void:
	check(absf(ResultFinaleHud.hp_bonus_time() - 3.92) < 0.02, "bonus merge time comes from After Effects (%.3f)" % ResultFinaleHud.hp_bonus_time())
	var before: Dictionary = sample_of("hp_bonus").get("cards", {})
	var after: Dictionary = sample_of("hp_merged").get("cards", {})
	for player_index in [1, 2]:
		if not before.has(player_index) or not after.has(player_index):
			failures.append("missing card sample P%d" % player_index)
			continue
		var hp := gs.result_p1_hp if player_index == 1 else gs.result_p2_hp
		if gs.is_result_ghost(player_index):
			check(not before[player_index].bonus and after[player_index].hp == "—", "P%d ghost card has no survival bonus" % player_index)
		else:
			check(before[player_index].bonus and float(before[player_index].bonus_alpha) > 0.9 and before[player_index].hp == str(hp), "P%d chip shows beside HP %d before the merge" % [player_index, hp])
			check(after[player_index].hp == "%d.5" % hp, "P%d HP value reads %d.5 after the merge (%s)" % [player_index, hp, after[player_index].hp])


## Once a tower outgrows the baked shot, the climb is shot from the front (low,
## both players whole, P1 left / P2 right); after the towers stop a win moves in
## beside the loser and looks up at the winner, a draw stays in front.
func check_tall_framing() -> void:
	var tallest := ResultFinaleMotion.stop_height(maxi(gs.result_p1_score, gs.result_p2_score))
	if tallest < ResultFinaleCameraRules.TALL_FULL:
		return
	var area := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var winner := gs.result_winner
	for tag in ["hush", "celebrate", "orz", "final"]:
		var sample := sample_of(tag)
		var camera: Transform3D = sample.camera
		var actors: Array = sample.director.actors
		var forward := -camera.basis.z
		check(forward.y > 0.05, "%s: camera looks up at the tall tower (%.3f)" % [tag, forward.y])
		if winner == 0 or tag == "hush":
			for actor: Dictionary in actors:
				check(area.grow(4).encloses(actor.screen_bounds), "%s: P%d whole in the front two-shot" % [tag, actor.player])
			var p1: Dictionary = actors.filter(func(actor): return int(actor.player) == 1)[0]
			var p2: Dictionary = actors.filter(func(actor): return int(actor.player) == 2)[0]
			check(float(p1.head.x) < 640.0 and float(p2.head.x) > 640.0, "%s: front two-shot keeps P1 left and P2 right" % tag)
			continue
		var top: Dictionary = actors.filter(func(actor): return int(actor.player) == winner)[0]
		var low: Dictionary = actors.filter(func(actor): return int(actor.player) != winner)[0]
		check(area.grow(4).encloses(top.screen_bounds), "%s: winner whole in the side shot" % tag)
		check(area.has_point(low.head), "%s: loser's head on screen in the side shot" % tag)
		check(camera.origin.distance_to(low.head_world) < camera.origin.distance_to(top.head_world), "%s: camera stays beside the loser" % tag)
		check(camera.origin.y < float(top.head_world.y), "%s: camera below the winner" % tag)


const ResultFinaleCameraRules = preload("res://scripts/world/result_finale/result_finale_camera.gd")


## A flag in each hand, held alike until the verdict, then the winner's flag goes up.
func check_referee_flags(final: Dictionary, winner: int) -> void:
	var hush: Array = sample_of("hush").director.get("referee_flags", [])
	check(hush.size() == 2 and absf((hush[0] as Vector3).y - (hush[1] as Vector3).y) < 0.05,
		"referee holds both flags alike before the verdict (%s)" % str(hush))
	var tips: Array = final.get("referee_flags", [])
	if tips.size() != 2 or hush.size() != 2:
		check(false, "referee has two flags after the verdict")
		return
	var a := tips[0] as Vector3
	var b := tips[1] as Vector3
	var hush_y := maxf((hush[0] as Vector3).y, (hush[1] as Vector3).y)
	if winner == 0:
		check(minf(a.y, b.y) > hush_y + 0.8, "draw raises both flags")
		return
	var raised := a if a.y > b.y else b
	var lowered := b if a.y > b.y else a
	var tower_x := {}
	for actor: Dictionary in final.actors:
		tower_x[int(actor.player)] = float(actor.tower_x)
	var toward_winner := absf(raised.x - float(tower_x[winner])) < absf(raised.x - float(tower_x[3 - winner]))
	check(raised.y > lowered.y + 0.8 and toward_winner, "referee raises the flag on the P%d winner's side" % winner)


func sample_of(tag: String) -> Dictionary:
	for sample: Dictionary in samples:
		if sample.tag == tag:
			return sample
	failures.append("missing sample " + tag)
	return {"director": {"actors": [], "heights": {1: 0.0, 2: 0.0}, "crown": {}}, "hud": {"burst_frame": -1}}


func frames(count: int) -> void:
	for frame in range(count):
		await get_tree().process_frame


func check_scene_routes() -> void:
	for cycle in range(2):
		for frame in range(fps * 10):
			if not SceneTransition.is_transitioning(): break
			await get_tree().process_frame
		gs.game_state = Constants.STATE_CLEAR
		gs.result_presentation_active = true
		gs.result_ceremony_elapsed = QuizGameState.RESULT_TOTAL_DURATION
		gs.result_ceremony_phase = QuizGameState.ResultCeremonyPhase.INTERACTIVE
		await frames(3)
		var previous_world_id := world.get_instance_id()
		var previous_director_id: int = world.get("_result_ceremony_director").get_instance_id()
		world.get_node("GameplayHUD").call("_retry_game")
		for frame in range(fps * 20):
			await get_tree().process_frame
			if get_tree().current_scene != null and get_tree().current_scene.get_instance_id() != previous_world_id: break
			if not SceneTransition.is_fully_covered():
				check(gs.result_presentation_active, "retry keeps the finale until black cover")
		world = get_tree().current_scene
		check(world != null and world.scene_file_path == "res://scenes/game_world.tscn" and world.get_instance_id() != previous_world_id, "retry reloads real game scene")
		check(not is_instance_id_valid(previous_director_id) and not gs.result_presentation_active and gs.goal_reached_mask == 0, "retry removes the prior finale")
		check(gs.p1_hp == 3 and gs.p2_hp == 3 and gs.p1_alive and gs.p2_alive, "retry restores both players and full HP")
		await frames(fps * 2)
		check(not world.get("camera_controller").get("_result_camera_active"), "retry camera has no finale override")
	for frame in range(fps * 10):
		if not SceneTransition.is_transitioning(): break
		await get_tree().process_frame
	gs.game_state = Constants.STATE_CLEAR
	gs.result_presentation_active = true
	gs.result_ceremony_elapsed = QuizGameState.RESULT_TOTAL_DURATION
	gs.result_ceremony_phase = QuizGameState.ResultCeremonyPhase.INTERACTIVE
	await frames(3)
	world.get_node("GameplayHUD").call("_return_to_main_menu")
	for frame in range(fps * 15):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://ui/main_menu.tscn": break
		if not SceneTransition.is_fully_covered():
			check(gs.result_presentation_active, "menu keeps the finale until black cover")
	check(get_tree().current_scene.scene_file_path == "res://ui/main_menu.tscn" and gs.game_state == Constants.STATE_MENU, "menu callback completes actual transition")
	for frame in range(fps * 10):
		if not SceneTransition.is_transitioning(): break
		await get_tree().process_frame
	world = get_tree().current_scene


func capture(tag: String) -> void:
	captured.append(tag)
	get_viewport().get_texture().get_image().save_png(OUT + scenario + "_" + tag + ".png")
	var camera: Camera3D = get_viewport().get_camera_3d()
	var director: Node3D = world.get("_result_ceremony_director")
	var overlay := world.get_node("GameplayHUD/ResultCeremonyOverlay")
	samples.append({"tag": tag, "time": gs.result_ceremony_elapsed, "state": gs.game_state, "phase": gs.result_ceremony_phase,
		"camera": camera.global_transform if camera != null else Transform3D.IDENTITY, "fov": camera.fov if camera != null else 0.0,
		"director": director.get_debug_snapshot(), "hud": overlay.get_debug_snapshot(), "cards": card_texts(overlay),
		"stand": world.get("_goal_stand").get_debug_snapshot() if is_instance_valid(world.get("_goal_stand")) else {}})
