extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/wall_text_far_runtime.gd").new())
