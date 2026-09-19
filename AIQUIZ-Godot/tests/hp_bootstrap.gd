extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var test := "hp_unit.gd"
	for arg in OS.get_cmdline_user_args():
		if arg == "runtime": test = "hp_runtime.gd"
		if arg.begins_with("network="): test = "hp_network.gd"
	var script := load("res://tests/" + test) as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
