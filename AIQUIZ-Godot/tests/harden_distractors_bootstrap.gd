extends SceneTree

## Hard-mode distractor rewriting (tests/harden_distractors_unit.gd).
## Example: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/harden_distractors_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/harden_distractors_unit.gd").new())
