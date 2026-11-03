@tool
extends RefCounted

const OUTPUT_PATH := "res://scenes/menu_helicopter_sequence.tscn"
const PROFILE_SCRIPT := preload("res://scripts/ui/menu_helicopter_sequence_profile.gd")
const HELICOPTER := preload("res://assets/vehicles/helicopter/helicopter_drop.glb")

func run(ctx) -> void:
	var root := Node3D.new()
	root.name = "MenuHelicopterSequence"
	root.set_script(PROFILE_SCRIPT)

	var intro_p1 := _add_path(
		root, "IntroP1Path", Vector3(-3.5, -1.2, 0.0), Color(0.95, 0.20, 0.16),
		[
			Vector3(5.238995, 25.9428, -6.833542),
			Vector3(0.0, 9.5, 0.0),
			Vector3(9.672901, 27.06954, -6.450356),
		],
		[
			Vector3(3.1430, 16.62705, -4.194601),
			Vector3(2.194387, 12.83207, -0.975126),
			Vector3(3.672745, 12.05284, -1.299028),
			Vector3(7.502594, 19.13937, -4.236313),
		]
	)
	var intro_p2 := _add_path(
		root, "IntroP2Path", Vector3(3.5, -1.2, 0.0), Color(0.15, 0.45, 1.0),
		[
			Vector3(32.16222, 10.673926, 0.385487),
			Vector3(0.0, 9.5, 0.0),
			Vector3(30.33186, 15.02248, -1.62656),
		],
		[
			Vector3(13.49171, 10.070008, -2.181892),
			Vector3(6.225672, 11.047284, -0.091169),
			Vector3(7.6306, 10.654581, -0.723392),
			Vector3(17.12689, 13.81815, -2.818905),
		]
	)
	var pickup_p1 := _add_path(
		root, "PickupP1Path", Vector3(-3.5, -1.2, 0.0), Color(1.0, 0.55, 0.15),
		[
			Vector3(1.5, 22.0, -7.0),
			Vector3(0.0, 10.2, 0.0),
			Vector3(1.0, 23.0, -7.0),
		],
		[
			Vector3(1.0, 18.0, -4.0),
			Vector3(-0.6, 11.4, 0.0),
			Vector3(-0.55, 13.0, 0.0),
			Vector3(0.5, 19.0, -5.0),
		]
	)
	var pickup_p2 := _add_path(
		root, "PickupP2Path", Vector3(3.5, -1.2, 0.0), Color(0.35, 0.85, 1.0),
		[
			Vector3(6.5, 22.0, -5.0),
			Vector3(0.0, 10.2, 0.0),
			Vector3(7.0, 23.0, -4.0),
		],
		[
			Vector3(4.0, 18.5, -3.0),
			Vector3(0.6, 11.4, 0.0),
			Vector3(0.55, 13.0, 0.0),
			Vector3(5.0, 19.0, -3.0),
		]
	)

	var editor_reference := Node3D.new()
	editor_reference.name = "EditorReference"
	root.add_child(editor_reference)
	editor_reference.owner = root
	_add_editor_reference(root, editor_reference)

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(-18.0, 6.1, 23.15)
	camera.rotation_degrees = Vector3(-4.0, -19.0, 0.0)
	camera.fov = 45.0
	camera.current = false
	root.add_child(camera)
	camera.owner = root

	var light := DirectionalLight3D.new()
	light.name = "PreviewLight"
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.15
	root.add_child(light)
	light.owner = root

	var world := WorldEnvironment.new()
	world.name = "PreviewEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.10, 0.14)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.60, 0.72)
	environment.ambient_light_energy = 0.8
	world.environment = environment
	root.add_child(world)
	world.owner = root

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	root.add_child(player)
	player.owner = root
	var library := AnimationLibrary.new()
	library.add_animation("RESET", _make_reset_animation())
	library.add_animation("intro_arrival", _make_intro_animation(intro_p1, intro_p2))
	library.add_animation("start_pickup", _make_pickup_animation(pickup_p1, pickup_p2))
	player.add_animation_library("", library)

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		ctx.error("Could not pack menu helicopter sequence: %s" % error_string(pack_error))
		root.free()
		return
	var save_error := ResourceSaver.save(packed, OUTPUT_PATH)
	if save_error != OK:
		ctx.error("Could not save menu helicopter sequence: %s" % error_string(save_error))
		root.free()
		return
	ctx.log("Created %s with 4 editable Path3D curves and 2 AnimationPlayer timelines" % OUTPUT_PATH)
	root.free()


