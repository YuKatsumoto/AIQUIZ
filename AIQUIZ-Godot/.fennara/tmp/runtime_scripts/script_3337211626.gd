extends RefCounted

func _append_phase(sequences: Dictionary, player_index: int, phase: int) -> void:
	var sequence: Array = sequences[player_index]
	if sequence.is_empty() or int(sequence[-1]) != phase:
		sequence.append(phase)

func run(ctx: Variant) -> void:
	await ctx.restart_scene()
	var world: Node3D = ctx.get_scene_root() as Node3D
	world.set_process(false)
	var state: Object = world.get("game_state")
	state.set("mode", Constants.MODE_TEN)
	state.set("num_players", 2)
	state.set("p1_alive", true)
	state.set("p2_alive", true)
	state.set("p1_waiting_for_shark", false)
	state.set("p2_waiting_for_shark", false)
	state.set("player_x", -15.0)
	state.set("player2_x", 15.0)
	state.set("player_local_z", 18.0)
	state.set("player2_local_z", 10.0)

	var stage: Node3D = world.get("stage_env") as Node3D
	var sharks: Array[SharkSwimmer] = stage.get_ocean_sharks()
	for index: int in range(sharks.size()):
		sharks[index].cancel_attack()
		sharks[index].position = Vector3(-30.0 if index % 2 == 0 else 30.0, -0.22, -60.0 - index * 4.0)
	sharks[0].position = Vector3(-15.0, -0.22, -28.0)
	sharks[1].position = Vector3(15.0, -0.22, -28.0)

	state.call("_begin_ocean_shark_wait", 1)
	await ctx.wait(0.22)
	var assignments: Dictionary = world.get("_ocean_attack_sharks")
	var shark1: SharkSwimmer = assignments.get(1) as SharkSwimmer
	if shark1 == null:
		ctx.error("P1 shark was not assigned")
		return
	var assigned_target_1: int = shark1.get_attack_player_index()

	state.call("_begin_ocean_shark_wait", 2)
	await ctx.wait(0.02)
	assignments = world.get("_ocean_attack_sharks")
	var shark2: SharkSwimmer = assignments.get(2) as SharkSwimmer
	if shark2 == null:
		ctx.error("P2 shark was not assigned")
		return
	var assigned_target_2: int = shark2.get_attack_player_index()
	var sequences: Dictionary = {1: [shark1.get_attack_phase()], 2: [shark2.get_attack_phase()]}
	var elapsed: float = 0.0
	while elapsed < 3.0 and (shark1.is_attacking or shark2.is_attacking):
		_append_phase(sequences, 1, shark1.get_attack_phase())
		_append_phase(sequences, 2, shark2.get_attack_phase())
		await ctx.wait(0.02)
		elapsed += 0.02
	_append_phase(sequences, 1, shark1.get_attack_phase())
	_append_phase(sequences, 2, shark2.get_attack_phase())

	var columns: int = 0
	var rings: int = 0
	var spawner: Node = world.get_node("ParticleSpawner")
	for child: Node in spawner.get_children():
		if String(child.name).begins_with("SharkImpactColumn"):
			columns += 1
		elif String(child.name).begins_with("SharkImpactRing"):
			rings += 1
	var wipe: Node = world.get_node("DeathWipeLayer/DeathWipe")
	ctx.log("two_player_staggered ids=%d/%d distinct=%s assigned=%d/%d phases=%s alive=%s/%s killed=%s/%s columns=%d rings=%d wipe_player=%d" % [
		shark1.get_instance_id(),
		shark2.get_instance_id(),
		str(shark1 != shark2),
		assigned_target_1,
		assigned_target_2,
		str(sequences),
		str(state.get("p1_alive")),
		str(state.get("p2_alive")),
		str(state.get("p1_shark_killed")),
		str(state.get("p2_shark_killed")),
		columns,
		rings,
		int(wipe.get("_dead_player")),
	])
