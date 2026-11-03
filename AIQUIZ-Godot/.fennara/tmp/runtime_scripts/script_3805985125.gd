extends RefCounted

func run(ctx: Variant) -> void:
	var rows: Array[Dictionary] = []
	for fps: int in [30, 60, 120]:
		for mode: String in [Constants.MODE_TEN, Constants.MODE_ENDLESS]:
			for player: int in [1, 2]:
				for local: bool in [true, false]:
					var gs: QuizGameState = QuizGameState.new()
					gs.num_players = 2
					gs.mode = mode
					gs.game_state = Constants.STATE_PLAYING
					gs.local_push_transport_enabled = local
					gs.player_x = 1.5
					gs.player2_x = -1.5
					gs.player_z = 139.49 if player == 1 else 138.0
					gs.player2_z = 139.49 if player == 2 else 138.0
					gs.current_wall_index = 5
					gs._active_wall_speed = 2.9
					for frame: int in range(4):
						gs.update(1.0 / fps, Vector2(0, 1) if player == 1 else Vector2.ZERO, Vector2(0, 1) if player == 2 else Vector2.ZERO)
					var x: float = gs.player_x if player == 1 else gs.player2_x
					var fall: bool = gs.p1_fall_committed if player == 1 else gs.p2_fall_committed
					rows.append({"fps": fps, "mode": mode, "player": player, "local_push": local, "x": x, "fall": fall, "teleport_reproduced": absf(x) > 12.0})
	var path: String = "res://artifacts/teleport_investigation"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	FileAccess.open(path + "/matrix.json", FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))
	ctx.log("boundary_matrix", {"cases": rows.size(), "rows": rows})
