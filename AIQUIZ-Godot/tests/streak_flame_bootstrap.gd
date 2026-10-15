extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/streak_flame_runtime.gd").new())
