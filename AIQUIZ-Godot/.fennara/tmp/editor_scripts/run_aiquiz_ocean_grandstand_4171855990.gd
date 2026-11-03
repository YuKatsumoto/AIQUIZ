@tool
extends RefCounted

func run(ctx) -> void:
	var image: Image = await ctx.capture(ctx.root, {"view": "perspective"})
	ctx.output(image, "Original grandstand asset")
