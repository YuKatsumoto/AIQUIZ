extends RefCounted

func run(ctx: Variant) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var main_menu: Control = tree.current_scene as Control
	var overlay: Control = main_menu.get("_embedded_customize") as Control

	# さらに右方向へドラッグして反対側(背中側)から見えるか確認
	var press_evt := InputEventMouseButton.new()
	press_evt.button_index = MOUSE_BUTTON_RIGHT
	press_evt.pressed = true
	overlay.call("_on_emote_preview_gui_input", press_evt)

	var motion_evt := InputEventMouseMotion.new()
	motion_evt.relative = Vector2(600.0, 0.0)
	overlay.call("_on_emote_preview_gui_input", motion_evt)

	var release_evt := InputEventMouseButton.new()
	release_evt.button_index = MOUSE_BUTTON_RIGHT
	release_evt.pressed = false
	overlay.call("_on_emote_preview_gui_input", release_evt)

	await ctx.wait(1.0)
	var yaw_final: float = float(overlay.get("_skin_cam_yaw"))
	ctx.log("yaw_final=%.2f" % yaw_final)
	await ctx.capture("skin_rotated_view")
	ctx.log("captured")
