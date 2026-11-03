extends RefCounted

func run(ctx: Variant) -> void:
	await ctx.wait(15.0)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var menu: Node = tree.current_scene
	ctx.log("scene=%s max_fps=%d gm=%d fps=%.1f" % [menu.scene_file_path, Engine.max_fps, GameManager.max_fps, Performance.get_monitor(Performance.TIME_FPS)])
	menu.call("_on_settings_btn_pressed")
	await ctx.wait(1.0)
	var vbox: VBoxContainer = menu.get_node("SettingsPanel/VBox") as VBoxContainer
	var names: PackedStringArray = []
	for c: Node in vbox.get_children():
		names.append(c.name)
	ctx.log("rows=%s" % ",".join(names))
	var opt: OptionButton = menu.get_node("SettingsPanel/VBox/MaxFpsBox/MaxFpsOption") as OptionButton
	var items: PackedStringArray = []
	for i: int in range(opt.item_count):
		items.append("%s(%d)" % [opt.get_item_text(i), opt.get_item_id(i)])
	ctx.log("items=%s selected=%s" % [",".join(items), opt.get_item_text(opt.selected)])
	await ctx.capture("settings")
	opt.select(3)
	opt.item_selected.emit(3)
	await ctx.wait(1.5)
	ctx.log("after unlimited: max_fps=%d fps=%.1f" % [Engine.max_fps, Performance.get_monitor(Performance.TIME_FPS)])
	opt.select(1)
	opt.item_selected.emit(1)
	await ctx.wait(1.5)
	ctx.log("after 60: max_fps=%d fps=%.1f" % [Engine.max_fps, Performance.get_monitor(Performance.TIME_FPS)])
