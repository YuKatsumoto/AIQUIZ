extends SceneTree

func _initialize() -> void:
	await process_frame
	var result: Dictionary = load("res://tests/floor_boundary_regression.gd").new().run()
	print("FLOOR_BOUNDARY_REGRESSION " + JSON.stringify(result))
	quit(0 if result.passed else 1)
