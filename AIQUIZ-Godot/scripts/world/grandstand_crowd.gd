@tool
extends Node3D

## Seated block-style spectators, with rare hats and independently timed dances.
## Bodies and hats remain batched by seating section.
## Seat coordinates mirror santorini_grandstand/source/build_santorini_grandstand.py.
## Each instance faces the course; the enclosing stand mirrors the opposite side.
const CROWD_SHADER: Shader = preload("res://shaders/grandstand_crowd.gdshader")
const ROW_COUNT: int = 4
const ROW_FRONT: float = 1.15
const ROW_PITCH: float = 1.25
const ROW_RISE: float = 0.40
const SEAT_EDGE: float = 77.5
const SEAT_PITCH: float = 0.92
const SEAT_TOP: float = 0.32 + 0.50 + 0.045
const AISLES: Array[float] = [-60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0]
const AISLE_CLEARANCE: float = 1.10 + 0.39
const POSE_COUNT: int = 3
const SECTION_COUNT: int = 8
const HAT_CHANCE: float = 0.08
const EMOTE_CHANCE: float = 0.06
const HAT_STYLE_COUNT: int = 3
const SHIRT_COLORS: Array[Color] = [
	Color("#ef6958"), Color("#f0b541"), Color("#54b7d0"), Color("#9873c5"),
	Color("#61b887"), Color("#ec8bab"), Color("#e9e3ce"), Color("#5379b7"),
]
const MESH_REVISION: int = 5
static var _pose_meshes: Array[ArrayMesh] = []
static var _hat_meshes: Array[ArrayMesh] = []
static var _material: ShaderMaterial = null
static var _built_revision: int = 0

var spectator_count: int = 0
var hat_count: int = 0
var emote_count: int = 0
var _batches: Array[Dictionary] = []
var _length_scale: float = -1.0


func build(density: float, crowd_seed: int) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_batches.clear()
	spectator_count = 0
	hat_count = 0
	emote_count = 0
	_length_scale = -1.0
	if density <= 0.0:
		return
	_ensure_meshes()
	var rng := RandomNumberGenerator.new()
	rng.seed = crowd_seed
	# Separate stream preserves the established seat, clothing and skin choices.
	var variety_rng := RandomNumberGenerator.new()
	variety_rng.seed = crowd_seed + 104729
	var groups: Array[Array] = []
	var hat_groups: Array[Array] = []
	for _index: int in range(SECTION_COUNT * HAT_STYLE_COUNT):
		hat_groups.append([])
	for _index: int in range(SECTION_COUNT * POSE_COUNT):
		groups.append([])
	for row: int in range(ROW_COUNT):
		for column: int in range(169):
			# glTF maps Blender +Y to Godot -Z. The seat grid is not symmetric:
			# its final chair is at 77.06, so reversing the sign matters.
			var seat_z: float = SEAT_EDGE - float(column) * SEAT_PITCH
			if seat_z < -SEAT_EDGE or _is_aisle(seat_z):
				continue
			if rng.randf() > clampf(density, 0.0, 1.0):
				continue
			# Most people sit normally; scattered spectators wave one or both hands.
			var pose_roll: float = rng.randf()
			var pose: int = 0 if pose_roll < 0.60 else (1 if pose_roll < 0.88 else 2)
			var section: int = clampi(int((seat_z + 80.0) / 20.0), 0, SECTION_COUNT - 1)
			var seat := Vector3(ROW_FRONT + float(row) * ROW_PITCH, SEAT_TOP + float(row) * ROW_RISE, seat_z)
			var person := {
				"transform": Transform3D(Basis(Vector3.UP, -PI * 0.5), seat),
				"color": SHIRT_COLORS[rng.randi_range(0, SHIRT_COLORS.size() - 1)],
				"custom": Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.91, 1.09)),
			}
			if variety_rng.randf() < EMOTE_CHANCE:
				# Values >= 2 mark occasional dancers; the fractional speed is retained.
				person["custom"].g += 2.0
				emote_count += 1
			groups[section * POSE_COUNT + pose].append(person)
			if variety_rng.randf() < HAT_CHANCE:
				var style: int = variety_rng.randi_range(0, HAT_STYLE_COUNT - 1)
				hat_groups[section * HAT_STYLE_COUNT + style].append(person)
				hat_count += 1
			spectator_count += 1
	for group_index: int in range(groups.size()):
		var people: Array = groups[group_index]
		if people.is_empty():
			continue
		var pose: int = group_index % POSE_COUNT
		_add_batch("Section%02dPose%d" % [floori(float(group_index) / float(POSE_COUNT)) + 1, pose], _pose_meshes[pose], people)
	for group_index: int in range(hat_groups.size()):
		var people: Array = hat_groups[group_index]
		if not people.is_empty():
			var style: int = group_index % HAT_STYLE_COUNT
			_add_batch("Section%02dHat%d" % [floori(float(group_index) / float(HAT_STYLE_COUNT)) + 1, style], _hat_meshes[style], people)
	sync_length_scale(1.0)


