extends SceneTree

## Friend code input normalization (tests/friend_code_unit.gd).
## Example: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/friend_code_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/friend_code_unit.gd").new())
