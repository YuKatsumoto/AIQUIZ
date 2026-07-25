extends Node3D
class_name BikeCourse

const BIKE_RULES_SCRIPT = preload("res://scripts/core/bike_race_rules.gd")
const LAYOUT_SCRIPT = preload("res://scripts/core/bike_course_layout.gd")

## Hand-built Phase 1 bicycle course. No generated 3D assets are used here.

const LENGTH: float = BIKE_RULES_SCRIPT.COURSE_LENGTH
const ROAD_WIDTH: float = 16.0
const STAGE_WIDTH: float = 24.0
const SURFACE_Y: float = BIKE_RULES_SCRIPT.COURSE_SURFACE_Y
const CHECKPOINTS: Array[float] = [0.0, 90.0, 130.0, 185.0, 220.0]

var _hazards: Array[Dictionary] = []
var _p1_hit_cooldown: float = 0.0
var _p2_hit_cooldown: float = 0.0
var _built: bool = false


func _ready() -> void:
	# The course must not appear during the quiz/countdown phases.
	visible = false
	build_course()


func build_course() -> void:
	if _built:
		return
	_built = true
	_build_road()
	_build_start_and_finish()
	_build_configured_gimmicks()
	_build_split_route_decorations()
	_build_climb()
	_build_checkpoint_markers()


func rebuild_course(layout_override: Dictionary) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_hazards.clear()
	_p1_hit_cooldown = 0.0
	_p2_hit_cooldown = 0.0
	_built = false
	LAYOUT_SCRIPT.set_cached_layout(layout_override)
	build_course()
	visible = true


func update_from_state(gs: QuizGameState, dt: float) -> void:
	visible = gs.game_state == Constants.STATE_ATHLETIC_RACE
	if not visible:
		return
	position = Vector3(0.0, 0.0, gs.bike_start_z - gs.world_scroll_z)
	_p1_hit_cooldown = maxf(0.0, _p1_hit_cooldown - dt)
	_p2_hit_cooldown = maxf(0.0, _p2_hit_cooldown - dt)
	_check_player_hazards(gs, 1)
	_check_player_hazards(gs, 2)


func get_section_name(relative_z: float) -> String:
	if relative_z < 15.0:
		return "自動乗車・発進"
	if relative_z < 45.0:
		return "加速直線"
	if relative_z < 90.0:
		return "コーンスラローム"
	if relative_z < 130.0:
		return "水たまり・段差"
	if relative_z < 185.0:
		return "二択ルート"
	if relative_z < 220.0:
		return "上り坂"
	return "自動降車"


static func get_course_height(relative_z: float) -> float:
	return LAYOUT_SCRIPT.get_cached_height(relative_z)


static func get_course_pitch(relative_z: float) -> float:
	return LAYOUT_SCRIPT.get_cached_pitch(relative_z)


func _build_road() -> void:
	var asphalt_a: StandardMaterial3D = _material(Color(0.10, 0.12, 0.15), 0.92, 0.0)
	var asphalt_b: StandardMaterial3D = _material(Color(0.135, 0.15, 0.18), 0.90, 0.0)
	var shoulder_mat: StandardMaterial3D = _material(Color(0.22, 0.25, 0.28), 0.85, 0.0)
	var line_mat: StandardMaterial3D = _material(Color(1.0, 0.84, 0.16), 0.55, 0.0)
	var rail_mat: StandardMaterial3D = _material(Color(0.95, 0.25, 0.18), 0.48, 0.15)

	const SEGMENT_LENGTH: float = 5.0
	var segment_count: int = int(LENGTH / SEGMENT_LENGTH)
	for index: int in range(segment_count):
		var z0: float = index * SEGMENT_LENGTH
		var z1: float = z0 + SEGMENT_LENGTH
		var h0: float = get_course_height(z0)
		var h1: float = get_course_height(z1)
		var center_z: float = (z0 + z1) * 0.5
		var center_h: float = (h0 + h1) * 0.5
		var slope_angle: float = -atan2(h1 - h0, SEGMENT_LENGTH)
		# Segments meet edge-to-edge. Overlapping coplanar top faces caused
		# visible z-fighting, especially where the alternating asphalt changed.
		var road: MeshInstance3D = _box(Vector3(ROAD_WIDTH, 0.22, SEGMENT_LENGTH), asphalt_a if index % 2 == 0 else asphalt_b)
		road.position = Vector3(0.0, SURFACE_Y - 0.11 + center_h, center_z)
		road.rotation.x = slope_angle
		road.name = "Road_%02d" % index
		add_child(road)
		_add_static_box_collider(road, Vector3(ROAD_WIDTH, 0.22, SEGMENT_LENGTH))

		for side: float in [-1.0, 1.0]:
			var shoulder: MeshInstance3D = _box(Vector3((STAGE_WIDTH - ROAD_WIDTH) * 0.5, 0.18, SEGMENT_LENGTH), shoulder_mat)
			shoulder.position = Vector3(side * (ROAD_WIDTH * 0.5 + (STAGE_WIDTH - ROAD_WIDTH) * 0.25), SURFACE_Y - 0.14 + center_h, center_z)
			shoulder.rotation.x = slope_angle
			add_child(shoulder)

		if index % 2 == 0:
			var dash: MeshInstance3D = _box(Vector3(0.12, 0.035, 2.2), line_mat)
			dash.position = Vector3(0.0, SURFACE_Y + 0.025 + center_h, center_z)
			dash.rotation.x = slope_angle
			add_child(dash)

		if index % 2 == 0:
			for side: float in [-1.0, 1.0]:
				var rail: MeshInstance3D = _box(Vector3(0.18, 0.75, 4.7), rail_mat)
				rail.position = Vector3(side * 9.3, SURFACE_Y + 0.48 + center_h, center_z)
				rail.rotation.x = slope_angle
				add_child(rail)
				_add_static_box_collider(rail, Vector3(0.18, 0.75, 4.7))


