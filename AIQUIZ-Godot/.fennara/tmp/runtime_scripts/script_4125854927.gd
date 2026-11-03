extends RefCounted

func run(ctx: Variant) -> void:
	var world := ctx.get_scene_root() as Node3D
	if world == null or not world.has_method("is_problem_wall_occluding_segment"):
		ctx.error("GameWorld occlusion API was not found")
		ctx.close_scene()
		return
	world.set_process(false)
	var active_walls_variant: Variant = world.get("_active_walls")
	if not (active_walls_variant is Array):
		ctx.error("GameWorld active wall list was not available")
		ctx.close_scene()
		return
	var active_walls: Array = active_walls_variant
	active_walls.clear()

	var fixture_wall := Node3D.new()
	fixture_wall.name = "OcclusionFixtureWall"
	var fixture_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 3.0, 0.5)
	fixture_mesh.mesh = box
	fixture_wall.add_child(fixture_mesh)
	world.add_child(fixture_wall)
	active_walls.append(fixture_wall)

	var hit: bool = world.call(
		"is_problem_wall_occluding_segment",
		Vector3(0.0, 0.0, 5.0),
		Vector3(0.0, 0.0, -5.0)
	)
	var miss: bool = world.call(
		"is_problem_wall_occluding_segment",
		Vector3(3.0, 0.0, 5.0),
		Vector3(3.0, 0.0, -5.0)
	)
	fixture_wall.visible = false
	var hidden_wall_hit: bool = world.call(
		"is_problem_wall_occluding_segment",
		Vector3(0.0, 0.0, 5.0),
		Vector3(0.0, 0.0, -5.0)
	)
	ctx.log("wall_intersection hit=%s miss=%s hidden=%s" % [hit, miss, hidden_wall_hit])
	if not hit or miss or hidden_wall_hit:
		ctx.error("Problem wall segment intersection gate returned an unexpected result")
	ctx.close_scene()
