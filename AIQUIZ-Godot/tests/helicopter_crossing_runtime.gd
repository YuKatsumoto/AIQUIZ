extends Node

## Drives the real Start route and observes the rendered menu and game world.
## Example: --script res://tests/helicopter_crossing_bootstrap.gd -- --players=2 --fps=60
var players := 1
var fps := 60
var label := ""
var capture := false
var quit_when_done := true
var finished := false
var report: Dictionary = {}
var failures: Array[String] = []
var checks: Dictionary = {}
var samples: Array = []
var metrics: Dictionary = {}
var pictures: Array[Dictionary] = []
var next_capture := 0.0
var out := "res://artifacts/helicopter_crossing/"
var last_sequence := ""
var pair_min_distance := INF
var pair_crossed := false
var previous_screen_order := 0.0
var capture_interval := 0.10
var early_gap_ms := 0.0
var frame_gaps: Array[Dictionary] = []
var mode := ""
var extras := false

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="): players = arg.get_slice("=", 1).to_int()
		if arg.begins_with("--fps="): fps = arg.get_slice("=", 1).to_int()
		if arg.begins_with("--label="): label = arg.get_slice("=", 1)
		if arg == "--capture": capture = true
		if arg == "--extras": extras = true
		if arg.begins_with("--capture-fps="): capture_interval = 1.0 / arg.get_slice("=", 1).to_float()
		if arg.begins_with("--mode="): mode = arg.get_slice("=", 1)
	if label.is_empty(): label = "p%d_%dfps" % [players, fps]
	Engine.max_fps = fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out + label))
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.llm_mode = "OFFLINE"
	gs.num_players = players
	gs.mode = Constants.MODE_TEN if mode.is_empty() else mode
	gs.menu_step = Constants.MENU_STEP_CONFIG
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://ui/main_menu.tscn":
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://ui/main_menu.tscn":
			await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.call("_update_ui")
	var preview: Node = menu.get("_menu_wall_preview")
	preview.sync_menu_player_count(players)
	await get_tree().create_timer(1.5).timeout
	var prepared: HelicopterArrivalDirector = preview.get("_menu_start_departure")
	var prepared_ok := is_instance_valid(prepared) and prepared._menu_departure_prepared and not prepared.visible and prepared.process_mode == Node.PROCESS_MODE_DISABLED
	check(prepared_ok, "departure is prebuilt, hidden and paused")
	if prepared_ok:
		var silent := true
		for info: Dictionary in prepared._helicopters:
			silent = silent and not (info["audio"] as AudioStreamPlayer3D).playing
		check(silent and not preview.is_game_start_departure_active(), "prebuilt departure is silent and inactive")
	var started := Time.get_ticks_usec()
	var previous_wall := started
	menu.call("_on_start_pressed")
	var deadline := Time.get_ticks_msec() + 40000
	var saw_wipe := false
	var saw_world := false
	var arrival_completed := false
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if now - started < 2000000:
			var gap := (now - previous_wall) / 1000.0
			early_gap_ms = maxf(early_gap_ms, gap)
			frame_gaps.append({"time_ms": (now - started) / 1000.0, "gap_ms": gap, "phase": prepared._phase})
		previous_wall = now
		var scene := get_tree().current_scene
		if scene == null: continue
		var director: HelicopterArrivalDirector
		var sequence := ""
		if scene == menu:
			director = preview.get("_menu_start_departure")
			sequence = "pickup"
			if SceneTransition.is_transitioning():
				saw_wipe = true
				check(director._all_menu_players_captured(), "wipe follows all grips")
		else:
			saw_world = scene.scene_file_path == "res://scenes/game_world.tscn"
			director = scene.get_node_or_null("HelicopterArrivalDirector") as HelicopterArrivalDirector
			sequence = "dropoff"
		if sequence != last_sequence:
			next_capture = 0.0
			last_sequence = sequence
		if is_instance_valid(director) and director._phase == "complete" and sequence == "dropoff":
			check(arrival_completed, "unlocked only after landing, before offscreen cleanup")
			break
		if is_instance_valid(director) and director._phase in ["arrival", "departure_pickup"]:
			sample_director(director, sequence)
			if capture and director._phase_elapsed >= next_capture:
				var picture := get_viewport().get_texture().get_image()
				picture.resize(960, 540)
				pictures.append({"image": picture, "sequence": sequence, "time": director._phase_elapsed})
				next_capture += capture_interval
				previous_wall = Time.get_ticks_usec()
			if sequence == "dropoff" and not director.is_start_locked():
				arrival_completed = true

	check(saw_world and saw_wipe, "actual Start route reaches the world through its wipe")
	check(arrival_completed, "actual touchdown, recovery and start unlock complete")
	check(early_gap_ms < maxf(50.0, 1000.0 / fps * 1.8), "Start frame gap remains bounded: %.2f ms" % early_gap_ms)
	for n in range(1, players + 1):
		for sequence in ["pickup", "dropoff"]:
			var key := "%s_%d" % [sequence, n]
			check(metrics.has(key), "%s observed" % key)
			if not metrics.has(key): continue
			var m: Dictionary = metrics[key]
			if sequence == "dropoff": check(float(m["max_stop_seconds"]) < 0.1, "%s never stops in view" % key)
			check(float(m["max_hand_error"]) <= 0.10, "%s attached hand error <= 10 cm (%.4f)" % [key, m["max_hand_error"]])
			check(float(m["max_boundary_excess"]) < 0.08, "%s no position reset at phase boundary (%.4f)" % [key, m["max_boundary_excess"]])
			if sequence == "pickup":
				check(m.has("captured_at") and m.has("boost_at"), "%s capture and original charge/boost" % key)
				if m.has("captured_at") and m.has("boost_at"):
					check(float(m["boost_at"]) - float(m["captured_at"]) >= 0.75, "%s restored anticipation after grip" % key)
			else:
				check(bool(m.get("landed", false)), "%s landed" % key)
				check(float(m.get("landing_error", INF)) < 0.15, "%s returns to its own starting ground position" % key)
				check(m.has("entered_frame_at") and m.has("lowering_started_at"), "%s entry and lowering observed" % key)
				if m.has("entered_frame_at") and m.has("lowering_started_at"):
					check(absf(float(m["lowering_started_at"]) - float(m["entered_frame_at"])) <= 1.0 / fps + 0.005, "%s lowers on screen entry" % key)
				check(float(m.get("min_inward_speed", -INF)) > 0.1, "%s keeps travelling forward without reversal" % key)
				check(bool(m.get("exited_frame", false)), "%s disappears outside frame" % key)
	if players == 2:
		check(pair_crossed, "helicopter screen paths cross after passenger release")
		check(pair_min_distance >= 10.0, "crossing rotor clearance: %.2f m between aircraft" % pair_min_distance)

	if extras and arrival_completed:
		await check_retry_and_skip()
	var screenshot_paths: Array = []
	for i in range(pictures.size()):
		var shot: Dictionary = pictures[i]
		var path := out + label + "/%04d_%s.png" % [i, shot["sequence"]]
		(shot["image"] as Image).save_png(path)
		screenshot_paths.append({"path": path, "sequence": shot["sequence"], "time": shot["time"]})
	pictures.clear()
	report = {"passed": failures.is_empty(), "players": players, "fps": fps, "label": label, "renderer": RenderingServer.get_current_rendering_method(), "early_gap_ms": early_gap_ms, "frame_gaps": frame_gaps, "failures": failures, "checks": checks, "extras": extras, "metrics": metrics, "captures": screenshot_paths, "samples": samples, "pair_min_distance": pair_min_distance if players == 2 else 0.0, "pair_crossed": pair_crossed}
	FileAccess.open(out + label + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	var compact := report.duplicate()
	compact.erase("samples")
	compact.erase("captures")
	compact.erase("frame_gaps")
	print("HELICOPTER_CROSSING ", JSON.stringify(compact))
	finished = true
	if quit_when_done: get_tree().quit.call_deferred(0 if failures.is_empty() else 1)

func sample_director(director: HelicopterArrivalDirector, sequence: String) -> void:
	for info: Dictionary in director._helicopters:
		var n := int(info["player_index"])
		var key := "%s_%d" % [sequence, n]
		var holder := info["holder"] as Node3D
		var phase := str(info.get("gp_phase", "approach")) if sequence == "dropoff" else ("boost" if director._menu_boost_started else ("grabbing" if info.get("pickup_started", false) else "approach"))
		var t := director._phase_elapsed
		if not metrics.has(key):
			metrics[key] = {"last_t": t, "last_position": holder.global_position, "last_speed": 0.0, "last_phase": phase, "stop_seconds": 0.0, "max_stop_seconds": 0.0, "min_speed": 999.0, "max_hand_error": 0.0, "max_boundary_excess": 0.0, "landed": false}
		var m: Dictionary = metrics[key]
		var dt := t - float(m["last_t"])
		var speed := 0.0
		var position_now := holder.global_position
		if dt > 0.00001:
			var travel := position_now.distance_to(m["last_position"])
			speed = travel / dt
			m["min_speed"] = minf(float(m["min_speed"]), speed)
			m["stop_seconds"] = float(m["stop_seconds"]) + dt if speed < 0.1 else 0.0
			m["max_stop_seconds"] = maxf(float(m["max_stop_seconds"]), float(m["stop_seconds"]))
			if phase != m["last_phase"]:
				m["max_boundary_excess"] = maxf(float(m["max_boundary_excess"]), travel - float(m["last_speed"]) * dt - 150.0 * dt * dt)
		var grab := director._player_controller.get_intro_ladder_grab_state(n)
		if (info.get("captured", false) or (info.get("hanging", false) and float(grab.get("progress", 0.0)) >= 1.0)) and grab.get("active", false):
			var parts: Dictionary = director._player_controller.p1_parts if n == 1 else director._player_controller.p2_parts
			var ladder := info["rope_ladder"] as PhysicalRopeLadder
			var physical_grip := ladder.get_grip_data()
			var left_wrist := parts["l_wrist"] as Node3D
			var right_wrist := parts["r_wrist"] as Node3D
			var actual_error := maxf(left_wrist.global_position.distance_to(physical_grip["left_hand"]), right_wrist.global_position.distance_to(physical_grip["right_hand"]))
			m["max_hand_error"] = maxf(float(m["max_hand_error"]), actual_error)
		if info.has("captured_at"): m["captured_at"] = info["captured_at"]
		if director._menu_boost_started and not m.has("boost_at"): m["boost_at"] = t
		if info.get("landed", false):
			m["landed"] = true
			var parts: Dictionary = director._player_controller.p1_parts if n == 1 else director._player_controller.p2_parts
			var pelvis := parts["pelvis"] as Node3D
			var ground: Vector3 = info["ground"]
			m["landing_error"] = Vector2(pelvis.global_position.x - ground.x, pelvis.global_position.z - ground.z).length()
		var bounds := director._helicopter_screen_bounds(info)
		var in_frame := director._screen_bounds_intersects_frame(bounds)
		if sequence == "dropoff":
			if in_frame and not m.has("entered_frame_at"): m["entered_frame_at"] = t
			if info.has("lowering_started_at"): m["lowering_started_at"] = info["lowering_started_at"]
			if info.has("released_at"): m["released_at"] = info["released_at"]
			if phase == "depart":
				m["exited_frame"] = not in_frame
			if dt > 0.00001:
				var inward_speed := (position_now - Vector3(m["last_position"])).dot(info["inward_direction"]) / dt
				m["min_inward_speed"] = minf(float(m.get("min_inward_speed", INF)), inward_speed)
		m["last_t"] = t
		m["last_position"] = position_now
		m["last_speed"] = speed
		m["last_phase"] = phase
		samples.append({"sequence": sequence, "player": n, "t": t, "phase": phase, "position": [position_now.x, position_now.y, position_now.z], "speed": speed, "hand_error": grab.get("max_hand_error", -1.0), "captured": info.get("captured", false), "landed": info.get("landed", false), "visible": in_frame, "bounds": bounds, "grip_progress": grab.get("progress", -1.0), "character": str(grab.get("character_position", Vector3.ZERO))})

	if sequence == "dropoff" and director._helicopters.size() == 2:
		var a: Dictionary = director._helicopters[0]
		var b: Dictionary = director._helicopters[1]
		var a_pos: Vector3 = a["holder"].global_position
		var b_pos: Vector3 = b["holder"].global_position
		pair_min_distance = minf(pair_min_distance, a_pos.distance_to(b_pos))
		var camera := get_viewport().get_camera_3d()
		var order := signf(camera.unproject_position(a_pos).x - camera.unproject_position(b_pos).x)
		if previous_screen_order != 0.0 and order != previous_screen_order:
			pair_crossed = bool(a.get("jumped", false)) and bool(b.get("jumped", false))
		previous_screen_order = order

func check(ok: bool, description: String) -> void:
	checks[description] = ok
	if not ok and not failures.has(description):
		failures.append(description)
		push_error(description)

func check_retry_and_skip() -> void:
	var world := get_tree().current_scene
	var world_id := world.get_instance_id()
	world.get_node("GameplayHUD").call("_retry_game")
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().current_scene
		if current != null and current.get_instance_id() != world_id and not SceneTransition.is_transitioning():
			check(current.get_node_or_null("HelicopterArrivalDirector") == null, "retry omits helicopter arrival")
			check(not current.call("is_start_presentation_locked"), "retry leaves start unlocked")
			check(QuizManager.game_state.game_state == Constants.STATE_WAITING_START, "retry reaches Ready")
			break
	check(Time.get_ticks_msec() < deadline, "retry completes")
	await SceneTransition.fade_to_color_and_wait(Color.BLACK)
	QuizManager.game_state.reset_to_menu()
	QuizManager.game_state.num_players = players
	QuizManager.game_state.mode = Constants.MODE_TEN
	QuizManager.game_state.menu_step = Constants.MENU_STEP_CONFIG
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://ui/main_menu.tscn" or SceneTransition.is_transitioning():
		await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.call("_update_ui")
	await get_tree().create_timer(0.5).timeout
	menu.call("_on_start_pressed")
	deadline = Time.get_ticks_msec() + 15000
	var skipped := false
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().current_scene
		if current == null: continue
		if current.scene_file_path == "res://scenes/game_world.tscn": break
		var preview: Node = current.get("_menu_wall_preview")
		var director: HelicopterArrivalDirector = preview.get("_menu_start_departure")
		if not skipped and is_instance_valid(director) and director._phase == "departure_pickup" and director._phase_elapsed > 1.8:
			# Exercise the same handler the Space key/button invokes.
			current.call("_skip_menu_helicopter_departure")
			skipped = true
	check(skipped and Time.get_ticks_msec() < deadline, "skip during restored pickup reaches world")
