extends SceneTree

## ゴーストシャークの突進が生き残り側に当たる瞬間の連番撮影と計測（tests/ghost_hit_capture_runtime.gd）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/ghost_hit_capture_bootstrap.gd -- tag=center hit=center power=1.0
func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/ghost_hit_capture_runtime.gd").new())
