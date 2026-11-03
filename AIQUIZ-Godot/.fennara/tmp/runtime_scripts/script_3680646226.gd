extends RefCounted

func run(ctx: Variant) -> void:
	for local: bool in [true, false]:
		var gs: QuizGameState = QuizGameState.new()
		gs.num_players = 2
		gs.mode = Constants.MODE_ENDLESS
		gs.game_state = Constants.STATE_PLAYING
		gs.local_push_transport_enabled = local
		gs.player_x = 1.5
		gs.player2_x = -1.5
		gs.player_z = 139.49
		gs.player2_z = 138.0
		gs.current_wall_index = 10
		gs._active_wall_speed = 2.9
		for frame: int in range(4):
			ctx.log("forward_boundary", {"local_push": local, "frame": frame, "x": gs.player_x, "y": gs.player_y, "local_z": gs.player_local_z, "fall": gs.p1_fall_committed})
			gs._update_playing(1.0 / 60.0, Vector2(0, 1), Vector2.ZERO, false, false)
	ctx.log("live_scene", {"path": ctx.get_scene_root().scene_file_path, "state": QuizManager.game_state.game_state, "user_dir": OS.get_user_data_dir()})