func _add_batch(batch_name: String, mesh: ArrayMesh, people: Array) -> void:
	var batch := MultiMeshInstance3D.new()
	batch.name = batch_name
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	instances.mesh = mesh
	instances.instance_count = people.size()
	batch.multimesh = instances
	batch.material_override = _material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(batch)
	for person_index: int in range(people.size()):
		instances.set_instance_color(person_index, people[person_index]["color"])
		instances.set_instance_custom_data(person_index, people[person_index]["custom"])
	_batches.append({"node": batch, "people": people})


func sync_length_scale(longitudinal_scale: float) -> void:
	var safe_scale: float = maxf(longitudinal_scale, 0.01)
	if is_equal_approx(_length_scale, safe_scale):
		return
	_length_scale = safe_scale
	# Seats follow stand stretching, but human bodies retain their proportions.
	# Apply the inverse in stand space BEFORE rotating the seated character.
	var compensation := Basis.from_scale(Vector3(1.0, 1.0, 1.0 / safe_scale))
	for batch_data: Dictionary in _batches:
		var batch: MultiMeshInstance3D = batch_data["node"]
		var people: Array = batch_data["people"]
		var bounds := AABB()
		for person_index: int in range(people.size()):
			var rest: Transform3D = people[person_index]["transform"]
			var placed := Transform3D(compensation * rest.basis, rest.origin)
			batch.multimesh.set_instance_transform(person_index, placed)
			var body_bounds: AABB = placed * batch.multimesh.mesh.get_aabb()
			bounds = body_bounds if person_index == 0 else bounds.merge(body_bounds)
		# Include shader-driven arm motion and individual upper-body height.
		batch.custom_aabb = bounds.grow(maxf(0.55, 0.55 / safe_scale))


static func _is_aisle(seat_z: float) -> bool:
	for aisle: float in AISLES:
		if absf(seat_z - aisle) < AISLE_CLEARANCE:
			return true
	return false


static func _ensure_meshes() -> void:
	if not _pose_meshes.is_empty() and _built_revision == MESH_REVISION:
		return
	_pose_meshes.clear()
	_hat_meshes.clear()
	_material = ShaderMaterial.new()
	_material.shader = CROWD_SHADER
	for pose: int in range(POSE_COUNT):
		_pose_meshes.append(_create_spectator_mesh(pose))
	for style: int in range(HAT_STYLE_COUNT):
		_hat_meshes.append(_create_hat_mesh(style))
	_built_revision = MESH_REVISION


