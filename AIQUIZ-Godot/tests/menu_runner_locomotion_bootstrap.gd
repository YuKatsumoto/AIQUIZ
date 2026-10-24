extends SceneTree
func _initialize() -> void:call_deferred("boot")
func boot() -> void:
	root.add_child(load("res://tests/menu_runner_locomotion_runtime.gd").new())
