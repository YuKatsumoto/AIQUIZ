class_name StandGate
extends Node3D

## 台座の横の水路（docs/sudden_death_v2/c130_float.md 第4章、skygate_build_plan.md 4.3）。台座の +X の側の横のスタンドのうち、
## 台座の z をはさむ 20 m のブロック 2 つを、海から上がる白い格子の塔 4 本で跳ね橋のように持ち上げる。観客（ブロックごとの
## MultiMesh）も一緒に上がる。水上機はその下を後ろ向きにくぐって入る。
##
## スタンドのブロックのメッシュは杭が海底まで伸びているので、持ち上げるときは「海面より下を切ったメッシュ」の写しに替える
## （元のブロックは隠すだけで、restore() で元に戻す）。スタンドのファイルは変えない。
##
## 使い方：setup(stage_env, podium_center) → activate() → set_towers(t) / set_lift(t)（0〜1）→ restore()

const GLB := "res://assets/sudden_death/stage_gate/stage_gate.glb"
const BLOCK_LENGTH := 20.0
## 持ち上げる高さ（m）。切った杭の下端（海面）が上がって、着水する前の水上機がその下をくぐれる高さ（c130_float.md 第9章：
## 急な進入から機首を起こしながらくぐるので、尾翼の上と 2 m 以上あける）。持ち上げたスタンドの上端は海面から 37.4 m で、
## 塔（40 m、海面の 1 m 下から）の頂上の機械の箱の下に収まる。
const LIFT_HEIGHT := 18.0
## 塔を隠しておく深さ（海面から下、m）と、立ったときの足もと（海面から下）。
const TOWER_HIDDEN := 44.0
const TOWER_BASE := 1.0
## 塔を立てる |x|（スタンドの内側の 0.6 m 内と、外側の 0.6 m 外）と、ブロックの端からの z の出。
const TOWER_X := [26.6, 43.1]
const TOWER_Z_OUT := 0.7

var side := 1.0
var gap_z := 0.0
var sea_y := StageConstants.OCEAN_SURFACE_Y
var lift := 0.0
var towers := 0.0

var _stand: Node3D = null
var _blocks: Array[MeshInstance3D] = []
var _copies: Array[MeshInstance3D] = []
var _crowd: Array[Node3D] = []
var _crowd_rest: Array[float] = []
var _towers: Array[MeshInstance3D] = []
var _active := false
var _ready_ok := false


## stage_env の Grandstands から、台座の +X（side）の側のスタンドを探す。見つからなければ false。
func setup(stage_env: Node, podium_center: Vector3, side_sign := 1.0) -> bool:
	name = "StandGate"
	side = 1.0 if side_sign >= 0.0 else -1.0
	_stand = stage_env.find_child("GrandstandRight" if side > 0.0 else "GrandstandLeft", true, false) as Node3D if stage_env != null else null
	if _stand == null:
		push_warning("[StandGate] grandstand not found")
		return false
	var blocks_node := _stand.get_node_or_null("Blocks")
	if blocks_node == null or blocks_node.get_child_count() < 2:
		return false
	# ブロックは 20 m ごと。境目が台座の z に一番近いところの前後 2 つ。
	var base_z := _stand.global_position.z
	var count := blocks_node.get_child_count()
	var k := clampi(roundi((podium_center.z - base_z) / BLOCK_LENGTH), 1, count - 1)
	gap_z = base_z + BLOCK_LENGTH * float(k)
	_blocks.clear()
	for index in [k - 1, k]:
		var block := blocks_node.get_child(index) as MeshInstance3D
		if block != null:
			_blocks.append(block)
	_crowd.clear()
	_crowd_rest.clear()
	var crowd := _stand.get_node_or_null("Spectators")
	if crowd != null:
		for index in [k - 1, k]:
			for suffix in ["", "Props"]:
				var batch := crowd.get_node_or_null("Block%02d%s" % [index + 1, suffix]) as Node3D
				if batch != null:
					_crowd.append(batch)
					_crowd_rest.append(batch.position.y)
	_ready_ok = _blocks.size() == 2
	return _ready_ok


func is_ready() -> bool:
	return _ready_ok


## 水上機の中心線の z（2 つのブロックの境目）。
func gap_center_z() -> float:
	return gap_z


