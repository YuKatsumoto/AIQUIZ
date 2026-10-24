extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var test := "wall_speed_runtime.gd" if "runtime" in OS.get_cmdline_user_args() else "wall_speed_unit.gd"
	var script := load("res://tests/" + test) as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
