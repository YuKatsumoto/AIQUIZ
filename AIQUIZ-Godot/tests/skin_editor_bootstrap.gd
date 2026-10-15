extends SceneTree

## tests/skin_editor_runtime.gd を起動する（autoload が揃ってから読み込む）。
func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/skin_editor_runtime.gd").new())
