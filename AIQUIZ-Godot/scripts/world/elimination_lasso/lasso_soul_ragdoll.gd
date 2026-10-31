class_name LassoSoulRagdoll
extends RefCounted

## ハテナがゴールへ投げつけた魂のラグドール（両者脱落の投げ縄の演出。EliminationLassoDirector）。
## 魂のブロックマン（PlayerController.create_ghost_rider_visual の部品）の関節を 15 の粒にして、骨の長さと
## 胴の形を保つ Verlet の物理で飛ばす：重力・床への衝突（はね返りと摩擦）・膝と肘が逆に曲がらない制限。
## 毎フレーム、粒から魂の体の向きと各部品の回転を組み直す（apply_pose）。止まったら、その場で自然に起き上がる
## （begin_get_up / apply_get_up）：あお向けなら上体を起こし、足を引き寄せてしゃがみ、立つ。うつ伏せなら腕で押し上げ、
## 四つんばいになって、立つ。立ちながら、これから歩いていく向きへ振り向く。
## 座標はすべて演出の根（GameWorld のローカル）の空間。

const PELVIS := 0
const CHEST := 1
const HEAD := 2
const L_SHOULDER := 3
const L_ELBOW := 4
const L_HAND := 5
const R_SHOULDER := 6
const R_ELBOW := 7
const R_HAND := 8
const L_HIP := 9
const L_KNEE := 10
const L_FOOT := 11
const R_HIP := 12
const R_KNEE := 13
const R_FOOT := 14
const COUNT := 15
const SUBSTEPS := 3
const ITERATIONS := 8
## 魂の根から骨盤までの高さ（PlayerController の BASE_Y + 0.9）
const PELVIS_FROM_ROOT := -0.3
const GRAVITY := 9.8
const RESTITUTION := 0.26
const FRICTION := 0.75
const AIR_DRAG := 0.08
## 床に着いてからの転がりの減り（1 秒あたり）。遠くまで転がっていかない
const GROUND_DRAG := 2.6

var floor_y := -INF
var landed := false
var land_time := -1.0
var age := 0.0

var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _radius := PackedFloat32Array()
var _links: Array = []
var _rest_pose: Dictionary = {}
var _still_time := 0.0
var _supine := true
var _heading := 0.0
var _lie_pelvis := Vector3.ZERO
## 前の小刻みの長さ（秒）。粒の速さは「今の位置 − 前の位置」なので、小刻みの長さが変わったら速さを保つよう直す
var _last_h := 0.0


