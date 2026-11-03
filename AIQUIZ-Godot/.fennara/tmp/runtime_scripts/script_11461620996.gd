extends RefCounted
func run(ctx: Variant) -> void:
	var probe: Script = ResourceLoader.load("res://.fennara/tmp/runtime_scripts/script_11418877439.gd", "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	await probe.new().run(ctx)
