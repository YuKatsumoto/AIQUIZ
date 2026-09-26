extends SceneTree

func _initialize() -> void:
	call_deferred("_export")

func _export() -> void:
	var actor := Node3D.new()
	actor.name = "Actor"
	root.add_child(actor)
	var builder = load("res://scripts/ui/emote_blockman_preview.gd")
	var parts: Dictionary = builder.build_player_skeleton(true, actor, 0)
	for key: Variant in parts:
		if parts[key] is Node3D:
			(parts[key] as Node3D).name = str(key)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(actor, state)
	if error == OK:
		error = document.write_to_filesystem(state, "res://assets/animations/result_referee/source/player_reference.glb")
	print("RESULT_ACTOR_EXPORT ", error)
	actor.free()
	quit(error)
