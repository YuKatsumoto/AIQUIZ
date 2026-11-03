extends SceneTree

## Godot --headless --path . --script res://tests/claude_live_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/claude_live_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
