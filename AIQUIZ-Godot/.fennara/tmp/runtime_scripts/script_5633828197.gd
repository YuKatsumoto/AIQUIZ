extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(2.0)
	var fps_samples: Array[float] = []
	var frame_ms_samples: Array[float] = []
	var draw_samples: Array[float] = []
	var primitive_samples: Array[float] = []
	for i: int in range(24):
		fps_samples.append(Performance.get_monitor(Performance.TIME_FPS))
		frame_ms_samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draw_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitive_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		await ctx.wait(0.25)
	var fps_total: float = 0.0
	var fps_min: float = 1000000.0
	var frame_total: float = 0.0
	var frame_max: float = 0.0
	var draw_total: float = 0.0
	var primitive_total: float = 0.0
	for value: float in fps_samples:
		fps_total += value
		fps_min = minf(fps_min, value)
	for value: float in frame_ms_samples:
		frame_total += value
		frame_max = maxf(frame_max, value)
	for value: float in draw_samples:
		draw_total += value
	for value: float in primitive_samples:
		primitive_total += value
	var count: float = float(fps_samples.size())
	ctx.log("quality=%s" % GameManager.graphics_quality)
	ctx.log("fps_avg=%.1f fps_min=%.1f" % [fps_total / count, fps_min])
	ctx.log("frame_ms_avg=%.2f frame_ms_max=%.2f" % [frame_total / count, frame_max])
	ctx.log("draw_calls_avg=%.1f primitives_avg=%.0f nodes=%d" % [
		draw_total / count,
		primitive_total / count,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	])
	await ctx.capture("balanced_game_world")
