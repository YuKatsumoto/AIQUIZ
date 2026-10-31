extends SceneTree

## コース③（2人対戦）の実機の通しテスト。本体は tests/practice_course3_smoke_runtime.gd（--script で読んだスクリプトは
## 自動読み込みの名前が見えないので、自動読み込みができてから読む）。ウィンドウありで流して画面を撮る。
##   Godot --path . --script tests/practice_course3_smoke_bootstrap.gd
## 撮った画面は artifacts/practice_course3/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/practice_course3_smoke_runtime.gd").new())
