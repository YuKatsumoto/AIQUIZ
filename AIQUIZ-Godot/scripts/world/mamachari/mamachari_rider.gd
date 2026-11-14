extends RefCounted
class_name MamachariRider

## 箱人形をママチャリに乗せる姿勢を解く。
## 腰をサドルに、足をペダルに、手をグリップに合わせ、ひざ・ひじは2本の骨の逆運動学で決める。
## 座標は「入れ物」（PlayerController 本体か Player2。自転車と骨盤の親）のものを使う。
## 通常のアニメが関節を書いたあとに呼ぶ（毎フレーム、全部の関節を書き直す）。
##
## 骨格の左右：つま先が +Z 向きで、"l_*" の部品は -X 側＝乗り手の右にある（PlayerSkinRig と同じ）。
## 自転車は チェーンケースが -X（乗り手の右）、PedalR・BrakeLeverR も -X 側。

const THIGH := 0.45
const CALF := 0.45
const UPPER_ARM := 0.40
const FOREARM := 0.40

## 腰（股関節）の高さ：サドルの上面からこれだけ上。箱の脚が太いので、少しサドルにめり込ませて座らせる。
const HIP_ABOVE_SEAT := 0.04
## 足首の位置：ペダルの軸から見て、上・後ろ（母指球がペダルの軸の上に来る）。
const ANKLE_ABOVE_PEDAL := 0.135
const ANKLE_BEHIND_PEDAL := 0.10
## 足の中心の横の位置（自転車の中心から）。足の幅が 0.28 あるので、クランクとチェーンケースの外へ出す。
const FOOT_SIDE := 0.27
## 手首の位置：グリップの中心から見て上・外。手のひらがグリップの外側に当たり、指が下から巻く。
const WRIST_ABOVE_GRIP := 0.115
const WRIST_OUTSIDE_GRIP := 0.05

## 上体の前傾（度）：[骨盤, 背骨]。座る／立ちこぎ／止まって片足をつく／空中。首と頭は、前を見るように起こす。
const LEAN_SEATED := Vector2(6.0, 12.0)
const LEAN_STANDING := Vector2(16.0, 24.0)
const LEAN_FOOT_DOWN := Vector2(2.0, 8.0)
const LEAN_AIR := Vector2(12.0, 20.0)
const HEAD_UP_RATIO := 0.45

## 立ちこぎの腰の位置（自転車の原点＝BBの真下の床から。上・前）。脚が下死点で伸びきる高さにする。
const STAND_HIP_HEIGHT := 1.185
const STAND_HIP_FORWARD := -0.05
## クランクが水平のとき（両足が同じ高さ）に、腰がさらに上がる量。
const STAND_BOB := 0.03
## ふみ込む足のほうへ腰が寄る量。
const STAND_SHIFT := 0.04
## 立ちこぎで、かかとが上がる角度（度）。座っているときは、ほぼ水平。
const FOOT_PITCH_SEATED := 4.0
const FOOT_PITCH_STANDING := 20.0

## 空中：水平にそろえたペダルの上に立ち、腰を後ろへ引く。
const AIR_HIP_HEIGHT := 1.24
const AIR_HIP_FORWARD := -0.20

## 止まって左足をつく：サドルの前へ降りて、低いフレームをまたいで立つ。
const DOWN_HIP_HEIGHT := 0.97
const DOWN_HIP_FORWARD := 0.12
const DOWN_HIP_SIDE := 0.10
## 地面につく左足の位置（自転車の原点から。左・前）と、足首の高さ（足の裏が床に付く）。
const GROUND_FOOT_SIDE := 0.47
const GROUND_FOOT_FORWARD := 0.10
const GROUND_ANKLE_HEIGHT := 0.12
## 足をペダルから地面へ移すあいだに、持ち上げる高さ。
const FOOT_STEP_LIFT := 0.10
## 着地で腰が沈む量。
const LAND_DIP := 0.07

const FINGERS: Array[String] = ["index", "middle", "ring", "pinky"]


