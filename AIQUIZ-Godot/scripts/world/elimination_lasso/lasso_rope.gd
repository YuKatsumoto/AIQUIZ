class_name LassoRope
extends Node3D

## 投げ縄の縄（両者脱落のあと、雲に乗ったハテナがプレイヤーの魂をゴールへ運ぶ演出。EliminationLassoDirector）。
## 縄は粒の列（Verlet）2 本：手から結び目（ホンダ）までの「幹」と、結び目から始まって閉じる「輪」。
## 演出は毎フレーム、手の位置・幹と輪の長さ・輪の目標の形と寄せる強さ・結び目の固定・当たり（魂のカプセルと床）を
## 渡して simulate() を呼ぶ。幹は重力と空気の抵抗で垂れ、なびき、張る。輪は目標の形（頭上で回る円・飛ぶ円・
## 2 人の胸に巻きつく輪郭）へばねで寄りながら、慣性と重力で遅れ・たわむ。
## 描き方は粒をなめらかな曲線（Catmull-Rom）でつないだ管（lasso_rope.gdshader の三つよりの縄）。左手の束（コイル）と、
## 束から右手までのたるみ、輪の結び目も描く。座標はすべて親（演出の根 = GameWorld のローカル）の空間。

const ROPE_SHADER := preload("res://assets/characters/aiquiz_mascot/lasso_rope.gdshader")
const STEM_COUNT := 40
const LOOP_COUNT := 56
const SUBSTEPS := 4
const ITERATIONS := 6

enum LoopMode { FREE, SHAPED, BOUND }

var rope_radius := 0.034
var sides := 12
var subdivisions := 3
var gravity := Vector3(0.0, -9.8, 0.0)
## 幹の始まり（右手）。simulate() の小刻みのあいだに、前の値から今の値へ動かす。
var hand := Vector3.ZERO
var stem_length := 0.5
var loop_length := 2.0
var loop_mode := LoopMode.FREE
var loop_targets := PackedVector3Array()
## 小刻み 1 回ごとに輪の粒を目標へ寄せる割合（0〜1）。
var loop_stiffness := 0.0
var honda_pinned := false
var honda_target := Vector3.ZERO
## 空気の抵抗（1 秒あたりに速さが減る割合）。
var stem_drag := 0.8
var loop_drag := 1.2
var floor_y := -INF
## 当たり：[a: Vector3, b: Vector3, r: float] の配列（線分のまわりの半径 r に入らない）。
var capsules: Array = []
## 左手の束（コイル）と、束から右手までのたるみ。
var coil_visible := true
var coil_transform := Transform3D.IDENTITY
var coil_radius := 0.15
var slack_sag := 0.22
## たるみを体の前へふくらませる向きと量（ハテナの前）
var slack_bulge := Vector3.ZERO

var _stem := PackedVector3Array()
var _stem_prev := PackedVector3Array()
var _loop := PackedVector3Array()
var _loop_prev := PackedVector3Array()
var _hand_prev := Vector3.ZERO
var _mesh := ArrayMesh.new()
var _mesh_instance: MeshInstance3D
var _knot: MeshInstance3D
var _material: ShaderMaterial
var _ring_cos := PackedFloat32Array()
var _ring_sin := PackedFloat32Array()
var _twist_pitch := 0.17
var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _tangents := PackedFloat32Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


func setup(radius: float, quality: String) -> void:
	rope_radius = radius
	var low := not GraphicsQuality.is_at_least(GraphicsQuality.normalize(quality), GraphicsQuality.BALANCED)
	sides = 8 if low else 12
	subdivisions = 2 if low else 3
	_twist_pitch = radius * 5.0
	_material = ShaderMaterial.new()
	_material.shader = ROPE_SHADER
	_material.set_shader_parameter("rope_radius", radius)
	_material.set_shader_parameter("twist_pitch", _twist_pitch)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "LassoRopeMesh"
	_mesh_instance.mesh = _mesh
	_mesh_instance.material_override = _material
	_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh_instance)
	# 結び目（ホンダ）：輪の始まりの小さなふくらみ
	var knot_mesh := CapsuleMesh.new()
	knot_mesh.radius = radius * 1.8
	knot_mesh.height = radius * 6.5
	knot_mesh.radial_segments = 12
	knot_mesh.rings = 4
	var knot_material := StandardMaterial3D.new()
	knot_material.albedo_color = Color(0.72, 0.56, 0.34)
	knot_material.roughness = 0.9
	_knot = MeshInstance3D.new()
	_knot.name = "LassoHonda"
	_knot.mesh = knot_mesh
	_knot.material_override = knot_material
	add_child(_knot)
	_ring_cos.resize(sides + 1)
	_ring_sin.resize(sides + 1)
	for j in range(sides + 1):
		var angle := TAU * float(j) / float(sides)
		_ring_cos[j] = cos(angle)
		_ring_sin[j] = sin(angle)
	_stem.resize(STEM_COUNT)
	_stem_prev.resize(STEM_COUNT)
	_loop.resize(LOOP_COUNT)
	_loop_prev.resize(LOOP_COUNT)
	loop_targets.resize(LOOP_COUNT)


