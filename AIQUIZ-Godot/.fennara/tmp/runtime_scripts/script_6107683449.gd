extends RefCounted

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	root.call("_on_graphics_quality_selected", 2)
	var live: Viewport = root.get("live_viewport") as Viewport
	if live:
		live.use_debanding = false
	await ctx.wait(2.0)
	await ctx.capture("quality_high_no_debanding")
	root.call("_on_graphics_quality_selected", 1)
	await ctx.wait(0.5)
