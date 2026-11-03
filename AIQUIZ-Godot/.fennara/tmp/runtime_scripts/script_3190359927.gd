extends RefCounted

func run(ctx: Variant) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var main_menu: Control = tree.current_scene as Control
	var btn: Button = main_menu.get_node("%CustomizeBtn") as Button
	btn.pressed.emit()
	await ctx.wait(0.8)

	var overlay: Control = main_menu.get("_embedded_customize") as Control
	overlay.call("_set_section", 1)  # Section.SKIN
	await ctx.wait(0.6)

	var yaw0: float = float(overlay.get("_skin_cam_yaw"))
	var pitch0: float = float(overlay.get("_skin_cam_pitch"))
	var dist0: float = float(overlay.get("_skin_cam_distance"))
	var desired0: Dictionary = overlay.call("_get_desired_preview_camera")
	ctx.log("before: yaw=%.2f pitch=%.2f dist=%.3f pos=%s" % [yaw0, pitch0, dist0, str(desired0.get("pos"))])

	# 縦方向+ホイールを試す(効かないはず)
	var press_evt := InputEventMouseButton.new()
	press_evt.button_index = MOUSE_BUTTON_RIGHT
	press_evt.pressed = true
	overlay.call("_on_emote_preview_gui_input", press_evt)

	var motion_v := InputEventMouseMotion.new()
	motion_v.relative = Vector2(0.0, 200.0)
	overlay.call("_on_emote_preview_gui_input", motion_v)

	var wheel_evt := InputEventMouseButton.new()
	wheel_evt.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_evt.pressed = true
	overlay.call("_on_emote_preview_gui_input", wheel_evt)

	var pitch_after_vertical: float = float(overlay.get("_skin_cam_pitch"))
	var dist_after_wheel: float = float(overlay.get("_skin_cam_distance"))
	ctx.log("after vertical+wheel (expect unchanged): pitch=%.2f dist=%.3f" % [pitch_after_vertical, dist_after_wheel])

	# 横方向ドラッグ(効くはず)
	var motion_h := InputEventMouseMotion.new()
	motion_h.relative = Vector2(90.0, 0.0)
	overlay.call("_on_emote_preview_gui_input", motion_h)

	var release_evt := InputEventMouseButton.new()
	release_evt.button_index = MOUSE_BUTTON_RIGHT
	release_evt.pressed = false
	overlay.call("_on_emote_preview_gui_input", release_evt)

	var yaw1: float = float(overlay.get("_skin_cam_yaw"))
	var pitch1: float = float(overlay.get("_skin_cam_pitch"))
	var dist1: float = float(overlay.get("_skin_cam_distance"))
	var desired1: Dictionary = overlay.call("_get_desired_preview_camera")
	ctx.log("after horizontal drag: yaw=%.2f(delta=%.2f) pitch=%.2f dist=%.3f pos=%s" % [
		yaw1, yaw1 - yaw0, pitch1, dist1, str(desired1.get("pos"))
	])
	ctx.log("done")
