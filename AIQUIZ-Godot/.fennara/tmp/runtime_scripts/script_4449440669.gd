extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var game_manager: Node = root.get_node("/root/GameManager")
	game_manager.set("graphics_quality", "balanced")
	await ctx.restart_scene()

	root = ctx.get_scene_root()
	var stage: Node = root.get_node("StageEnvironment")
	var ocean := stage.get_node("Ocean") as MeshInstance3D
	var shader_material := ocean.material_override as ShaderMaterial
	var plane := ocean.mesh as PlaneMesh
	await ctx.wait(0.75)
	var viewport: Viewport = root.get_viewport()
	ctx.log("balanced ocean=%s subdivisions=%dx%d scale=%.2f msaa=%d fps=%d draw_calls=%d" % [
		shader_material.shader.resource_path,
		plane.subdivide_width,
		plane.subdivide_depth,
		viewport.scaling_3d_scale,
		viewport.msaa_3d,
		Engine.get_frames_per_second(),
		roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	])
	await ctx.capture("balanced_mobile_ready_world", 1280)
