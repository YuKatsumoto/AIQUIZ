@tool
extends Node3D

## One side stand of AIQUIZ STADIUM, built from 20 m blocks
## (assets/aiquiz_stadium/aiquiz_stadium_stand_blocks.glb, source/blender/build_stadium.py).
## Same contract as santorini_terrace_stand.gd: the origin is the conveyor's back
## end, the right stand (+X) is not rotated, the left one is turned PI, blocks run
## along world +Z on both sides and every block but the far cap owns an aisle on
## its local -Z edge. Blocks are added as the conveyor grows and never removed.
##
## The stands carry no sails: the sail rigs (aiquiz_stadium_sail_rigs.glb) are
## still exported by the builder but are not placed. The masts, yards and shrouds
## belong to the block meshes and stay.

const WaterfrontScript = preload("res://scripts/world/santorini_waterfront.gd")
const CrowdScript = preload("res://scripts/world/grandstand_crowd.gd")
const Materials = preload("res://scripts/world/aiquiz_stadium/aiquiz_stadium_materials.gd")
const MODULE_SCENE_PATH := "res://assets/aiquiz_stadium/aiquiz_stadium_stand_blocks.glb"
const LAYOUT_PATH := "res://assets/aiquiz_stadium/aiquiz_stadium_stand_blocks.json"
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
	# Sea piles reach the stage seabed (the GLB stops at the authored -17.2 m).
	WaterfrontScript.extend_stand_supports(scene)
	Materials.apply(scene)
	for kind: String in _layout["blocks"]:
		var node_name: String = (_layout["blocks"][kind] as Dictionary)["node"]
		_meshes[kind] = (scene.find_child(node_name, true, false) as MeshInstance3D).mesh
	scene.free()
