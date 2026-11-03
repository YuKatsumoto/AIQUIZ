extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.restart_scene()
	var frames: Array[Image] = []
	var labels: Array[String] = []
	var sample_times: Array[float] = [0.5, 4.5, 5.5, 8.3, 11.2]
	var previous := 0.0
	for sample_time: float in sample_times:
		await ctx.wait(sample_time - previous)
		previous = sample_time
		frames.append(await ctx.frame())
		labels.append("%.1fs" % sample_time)
	var pages: Array[Image] = ctx.sheet(frames, {
		"columns": 5,
		"cell_size": Vector2i(384, 216),
		"labels": labels,
	})
	for page: Image in pages:
		ctx.output(page, "Main-menu authored helicopter arrival")
	var root: Node = ctx.get_scene_root()
	var director: Node = root.find_child("MenuHelicopterArrivalDirector", true, false)
	ctx.log("arrival_director_present=%s" % str(director != null))
