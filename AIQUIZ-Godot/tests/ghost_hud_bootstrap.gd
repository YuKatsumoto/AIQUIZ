extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/ghost_hud_runtime.gd").new())
