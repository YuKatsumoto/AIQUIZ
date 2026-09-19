@tool
extends Node3D

## Blender-authored seabed and access modules with runtime deep-water supports. The stairs keep metre-scale
## treads while the repeated pier bays bridge the measured shore distance.
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const FOUNDATION_SCENE = preload("res://assets/environment/santorini_waterfront/waterfront_foundations.glb")
const STAIR_SCENE = preload("res://assets/environment/santorini_waterfront/access_stair.glb")
const BAY_SCENE = preload("res://assets/environment/santorini_waterfront/pier_bay.glb")
const GATEWAY_SCENE = preload("res://assets/environment/santorini_waterfront/quay_gateway.glb")
const GATE_FILLER_SCENE = preload("res://assets/environment/santorini_waterfront/gate_filler.glb")
const AUTHORED_BED_Y := -17.2
const BED_Y := StageConstants.SEABED_Y
const QUAY_Y := -5.16
const STAIR_END_X := 28.99
const AISLES := [-60.0, -40.0, -20.0, 0.0, 20.0, 40.0, 60.0]
const DISTRICT_Z := [-108.0, 65.0, 238.0, 411.0, 584.0]
const WEST_X := [98.79264507596052, 106.58678045449761, 105.57750685910732, 98.24198963055242, 102.58455298591252]
const EAST_X := [118.0, 104.67494075077953, 98.03154498183268, 118.0, 107.70365278339887]

var routes: Array[Dictionary] = []
var _town_enabled := true
var _quality := "balanced"
var _access: Node3D
var _bay_mesh: Mesh
var _filler_mesh: Mesh
var _last_layout := ""
static var _deep_stand_meshes: Dictionary = {}


func setup(stands: Node3D, town_enabled: bool, quality: String) -> void:
	_town_enabled = town_enabled
	_quality = quality
	var foundation := FOUNDATION_SCENE.instantiate() as Node3D
	foundation.name = "SeabedAndDistrictFoundations"
	add_child(foundation)
	for node: Node in foundation.find_children("*", "MeshInstance3D", true, false):
		var geometry := node as MeshInstance3D
		geometry.visible = town_enabled or "Seabed" in node.name
		if "Seabed" in node.name:
			geometry.position.y += BED_Y - AUTHORED_BED_Y
		else:
			# Keep the archived town's foundation tops fixed if it is enabled again.
			var bounds := geometry.get_aabb()
			var top := bounds.end.y
			geometry.scale.y = (top - BED_Y) / bounds.size.y
			geometry.position.y = top * (1.0 - geometry.scale.y)
	_bay_mesh = _module_mesh(BAY_SCENE)
	_filler_mesh = _module_mesh(GATE_FILLER_SCENE)
	sync_to_stands(stands)
	apply_graphics_quality(quality)


static func extend_stand_supports(stand: Node3D) -> void:
	# The imported asset has bottom column vertices at -17.2 and separate
	# footings at -17.2..-15.0. Everything above the waterline stays byte-identical.
	# Work on a cached runtime mesh; the editable Blender/GLB sources stay intact.
	for node: Node in stand.find_children("*", "MeshInstance3D", true, false):
		var geometry := node as MeshInstance3D
		var source := geometry.mesh as ArrayMesh
		if source == null or absf(source.get_aabb().position.y - AUTHORED_BED_Y) > 0.01:
			continue
		var key := source.get_instance_id()
		if not _deep_stand_meshes.has(key):
			var extended := ArrayMesh.new()
			for surface: int in range(source.get_surface_count()):
				var arrays := source.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for index: int in range(vertices.size()):
					if vertices[index].y < StageConstants.OCEAN_SURFACE_Y:
						vertices[index].y += BED_Y - AUTHORED_BED_Y
				arrays[Mesh.ARRAY_VERTEX] = vertices
				# Retain the imported LOD topology as well as UVs, normals and materials.
				var lods := _surface_lods(source, surface)
				extended.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], lods)
				extended.surface_set_material(surface, source.surface_get_material(surface))
			_deep_stand_meshes[key] = extended
		geometry.mesh = _deep_stand_meshes[key]


static func _surface_lods(mesh: ArrayMesh, surface: int) -> Dictionary:
	var data := RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
	var lods := {}
	var index_bytes: int = 2 if int(data.vertex_count) <= 65536 else 4
	for lod: Dictionary in data.get("lods", []):
		var bytes: PackedByteArray = lod.index_data
		var indices := PackedInt32Array()
		indices.resize(bytes.size() / index_bytes)
		for index: int in range(indices.size()):
			indices[index] = bytes.decode_u16(index * 2) if index_bytes == 2 else bytes.decode_u32(index * 4)
		lods[float(lod.edge_length)] = indices
	return lods


