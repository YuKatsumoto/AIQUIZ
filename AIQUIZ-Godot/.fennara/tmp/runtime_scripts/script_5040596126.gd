extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var game_manager: Node = root.get_node("/root/GameManager")
	game_manager.set("graphics_quality", "balanced")
	await ctx.restart_scene()
	await ctx.wait(2.0)

	root = ctx.get_scene_root()
	var stage: Node = root.get_node("StageEnvironment")
	var ocean := stage.get_node("Ocean") as MeshInstance3D
	var ocean_material := ocean.material_override as ShaderMaterial
	var mesh_nodes: Array[Node] = stage.get_node("Grandstands").find_children(
		"*", "MeshInstance3D", true, false
	)
	var shadow_meshes: int = 0
	for node: Node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_meshes += 1

	var fps_samples: Array[int] = []
	var draw_samples: Array[int] = []
	for sample_index: int in range(5):
		await ctx.wait(0.25)
		fps_samples.append(Engine.get_frames_per_second())
		draw_samples.append(roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var viewport: Viewport = root.get_viewport()
	ctx.log("balanced fps=%s draw_calls=%s scale=%.2f msaa=%d shadow_meshes=%d ocean=%s" % [
		str(fps_samples), str(draw_samples), viewport.scaling_3d_scale, viewport.msaa_3d,
		shadow_meshes, ocean_material.shader.resource_path
	])
	await ctx.capture("blender_optimized_balanced_world", 1280)
