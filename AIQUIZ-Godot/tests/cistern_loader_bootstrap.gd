extends SceneTree

## SuddenDeathLoader / CisternStage（docs/sudden_death_underground.md 5.5節・第6章）。
## 構文と生成シーンの確認（ヘッドレス）:
##   Godot --headless --path . --script res://tests/cistern_loader_bootstrap.gd -- parse
## 実際の描画での読み込み・組み立て・描画準備（ウィンドウあり。コンパイル数を数えるため）:
##   Godot --path . --script res://tests/cistern_loader_bootstrap.gd -- runtime [case=all|normal|slow_load|load_fail|cancel_restart] [quality=balanced]
## The test node is loaded after the autoloads, so it may use GameManager and the class names.

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/cistern_loader_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
