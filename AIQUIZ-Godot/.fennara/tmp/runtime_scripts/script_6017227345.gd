extends RefCounted

func run(ctx: Variant) -> void:
	var result: Dictionary = load("res://tests/floor_boundary_regression.gd").new().run()
	ctx.log("floor_regression", result)
	var output: String = "res://artifacts/teleport_fix"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output + "/regression.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	if not result.passed:
		ctx.error("Floor regression failed")
		return
	ctx.get_scene_root().get_node("HelicopterArrivalDirector").cancel()
	ctx.get_scene_root().get_node("Player").reveal_without_intro_arrival()
	var rows: Array[Dictionary] = []
	for player: int in [1, 2]:
		ctx.get_scene_root().get_tree().paused = true
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
		gs.p1_fall_committed = false
		gs.p2_fall_committed = false
		gs._active_wall_speed = 2.9
		gs.current_quiz = null
		gs.local_push.reset()
		ctx.get_scene_root().call("_update_floor")
		ctx.get_scene_root().call("_update_player", 0.0)
		ctx.get_scene_root().call("_update_camera", 1.0)
		ctx.get_scene_root().get_tree().paused = false
		await ctx.wait(0.1)
		ctx.press_key(KEY_W if player == 1 else KEY_UP, {"physical": false})
		await ctx.wait(0.5)
		ctx.release_all_inputs()
		ctx.get_scene_root().get_tree().paused = true
		gs = QuizManager.game_state
		var stage: Node = ctx.get_scene_root().get_node("StageEnvironment")
		var z: float = gs.player_local_z if player == 1 else gs.player2_local_z
		var rendered_front: float = stage.get_floor_center_z() + stage.get_floor_length() * 0.5
		var passed: bool = z > 140.0 and not gs.p1_fall_committed and not gs.p2_fall_committed and is_equal_approx(gs.player_x, 1.5) and is_equal_approx(gs.player2_x, -1.5) and gs.player_y == 0.0 and gs.player2_y == 0.0 and is_equal_approx(rendered_front, gs.get_floor_front_z())
		rows.append({"player": player, "passed": passed, "p1": [gs.player_x, gs.player_y, gs.player_local_z], "p2": [gs.player2_x, gs.player2_y, gs.player2_local_z], "rendered_front": rendered_front, "logic_front": gs.get_floor_front_z()})
		if not passed:
			ctx.error("Forward runtime case failed P%d" % player)
		await ctx.capture("fixed_forward_p%d" % player)
	ctx.log("live_forward_results", {"rows": rows})
	FileAccess.open(output + "/live_forward.json", FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))
	QuizManager.game_state.player_x = 11.99
	ctx.get_scene_root().get_tree().paused = false
	ctx.press_key(KEY_A, {"physical": false})
	await ctx.wait(0.15)
	ctx.release_all_inputs()
	ctx.get_scene_root().get_tree().paused = true
	var edge_gs: QuizGameState = QuizManager.game_state
	var edge_ok: bool = edge_gs.p1_fall_committed and edge_gs.player_y < 0.0 and not edge_gs.p2_fall_committed
	ctx.log("live_side_fall", {"passed": edge_ok, "x": edge_gs.player_x, "y": edge_gs.player_y, "p2_grounded": edge_gs.player2_y == 0.0})
	if not edge_ok:
		ctx.error("Real side edge no longer falls")
