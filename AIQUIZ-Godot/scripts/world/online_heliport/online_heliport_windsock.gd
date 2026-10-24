class_name OnlineHeliportWindsock
extends RefCounted

## 海上ヘリポートの吹き流し（GLB の OHP_Windsock）を風でなびかせる物理。
## 袋の芯を、Blender の輪の位置（STATIONS 個）に置いた点のくさりとみなし、重さ・風の抗力・張り（ふくらむほど曲がりにくい）・
## 尾のはためきを Verlet で解く（1/120 秒きざみ）。口の輪は柱の先の回り台に付いていて、袋に引かれて風下へ回る。
## 袋の形は輪ごとのボーン（Skeleton3D）で曲げる。ボーン 0 は口の輪・金具といっしょに固い。
## 風はそよ風（向きと強さがゆっくり揺れ、ときどき突風）と、ヘリのローターの吹き下ろし：
##   ディスクの真下の柱 ＋ デッキに当たって外へ広がる風（ハブが低いほど・近いほど強い）。どちらも乱れる。
## 呼ぶ側（OnlineHeliportStage）は毎フレーム rotor_* を入れてから advance を呼ぶ。

# ohp_parts.windsock() と同じ形（Godot の向き：袋は +X、垂れは -Y）
const MOUTH_X := 0.08
const LENGTH := 2.4
const STATIONS := 11
const RADIUS_MOUTH := 0.34
const RADIUS_TAIL := 0.14
## 柱の太さ（＋すき間）。垂れた袋が柱に食い込まない
const POLE_RADIUS := 0.1

const STEP := 1.0 / 120.0
const MAX_STEPS := 10
const GRAVITY := 9.8
## 風の抗力（加速度 = DRAG × |相対風|²）。8 m/秒でほぼ水平、2.8 m/秒で 45° ほど垂れる
const DRAG := 1.3
const MAX_RELATIVE_WIND := 25.0
## 空気と布のねばり（1 秒あたり）
const DAMPING := 0.6
## ふくらみ：口へ入る風がこの速さ（m/秒）で張りはじめ、FULL で張り切る
const INFLATE_START := 1.2
const INFLATE_FULL := 7.0
const INFLATE_RATE := 3.5
const DEFLATE_RATE := 1.2
## しぼんだ尾の細り（尾で半径がこの割合だけ細る）
const DEFLATE_SHRINK := 0.38
## 曲がりにくさ（1 きざみで、前の節のまっすぐ先へ寄せる割合）
const BEND_LIMP := 0.01
const BEND_FULL := 0.12
## しぼんだときの口のすぐ後ろの垂れ
const MOUTH_DROOP_DEG := 30.0
## 尾のはためき（横向きの力。相対風² と尾への近さ² に比例）
const FLUTTER := 0.6
## 回り台：袋に引かれて回る強さと、軸受けのねばり
const SWIVEL_PULL := 9.0
const SWIVEL_DAMP := 3.5

## そよ風（m/秒）
const BREEZE := 2.8
const BREEZE_SWING := 1.0
const GUST := 2.4
const BREEZE_TURN_DEG := 14.0
## ローターの吹き下ろしの速さ（満ちた推力で m/秒）
const ROTOR_INDUCED := 11.0

## ヘリのローター（ワールド）。power は 0〜1（回転の 2 乗 × ピッチ）
var rotor_hub := Vector3.ZERO
var rotor_up := Vector3.UP
var rotor_radius := 5.3
var rotor_power := 0.0
var deck_y := 0.0
## いまの口の風（ワールド、m/秒。確かめ用）
var mouth_wind := Vector3.ZERO
var inflation := 0.0

var _pivot: Node3D = null
var _mesh: MeshInstance3D = null
var _skeleton: Skeleton3D = null
var _mesh_offset := Transform3D.IDENTITY
var _scale := Vector3.ONE
var _yaw := 0.0
var _yaw_velocity := 0.0
var _breeze_yaw := 0.0
var _rest := PackedVector3Array()
var _rest_tangent := PackedVector3Array()
var _radius := PackedFloat32Array()
var _length := PackedFloat32Array()
var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _noise := FastNoiseLite.new()
var _time := 0.0
var _phase := 0.0
var _accumulator := 0.0
var _breeze := Vector3.ZERO


