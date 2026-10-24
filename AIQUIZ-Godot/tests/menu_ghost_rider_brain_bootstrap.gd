extends SceneTree
func _initialize() -> void:call_deferred("boot")
func boot() -> void:
	root.add_child(load("res://tests/menu_ghost_rider_brain_unit.gd").new())