static func _create_spectator_mesh(pose: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Origin is the top of the seat; the face looks along local +Z.
	_box(surface, Vector3(0.0, 0.085, 0.0), Vector3(0.37, 0.17, 0.27), 3.0)
	_box(surface, Vector3(0.0, 0.325, 0.0), Vector3(0.40, 0.44, 0.25), 0.0, true)
	_box(surface, Vector3(0.0, 0.575, 0.0), Vector3(0.13, 0.10, 0.14), 1.0, true)
	_box(surface, Vector3(0.0, 0.77, 0.0), Vector3(0.30, 0.32, 0.28), 1.0, true)
	# Cap covers the crown. A separate forehead slab sits just in front of the
	# face so bangs stay visible without sharing a depth plane with skin.
	_box(surface, Vector3(0.0, 0.92, -0.02), Vector3(0.322, 0.09, 0.24), 2.0, true)
	_box(surface, Vector3(0.0, 0.82, -0.175), Vector3(0.31, 0.20, 0.05), 2.0, true)
	_box(surface, Vector3(0.0, 0.878, 0.182), Vector3(0.312, 0.116, 0.054), 2.0, true)
	if pose == 1:
		_box(surface, Vector3(0.0, 0.68, -0.185), Vector3(0.30, 0.28, 0.06), 2.0, true)
	else:
		_box(surface, Vector3(-0.09, 0.835, 0.196), Vector3(0.15, 0.09, 0.04), 2.0, true)
	for side: float in [-1.0, 1.0]:
		_box(surface, Vector3(side * 0.068, 0.782, 0.145), Vector3(0.031, 0.045, 0.018), 5.0, true)
		_box(surface, Vector3(side * 0.105, 0.065, 0.20), Vector3(0.16, 0.18, 0.40), 3.0)
		_box(surface, Vector3(side * 0.105, -0.23, 0.36), Vector3(0.15, 0.42, 0.16), 3.0)
		_box(surface, Vector3(side * 0.105, -0.485, 0.405), Vector3(0.18, 0.12, 0.27), 4.0)
		var shoulder := Vector3(side * 0.235, 0.46, 0.0)
		var raised: bool = pose == 2 or (pose == 1 and side > 0.0)
		var elbow := Vector3(side * 0.25, 0.24, 0.07)
		var hand := Vector3(side * 0.19, 0.19, 0.31)
		if raised:
			elbow = Vector3(side * 0.32, 0.67, 0.04)
			hand = Vector3(side * 0.30, 0.94, 0.09)
		var arm_tag := Vector2(1.0 if raised else 2.0, shoulder.x)
		_limb(surface, shoulder, shoulder.lerp(elbow, 0.62), 0.15, 0.0, arm_tag)
		_limb(surface, shoulder.lerp(elbow, 0.54), elbow, 0.12, 1.0, arm_tag)
		_limb(surface, elbow, hand, 0.11, 1.0, arm_tag)
		_box(surface, hand, Vector3(0.13, 0.14, 0.115), 1.0, true, arm_tag)
	_box(surface, Vector3(0.0, 0.689, 0.146), Vector3(0.068, 0.019, 0.014), 5.0, true)
	surface.index()
	return surface.commit()


static func _create_hat_mesh(style: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# All pieces share the head's upper-body deformation, including during dances.
	if style == 0: # Baseball cap with a forward brim.
		_box(surface, Vector3(0, 0.99, -0.01), Vector3(0.35, 0.15, 0.33), 6.0, true)
		_box(surface, Vector3(0, 0.94, 0.21), Vector3(0.37, 0.035, 0.22), 6.0, true)
	elif style == 1: # Top hat with contrasting band.
		_box(surface, Vector3(0, 0.97, 0), Vector3(0.44, 0.05, 0.40), 5.0, true)
		_box(surface, Vector3(0, 1.13, 0), Vector3(0.30, 0.28, 0.28), 5.0, true)
		_box(surface, Vector3(0, 1.035, 0), Vector3(0.31, 0.06, 0.29), 6.0, true)
	else: # Gold crown, five visible points.
		_box(surface, Vector3(0, 0.99, 0), Vector3(0.35, 0.10, 0.32), 7.0, true)
		for x: float in [-0.14, 0.0, 0.14]:
			_box(surface, Vector3(x, 1.075, 0.135), Vector3(0.065, 0.13, 0.06), 7.0, true)
		for x: float in [-0.14, 0.14]:
			_box(surface, Vector3(x, 1.075, -0.13), Vector3(0.065, 0.13, 0.06), 7.0, true)
	surface.index()
	return surface.commit()


static func _limb(surface: SurfaceTool, start: Vector3, finish: Vector3, width: float, material_id: float, arm_tag: Vector2) -> void:
	var direction: Vector3 = finish - start
	var limb_basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
	_box(surface, (start + finish) * 0.5, Vector3(width, direction.length() + 0.035, width), material_id, true, arm_tag, limb_basis)


static func _box(surface: SurfaceTool, center: Vector3, size: Vector3, material_id: float, upper_body: bool = false, arm_tag: Vector2 = Vector2.ZERO, box_basis: Basis = Basis.IDENTITY) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays: Array = box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for vertex_index: int in indices:
		surface.set_color(Color.WHITE)
		surface.set_uv(Vector2(material_id, 1.0 if upper_body else 0.0))
		surface.set_uv2(arm_tag)
		surface.set_normal(box_basis * normals[vertex_index])
		surface.add_vertex(box_basis * vertices[vertex_index] + center)
