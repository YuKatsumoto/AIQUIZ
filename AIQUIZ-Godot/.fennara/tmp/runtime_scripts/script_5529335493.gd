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

	var last_survivor_waiting := QuizGameState.new()
	last_survivor_waiting.num_players = 2
	last_survivor_waiting.p1_alive = false
	last_survivor_waiting.p2_alive = true
	last_survivor_waiting.p2_waiting_for_shark = true

	var solo_shark_death := QuizGameState.new()
	solo_shark_death.num_players = 1
	solo_shark_death.p1_alive = false
	solo_shark_death.p1_shark_killed = true
	solo_shark_death.game_state = Constants.STATE_GAME_OVER

	var final_uses_ocean: bool = bool(
		camera_controller.call("_should_use_ocean_attack_camera", final_shark_death)
	)
	var waiting_uses_ocean: bool = bool(
		camera_controller.call("_should_use_ocean_attack_camera", last_survivor_waiting)
	)
	var solo_uses_ocean: bool = bool(
		camera_controller.call("_should_use_ocean_attack_camera", solo_shark_death)
	)

	camera_controller.call("update_camera", final_shark_death, 0.016)
	var ocean_camera_active: bool = bool(camera_controller.get("_ocean_attack_camera_active"))
	ctx.log("camera selection cases", {
		"2p_final_shark_death_uses_ocean": final_uses_ocean,
		"2p_last_survivor_waiting_uses_ocean": waiting_uses_ocean,
		"1p_shark_death_uses_ocean": solo_uses_ocean,
		"2p_final_death_ocean_camera_active": ocean_camera_active,
	})
	if final_uses_ocean or waiting_uses_ocean or ocean_camera_active or not solo_uses_ocean:
		ctx.error("Ocean camera selection did not match the expected 1P/2P behavior.")
