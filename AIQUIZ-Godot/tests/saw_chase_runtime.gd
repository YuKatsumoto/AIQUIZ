extends RefCounted
const OUT := "res://artifacts/chip_saw/verification/"
var checks: Array[String] = []
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func save_frame(ctx: Variant, label: String) -> void:
	var frame: Image = await ctx.frame(1280)
	frame.save_png(OUT + label + ".png")
	ctx.output(frame, label)

func run(ctx: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "clip"))
	var gs: QuizGameState = QuizManager.game_state
	var world: Node3D = ctx.get_scene_root()
	var tree: SceneTree = world.get_tree()
	tree.paused = true
	var camera: Camera3D = world.camera_controller.get_node("Camera3D")
	var rails: Node3D = world.stage_env._running_rails
	check(rails.find_children("*", "CollisionObject3D", true, false).is_empty(), "live rails have no colliders")
	var weather: WeatherCycle = world.stage_env.weather_cycle
	# Mechanical closeups use the live game viewport, only the camera is staged.
	gs.saw.elapsed = 3
	gs.saw.local_z = -10.85
	world._saw_controller.update_visual(gs)
	var saved_transform := camera.global_transform
	var saved_fov := camera.fov
	if weather != null: weather.force_day_phase(0.23)
	camera.global_position = Vector3(14.0, 1.5, -15.0)
	camera.look_at(Vector3(11.65, -0.85, -10.3))
	camera.fov = 52
	await save_frame(ctx, "rail_closeup_day")
	if weather != null: weather.force_day_phase(0.7)
	await save_frame(ctx, "rail_closeup_night")
	if weather != null: weather.force_day_phase(0.23)
	camera.global_transform = saved_transform
	camera.fov = saved_fov
	var skeleton: Skeleton3D = world._saw_controller.skeleton
	var bone: int = skeleton.find_bone("Spin_01")
	for fps: int in [24,30,60,120]:
		gs.saw.elapsed = 5.0
		world._saw_controller.update_visual(gs)
		var before := skeleton.get_bone_pose_rotation(bone)
		gs.saw.elapsed += 1.0 / fps
		world._saw_controller.update_visual(gs)
		var after := skeleton.get_bone_pose_rotation(bone)
		check(absf(before.angle_to(after) - TAU * SawChaseState.BLADE_RPM / 60.0 / fps) < 0.001, "imported blade rotation 90rpm at %dfps" % fps)
	var wheel: int = skeleton.find_bone("Roll_01")
	gs.saw.wheel_distance = 0.18 * PI / 2
	world._saw_controller.update_visual(gs)
	var expected := skeleton.get_bone_rest(wheel).basis.get_rotation_quaternion() * Quaternion(Vector3.UP, -PI / 2)
	check(skeleton.get_bone_pose_rotation(wheel).angle_to(expected) < .001, "wheel angle follows real travel and retains axle")
	# Fresh placements before the real input-driven chase; no hit is forced.
	gs.world_scroll_z = 0
	gs.saw.local_z = -10.85
	gs.saw.elapsed = 3
	gs.saw.wheel_distance = 0
	gs.player_x = 1.5
	gs.player2_x = -1.5
	gs.player_y = 0
	gs.player2_y = 0
	gs.player_z = 9
	gs.player2_z = -3.5
	gs.player_vel_y = 0
	gs.player2_vel_y = 0
	gs.current_wall_index = 0
	gs.current_index = 0
	gs.load_current_quiz()
	var old_fps := Engine.max_fps
	Engine.max_fps = 60
	tree.paused = false
	await ctx.wait(0.2)
	tree = ctx.get_scene_root().get_tree()
	tree.paused = true
	await save_frame(ctx, "chase")
	var saved_p2_z: float = gs.player2_z
	gs.player2_z = gs.world_scroll_z + gs.saw.local_z + 2.47
	world._update_player(0.0)
	for i: int in range(30): world._update_camera(1.0 / 60.0)
	await save_frame(ctx, "before_contact")
	gs.player2_z = saved_p2_z
	world._update_player(0.0)
	var paused_z: float = gs.saw.local_z
	var paused_time: float = gs.saw.elapsed
	await ctx.wait(0.3)
	check(gs.saw.local_z == paused_z and gs.saw.elapsed == paused_time, "pause freezes carriage and spin")
	var frames: Array[Image] = []
	var times: Array[float] = []
	key(KEY_DOWN, true)
	key(KEY_CTRL, true)
	tree.paused = false
	var started := Time.get_ticks_msec()
	var last_capture := -1000
	var contact_saved := true
	var ragdoll_saved := false
	var scatter_saved := false
	while Time.get_ticks_msec() - started < 5200:
		await tree.process_frame
		world = ctx.get_scene_root()
		gs = QuizManager.game_state
		var elapsed := Time.get_ticks_msec() - started
		if elapsed - last_capture >= 65:
			last_capture = elapsed
			frames.append(await ctx.frame(960))
			times.append(elapsed / 1000.0)
		if gs.p2_alive and gs.get_saw_clearance(2) < 1.0 and not contact_saved:
			contact_saved = true
			await save_frame(ctx, "before_contact")
		if gs.p2_saw_killed and not ragdoll_saved:
			ragdoll_saved = true
			key(KEY_DOWN, false)
			key(KEY_CTRL, false)
			check(gs.player2_y > 0.1, "real jumping P2 caught")
			check(not gs.p2_wall_impact and gs.p2_hp == 0 and gs.p1_alive, "live saw kill leaves survivor and bypasses HP")
			await ctx.wait(0.25)
			await save_frame(ctx, "caught_ragdoll")
		if gs.player2_game_over_timer > 2.2 and not scatter_saved:
			scatter_saved = true
			await save_frame(ctx, "block_scatter")
	key(KEY_DOWN, false)
	key(KEY_CTRL, false)
	tree.paused = true
	world = ctx.get_scene_root()
	check(ragdoll_saved and scatter_saved, "live contact and 2-second block scatter completed")
	check(world.player_node._p2_explosion_bodies.size() > 0, "block debris instantiated")
	var ghost: Dictionary = world._ghost_shark_ride_controller.get_presentation_state(2)
	samples.append({"ghost_after_5sec":ghost,"p2_timer":gs.player2_game_over_timer})
	var leader_z: float = gs.player_local_z
	gs.player_z += 8
	var saw_before: float = gs.saw.local_z
	tree.paused = false
	await ctx.wait(0.8)
	tree.paused = true
	check(gs.saw.local_z > saw_before, "live pursuit continues after P2 death")
	gs.player_z = leader_z + gs.world_scroll_z
	# Keep survivor clear of the next wall while the existing ghost sequence finishes.
	gs.current_wall_index = 20
	tree.paused = false
	await ctx.wait(13.0)
	tree.paused = true
	world = ctx.get_scene_root()
	ghost = world._ghost_shark_ride_controller.get_presentation_state(2)
	check(bool(ghost.get("active", false)), "ghost shark presentation active after saw death")
	samples.append({"ghost_after_19sec":ghost})
	await save_frame(ctx, "ghost_shark")
	Engine.max_fps = old_fps
	for i: int in range(frames.size()):
		frames[i].save_png(OUT + "clip/frame_%04d.png" % i)
	FileAccess.open(OUT + "clip/times.json", FileAccess.WRITE).store_string(JSON.stringify(times))
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"samples":samples,"video_frames":frames.size()}, "\t"))
	ctx.log("Saw runtime validation", {"checks":checks.size(),"failures":failures,"frames":frames.size()})