## 今の魂の姿勢（部品の位置）から始める。to_space は世界 → 演出の根の空間。
func start(parts: Dictionary, to_space: Transform3D) -> void:
	_pos.resize(COUNT)
	_prev.resize(COUNT)
	_radius.resize(COUNT)
	var spine := parts.get("spine") as Node3D
	var head := parts.get("head_pivot") as Node3D
	_pos[PELVIS] = to_space * (parts.get("pelvis") as Node3D).global_position
	_pos[CHEST] = to_space * (spine.global_transform * Vector3(0.0, 0.35, 0.0))
	_pos[HEAD] = to_space * (head.global_transform * Vector3(0.0, 0.22, 0.0))
	_pos[L_SHOULDER] = to_space * (parts.get("l_shoulder") as Node3D).global_position
	_pos[L_ELBOW] = to_space * (parts.get("l_elbow") as Node3D).global_position
	_pos[L_HAND] = to_space * (parts.get("l_wrist") as Node3D).global_position
	_pos[R_SHOULDER] = to_space * (parts.get("r_shoulder") as Node3D).global_position
	_pos[R_ELBOW] = to_space * (parts.get("r_elbow") as Node3D).global_position
	_pos[R_HAND] = to_space * (parts.get("r_wrist") as Node3D).global_position
	_pos[L_HIP] = to_space * (parts.get("l_hip") as Node3D).global_position
	_pos[L_KNEE] = to_space * (parts.get("l_knee") as Node3D).global_position
	_pos[L_FOOT] = to_space * (parts.get("l_ankle") as Node3D).global_position
	_pos[R_HIP] = to_space * (parts.get("r_hip") as Node3D).global_position
	_pos[R_KNEE] = to_space * (parts.get("r_knee") as Node3D).global_position
	_pos[R_FOOT] = to_space * (parts.get("r_ankle") as Node3D).global_position
	for i in range(COUNT):
		_prev[i] = _pos[i]
		_radius[i] = 0.1
	_radius[PELVIS] = 0.16
	_radius[CHEST] = 0.18
	_radius[HEAD] = 0.13
	_links.clear()
	# 骨（長さを保つ）と、胴の箱を崩さない筋交い
	for pair: Array in [[PELVIS, CHEST], [CHEST, HEAD], [CHEST, L_SHOULDER], [CHEST, R_SHOULDER], [L_SHOULDER, R_SHOULDER],
			[L_SHOULDER, L_ELBOW], [L_ELBOW, L_HAND], [R_SHOULDER, R_ELBOW], [R_ELBOW, R_HAND],
			[PELVIS, L_HIP], [PELVIS, R_HIP], [L_HIP, R_HIP], [L_HIP, L_KNEE], [L_KNEE, L_FOOT], [R_HIP, R_KNEE], [R_KNEE, R_FOOT],
			[L_SHOULDER, L_HIP], [R_SHOULDER, R_HIP], [L_SHOULDER, R_HIP], [R_SHOULDER, L_HIP],
			[HEAD, L_SHOULDER], [HEAD, R_SHOULDER], [CHEST, L_HIP], [CHEST, R_HIP]]:
		_links.append([pair[0], pair[1], _pos[pair[0]].distance_to(_pos[pair[1]])])
	landed = false
	land_time = -1.0
	age = 0.0
	_still_time = 0.0


## 投げる：重心が time 秒後に land へ落ちる放物線の速さで、前転するように回しながら放つ。
## frame_dt は次に step() へ渡すフレームの長さの見込み（速さは小刻みの長さで入れる）。
func launch(land: Vector3, time: float, spin_axis: Vector3, spin: float, frame_dt: float) -> void:
	var center := center_of_mass()
	var gravity := Vector3(0.0, -GRAVITY, 0.0)
	var velocity := (land - center - 0.5 * gravity * time * time) / time
	var omega := spin_axis.normalized() * spin
	var h := frame_dt / float(SUBSTEPS)
	_last_h = h
	for i in range(COUNT):
		var v := velocity + omega.cross(_pos[i] - center)
		_prev[i] = _pos[i] - v * h


func center_of_mass() -> Vector3:
	return (_pos[PELVIS] + _pos[CHEST]) * 0.5


func point(index: int) -> Vector3:
	return _pos[index]


## いちばん速い粒の速さ（m/秒）。
func speed() -> float:
	var top := 0.0
	for i in range(COUNT):
		top = maxf(top, _pos[i].distance_to(_prev[i]) / maxf(_last_h, 1e-5))
	return top


## 止まった（ほとんど動かない状態が少し続いた）か。
func is_resting() -> bool:
	return landed and (_still_time > 0.18 or age - land_time > 0.75)