## 乗った姿勢を当てる。container は自転車と骨盤の親。pose は MamachariRide.pose()（無ければ座った姿勢）。
static func apply(parts: Dictionary, rig: MamachariRig, container: Node3D, pose: Dictionary = {}) -> void:
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null or rig == null or container == null or not pelvis.is_inside_tree():
		return
	var world := container.global_transform.basis.orthonormalized()
	var bike := rig.frame_basis()
	var body: Basis = pose.get("body_basis", bike)
	var standing := _ease(float(pose.get("standing", 0.0)))
	var foot_down := _ease(float(pose.get("foot_down", 0.0)))
	var air := _ease(float(pose.get("air", 0.0)))
	var land := float(pose.get("land", 0.0))
	var origin := rig.transform.origin
	var crank := rig.crank_angle

	# 腰の位置：座る → 立ちこぎ → 空中 → 片足をつく の順に重ねる。
	var seat_point := rig.seat_position() + bike.y * HIP_ABOVE_SEAT
	var stand_point := origin + body.y * (STAND_HIP_HEIGHT + STAND_BOB * cos(crank) * cos(crank)) 		+ body.z * STAND_HIP_FORWARD - body.x * (STAND_SHIFT * cos(crank))
	var air_point := origin + body.y * AIR_HIP_HEIGHT + body.z * AIR_HIP_FORWARD
	var down_point := origin + body.y * DOWN_HIP_HEIGHT + body.z * DOWN_HIP_FORWARD + body.x * DOWN_HIP_SIDE
	var pelvis_origin := seat_point.lerp(stand_point, standing).lerp(air_point, air).lerp(down_point, foot_down)
	pelvis_origin -= body.y * (LAND_DIP * land)
	var lean := LEAN_SEATED.lerp(LEAN_STANDING, standing).lerp(LEAN_AIR, air).lerp(LEAN_FOOT_DOWN, foot_down)
	lean += Vector2(4.0, 8.0) * land

	# 上体
	var pelvis_basis := body * Basis(Vector3.RIGHT, deg_to_rad(lean.x))
	pelvis.transform = Transform3D(pelvis_basis, pelvis_origin)
	var spine := parts.get("spine") as Node3D
	var spine_basis := pelvis_basis * Basis(Vector3.RIGHT, deg_to_rad(lean.y))
	var spine_origin := pelvis_origin
	if spine != null:
		spine_origin = pelvis_origin + pelvis_basis * spine.position
		spine.global_basis = world * spine_basis
	var head_up := deg_to_rad((lean.x + lean.y) * HEAD_UP_RATIO)
	var neck := parts.get("neck") as Node3D
	var neck_basis := spine_basis * Basis(Vector3.RIGHT, -head_up)
	if neck != null:
		neck.global_basis = world * neck_basis
	var head := parts.get("head_pivot") as Node3D
	if head != null:
		head.global_basis = world * (neck_basis * Basis(Vector3.RIGHT, -head_up))

	var foot_pitch := deg_to_rad(lerpf(FOOT_PITCH_SEATED, FOOT_PITCH_STANDING, standing) * (1.0 - air))
	for prefix: String in ["l_", "r_"]:
		# "l_" は乗り手の右（-X）。地面につくのは乗り手の左足（"r_"）。
		var right := prefix == "l_"
		var side := -1.0 if right else 1.0
		_solve_leg(parts, prefix, rig, right, side, bike, body, world, pelvis_origin, pelvis_basis, foot_pitch,
			0.0 if right else foot_down)
		_solve_arm(parts, prefix, rig, right, side, bike, world, spine_origin, spine_basis)


static func _ease(value: float) -> float:
	return smoothstep(0.0, 1.0, clampf(value, 0.0, 1.0))


