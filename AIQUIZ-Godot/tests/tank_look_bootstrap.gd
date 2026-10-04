extends SceneTree

## 地下ステージ（調圧水槽の再現、docs/surge_tank_reproduction.md）の見た目と重さ。ウィンドウあり（Forward+）:
##   Godot --path . --script res://tests/tank_look_bootstrap.gd -- [quality=low|balanced|high|ultra] [shots] [perf] [frames=240]
## 画像と report.json は artifacts/surge_tank/<quality>/。
## The test node is loaded after the autoloads, so it may use GameManager and the class names.

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/tank_look_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
