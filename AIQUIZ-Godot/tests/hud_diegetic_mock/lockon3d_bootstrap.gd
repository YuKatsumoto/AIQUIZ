extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/hud_diegetic_mock/lockon3d_runtime.gd").new())