## 組み立てる。sock は支点（柱の先）を原点にした OHP_Windsock。木に入っていること。
func setup(sock: Node3D) -> bool:
	_pivot = sock
	_mesh = sock as MeshInstance3D
	if _mesh == null:
		for node: Node in sock.find_children("*", "MeshInstance3D", true, false):
			_mesh = node as MeshInstance3D
			break
	if _mesh == null or _mesh.mesh == null:
		return false
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_octaves = 2
	_noise.seed = 4127
	_scale = sock.global_basis.get_scale()
	var axis := sock.global_basis.x
	_yaw = atan2(-axis.z, axis.x)
	_breeze_yaw = _yaw
	_mesh_offset = sock.global_transform.affine_inverse() * _mesh.global_transform
	_build_stations()
	if not _build_skin():
		return false
	var ring := _ring_transform()
	_pos.resize(STATIONS)
	_prev.resize(STATIONS)
	for i: int in range(STATIONS):
		_pos[i] = ring * _rest[i]
		_prev[i] = _pos[i]
	# 落ち着いた形から始める
	_simulate(3.0)
	_apply_pose()
	return true


## 毎フレーム。heliport が見えているときだけ呼ぶ。
func advance(delta: float) -> void:
	if _skeleton == null:
		return
	_simulate(minf(delta, STEP * MAX_STEPS))
	_apply_pose()


## 尾の先（ワールド。確かめ用）
func tail_position() -> Vector3:
	return _pos[STATIONS - 1] if _pos.size() == STATIONS else Vector3.ZERO


## 口の輪の向き（ワールド、水平）
func mouth_axis() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func pivot_position() -> Vector3:
	return _pivot.global_position if _pivot != null else Vector3.ZERO


# ---------- 解く ----------

func _simulate(seconds: float) -> void:
	_accumulator += seconds
	while _accumulator >= STEP:
		_accumulator -= STEP
		_step(STEP)


func _step(h: float) -> void:
	_time += h
	_breeze = _breeze_at(_time)
	var ring := _ring_transform()
	var axis := (ring.basis.x * Vector3(1, 0, 1)).normalized()
	# 口へ入る風でふくらむ（入るのは速く、抜けるのはゆっくり）
	mouth_wind = _wind_at(ring * _rest[0], 0)
	var into := maxf(mouth_wind.dot(axis), 0.0) + 0.25 * mouth_wind.length()
	var target := smoothstep(INFLATE_START, INFLATE_FULL, into)
	inflation = move_toward(inflation, target, (INFLATE_RATE if target > inflation else DEFLATE_RATE) * h)
	_phase += h * TAU * (0.55 + 0.3 * mouth_wind.length())
	# 口の輪とそのすぐ後ろは輪に縫い付けられている
	_pos[0] = ring * _rest[0]
	_prev[0] = _pos[0]
	var droop := deg_to_rad(MOUTH_DROOP_DEG) * (1.0 - inflation)
	var first := axis * cos(droop) + Vector3.DOWN * sin(droop)
	_prev[1] = _pos[1]
	_pos[1] = _pos[0] + first * _length[0]
	var keep := 1.0 - DAMPING * h
	for i: int in range(2, STATIONS):
		var s := float(i) / float(STATIONS - 1)
		var velocity := (_pos[i] - _prev[i]) / h
		var relative := _wind_at(_pos[i], i) - velocity
		var speed := relative.length()
		if speed > MAX_RELATIVE_WIND:
			relative *= MAX_RELATIVE_WIND / speed
			speed = MAX_RELATIVE_WIND
		var acceleration := Vector3.DOWN * GRAVITY + relative * (DRAG * speed)
		if speed > 0.3:
			var flow := relative / speed
			var side := flow.cross(Vector3.UP)
			if side.length_squared() < 0.01:
				side = axis.cross(Vector3.UP)
			side = side.normalized()
			var lift := side.cross(flow).normalized()
			# 尾へ向かって伝わる波（張っているほど速く強い）＋ちぎれた乱れ
			var force := FLUTTER * DRAG * speed * speed * s * s * (0.35 + 0.65 * inflation)
			var wave := _phase - float(i) * 0.8
			acceleration += side * force * (sin(wave) + 0.6 * _noise.get_noise_2d(_time * 6.0, float(i) * 3.1))
			acceleration += lift * force * 0.5 * (sin(wave * 1.31 + 1.7) + 0.6 * _noise.get_noise_2d(_time * 5.0 + 40.0, float(i) * 2.3))
		var next := _pos[i] + (_pos[i] - _prev[i]) * keep + acceleration * h * h
		_prev[i] = _pos[i]
		_pos[i] = next
	var bend := lerpf(BEND_LIMP, BEND_FULL, inflation)
	for _iteration: int in range(4):
		for i: int in range(1, STATIONS - 1):
			var d := _pos[i + 1] - _pos[i]
			var l := d.length()
			if l < 0.000001:
				continue
			var fix := d * ((l - _length[i]) / l)
			if i == 1:
				_pos[i + 1] -= fix
			else:
				_pos[i] += fix * 0.5
				_pos[i + 1] -= fix * 0.5
		for i: int in range(2, STATIONS):
			var along := (_pos[i - 1] - _pos[i - 2]).normalized()
			_pos[i] = _pos[i].lerp(_pos[i - 1] + along * _length[i - 1], bend)
		_push_off_pole(ring.origin)
	_turn_swivel(h)


