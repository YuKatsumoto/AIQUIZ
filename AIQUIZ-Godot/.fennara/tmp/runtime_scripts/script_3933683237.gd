extends RefCounted

func run(ctx: Variant) -> void:
	var world: Node = ctx.get_scene_root()
	var debug_camera: Camera3D = Camera3D.new()
	debug_camera.name = "TeleportInvestigationCamera"
	world.add_child(debug_camera)
	debug_camera.global_position = Vector3(28.0, 16.0, 121.0)
	debug_camera.look_at(Vector3(4.0, -2.0, 139.5))
	debug_camera.fov = 60.0
	debug_camera.far = 5000.0
	debug_camera.make_current()
	ctx.log("wide_inspection", {"p1": [QuizManager.game_state.player_x, QuizManager.game_state.player_y, QuizManager.game_state.player_local_z], "p2": [QuizManager.game_state.player2_x, QuizManager.game_state.player2_y, QuizManager.game_state.player2_local_z], "fall": QuizManager.game_state.p1_fall_committed, "camera": "diagnostic wide view; paused game state unchanged"})
	await ctx.capture("wide_ocean_evidence")
