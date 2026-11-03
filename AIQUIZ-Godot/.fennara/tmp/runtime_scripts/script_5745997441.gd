extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(4.0)
	ctx.log("quality=%s" % GameManager.graphics_quality)
	ctx.log("settings_button=%s" % str(ctx.button_path_by_text("設定")))
	await ctx.capture("balanced_main_menu")
