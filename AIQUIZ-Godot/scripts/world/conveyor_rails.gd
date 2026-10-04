@tool
extends Node3D
class_name ConveyorRails

## Shared, non-colliding running rails for every conveyor presentation.
const StageMaterialsScript = preload("res://scripts/world/stage_materials.gd")
const CENTER_X := 11.86
const TOP_HEIGHT := 0.26
var left_head: MeshInstance3D
var right_head: MeshInstance3D
var _long_parts: Array[MeshInstance3D] = []
var _caps: Array[MeshInstance3D] = []
## Galvanised head and web / painted mounting base and end caps (StageMaterials).
var _head_parts: Array[MeshInstance3D] = []
var _support_parts: Array[MeshInstance3D] = []
var _center := INF
var _length := -1.0
var _floor_y := 0.0

func build(center_z: float, length: float, floor_y: float) -> void:
	for side in [-1, 1]:
		var prefix := "Left" if side < 0 else "Right"
		var x: float = CENTER_X * side
		var head := _part(prefix + "RunningHead", Vector3(0.16, 0.04, 1.0), Vector3(x, 0.24, 0.0), _head_parts)
		if side < 0: left_head = head
		else: right_head = head
		_long_parts.append(head)
		_long_parts.append(_part(prefix + "Web", Vector3(0.06, 0.12, 1.0), Vector3(x, 0.16, 0.0), _head_parts))
		_long_parts.append(_part(prefix + "MountingBase", Vector3(0.24, 0.06, 1.0), Vector3(x, 0.07, 0.0), _support_parts))
		for end in [-1, 1]:
			var cap := _part(prefix + "EndCap" + str(end), Vector3(0.24, 0.1, 0.08), Vector3(x, 0.09, 0.0), _support_parts)
			cap.set_meta("end", end)
			_caps.append(cap)
	apply_graphics_quality(StageMaterialsScript.current_quality())
	set_geometry(center_z, length, floor_y)

## Steel materials for `q` (StageEnvironment calls this again when the graphics quality changes).
func apply_graphics_quality(q: String) -> void:
	var head_material: Material = StageMaterialsScript.rail_head(q)
	var support_material: Material = StageMaterialsScript.rail_support(q)
	for part in _head_parts:
		part.material_override = head_material
	for part in _support_parts:
		part.material_override = support_material

func _part(part_name: String, size: Vector3, at: Vector3, group: Array[MeshInstance3D]) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.position = at
	add_child(part)
	group.append(part)
	return part

func set_geometry(center_z: float, length: float, floor_y: float) -> void:
	length = maxf(length, 0.16)
	if is_equal_approx(center_z, _center) and is_equal_approx(length, _length) and is_equal_approx(floor_y, _floor_y):
		return
	_center = center_z
	_length = length
	_floor_y = floor_y
	position = Vector3(0.0, floor_y, center_z)
	for part in _long_parts:
		var box := part.mesh as BoxMesh
		box.size.z = length
	for cap in _caps:
		cap.position.z = float(cap.get_meta("end")) * (length * 0.5 - 0.04)
