extends SceneTree

## Frames of the menu Start pickup and departure (needs the autoloads): see tests/heli_departure_capture.gd.

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/heli_departure_capture.gd").new())
