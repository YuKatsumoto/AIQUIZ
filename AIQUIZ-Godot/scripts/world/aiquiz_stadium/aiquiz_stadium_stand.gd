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
## Spectators of the cut block hide this far before the cut, so nobody sits on a
## half-cut chair (half the 0.92 m seat pitch).
const SEAT_CLEARANCE := 0.46
## The cut block runs this far into the moved cap, so no crack opens at the cut.
const CUT_OVERLAP := 0.02
const NO_CLIP := 1e9

static var _meshes := {}
static var _layout := {}
## _front_cap_overhang() per cap kind and side.
static var _overhangs := {}

var block_count := 0
var side := 1.0
var crowd: Node3D = null
var _blocks: Node3D = null
## fit_end() state: the inputs it last ran with, how far the front cap is moved
## back along world z and the block cut under it (-1 none).
var _fit_end_z := NAN
var _fit_start_z := NAN
var _fit_blocks := -1
var _cap_shift := 0.0
var _cut_index := -1


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
	# The front cap becomes a bay: undo fit_end() first (the caller fits again).
	_reset_fit()
	var previous := block_count
	block_count = count
	# Only the old front cap changes kind; the blocks behind it keep theirs.
	for index: int in range(maxi(previous - 1, 0), block_count):
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
	_place_mascot()
	_update_crowd_layout()
	return true


## Lets the crowd walk (CrowdSim, docs/crowd_sim.md) with `pool` people on foot
## at a time and `vendors` beer vendors. Call right after setup().
func enable_crowd_sim(pool: int, vendors := 0) -> void:
	if crowd != null:
		crowd.enable_sim(pool, vendors)


## Tells the walking crowd where the blocks, booths and aisles are (stand space).
func _update_crowd_layout() -> void:
	if crowd == null or crowd.sim == null:
		return
	var centers: Array[float] = []
	var kinds: Array[String] = []
	var aisles: Array[float] = []
	for index: int in range(block_count):
		centers.append(block_center_z(index))
		kinds.append(block_kind(index))
		for aisle: float in (_layout["blocks"][block_kind(index)] as Dictionary)["aisle_z"]:
			aisles.append(block_center_z(index) + aisle)
	crowd.set_layout(centers, kinds, aisles, _layout.get("walk", {}))


## Ends the stand at world z `end_z` (the goal stand's monitor; INF = its own end).
## The front cap moves back so its far end meets end_z, the bays it now covers hide
## and the bay it overlaps is cut at the cap's start (AiquizStadiumMaterials.far_clipped(),
## seated_spectator.gdshader far_clip_z), so the stand runs on unbroken up to the
## monitor and still ends in its cap. When the stand is too short to keep a bay
## before the cap, whole blocks past end_z hide instead. Cheap to call every frame.
func fit_end(end_z: float) -> void:
	if not is_inside_tree() or block_count == 0:
		return
	var start_z := global_position.z
	if end_z == _fit_end_z and start_z == _fit_start_z and block_count == _fit_blocks:
		return
	_fit_end_z = end_z
	_fit_start_z = start_z
	_fit_blocks = block_count
	var front := block_count - 1
	var natural_end := start_z + length()
	var cap_start := end_z - BLOCK_LENGTH
	# The back cap stays whole: the cut must fall past block 0.
	var fits := end_z < natural_end and cap_start > start_z + BLOCK_LENGTH
	var cut := ceili((cap_start - start_z) / BLOCK_LENGTH) - 1 if fits else -1
	var shown_count := 0
	for index: int in range(block_count):
		var shown := start_z + BLOCK_LENGTH * (index + 1) <= end_z
		if fits:
			shown = index <= cut or index == front
		elif shown:
			shown_count += 1
		_show_block(index, shown)
	_move_front_cap(end_z - natural_end if fits else 0.0)
	_cut_block(cut, cap_start)
	_set_crowd_reach(end_z - start_z if fits else BLOCK_LENGTH * shown_count)


## The front cap's aisle reaching back over the block before it (the right stand's
## cap_start owns the aisle on its near edge; the left stand's cap has none):
## x = from, y = to (block-local x, away from the course), z = depth along world z.
func _front_cap_overhang() -> Vector3:
	var kind := block_kind(block_count - 1)
	var key := "%s%+d" % [kind, int(side)]
	if not _overhangs.has(key):
		# Blocks run along world +Z on both sides; the left stand is turned PI, so its
		# near edge is the block's local +Z.
		var band := Vector3(INF, -INF, 0.0)
		var mesh := _meshes[kind] as ArrayMesh
		for surface: int in range(mesh.get_surface_count()):
			for vertex: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				var depth := -side * vertex.z - BLOCK_LENGTH * 0.5
				if depth > 0.01:
					band = Vector3(minf(band.x, vertex.x), maxf(band.y, vertex.x), maxf(band.z, depth))
		_overhangs[key] = band if band.z > 0.0 else Vector3.ZERO
	return _overhangs[key]