## 持ち上げる準備：海面より下を切ったブロックの写しを作って元を隠し、塔を海の中に置く。
func activate() -> void:
	if _active or not _ready_ok:
		return
	_active = true
	for block in _blocks:
		var copy := MeshInstance3D.new()
		copy.name = "Lifted_" + String(block.name)
		copy.mesh = _cropped_mesh(block)
		copy.cast_shadow = block.cast_shadow
		copy.lod_bias = block.lod_bias
		copy.gi_mode = block.gi_mode
		add_child(copy)
		copy.global_transform = block.global_transform
		copy.set_meta("rest", copy.global_transform)
		_copies.append(copy)
		block.visible = false
	_build_towers()
	set_towers(0.0)
	set_lift(0.0)


## 塔が海から上がる（0＝海の中、1＝立った）。
func set_towers(t: float) -> void:
	towers = clampf(t, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - towers, 3.0)
	for tower in _towers:
		var rest: Vector3 = tower.get_meta("rest")
		tower.global_position = rest + Vector3(0.0, -TOWER_HIDDEN * (1.0 - e), 0.0)
		tower.visible = towers > 0.0


## スタンドの 2 ブロックと観客が上がる（0〜1 → 0〜LIFT_HEIGHT m）。
func set_lift(t: float) -> void:
	lift = clampf(t, 0.0, 1.0)
	var h := LIFT_HEIGHT * lift
	for copy in _copies:
		var rest: Transform3D = copy.get_meta("rest")
		copy.global_transform = Transform3D(rest.basis, rest.origin + Vector3(0.0, h, 0.0))
	for i in range(_crowd.size()):
		_crowd[i].position.y = _crowd_rest[i] + h


## 持ち上げた写しの一番下（ワールドの y）。テストで尾翼とのすき間を測る。
func lifted_bottom_y() -> float:
	var bottom := INF
	for copy in _copies:
		var box := copy.global_transform * copy.get_aabb()
		bottom = minf(bottom, box.position.y)
	return bottom


## 元に戻す（写しと塔を消し、元のブロックと観客を戻す）。
func restore() -> void:
	for copy in _copies:
		copy.queue_free()
	_copies.clear()
	for block in _blocks:
		if is_instance_valid(block):
			block.visible = true
	for i in range(_crowd.size()):
		if is_instance_valid(_crowd[i]):
			_crowd[i].position.y = _crowd_rest[i]
	for tower in _towers:
		tower.queue_free()
	_towers.clear()
	lift = 0.0
	towers = 0.0
	_active = false


func _build_towers() -> void:
	var mesh := _glb_mesh("SG_Tower")
	if mesh == null:
		return
	var z0 := gap_z - BLOCK_LENGTH - TOWER_Z_OUT
	var z1 := gap_z + BLOCK_LENGTH + TOWER_Z_OUT
	for x: float in TOWER_X:
		for z in [z0, z1]:
			var tower := MeshInstance3D.new()
			tower.name = "LiftTower"
			tower.mesh = mesh
			tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(tower)
			var rest := Vector3(x * side, sea_y - TOWER_BASE, z)
			tower.global_position = rest
			tower.set_meta("rest", rest)
			_towers.append(tower)


## ブロックのメッシュから、海面より下を切った写しを作る。三角形が全部海面より下なら捨て、残る頂点は海面で止める
## （海底まで伸びた杭は海面の高さで切れる）。
func _cropped_mesh(block: MeshInstance3D) -> ArrayMesh:
	var source := block.mesh
	var out := ArrayMesh.new()
	if source == null:
		return out
	var clip := (block.global_transform.affine_inverse() * Vector3(0.0, sea_y, 0.0)).y
	for s in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(vertices.size())
			for i in range(vertices.size()):
				indices[i] = i
		var kept := PackedInt32Array()
		for i in range(0, indices.size() - 2, 3):
			var a := indices[i]
			var b := indices[i + 1]
			var c := indices[i + 2]
			if vertices[a].y < clip and vertices[b].y < clip and vertices[c].y < clip:
				continue
			kept.append(a)
			kept.append(b)
			kept.append(c)
		if kept.is_empty():
			continue
		for i in range(vertices.size()):
			if vertices[i].y < clip:
				vertices[i].y = clip
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, source.surface_get_material(s))
	return out


static var _glb_cache: Node3D = null


static func _glb_mesh(mesh_name: String) -> Mesh:
	if _glb_cache == null:
		var scene := load(GLB) as PackedScene
		if scene == null:
			return null
		_glb_cache = scene.instantiate() as Node3D
	var node := _glb_cache.find_child(mesh_name, true, false) as MeshInstance3D
	return node.mesh if node != null else null


static func glb_mesh(mesh_name: String) -> Mesh:
	return _glb_mesh(mesh_name)
