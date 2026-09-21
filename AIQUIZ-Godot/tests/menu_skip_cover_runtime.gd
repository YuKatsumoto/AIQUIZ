extends Node

## Rendered regression: the real Space input must not retire the actors before
## the wipe covers them, and the scene/seat handoff must still complete once.
var failures: Array[String] = []
var frames: Array[Dictionary] = []
var shots: Dictionary = {}
var completions: Array[Dictionary] = []
var scenario := "early"
var players := 2
var output := ""

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok and not failures.has(label):
		failures.append(label)

func picture(label: String) -> void:
	if shots.has(label): return
	var path := output + "/" + label + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	shots[label] = path

func on_completed(success: bool) -> void:
	completions.append({"success": success, "cover": SceneTransition.get_cover_factor()})
	check(SceneTransition.is_fully_covered(), "departure completes only behind full cover")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="): scenario = arg.get_slice("=", 1)
		if arg.begins_with("--players="): players = arg.get_slice("=", 1).to_int()
	output = "res://artifacts/menu_skip_cover/" + scenario + "_p%d" % players
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1280, 720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.llm_mode = "OFFLINE"
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.menu_step = Constants.MENU_STEP_CONFIG
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene == null: await get_tree().process_frame
	var menu := get_tree().current_scene
	var preview: Node = menu.get("_menu_wall_preview")
	preview.sync_menu_player_count(players)
	await get_tree().create_timer(1.5).timeout
	while menu.config_conveyor.is_moving(): await get_tree().process_frame
	var director: HelicopterArrivalDirector = preview._menu_start_departure
	director.presentation_finished.connect(on_completed)
	menu.call("_on_start_pressed")
	check(menu._menu_exit_in_progress, "real Start accepted")
	var deadline := Time.get_ticks_msec() + 25000
	var skipped := false
	var uncovered_frames := 0
	var first_clock := -1.0
	var last_clock := -1.0
	var reached_game := false
	var seat_arriving := false
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var scene := get_tree().current_scene
		if scene == null: continue
		if scene != menu:
			reached_game = scene.scene_file_path == "res://scenes/game_world.tscn"
			if reached_game and players == 2:
				seat_arriving = scene._saw_controller.operator_seat.seat_transfer.is_arriving()
			break
		var seat: SeatLaunchPresentation = preview._preview_saw.operator_seat.seat_transfer
		var ready_to_skip := bool(menu._heli_departure_skippable)
		if scenario == "buckle": ready_to_skip = ready_to_skip and seat.phase == seat.Phase.BUCKLING and seat.elapsed > 0.8
		if scenario == "flight": ready_to_skip = ready_to_skip and director._menu_boost_started and director._menu_launch_elapsed > 0.2
		if scenario != "normal" and ready_to_skip and not skipped:
			picture("before_skip")
			var key := InputEventKey.new()
			key.keycode = KEY_SPACE
			key.physical_keycode = KEY_SPACE
			key.pressed = true
			Input.parse_input_event(key)
			Input.flush_buffered_events()
			# Repeated input must not complete the departure or restart the wipe.
			Input.parse_input_event(key.duplicate())
			var release := key.duplicate() as InputEventKey
			release.pressed = false
			Input.parse_input_event(release)
			Input.flush_buffered_events()
			skipped = true
			first_clock = director._total_elapsed
			check(menu._heli_departure_skip_requested, "Space reaches menu skip handler")
			check(preview.is_game_start_departure_active(), "Space does not retire departure immediately")
			check(preview._preview_player.visible, "Space does not hide players immediately")
		if skipped and not SceneTransition.is_fully_covered():
			uncovered_frames += 1
			last_clock = director._total_elapsed
			check(preview.is_game_start_departure_active(), "departure stays active throughout partial cover")
			check(preview._preview_player.visible, "player root stays visible throughout partial cover")
			if scenario in ["early", "buckle"] and players == 2:
				check(seat.flight_root.visible, "chair stays visible throughout partial cover")
			var cover := SceneTransition.get_cover_factor()
			frames.append({"cover": cover, "clock": last_clock, "player_visible": preview._preview_player.visible, "seat_phase": seat.phase})
			if cover >= 0.15: picture("cover_15")
			if cover >= 0.5: picture("cover_50")
			if cover >= 0.9: picture("cover_90")
	check(reached_game, "game scene reached")
	if scenario != "normal":
		check(completions.size() == 1 and bool(completions[0].success), "departure completes successfully once")
		check(skipped, "requested skip phase reached")
		check(uncovered_frames > 5, "multiple partial-cover frames sampled")
		check(last_clock - first_clock > 0.5, "animation advances while screen is being covered")
	if players == 2: check(seat_arriving, "chair arrival handoff retained")
	var report := {"passed": failures.is_empty(), "scenario": scenario, "players": players, "failures": failures, "completions": completions, "uncovered_frames": uncovered_frames, "animation_advanced": last_clock - first_clock, "reached_game": reached_game, "seat_arriving": seat_arriving, "frames": frames, "shots": shots}
	FileAccess.open(output + "/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MENU_SKIP_COVER ", JSON.stringify({"passed": failures.is_empty(), "scenario": scenario, "players": players, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
