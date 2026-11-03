extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	if root == null:
		ctx.error("GameWorld root was not available")
		return
	var world: Node3D = root as Node3D
	var game_state: QuizGameState = world.get("game_state") as QuizGameState
	var stage_env: StageEnvironment = world.get("stage_env") as StageEnvironment
	if game_state == null or stage_env == null:
		ctx.error("Game state or stage environment was not ready")
		return
	var sharks: Array[SharkSwimmer] = stage_env.get_ocean_sharks()
	if sharks.is_empty():
		ctx.error("No sharks were available")
		return
	for index: int in range(sharks.size()):
		var setup_shark: SharkSwimmer = sharks[index]
		setup_shark.cancel_attack()
		setup_shark.position = Vector3(
			-18.0 if index == 0 else 18.0,
			StageConstants.OCEAN_SURFACE_Y - 0.22,
			-18.0 + float(index) * 12.0
		)

	game_state.num_players = 1
	game_state.game_state = "PLAYING"
	game_state.p1_alive = true
	game_state.p1_waiting_for_shark = true
	game_state.p1_shark_killed = false
	game_state.player_x = -15.0
	game_state.player_y = StageConstants.OCEAN_FLOAT_Y
	game_state.p1_ocean_local_z = 18.0
	game_state.player_z = game_state.world_scroll_z + game_state.p1_ocean_local_z
	world.call(
		"_start_ocean_shark_attack",
		1,
		Vector3(game_state.player_x, StageConstants.OCEAN_SURFACE_Y, game_state.p1_ocean_local_z)
	)

	var last_phase: int = -1
	var captured_charge: bool = false
	var captured_bite: bool = false
	for sample_index: int in range(90):
		await ctx.wait(0.05)
		root = ctx.get_scene_root()
		if root == null:
			break
		world = root as Node3D
		var assigned: Variant = world.get("_ocean_attack_sharks").get(1)
		var shark: SharkSwimmer = assigned as SharkSwimmer
		if shark == null or not is_instance_valid(shark):
			ctx.log("attack_complete sample=%d alive=%s waiting=%s" % [
				sample_index,
				str(game_state.p1_alive),
				str(game_state.p1_waiting_for_shark)
			])
			break
		var current_phase: int = shark.get_attack_phase()
		if current_phase != last_phase:
			last_phase = current_phase
			ctx.log("phase=%d intensity=%.3f distance=%.3f jaw_index=%d" % [
				current_phase,
				shark.get_attack_intensity(),
				shark.position.distance_to(game_state.get_ocean_player_local_position(1)),
				(shark.get("_jaw_bone_index") as int)
			])
		if current_phase == SharkSwimmer.AttackPhase.CHARGE and not captured_charge:
			captured_charge = true
			await ctx.capture("shark_charge")
		elif current_phase == SharkSwimmer.AttackPhase.BITE and not captured_bite:
			captured_bite = true
			await ctx.capture("shark_bite")
	await ctx.wait(0.45)
	await ctx.capture("shark_impact")
	ctx.log("summary charge_capture=%s bite_capture=%s p1_alive=%s waiting=%s" % [
		str(captured_charge),
		str(captured_bite),
		str(game_state.p1_alive),
		str(game_state.p1_waiting_for_shark)
	])
