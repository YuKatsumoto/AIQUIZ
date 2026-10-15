extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/ladder_release_runtime.gd").new())
