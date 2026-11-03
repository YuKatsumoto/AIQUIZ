extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(2.0)
	await ctx.capture("current_magma_menu")
	ctx.log("Captured current main-menu stage.")
