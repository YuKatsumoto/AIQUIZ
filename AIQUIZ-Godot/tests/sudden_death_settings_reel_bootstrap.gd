extends SceneTree

## The sudden death's setting, match record, LED labels, scoreboard cut-ins and goal
## stand crowd refresh (tests/sudden_death_settings_reel_runtime.gd).
## Example: Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/sudden_death_settings_reel_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	# The game has the sudden death switched off for now (docs 20); its tests still run it.
	# Loaded here, not named: naming QuizGameState compiles it before the autoloads exist.
	(load("res://scripts/core/game_state.gd") as GDScript).set("sudden_death_available", true)
	root.add_child(load("res://tests/sudden_death_settings_reel_runtime.gd").new())
