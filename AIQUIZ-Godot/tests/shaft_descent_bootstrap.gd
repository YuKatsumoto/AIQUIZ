extends SceneTree

## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/shaft_descent_bootstrap.gd [-- quality=balanced shots=b,c perf]
## Windowed (headless cannot render). Images go to artifacts/sudden_death/shaft/.

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var script := load("res://tests/shaft_descent_preview.gd") as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
