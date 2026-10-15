extends SceneTree

## Windowed run (needs a real audio driver for the capture):
## Godot --path . --script res://tests/ghost_shark_audio_bootstrap.gd
func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	root.add_child(load("res://tests/ghost_shark_audio_runtime.gd").new())
