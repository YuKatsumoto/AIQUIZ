extends SceneTree

## エンドレスの2人の両者脱落の結果発表を結果発表アリーナで行うことを、本物の GameWorld で確かめて撮る:
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script res://tests/result_arena_bootstrap.gd -- quality=high
##   （10問の両者脱落はアリーナを使わず、ハテナの投げ縄でコースのゴールへ運ぶ：tests/elimination_lasso_bootstrap.gd）
## 画像と report.json は artifacts/result_arena/runtime/endless[_draw]/。詳細は result_arena_runtime.gd。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/result_arena_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("result_arena_runtime.gd failed to load")
		quit(1)
		return
	root.add_child(script.new())
