extends SceneTree

## Starts the PV capture runner once the autoloads exist (see tests/pv/pv_runtime.gd).

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/pv/pv_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