## 柱（支点から真下）に袋が食い込まない
func _push_off_pole(mouth: Vector3) -> void:
	var pivot := _pivot.global_position
	for i: int in range(2, STATIONS):
		var p := _pos[i]
		if p.y > pivot.y + 0.3:
			continue
		var away := Vector2(p.x - pivot.x, p.z - pivot.z)
		var reach := _radius[i] * _shrink(i) + POLE_RADIUS
		var l := away.length()
		if l >= reach:
			continue
		if l < 0.0001:
			away = Vector2(mouth.x - pivot.x, mouth.z - pivot.z)
			l = maxf(away.length(), 0.0001)
		away *= reach / l
		_pos[i] = Vector3(pivot.x + away.x, p.y, pivot.z + away.y)


## 回り台：袋の重心の向き（水平）へ引かれて回る
func _turn_swivel(h: float) -> void:
	var pivot := _pivot.global_position
	var pull := Vector3.ZERO
	for i: int in range(2, STATIONS):
		pull += _pos[i] - pivot
	pull.y = 0.0
	var reach := pull.length() / float(STATIONS - 2)
	if reach > 0.02:
		var target := atan2(-pull.z, pull.x)
		var error := wrapf(target - _yaw, -PI, PI)
		_yaw_velocity += SWIVEL_PULL * clampf(reach / LENGTH * 2.0, 0.0, 1.0) * error * h
	_yaw_velocity -= _yaw_velocity * SWIVEL_DAMP * h
	_yaw += _yaw_velocity * h


func _ring_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _yaw).scaled_local(_scale), _pivot.global_position) * _mesh_offset


func _shrink(i: int) -> float:
	var s := float(i) / float(STATIONS - 1)
	return 1.0 - (1.0 - inflation) * DEFLATE_SHRINK * pow(s, 1.3)


# ---------- 風 ----------

## そよ風：向き（建てたときの風下）と強さがゆっくり揺れ、ときどき突風が来る
func _breeze_at(t: float) -> Vector3:
	var turn := deg_to_rad(BREEZE_TURN_DEG) * (0.6 * sin(t * 0.23 + 0.4) + 0.7 * _noise.get_noise_2d(t * 0.17, 11.0))
	var gust := maxf(_noise.get_noise_2d(t * 0.21, 37.0), 0.0) * 2.0
	var speed := BREEZE + BREEZE_SWING * sin(t * 0.31 + 0.9) + GUST * gust * gust
	return Vector3(cos(_breeze_yaw + turn), 0.0, -sin(_breeze_yaw + turn)) * speed


func _wind_at(p: Vector3, i: int) -> Vector3:
	var lane := float(i) * 0.37
	var wind := _breeze
	# そよ風の小さな乱れ（袋の場所ごとに少しちがう）
	wind += Vector3(_noise.get_noise_2d(_time * 1.3, 70.0 + lane), 0.4 * _noise.get_noise_2d(_time * 1.1, 90.0 + lane),
		_noise.get_noise_2d(_time * 1.3, 110.0 + lane)) * (0.18 * _breeze.length())
	if rotor_power > 0.001:
		wind += _rotor_wind(p, lane)
	return wind


## ローターの吹き下ろし：ディスクの真下の柱と、デッキに当たって外へ広がる風
func _rotor_wind(p: Vector3, lane: float) -> Vector3:
	var v := ROTOR_INDUCED * rotor_power
	var r_disc := rotor_radius
	var up := rotor_up.normalized()
	var rel := p - rotor_hub
	var below := -rel.dot(up)
	var radial := (rel + up * below).length()
	var wind := Vector3.ZERO
	# 柱（ディスクの下で少し細って速くなる）
	var core := (1.0 - smoothstep(0.75 * r_disc, 1.1 * r_disc, radial)) * smoothstep(-1.0, 0.5, below)
	wind -= up * (v * 1.4 * core)
	# デッキに当たって外へ広がる風
	var height := rotor_hub.y - deck_y
	var ground := 1.0 - smoothstep(1.2 * r_disc, 3.5 * r_disc, height)
	if ground > 0.0:
		var spread := rotor_hub - up * (height / maxf(up.y, 0.3))
		var out := Vector3(p.x - spread.x, 0.0, p.z - spread.z)
		var reach := out.length()
		if reach > 0.01:
			out /= reach
			var falloff := clampf(1.2 * r_disc / maxf(reach, 0.8 * r_disc), 0.0, 1.5)
			var thick := 1.5 + 0.45 * reach
			var above := maxf(p.y - deck_y, 0.0)
			var profile := exp(-0.5 * (above / thick) * (above / thick))
			# 外の縁で巻き上がる
			var dir := (out + Vector3.UP * 0.25).normalized()
			wind += dir * (v * 1.5 * ground * falloff * profile)
	# 吹き下ろしは強く乱れる（息つぎのような強弱と、横・上下のゆらぎ）
	var strength := wind.length()
	if strength > 0.01:
		var flow := wind / strength
		var side := flow.cross(Vector3.UP)
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var lift := side.cross(flow)
		wind *= 1.0 + 0.5 * _noise.get_noise_2d(_time * 3.0, 130.0 + lane)
		wind += side * (strength * 0.6 * _noise.get_noise_2d(_time * 4.5, 150.0 + lane))
		wind += lift * (strength * 0.35 * _noise.get_noise_2d(_time * 4.0, 170.0 + lane))
	return wind


