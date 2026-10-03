extends SceneTree

## Runs the main menu with the harbor stage (AIQUIZ HARBOR LAUNCH) and checks it.
## Example: Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/menu_harbor_stage_bootstrap.gd
## Options after "--": --no-capture (skip the screenshots)

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/menu_harbor_stage_runtime.gd").new())