func step(delta: float) -> void:
	var dt := clampf(delta, 0.0, 1.0 / 20.0)
	if dt <= 0.0:
		return
	age += dt
	var h := dt / float(SUBSTEPS)
	var g := Vector3(0.0, -GRAVITY * h * h, 0.0)
	var damp := maxf(0.0, 1.0 - (GROUND_DRAG if landed else AIR_DRAG) * h)
	var rescale := h / _last_h if _last_h > 0.0 else 1.0
	_last_h = h
	for sub in range(SUBSTEPS):
		for i in range(COUNT):
			var p := _pos[i]
			var v := (p - _prev[i]) * damp * (rescale if sub == 0 else 1.0)
			_prev[i] = p
			_pos[i] = p + v + g
		for _iteration in range(ITERATIONS):
			for link: Array in _links:
				var a: int = link[0]
				var b: int = link[1]
				var rest: float = link[2]
				var d := _pos[b] - _pos[a]
				var length := d.length()
				if length < 1e-6:
					continue
				var correction := d * (0.5 * (length - rest) / length)
				_pos[a] += correction
				_pos[b] -= correction
			_bend_limits()
			_floor_contacts()
	var moving := speed()
	if landed:
		_still_time = _still_time + dt if moving < 0.45 else 0.0


## 膝は前へ、肘はうしろへだけ曲がる（体の前の向きで判定し、逆へ曲がったら押し戻す）。
func _bend_limits() -> void:
	var up := (_pos[CHEST] - _pos[PELVIS]).normalized()
	var right := _pos[R_SHOULDER] - _pos[L_SHOULDER]
	right = (right - up * right.dot(up)).normalized()
	var forward := right.cross(up)
	for joint: Array in [[L_HIP, L_KNEE, L_FOOT, 1.0], [R_HIP, R_KNEE, R_FOOT, 1.0], [L_SHOULDER, L_ELBOW, L_HAND, -1.0], [R_SHOULDER, R_ELBOW, R_HAND, -1.0]]:
		var root: int = joint[0]
		var middle: int = joint[1]
		var tip: int = joint[2]
		var sign: float = joint[3]
		var mid := (_pos[root] + _pos[tip]) * 0.5
		var out := (_pos[middle] - mid).dot(forward) * sign
		if out < 0.02:
			_pos[middle] += forward * sign * (0.02 - out) * 0.6


func _floor_contacts() -> void:
	if not is_finite(floor_y):
		return
	for i in range(COUNT):
		var bottom := floor_y + _radius[i]
		if _pos[i].y < bottom:
			var vy := _pos[i].y - _prev[i].y
			_pos[i].y = bottom
			# はね返り（下向きの速さの一部を上向きへ）と、床をこする摩擦
			_prev[i].y = bottom + vy * RESTITUTION
			_prev[i].x = lerpf(_prev[i].x, _pos[i].x, FRICTION * 0.35)
			_prev[i].z = lerpf(_prev[i].z, _pos[i].z, FRICTION * 0.35)
			if not landed:
				landed = true
				land_time = age


## 粒から魂の体の置き場所（根の変換）を求める。
func root_transform() -> Transform3D:
	var up := (_pos[CHEST] - _pos[PELVIS]).normalized()
	var right := _pos[R_SHOULDER] - _pos[L_SHOULDER]
	right = right - up * right.dot(up)
	if right.length_squared() < 1e-8:
		right = Vector3.RIGHT
	right = right.normalized()
	var forward := right.cross(up).normalized()
	var basis := Basis(right, up, forward)
	return Transform3D(basis, _pos[PELVIS] - basis * Vector3(0.0, PELVIS_FROM_ROOT, 0.0))


## 魂の体と部品を、今の粒の形に合わせる（肩・肘・股・膝・首を、子の粒へ向ける）。
func apply_pose(soul: Node3D, parts: Dictionary) -> void:
	var root := root_transform()
	soul.transform = root
	var basis := root.basis
	for key: String in ["pelvis", "spine", "neck", "head_pivot", "l_wrist", "r_wrist", "l_ankle", "r_ankle"]:
		if parts.get(key) is Node3D:
			(parts[key] as Node3D).quaternion = Quaternion.IDENTITY
	var neck := parts.get("neck") as Node3D
	if neck != null:
		var to_head := basis.inverse() * (_pos[HEAD] - _pos[CHEST])
		neck.quaternion = _arc(Vector3.UP, to_head)
	_aim_limb(parts, "l_shoulder", "l_elbow", basis, L_SHOULDER, L_ELBOW, L_HAND)
	_aim_limb(parts, "r_shoulder", "r_elbow", basis, R_SHOULDER, R_ELBOW, R_HAND)
	_aim_limb(parts, "l_hip", "l_knee", basis, L_HIP, L_KNEE, L_FOOT)
	_aim_limb(parts, "r_hip", "r_knee", basis, R_HIP, R_KNEE, R_FOOT)


