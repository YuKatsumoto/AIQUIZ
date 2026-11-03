extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var camera_controller: Node = root.get_node_or_null("CameraController")
	if camera_controller == null:
		ctx.error("CameraController was not found in the running game world.")
		return

	var final_shark_death := QuizGameState.new()
	final_shark_death.num_players = 2
	final_shark_death.p1_alive = false
	final_shark_death.p2_alive = false
	final_shark_death.p2_shark_killed = true
	final_shark_death.game_state = Constants.STATE_GAME_OVER
	final_shark_death.player2_x = -1.5
	final_shark_death.player2_y = 0.0
	final_shark_death.player2_local_z = 12.0

	var solo_shark_death := QuizGameState.new()
	solo_shark_death.num_players = 1
	solo_shark_death.p1_alive = false
	solo_shark_death.p1_shark_killed = true
	solo_shark_death.game_state = Constants.STATE_GAME_OVER

	camera_controller.set("_ocean_attack_camera_active", false)
	camera_controller.call("update_camera", final_shark_death, 0.016)
	var final_uses_ocean: bool = bool(camera_controller.get("_ocean_attack_camera_active"))

	camera_controller.set("_ocean_attack_camera_active", false)
	camera_controller.call("update_camera", solo_shark_death, 0.016)
	var solo_uses_ocean: bool = bool(camera_controller.get("_ocean_attack_camera_active"))

	ctx.log("camera mode after shark death", {
		"2p_final_shark_death_ocean_camera_active": final_uses_ocean,
		"1p_shark_death_ocean_camera_active": solo_uses_ocean,
	})
	if final_uses_ocean or not solo_uses_ocean:
		ctx.error("Camera mode did not match the expected 1P/2P behavior.")
