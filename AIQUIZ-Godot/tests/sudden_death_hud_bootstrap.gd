extends SceneTree

## Godot --path . --script res://tests/sudden_death_hud_bootstrap.gd
## Windowed (not headless): the HUD is checked from real screenshots.

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	root.add_child(load("res://tests/sudden_death_hud_runtime.gd").new())