func sync_to_stands(stands: Node3D) -> void:
	if not is_instance_valid(stands):
		return
	var signature := str(stands.position, ":", stands.get_child_count())
	for stand: Node3D in stands.get_children():
		signature += str(stand.position, ":", stand.scale)
	if signature == _last_layout:
		return
	_last_layout = signature
	if is_instance_valid(_access):
		remove_child(_access)
		_access.free()
	_access = Node3D.new()
	_access.name = "AccessRoutes"
	add_child(_access)
	routes.clear()
	var bay_transforms: Array[Transform3D] = []
	var rail_transforms: Array[Transform3D] = []
	for stand: Node3D in stands.get_children():
		var side := -1.0 if stand.position.x < 0.0 else 1.0
		var offset := absf(stand.position.x)
		var longitudinal_scale := stand.scale.z
		var selected: Array[float] = []
		if _town_enabled and longitudinal_scale >= 1.0:
			for aisle: float in [-60.0, 60.0, 0.0, -40.0, 40.0, -20.0, 20.0]:
				var z := stands.position.z + aisle * longitudinal_scale
				var district := _nearest_district(z)
				var quay_x := float((WEST_X if side < 0.0 else EAST_X)[district]) + 5.0
				if absf(z - DISTRICT_Z[district]) > 78.0 or quay_x - offset - STAIR_END_X < 4.0:
					continue
				var separated := true
				for existing: float in selected:
					separated = separated and absf((existing - aisle) * longitudinal_scale) >= 18.0
				if not separated:
					continue
				selected.append(aisle)
				_add_route(stand.name, side, offset, aisle, z, quay_x, district, bay_transforms)
				if selected.size() == 2:
					break
		for aisle: float in AISLES:
			var z := stands.position.z + aisle * longitudinal_scale
			if not selected.has(aisle):
				rail_transforms.append(_transform(side, offset, z, 1.0, longitudinal_scale))
			else:
				# An elongated stand has a wider aisle. Close the space beside
				# the metre-scale staircase, leaving a 2.3m opening in the middle.
				var half_extra := 2.3 * (longitudinal_scale - 1.0) * 0.5
				if half_extra > 0.001:
					for sign_z: float in [-1.0, 1.0]:
						rail_transforms.append(_transform(side, offset, z + sign_z * (1.15 + half_extra * 0.5), 1.0, half_extra / 2.3))
	_add_batch("PierBays", _bay_mesh, bay_transforms)
	_add_batch("UnusedGateAndLandingRailings", _filler_mesh, rail_transforms)
	apply_graphics_quality(_quality)


func _add_route(stand_name: String, side: float, offset: float, aisle: float, z: float, quay_x: float, district: int, bays: Array[Transform3D]) -> void:
	var route := Node3D.new()
	route.name = stand_name + "_Aisle_" + str(int(aisle))
	_access.add_child(route)
	var stair := STAIR_SCENE.instantiate() as Node3D
	stair.name = "AccessStair"
	route.add_child(stair)
	stair.transform = _transform(side, offset, z)
	var gateway := GATEWAY_SCENE.instantiate() as Node3D
	gateway.name = "QuayGateway"
	route.add_child(gateway)
	gateway.transform = _transform(side, quay_x, z)
	var start := offset + STAIR_END_X
	var count := ceili((quay_x - start) / 4.0)
	var span := (quay_x - start) / float(count)
	for index: int in range(count):
		bays.append(_transform(side, start + span * index, z, span / 4.0))
	routes.append({
		"stand": stand_name, "side": side, "aisle": aisle, "world_z": z,
		"entry_x": side * (offset + 8.18), "entry_y": 1.52,
		"quay_x": side * quay_x, "quay_y": QUAY_Y,
		"district": ("West_" if side < 0.0 else "East_") + str(district + 1),
		"bay_count": count, "bay_length": span, "stair_count": 36,
		"riser": (1.52 - QUAY_Y) / 36.0, "clear_gate_width": 2.3,
	})


func _add_batch(label: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty() or mesh == null:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multimesh
	_access.add_child(node)


func apply_graphics_quality(quality: String) -> void:
	_quality = QualityRules.normalize(quality)
	for child: Node in find_children("*", "GeometryInstance3D", true, false):
		var geometry := child as GeometryInstance3D
		geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _quality != QualityRules.LOW and "Seabed" not in geometry.name else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _module_mesh(packed: PackedScene) -> Mesh:
	var root := packed.instantiate()
	var children := root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (children[0] as MeshInstance3D).mesh if not children.is_empty() else null
	root.free()
	return mesh


static func _nearest_district(z: float) -> int:
	var best := 0
	for index: int in range(1, DISTRICT_Z.size()):
		if absf(z - DISTRICT_Z[index]) < absf(z - DISTRICT_Z[best]):
			best = index
	return best


static func _transform(side: float, x: float, z: float, scale_x: float = 1.0, scale_z: float = 1.0) -> Transform3D:
	var basis := Basis(Vector3.UP, PI if side < 0.0 else 0.0).scaled(Vector3(scale_x, 1.0, scale_z))
	return Transform3D(basis, Vector3(side * x, 0.0, z))
