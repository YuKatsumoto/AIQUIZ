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

func _make_label(text_value: String) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.03, 0.04, 0.07, 1.0)
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
	var controller: Node = root.get_node("GhostSharkRideController")
	controller.call("_set_aim_color", Color(0.20, 0.65, 0.90, 1.0))
	var aim_material: StandardMaterial3D = controller.get("_aim_material") as StandardMaterial3D
	var outer_material: StandardMaterial3D = controller.get("_aim_outer_material") as StandardMaterial3D
	if aim_material == null or outer_material == null:
		ctx.error("Aim materials were not created")
		return

	var wall_scene: PackedScene = load("res://scenes/quiz_wall.tscn") as PackedScene
	var quiz_wall: Node = wall_scene.instantiate()
	root.add_child(quiz_wall)
	var sample_label: Label3D = quiz_wall.call("_create_label") as Label3D
	var label_safe: bool = (
		sample_label.render_priority > aim_material.render_priority
		and sample_label.outline_render_priority > aim_material.render_priority
		and not sample_label.no_depth_test
	)
	sample_label.free()
	quiz_wall.queue_free()

	var main_ok: bool = (
		aim_material.no_depth_test
		and aim_material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED
		and aim_material.render_priority == 12
		and is_equal_approx(aim_material.albedo_color.a, 0.68)
	)
	var outer_ok: bool = (
		outer_material.no_depth_test
		and outer_material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED
		and outer_material.render_priority == 12
		and is_equal_approx(outer_material.albedo_color.a, 0.30)
	)
	ctx.log("aim xray main=%s outer=%s choice_label_safe=%s" % [main_ok, outer_ok, label_safe])
	ctx.log("RESULT=%s" % ("PASS" if main_ok and outer_ok and label_safe else "FAIL"))

	var camera: Camera3D = root.get_node("CameraController/Camera3D") as Camera3D
	var fixture := Node3D.new()
	root.add_child(fixture)
	fixture.global_transform = camera.global_transform

	var backdrop := _make_box(Vector3(10.0, 5.7, 0.25), Color(0.10, 0.14, 0.20, 1.0))
	backdrop.position = Vector3(0.0, 0.0, -9.2)
	fixture.add_child(backdrop)
	var frame := _make_box(Vector3(8.4, 1.2, 0.55), Color(0.36, 0.39, 0.46, 1.0))
	frame.position = Vector3(0.0, 1.65, -7.7)
	fixture.add_child(frame)
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

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.72
	ring_mesh.outer_radius = 0.98
	ring.mesh = ring_mesh
	ring.material_override = aim_material
	ring.position = Vector3(-2.0, -0.45, -8.25)
	ring.rotation_degrees.x = 90.0
	ring.scale = Vector3.ONE * 1.35
	fixture.add_child(ring)
	var outer_ring := MeshInstance3D.new()
	var outer_mesh := TorusMesh.new()
	outer_mesh.inner_radius = 1.10
	outer_mesh.outer_radius = 1.22
	outer_ring.mesh = outer_mesh
	outer_ring.material_override = outer_material
	outer_ring.position = Vector3(-2.0, -0.45, -8.26)
	outer_ring.rotation_degrees.x = 90.0
	outer_ring.scale = Vector3.ONE * 1.35
	fixture.add_child(outer_ring)

	var left_label := _make_label("A.  8")
	left_label.position = Vector3(-2.0, -0.45, -7.50)
	fixture.add_child(left_label)
	var right_label := _make_label("B.  10")
	right_label.position = Vector3(2.0, -0.45, -7.50)
	fixture.add_child(right_label)
	var title := _make_label("照準は壁越し表示　／　選択肢文字を優先")
	title.font_size = 36
	title.position = Vector3(0.0, 2.55, -7.48)
	fixture.add_child(title)

	await ctx.wait(0.15)
	await ctx.capture("aim_xray_choice_readability", 1280)
	fixture.queue_free()
