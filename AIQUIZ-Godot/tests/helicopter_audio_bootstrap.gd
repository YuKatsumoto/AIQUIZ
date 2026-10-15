extends SceneTree

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var runner = load("res://tests/helicopter_audio_runtime.gd").new()
	root.add_child(runner)
	while not runner.finished:
		await process_frame
	quit(0 if runner.failures.is_empty() else 1)
