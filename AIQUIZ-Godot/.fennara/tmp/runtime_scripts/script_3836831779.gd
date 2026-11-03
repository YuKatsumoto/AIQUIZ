extends RefCounted

func run(ctx: Variant) -> void:
	var world: Node = ctx.get_scene_root()
	world.get_tree().paused = true
	world.get_node("HelicopterArrivalDirector").cancel()
	world.get_node("Player").reveal_without_intro_arrival()
	var gs: QuizGameState = QuizManager.game_state
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.game_state = Constants.STATE_PLAYING
	gs.current_index = 5
	gs.current_wall_index = 5
	gs.world_scroll_z = 0.0
	gs.player_x = 1.5
	gs.player2_x = -1.5
	gs.player_z = 139.3
	gs.player2_z = 139.3
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	gs.p1_alive = true
	gs.p2_alive = true
	gs.p1_fall_committed = false
	gs.p2_fall_committed = false
	gs._active_wall_speed = 2.9
	gs.local_push.reset()
	gs.current_quiz = null
	world.call("_update_floor")
	world.call("_update_player", 0.0)
	world.call("_update_camera", 1.0)
	var stage: Node = world.get_node("StageEnvironment")
	ctx.log("live_fixture", {"p1": [gs.player_x, gs.player_y, gs.player_local_z], "p2": [gs.player2_x, gs.player2_y, gs.player2_local_z], "floor_front": stage.get_floor_center_z() + stage.get_floor_length() * 0.5})
	await ctx.capture("before_forward_input")
	ctx.get_scene_root().get_tree().paused = false
	ctx.press_key(KEY_W)
	var samples: Array[Dictionary] = []
	for frame: int in range(60):
		await ctx.get_scene_root().get_tree().process_frame
		gs = QuizManager.game_state
		samples.append({"frame": frame, "p1": [gs.player_x, gs.player_y, gs.player_local_z], "p2": [gs.player2_x, gs.player2_y, gs.player2_local_z], "fall": gs.p1_fall_committed})
		if gs.p1_fall_committed:
			break
	ctx.release_all_inputs()
	ctx.get_scene_root().get_tree().paused = true
	ctx.log("live_keyboard_result", {"samples": samples})
	FileAccess.open("res://artifacts/teleport_investigation/live_samples.json", FileAccess.WRITE).store_string(JSON.stringify(samples, "\t"))
	await ctx.capture("after_forward_input_teleport")
	ctx.get_scene_root().get_tree().paused = false
	await ctx.wait(0.7)
	ctx.get_scene_root().get_tree().paused = true
	await ctx.capture("falling_into_ocean")
