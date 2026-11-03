extends RefCounted
func run(ctx: Variant) -> void:
	var helper: RefCounted = load("res://tests/saw_chase_modes_runtime.gd").new()
	if not await helper.start(ctx, Constants.MODE_ENDLESS, 2):
		ctx.error("Could not start verification")
		return
	var world: Node = ctx.get_scene_root()
	var gs: QuizGameState = QuizManager.game_state
	var tree: SceneTree = world.get_tree()
	var rows: Array = []
	gs.current_wall_index = 20
	var old_cap := Engine.max_fps
	for cap: int in [24,30,60,120]:
		Engine.max_fps = cap
		var skeleton: Skeleton3D = world._saw_controller.skeleton
		var bone: int = skeleton.find_bone("Spin_01")
		var angle_before := skeleton.get_bone_pose_rotation(bone)
		var clock_before: float = gs.saw.elapsed
		var frame_before := Engine.get_process_frames()
		var wall_before := Time.get_ticks_msec()
		tree.paused = false
		await ctx.wait(0.5)
		tree.paused = true
		world = ctx.get_scene_root()
		var elapsed: float = gs.saw.elapsed - clock_before
		var expected: float = elapsed * TAU * 0.3
		var actual := angle_before.angle_to(world._saw_controller.skeleton.get_bone_pose_rotation(bone))
		rows.append({"cap":cap,"render_fps":(Engine.get_process_frames()-frame_before)*1000.0/(Time.get_ticks_msec()-wall_before),"angle":actual,"expected":expected,"passed":absf(actual-expected)<0.002})
	Engine.max_fps = old_cap
	gs.player_x = 11.95
	gs.player_z = gs.world_scroll_z
	gs.player_y = 0
	gs.player_vel_y = 0
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	Input.parse_input_event(key)
	tree.paused = false
	await ctx.wait(0.25)
	key = InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = false
	Input.parse_input_event(key)
	tree.paused = true
	rows.append({"side_fall":gs.p1_fall_committed,"x":gs.player_x,"y":gs.player_y,"passed":gs.p1_fall_committed and gs.player_x>12.0 and gs.player_y<0.0 and not gs.p1_saw_killed})
	var shot: Image = await ctx.frame(1280)
	shot.save_png("res://artifacts/chip_saw/verification/side_fall.png")
	FileAccess.open("res://artifacts/chip_saw/verification/fps_and_fall.json", FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	ctx.log("Real frame caps and side fall", {"results":rows})
