extends SceneTree

## メニュー以外の画面（設定・カスタマイズ）のボタンが、メニューと同じ金属プレート（MenuMetalButton）になっているかを撮って見る。
## 本体は tests/ui_metal_buttons_capture_runtime.gd（--script で読んだスクリプトは自動読み込みの名前が見えないので、自動読み込みができてから読む）。
##   Godot --path . --resolution 1280x720 --script res://tests/ui_metal_buttons_capture_bootstrap.gd -- tag=after
## 撮った画面は artifacts/ui_metal_buttons/<tag>_*.png。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/ui_metal_buttons_capture_runtime.gd").new())
