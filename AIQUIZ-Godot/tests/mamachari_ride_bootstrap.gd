extends SceneTree

## ママチャリに乗った姿を本番の試合の画面で確かめる。本体は tests/mamachari_ride_runtime.gd
## （--script で読んだスクリプトは自動読み込みの名前が見えないので、自動読み込みができてから読む）。ウィンドウありで流す。
##   Godot --path . --resolution 1280x720 --script tests/mamachari_ride_bootstrap.gd --fixed-fps 60
## 撮った画像は artifacts/mamachari_ride/。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/mamachari_ride_runtime.gd").new())
