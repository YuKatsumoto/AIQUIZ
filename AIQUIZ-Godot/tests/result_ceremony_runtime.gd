extends Node

## Score Tower Finale in the real GameWorld: ten-question finish -> goal walk ->
## towers climb with the real totals -> verdict, confetti, crown / sinking tower,
## rain cloud -> controls. Captures beats and optional frames for review.
## Args: case=p1|p2|draw fps=30|60|120 quality=low|balanced|high record hats
##       sizes routes emote=<id> all_emotes audible out=<folder>

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
var record_frames := false
var test_hats := false
var verify_all_emotes := false
var selected_emote := 0
var quality := "balanced"
var ceremony_start_frame := -1

const BEATS := [[0.2, "assemble"], [1.2, "walk"], [2.3, "hop"], [2.9, "correct"], [3.6, "formula"],
	[4.6, "climb_early"], [5.5, "climb_mid"], [6.5, "hush"], [6.93, "verdict"], [7.1, "burst"],
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
		if arg == "audible":
			# Recording-only override; never write the user's audio preferences.
			AudioManager.set_sfx_volume(0.8, false)
			AudioManager.set_bgm_volume(0.10, false)
	GameManager.graphics_quality = quality
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + scenario + "_frames"))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
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
	gs.current_index = 10
	gs.current_wall_index = 10
	gs.load_current_quiz()
	check(gs.game_state == Constants.STATE_GOAL_RACE, "actual ten-question completion routes to goal")
	gs.world_scroll_z = gs.goal_z - 24.0
	gs.player_z = gs.goal_z - 10.0
	gs.player2_z = gs.goal_z - 10.0
	await frames(maxi(3, fps / 4))
	var marks_z := gs.get_local_result_goal_z() + QuizGameState.RESULT_WALK_FINISH_OFFSET - gs.world_scroll_z
	var waiter := world.get_node_or_null("GoalLine/GoalWaitingReferee") as Node3D
	check(waiter != null and waiter.visible, "flag referee waits beyond the goal before the finish")
	if waiter != null:
		var rig := waiter.find_child("RIG_Referee", true, false) as Node3D
		check(rig != null and absf(rig.global_position.z - (marks_z + 1.0)) < 0.05, "waiting referee stands 1 m behind the finishing marks")
		check(rig != null and absf(rig.global_position.y + 1.2) < 0.3, "waiting referee stands on the conveyor")
		await capture("goal_approach")
	gs.player_x = 2.2
	gs.player2_x = -2.2
	gs.player_z = gs.goal_z - (1.6 if scenario == "p1" else 0.3)
	gs.player2_z = gs.goal_z - (0.3 if scenario == "p1" else 1.6)
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.p1_alive = true
	gs.p2_alive = true
	# p1: 8x3=24 vs 9x1=9, p2: 9x1=9 vs 7x3=21, draw: 6x2=12 vs 4x3=12
	gs.score = 6 if scenario == "draw" else (8 if scenario == "p1" else 9)
	gs.player2_score = 4 if scenario == "draw" else (9 if scenario == "p1" else 7)
	gs.p1_hp = 2 if scenario == "draw" else (3 if scenario == "p1" else 1)
	gs.p2_hp = 3 if scenario != "p1" else 1
	var expected_hp := [gs.p1_hp, gs.p2_hp]
	var expected_winner := 0 if scenario == "draw" else (1 if scenario == "p1" else 2)
	gs.result_ceremony_phase_changed.connect(func(phase: int): phases.append({"phase": phase, "time": gs.result_ceremony_elapsed}))
	var overlay: Control = world.get_node("GameplayHUD/ResultCeremonyOverlay")
	var director: Node3D = world.get("_result_ceremony_director")
	var ceremony_frames := 0
	var interactive_frames := 0
	for frame in range(fps * 24):
		await RenderingServer.frame_post_draw
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
	check(gs.result_winner == expected_winner, "winner based on goal products")
	check(gs.game_state == Constants.STATE_CLEAR and is_equal_approx(gs.result_ceremony_elapsed, QuizGameState.RESULT_TOTAL_DURATION), "interactive after the authored performance")
	check([gs.p1_hp, gs.p2_hp] == expected_hp and gs.p1_alive and gs.p2_alive, "finale preserves authoritative HP and life")
	check(hud.motion_loaded and hud.actions_visible and hud.buttons.size() == 3, "After Effects HUD and three controls visible")
	check(hud.totals == [str(gs.result_p1_score), str(gs.result_p2_score)], "cards show the frozen products")
	check(hud.verdict == ("DRAW!" if expected_winner == 0 else "WIN!"), "verdict word matches outcome")
	check(final.built and final.visible and final.cast_visible and final.winner == expected_winner, "finale stage built in the game world")
	check(final.referee_animation == ("FinaleDraw" if expected_winner == 0 else "FinaleWin"), "referee plays the outcome's animation")
	check(world.get_node("StageEnvironment/Floor").visible and world.get_node("StageEnvironment/Grandstands").visible, "real conveyor and stadium stay visible")
	check(absf(float(final.stage_origin.y) + 1.2) < 0.01 and absf(float(final.stage_origin.z) - marks_z) < 0.05, "stage anchored at the finishing marks")
	check(bool(final.mirrored) == (expected_winner == 2), "only a P2 win mirrors the stage")
	var heights: Dictionary = sample_of("hush").director.heights
	var h: Dictionary = ResultFinaleMotion.heights()
	var totals := [gs.result_p1_score, gs.result_p2_score]
	var max_total := maxi(totals[0], totals[1])
	for player_index in [1, 2]:
		var expected := ResultFinaleMotion.stop_height(totals[player_index - 1], max_total)
		check(absf(float(heights[player_index]) - expected) < 0.08, "P%d tower height matches its total at the hush" % player_index)
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
	await check_goal_stand(expected_winner, marks_z)
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
		var cloud: Dictionary = sample_of("orz").director.cloud
		check(cloud.visible and float(cloud.over_loser) < 0.7, "rain cloud hovers over the loser")
		check(events.filter(func(event): return event.kind == "rain").size() == 1, "loser gets rain once")
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
		check(final.crown.is_empty() and final.cloud.is_empty(), "draw has no crown or cloud")
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
	check(not AudioManager.result_victory_player.playing and not AudioManager.result_rain_player.playing, "cleanup stops finale audio")
	check(not director.get_debug_snapshot().built and pc.visible, "reset frees the finale stage and restores players")
	await capture("restored")
	if verify_routes:
		await check_scene_routes()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "case": scenario, "fps": fps,
		"quality": quality, "hats": test_hats, "renderer": RenderingServer.get_current_rendering_method(),
		"phases": phases, "samples": samples, "movie_frames": movie_frame, "ceremony_start_frame": ceremony_start_frame}
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


## Finish grandstand beyond the conveyor: placement, cast, moods, eggs and boards.
func check_goal_stand(expected_winner: int, marks_z: float) -> void:
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
	check(String(sample_of("goal_approach").stand.get("mood", "")) == "hype", "crowd is hyped while the players race to the goal")
	check(String(sample_of("climb_mid").stand.get("mood", "")) == "nervous", "crowd holds its breath while the towers climb")
	var end: Dictionary = sample_of("loop_living").stand
	check(String(end.get("mood", "")) == "verdict", "crowd reacts to the verdict")
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


func sample_of(tag: String) -> Dictionary:
	for sample: Dictionary in samples:
		if sample.tag == tag:
			return sample
	failures.append("missing sample " + tag)
	return {"director": {"actors": [], "heights": {1: 0.0, 2: 0.0}, "crown": {}, "cloud": {}}, "hud": {"burst_frame": -1}}


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
	check(not AudioManager.result_victory_player.playing and not AudioManager.result_rain_player.playing, "scene changes leave no finale audio")
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
		"director": director.get_debug_snapshot(), "hud": overlay.get_debug_snapshot(),
		"stand": world.get("_goal_stand").get_debug_snapshot() if is_instance_valid(world.get("_goal_stand")) else {}})
