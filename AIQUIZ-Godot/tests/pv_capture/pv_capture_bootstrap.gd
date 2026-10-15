extends SceneTree

## PV（ゲームクリエイター甲子園2026）の撮影。本物の GameWorld を動かし、カメラ・入力・時間の速さだけを外から決める。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_capture_bootstrap.gd -- quality=ultra
## 引数と撮るものは pv_capture_runtime.gd。
## The test node is loaded after the autoloads, so it may use GameManager and the class names.

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/pv_capture/pv_capture_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("pv_capture_runtime.gd failed to load")
		quit(1)
		return
	root.add_child(script.new())
