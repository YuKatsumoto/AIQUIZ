extends RefCounted
func run(ctx: Variant) -> void:
	await (ResourceLoader.load("res://.fennara/tmp/runtime_scripts/script_11607234065.gd", "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as Script).new().run(ctx)
