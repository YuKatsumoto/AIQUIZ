extends SceneTree

## Esc pause also stops the ocean shark attack (tests/shark_pause_runtime.gd).
## Needs a window: Godot_v4.7.2-stable_win64_console.exe --path . --resolution 960x540 --script res://tests/shark_pause_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/shark_pause_runtime.gd").new())
