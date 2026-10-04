extends SceneTree

## tests/customize_tour_capture_runtime.gd を起動する。
func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/customize_tour_capture_runtime.gd").new())
