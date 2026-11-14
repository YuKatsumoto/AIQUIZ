extends SceneTree

## カスタマイズ画面のシークレット枠（ママチャリ）と解放の知らせを確かめる。本体は tests/secret_ride_ui_runtime.gd
## （--script で読んだスクリプトは自動読み込みの名前が見えないので、自動読み込みができてから読む）。ウィンドウありで流す。
##   Godot --path . --resolution 1280x720 --script tests/secret_ride_ui_bootstrap.gd
## 撮った画像は artifacts/secret_ride_ui/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/secret_ride_ui_runtime.gd").new())
