extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(3.0)
	var root: Node = ctx.get_scene_root()
	root.call("_on_graphics_quality_selected", 0)
	await ctx.wait(1.0)
	ctx.log("capture_quality=%s" % GameManager.graphics_quality)
	await ctx.capture("quality_low")
	root.call("_on_graphics_quality_selected", 2)
	await ctx.wait(1.0)
	ctx.log("capture_quality=%s" % GameManager.graphics_quality)
	await ctx.capture("quality_high")
	root.call("_on_graphics_quality_selected", 1)
	await ctx.wait(1.0)
	ctx.log("restored_quality=%s" % GameManager.graphics_quality)
	await ctx.capture("quality_balanced")
