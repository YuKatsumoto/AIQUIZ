extends Node

var players := 2
var out := ""
var failures: Array[String] = []
var checks: Dictionary = {}
var captures: Dictionary = {}

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks[label] = bool(checks.get(label, true)) and ok
	if not ok and not failures.has(label): failures.append(label)

func check_idle(pc: PlayerController, count: int, label: String) -> void:
	for index in range(1, count + 1):
		var rig := pc._p1_rig if index == 1 else pc._p2_rig
		var parts := pc.p1_parts if index == 1 else pc.p2_parts
		var ap := rig.aps[AnimationRig.SLOT_UAL] as AnimationPlayer
		var resolved := rig.resolve_ual_clip(AnimationRig.UAL_IDLE)
		check(ap.is_playing() and ap.current_animation == resolved, label + " P%d uses preparation idle" % index)
		if not checks[label + " P%d uses preparation idle" % index]:
			print("IDLE_DIAGNOSTIC ", label, " P", index, " expected=", resolved, " actual=", ap.current_animation, " playing=", ap.is_playing())
		check((parts.l_hand as Node3D).global_position.y < (parts.l_shoulder as Node3D).global_position.y - 0.25, label + " P%d left arm is not T pose" % index)
		check((parts.r_hand as Node3D).global_position.y < (parts.r_shoulder as Node3D).global_position.y - 0.25, label + " P%d right arm is not T pose" % index)
		var menu_wait := label.begins_with("menu") or label == "pickup waiting"
		var facing := Vector3.FORWARD if menu_wait else Vector3.BACK
		check((parts.pelvis as Node3D).global_basis.z.normalized().dot(facing) > 0.9, label + " P%d keeps the stage facing" % index)
		if menu_wait:
			# Check the complete visible pose after all menu/intro writers ran.
			# Clip-name checks alone miss a root-facing override on the next frame.
			var mapping := {"spine": "spine", "head_pivot": "head", "l_shoulder": "l_upper_arm", "r_shoulder": "r_upper_arm", "l_elbow": "l_lower_arm", "r_elbow": "r_lower_arm", "l_hip": "l_upper_leg", "r_hip": "r_upper_leg", "l_knee": "l_lower_leg", "r_knee": "r_lower_leg"}
			var mirror := Basis.from_scale(Vector3(-1, 1, 1))
			for key: String in mapping:
				var bone: int = rig.active_bone_indices[mapping[key]]
				var expected := rig.active_skeleton.get_bone_global_pose(bone).basis.orthonormalized()
				expected = mirror * expected * mirror
				if key.begins_with("l_") or key.begins_with("r_"): expected *= Basis(Vector3.RIGHT, PI)
				expected = Basis(Vector3.UP, PI) * expected
				var actual := (parts[key] as Node3D).global_basis.orthonormalized()
				check(actual.get_rotation_quaternion().angle_to(expected.get_rotation_quaternion()) < 0.08, label + " P%d %s retains idle shape" % [index, key])

func close_picture(preview: Node, label: String) -> void:
	# Share the live world, but use an independent viewport so the helicopter
	# director can keep ownership of the actual cinematic camera.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 720)
	viewport.world_3d = preview._preview_player.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var pelvis: Node3D = preview._preview_player.p1_parts.pelvis
	var target := pelvis.global_position + Vector3(0, 0.45, 0)
	camera.fov = 30.0
	camera.global_position = target + Vector3(0, 2.0, 6.5)
	camera.look_at(target)
	camera.make_current()
	await RenderingServer.frame_post_draw
	var path := out + label + ".png"
	viewport.get_texture().get_image().save_png(path)
	captures[label] = path
	viewport.queue_free()

