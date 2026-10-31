extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/hud_diegetic_mock/lockon_video_runtime.gd").new())