func _aim_limb(parts: Dictionary, upper_key: String, lower_key: String, basis: Basis, a: int, b: int, c: int) -> void:
	var upper := parts.get(upper_key) as Node3D
	var lower := parts.get(lower_key) as Node3D
	if upper == null or lower == null:
		return
	var upper_rot := _arc(Vector3.DOWN, basis.inverse() * (_pos[b] - _pos[a]))
	upper.quaternion = upper_rot
	var upper_basis := basis * Basis(upper_rot)
	lower.quaternion = _arc(Vector3.DOWN, upper_basis.inverse() * (_pos[c] - _pos[b]))


## 起き上がりの始まり：止まった形（体の置き場所と部品の回転）を覚え、あお向けかうつ伏せか、起き上がる向きを決める。
func begin_get_up(soul: Node3D, parts: Dictionary) -> void:
	apply_pose(soul, parts)
	_rest_pose = {"root": soul.transform}
	for key: Variant in parts:
		if parts[key] is Node3D:
			_rest_pose[key] = (parts[key] as Node3D).quaternion
	var basis := soul.transform.basis.orthonormalized()
	# 胸の前が上を向いていればあお向け。あお向けは足の方へ、うつ伏せは頭の方へ起き上がる
	_supine = basis.z.y >= 0.0
	var along := -basis.y if _supine else basis.y
	along.y = 0.0
	if along.length_squared() < 1e-4:
		along = basis.z if _supine else -basis.z
		along.y = 0.0
	_heading = atan2(along.x, along.z) if along.length_squared() > 1e-6 else 0.0
	_lie_pelvis = _pos[PELVIS]


