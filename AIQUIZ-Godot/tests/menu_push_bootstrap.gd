extends SceneTree
## tests/menu_push_runtime.gd を単独で回す（本体は tests/menu_push_driver.gd。オートロードはここではまだ読めない）。
func _initialize() -> void:call_deferred("boot")
func boot() -> void:
	root.add_child(load("res://tests/menu_push_driver.gd").new())