func _reset_fit() -> void:
	_move_front_cap(0.0)
	_cut_block(-1, 0.0)
	for index: int in range(block_count):
		_show_block(index, true)
	_set_crowd_reach(length())
	_fit_end_z = NAN


## The walking crowd keeps to the first `reach` metres of the stand (along world
## +Z from its back end); past them the blocks are hidden.
func _set_crowd_reach(reach: float) -> void:
	if crowd != null:
		# Blocks run along world +Z on both sides; the left stand is turned PI.
		crowd.set_walk_z(0.0 if side > 0.0 else -reach, reach if side > 0.0 else 0.0)


## The block's spectator batches (GrandstandCrowd: plain and prop holders).
func _crowd_batches(index: int) -> Array[GeometryInstance3D]:
	var batches: Array[GeometryInstance3D] = []
	if crowd == null:
		return batches
	for suffix: String in ["", "Props"]:
		var batch := crowd.get_node_or_null("Block%02d%s" % [index + 1, suffix]) as GeometryInstance3D
		if batch != null:
			batches.append(batch)
	return batches


func _show_block(index: int, shown: bool) -> void:
	(_blocks.get_child(index) as Node3D).visible = shown
	for batch: GeometryInstance3D in _crowd_batches(index):
		batch.visible = shown


## Moves the front cap (and its spectators) `shift` metres along world z.
func _move_front_cap(shift: float) -> void:
	if shift == _cap_shift:
		return
	_cap_shift = shift
	var front := block_count - 1
	# Blocks run along world +Z on both sides; the left stand is turned PI.
	(_blocks.get_child(front) as Node3D).position.z = block_center_z(front) + side * shift
	for batch: GeometryInstance3D in _crowd_batches(front):
		batch.position.z = side * shift


## Cuts block `index` where the front cap, starting at world z `cap_start`, takes
## over (-1: no block is cut). Within the cap's aisle overhang (seats and stairs)
## the cut comes that much earlier; the walls and deck edges run on to cap_start.
func _cut_block(index: int, cap_start: float) -> void:
	if _cut_index >= 0 and _cut_index != index:
		var previous := _blocks.get_child(_cut_index) as MeshInstance3D
		for surface: int in range(previous.get_surface_override_material_count()):
			previous.set_surface_override_material(surface, null)
		for batch: GeometryInstance3D in _crowd_batches(_cut_index):
			batch.set_instance_shader_parameter(Materials.FAR_CLIP_Z, NO_CLIP)
	_cut_index = index
	if index < 0:
		return
	var overhang := _front_cap_overhang()
	var aisle_clip := cap_start - overhang.z + CUT_OVERLAP
	var block := _blocks.get_child(index) as MeshInstance3D
	for surface: int in range(block.mesh.get_surface_count()):
		var original := block.mesh.surface_get_material(surface)
		var clipped := Materials.far_clipped(original)
		block.set_surface_override_material(surface, clipped if clipped != original else null)
	block.set_instance_shader_parameter(Materials.FAR_CLIP_Z, cap_start + CUT_OVERLAP)
	block.set_instance_shader_parameter(Materials.AISLE_CLIP_Z, aisle_clip)
	block.set_instance_shader_parameter(Materials.AISLE_BAND, Vector2(overhang.x, overhang.y))
	for batch: GeometryInstance3D in _crowd_batches(index):
		batch.set_instance_shader_parameter(Materials.FAR_CLIP_Z, aisle_clip - SEAT_CLEARANCE)


## The crowd's mascot stands in the aisle nearest CrowdScript.MASCOT_ALONG.
func _place_mascot() -> void:
	if crowd == null or crowd.mascot != null:
		return
	var best := INF
	for offset: float in aisle_offsets_z():
		if absf(offset - CrowdScript.MASCOT_ALONG) < absf(best - CrowdScript.MASCOT_ALONG):
			best = offset
	if absf(best - CrowdScript.MASCOT_ALONG) < 15.0:
		# Aisle offsets run along world +Z; the left stand is turned PI.
		crowd.add_mascot(best * side)


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
