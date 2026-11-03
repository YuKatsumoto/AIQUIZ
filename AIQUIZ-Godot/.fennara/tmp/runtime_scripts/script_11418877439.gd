extends RefCounted
func run(ctx: Variant) -> void:
	var menu: Node = ctx.get_scene_root()
	var image: Image = await ctx.frame(1280)
	image.save_png("res://artifacts/chip_saw/verification/menu_rails.png")
	menu._open_embedded_customize()
	await ctx.wait(1.5)
	menu = ctx.get_scene_root()
	var custom: Control = menu._embedded_customize
	var rails: Node3D = custom._sub_viewport.find_child("ConveyorRunningRails", true, false)
	ctx.log("Shared preview rails", {"script":str(rails.get_script().resource_path),"gauge":absf(rails.left_head.position.x),"colliders":rails.find_children("*", "CollisionObject3D", true, false).size()})
	for section: int in [0,1,2]:
		ctx.get_scene_root()._embedded_customize._set_section(section)
		await ctx.wait(1.0)
		var shot: Image = await ctx.frame(1280)
		shot.save_png("res://artifacts/chip_saw/verification/customize_%d.png" % section)
		ctx.output(shot,"Customization section %d" % section)
	ctx.get_scene_root()._embedded_customize._sub_viewport.find_child("WeatherCycle", true, false).force_day_phase(0.7)
	await ctx.wait(0.3)
	var night: Image = await ctx.frame(1280)
	night.save_png("res://artifacts/chip_saw/verification/customize_night.png")
	ctx.output(night,"Night customization")
