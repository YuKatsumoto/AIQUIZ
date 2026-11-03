extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var world: Node3D = root as Node3D
	var game_state: QuizGameState = world.get("game_state") as QuizGameState
	var stage_env: StageEnvironment = world.get("stage_env") as StageEnvironment
	var sharks: Array[SharkSwimmer] = stage_env.get_ocean_sharks()
	for index: int in range(sharks.size()):
		var setup_shark: SharkSwimmer = sharks[index]
		setup_shark.cancel_attack()
		setup_shark.position = Vector3(-18.0 if index == 0 else 18.0, StageConstants.OCEAN_SURFACE_Y - 0.22, -18.0 + float(index) * 12.0)
	game_state.num_players = 1
	game_state.game_state = "PLAYING"
	game_state.p1_alive = true
	game_state.p1_waiting_for_shark = true
	game_state.p1_shark_killed = false
	game_state.player_x = -15.0
	game_state.player_y = StageConstants.OCEAN_FLOAT_Y
	game_state.p1_ocean_local_z = 18.0
	game_state.player_z = game_state.world_scroll_z + game_state.p1_ocean_local_z
	world.call("_start_ocean_shark_attack", 1, Vector3(-15.0, StageConstants.OCEAN_SURFACE_Y, 18.0))
	var phase_order: PackedInt32Array = PackedInt32Array()
	var last_phase: int = -1
	for sample_index: int in range(80):
		await ctx.wait(0.04)
		root = ctx.get_scene_root()
		world = root as Node3D
		var assigned: Variant = world.get("_ocean_attack_sharks").get(1)
		var shark: SharkSwimmer = assigned as SharkSwimmer
		if shark == null:
			break
		var attack_phase: int = shark.get_attack_phase()
		if attack_phase != last_phase:
			last_phase = attack_phase
			phase_order.append(attack_phase)
	await ctx.wait(0.08)
	await ctx.capture("shark_impact_fixed")
	var spawner: Node = world.get_node_or_null("ParticleSpawner")
	var impact_columns: int = 0
	var impact_rings: int = 0
	for child: Node in spawner.get_children():
		if child.name == "SharkImpactColumn":
			impact_columns += 1
		elif child.name == "SharkImpactRing":
			impact_rings += 1
	ctx.log("one_player phases=%s alive=%s waiting=%s columns=%d rings=%d" % [
		str(phase_order),
		str(game_state.p1_alive),
		str(game_state.p1_waiting_for_shark),
		impact_columns,
		impact_rings
	])
