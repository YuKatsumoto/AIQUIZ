extends SceneTree

## tests/ghost_mount_probe.gd を動かす。
func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/ghost_mount_probe.gd").new())
