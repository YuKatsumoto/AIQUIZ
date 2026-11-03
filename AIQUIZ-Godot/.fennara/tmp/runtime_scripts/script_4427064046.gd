extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var stage: Node = root.get_node_or_null("StageEnvironment")
	if stage == null:
		ctx.error("StageEnvironment missing")
		return
	var grandstands: Node = stage.get_node_or_null("Grandstands")
	var batched_nodes: Array[Node] = grandstands.find_children("*", "MultiMeshInstance3D", true, false)
	var instance_total: int = 0
	var triangle_total: int = 0
	for node: Node in batched_nodes:
		var renderer := node as MultiMeshInstance3D
		var multi_mesh: MultiMesh = renderer.multimesh
		if multi_mesh == null or multi_mesh.mesh == null:
			continue
		instance_total += multi_mesh.instance_count
		var mesh: Mesh = multi_mesh.mesh
		var box_triangles: int = 0
		for surface_index: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			box_triangles += floori(float(indices.size()) / 3.0)
		triangle_total += box_triangles * multi_mesh.instance_count
	var dense_seats: Array[Node] = root.find_children("*Grandstand_Seats_LOD0*", "", true, false)
	var ocean := stage.get_node_or_null("Ocean") as MeshInstance3D
	var ocean_shader_path: String = ""
	var ocean_subdivisions: Vector2i = Vector2i.ZERO
	if ocean != null and ocean.mesh is PlaneMesh:
		var plane := ocean.mesh as PlaneMesh
		ocean_subdivisions = Vector2i(plane.subdivide_width, plane.subdivide_depth)
		var shader_material := ocean.material_override as ShaderMaterial
		if shader_material != null and shader_material.shader != null:
			ocean_shader_path = shader_material.shader.resource_path

	var fps_samples: Array[float] = []
	var draw_samples: Array[float] = []
	var primitive_samples: Array[float] = []
	for sample_index: int in range(5):
		await ctx.wait(0.25)
		fps_samples.append(float(Engine.get_frames_per_second()))
		draw_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitive_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var viewport: Viewport = root.get_viewport()
	ctx.log("grandstands=%d multimeshes=%d instances=%d estimated_triangles=%d dense_seat_nodes=%d" % [
		grandstands.get_child_count(), batched_nodes.size(), instance_total, triangle_total, dense_seats.size()
	])
	ctx.log("ocean_subdivisions=%s shader=%s" % [str(ocean_subdivisions), ocean_shader_path])
	ctx.log("viewport scale=%.2f msaa3d=%d screen_aa=%d lod_threshold=%.2f" % [
		viewport.scaling_3d_scale, viewport.msaa_3d, viewport.screen_space_aa, viewport.mesh_lod_threshold
	])
	ctx.log("samples fps=%s draw_calls=%s primitives=%s" % [
		str(fps_samples), str(draw_samples), str(primitive_samples)
	])
	await ctx.capture("optimized_game_world", 1280)
