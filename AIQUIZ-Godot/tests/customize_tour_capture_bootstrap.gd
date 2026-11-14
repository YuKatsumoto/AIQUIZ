extends SceneTree

## コース⑤（カスタマイズの紹介）の画像を撮る。本体は tests/customize_tour_capture_runtime.gd（--script で読んだスクリプトは
## 自動読み込みの名前が見えないので、自動読み込みができてから読む）。ウィンドウありで流す。
##   Godot --path . --resolution 1280x720 --script tests/customize_tour_capture_bootstrap.gd
## 撮った画像は artifacts/customize_tour/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/customize_tour_capture_runtime.gd").new())
