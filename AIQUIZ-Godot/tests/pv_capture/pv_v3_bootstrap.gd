extends SceneTree

## PV 冒頭 S01〜S03 の新しい流れ（絵コンテ v3）の撮影。本物の GameWorld を動かし、カメラ・入力・時間の速さ・演技だけを外から決める。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_v3_bootstrap.gd -- quality=ultra
## 動きのブレ付き（1 フレームを 4 回に分ける）: --fixed-fps 240 ... -- quality=ultra sub=4
## 引数と撮るものは pv_v3_runtime.gd。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/pv_capture/pv_v3_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("pv_v3_runtime.gd failed to load")
		quit(1)
		return
	root.add_child(script.new())
