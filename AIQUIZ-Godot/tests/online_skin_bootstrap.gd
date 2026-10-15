extends SceneTree

## tests/online_skin_runtime.gd を起動する（autoload が揃ってから読み込む）。
func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/online_skin_runtime.gd").new())
