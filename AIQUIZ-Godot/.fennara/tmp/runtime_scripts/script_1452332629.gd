extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(1.5)
	await ctx.capture("ocean_main_menu_final")
