extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var wall_scene: PackedScene = load("res://scenes/quiz_wall.tscn") as PackedScene
	var wall: Node3D = wall_scene.instantiate() as Node3D
	root.add_child(wall)
	var frame: MeshInstance3D = wall.get("wall_parts")[0] as MeshInstance3D
	var door: MeshInstance3D = wall.get("doors")[0] as MeshInstance3D
	var frame_start: Vector3 = frame.global_transform * Vector3(0.0, 0.0, -4.0)
	var frame_end: Vector3 = frame.global_transform * Vector3(0.0, 0.0, 4.0)
	var door_start: Vector3 = door.global_transform * Vector3(0.0, 0.0, -4.0)
	var door_end: Vector3 = door.global_transform * Vector3(0.0, 0.0, 4.0)
	var original: Array[Node3D] = root.get("_active_walls")
	var test_walls: Array[Node3D] = [wall]
	root.set("_active_walls", test_walls)
	var frame_direct: bool = bool(wall.call("is_solid_frame_occluding_segment", frame_start, frame_end))
	var door_direct: bool = bool(wall.call("is_solid_frame_occluding_segment", door_start, door_end))
	var frame_world: bool = bool(root.call("is_problem_wall_occluding_segment", frame_start, frame_end))
	var door_world: bool = bool(root.call("is_problem_wall_occluding_segment", door_start, door_end))
	ctx.log("wall visible=%s retiring=%s active=%d" % [wall.is_visible_in_tree(), wall.call("is_retiring_after_pass"), (root.get("_active_walls") as Array).size()])
	ctx.log("frame direct/world=%s/%s door direct/world=%s/%s" % [frame_direct, frame_world, door_direct, door_world])
	ctx.log("RESULT=%s" % ("PASS" if frame_direct and frame_world and not door_direct and not door_world else "FAIL"))
	root.set("_active_walls", original)
	wall.queue_free()
