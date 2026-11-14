extends SceneTree

## 画面ありで動かす：
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/fresh_pc_pipeline_runtime_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/fresh_pc_pipeline_runtime.gd").new())