static func _solve_leg(
	parts: Dictionary, prefix: String, rig: MamachariRig, right: bool, side: float,
	bike: Basis, body: Basis, world: Basis, pelvis_origin: Vector3, pelvis_basis: Basis,
	foot_pitch: float, ground: float
) -> void:
	var hip := parts.get(prefix + "hip") as Node3D
	var knee := parts.get(prefix + "knee") as Node3D
	var ankle := parts.get(prefix + "ankle") as Node3D
	if hip == null or knee == null or ankle == null:
		return
	var hip_origin := pelvis_origin + pelvis_basis * hip.position
	var pedal := rig.pedal_position(right)
	# ペダルの前後・上下はそのまま、横は足の幅ぶん外へ（自転車の中心線から FOOT_SIDE）。
	# 母指球はペダルの軸の上。かかとを上げる（foot_pitch）と、足首は上・前へ動く。
	var center := rig.transform.origin
	var lateral := (pedal - center).dot(bike.x)
	var above := ANKLE_ABOVE_PEDAL * cos(foot_pitch) + ANKLE_BEHIND_PEDAL * sin(foot_pitch)
	var behind := ANKLE_BEHIND_PEDAL * cos(foot_pitch) - ANKLE_ABOVE_PEDAL * sin(foot_pitch)
	var target := pedal + bike.x * (side * FOOT_SIDE - lateral) + bike.y * above - bike.z * behind
	var foot_basis := bike * Basis(Vector3.RIGHT, foot_pitch)
	if ground > 0.0:
		# 地面につく足：床は水平なので、体の向きの水平成分だけを使う。
		var flat_z := Vector3(body.z.x, 0.0, body.z.z).normalized()
		var flat := Basis(Vector3.UP.cross(flat_z).normalized(), Vector3.UP, flat_z)
		var planted := center + flat.x * (side * GROUND_FOOT_SIDE) + flat.z * GROUND_FOOT_FORWARD + Vector3.UP * GROUND_ANKLE_HEIGHT
		target = target.lerp(planted, ground) + Vector3.UP * (FOOT_STEP_LIFT * sin(PI * ground))
		foot_basis = Basis(foot_basis.get_rotation_quaternion().slerp(flat.get_rotation_quaternion(), ground))
	# ひざは前へ、少し外へ曲げる。
	var joint := _two_bone(hip_origin, target, THIGH, CALF, bike.z + bike.x * (side * 0.12))
	var reach := _clamped_end(hip_origin, target, THIGH + CALF)
	var hip_basis := _basis_pointing_down(joint - hip_origin, bike.x)
	var knee_basis := _basis_pointing_down(reach - joint, bike.x)
	hip.global_basis = world * hip_basis
	knee.global_basis = world * knee_basis
	ankle.global_basis = world * foot_basis
	var toe := parts.get(prefix + "toe") as Node3D
	if toe != null:
		toe.basis = Basis.IDENTITY


static func _solve_arm(
	parts: Dictionary, prefix: String, rig: MamachariRig, right: bool, side: float,
	bike: Basis, world: Basis, spine_origin: Vector3, spine_basis: Basis
) -> void:
	var shoulder := parts.get(prefix + "shoulder") as Node3D
	var elbow := parts.get(prefix + "elbow") as Node3D
	var wrist := parts.get(prefix + "wrist") as Node3D
	if shoulder == null or elbow == null or wrist == null:
		return
	var shoulder_origin := spine_origin + spine_basis * shoulder.position
	var grip := rig.grip_position(right)
	var outward := bike.x * side
	var target := grip + bike.y * WRIST_ABOVE_GRIP + outward * (rig.grip_radius() + WRIST_OUTSIDE_GRIP)
	# ひじは後ろ・下へ引く（わきを締める）。外へは少しだけ。
	var joint := _two_bone(shoulder_origin, target, UPPER_ARM, FOREARM, outward * 0.2 - bike.z * 1.0 - bike.y * 0.7)
	var reach := _clamped_end(shoulder_origin, target, UPPER_ARM + FOREARM)
	shoulder.global_basis = world * _basis_pointing_down(joint - shoulder_origin, bike.x)
	elbow.global_basis = world * _basis_pointing_down(reach - joint, bike.x)
	# 手：指が下、手のひら（指が巻く側 = 手の +Z）がグリップのほう、指の付け根の並びがグリップと平行。
	var hand_y := bike.y
	var hand_z := (-outward - hand_y * (-outward).dot(hand_y)).normalized()
	var hand_x := hand_y.cross(hand_z).normalized()
	wrist.global_basis = world * Basis(hand_x, hand_y, hand_z)
	_curl_fingers(parts, prefix)


