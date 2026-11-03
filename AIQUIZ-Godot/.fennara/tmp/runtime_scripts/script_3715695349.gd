extends RefCounted

func run(ctx: Variant) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var main_menu: Control = tree.current_scene as Control
	var btn: Button = main_menu.get_node("%CustomizeBtn") as Button
	btn.pressed.emit()
	await ctx.wait(0.8)

	var overlay: Control = main_menu.get("_embedded_customize") as Control
	overlay.call("_set_section", 1)  # Section.SKIN
	await ctx.wait(1.0)

	var desired: Dictionary = overlay.call("_get_desired_preview_camera")
	ctx.log("desired=%s" % [str(desired)])
	await ctx.capture("skin_final")
	ctx.log("done")
