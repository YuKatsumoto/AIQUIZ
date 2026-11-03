extends RefCounted

func _make_box(size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	node.material_override = material
	return node

func _make_label(text_value: String, font_size_value: int) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = font_size_value
	label.pixel_size = 0.006
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.04, 0.05, 0.08, 1.0)
	label.outline_size = 12
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.render_priority = 20
	label.outline_render_priority = 19
	label.no_depth_test = false
	var font: Font = load("res://resources/fonts/NotoSansJP-Regular.otf") as Font
	if font != null:
		label.font = font
	return label

func run(ctx: Variant) -> void:
	var root: Node = ctx.get_scene_root()
	var game_manager: Node = root.get_node("/root/GameManager")
	var old_quality: String = str(game_manager.get("graphics_quality"))
	game_manager.set("graphics_quality", "balanced")
	var stage: Node = root.get_node("StageEnvironment")
	var sharks: Array = stage.call("get_ocean_sharks")
	if sharks.is_empty():
		ctx.error("No shark available for material verification")
		return
	var shark: Node = sharks[0] as Node
	var xray_material: StandardMaterial3D = shark.call("_create_ghost_silhouette_material") as StandardMaterial3D
	if xray_material == null:
		ctx.error("Could not create standard x-ray material")
		return

	var camera: Camera3D = root.get_node("CameraController/Camera3D") as Camera3D
	var fixture := Node3D.new()
	fixture.name = "StandardXrayVisualFixture"
	root.add_child(fixture)
	fixture.global_transform = camera.global_transform

	var backdrop := _make_box(Vector3(10.0, 5.7, 0.25), Color(0.10, 0.14, 0.20, 1.0))
	backdrop.position = Vector3(0.0, 0.0, -9.2)
	fixture.add_child(backdrop)

	var top_beam := _make_box(Vector3(8.4, 1.25, 0.55), Color(0.36, 0.39, 0.46, 1.0))
	top_beam.position = Vector3(0.0, 1.65, -7.7)
	fixture.add_child(top_beam)
	for x: float in [-4.0, 0.0, 4.0]:
		var pillar := _make_box(Vector3(0.35, 3.0, 0.55), Color(0.36, 0.39, 0.46, 1.0))
		pillar.position = Vector3(x, -0.45, -7.7)
		fixture.add_child(pillar)

	var left_door := _make_box(Vector3(3.65, 3.0, 0.42), Color(0.10, 0.52, 0.92, 1.0))
	left_door.position = Vector3(-2.0, -0.45, -7.75)
	fixture.add_child(left_door)
	var right_door := _make_box(Vector3(3.65, 3.0, 0.42), Color(0.88, 0.18, 0.15, 1.0))
	right_door.position = Vector3(2.0, -0.45, -7.75)
	fixture.add_child(right_door)

	var left_label := _make_label("A.  8", 64)
	left_label.position = Vector3(-2.0, -0.45, -7.50)
	fixture.add_child(left_label)
	var right_label := _make_label("B.  10", 64)
	right_label.position = Vector3(2.0, -0.45, -7.50)
	fixture.add_child(right_label)
	var title := _make_label("標準：壁越し表示　／　選択肢を優先", 38)
	title.position = Vector3(0.0, 2.55, -7.48)
	fixture.add_child(title)

	var ghost_shape := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.52
	capsule.height = 1.8
	ghost_shape.mesh = capsule
	ghost_shape.material_override = xray_material
	ghost_shape.position = Vector3(-2.0, 1.65, -8.2)
	ghost_shape.rotation_degrees.z = 68.0
	fixture.add_child(ghost_shape)

	await ctx.wait(0.15)
	await ctx.capture("standard_xray_choices_clear", 1280)
	fixture.queue_free()
	game_manager.set("graphics_quality", old_quality)
	ctx.log("standard visual captured: alpha=%.2f labels_depth_tested=true priorities=20/19" % xray_material.albedo_color.a)
