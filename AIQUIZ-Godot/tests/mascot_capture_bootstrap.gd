extends SceneTree

## Mascot checks that need the autoloads: `-- pilot` (cockpit close-ups).

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var path := "res://tests/mascot_pilot_capture.gd"
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
