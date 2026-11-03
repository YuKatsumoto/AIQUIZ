extends RefCounted

func run(ctx: Variant) -> void:
	var min_fps: float = 999999.0
	var max_fps: float = 0.0
	var sum_fps: float = 0.0
	var frame_ms: float = 0.0
	var draw_calls: float = 0.0
	var primitives: float = 0.0
	var nodes: float = 0.0
	var physics_bodies: float = 0.0
	var sample_index: int = 0
	for sample_index in range(5):
		await ctx.wait(1.0)
		var fps: float = Performance.get_monitor(Performance.TIME_FPS)
		min_fps = minf(min_fps, fps)
		max_fps = maxf(max_fps, fps)
		sum_fps += fps
		frame_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		physics_bodies = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
	ctx.log("perf avg_fps=%.1f min_fps=%.1f max_fps=%.1f frame_ms=%.2f draw_calls=%.0f primitives=%.0f nodes=%.0f active_3d_bodies=%.0f" % [sum_fps / 5.0, min_fps, max_fps, frame_ms, draw_calls, primitives, nodes, physics_bodies])
