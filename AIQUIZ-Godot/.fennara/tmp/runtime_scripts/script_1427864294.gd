extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var gs: QuizGameState = root.get("game_state") as QuizGameState
	var event_count: Array[int] = [0]
	var on_ocean: Callable = func(_player_index: int, _local_position: Vector3) -> void:
		event_count[0] += 1
	gs.player_entered_ocean.connect(on_ocean)
	gs.num_players = 1
	gs.p1_alive = true
	gs.p2_alive = false
	gs.game_state = Constants.STATE_PLAYING
	gs.player_x = StageConstants.FLOOR_HALF_WIDTH + 2.0
	gs.player_y = StageConstants.OCEAN_ENTRY_Y + 0.1
	gs.player_z = 0.0
	gs.world_scroll_z = 0.0
	gs.player_vel_y = -6.0
	gs.game_over_timer = 0.0
	await ctx.wait(0.35)
	var splash: Node = root.find_child("OceanSplash", true, false)
	await ctx.wait(2.1)
	var player_controller: Node = root.get_node("Player")
	var explosion_bodies: Array = player_controller.get("_p1_explosion_bodies")
	ctx.log("verify events=%d splash=%s sink_y=%.3f explosions=%d message_has_ocean=%s" % [
		event_count[0],
		str(splash != null),
		gs.player_y,
		explosion_bodies.size(),
		str(gs.game_over_base_msg.contains("海") or gs.game_over_base_msg.contains("ocean"))
	])
