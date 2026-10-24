extends Node

## Egg break physics (no gameplay). The egg squashes on the surface it hits and
## bursts into shell pieces that fly, bounce and come to rest flat before fading;
## some stay stuck in the white. The raw contents come out: a hit on a blockman
## body lands on the real face of the part it reaches and rides it, a miss lies on
## the conveyor. Endless throwing keeps every kind of piece capped, nothing is
## parented under the target, and clear() leaves nothing behind.
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
	var holder := Node3D.new()
	holder.name = "Loser"
	add_child(holder)
	holder.global_position = Vector3(0.0, StageConstants.FLOOR_TOP_Y + 1.2, 0.0)
	var parts := EmoteBlockmanPreview.build_player_skeleton(true, holder, HatData.HAT_NONE)
	var target := parts.spine as Node3D
	var nodes_under_target := target.find_children("*", "", true, false).size()
	await get_tree().process_frame
	var eggs := GoalStandEggs.new()
	add_child(eggs)
	var shard := BoxMesh.new()
	shard.size = Vector3(0.07, 0.012, 0.05)
	var egg_mesh := SphereMesh.new()
	egg_mesh.radius = 0.075
	egg_mesh.height = 0.2
	eggs.setup(egg_mesh, shard, StandardMaterial3D.new(), 1234, "high")
	var shards_per_egg := int(GoalStandEggs.DETAIL["high"].shards)
	check(eggs.contents != null and eggs.contents.model != null, "contents set up with the egg's scale")
	check(absf(eggs.contents.model.scale - 0.32 / 0.057) < 0.1, "contents scale from the egg mesh (%.2f)" % eggs.contents.model.scale)
	check(GoalStandEggs.detail_level("ultra", true) == "balanced" and GoalStandEggs.detail_level("ultra", false) == "ultra", "mobile stops at balanced")

	var start := Vector3(0.5, StageConstants.FLOOR_TOP_Y + 4.0, 9.0)
	eggs.launch(start, target.global_position + Vector3(0.0, 0.2, 0.0), 1.0, target, false)
	eggs.launch(start, Vector3(1.5, StageConstants.FLOOR_TOP_Y, 1.0), 1.0, null, true)
	var impacts: Array[Dictionary] = []
	var shard_airborne_seen := false
	var body_splat_seen := false
	var floor_splat_seen := false
	var yolk_seen := false
	var on_face := false
	for frame in range(int(8.0 / STEP)):
		impacts.append_array(eggs.update(STEP, camera))
		await get_tree().process_frame
		for entry: Dictionary in eggs._shards:
			if is_instance_valid(entry.node) and (entry.node as Node3D).global_position.y > StageConstants.FLOOR_TOP_Y + 0.2:
				shard_airborne_seen = true
		var counts := eggs.active_counts()
		body_splat_seen = body_splat_seen or int(counts.body_splats) >= 1
		floor_splat_seen = floor_splat_seen or int(counts.floor_splats) >= 1
		yolk_seen = yolk_seen or int(counts.yolks) >= 1
		if frame == int(1.5 / STEP):
			for entry: Dictionary in eggs.contents.splats():
				if entry.body == null:
					continue
				var body := entry.body as GoalStandEggBody
				var box := body.shapes[int(entry.anchor.shape)].node as MeshInstance3D
				var local := box.global_transform.affine_inverse() * (entry.frame as Transform3D).origin
				var aabb := box.mesh.get_aabb()
				var gap := INF
				for axis in range(3):
					gap = minf(gap, minf(absf(local[axis] - aabb.position[axis]), absf(local[axis] - aabb.end[axis])))
				on_face = gap < 0.002 and (entry.frame as Transform3D).basis.determinant() > 0.0
		if frame == int(3.0 / STEP):
			var captured := int(eggs.active_counts().captured)
			check(eggs.shards_rested + captured == shards_per_egg * 2, "every shell piece came to rest or stuck in the white (%d + %d / %d)" % [eggs.shards_rested, captured, shards_per_egg * 2])
			for entry: Dictionary in eggs._shards:
				var node := entry.node as Node3D
				check(absf(node.global_position.y - GoalStandEggs.SHARD_REST_Y) < 0.002, "resting shard sits on the conveyor")
				check(node.global_basis.y.normalized().dot(Vector3.UP) > 0.99, "resting shard lies flat")

	check(impacts.size() == 2 and eggs.hits == 1 and eggs.misses == 1, "one hit, one miss")
	check(shard_airborne_seen, "shell pieces fly before landing")
	check(body_splat_seen, "the hit leaves a splat on the body")
	check(floor_splat_seen, "the miss leaves a splat on the conveyor")
	check(yolk_seen, "yolks come out")
	check(on_face, "the body splat sits on the face of the part it hit, right-handed")
	check(target.find_children("*", "", true, false).size() == nodes_under_target, "nothing is parented under the target")
	var end := eggs.active_counts()
	check(int(end.shards) == 0, "shell pieces fade out: %s" % [end])
	check(int(end.body_splats) >= 1 and int(end.floor_splats) >= 1, "the splats stay after the shell has gone")

	# The target moves (the loser sinks and turns): the splat rides along.
	var entry_on_body: Dictionary = {}
	for entry: Dictionary in eggs.contents.splats():
		if entry.body != null:
			entry_on_body = entry
	if not entry_on_body.is_empty():
		var box := (entry_on_body.body as GoalStandEggBody).shapes[int(entry_on_body.anchor.shape)].node as MeshInstance3D
		var local := box.global_transform.affine_inverse() * (entry_on_body.frame as Transform3D).origin
		holder.global_position += Vector3(0.3, -0.4, 0.0)
		holder.rotation.y = 0.7
		eggs.update(STEP, camera)
		await get_tree().process_frame
		var expected := box.global_transform * local
		check((entry_on_body.frame as Transform3D).origin.distance_to(expected) < 0.002, "the splat rides the moving body")
		check((entry_on_body.node as Node3D).global_position.distance_to(expected) < 0.002, "its white node follows")

	# Endless throwing: a long barrage keeps every kind of piece capped.
	var caps: Dictionary = GoalStandEggContents.DETAIL["high"]
	var most := {}
	for i in range(300):
		var miss := i % 3 == 0
		var aim := Vector3(-2.0 + (i % 20) * 0.2, StageConstants.FLOOR_TOP_Y, 0.5) if miss else target.global_position + Vector3((i % 5) * 0.08 - 0.16, 0.15 + (i % 4) * 0.08, 0.0)
		eggs.launch(start + Vector3((i % 7) * 0.3 - 1.0, 0.0, 0.0), aim, 0.9, null if miss else target, miss)
		for _frame in range(4):
			eggs.update(STEP, camera)
			var counts := eggs.active_counts()
			for key: String in counts:
				if counts[key] is int:
					most[key] = maxi(int(most.get(key, 0)), int(counts[key]))
	check(int(most.shards) <= GoalStandEggs.MAX_SHARDS, "shell pieces capped under a long barrage (%d)" % int(most.shards))
	check(int(most.body_splats) <= int(caps.body_splats) + 2, "body splats capped (%d)" % int(most.body_splats))
	check(int(most.floor_splats) <= int(caps.floor_splats) + 2, "floor splats capped (%d)" % int(most.floor_splats))
	check(int(most.puddles) <= int(caps.puddles) + 2, "puddles capped (%d)" % int(most.puddles))
	check(int(most.drips) <= int(caps.drips), "drips capped (%d)" % int(most.drips))
	check(int(most.drops) <= int(caps.drops), "drops capped (%d)" % int(most.drops))
	check(int(most.loose_yolks) <= int(caps.loose_yolks) + 1, "fallen yolks capped (%d)" % int(most.loose_yolks))
	check(int(most.rows_used) <= GoalStandEggContents.ROWS, "data rows within the texture (%d)" % int(most.rows_used))
	check(int(eggs.contents.merges) > 0, "eggs landing on a splat join it (%d merges)" % int(eggs.contents.merges))
	await get_tree().process_frame
	var nodes := eggs.get_child_count() + eggs.contents.get_child_count()
	check(nodes <= GoalStandEggs.MAX_SHARDS + 400, "no node build-up under a long barrage (%d)" % nodes)
	print("GOAL_STAND_EGGS_STATS " + JSON.stringify(eggs.active_counts()))
	print("GOAL_STAND_EGGS_PEAKS " + JSON.stringify(most))
	await finish(eggs, target, nodes_under_target)


func finish(eggs: GoalStandEggs, target: Node3D, nodes_under_target: int) -> void:
	eggs.clear()
	await get_tree().process_frame
	var counts := eggs.active_counts()
	var left := 0
	for key in ["body_splats", "floor_splats", "puddles", "drips", "drops", "strands", "loose_yolks"]:
		left += int(counts[key])
	check(eggs.get_child_count() == 1 and eggs.contents.get_child_count() == 0 and left == 0 and eggs.in_flight() == 0,
		"clear leaves nothing behind (%d, %d, %d)" % [eggs.get_child_count(), eggs.contents.get_child_count(), left])
	check(target.find_children("*", "", true, false).size() == nodes_under_target, "the target is left as it was")
	print("GOAL_STAND_EGGS_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
