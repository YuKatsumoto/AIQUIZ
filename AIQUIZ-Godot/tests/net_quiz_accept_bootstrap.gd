extends SceneTree

## Guest acceptance of host quizzes (tests/net_quiz_accept_unit.gd).
## Example: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/net_quiz_accept_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/net_quiz_accept_unit.gd").new())
