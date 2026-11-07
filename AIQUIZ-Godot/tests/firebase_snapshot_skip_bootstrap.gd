extends SceneTree

## Shared bank snapshot skips bad items instead of failing (tests/firebase_snapshot_skip_unit.gd).
## Example: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/firebase_snapshot_skip_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/firebase_snapshot_skip_unit.gd").new())
