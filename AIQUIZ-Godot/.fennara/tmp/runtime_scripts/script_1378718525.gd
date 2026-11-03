extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var gs: QuizGameState = root.get("game_state") as QuizGameState
	var event_count: Array[int] = [0]
	var event_player: Array[int] = [0]
	var event_position: Array[Vector3] = [Vector3.ZERO]
	var on_ocean: Callable = func(player_index: int, local_position: Vector3) -> void:
		event_count[0] += 1
		event_player[0] = player_index
		event_position[0] = local_position
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
	ctx.log("ocean_entry events=%d player=%d pos=%s alive=%s timer=%.3f y=%.3f splash=%s" % [
		event_count[0],
		event_player[0],
		str(event_position[0]),
		str(gs.p1_alive),
		gs.game_over_timer,
		gs.player_y,
		str(splash != null)
	])
	await ctx.capture("ocean_fall_splash")

	await ctx.wait(2.1)
	var player_controller: Node = root.get_node("Player")
	var explosion_bodies: Array = player_controller.get("_p1_explosion_bodies")
	var explosion_particles: GPUParticles3D = root.get_node("ParticleSpawner/ExplosionParticles") as GPUParticles3D
	ctx.log("ocean_sink y=%.3f timer=%.3f explosion_bodies=%d explosion_emitting=%s" % [
		gs.player_y,
		gs.game_over_timer,
		explosion_bodies.size(),
		str(explosion_particles.emitting)
	])
	await ctx.capture("ocean_after_sink")
