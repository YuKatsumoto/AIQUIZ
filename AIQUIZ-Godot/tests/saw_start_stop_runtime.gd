extends Node

const OUT := "res://artifacts/saw_start_stop/"
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok and not failures.has(label): failures.append(label)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + label + ".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.max_fps = 60
	get_tree().root.size = Vector2i(1280, 720)
	QuizManager.provider.set_llm_mode("OFFLINE")
	var gs := QuizManager.game_state
	gs.num_players = 2
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
	check(Time.get_ticks_msec() < deadline, "startup completes")
	world.set_process(false)
	var saw: SawChaseController = world._saw_controller
	saw.finish_entrance()
	gs.game_state = Constants.STATE_COUNTDOWN
	gs.countdown_timer = 0.01
	saw._landing_spin_elapsed = SawChaseState.SPINUP_SECONDS
	gs.update(1.0 / 60.0)
	gs.state_changed.emit(gs.game_state)
	var camera: Camera3D = world.camera_controller.camera
	camera.global_position = Vector3(-16, 10, -21)
	camera.look_at(Vector3(0, 0, -6))
	for frame in range(120):
		await get_tree().physics_frame
		gs.update(1.0 / 60.0, Vector2(0, -1), Vector2.ZERO)
		saw.update_visual(gs, 1.0 / 60.0, true)
		world._update_player(1.0 / 60.0)
		world._update_walls()
		if gs.p1_saw_killed: break
	check(gs.p1_saw_killed and gs.p2_alive and gs.saw.elapsed < 2.0, "rendered P1 retreat catches during start grace")
	check(not gs.saw.stopping, "survivor prevents coast")
	samples.append({"case": "start_contact", "time": gs.saw.elapsed, "p1_z": gs.player_local_z, "saw_z": gs.saw.local_z})
	await capture("start_contact")
	for frame in range(120):
		await get_tree().physics_frame
		gs.update(1.0 / 60.0, Vector2.ZERO, Vector2(0, -1))
		saw.update_visual(gs, 1.0 / 60.0, true)
		world._update_player(1.0 / 60.0)
		if gs.p2_saw_killed: break
	check(gs.p2_saw_killed and gs.game_state == Constants.STATE_GAME_OVER, "last survivor contact enters game over")
	await coast_case(world, "stationary")
	# Exercise the same final-death route with a moving carriage and a wall victim.
	gs.start_game()
	gs.game_state = Constants.STATE_PLAYING
	gs.saw.advance(0.1, 100.0, 14.0, 6.0)
	gs.saw.elapsed = 4.0
	gs.p1_alive = false
	gs.player2_x = 1.5
	gs.player2_z = gs.world_scroll_z
	gs._set_player_hp(2, 1)
	gs._apply_hp_wall_damage(2)
	gs._game_over("Saw coast regression")
	saw.update_visual(gs, 1.0 / 60.0, true)
	world._update_player(1.0 / 60.0)
	await coast_case(world, "moving")
	var report := {"passed": failures.is_empty(), "failures": failures, "samples": samples}
	FileAccess.open(OUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SAW_START_STOP_RUNTIME ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func coast_case(world: Node, label: String) -> void:
	var gs: QuizGameState = world.game_state
	var saw: SawChaseController = world._saw_controller
	var bone := saw.spin_bones[0]
	var previous_rotation := saw.skeleton.get_bone_pose_rotation(bone)
	var previous_angle := INF
	var initial_z: float = gs.saw.local_z
	var initial_velocity: float = gs.saw.velocity
	var initial_spin: float = gs.saw.elapsed
	var angles: Array[float] = []
	for frame in range(151):
		await get_tree().physics_frame
		gs.update(1.0 / 60.0)
		saw.update_visual(gs, 1.0 / 60.0, true)
		world._update_player(1.0 / 60.0)
		world._check_particles()
		var rotation := saw.skeleton.get_bone_pose_rotation(bone)
		var angle := previous_rotation.angle_to(rotation)
		if frame < 110: check(angle <= previous_angle + 0.0015, label + " rendered blade rotation slows continuously")
		if frame == 0: check(angle > 0.10, label + " first game-over frame keeps spinning")
		if frame == 60: check(angle > 0.02 and angle < 0.10, label + " halfway frame still rotating slowly")
		if frame >= 125: check(angle < 0.001, label + " rendered rotation settles completely")
		previous_rotation = rotation
		previous_angle = angle
		angles.append(angle)
		if frame in [0, 29, 59, 89, 119, 150]:
			samples.append({"case": label, "time": gs.saw.stop_elapsed, "angle": angle, "velocity": gs.saw.velocity, "z": gs.saw.local_z, "audio_pitch": saw.dock._spindle.pitch_scale, "audio_playing": saw.dock._spindle.playing, "operator_drive": saw.operator_seat.last_sample.drive})
			await capture(label + "_%03d" % frame)
	check(is_equal_approx(gs.saw.local_z - initial_z, initial_velocity), label + " actual carriage matches integrated stopping distance")
	check(is_equal_approx(gs.saw.elapsed - initial_spin, 1.0), label + " motor clock integrates deceleration")
	check(not saw.dock._spindle.playing, label + " spindle audio stops at rest")
	check(float(saw.operator_seat.last_sample.drive) == 0.0, label + " operator lever returns to rest")
