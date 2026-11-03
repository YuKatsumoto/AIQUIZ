extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(2.0)
	var fps_samples: Array[int] = []
	var draw_samples: Array[int] = []
	for sample_index: int in range(5):
		await ctx.wait(0.25)
		fps_samples.append(Engine.get_frames_per_second())
		draw_samples.append(roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	ctx.log("balanced settled fps=%s draw_calls=%s" % [str(fps_samples), str(draw_samples)])
