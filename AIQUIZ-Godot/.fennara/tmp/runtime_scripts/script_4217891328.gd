extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var preview: Node = null
	for node: Node in root.find_children("*", "Node", true, false):
		if node.has_method("begin_game_start_departure"):
			preview = node
			break
	if preview == null:
		ctx.error("menu preview controller not found")
		return
	if not bool(preview.call("begin_game_start_departure", 2)):
		ctx.error("pickup did not start")
		return
	var frames: Array[Image] = []
	var labels: Array[String] = []
	var sample_times: Array[float] = [0.2, 0.82, 1.4, 2.4, 2.9]
	var previous := 0.0
	for sample_time: float in sample_times:
		await ctx.wait(sample_time - previous)
		previous = sample_time
		frames.append(await ctx.frame())
		labels.append("%.2fs" % sample_time)
	var pages: Array[Image] = ctx.sheet(frames, {
		"columns": 5,
		"cell_size": Vector2i(384, 216),
		"labels": labels,
	})
	for page: Image in pages:
		ctx.output(page, "Main-menu authored helicopter pickup")
	var active := bool(preview.call("is_game_start_departure_active"))
	ctx.log("pickup_active_after_2_9s=%s" % str(active))
