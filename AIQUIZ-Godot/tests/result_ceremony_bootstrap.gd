extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var path := "res://tests/result_ceremony_unit.gd"
	if "runtime" in OS.get_cmdline_user_args():
		path = "res://tests/result_ceremony_runtime.gd"
	if "referee_unit" in OS.get_cmdline_user_args():
		path = "res://tests/result_referee_unit.gd"
	if "emote_orientation" in OS.get_cmdline_user_args():
		path = "res://tests/result_emote_orientation.gd"
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
