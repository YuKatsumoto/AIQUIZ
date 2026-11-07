extends SceneTree

## カウントダウンの壁が、問題の読み込みが終わるまで落ちないことの実機テスト:
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/barrier_preload_bootstrap.gd
## 詳細は barrier_preload_runtime.gd。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/barrier_preload_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("barrier_preload_runtime.gd failed to load")
		quit(1)
		return
	root.add_child(script.new())
