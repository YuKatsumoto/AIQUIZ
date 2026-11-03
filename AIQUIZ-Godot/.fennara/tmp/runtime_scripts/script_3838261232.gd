extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	if root == null:
		ctx.error("no root")
		return
	await ctx.wait(1.0)
	var samples: int = 90
	var fps_min: float = 9999.0
	var fps_max: float = 0.0
	var fps_sum: float = 0.0
	var draw_sum: float = 0.0
	var obj_sum: float = 0.0
	var prim_sum: float = 0.0
	var process_sum: float = 0.0
	var physics_sum: float = 0.0
	for _i: int in range(samples):
		var fps: float = float(Performance.get_monitor(Performance.TIME_FPS))
		var draw: float = float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var objs: float = float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		var prims: float = float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var proc_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		var phys_ms: float = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		fps_min = minf(fps_min, fps)
		fps_max = maxf(fps_max, fps)
		fps_sum += fps
		draw_sum += draw
		obj_sum += objs
		prim_sum += prims
		process_sum += proc_ms
		physics_sum += phys_ms
		await ctx.wait(0.0)
	var mi_count: int = 0
	var multi_count: int = 0
	var label3d_count: int = 0
	var node_count: int = 0
	var grandstand_meshes: int = 0
	var grandstand_nodes: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		node_count += 1
		if n is MeshInstance3D:
			mi_count += 1
		if n is MultiMeshInstance3D:
			multi_count += 1
		if n is Label3D:
			label3d_count += 1
		var under_grand: bool = false
		var walk: Node = n
		while walk != null:
			var walk_name: String = String(walk.name)
			if walk_name.begins_with("Grandstand") or walk_name == "Grandstands":
				under_grand = true
				break
			walk = walk.get_parent()
		if under_grand:
			grandstand_nodes += 1
			if n is MeshInstance3D:
				grandstand_meshes += 1
		for c: Node in n.get_children():
			stack.append(c)
	var quality: String = str(GameManager.graphics_quality)
	var vp: Viewport = root.get_viewport()
	var glow_on: bool = false
	var stage_env: Node = root.get_node_or_null("StageEnvironment")
	if stage_env != null:
		var we: WorldEnvironment = stage_env.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we != null and we.environment != null:
			glow_on = we.environment.glow_enabled
	ctx.log("quality=%s msaa3d=%s scale3d=%.2f glow=%s" % [
		quality,
		str(vp.msaa_3d),
		vp.scaling_3d_scale,
		str(glow_on),
	])
	ctx.log("fps avg=%.1f min=%.1f max=%.1f" % [fps_sum / float(samples), fps_min, fps_max])
	ctx.log("draw avg=%.0f objects avg=%.0f prims avg=%.0f" % [draw_sum / float(samples), obj_sum / float(samples), prim_sum / float(samples)])
	ctx.log("process_ms avg=%.2f physics_ms avg=%.2f" % [process_sum / float(samples), physics_sum / float(samples)])
	ctx.log("nodes=%d mesh_instances=%d multimersh=%d label3d=%d" % [node_count, mi_count, multi_count, label3d_count])
	ctx.log("grandstand_nodes=%d grandstand_mesh_instances=%d" % [grandstand_nodes, grandstand_meshes])
	if stage_env == null:
		return
	var gs: Node3D = stage_env.get_node_or_null("Grandstands") as Node3D
	var ocean: Node3D = stage_env.get_node_or_null("Ocean") as Node3D
	if gs != null:
		gs.visible = false
		ctx.log("hid Grandstands for A/B")
		await ctx.wait(0.5)
		var fps2_sum: float = 0.0
		var draw2_sum: float = 0.0
		var prim2_sum: float = 0.0
		var fps2_min: float = 9999.0
		for _j: int in range(samples):
			var fps2: float = float(Performance.get_monitor(Performance.TIME_FPS))
			fps2_min = minf(fps2_min, fps2)
			fps2_sum += fps2
			draw2_sum += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			prim2_sum += float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			await ctx.wait(0.0)
		ctx.log("NO_GRAND fps avg=%.1f min=%.1f draw avg=%.0f prims avg=%.0f" % [
			fps2_sum / float(samples), fps2_min, draw2_sum / float(samples), prim2_sum / float(samples)
		])
		gs.visible = true
		await ctx.wait(0.3)
	if ocean != null:
		ocean.visible = false
		ctx.log("hid Ocean for A/B (grandstands visible)")
		await ctx.wait(0.5)
		var fps3_sum: float = 0.0
		var draw3_sum: float = 0.0
		for _k: int in range(samples):
			fps3_sum += float(Performance.get_monitor(Performance.TIME_FPS))
			draw3_sum += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			await ctx.wait(0.0)
		ctx.log("NO_OCEAN fps avg=%.1f draw avg=%.0f" % [fps3_sum / float(samples), draw3_sum / float(samples)])
		ocean.visible = true
	if gs != null and ocean != null:
		gs.visible = false
		ocean.visible = false
		await ctx.wait(0.5)
		var fps4_sum: float = 0.0
		var draw4_sum: float = 0.0
		for _m: int in range(samples):
			fps4_sum += float(Performance.get_monitor(Performance.TIME_FPS))
			draw4_sum += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			await ctx.wait(0.0)
		ctx.log("NO_GRAND_NO_OCEAN fps avg=%.1f draw avg=%.0f" % [fps4_sum / float(samples), draw4_sum / float(samples)])
		gs.visible = true
		ocean.visible = true
