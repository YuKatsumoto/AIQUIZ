extends SceneTree

## Offline PCs switch the round to the bank without the 12 s wait (tests/offline_fast_fallback_unit.gd).
## Example: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/offline_fast_fallback_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/offline_fast_fallback_unit.gd").new())
