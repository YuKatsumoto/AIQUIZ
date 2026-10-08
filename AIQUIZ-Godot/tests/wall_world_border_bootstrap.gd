extends SceneTree

func _initialize() -> void:
	await process_frame
	var result: Dictionary = load("res://tests/wall_world_border_regression.gd").new().run()
	print("WALL_WORLD_BORDER_REGRESSION " + JSON.stringify(result))
	quit(0 if result.passed else 1)