func _build_start_and_finish() -> void:
	_build_arch(0.0, "MAMA CHARI START", Color(1.0, 0.58, 0.12))
	_build_arch(LENGTH, "BIKE FINISH", Color(0.25, 0.85, 0.52))
	var checker_white: StandardMaterial3D = _material(Color(0.96, 0.96, 0.96), 0.45, 0.0)
	var checker_dark: StandardMaterial3D = _material(Color(0.08, 0.09, 0.11), 0.72, 0.0)
	var finish_height: float = get_course_height(LENGTH)
	var finish_pitch: float = get_course_pitch(LENGTH)
	for lane: int in range(16):
		var tile: MeshInstance3D = _box(Vector3(1.0, 0.045, 1.1), checker_white if lane % 2 == 0 else checker_dark)
		tile.position = Vector3(-7.5 + lane, SURFACE_Y + finish_height + 0.03, LENGTH)
		tile.rotation.x = finish_pitch
		add_child(tile)


func _build_arch(z_pos: float, text: String, color: Color) -> void:
	var arch: Node3D = Node3D.new()
	arch.name = text.replace(" ", "")
	arch.position = Vector3(0.0, get_course_height(z_pos), z_pos)
	add_child(arch)
	var mat: StandardMaterial3D = _material(color, 0.38, 0.22)
	for side: float in [-1.0, 1.0]:
		var pillar: MeshInstance3D = _box(Vector3(0.45, 4.7, 0.6), mat)
		pillar.position = Vector3(side * 8.7, SURFACE_Y + 2.35, 0.0)
		arch.add_child(pillar)
		var flag: MeshInstance3D = _box(Vector3(1.0, 0.58, 0.08), _material(Color.WHITE, 0.7, 0.0))
		flag.position = Vector3(side * 8.15, SURFACE_Y + 3.65, 0.0)
		arch.add_child(flag)
	var crossbar: MeshInstance3D = _box(Vector3(17.8, 0.55, 0.6), mat)
	crossbar.position = Vector3(0.0, SURFACE_Y + 4.55, 0.0)
	arch.add_child(crossbar)
	var label: Label3D = _label(text, Color.WHITE, 54)
	label.position = Vector3(0.0, SURFACE_Y + 4.45, -0.35)
	label.rotation.y = PI
	arch.add_child(label)


