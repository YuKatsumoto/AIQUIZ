extends Node

## Inject into the rendered main menu. Measures wall-clock frame gaps through
## the real Start handler, stopping measurements before the covered scene load.
var finished := false
var report: Dictionary = {}

func run(label: String, players: int) -> void:
	var menu := get_tree().current_scene
	var gs := QuizManager.game_state
	QuizManager.provider.llm_mode = "OFFLINE"
	gs.llm_mode = "OFFLINE"
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	var preview: Node = menu.get("_menu_wall_preview")
	preview.sync_menu_player_count(players)
	await get_tree().create_timer(1.0).timeout
	var prepared: HelicopterArrivalDirector = preview.get("_menu_start_departure")
	var preparation: Dictionary = {}
	if is_instance_valid(prepared):
		var silent := true
		for info: Dictionary in prepared._helicopters:
			silent = silent and not (info["audio"] as AudioStreamPlayer3D).playing
		preparation = {"ready": prepared._menu_departure_prepared, "hidden": not prepared.visible, "paused": prepared.process_mode == Node.PROCESS_MODE_DISABLED, "silent": silent, "count": prepared._helicopters.size(), "active": preview.is_game_start_departure_active()}
	var output := "res://artifacts/menu_start/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var frames: Array[Dictionary] = []
	var captures: Dictionary = {}
	var grips: Dictionary = {}
	var started := Time.get_ticks_usec()
	var previous := started
	menu._on_start_pressed()
	var handler_ms := (Time.get_ticks_usec() - started) / 1000.0
	var saw_departure := false
	var count_seen := 0
	var end_usec := started + 15000000
	while is_instance_valid(menu) and get_tree().current_scene == menu and Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var director: HelicopterArrivalDirector = preview.get("_menu_start_departure")
		var phase := director._phase if is_instance_valid(director) else "ui"
		frames.append({"t_ms": (now - started) / 1000.0, "gap_ms": (now - previous) / 1000.0, "phase": phase})
		previous = now
		if is_instance_valid(director) and phase == "departure_pickup":
			saw_departure = true
			count_seen = director._helicopters.size()
			for info: Dictionary in director._helicopters:
				if bool(info.get("captured", false)):
					grips[int(info["player_index"])] = true
			var shot := ""
			if director._phase_elapsed > 0.8 and not captures.has("arrival"):
				shot = "arrival"
			elif grips.size() == players and not captures.has("grip"):
				shot = "grip"
			if not shot.is_empty():
				await RenderingServer.frame_post_draw
				var path := output + label + "_p%d_%s.png" % [players, shot]
				get_viewport().get_texture().get_image().save_png(path)
				captures[shot] = path
				# Exclude deliberate GPU readback/PNG encoding from frame measurements.
				previous = Time.get_ticks_usec()
		if SceneTransition.is_transitioning():
			break
	var max_gap := 0.0
	var early_gap := 0.0
	for frame: Dictionary in frames:
		max_gap = maxf(max_gap, frame["gap_ms"])
		if float(frame["t_ms"]) < 2000.0:
			early_gap = maxf(early_gap, frame["gap_ms"])
	while get_tree().current_scene == menu and Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame
	while get_tree().current_scene == null and Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame
	report = {"label": label, "players": players, "renderer": RenderingServer.get_current_rendering_method(), "handler_ms": handler_ms, "max_gap_ms": max_gap, "early_gap_ms": early_gap, "helicopters": count_seen, "grips": grips.size(), "saw_departure": saw_departure, "reached_game": get_tree().current_scene.scene_file_path == "res://scenes/game_world.tscn", "captures": captures, "frames": frames}
	report["preparation"] = preparation
	report["passed"] = saw_departure and count_seen == players and grips.size() == players and report["reached_game"]
	if label.begins_with("after"):
		report["passed"] = report["passed"] and early_gap < 50.0 and preparation.get("ready", false) and preparation.get("hidden", false) and preparation.get("paused", false) and preparation.get("silent", false) and not preparation.get("active", true)
	var file := FileAccess.open(output + label + "_p%d.json" % players, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	finished = true
	var summary := report.duplicate()
	summary.erase("frames")
	print("MENU_START_FRAME_REGRESSION " + JSON.stringify(summary))
