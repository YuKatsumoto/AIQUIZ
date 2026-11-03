extends RefCounted
func run(ctx: Variant) -> void:
	var probe: RefCounted = load("res://tests/saw_chase_modes_runtime.gd").new()
	await probe.verify(ctx, Constants.MODE_TEN, 1)
	await probe.verify(ctx, Constants.MODE_COOP, 2)