func _add_path(
	root: Node3D,
	node_name: String,
	ground: Vector3,
	color: Color,
	points: Array,
	controls: Array
) -> Path3D:
	var path := Path3D.new()
	path.name = node_name
	path.position = ground
	path.debug_custom_color = color
	var curve := Curve3D.new()
	curve.resource_local_to_scene = true
	curve.bake_interval = 0.08
	curve.add_point(points[0], Vector3.ZERO, controls[0] - points[0])
	curve.add_point(points[1], controls[1] - points[1], controls[2] - points[1])
	curve.add_point(points[2], controls[3] - points[2], Vector3.ZERO)
	path.curve = curve
	root.add_child(path)
	path.owner = root

	var follow := PathFollow3D.new()
	follow.name = "Follow"
	follow.loop = false
	follow.rotation_mode = PathFollow3D.ROTATION_XYZ
	follow.use_model_front = false
	path.add_child(follow)
	follow.owner = root

	var model := HELICOPTER.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	model.name = "PreviewModel"
	follow.add_child(model)
	model.owner = root
	return path


func _add_editor_reference(root: Node3D, parent: Node3D) -> void:
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "FloorReference"
	var plane := PlaneMesh.new()
	plane.size = Vector2(28.0, 24.0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0.0, -1.23, 0.0)
	floor_mesh.material_override = _material(Color(0.14, 0.16, 0.20, 0.78))
	parent.add_child(floor_mesh)
	floor_mesh.owner = root

	_add_player_marker(root, parent, "P1Ground", Vector3(-3.5, -0.2, 0.0), Color(0.95, 0.20, 0.16))
	_add_player_marker(root, parent, "P2Ground", Vector3(3.5, -0.2, 0.0), Color(0.15, 0.45, 1.0))

	var label := Label3D.new()
	label.name = "EditingHint"
	label.text = "Select a Path3D to drag its points/handles\nScrub AnimationPlayer: intro_arrival / start_pickup"
	label.position = Vector3(0.0, 2.0, -6.0)
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Color(0.95, 0.97, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	label.owner = root


func _add_player_marker(root: Node3D, parent: Node3D, marker_name: String, pos: Vector3, color: Color) -> void:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 2.0
	marker.mesh = capsule
	marker.position = pos
	marker.material_override = _material(color)
	parent.add_child(marker)
	marker.owner = root


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	return material


func _hover_ratio(path: Path3D) -> float:
	var curve := path.curve
	return curve.get_closest_offset(curve.get_point_position(1)) / maxf(curve.get_baked_length(), 0.001)


func _make_reset_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 0.1
	_add_value(animation, ".:p1_hatch", [[0.0, 0.0]])
	_add_value(animation, ".:p2_hatch", [[0.0, 0.0]])
	_add_value(animation, ".:p1_action_progress", [[0.0, 0.0]])
	_add_value(animation, ".:p2_action_progress", [[0.0, 0.0]])
	_add_value(animation, ".:camera_fov_delta", [[0.0, 0.0]])
	_add_value(animation, ".:camera_tilt_deg", [[0.0, 0.0]])
	return animation


func _make_intro_animation(p1: Path3D, p2: Path3D) -> Animation:
	var animation := Animation.new()
	animation.resource_name = "Main menu arrival — drag keys to retime"
	animation.length = 10.95
	animation.step = 0.05
	animation.add_marker("HOVER", 4.40)
	animation.add_marker("P1_DROP", 5.15)
	animation.add_marker("P2_DROP", 5.50)
	animation.add_marker("P1_EXIT", 6.00)
	animation.add_marker("P2_EXIT", 6.35)
	_add_value(animation, "IntroP1Path/Follow:progress_ratio", [
		[0.0, 0.0], [4.40, _hover_ratio(p1)], [6.00, _hover_ratio(p1)], [10.60, 1.0],
	])
	_add_value(animation, "IntroP2Path/Follow:progress_ratio", [
		[0.0, 0.0], [4.40, _hover_ratio(p2)], [6.35, _hover_ratio(p2)], [10.95, 1.0],
	])
	_add_value(animation, ".:p1_hatch", [
		[0.0, 0.0], [4.60, 0.0], [5.05, 1.0], [5.70, 1.0], [6.20, 0.0],
	])
	_add_value(animation, ".:p2_hatch", [
		[0.0, 0.0], [4.95, 0.0], [5.40, 1.0], [6.05, 1.0], [6.55, 0.0],
	])
	_add_discrete(animation, ".:p1_action_progress", [[0.0, 0.0], [5.15, 1.0]])
	_add_discrete(animation, ".:p2_action_progress", [[0.0, 0.0], [5.50, 1.0]])
	_add_value(animation, ".:p1_bank_deg", [[0.0, 0.0], [2.2, 7.5], [4.4, 0.0], [8.3, 9.2], [10.6, 0.0]])
	_add_value(animation, ".:p2_bank_deg", [[0.0, 0.0], [2.2, -7.5], [4.4, 0.0], [8.65, -9.2], [10.95, 0.0]])
	_add_value(animation, ".:p1_pitch_deg", [[0.0, 0.0], [2.2, -2.0], [4.4, 0.0], [8.3, -6.0], [10.6, 0.0]])
	_add_value(animation, ".:p2_pitch_deg", [[0.0, 0.0], [2.2, -2.0], [4.4, 0.0], [8.65, -6.0], [10.95, 0.0]])
	_add_value(animation, ".:camera_fov_delta", [[0.0, 7.5], [7.8, 7.5], [10.8, 0.0]])
	_add_value(animation, ".:camera_tilt_deg", [[0.0, 10.0], [7.8, 10.0], [10.8, 0.0]])
	_add_discrete(animation, ".:show_intro_preview", [[0.0, true]])
	_add_discrete(animation, ".:show_pickup_preview", [[0.0, false]])
	return animation


func _make_pickup_animation(p1: Path3D, p2: Path3D) -> Animation:
	var animation := Animation.new()
	animation.resource_name = "Start-button pickup — drag keys to retime"
	animation.length = 2.76
	animation.step = 0.02
	animation.add_marker("HOVER", 0.82)
	animation.add_marker("P1_SUCTION", 1.02)
	animation.add_marker("P2_SUCTION", 1.08)
	animation.add_marker("CLOSE_HATCH", 1.82)
	animation.add_marker("EXIT", 1.98)
	_add_value(animation, "PickupP1Path/Follow:progress_ratio", [
		[0.0, 0.0], [0.82, _hover_ratio(p1)], [1.98, _hover_ratio(p1)], [2.76, 1.0],
	])
	_add_value(animation, "PickupP2Path/Follow:progress_ratio", [
		[0.0, 0.0], [0.82, _hover_ratio(p2)], [1.98, _hover_ratio(p2)], [2.76, 1.0],
	])
	_add_value(animation, ".:p1_hatch", [[0.0, 0.0], [0.82, 0.0], [1.02, 1.0], [1.82, 1.0], [1.98, 0.0]])
	_add_value(animation, ".:p2_hatch", [[0.0, 0.0], [0.82, 0.0], [1.02, 1.0], [1.82, 1.0], [1.98, 0.0]])
	_add_value(animation, ".:p1_action_progress", [[0.0, 0.0], [1.02, 0.0], [1.76, 1.0], [2.76, 1.0]])
	_add_value(animation, ".:p2_action_progress", [[0.0, 0.0], [1.08, 0.0], [1.82, 1.0], [2.76, 1.0]])
	_add_value(animation, ".:p1_bank_deg", [[0.0, -2.0], [0.41, -5.0], [0.82, 0.0], [2.37, -8.0], [2.76, 0.0]])
	_add_value(animation, ".:p2_bank_deg", [[0.0, 2.0], [0.41, 5.0], [0.82, 0.0], [2.37, 8.0], [2.76, 0.0]])
	_add_value(animation, ".:p1_pitch_deg", [[0.0, -3.0], [0.82, 0.0], [2.37, -7.0], [2.76, 0.0]])
	_add_value(animation, ".:p2_pitch_deg", [[0.0, -3.0], [0.82, 0.0], [2.37, -7.0], [2.76, 0.0]])
	_add_value(animation, ".:camera_fov_delta", [[0.0, 4.0], [2.76, 4.0]])
	_add_value(animation, ".:camera_tilt_deg", [[0.0, 5.0], [2.76, 5.0]])
	_add_discrete(animation, ".:show_intro_preview", [[0.0, false]])
	_add_discrete(animation, ".:show_pickup_preview", [[0.0, true]])
	return animation


func _add_value(animation: Animation, path: String, keys: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for item: Array in keys:
		animation.track_insert_key(track, float(item[0]), item[1])


func _add_discrete(animation: Animation, path: String, keys: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	for item: Array in keys:
		animation.track_insert_key(track, float(item[0]), item[1])