## 指をグリップに巻きつける（親指は作ったときの形のまま）。
static func _curl_fingers(parts: Dictionary, prefix: String) -> void:
	var is_left := prefix == "l_"
	for index: int in range(FINGERS.size()):
		var spread := deg_to_rad((1.5 - index) * 5.0) * (1.0 if is_left else -1.0)
		_set_rotation(parts, prefix + FINGERS[index] + "_prox", Vector3(deg_to_rad(-70.0), 0.0, spread))
		_set_rotation(parts, prefix + FINGERS[index] + "_mid", Vector3(deg_to_rad(-75.0), 0.0, 0.0))
		_set_rotation(parts, prefix + FINGERS[index] + "_dist", Vector3(deg_to_rad(-50.0), 0.0, 0.0))
	_reset_thumb(parts, prefix, is_left)


## 降りたときに、指を作ったときの形へ戻す（通常のアニメに指の骨が無いと、巻いたまま残るため）。
static func release_hands(parts: Dictionary) -> void:
	for prefix: String in ["l_", "r_"]:
		var is_left := prefix == "l_"
		for index: int in range(FINGERS.size()):
			var spread := deg_to_rad((1.5 - index) * 5.0) * (1.0 if is_left else -1.0)
			_set_rotation(parts, prefix + FINGERS[index] + "_prox", Vector3(deg_to_rad(-5.0), 0.0, spread))
			_set_rotation(parts, prefix + FINGERS[index] + "_mid", Vector3(deg_to_rad(-10.0), 0.0, 0.0))
			_set_rotation(parts, prefix + FINGERS[index] + "_dist", Vector3(deg_to_rad(-10.0), 0.0, 0.0))
		_reset_thumb(parts, prefix, is_left)


static func _reset_thumb(parts: Dictionary, prefix: String, is_left: bool) -> void:
	var sign_value := 1.0 if is_left else -1.0
	_set_rotation(parts, prefix + "thumb_prox", Vector3(deg_to_rad(-20.0), deg_to_rad(45.0) * sign_value, deg_to_rad(30.0) * sign_value))
	_set_rotation(parts, prefix + "thumb_dist", Vector3(deg_to_rad(-15.0), 0.0, 0.0))


static func _set_rotation(parts: Dictionary, key: String, euler: Vector3) -> void:
	var node := parts.get(key) as Node3D
	if node != null:
		node.rotation = euler


## 2本の骨（長さ first・second）で root から target へ届かせるときの、あいだの関節の位置。
## hint は関節を曲げる向き。届かないときは、まっすぐ伸ばした向きで止まる。
static func _two_bone(root: Vector3, target: Vector3, first: float, second: float, hint: Vector3) -> Vector3:
	var offset := target - root
	var distance := clampf(offset.length(), absf(first - second) + 0.001, first + second - 0.001)
	var direction := offset.normalized() if offset.length_squared() > 0.000001 else Vector3.DOWN
	var along := (first * first - second * second + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(first * first - along * along, 0.0))
	var bend := hint - direction * hint.dot(direction)
	if bend.length_squared() < 0.000001:
		bend = direction.cross(Vector3.RIGHT)
	return root + direction * along + bend.normalized() * height


## target が total より遠いときは、届く所までに縮めた先の位置。
static func _clamped_end(root: Vector3, target: Vector3, total: float) -> Vector3:
	var offset := target - root
	if offset.length() <= total - 0.001:
		return target
	return root + offset.normalized() * (total - 0.001)


## 部品の -Y を direction に向ける（手足は -Y へ伸びた箱）。X は reference にできるだけ合わせる。
static func _basis_pointing_down(direction: Vector3, reference_x: Vector3) -> Basis:
	var y_axis := -direction.normalized()
	var x_axis := reference_x - y_axis * reference_x.dot(y_axis)
	if x_axis.length_squared() < 0.000001:
		x_axis = y_axis.cross(Vector3.FORWARD)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()
