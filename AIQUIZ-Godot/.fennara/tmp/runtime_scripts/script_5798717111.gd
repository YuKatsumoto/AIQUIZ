extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.click_button("SettingsBtn")
	await ctx.wait(1.0)
	await ctx.capture("balanced_settings_panel")