# ---------- 形 ----------

func _build_stations() -> void:
	_rest.resize(STATIONS)
	_rest_tangent.resize(STATIONS)
	_radius.resize(STATIONS)
	_length.resize(STATIONS - 1)
	for k: int in range(STATIONS):
		var t := float(k) / float(STATIONS - 1)
		_rest[k] = Vector3(MOUTH_X + t * LENGTH, -0.06 - 0.16 * pow(t, 1.6), 0.0)
		_rest_tangent[k] = Vector3(LENGTH, -0.16 * 1.6 * pow(t, 0.6), 0.0).normalized()
		_radius[k] = lerpf(RADIUS_MOUTH, RADIUS_TAIL, t)
	for k: int in range(STATIONS - 1):
		_length[k] = _rest[k].distance_to(_rest[k + 1])


## 輪ごとのボーンを作り、頂点をいちばん近い輪へ割り当てる（輪より前＝口の輪と金具はボーン 0）
func _build_skin() -> bool:
	var source := _mesh.mesh
	var skinned := ArrayMesh.new()
	var overrides: Array[Material] = []
	for surface: int in range(source.get_surface_count()):
		overrides.append(_mesh.get_surface_override_material(surface))
		var arrays: Array = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(vertices.size() * 4)
		weights.resize(vertices.size() * 4)
		for v: int in range(vertices.size()):
			var station := clampi(roundi((vertices[v].x - MOUTH_X) / LENGTH * float(STATIONS - 1)), 0, STATIONS - 1)
			bones[v * 4] = station
			weights[v * 4] = 1.0
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		skinned.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		skinned.surface_set_material(surface, source.surface_get_material(surface))
	_skeleton = Skeleton3D.new()
	_skeleton.name = "WindsockBones"
	var skin := Skin.new()
	for k: int in range(STATIONS):
		_skeleton.add_bone("S%02d" % k)
		var rest := Transform3D(Basis.IDENTITY, _rest[k])
		_skeleton.set_bone_rest(k, rest)
		skin.add_bind(k, rest.affine_inverse())
	_mesh.add_child(_skeleton)
	_mesh.mesh = skinned
	for surface: int in range(overrides.size()):
		if overrides[surface] != null:
			_mesh.set_surface_override_material(surface, overrides[surface])
	_mesh.skin = skin
	_mesh.skeleton = _mesh.get_path_to(_skeleton)
	# 垂れても、張っても、柱の回りに収まる
	_mesh.custom_aabb = AABB(Vector3(-3.2, -3.2, -3.2), Vector3(6.4, 6.4, 6.4))
	return true


func _apply_pose() -> void:
	_pivot.global_basis = Basis(Vector3.UP, _yaw).scaled_local(_scale)
	var to_local := _skeleton.global_transform.affine_inverse()
	var local := PackedVector3Array()
	local.resize(STATIONS)
	for i: int in range(STATIONS):
		local[i] = to_local * _pos[i]
	for i: int in range(STATIONS):
		if i == 0:
			_skeleton.set_bone_pose_position(0, _rest[0])
			continue
		var tangent := (local[i] - local[i - 1]) if i == STATIONS - 1 else (local[i + 1] - local[i - 1])
		if tangent.length_squared() < 0.000001:
			tangent = _rest_tangent[i]
		tangent = tangent.normalized()
		var turn := Quaternion.IDENTITY
		if _rest_tangent[i].dot(tangent) > -0.999:
			turn = Quaternion(_rest_tangent[i], tangent)
		var s := float(i) / float(STATIONS - 1)
		# 張った袋は風を呑んでかすかに脈打つ
		var breathe := 1.0 + inflation * 0.035 * s * sin(_phase * 0.5 + float(i) * 0.9)
		var size := _shrink(i) * breathe
		_skeleton.set_bone_pose_position(i, local[i])
		_skeleton.set_bone_pose_rotation(i, turn)
		_skeleton.set_bone_pose_scale(i, Vector3(size, size, size))
