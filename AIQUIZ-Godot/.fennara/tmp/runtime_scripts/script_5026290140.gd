extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(2.0)
	var root: Node = ctx.get_scene_root()
	var stage: Node = root.get_node("StageEnvironment")
	var grandstands: Node = stage.get_node("Grandstands")
	var mesh_nodes: Array[Node] = grandstands.find_children("*", "MeshInstance3D", true, false)
	var vertices: int = 0
	var triangles: int = 0
	var shadow_meshes: int = 0
	for node: Node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_meshes += 1
		if mesh_instance.mesh == null:
			continue
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
			var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			vertices += surface_vertices.size()
			triangles += floori(float(indices.size()) / 3.0)

	var fps_samples: Array[int] = []
	var draw_samples: Array[int] = []
	for sample_index: int in range(5):
		await ctx.wait(0.25)
		fps_samples.append(Engine.get_frames_per_second())
		draw_samples.append(roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var viewport: Viewport = root.get_viewport()
	var game_manager: Node = root.get_node("/root/GameManager")
	ctx.log("quality=%s grandstand_meshes=%d vertices=%d triangles=%d shadow_meshes=%d" % [
		str(game_manager.get("graphics_quality")), mesh_nodes.size(), vertices, triangles, shadow_meshes
	])
	ctx.log("fps=%s draw_calls=%s scale=%.2f msaa=%d" % [
		str(fps_samples), str(draw_samples), viewport.scaling_3d_scale, viewport.msaa_3d
	])
	await ctx.capture("blender_optimized_game_world", 1280)
