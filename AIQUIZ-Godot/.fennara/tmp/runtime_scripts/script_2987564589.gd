extends RefCounted

func run(ctx: Variant) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var main_menu: Control = tree.current_scene as Control
	ctx.log("main_menu=%s" % [main_menu])

	var btn: Button = main_menu.get_node("%CustomizeBtn") as Button
	btn.pressed.emit()
	await ctx.wait(0.8)

	var overlay: Control = main_menu.get("_embedded_customize") as Control
	ctx.log("overlay=%s" % [overlay])
	if overlay == null:
		ctx.log("FAIL: overlay not found")
		return

	overlay.call("_set_section", 1)  # Section.SKIN
	await ctx.wait(0.6)

	var active_section: int = int(overlay.get("_active_section"))
	ctx.log("active_section=%d (expect 1=SKIN)" % active_section)

	var yaw0: float = float(overlay.get("_skin_cam_yaw"))
	var pitch0: float = float(overlay.get("_skin_cam_pitch"))
	var desired0: Dictionary = overlay.call("_get_desired_preview_camera")
	ctx.log("before drag: yaw=%.2f pitch=%.2f cam_pos=%s" % [yaw0, pitch0, str(desired0.get("pos"))])

	var press_evt := InputEventMouseButton.new()
	press_evt.button_index = MOUSE_BUTTON_RIGHT
	press_evt.pressed = true
	overlay.call("_on_emote_preview_gui_input", press_evt)

	var motion_evt := InputEventMouseMotion.new()
	motion_evt.relative = Vector2(150.0, 40.0)
	overlay.call("_on_emote_preview_gui_input", motion_evt)

	var release_evt := InputEventMouseButton.new()
	release_evt.button_index = MOUSE_BUTTON_RIGHT
	release_evt.pressed = false
	overlay.call("_on_emote_preview_gui_input", release_evt)

	var yaw1: float = float(overlay.get("_skin_cam_yaw"))
	var pitch1: float = float(overlay.get("_skin_cam_pitch"))
	var desired1: Dictionary = overlay.call("_get_desired_preview_camera")
	ctx.log("after drag: yaw=%.2f pitch=%.2f cam_pos=%s" % [yaw1, pitch1, str(desired1.get("pos"))])
	ctx.log("delta yaw=%.2f (expect approx -45.0) delta pitch=%.2f (expect approx -12.0)" % [yaw1 - yaw0, pitch1 - pitch0])

	await ctx.wait(1.2)
	var cam_pos_now: Vector3 = overlay.get_node("PreviewViewport" ) if overlay.has_node("PreviewViewport") else Vector3.ZERO
	ctx.log("done")
