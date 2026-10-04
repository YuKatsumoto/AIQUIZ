extends SceneTree

## Godot --headless --path . --script res://tests/sudden_death_bootstrap.gd
## Godot --path . --script res://tests/sudden_death_bootstrap.gd -- runtime case=<name>

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	# The game has the sudden death switched off for now (docs 20); its tests still run it.
	# Loaded here, not named: naming QuizGameState compiles it before the autoloads exist.
	(load("res://scripts/core/game_state.gd") as GDScript).set("sudden_death_available", true)
	var path := "res://tests/sudden_death_unit.gd"
	if "runtime" in OS.get_cmdline_user_args():
		path = "res://tests/sudden_death_runtime.gd"
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		quit(1)
		return
	root.add_child(script.new())