## 手から垂れた小さな輪の形で始める（雲が飛んでくるあいだ）。
func reset_hanging(hand_position: Vector3, side: Vector3, loop_radius: float, stem: float) -> void:
	hand = hand_position
	_hand_prev = hand_position
	stem_length = stem
	loop_length = TAU * loop_radius
	var down := Vector3.DOWN
	for i in range(STEM_COUNT):
		var p := hand_position + down * stem * float(i) / float(STEM_COUNT - 1)
		_stem[i] = p
		_stem_prev[i] = p
	var honda := _stem[STEM_COUNT - 1]
	var center := honda + down * loop_radius
	var across := side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	for i in range(LOOP_COUNT):
		var angle := TAU * float(i) / float(LOOP_COUNT)
		var p := center + (-down * cos(angle) + across * sin(angle)) * loop_radius
		_loop[i] = p
		_loop_prev[i] = p
		loop_targets[i] = p


func get_honda() -> Vector3:
	return _loop[0]


func get_loop_point(index: int) -> Vector3:
	return _loop[posmod(index, LOOP_COUNT)]


func get_loop_center() -> Vector3:
	var sum := Vector3.ZERO
	for p in _loop:
		sum += p
	return sum / float(LOOP_COUNT)


func get_stem_point(index: int) -> Vector3:
	return _stem[clampi(index, 0, STEM_COUNT - 1)]


## 幹の今の長さ（粒をたどった長さ。張っていれば手から結び目までの距離に近い）。
func get_stem_span() -> float:
	var total := 0.0
	for i in range(1, STEM_COUNT):
		total += _stem[i].distance_to(_stem[i - 1])
	return total


## 輪の粒を一度に動かす（雲や束が大きく動いたときに、輪だけ遅れて伸びないように）。
func shift_loop(offset: Vector3) -> void:
	for i in range(LOOP_COUNT):
		_loop[i] += offset
		_loop_prev[i] += offset


func simulate(delta: float) -> void:
	var dt := clampf(delta, 0.0, 1.0 / 20.0)
	if dt <= 0.0:
		_hand_prev = hand
		return
	var h := dt / float(SUBSTEPS)
	var stem_rest := maxf(stem_length, 0.05) / float(STEM_COUNT - 1)
	var loop_rest := maxf(loop_length, 0.1) / float(LOOP_COUNT)
	var k_shape := clampf(loop_stiffness, 0.0, 1.0)
	var shaped := loop_mode != LoopMode.FREE and k_shape > 0.0
	var stem_damp := maxf(0.0, 1.0 - stem_drag * h)
	var loop_damp := maxf(0.0, 1.0 - loop_drag * h)
	var g := gravity * h * h
	for step in range(SUBSTEPS):
		var hand_now := _hand_prev.lerp(hand, float(step + 1) / float(SUBSTEPS))
		for i in range(STEM_COUNT):
			var p := _stem[i]
			var v := (p - _stem_prev[i]) * stem_damp
			_stem_prev[i] = p
			_stem[i] = p + v + g
		for i in range(LOOP_COUNT):
			var p := _loop[i]
			var v := (p - _loop_prev[i]) * loop_damp
			_loop_prev[i] = p
			_loop[i] = p + v + g
		if shaped:
			for i in range(LOOP_COUNT):
				_loop[i] += (loop_targets[i] - _loop[i]) * k_shape
		for _iteration in range(ITERATIONS):
			_stem[0] = hand_now
			_solve_stem(stem_rest)
			_solve_loop(loop_rest)
			_join_honda()
			_stem[0] = hand_now
		_collide()
		_stem[0] = hand_now
		if honda_pinned:
			_stem[STEM_COUNT - 1] = honda_target
			_loop[0] = honda_target
	_hand_prev = hand