func _build_configured_gimmicks() -> void:
	var layout: Dictionary = LAYOUT_SCRIPT.load_layout()
	var raw_items: Array = layout.get("gimmicks", [])
	for index: int in range(raw_items.size()):
		var raw: Variant = raw_items[index]
		if not raw is Dictionary:
			continue
		var item: Dictionary = raw as Dictionary
		var type_id: String = str(item.get("type", ""))
		var item_id: String = str(item.get("id", "%s_%03d" % [type_id, index]))
		var x_pos: float = float(item.get("x", 0.0))
		var z_pos: float = float(item.get("z", 0.0))
		var rotation_y: float = deg_to_rad(float(item.get("rotation_y", 0.0)))
		var gimmick_root: Node3D = Node3D.new()
		gimmick_root.name = item_id
		gimmick_root.position = Vector3(
			x_pos,
			SURFACE_Y + get_course_height(z_pos),
			z_pos
		)
		gimmick_root.rotation = Vector3(get_course_pitch(z_pos), rotation_y, 0.0)
		add_child(gimmick_root)
		match type_id:
			"cone":
				_add_cone(gimmick_root, item_id)
			"puddle":
				_add_puddle(gimmick_root, item_id)
			"bump":
				_add_bump(gimmick_root, item_id)
			"barrier":
				_add_barrier(gimmick_root, item_id)
			_:
				gimmick_root.queue_free()
				continue
		var hazard: Dictionary = LAYOUT_SCRIPT.type_hazard(type_id)
		_hazards.append({
			"id": item_id,
			"type": type_id,
			"x": x_pos,
			"z": z_pos,
			"rotation_y": rotation_y,
			"hx": float(hazard.get("hx", 0.5)),
			"hz": float(hazard.get("hz", 0.5)),
			"severity": float(hazard.get("severity", 0.0)),
		})


func _add_cone(parent: Node3D, gimmick_name: String) -> void:
	var cone: MeshInstance3D = MeshInstance3D.new()
	cone.name = "%s_Cone" % gimmick_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.36
	mesh.height = 0.9
	mesh.radial_segments = 16
	cone.mesh = mesh
	cone.material_override = _material(Color(1.0, 0.34, 0.04), 0.58, 0.0)
	cone.position = Vector3(0.0, 0.45, 0.0)
	parent.add_child(cone)
	var stripe: MeshInstance3D = _box(
		Vector3(0.48, 0.12, 0.48),
		_material(Color.WHITE, 0.6, 0.0)
	)
	stripe.name = "%s_Stripe" % gimmick_name
	stripe.position = Vector3(0.0, 0.42, 0.0)
	parent.add_child(stripe)
	_add_static_box_collider(
		parent,
		Vector3(0.62, 0.90, 0.62),
		Vector3(0.0, 0.45, 0.0)
	)


func _add_puddle(parent: Node3D, gimmick_name: String) -> void:
	var puddle: MeshInstance3D = MeshInstance3D.new()
	puddle.name = "%s_Puddle" % gimmick_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 1.65
	mesh.bottom_radius = 1.8
	mesh.height = 0.035
	mesh.radial_segments = 32
	puddle.mesh = mesh
	puddle.material_override = _material(
		Color(0.10, 0.55, 0.90, 0.72),
		0.18,
		0.05,
		true
	)
	puddle.scale.z = 0.58
	puddle.position = Vector3(0.0, 0.035, 0.0)
	parent.add_child(puddle)


func _add_bump(parent: Node3D, gimmick_name: String) -> void:
	var bump: MeshInstance3D = _box(
		Vector3(ROAD_WIDTH - 1.0, 0.16, 0.35),
		_material(Color(0.96, 0.78, 0.08), 0.65, 0.0)
	)
	bump.name = "%s_Bump" % gimmick_name
	bump.position = Vector3(0.0, 0.08, 0.0)
	parent.add_child(bump)
	_add_static_box_collider(
		parent,
		Vector3(ROAD_WIDTH - 1.0, 0.16, 0.35),
		Vector3(0.0, 0.08, 0.0)
	)


func _add_barrier(parent: Node3D, gimmick_name: String) -> void:
	var obstacle: MeshInstance3D = _box(
		Vector3(3.8, 0.24, 0.52),
		_material(Color(1.0, 0.30, 0.16), 0.55, 0.0)
	)
	obstacle.name = "%s_Barrier" % gimmick_name
	obstacle.position = Vector3(0.0, 0.12, 0.0)
	parent.add_child(obstacle)
	_add_static_box_collider(
		parent,
		Vector3(3.8, 0.24, 0.52),
		Vector3(0.0, 0.12, 0.0)
	)


