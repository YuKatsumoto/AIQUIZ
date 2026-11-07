extends SceneTree

## エンドレスのコースが地平線まで続いて見えるかの撮影。ウィンドウあり（Forward+）、1280x720 固定:
##   Godot --path . --script res://tests/endless_horizon_bootstrap.gd --fixed-fps 60 -- tag=after
## 画像と report.json は artifacts/endless_horizon/<tag>/<quality>/。詳細は endless_horizon_runtime.gd。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/endless_horizon_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("endless_horizon_runtime.gd failed to load")
		quit(1)
		return
	root.add_child(script.new())
