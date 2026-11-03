extends RefCounted

func run(ctx: Variant) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var main_menu: Control = tree.current_scene as Control
	var overlay: Control = main_menu.get("_embedded_customize") as Control
	var preview_player: Node3D = overlay.get("_preview_player") as Node3D
	var p1_parts: Dictionary = preview_player.get("p1_parts") as Dictionary
	var head_pos: Vector3 = (p1_parts["head"] as Node3D).global_position
	var hat_top_pos: Vector3 = (p1_parts["hat_mount"] as Node3D).global_position

	var cam: Camera3D = overlay.get("_preview_camera") as Camera3D
	var orig_pos: Vector3 = cam.global_position
	var orig_rot: Vector3 = cam.rotation
	var orig_fov: float = cam.fov
	var orig_h: float = cam.h_offset
	var vp_size: Vector2 = cam.get_viewport().get_visible_rect().size

	var tx: float = -3.5
	var candidates: Array = [
		[1.6, 0.9, 0.70, 0.30, 34.0],
		[1.6, 0.85, 0.68, 0.30, 34.0],
		[1.6, 0.9, 0.68, 0.32, 34.0],
		[1.55, 0.88, 0.69, 0.31, 34.0],
	]

	for c: Array in candidates:
		var dist_z: float = c[0]
		var cam_y: float = c[1]
		var look_y: float = c[2]
		var h_off: float = c[3]
		var fov: float = c[4]
		var look_tgt := Vector3(tx, look_y, 0.0)
		var cam_pos := Vector3(tx, cam_y, -dist_z)
		cam.global_position = cam_pos
		cam.look_at(look_tgt, Vector3.UP)
		cam.fov = fov
		cam.h_offset = h_off
		var head_screen: Vector2 = cam.unproject_position(head_pos)
		var hat_screen: Vector2 = cam.unproject_position(hat_top_pos)
		ctx.log(
			"dist=%.2f cam_y=%.2f look_y=%.2f h=%.2f fov=%.1f => head_norm=(%.3f,%.3f) hat_norm=(%.3f,%.3f)" % [
				dist_z, cam_y, look_y, h_off, fov,
				head_screen.x / vp_size.x, head_screen.y / vp_size.y,
				hat_screen.x / vp_size.x, hat_screen.y / vp_size.y,
			]
		)

	cam.global_position = orig_pos
	cam.rotation = orig_rot
	cam.fov = orig_fov
	cam.h_offset = orig_h
	ctx.log("done")
