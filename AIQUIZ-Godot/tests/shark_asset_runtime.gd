extends Node

## Inspect and render the imported runtime clips, including retained ghost clips.
func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var stage := Node3D.new()
	add_child(stage)
	var shark: SharkSwimmer = load("res://scenes/shark_swimmer.tscn").instantiate()
	shark.model_scale = 1.0
	stage.add_child(shark)
	shark.set_process(false)
	shark.position = Vector3.ZERO
	shark.rotation = Vector3.ZERO
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(13, 4, 2)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11
	camera.make_current()
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-45, -45, 0)
	light.light_energy = 1.5
	var skeleton := shark.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := shark.animation_player
	var clips: Array[Dictionary] = []
	var passed := skeleton.get_bone_count() == 10
	var jaw_index := skeleton.find_bone("jaw")
	var tail_index := skeleton.find_bone("tail_03")
	for clip in ["SharkSwim", "SharkBite", "GhostRendezvousIdle", "GhostMountReceive", "GhostDeparture"]:
		if not ap.has_animation(clip):
			passed = false
			continue
		var animation := ap.get_animation(clip)
		ap.play(clip)
		ap.pause()
		var poses: Array[Dictionary] = []
		for fraction in [0.0, 0.25, 0.5, 0.75, 0.999]:
			ap.seek(animation.length * fraction, true)
			ap.advance(0.0)
			await RenderingServer.frame_post_draw
			var jaw_angle := skeleton.get_bone_pose_rotation(jaw_index).get_angle()
			passed = passed and absf(jaw_angle) < 0.0001
			poses.append({"fraction": fraction, "jaw": jaw_angle,
				"tail": str(skeleton.get_bone_pose_rotation(tail_index))})
			if fraction == 0.25:
				get_viewport().get_texture().get_image().save_png("res://artifacts/shark_rig_rebuild/imported_" + clip + ".png")
		clips.append({"clip": clip, "length": animation.length, "poses": poses})
	var report := {"passed": passed, "bones": skeleton.get_bone_count(), "clips": clips,
		"mesh_count": shark.model.find_children("*", "MeshInstance3D", true, false).size(),
		"mount_socket": shark.model.find_child("GhostMountSocket", true, false) != null,
		"renderer": RenderingServer.get_current_rendering_method()}
	FileAccess.open("res://artifacts/shark_rig_rebuild/imported_asset.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SHARK_ASSET_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if passed else 1)
