extends Node

## Egg break physics (no gameplay). The contents are the Blender white and yolk
## meshes, not an image: the white spreads fast then brakes, further along the
## throw, and creeps downhill on a body; the yolk lands squashed and jiggles back,
## rolls on along the throw on the floor, and slides down (or off) a body. Shell
## pieces bounce and come to rest flat before fading, sprayed liquid lands as
## capped puddles, and clear() leaves nothing behind.
## Run: Godot --headless --path . --script tests/goal_stand_eggs_bootstrap.gd

const STEP := 1.0 / 60.0

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func mean_rim(entry: Dictionary) -> float:
	var total := 0.0
	for radius: float in entry.rim:
		total += radius
	return total / GoalStandEggs.RIM_COUNT


func run() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(0.0, 3.0, 8.0)
	var target := Node3D.new()
	target.name = "Loser"
	add_child(target)
	target.global_position = Vector3(0.0, StageConstants.FLOOR_TOP_Y + 1.2, 0.0)
	var eggs := GoalStandEggs.new()
	add_child(eggs)
	var shard := BoxMesh.new()
	shard.size = Vector3(0.07, 0.012, 0.05)
	eggs.setup(SphereMesh.new(), shard, StandardMaterial3D.new(), 1234, "high")
	check(eggs.white_mesh != null and eggs.yolk_mesh != null, "Blender white and yolk meshes load")
	var shards_per_egg := int(GoalStandEggs.DETAIL["high"].shards)

	var start := Vector3(4.0, StageConstants.FLOOR_TOP_Y + 5.0, -10.0)
	eggs.launch(start, target.global_position + Vector3(0.0, 0.2, 0.0), 1.0, target, false)
	eggs.launch(start, Vector3(1.5, StageConstants.FLOOR_TOP_Y, 1.0), 1.0, null, true)
	var impacts := 0
	var body: Dictionary = {}
	var floor_entry: Dictionary = {}
	var floor_rim_early := 0.0
	var floor_rim_mid := 0.0
	var squash_min := 0.0
	var squash_max := 0.0
	var yolk_y_start := 0.0
	var shard_airborne_seen := false
	var impact_age := -1.0
	for frame in range(int(8.0 / STEP)):
		impacts += eggs.update(STEP, camera).size()
		await get_tree().process_frame
		if body.is_empty():
			for entry: Dictionary in eggs._splats:
				if entry.hit:
					body = entry
					yolk_y_start = (entry.yolk as Node3D).global_position.y
				else:
					floor_entry = entry
					squash_min = float(entry.squash)
			if not body.is_empty():
				impact_age = 0.0
				check(eggs.find_children("*", "Sprite3D", true, false).is_empty() and target.find_children("*", "Sprite3D", true, false).is_empty(), "no image splats")
				var white := body.white as MeshInstance3D
				check(white.mesh == eggs.white_mesh and white.material_override is ShaderMaterial, "body splat is the Blender white with the sheet shader")
				check((body.yolk as MeshInstance3D).mesh == eggs.yolk_mesh, "body splat carries the Blender yolk")
			continue
		impact_age += STEP
		if not floor_entry.is_empty():
			squash_min = minf(squash_min, float(floor_entry.squash))
			squash_max = maxf(squash_max, float(floor_entry.squash))
			if floor_rim_early == 0.0 and impact_age >= 0.05:
				floor_rim_early = mean_rim(floor_entry)
			if floor_rim_mid == 0.0 and impact_age >= 0.3:
				floor_rim_mid = mean_rim(floor_entry)
		for entry: Dictionary in eggs._shards:
			if is_instance_valid(entry.node) and (entry.node as Node3D).global_position.y > StageConstants.FLOOR_TOP_Y + 0.2:
				shard_airborne_seen = true
		if frame == int(3.0 / STEP):
			check(eggs.shards_rested == shards_per_egg * 2, "all shell pieces came to rest (%d/%d)" % [eggs.shards_rested, shards_per_egg * 2])
			for entry: Dictionary in eggs._shards:
				var node := entry.node as Node3D
				check(absf(node.global_position.y - GoalStandEggs.SHARD_REST_Y) < 0.002, "resting shard sits on the conveyor")
				check(node.global_basis.y.normalized().dot(Vector3.UP) > 0.99, "resting shard lies flat")

	check(impacts == 2 and eggs.hits == 1 and eggs.misses == 1, "one hit, one miss")
	check(not body.is_empty() and not floor_entry.is_empty(), "both splats simulated")
	if body.is_empty() or floor_entry.is_empty():
		await finish(eggs, target)
		return
	check(shard_airborne_seen, "shell pieces fly before landing")
	# White: fast spread, braked by viscosity, reaching further along the throw.
	var floor_rim_end := mean_rim(floor_entry)
	check(floor_rim_mid - floor_rim_early > 0.08, "white spreads fast at first (%.3f -> %.3f)" % [floor_rim_early, floor_rim_mid])
	check(floor_rim_end - floor_rim_mid < (floor_rim_mid - floor_rim_early) * 0.1, "then viscosity stops it (%.3f -> %.3f)" % [floor_rim_mid, floor_rim_end])
	var rim: PackedFloat32Array = floor_entry.rim
	check(rim[0] > rim[GoalStandEggs.RIM_COUNT / 2] * 1.2, "white reaches further along the throw (%.3f vs %.3f)" % [rim[0], rim[GoalStandEggs.RIM_COUNT / 2]])
	check(float((floor_entry.material as ShaderMaterial).get_shader_parameter("thickness")) <= GoalStandEggs.WHITE_THICKNESS + 0.001, "white thins as it spreads")
	# Yolk: lands squashed, overshoots, settles; momentum rolls it along the throw.
	check(squash_min < -0.4 and squash_max > 0.05 and absf(float(floor_entry.squash)) < 0.01, "yolk squashes, jiggles and settles (%.2f..%.2f -> %.3f)" % [squash_min, squash_max, float(floor_entry.squash)])
	var floor_yolk: Vector2 = floor_entry.yolk_pos
	check(floor_yolk.x > 0.02 and floor_yolk.length() < eggs._rim_at(rim, floor_yolk.angle()), "floor yolk rolls on along the throw and stays on the white (%.3f)" % floor_yolk.x)
	check(floor_entry.yolk_attached, "floor yolk stays in its white")
	# Body: the white creeps downhill and the yolk slides down or falls off.
	var splat := body.node as Node3D
	var down := splat.global_basis.orthonormalized().inverse() * Vector3.DOWN
	var downhill := atan2(down.z, down.x)
	var body_rim: PackedFloat32Array = body.rim
	check(eggs._rim_at(body_rim, downhill) > eggs._rim_at(body_rim, downhill + PI) + 0.03, "white creeps downhill on the body")
	if body.yolk_attached:
		check((body.yolk as Node3D).global_position.y < yolk_y_start - 0.03, "yolk slides down the body")
	else:
		check(eggs.yolks_fallen == 1, "yolk slid off the body")
		var loose := eggs.find_children("Yolk", "MeshInstance3D", true, false).filter(func(node): return node.get_parent() == eggs)
		check(loose.size() == 1, "fallen yolk is loose in the world")
		for node: MeshInstance3D in loose:
			check(absf(node.global_position.y - StageConstants.FLOOR_TOP_Y) < 0.01 and node.global_basis.y.normalized().dot(Vector3.UP) > 0.99, "fallen yolk rests upright on the conveyor")
	check(eggs.drops_landed >= 10, "sprayed liquid lands on the floor (%d)" % eggs.drops_landed)
	var end := eggs.active_counts()
	check(int(end.puddles) > 0 and int(end.puddles) <= GoalStandEggs.MAX_PUDDLES, "puddles left and capped (%d)" % int(end.puddles))
	check(int(end.shards) == 0 and int(end.drops) == 0 and int(end.drips) == 0, "debris fades out: %s" % [end])

	# Puddle cap holds under a full budget of misses.
	for i in range(18):
		eggs.launch(start, Vector3(-2.0 + i * 0.2, StageConstants.FLOOR_TOP_Y, 0.5), 0.9, null, true)
	for _frame in range(int(4.0 / STEP)):
		eggs.update(STEP, camera)
	check(int(eggs.active_counts().puddles) <= GoalStandEggs.MAX_PUDDLES, "puddle cap under load")
	print("GOAL_STAND_EGGS_STATS " + JSON.stringify(eggs.active_counts()))
	await finish(eggs, target)


func finish(eggs: GoalStandEggs, target: Node3D) -> void:
	eggs.clear()
	await get_tree().process_frame
	check(eggs.get_child_count() == 0 and target.get_child_count() == 0 and eggs.in_flight() == 0, "clear leaves nothing behind")
	print("GOAL_STAND_EGGS_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
