extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var graphics_quality: Node = root.get_node("/root/GraphicsQuality")
	var game_manager: Node = root.get_node("/root/GameManager")
	var standard_enabled: bool = bool(graphics_quality.call("ghost_xray_enabled", "balanced"))
	var low_enabled: bool = bool(graphics_quality.call("ghost_xray_enabled", "low"))
	var standard_alpha: float = float(graphics_quality.call("ghost_xray_alpha", "balanced"))
	var high_alpha: float = float(graphics_quality.call("ghost_xray_alpha", "high"))

	var active_walls: Array = root.get("_active_walls")
	var original_active_walls: Array = active_walls.duplicate()
	var created_wall: bool = false # Runtime-only fixture when no live wall exists.
	if active_walls.is_empty():
		active_walls = root.get_node("WallContainer").get_children()
	var wall: Node3D = null
	for candidate: Variant in active_walls:
		if (
			candidate is Node3D
			and is_instance_valid(candidate)
			and candidate.has_method("is_solid_frame_occluding_segment")
		):
			wall = candidate as Node3D
			break
	if wall == null:
		for candidate: Node in root.get_node("WallContainer").get_children():
			if (
				candidate is Node3D
				and is_instance_valid(candidate)
				and candidate.has_method("is_solid_frame_occluding_segment")
			):
				wall = candidate as Node3D
				break
	if wall == null:
		var wall_scene: PackedScene = load("res://scenes/quiz_wall.tscn") as PackedScene
		wall = wall_scene.instantiate() as Node3D
		root.add_child(wall)
		created_wall = true
	root.set("_active_walls", [wall])

	var parts: Array = wall.get("wall_parts")
	var doors: Array = wall.get("doors")
	if parts.is_empty() or doors.is_empty():
		ctx.error("Quiz wall has no frame or answer doors")
		return
	var frame: MeshInstance3D = parts[0] as MeshInstance3D
	var door: MeshInstance3D = doors[0] as MeshInstance3D
	var frame_start: Vector3 = frame.global_transform * Vector3(0.0, 0.0, -4.0)
	var frame_end: Vector3 = frame.global_transform * Vector3(0.0, 0.0, 4.0)
	var door_start: Vector3 = door.global_transform * Vector3(0.0, 0.0, -4.0)
	var door_end: Vector3 = door.global_transform * Vector3(0.0, 0.0, 4.0)
	var frame_occludes: bool = bool(wall.call("is_solid_frame_occluding_segment", frame_start, frame_end))
	var door_occludes: bool = bool(wall.call("is_solid_frame_occluding_segment", door_start, door_end))
	var world_frame_occludes: bool = bool(root.call("is_problem_wall_occluding_segment", frame_start, frame_end))
	var world_door_occludes: bool = bool(root.call("is_problem_wall_occluding_segment", door_start, door_end))

	var test_label: Label3D = wall.call("_create_label") as Label3D
	var label_priority: int = test_label.render_priority
	var outline_priority: int = test_label.outline_render_priority
	var label_depth_tested: bool = not test_label.no_depth_test
	test_label.free()

	var old_quality: String = str(game_manager.get("graphics_quality"))
	game_manager.set("graphics_quality", "balanced")
	var stage: Node = root.get_node("StageEnvironment")
	var sharks: Array = stage.call("get_ocean_sharks")
	var material_alpha: float = -1.0
	if not sharks.is_empty():
		var shark: Node = sharks[0] as Node
		var material: StandardMaterial3D = shark.call("_create_ghost_silhouette_material") as StandardMaterial3D
		if material != null:
			material_alpha = material.albedo_color.a
	game_manager.set("graphics_quality", old_quality)

	var passed: bool = (
		standard_enabled
		and not low_enabled
		and is_equal_approx(standard_alpha, 0.52)
		and is_equal_approx(high_alpha, 0.68)
		and frame_occludes
		and world_frame_occludes
		and not door_occludes
		and not world_door_occludes
		and label_priority == 20
		and outline_priority == 19
		and label_depth_tested
		and is_equal_approx(material_alpha, 0.52)
	)
	ctx.log("ghost_xray_standard=%s alpha=%.2f high_alpha=%.2f low=%s" % [standard_enabled, standard_alpha, high_alpha, low_enabled])
	ctx.log("occlusion frame=%s/%s door=%s/%s" % [frame_occludes, world_frame_occludes, door_occludes, world_door_occludes])
	ctx.log("choice_label priority=%d outline=%d depth_tested=%s material_alpha=%.2f" % [label_priority, outline_priority, label_depth_tested, material_alpha])
	ctx.log("RESULT=%s" % ("PASS" if passed else "FAIL"))
	root.set("_active_walls", original_active_walls)
	if created_wall:
		wall.queue_free()
