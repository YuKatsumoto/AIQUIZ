extends SceneTree
func _initialize() -> void:
	await process_frame
	var suite: RefCounted = load("res://tools/fixtures/choice_contract_cases.gd").new()
	var failures: int = suite.run()
	quit(0 if failures == 0 else 1)
