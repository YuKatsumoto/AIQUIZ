extends RefCounted

func run(ctx: Variant) -> void:
	var shark := ctx.get_scene_root() as SharkSwimmer
	if shark == null:
		ctx.error("Runtime root is not SharkSwimmer")
		ctx.close_scene()
		return
	shark.set_process(false)
	shark.position = Vector3.ZERO

	var model := shark.get_node_or_null("Model") as Node3D
	if model == null:
		ctx.error("Shark model was not found")
		ctx.close_scene()
		return
	var mesh_nodes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	var original_overlays: Dictionary = {}
	for mesh_node: Node in mesh_nodes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance != null:
			original_overlays[mesh_instance] = mesh_instance.material_overlay

	if not shark.prepare_ghost_rendezvous(2, Vector3.ZERO, Vector3.FORWARD):
		ctx.error("prepare_ghost_rendezvous failed")
		ctx.close_scene()
		return
	shark.position = Vector3.ZERO
	shark._ghost_phase = SharkSwimmer.GhostRidePhase.HOVER
	shark._update_ghost_occlusion_silhouette()

	var overlay_count := 0
	for mesh_node: Node in mesh_nodes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance != null and mesh_instance.material_overlay == shark._ghost_silhouette_material:
			overlay_count += 1
	ctx.log("silhouette enabled", {
		"registered": shark._ghost_silhouette_meshes.size(),
		"overlay_count": overlay_count,
		"phase": shark._ghost_phase,
	})
	if overlay_count != mesh_nodes.size():
		ctx.error("Not every shark mesh received the silhouette overlay")

	var bounds := AABB()
	var has_bounds := false
	for mesh_node: Node in mesh_nodes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance == null:
			continue
		var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true
	var center := bounds.get_center()
	var extent := maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z)

	var camera := Camera3D.new()
	camera.name = "RuntimeSilhouetteCamera"
	camera.top_level = true
	camera.fov = 42.0
	shark.add_child(camera)
	camera.global_position = center + Vector3(0.0, extent * 0.12, extent * 2.4)
	camera.look_at(center, Vector3.UP)
	camera.current = true

	var light := DirectionalLight3D.new()
	light.name = "RuntimeSilhouetteLight"
	light.top_level = true
	light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	light.light_energy = 1.4
	shark.add_child(light)

	var wall := MeshInstance3D.new()
	wall.name = "RuntimeSilhouetteWall"
	wall.top_level = true
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(
		maxf(bounds.size.x * 0.46, extent * 0.28),
		maxf(bounds.size.y * 1.35, extent * 0.45),
		maxf(extent * 0.06, 0.04)
	)
	wall.mesh = wall_mesh
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.32, 0.34, 0.38, 1.0)
	wall_material.roughness = 0.82
	wall.material_override = wall_material
	shark.add_child(wall)
	wall.global_position = center + Vector3(0.0, 0.0, extent * 0.42)

	wall.visible = false
	var unobstructed: Image = await ctx.frame(1280)
	wall.visible = true
	var occluded: Image = await ctx.frame(1280)
	var sheets: Array[Image] = ctx.sheet(
		[unobstructed, occluded],
		{
			"columns": 2,
			"cell_size": Vector2i(560, 315),
			"labels": ["VISIBLE", "BEHIND WALL"],
			"gap": 8,
			"fit": "contain",
		}
	)
	for sheet: Image in sheets:
		ctx.output(sheet, "Runtime ghost shark wall-occlusion silhouette comparison")

	shark.end_ghost_ride()
	var restored_count := 0
	for mesh_node: Node in mesh_nodes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance != null and mesh_instance.material_overlay == original_overlays.get(mesh_instance):
			restored_count += 1
	ctx.log("silhouette restored", {
		"restored_count": restored_count,
		"mesh_count": mesh_nodes.size(),
		"tracked_after_end": shark._ghost_silhouette_meshes.size(),
	})
	if restored_count != mesh_nodes.size() or not shark._ghost_silhouette_meshes.is_empty():
		ctx.error("Silhouette overlays were not fully restored")
	ctx.close_scene()
