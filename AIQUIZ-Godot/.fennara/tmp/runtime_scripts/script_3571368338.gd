extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(15.0)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	ctx.log("scene=%s vsync=%d max_fps=%d refresh=%.1f screen=%s win=%s quality=%s" % [
		tree.current_scene.scene_file_path if tree.current_scene else "none",
		DisplayServer.window_get_vsync_mode(), Engine.max_fps,
		DisplayServer.screen_get_refresh_rate(), str(DisplayServer.screen_get_size()),
		str(DisplayServer.window_get_size()), GameManager.graphics_quality])
	var root: Viewport = tree.root
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var vps: Array[Node] = root.find_children("*", "SubViewport", true, false)
	for v: Node in vps:
		RenderingServer.viewport_set_measure_render_time((v as Viewport).get_viewport_rid(), true)
	await ctx.wait(1.0)
	var fps_sum: float = 0.0
	var gpu_sum: float = 0.0
	var per_vp: Dictionary = {}
	for i: int in range(60):
		await tree.process_frame
		fps_sum += Performance.get_monitor(Performance.TIME_FPS)
		gpu_sum += RenderingServer.get_frame_setup_time_cpu()
		for v: Node in vps:
			var vp: Viewport = v as Viewport
			if not is_instance_valid(vp):
				continue
			var key: String = str(vp.get_path())
			per_vp[key] = float(per_vp.get(key, 0.0)) + RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		var r: float = RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		per_vp["ROOT"] = float(per_vp.get("ROOT", 0.0)) + r
	ctx.log("avg_fps=%.1f draw_calls=%d prims=%d vram_MB=%.0f tex_MB=%.0f" % [fps_sum / 60.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
	ctx.log("root scale=%.2f msaa=%d ssaa=%d" % [root.scaling_3d_scale, root.msaa_3d, root.screen_space_aa])
	for k: String in per_vp.keys():
		var ms: float = float(per_vp[k]) / 60.0
		if ms > 0.05:
			var info: String = ""
			if k != "ROOT":
				var vp2: SubViewport = root.get_node_or_null(NodePath(k)) as SubViewport
				if vp2:
					info = " size=%s mode=%d scale=%.2f msaa=%d" % [str(vp2.size), vp2.render_target_update_mode, vp2.scaling_3d_scale, vp2.msaa_3d]
			ctx.log("gpu_ms %.2f %s%s" % [ms, k, info])
	await ctx.capture("menu")
