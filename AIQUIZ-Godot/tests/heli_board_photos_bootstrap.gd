extends SceneTree

## Photos for the helicopter's rear cork board (needs the autoloads): see tests/heli_board_photos.gd.

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/heli_board_photos.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
