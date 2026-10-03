extends SceneTree

## Godot --headless --path . --script res://tests/sudden_death_bootstrap.gd
## Godot --path . --script res://tests/sudden_death_bootstrap.gd -- runtime case=<name>

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var path := "res://tests/sudden_death_unit.gd"
	if "runtime" in OS.get_cmdline_user_args():
		path = "res://tests/sudden_death_runtime.gd"
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
