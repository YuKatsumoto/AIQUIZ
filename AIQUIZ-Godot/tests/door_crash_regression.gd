extends Node

## Run in a rendered editor game (not headless):
## var probe = load("res://tests/door_crash_regression.gd").new()
## get_tree().root.add_child(probe)
## probe.run.call_deferred()
## Uses offline questions and runtime-only quality settings.
## With 3HP, a wrong door only costs 1 HP: wrong-door cases keep crossing wrong
## doors until that player's HP reaches 0, and only the last one is fatal.
var results: Array[Dictionary] = []
var finished := false
var failed := false
const OUTPUT := "res://artifacts/door_crash/"
## passes = 0 means "cross wrong doors until the wrong player's HP is gone".
const CASES: Array = [[2, 2, 0], [2, 1, 0], [2, 0, 9], [1, 0, 9], [1, 1, 0]]
var _hp_events: Array = []


func run() -> void:
	name = "DoorCrashRegression"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var previous_quality := GameManager.graphics_quality
	var previous_source: String = QuizManager.provider.llm_mode
	GameManager.graphics_quality = GraphicsQuality.HIGH
	QuizManager.provider.llm_mode = "OFFLINE"
	var gs := QuizManager.game_state
	gs.health_changed.connect(_on_health_changed)
	for spec: Array in CASES:
		if not await _run_case(spec[0], spec[1], spec[2]):
			failed = true
			break
	gs.health_changed.disconnect(_on_health_changed)
	GameManager.graphics_quality = previous_quality
	QuizManager.provider.llm_mode = previous_source
	finished = true
	var report := {"passed": not failed, "cases": results, "renderer": RenderingServer.get_current_rendering_method()}
	var file := FileAccess.open(OUTPUT + "after.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("DOOR_CRASH_REGRESSION " + JSON.stringify(report))


func _on_health_changed(player_index: int, previous_hp: int, hp: int) -> void:
	_hp_events.append([player_index, previous_hp, hp])


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
	if not gs.uses_hp():
		return _fail("HP system inactive")
	for player_index in range(1, players + 1):
		if gs.get_player_hp(player_index) != gs.MAX_HP:
			return _fail("P%d did not start at %d HP" % [player_index, gs.MAX_HP])
	var crossings := passes if wrong_player == 0 else gs.get_player_hp(wrong_player)
	var world := get_tree().current_scene
	var wipe: Node = world.get_node("DeathWipeLayer/DeathWipe")
	var saw_wipe := false
	var choices_seen: Array[int] = []
	var hp_trace: Array = []
	for step in range(crossings):
		var index := gs.current_wall_index
		var answer := gs.current_quiz.a
		var choices := gs.num_choices
		if choices not in choices_seen:
			choices_seen.append(choices)
		var hp_before: Array[int] = [0, gs.p1_hp, gs.p2_hp]
		var fatal: bool = wrong_player != 0 and hp_before[wrong_player] == 1
		var xs: Array = Array(gs.tuning.door4_xs) if choices == 4 else [gs.tuning.left_door_x, gs.tuning.right_door_x]
		var wrong := (answer + 1) % choices
		gs.player_x = xs[wrong if wrong_player == 1 else answer] + (0.38 if players == 2 and wrong_player == 0 else 0.0)
		gs.player2_x = xs[wrong if wrong_player == 2 else answer] - (0.38 if wrong_player == 0 else 0.0)
		gs.world_scroll_z = gs.wall_z - 2.0
		gs.player_z = gs.wall_z - 2.0
		gs.player2_z = gs.wall_z - 2.0
		_hp_events.clear()
		print("DOOR_CROSSING players=%d wrong=%d index=%d choices=%d hp=%s fatal=%s" % [players, wrong_player, index, choices, str(hp_before.slice(1, players + 1)), fatal])
		deadline = Time.get_ticks_msec() + 5000
		while gs.current_wall_index == index and gs.game_state == Constants.STATE_PLAYING and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		for player_index in range(1, players + 1):
			var expected: int = hp_before[player_index] - (1 if player_index == wrong_player else 0)
			if gs.get_player_hp(player_index) != expected:
				return _fail("P%d HP %d after crossing %d, expected %d (events %s)" % [player_index, gs.get_player_hp(player_index), step, expected, str(_hp_events)])
		if wrong_player != 0 and [wrong_player, hp_before[wrong_player], hp_before[wrong_player] - 1] not in _hp_events:
			return _fail("health_changed not emitted for wrong door: %s" % str(_hp_events))
		hp_trace.append([gs.p1_hp, gs.p2_hp].slice(0, players))
		if wrong_player == 0:
			if gs.current_wall_index != index + 1 or not gs.p1_alive or (players == 2 and not gs.p2_alive):
				return _fail("correct door did not advance with players alive")
		elif not fatal:
			if gs.current_wall_index != index + 1 or gs.game_state != Constants.STATE_PLAYING or not gs.p1_alive or (players == 2 and not gs.p2_alive):
				return _fail("non-fatal wrong door did not advance with players alive")
		elif players == 1:
			if gs.p1_alive or gs.game_state != Constants.STATE_GAME_OVER:
				return _fail("fatal solo wrong door did not reach game over")
		else:
			if gs.current_wall_index != index + 1 or gs.p1_alive != (wrong_player != 1) or gs.p2_alive != (wrong_player != 2):
				return _fail("fatal mixed door outcome incorrect")
		# Allow destruction, retirement, and death camera activation to render.
		# A non-fatal hit only needs the 0.6 s damage flash to finish.
		deadline = Time.get_ticks_msec() + (6000 if fatal else (700 if wrong_player != 0 else 450))
		while Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			if wipe.visible and not fatal:
				return _fail("death wipe shown while every player still had HP")
			if wipe.visible and not saw_wipe:
				saw_wipe = true
				await _capture("p%d_wrong%d_wipe" % [players, wrong_player])
			# Keep the survivor lined up for any following wall during the death sequence.
			# Only after a fatal hit: stacking two living players on one X leaves the
			# 2P push resolver in contact, and the next teleport would swap their order.
			if fatal and gs.current_quiz != null and gs.game_state == Constants.STATE_PLAYING:
				var next_x: float = gs.tuning.door4_xs[gs.current_quiz.a] if gs.num_choices == 4 else (gs.tuning.left_door_x if gs.current_quiz.a == 0 else gs.tuning.right_door_x)
				if gs.p1_alive:
					gs.player_x = next_x
				if gs.p2_alive:
					gs.player2_x = next_x
		if step == crossings - 1:
			await _capture("p%d_wrong%d_after" % [players, wrong_player])
	if players == 2 and wrong_player != 0 and not saw_wipe:
		return _fail("death wipe never rendered")
	if saw_wipe:
		# Reapply every quality tier to the existing target and render it again.
		for quality: String in GraphicsQuality.VALID_QUALITIES:
			GraphicsQuality.apply_character_preview(wipe.sub_viewport, quality)
			if wipe.sub_viewport.msaa_2d != Viewport.MSAA_DISABLED:
				return _fail("2D MSAA re-enabled on death camera (%s)" % quality)
			await get_tree().process_frame
		GraphicsQuality.apply_character_preview(wipe.sub_viewport, GameManager.graphics_quality)
	var result := {"players": players, "wrong_player": wrong_player, "passes": crossings, "hp": hp_trace, "choices": choices_seen, "wipe_rendered": saw_wipe, "state": gs.game_state, "wall": gs.current_wall_index, "passed": true}
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
