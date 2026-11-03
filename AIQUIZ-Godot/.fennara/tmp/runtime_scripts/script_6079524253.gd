extends RefCounted

func run(ctx: Variant) -> void:
	var gs: QuizGameState = QuizManager.game_state
	gs.player_x = 1.5
	gs.player2_x = -1.5
	gs.player_z = gs.world_scroll_z + 139.3
	gs.player2_z = gs.world_scroll_z + 139.3
	gs.player_y = 0.0
	gs.player2_y = 0.0
	gs.player_vel_y = 0.0
	gs.player2_vel_y = 0.0
	gs.p1_fall_committed = false
	gs.p2_fall_committed = false
	gs.local_push.reset()
	ctx.get_scene_root().get_tree().paused = false
	ctx.press_key(KEY_W, {"physical": false})
	ctx.press_key(KEY_UP, {"physical": false})
	await ctx.wait(0.6)
	ctx.release_all_inputs()
	ctx.get_scene_root().get_tree().paused = true
	gs = QuizManager.game_state
	ctx.log("both_crossed", {"p1": [gs.player_x, gs.player_y, gs.player_local_z], "p2": [gs.player2_x, gs.player2_y, gs.player2_local_z], "fall1": gs.p1_fall_committed, "fall2": gs.p2_fall_committed})
	var debug_camera: Camera3D = Camera3D.new()
	ctx.get_scene_root().add_child(debug_camera)
	debug_camera.global_position = Vector3(28.0, 16.0, 125.0)
	debug_camera.look_at(Vector3(4.0, -2.0, 143.5))
	debug_camera.fov = 60.0
	debug_camera.far = 5000.0
	debug_camera.make_current()
	await ctx.capture("both_players_grounded_after_boundary")
