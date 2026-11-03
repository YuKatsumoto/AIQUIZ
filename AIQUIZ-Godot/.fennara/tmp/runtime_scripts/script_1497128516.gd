extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(1.2)
	await ctx.capture("ocean_customize")
