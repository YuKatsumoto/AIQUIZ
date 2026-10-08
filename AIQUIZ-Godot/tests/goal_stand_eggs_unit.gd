extends Node

## Egg break physics (no gameplay). Only the shell is drawn: the egg squashes on
## the surface it hits and bursts into shell pieces that fly, bounce and come to
## rest flat before fading. No contents (white, yolk, spray) and nothing sticks to
## the target. Endless throwing keeps the live pieces capped, and clear() leaves
## nothing behind.
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
	var shards_per_egg := int(GoalStandEggs.DETAIL["high"].shards)

	var start := Vector3(4.0, StageConstants.FLOOR_TOP_Y + 5.0, -10.0)
	eggs.launch(start, target.global_position + Vector3(0.0, 0.2, 0.0), 1.0, target, false)
	eggs.launch(start, Vector3(1.5, StageConstants.FLOOR_TOP_Y, 1.0), 1.0, null, true)
	var impacts := 0
	var shard_airborne_seen := false
	var only_shell := true
	for frame in range(int(8.0 / STEP)):
		impacts += eggs.update(STEP, camera).size()
		await get_tree().process_frame
		for entry: Dictionary in eggs._shards:
			if is_instance_valid(entry.node) and (entry.node as Node3D).global_position.y > StageConstants.FLOOR_TOP_Y + 0.2:
				shard_airborne_seen = true
		for child in eggs.get_children():
			var mesh := child as MeshInstance3D
			only_shell = only_shell and mesh != null and mesh.mesh in [eggs.egg_mesh, eggs.shard_mesh]
		if frame == int(3.0 / STEP):
			check(eggs.shards_rested == shards_per_egg * 2, "all shell pieces came to rest (%d/%d)" % [eggs.shards_rested, shards_per_egg * 2])
			for entry: Dictionary in eggs._shards:
				var node := entry.node as Node3D
				check(absf(node.global_position.y - GoalStandEggs.SHARD_REST_Y) < 0.002, "resting shard sits on the conveyor")
				check(node.global_basis.y.normalized().dot(Vector3.UP) > 0.99, "resting shard lies flat")

	check(impacts == 2 and eggs.hits == 1 and eggs.misses == 1, "one hit, one miss")
	check(shard_airborne_seen, "shell pieces fly before landing")
	check(only_shell, "only the egg and its shell pieces are drawn (no contents)")
	check(target.get_child_count() == 0, "nothing sticks to the target")
	var end := eggs.active_counts()
	check(int(end.shards) == 0, "shell pieces fade out: %s" % [end])

	# Endless throwing: a long barrage keeps the live pieces capped.
	var most := 0
	for i in range(120):
		eggs.launch(start, Vector3(-2.0 + (i % 20) * 0.2, StageConstants.FLOOR_TOP_Y, 0.5), 0.9, null, true)
		for _frame in range(6):
			eggs.update(STEP, camera)
			most = maxi(most, int(eggs.active_counts().shards))
	check(most <= GoalStandEggs.MAX_SHARDS and most >= GoalStandEggs.MAX_SHARDS - shards_per_egg, "shell pieces capped under a long barrage (%d)" % most)
	await get_tree().process_frame
	var nodes := eggs.get_child_count()
	check(nodes <= GoalStandEggs.MAX_SHARDS + 20, "no node build-up under a long barrage (%d)" % nodes)
	print("GOAL_STAND_EGGS_STATS " + JSON.stringify(eggs.active_counts()))
	await finish(eggs, target)


func finish(eggs: GoalStandEggs, target: Node3D) -> void:
	eggs.clear()
	await get_tree().process_frame
	check(eggs.get_child_count() == 0 and target.get_child_count() == 0 and eggs.in_flight() == 0, "clear leaves nothing behind")
	print("GOAL_STAND_EGGS_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
