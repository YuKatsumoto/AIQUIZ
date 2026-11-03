extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(3.0)
	var root: Node = ctx.get_scene_root()
	root.call("_on_graphics_quality_selected", 2)
	await ctx.wait(2.0)
	await ctx.capture("quality_high_verified")
	root.call("_on_graphics_quality_selected", 1)
	await ctx.wait(0.5)
	ctx.log("restored_quality=%s" % GameManager.graphics_quality)