## 起き上がりのキー（時刻 0〜1、体の前のめり（度。-90 = あお向け、90 = うつ伏せ）、骨盤の床からの高さ、
## 骨盤が起き上がる向きへ進む距離、部品の回転（度））。
const SUPINE_KEYS := [
	[0.0, -90.0, 0.13, 0.0, {"spine": Vector3(0, 0, 0), "neck": Vector3(-10, 0, 0), "l_shoulder": Vector3(0, 0, -18), "r_shoulder": Vector3(0, 0, 18),
		"l_elbow": Vector3(-10, 0, 0), "r_elbow": Vector3(-10, 0, 0), "l_hip": Vector3(-6, 0, -4), "r_hip": Vector3(-6, 0, 4),
		"l_knee": Vector3(12, 0, 0), "r_knee": Vector3(12, 0, 0), "l_ankle": Vector3(20, 0, 0), "r_ankle": Vector3(20, 0, 0)}],
	# 上体を起こす（両手をうしろの床につく）。頭を振る
	[0.28, -18.0, 0.1, 0.0, {"spine": Vector3(14, 0, 0), "neck": Vector3(12, 0, 0), "head_pivot": Vector3(6, 0, 0),
		"l_shoulder": Vector3(40, 0, -22), "r_shoulder": Vector3(40, 0, 22), "l_elbow": Vector3(-6, 0, 0), "r_elbow": Vector3(-6, 0, 0),
		"l_hip": Vector3(-72, 0, -6), "r_hip": Vector3(-72, 0, 6), "l_knee": Vector3(24, 0, 0), "r_knee": Vector3(34, 0, 0),
		"l_ankle": Vector3(10, 0, 0), "r_ankle": Vector3(10, 0, 0)}],
	# 足を引き寄せてしゃがむ（前へ体重を移し、両手を前へ）
	[0.52, 30.0, 0.46, 0.38, {"spine": Vector3(18, 0, 0), "neck": Vector3(-8, 0, 0), "head_pivot": Vector3(-6, 0, 0),
		"l_shoulder": Vector3(-52, 0, -14), "r_shoulder": Vector3(-52, 0, 14), "l_elbow": Vector3(-24, 0, 0), "r_elbow": Vector3(-24, 0, 0),
		"l_hip": Vector3(-112, 0, -8), "r_hip": Vector3(-112, 0, 8), "l_knee": Vector3(128, 0, 0), "r_knee": Vector3(128, 0, 0),
		"l_ankle": Vector3(-34, 0, 0), "r_ankle": Vector3(-34, 0, 0)}],
	# 伸び上がる
	[0.78, 16.0, 0.76, 0.44, {"spine": Vector3(10, 0, 0), "neck": Vector3(-4, 0, 0), "l_shoulder": Vector3(-14, 0, -16), "r_shoulder": Vector3(-14, 0, 16),
		"l_elbow": Vector3(-14, 0, 0), "r_elbow": Vector3(-14, 0, 0), "l_hip": Vector3(-46, 0, -3), "r_hip": Vector3(-46, 0, 3),
		"l_knee": Vector3(64, 0, 0), "r_knee": Vector3(64, 0, 0), "l_ankle": Vector3(-16, 0, 0), "r_ankle": Vector3(-16, 0, 0)}],
	[1.0, 0.0, 0.9, 0.44, {}],
]
const PRONE_KEYS := [
	[0.0, 90.0, 0.14, 0.0, {"spine": Vector3(0, 0, 0), "neck": Vector3(-20, 0, 0), "l_shoulder": Vector3(-20, 0, -20), "r_shoulder": Vector3(-20, 0, 20),
		"l_elbow": Vector3(-30, 0, 0), "r_elbow": Vector3(-30, 0, 0), "l_hip": Vector3(4, 0, -4), "r_hip": Vector3(4, 0, 4),
		"l_knee": Vector3(14, 0, 0), "r_knee": Vector3(14, 0, 0), "l_ankle": Vector3(30, 0, 0), "r_ankle": Vector3(30, 0, 0)}],
	# 腕で押し上げる（手は肩の下の床）
	[0.3, 58.0, 0.22, 0.0, {"spine": Vector3(-14, 0, 0), "neck": Vector3(-26, 0, 0), "head_pivot": Vector3(-8, 0, 0),
		"l_shoulder": Vector3(-58, 0, -10), "r_shoulder": Vector3(-58, 0, 10), "l_elbow": Vector3(-6, 0, 0), "r_elbow": Vector3(-6, 0, 0),
		"l_hip": Vector3(6, 0, -4), "r_hip": Vector3(6, 0, 4), "l_knee": Vector3(30, 0, 0), "r_knee": Vector3(22, 0, 0),
		"l_ankle": Vector3(30, 0, 0), "r_ankle": Vector3(30, 0, 0)}],
	# 膝を引き寄せて四つんばい
	[0.55, 52.0, 0.52, -0.18, {"spine": Vector3(4, 0, 0), "neck": Vector3(-30, 0, 0), "l_shoulder": Vector3(-54, 0, -8), "r_shoulder": Vector3(-54, 0, 8),
		"l_elbow": Vector3(-4, 0, 0), "r_elbow": Vector3(-4, 0, 0), "l_hip": Vector3(-56, 0, -5), "r_hip": Vector3(-56, 0, 5),
		"l_knee": Vector3(92, 0, 0), "r_knee": Vector3(92, 0, 0), "l_ankle": Vector3(40, 0, 0), "r_ankle": Vector3(40, 0, 0)}],
	# 片ひざを立ててしゃがみ、伸び上がる
	[0.78, 22.0, 0.72, -0.1, {"spine": Vector3(12, 0, 0), "neck": Vector3(-8, 0, 0), "l_shoulder": Vector3(-20, 0, -16), "r_shoulder": Vector3(-26, 0, 16),
		"l_elbow": Vector3(-20, 0, 0), "r_elbow": Vector3(-16, 0, 0), "l_hip": Vector3(-62, 0, -4), "r_hip": Vector3(-38, 0, 4),
		"l_knee": Vector3(78, 0, 0), "r_knee": Vector3(60, 0, 0), "l_ankle": Vector3(-14, 0, 0), "r_ankle": Vector3(-10, 0, 0)}],
	[1.0, 0.0, 0.9, -0.1, {}],
]


