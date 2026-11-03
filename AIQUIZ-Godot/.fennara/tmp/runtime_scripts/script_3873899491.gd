extends RefCounted
func run(ctx: Variant) -> void:
	var world: Node = ctx.get_scene_root()
	ctx.log("loop_gates", {"replay": world._replay_mode, "online": world._net_state.is_online, "host": NetworkManager.is_host, "time_scale": Engine.time_scale, "process_mode": world.process_mode, "pause": world.get_tree().paused, "can_process": world.can_process()})
	world.get_tree().paused = false
	ctx.press_key(KEY_W)
	await ctx.wait(0.15)
	world = ctx.get_scene_root()
	ctx.log("after_key", {"w": Input.is_key_pressed(KEY_W), "state": QuizManager.game_state.game_state, "time": QuizManager.game_state.play_time, "z": QuizManager.game_state.player_local_z, "pause": world.get_tree().paused, "dt": world.get_process_delta_time(), "can_process": world.can_process()})
	ctx.release_all_inputs()
	world.get_tree().paused = true
