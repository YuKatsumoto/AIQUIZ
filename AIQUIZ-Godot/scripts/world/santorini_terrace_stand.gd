@tool
extends Node3D

## One side stand built from 20 m terrace blocks (santorini_terrace_modules.glb,
## source/build_terrace_modules.py). Blocks are added as the conveyor grows, so
## seats, stairs and pergolas keep their size instead of being stretched.
##
## The stand's origin is the conveyor's back end. The right stand (+X) is not
## rotated; the left one is turned PI so it faces the course, which makes its
## local -Z point down the course. Blocks therefore run along world +Z on both
## sides. Every block but the far cap owns an aisle on its local -Z edge.

const WaterfrontScript = preload("res://scripts/world/santorini_waterfront.gd")
const CrowdScript = preload("res://scripts/world/grandstand_crowd.gd")
const MODULE_SCENE_PATH := "res://assets/environment/santorini_grandstand/santorini_terrace_modules.glb"
const LAYOUT_PATH := "res://assets/environment/santorini_grandstand/santorini_terrace_modules.json"
const BLOCK_LENGTH := 20.0
const MIN_BLOCKS := 2
const PERGOLA_EVERY := 3

static var _meshes := {}
static var _layout := {}

var block_count := 0
var side := 1.0
var crowd: Node3D = null
var _blocks: Node3D = null


## side_sign: +1 right stand (+X, P1), -1 left stand (-X, P2).
func setup(side_sign: float, crowd_density: float, crowd_seed: int) -> void:
	side = 1.0 if side_sign >= 0.0 else -1.0
	name = "GrandstandRight" if side > 0.0 else "GrandstandLeft"
	rotation = Vector3(0.0, 0.0 if side > 0.0 else PI, 0.0)
	_ensure_modules()
	_blocks = Node3D.new()
	_blocks.name = "Blocks"
	add_child(_blocks)
	if crowd_density > 0.0:
		crowd = CrowdScript.new()
		crowd.name = "Spectators"
		add_child(crowd)
		crowd.setup(crowd_density, crowd_seed, 1 if side > 0.0 else 2)


static func blocks_for_length(length: float) -> int:
	return maxi(MIN_BLOCKS, ceili(length / BLOCK_LENGTH - 0.001))


func length() -> float:
	return BLOCK_LENGTH * block_count


## Grows the stand to at least `count` blocks. Blocks are never removed, so a
## shorter conveyor later in the round leaves the stand untouched.
func ensure_blocks(count: int) -> bool:
	if count <= block_count:
		return false
	var previous := block_count
	block_count = count
	for index: int in range(block_count):
		var block: MeshInstance3D = null
		if index < previous:
			block = _blocks.get_child(index) as MeshInstance3D
		else:
			block = MeshInstance3D.new()
			block.name = "Block%02d" % (index + 1)
			block.position = Vector3(0.0, 0.0, block_center_z(index))
			_blocks.add_child(block)
			if crowd != null:
				crowd.add_block(index, block_center_z(index), block_seats(index))
		var kind := block_kind(index)
		block.set_meta("kind", kind)
		block.mesh = _meshes[kind]
	return true


## Block centre in stand-local Z (see the class comment for the direction).
func block_center_z(index: int) -> float:
	return side * BLOCK_LENGTH * (float(index) + 0.5)


func block_kind(index: int) -> String:
	# The block with the largest local Z closes that end, the smallest the other.
	var top := block_count - 1 if side > 0.0 else 0
	var bottom := 0 if side > 0.0 else block_count - 1
	if index == top:
		return "cap_start"
	if index == bottom:
		return "cap_end"
	return "bay_pergola" if index % PERGOLA_EVERY == 1 else "bay"


func block_seats(index: int) -> Array:
	return (_layout["blocks"][block_kind(index)] as Dictionary)["seats"]


## Aisle positions along world Z, relative to the stand origin.
func aisle_offsets_z() -> Array[float]:
	var offsets: Array[float] = []
	for index: int in range(block_count):
		for aisle: float in (_layout["blocks"][block_kind(index)] as Dictionary)["aisle_z"]:
			offsets.append(side * (block_center_z(index) + aisle))
	offsets.sort()
	return offsets


static func _ensure_modules() -> void:
	if not _meshes.is_empty():
		return
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var scene := (load(MODULE_SCENE_PATH) as PackedScene).instantiate() as Node3D
	# Sea piers reach the stage seabed (the GLB stops at the authored -17.2 m).
	WaterfrontScript.extend_stand_supports(scene)
	var painted := StandardMaterial3D.new()
	painted.resource_name = "Santorini terrace painted"
	painted.vertex_color_use_as_albedo = true
	painted.roughness = 0.78
	for kind: String in _layout["blocks"]:
		var node_name: String = (_layout["blocks"][kind] as Dictionary)["node"]
		var source := scene.find_child(node_name, true, false) as MeshInstance3D
		var mesh := source.mesh
		for surface: int in range(mesh.get_surface_count()):
			var original := mesh.surface_get_material(surface)
			if original != null and original.resource_name.begins_with("Lantern"):
				# Lantern glass carries a vertex colour too; keep the authored glow only.
				var glass := original.duplicate() as BaseMaterial3D
				glass.vertex_color_use_as_albedo = false
				mesh.surface_set_material(surface, glass)
			else:
				mesh.surface_set_material(surface, painted)
		_meshes[kind] = mesh
	scene.free()
