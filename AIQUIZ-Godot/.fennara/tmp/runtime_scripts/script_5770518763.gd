extends RefCounted

func run(ctx: Variant) -> void:
	ctx.log("settings_button=%s" % str(ctx.button_path_by_text("設定 / API状態")))
	await ctx.click_button("設定 / API状態")
	await ctx.wait(1.0)
	await ctx.capture("balanced_settings")
