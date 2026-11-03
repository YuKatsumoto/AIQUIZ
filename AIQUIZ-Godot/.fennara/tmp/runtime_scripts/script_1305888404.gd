extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(2.0)
	await ctx.capture("ocean_main_menu")
	ctx.log("Captured ocean main menu.")
