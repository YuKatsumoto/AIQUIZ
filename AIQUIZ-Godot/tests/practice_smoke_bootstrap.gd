extends SceneTree

## 練習（新チュートリアル）の土台の実機テスト。本体は tests/practice_smoke_runtime.gd（--script で読んだスクリプトは
## 自動読み込みの名前が見えないので、自動読み込みができてから読む）。ウィンドウありで流して画面を撮る。
##   Godot --path . --script tests/practice_smoke_bootstrap.gd
## 撮った画面は artifacts/practice_smoke/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/practice_smoke_runtime.gd").new())
