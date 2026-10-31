extends SceneTree

## 練習の舞台の小物（看板の壁・床の印・的のマーク・ハテナの動き）の見た目の確かめ。本体は
## tests/practice_props_preview_runtime.gd（--script で読んだスクリプトは自動読み込みの名前が見えないので、
## 自動読み込みができてから読む）。ウィンドウありで流して画面を撮る。
##   Godot --path . --script tests/practice_props_preview_bootstrap.gd
## 撮った画面は artifacts/practice_props/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/practice_props_preview_runtime.gd").new())