func _solve_stem(rest: float) -> void:
	var last := STEM_COUNT - 1
	for i in range(last):
		var a := _stem[i]
		var b := _stem[i + 1]
		var d := b - a
		var length := d.length()
		if length < 1e-6:
			continue
		var correction := d * ((length - rest) / length)
		var wa := 0.0 if i == 0 else 0.5
		var wb := 0.0 if (i + 1 == last and honda_pinned) else 0.5
		var total := wa + wb
		if total <= 0.0:
			continue
		_stem[i] = a + correction * (wa / total)
		_stem[i + 1] = b - correction * (wb / total)


func _solve_loop(rest: float) -> void:
	for i in range(LOOP_COUNT):
		var j := (i + 1) % LOOP_COUNT
		var a := _loop[i]
		var b := _loop[j]
		var d := b - a
		var length := d.length()
		if length < 1e-6:
			continue
		var correction := d * ((length - rest) / length)
		var wa := 0.0 if (i == 0 and honda_pinned) else 0.5
		var wb := 0.0 if (j == 0 and honda_pinned) else 0.5
		var total := wa + wb
		if total <= 0.0:
			continue
		_loop[i] = a + correction * (wa / total)
		_loop[j] = b - correction * (wb / total)


func _join_honda() -> void:
	var last := STEM_COUNT - 1
	if honda_pinned:
		_stem[last] = honda_target
		_loop[0] = honda_target
		return
	# 結び目は輪の側がやや重い（輪の粒の方が動きにくい）
	var joined := _stem[last].lerp(_loop[0], 0.6)
	_stem[last] = joined
	_loop[0] = joined


func _collide() -> void:
	var min_y := floor_y + rope_radius
	for capsule: Array in capsules:
		var a: Vector3 = capsule[0]
		var b: Vector3 = capsule[1]
		var reach: float = float(capsule[2]) + rope_radius
		var ab := b - a
		var ab_len2 := maxf(ab.length_squared(), 1e-6)
		for i in range(LOOP_COUNT):
			var p := _loop[i]
			var t := clampf((p - a).dot(ab) / ab_len2, 0.0, 1.0)
			var c := a + ab * t
			var d := p - c
			var dist := d.length()
			if dist < reach and dist > 1e-5:
				_loop[i] = c + d * (reach / dist)
	if is_finite(min_y):
		for i in range(STEM_COUNT):
			if _stem[i].y < min_y:
				_stem[i].y = min_y
				# 床をこする摩擦
				_stem_prev[i] = _stem_prev[i].lerp(Vector3(_stem[i].x, _stem_prev[i].y, _stem[i].z), 0.4)
		for i in range(LOOP_COUNT):
			if _loop[i].y < min_y:
				_loop[i].y = min_y
				_loop_prev[i] = _loop_prev[i].lerp(Vector3(_loop[i].x, _loop_prev[i].y, _loop[i].z), 0.4)


# ------------------------------------------------------------------ drawing

func rebuild_mesh() -> void:
	_verts.clear()
	_normals.clear()
	_tangents.clear()
	_uvs.clear()
	_indices.clear()
	_append_tube(_smooth(_stem, false), false, 0.0)
	_append_tube(_smooth(_loop, true), true, 0.0)
	if coil_visible:
		_append_slack()
		_append_coils()
	_mesh.clear_surfaces()
	if _verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TANGENT] = _tangents
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var forward := (_loop[1] - _loop[LOOP_COUNT - 1])
	if forward.length_squared() > 1e-8:
		var y := forward.normalized()
		var x := y.cross(Vector3.UP)
		if x.length_squared() < 1e-6:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		_knot.transform = Transform3D(Basis(x, y, x.cross(y)), _loop[0])


func _smooth(points: PackedVector3Array, closed: bool) -> PackedVector3Array:
	var n := points.size()
	var out := PackedVector3Array()
	if n < 2:
		return out
	var segments := n if closed else n - 1
	for i in range(segments):
		var p0 := points[posmod(i - 1, n)] if closed else points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[(i + 1) % n]
		var p3 := points[(i + 2) % n] if closed else points[mini(i + 2, n - 1)]
		for s in range(subdivisions):
			var t := float(s) / float(subdivisions)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	if not closed:
		out.append(points[n - 1])
	return out


