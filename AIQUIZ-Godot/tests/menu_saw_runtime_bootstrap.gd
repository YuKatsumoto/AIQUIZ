extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:root.add_child(load("res://tests/menu_saw_runtime.gd").new())
