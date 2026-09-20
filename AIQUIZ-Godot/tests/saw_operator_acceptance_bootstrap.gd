extends SceneTree
func _initialize() -> void:
	call_deferred("boot")
func boot() -> void:
	root.add_child(load("res://tests/saw_operator_acceptance.gd").new())
