extends RefCounted

func run(ctx: Variant) -> void:
	Engine.max_fps = 60
	await ctx.wait(1.0)
	ctx.log("capped fps=%.1f" % Performance.get_monitor(Performance.TIME_FPS))
