extends SceneTree

## 地下神殿の見た目と性能（docs/sudden_death_underground.md 6.4・6.7・6.8）。ウィンドウあり（Forward+）:
##   Godot --path . --script res://tests/cistern_look_bootstrap.gd -- [quality=low|balanced|high|ultra] [shots] [perf] [frames=300]
## 画像と report.json は artifacts/sudden_death/cistern_m3/<quality>/。
## The test node is loaded after the autoloads, so it may use GameManager and the class names.

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/cistern_look_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
