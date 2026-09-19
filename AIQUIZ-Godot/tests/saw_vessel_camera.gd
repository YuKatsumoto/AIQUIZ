extends Node

func inspect_menu() -> void:
	var preview: Node = get_tree().current_scene._menu_wall_preview
	preview.set_process(false)
	preview._preview_saw.dock.begin()
	preview._preview_saw.dock.elapsed = 2.45
	preview._preview_saw.update_preview(0.0)
	var camera: Camera3D = preview._preview_camera
	for distance: float in [6.0,9.0,12.0]:
		camera.position = Vector3(-18.0,6.1,23.15) + camera.basis.z * distance
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/saw_vessel/menu_fixed_%d.png" % int(distance))
	queue_free()
