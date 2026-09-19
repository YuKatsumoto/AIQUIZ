extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var path := "res://tests/helicopter_crossing_resource_check.gd" if "--resources" in OS.get_cmdline_user_args() else "res://tests/helicopter_crossing_runtime.gd"
	root.add_child(load(path).new())
