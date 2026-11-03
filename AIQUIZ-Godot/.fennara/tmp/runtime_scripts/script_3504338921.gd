extends RefCounted

func run(ctx: Variant) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var main_menu: Control = tree.current_scene as Control
	var overlay: Control = main_menu.get("_embedded_customize") as Control

	var preview_player: Node3D = overlay.get("_preview_player") as Node3D
	ctx.log("preview_player=%s pos=%s" % [str(preview_player), str(preview_player.global_position) if preview_player else "n/a"])

	var p1_parts: Dictionary = preview_player.get("p1_parts") as Dictionary
	for key in ["pelvis", "head_pivot", "head", "hat_mount", "neck"]:
		if p1_parts.has(key):
			var n: Node3D = p1_parts[key] as Node3D
			ctx.log("%s global_pos=%s" % [key, str(n.global_position)])
		else:
			ctx.log("%s: not found" % key)

	var cam: Camera3D = overlay.get("_preview_camera") as Camera3D
	ctx.log("camera global_pos=%s global_rot_deg=%s fov=%.2f" % [str(cam.global_position), str(cam.global_rotation_degrees), cam.fov])

	var viewport: Viewport = cam.get_viewport()
	ctx.log("viewport size=%s" % [str(viewport.get_visible_rect().size)])

	# 頭部中心をスクリーン座標に投影
	if p1_parts.has("head_pivot"):
		var head_pos: Vector3 = (p1_parts["head_pivot"] as Node3D).global_position
		var screen_pos: Vector2 = cam.unproject_position(head_pos)
		ctx.log("head_pivot screen_pos=%s (viewport size=%s)" % [str(screen_pos), str(viewport.get_visible_rect().size)])
	ctx.log("done")