func _build_split_route_decorations() -> void:
	var divider_mat: StandardMaterial3D = _material(Color(0.28, 0.82, 0.90), 0.52, 0.1)
	for index: int in range(10):
		var divider: MeshInstance3D = _box(Vector3(0.35, 0.55, 4.5), divider_mat)
		var z_pos: float = 137.0 + index * 4.8
		divider.name = "SplitDivider_%02d" % index
		divider.position = Vector3(0.0, SURFACE_Y + get_course_height(z_pos) + 0.3, z_pos)
		divider.rotation.x = get_course_pitch(z_pos)
		add_child(divider)

	var split_label_height: float = get_course_height(133.0)
	var safe_label: Label3D = _label("SAFE", Color(0.30, 0.95, 0.55), 42)
	safe_label.name = "SafeRouteLabel"
	safe_label.position = Vector3(4.0, SURFACE_Y + split_label_height + 2.0, 133.0)
	safe_label.rotation.y = PI
	add_child(safe_label)
	var short_label: Label3D = _label("SHORT", Color(1.0, 0.62, 0.12), 42)
	short_label.name = "ShortRouteLabel"
	short_label.position = Vector3(-4.0, SURFACE_Y + split_label_height + 2.0, 133.0)
	short_label.rotation.y = PI
	add_child(short_label)


func _build_climb() -> void:
	var chevron_mat: StandardMaterial3D = _material(Color(0.98, 0.72, 0.08), 0.5, 0.0)
	for index: int in range(6):
		var z_pos: float = 188.0 + index * 5.2
		var height: float = get_course_height(z_pos)
		for side: float in [-1.0, 1.0]:
			var chevron: MeshInstance3D = _box(Vector3(3.0, 0.04, 0.22), chevron_mat)
			chevron.position = Vector3(side * 2.2, SURFACE_Y + height + 0.035, z_pos)
			chevron.rotation = Vector3(get_course_pitch(z_pos), side * 0.36, 0.0)
			add_child(chevron)
	var climb_label: Label3D = _label("STAND & PEDAL!", Color(1.0, 0.82, 0.20), 42)
	climb_label.position = Vector3(0.0, SURFACE_Y + get_course_height(188.0) + 3.2, 188.0)
	climb_label.rotation.y = PI
	add_child(climb_label)


func _build_checkpoint_markers() -> void:
	for index: int in range(CHECKPOINTS.size()):
		var z_pos: float = CHECKPOINTS[index]
		var height: float = get_course_height(z_pos)
		var marker_mat: StandardMaterial3D = _material(Color(0.35, 0.72, 1.0), 0.45, 0.08)
		for side: float in [-1.0, 1.0]:
			var post: MeshInstance3D = _box(Vector3(0.16, 1.35, 0.16), marker_mat)
			post.position = Vector3(side * 8.15, SURFACE_Y + height + 0.68, z_pos)
			add_child(post)


func _check_player_hazards(gs: QuizGameState, player_index: int) -> void:
	if player_index == 1 and _p1_hit_cooldown > 0.0:
		return
	if player_index == 2 and _p2_hit_cooldown > 0.0:
		return
	var px: float = gs.player_x if player_index == 1 else gs.player2_x
	var pz: float = (gs.player_z if player_index == 1 else gs.player2_z) - gs.bike_start_z
	for hazard: Dictionary in _hazards:
		var delta_x: float = px - float(hazard.x)
		var delta_z: float = pz - float(hazard.z)
		var yaw: float = float(hazard.get("rotation_y", 0.0))
		var local_x: float = cos(yaw) * delta_x - sin(yaw) * delta_z
		var local_z: float = sin(yaw) * delta_x + cos(yaw) * delta_z
		if absf(local_x) <= float(hazard.hx) and absf(local_z) <= float(hazard.hz):
			gs.apply_bike_hazard(player_index, float(hazard.severity))
			if player_index == 1:
				_p1_hit_cooldown = 0.42
			else:
				_p2_hit_cooldown = 0.42
			return


func _box(size: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	return instance


func _add_static_box_collider(
	parent: Node3D,
	size: Vector3,
	center: Vector3 = Vector3.ZERO
) -> void:
	var body := StaticBody3D.new()
	body.name = "PhysicsCollider"
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = center
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


func _label(text: String, color: Color, font_size: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_modulate = Color(0.03, 0.04, 0.06, 1.0)
	label.outline_size = 8
	var font: Font = load("res://resources/fonts/NotoSansJP-Regular.otf") as Font
	if font != null:
		label.font = font
	return label


func _material(color: Color, roughness: float, metallic: float, transparent: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if transparent or color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
