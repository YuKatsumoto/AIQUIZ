extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:root.add_child(load("res://tests/saw_gantry_fold_capture.gd").new())
