extends Node

## Run in a rendered editor game (not headless):
## var probe = load("res://tests/door_crash_regression.gd").new()
## get_tree().root.add_child(probe)
## probe.run.call_deferred()
## Uses offline questions and runtime-only quality settings.
var results: Array[Dictionary] = []
var finished := false
var failed := false
const OUTPUT := "res://artifacts/door_crash/"


func run() -> void:
	name = "DoorCrashRegression"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var previous_quality := GameManager.graphics_quality
	var previous_source: String = QuizManager.provider.llm_mode
	GameManager.graphics_quality = GraphicsQuality.HIGH
	QuizManager.provider.llm_mode = "OFFLINE"
	for spec: Array in [[2, 2, 1], [2, 1, 1], [2, 0, 9], [1, 0, 9], [1, 1, 1]]:
		if not await _run_case(spec[0], spec[1], spec[2]):
			failed = true
			break
	GameManager.graphics_quality = previous_quality
	QuizManager.provider.llm_mode = previous_source
	finished = true
	var report := {"passed": not failed, "cases": results, "renderer": RenderingServer.get_current_rendering_method()}
	var file := FileAccess.open(OUTPUT + "after.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("DOOR_CRASH_REGRESSION " + JSON.stringify(report))


func _run_case(players: int, wrong_player: int, passes: int) -> bool:
	var gs := QuizManager.game_state
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.start_game()
	GameManager.start_game()
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.name == "GameWorld" and not SceneTransition.is_transitioning() and not scene.is_start_presentation_locked():
			break
	if Time.get_ticks_msec() >= deadline:
		return _fail("start presentation timed out")
	gs.trigger_start()
	deadline = Time.get_ticks_msec() + 15000
	while gs.game_state != Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if gs.game_state != Constants.STATE_PLAYING:
		return _fail("countdown timed out")
	var world := get_tree().current_scene
	var wipe: Node = world.get_node("DeathWipeLayer/DeathWipe")
	var saw_wipe := false
	var choices_seen: Array[int] = []
	for step in range(passes):
		var index := gs.current_wall_index
		var answer := gs.current_quiz.a
		var choices := gs.num_choices
		if choices not in choices_seen:
			choices_seen.append(choices)
		var xs: Array = Array(gs.tuning.door4_xs) if choices == 4 else [gs.tuning.left_door_x, gs.tuning.right_door_x]
		var wrong := (answer + 1) % choices
		gs.player_x = xs[wrong if wrong_player == 1 else answer] + (0.38 if players == 2 and wrong_player == 0 else 0.0)
		gs.player2_x = xs[wrong if wrong_player == 2 else answer] - (0.38 if wrong_player == 0 else 0.0)
		gs.world_scroll_z = gs.wall_z - 2.0
		gs.player_z = gs.wall_z - 2.0
		gs.player2_z = gs.wall_z - 2.0
		print("DOOR_CROSSING players=%d wrong=%d index=%d choices=%d" % [players, wrong_player, index, choices])
		deadline = Time.get_ticks_msec() + 5000
		while gs.current_wall_index == index and gs.game_state == Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if wrong_player == 0:
			if gs.current_wall_index != index + 1 or not gs.p1_alive or (players == 2 and not gs.p2_alive):
				return _fail("correct door did not advance with players alive")
		elif players == 1:
			if gs.p1_alive or gs.game_state != Constants.STATE_GAME_OVER:
				return _fail("wrong solo door did not reach game over")
		else:
			if gs.current_wall_index != index + 1 or gs.p1_alive != (wrong_player != 1) or gs.p2_alive != (wrong_player != 2):
				return _fail("mixed door outcome incorrect")
		# Allow destruction, retirement, and death camera activation to render.
		deadline = Time.get_ticks_msec() + (6000 if wrong_player != 0 else 450)
		while Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			if wipe.visible and not saw_wipe:
				saw_wipe = true
				await _capture("p%d_wrong%d_wipe" % [players, wrong_player])
			# Keep the survivor lined up for any following wall during the death sequence.
			if wrong_player != 0 and gs.current_quiz != null and gs.game_state == Constants.STATE_PLAYING:
				var next_x: float = gs.tuning.door4_xs[gs.current_quiz.a] if gs.num_choices == 4 else (gs.tuning.left_door_x if gs.current_quiz.a == 0 else gs.tuning.right_door_x)
				if gs.p1_alive:
					gs.player_x = next_x
				if gs.p2_alive:
					gs.player2_x = next_x
		if step == passes - 1:
			await _capture("p%d_wrong%d_after" % [players, wrong_player])
	if players == 2 and wrong_player != 0 and not saw_wipe:
		return _fail("death wipe never rendered")
	if saw_wipe:
		# Reapply every quality tier to the existing target and render it again.
		for quality: String in [GraphicsQuality.LOW, GraphicsQuality.BALANCED, GraphicsQuality.HIGH]:
			GraphicsQuality.apply_character_preview(wipe.sub_viewport, quality)
			if wipe.sub_viewport.msaa_2d != Viewport.MSAA_DISABLED:
				return _fail("2D MSAA re-enabled on death camera")
			await get_tree().process_frame
	var result := {"players": players, "wrong_player": wrong_player, "passes": passes, "choices": choices_seen, "wipe_rendered": saw_wipe, "state": gs.game_state, "wall": gs.current_wall_index, "passed": true}
	results.append(result)
	print("DOOR_CASE_PASS " + JSON.stringify(result))
	return true


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + label + ".png")


func _fail(reason: String) -> bool:
	results.append({"passed": false, "reason": reason})
	push_error("DOOR_CASE_FAIL " + reason)
	return false
