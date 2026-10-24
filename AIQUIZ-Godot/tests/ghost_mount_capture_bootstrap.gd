extends SceneTree

## ゴーストシャーク搭乗の連番撮影（tests/ghost_mount_capture_runtime.gd）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/ghost_mount_capture_bootstrap.gd -- tag=before
func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/ghost_mount_capture_runtime.gd").new())
