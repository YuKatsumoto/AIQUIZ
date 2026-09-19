extends SceneTree

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://ui/main_menu.tscn")
	await scene_changed
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://artifacts/emote_push")
	var probe = load("res://tests/emote_push_runtime.gd").new()
	root.add_child(probe)
	await probe.run()
	quit(0 if probe.failures.is_empty() else 1)
