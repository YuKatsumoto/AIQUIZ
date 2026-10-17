extends SceneTree

## Godot --path . --fixed-fps 60 --script res://tests/preload_progress_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/preload_progress_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
