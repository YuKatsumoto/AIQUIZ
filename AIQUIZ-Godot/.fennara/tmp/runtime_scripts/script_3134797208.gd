extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(1.5)
	await ctx.capture("clear_water")
