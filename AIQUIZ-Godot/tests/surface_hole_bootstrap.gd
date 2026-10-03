extends SceneTree

## Godot --path . --script res://tests/surface_hole_bootstrap.gd --fixed-fps 60
## Godot --path . --script res://tests/surface_hole_bootstrap.gd --fixed-fps 60 -- quality=low stage=env

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/surface_hole_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