func _append_tube(path: PackedVector3Array, closed: bool, uv_offset: float, radius := -1.0) -> void:
	var n := path.size()
	if n < 2:
		return
	var r := rope_radius if radius < 0.0 else radius
	var tangents := PackedVector3Array()
	tangents.resize(n)
	var previous := Vector3.FORWARD
	for i in range(n):
		var d: Vector3
		if closed:
			d = path[(i + 1) % n] - path[posmod(i - 1, n)]
		else:
			d = path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]
		previous = d.normalized() if d.length_squared() > 1e-12 else previous
		tangents[i] = previous
	# 平行移動の枠（管がねじれない）。輪は一周して戻ったときのずれを均等に配って継ぎ目をなくす。
	var frames := PackedVector3Array()
	frames.resize(n)
	var first := tangents[0].cross(Vector3.UP)
	if first.length_squared() < 1e-6:
		first = tangents[0].cross(Vector3.RIGHT)
	frames[0] = first.normalized()
	for i in range(1, n):
		frames[i] = _transport(frames[i - 1], tangents[i - 1], tangents[i])
	var lengths := PackedFloat32Array()
	lengths.resize(n + 1)
	lengths[0] = 0.0
	for i in range(1, n):
		lengths[i] = lengths[i - 1] + path[i].distance_to(path[i - 1])
	var total := lengths[n - 1]
	var uv_scale := 1.0
	if closed:
		total += path[n - 1].distance_to(path[0])
		lengths[n] = total
		var wrapped := _transport(frames[n - 1], tangents[n - 1], tangents[0])
		var twist := atan2(tangents[0].dot(wrapped.cross(frames[0])), wrapped.dot(frames[0]))
		for i in range(1, n):
			frames[i] = frames[i].rotated(tangents[i], twist * float(i) / float(n))
		# よりの模様が継ぎ目で合うよう、1 周の長さをピッチの整数倍にそろえる
		var turns := maxf(1.0, roundf(total / _twist_pitch))
		uv_scale = turns * _twist_pitch / maxf(total, 1e-4)
	var ring_count := n + (1 if closed else 0)
	var base := _verts.size()
	for i in range(ring_count):
		var index := i % n
		var center := path[index]
		var t := tangents[index]
		var nn := frames[index]
		var b := t.cross(nn)
		var u := lengths[i] * uv_scale + uv_offset
		for j in range(sides + 1):
			var dir := nn * _ring_cos[j] + b * _ring_sin[j]
			_verts.append(center + dir * r)
			_normals.append(dir)
			_tangents.append(t.x)
			_tangents.append(t.y)
			_tangents.append(t.z)
			_tangents.append(-1.0)
			_uvs.append(Vector2(u, float(j) / float(sides)))
	var stride := sides + 1
	for i in range(ring_count - 1):
		var row := base + i * stride
		var next := row + stride
		for j in range(sides):
			_indices.append(row + j)
			_indices.append(next + j)
			_indices.append(row + j + 1)
			_indices.append(row + j + 1)
			_indices.append(next + j)
			_indices.append(next + j + 1)


static func _transport(frame: Vector3, from_tangent: Vector3, to_tangent: Vector3) -> Vector3:
	var axis := from_tangent.cross(to_tangent)
	var result := frame
	if axis.length_squared() > 1e-12:
		var angle := acos(clampf(from_tangent.dot(to_tangent), -1.0, 1.0))
		result = frame.rotated(axis.normalized(), angle)
	result = result - to_tangent * result.dot(to_tangent)
	return result.normalized() if result.length_squared() > 1e-12 else frame


## 右手から左手の束までのたるみ（2 次ベジェ）。
func _append_slack() -> void:
	var start := hand
	var finish := coil_transform.origin
	var span := start.distance_to(finish)
	var control := (start + finish) * 0.5 + Vector3.DOWN * (slack_sag + span * 0.25) + slack_bulge
	var path := PackedVector3Array()
	var count := 10
	for i in range(count + 1):
		var t := float(i) / float(count)
		var a := start.lerp(control, t)
		var b := control.lerp(finish, t)
		path.append(a.lerp(b, t))
	_append_tube(path, false, 0.0)


## 左手に掛けた束：手の下に垂れた 3 つの輪を少しずつずらして重ねる。
func _append_coils() -> void:
	var basis := coil_transform.basis
	var origin := coil_transform.origin
	for turn in range(3):
		var radius := coil_radius * (1.0 + 0.07 * float(turn))
		var tilt := deg_to_rad(-9.0 + 9.0 * float(turn))
		var offset := Vector3(0.0, 0.0, (float(turn) - 1.0) * rope_radius * 1.6)
		var path := PackedVector3Array()
		var count := 22
		for i in range(count):
			var angle := TAU * float(i) / float(count)
			# 手で握った所（上）から下へ垂れた円
			var local := Vector3(sin(angle) * radius * 0.92, -radius + cos(angle) * radius, 0.0)
			local = local.rotated(Vector3.UP, tilt) + offset
			path.append(origin + basis * local)
		_append_tube(path, true, float(turn) * 0.37)