## 起き上がる（weight 0 = 止まった形、1 = 立った）。standing_rotations は結果発表の立ち姿の部品の回転（呼ぶ側が作る）。
## face_yaw は立ち上がったときに向く向き（これから歩いていく向き）。立ち上がる後半で振り向く。
func apply_get_up(soul: Node3D, parts: Dictionary, standing_rotations: Dictionary, weight: float, face_yaw: float) -> void:
	var t := clampf(weight, 0.0, 1.0)
	var keys: Array = SUPINE_KEYS if _supine else PRONE_KEYS
	var k := 0
	while k < keys.size() - 2 and t > float(keys[k + 1][0]):
		k += 1
	var a: Array = keys[k]
	var b: Array = keys[k + 1]
	var s := clampf((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4), 0.0, 1.0)
	s = s * s * (3.0 - 2.0 * s)
	var pitch := deg_to_rad(lerpf(float(a[1]), float(b[1]), s))
	var height := lerpf(float(a[2]), float(b[2]), s)
	var advance := lerpf(float(a[3]), float(b[3]), s)
	# 立ち上がる後半で、これから歩いていく向きへ振り向く
	var yaw := lerp_angle(_heading, face_yaw, smoothstep(0.55, 1.0, t))
	var heading_basis := Basis(Vector3.UP, yaw)
	var basis := heading_basis * Basis(Vector3.RIGHT, pitch)
	var forward := Basis(Vector3.UP, _heading) * Vector3.BACK
	var pelvis := Vector3(_lie_pelvis.x, floor_y + height, _lie_pelvis.z) + forward * advance
	var key_root := Transform3D(basis, pelvis - basis * Vector3(0.0, PELVIS_FROM_ROOT, 0.0))
	# 止まった形から、最初のキーの形へなじませる
	var settle := smoothstep(0.0, 0.2, t)
	var from: Transform3D = _rest_pose.get("root", key_root)
	var rot := Quaternion(from.basis.orthonormalized()).slerp(Quaternion(key_root.basis.orthonormalized()), settle)
	soul.transform = Transform3D(Basis(rot), from.origin.lerp(key_root.origin, settle))
	var stand_w := smoothstep(0.82, 1.0, t)
	var pose_a: Dictionary = a[4]
	var pose_b: Dictionary = b[4]
	for key: Variant in standing_rotations:
		var node: Node3D = parts.get(key) if parts.get(key) is Node3D else null
		if node == null:
			continue
		var standing: Quaternion = standing_rotations[key]
		var qa: Quaternion = Quaternion.from_euler(pose_a[key] * (PI / 180.0)) if pose_a.has(key) else standing
		var qb: Quaternion = Quaternion.from_euler(pose_b[key] * (PI / 180.0)) if pose_b.has(key) else standing
		var keyed := qa.slerp(qb, s).slerp(standing, stand_w)
		var rest: Quaternion = _rest_pose.get(key, keyed)
		node.quaternion = rest.slerp(keyed, settle)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if to.length_squared() < 1e-10:
		return Quaternion.IDENTITY
	var a := from.normalized()
	var b := to.normalized()
	var d := clampf(a.dot(b), -1.0, 1.0)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		var axis := a.cross(Vector3.RIGHT)
		if axis.length_squared() < 1e-6:
			axis = a.cross(Vector3.FORWARD)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(a, b)
