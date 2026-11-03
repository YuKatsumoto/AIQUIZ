@tool
extends RefCounted

func run(ctx) -> void:
	var shark := ctx.root as Node3D
	if shark == null:
		ctx.error("Expected a 3D shark asset root")
		return
	var mesh_nodes: Array[Node] = shark.find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty():
		ctx.error("Shark asset contains no MeshInstance3D nodes")
		return

	var camera := Camera3D.new()
	camera.name = "SilhouetteTestCamera"
	camera.fov = 42.0
	camera.top_level = true
	shark.add_child(camera)

	var wall := MeshInstance3D.new()
	wall.name = "SilhouetteTestWall"
	wall.top_level = true
	var wall_mesh := BoxMesh.new()
	wall.mesh = wall_mesh
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.32, 0.34, 0.38, 1.0)
	wall_material.roughness = 0.82
	wall.material_override = wall_material
	shark.add_child(wall)

	var light := DirectionalLight3D.new()
	light.name = "SilhouetteTestLight"
	light.top_level = true
	light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	light.light_energy = 1.4
	shark.add_child(light)

	# Initialize the detached asset before reading global mesh bounds.
	await ctx.capture(shark, {"view": "front"})
	var bounds := AABB()
	var has_bounds := false
	for mesh_node: Node in mesh_nodes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null:
			continue
		var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true
	if not has_bounds:
		ctx.error("Could not determine shark mesh bounds")
		return

	var silhouette_material := StandardMaterial3D.new()
	silhouette_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	silhouette_material.albedo_color = Color(0.18, 0.68, 1.0, 0.68)
	silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	silhouette_material.emission_enabled = true
	silhouette_material.emission = Color(0.18, 0.68, 1.0, 1.0)
	silhouette_material.emission_energy_multiplier = 2.2
	silhouette_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	silhouette_material.depth_test = BaseMaterial3D.DEPTH_TEST_INVERTED
	silhouette_material.disable_fog = true
	silhouette_material.render_priority = 8
	for mesh_node: Node in mesh_nodes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_overlay = silhouette_material

	var center := bounds.get_center()
	var extent := maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z)
	camera.global_position = center + Vector3(0.0, extent * 0.12, extent * 2.4)
	camera.look_at(center, Vector3.UP)
	wall_mesh.size = Vector3(
		maxf(bounds.size.x * 0.46, extent * 0.28),
		maxf(bounds.size.y * 1.35, extent * 0.45),
		maxf(extent * 0.06, 0.04)
	)
	wall.global_position = center + Vector3(0.0, 0.0, extent * 0.42)

	wall.visible = false
	var unobstructed: Image = await ctx.capture(shark, {"camera": camera})
	wall.visible = true
	var occluded: Image = await ctx.capture(shark, {"camera": camera})
	var pages: Array[Image] = ctx.sheet(
		[unobstructed, occluded],
		{
			"columns": 2,
			"cell_size": Vector2i(560, 420),
			"labels": ["VISIBLE", "BEHIND WALL"],
			"gap": 8,
			"fit": "contain",
		}
	)
	for page: Image in pages:
		ctx.output(page, "Ghost shark normal and wall-occluded silhouette comparison")