func picture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out + label + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	captures[label] = path

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--players="): players = arg.get_slice("=", 1).to_int()
	out = "res://artifacts/waiting_pose/p%d/" % players
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1280, 720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	gs.start_game()
	gs.skip_start_helicopter_arrival = true
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	while get_tree().current_scene == null: await get_tree().process_frame
	var world := get_tree().current_scene
	var deadline := Time.get_ticks_msec() + 45000
	while (SceneTransition.is_transitioning() or world.is_start_presentation_locked()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(Time.get_ticks_msec() < deadline, "game startup completes")
	world.set_process(false)
	gs.game_state = Constants.STATE_PRELOADING
	world._update_player(0.0)
	check_idle(world.player_node, players, "preloading first frame")
	await picture("preloading")
	gs.game_state = Constants.STATE_WAITING_START
	world._update_player(0.0)
	check_idle(world.player_node, players, "waiting start")
	world.get_node("GameplayHUD")._return_to_main_menu()
	deadline = Time.get_ticks_msec() + 30000
	while (get_tree().current_scene == world or get_tree().current_scene == null) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	check(menu != null and menu.scene_file_path == "res://ui/main_menu.tscn", "real HUD return reaches menu")
	var preview: Node = menu._menu_wall_preview
	var pc: PlayerController = preview._preview_player
	check_idle(pc, preview._preview_gs.num_players, "menu first frame")
	var reveal_frames := 0
	while SceneTransition.is_transitioning() and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if not SceneTransition.is_transitioning(): break
		check_idle(pc, preview._preview_gs.num_players, "menu reveal")
		reveal_frames += 1
		if SceneTransition.get_cover_factor() < 0.35 and not captures.has("menu_reveal"):
			await picture("menu_reveal")
			await close_picture(preview, "menu_reveal_close")
	check(reveal_frames > 5, "menu reveal sampled")
	await picture("menu_ready")
	# The actual customization screen retains its original skin rest posture.
	menu._on_customize_pressed()
	await get_tree().create_timer(1.0).timeout
	var customize: Node = menu._embedded_customize
	customize._set_section(customize.Section.SKIN)
	await get_tree().create_timer(0.4).timeout
	var skin_pc: PlayerController = customize._preview_player
	check(skin_pc.use_skin_preview_rest_pose, "skin exception enabled")
	check(not (skin_pc._p1_rig.aps[AnimationRig.SLOT_UAL] as AnimationPlayer).is_playing(), "skin does not use waiting loop")
	await picture("skin_rest")
	customize._set_section(customize.Section.WALL_SPEED)
	await get_tree().create_timer(0.2).timeout
	check(not skin_pc.use_skin_preview_rest_pose, "leaving skin clears exception")
	check((skin_pc._p1_rig.aps[AnimationRig.SLOT_RUN] as AnimationPlayer).is_playing(), "wall speed running preview retained")
	menu._on_embedded_customize_close_requested()
	await get_tree().create_timer(1.0).timeout
	gs.menu_step = Constants.MENU_STEP_CONFIG
	menu._update_ui()
	preview.sync_menu_player_count(players)
	deadline = Time.get_ticks_msec() + 10000
	while menu.config_conveyor.is_moving() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	menu._on_start_pressed()
	deadline = Time.get_ticks_msec() + 12000
	var wait_frames := 0
	var saw_approach := false
	var saw_grab := false
	var previous_pose := Vector3.ZERO
	var pose_motion := 0.0
	while is_instance_valid(menu) and get_tree().current_scene == menu and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var director: HelicopterArrivalDirector = preview._menu_start_departure
		if not preview.is_game_start_departure_active(): continue
		pc = preview._preview_player
		if not bool(director._helicopters[0].get("approach_started", false)):
			check_idle(pc, players, "pickup waiting")
			var hand: Vector3 = pc.p1_parts.l_hand.global_position
			if wait_frames > 0: pose_motion += hand.distance_to(previous_pose)
			previous_pose = hand
			wait_frames += 1
			if wait_frames == 15:
				await picture("pickup_waiting")
				await close_picture(preview, "pickup_waiting_close")
		else:
			saw_approach = true
			check(not pc._intro_idles.has(1), "pickup run releases idle ownership")
		if bool(director._helicopters[0].get("captured", false)):
			saw_grab = true
			await picture("pickup_grab")
			menu._skip_menu_helicopter_departure()
			break
	check(wait_frames > 5 and pose_motion > 0.001, "pickup waiting pose animates")
	check(saw_approach and saw_grab, "run and ladder grab still complete")
	var report := {"passed": failures.is_empty(), "players": players, "failures": failures, "checks": checks, "captures": captures, "waiting_frames": wait_frames, "waiting_motion": pose_motion}
	FileAccess.open(out + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WAITING_POSE ", JSON.stringify({"passed": failures.is_empty(), "players": players, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
