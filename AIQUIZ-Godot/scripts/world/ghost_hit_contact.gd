class_name GhostHitContact
extends RefCounted

## GOSTRIDER の突進が生き残りに当たる瞬間の「当たり方」（docs/ghost_hit_ragdoll_plan.md 段階 1・2）。
## サメ（ゴースト時）の胴を「鼻先から後ろへの断面の楕円」で表し、体の部品の箱の点のどれが最初に触れるかを求める。
## 当たる / 外れるの判定はしない（それは GhostSharkRideController の今までの基準のまま）。ここは時刻と部位と飛ばし方だけ。
## 断面の座標はサメのノードのローカル（前 = −Z、上 = +Y、横 = X。ゴースト時はノードの大きさ 0.62）。

## 鼻先の前の位置（ローカルの −Z）。
const PROFILE_FRONT := 5.39
## 断面の間隔（ローカル）。
const PROFILE_STEP := 0.4
## 鼻先から PROFILE_STEP ごとの断面：[中心の上下, 横の半径, 上下の半径]。
## 静止姿勢の SK_Shark_001 の面を細かく取り、横は 97% の点、上下は最大で測った（2026-11-05）。
## 測り方：tests/ghost_hit_capture_runtime.gd の dims.profile_local。サメのモデルを直したら測り直す。
## 0〜2.8：頭、3.2〜4.4：胸びれ、4.4〜5.6：背びれ、6.0〜：尾。
const PROFILE := [
	[-0.249, 0.253, 0.211],
	[-0.312, 0.430, 0.420],
	[-0.429, 0.563, 0.639],
	[-0.432, 0.586, 0.722],
	[-0.443, 0.701, 0.792],
	[-0.450, 0.753, 0.862],
	[-0.451, 0.811, 0.927],
	[-0.458, 0.836, 0.970],
	[-0.495, 1.462, 1.044],
	[-0.649, 1.987, 1.235],
	[-0.546, 2.102, 1.497],
	[-0.059, 1.112, 1.492],
	[0.135, 0.763, 1.645],
	[0.280, 0.711, 1.741],
	[-0.156, 0.654, 1.265],
	[-0.461, 0.601, 0.920],
	[-0.526, 0.545, 0.845],
	[-0.588, 0.485, 0.817],
	[-0.471, 0.436, 0.626],
	[-0.460, 0.386, 0.677],
	[-0.432, 0.324, 0.726],
	[-0.471, 0.270, 0.367],
	[-0.517, 0.218, 0.481],
	[-0.578, 0.130, 0.880],
	[-0.531, 0.050, 1.157],
	[-0.443, 0.039, 1.341],
]
## 当たり方を調べる体の部品 → ラグドールの体の名前（RagdollBuilder.LIMB_SPECS の key。胴の上下 2 つの箱は torso）。
const PART_KEYS := {
	"head": "head",
	"upper_torso": "torso",
	"lower_torso": "torso",
	"l_upp_arm": "l_upp_arm",
	"l_low_arm": "l_low_arm",
	"l_hand": "l_hand",
	"r_upp_arm": "r_upp_arm",
	"r_low_arm": "r_low_arm",
	"r_hand": "r_hand",
	"l_thigh": "l_thigh",
	"l_calf": "l_calf",
	"l_foot": "l_foot",
	"r_thigh": "r_thigh",
	"r_calf": "r_calf",
	"r_foot": "r_foot",
}
## GhostSharkRideController._segment_hits_survivor の横の幅。横ずれ s はこれで割る。
const HIT_HALF_WIDTH := 1.45

## 段階 2：横ずれ |s| がこれ以下は「真ん中」（向きはサメの進む向きのまま、縦を上乗せ）。
const CENTER_END := 0.3
## |s| がこれ以上は「横」（当たった側へ SIDE_MIN_DEG〜SIDE_MAX_DEG ふる）。間は混ぜる。
const SIDE_START := 0.45
const SIDE_MIN_DEG := 15.0
const SIDE_MAX_DEG := 40.0
## 真ん中の命中の縦の上乗せ（m/s）。
const CENTER_VERTICAL_BONUS := 1.2

## 段階 4：戻り方。PERFECT か強さ TUMBLE_POWER 以上は「転倒」（倒れて転がり、起き上がる）、ほかは「立て直し」（空中で立て直して足から着地）。
## ただし転倒は、操作ロックが着地より後まで続くときだけ（下の数値では、どの命中も空中で操作が戻るので起きない）。
const TUMBLE_POWER := 0.8
## 操作ロック：強さで MIN_CONTROL_LOCK〜MAX_CONTROL_LOCK 秒（PERFECT の上乗せなし）。ゲームの元の数値。
## 段階 4 で「立て直しは着地の後まで・転倒は 2.1 秒」に延ばしたが、操作できない時間が長くサメが強すぎたので戻した（2026-11-06）。
const MIN_CONTROL_LOCK := 0.25
const MAX_CONTROL_LOCK := 0.48
## 立て直しの着地の横の速さがこれ以上なら、着地を受け身の転がり（Roll）にする（体の演出がまだ続いているときだけ見える）。
const ROLL_LANDING_SPEED := 7.0


## 体の部品のうち、サメが最初に触れる点。
## 戻り値：{"lead": 鼻先があと何 m 進むと触れるか（0 以下ならもう触れている・食い込んでいる。触れない形なら INF）,
##         "part": ラグドールの体の名前, "point": 触れる点（ワールド）, "radial": サメの軸からその点への向き（ワールド、単位）}
static func find_contact(shark: Node3D, parts: Dictionary) -> Dictionary:
	var best := {"lead": INF, "part": "torso", "point": Vector3.ZERO, "radial": Vector3.ZERO}
	if shark == null or not is_instance_valid(shark) or parts.is_empty():
		return best
	var shark_xf := shark.global_transform
	var to_local := shark_xf.affine_inverse()
	var scale := shark_xf.basis.get_scale().x
	var best_lead_local := INF
	var best_local := Vector3.ZERO
	for key: String in PART_KEYS:
		var value: Variant = parts.get(key)
		if not (value is Node3D) or not is_instance_valid(value):
			continue
		for point in part_points(value as Node3D):
			var local := to_local * point
			var lead := _lead_local(local)
			if lead < best_lead_local:
				best_lead_local = lead
				best_local = local
				best.part = PART_KEYS[key]
				best.point = point
	if best_lead_local == INF:
		return best
	best.lead = best_lead_local * scale
	var section := _section_index(PROFILE_FRONT - (-best_local.z))
	var center_up := float(PROFILE[section][0]) if section >= 0 else 0.0
	var radial_local := Vector3(best_local.x, best_local.y - center_up, 0.0)
	if radial_local.length_squared() > 0.000001:
		best.radial = (shark_xf.basis * radial_local).normalized()
	return best


## 部品の箱の点（中心・8 つの角・6 つの面の中心）。メッシュでない部品（手）は付け根の点だけ。
static func part_points(node: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	var mesh := node as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		points.append(node.global_position)
		return points
	var box := mesh.get_aabb()
	var xf := mesh.global_transform
	var center := box.get_center()
	var half := box.size * 0.5
	points.append(xf * center)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				points.append(xf * (center + Vector3(half.x * sx, half.y * sy, half.z * sz)))
	for axis in range(3):
		for face: float in [-1.0, 1.0]:
			var offset := Vector3.ZERO
			offset[axis] = half[axis] * face
			points.append(xf * (center + offset))
	return points


## サメのローカルの点 local に、鼻先があと何（ローカル単位）進むと触れるか。いちばん前で触れる断面で決める。
static func _lead_local(local: Vector3) -> float:
	var depth := PROFILE_FRONT - (-local.z)
	# 鼻先より 8 以上前の点は、まだ調べなくてよい（突進の 1 フレームは最大 1.4 ほど）。
	if depth < -8.0:
		return INF
	for k in range(PROFILE.size()):
		var row: Array = PROFILE[k]
		var side := local.x / float(row[1])
		var up := (local.y - float(row[0])) / float(row[2])
		if side * side + up * up <= 1.0:
			return float(k) * PROFILE_STEP - depth
	return INF


static func _section_index(depth: float) -> int:
	if depth < 0.0:
		return 0
	var k := int(depth / PROFILE_STEP)
	return k if k < PROFILE.size() else -1


## 横ずれ s：サメの進む線（水平）から target までの横の距離（進む向きの右が +）を、判定の幅で割った値（−1〜1）。
static func lateral_offset(from: Vector3, direction: Vector3, target: Vector3) -> float:
	var flat := Vector2(direction.x, direction.z)
	if flat.length_squared() < 0.000001:
		return 0.0
	flat = flat.normalized()
	var right := Vector2(-flat.y, flat.x)
	return clampf(Vector2(target.x - from.x, target.z - from.z).dot(right) / HIT_HALF_WIDTH, -1.0, 1.0)


## 当たり方による飛ばし方（段階 2）：{"direction": 水平の単位ベクトル（x, z）, "vertical_bonus": 縦の上乗せ m/s}
## 真ん中はサメの進む向きのまま縦を上乗せ、横ずれは当たった側（s の符号の側）へ 15〜40° ふる。
static func deflect(direction: Vector2, s: float) -> Dictionary:
	var flat := direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var amount := absf(s)
	var angle_deg := 0.0
	if amount >= SIDE_START:
		angle_deg = lerpf(SIDE_MIN_DEG, SIDE_MAX_DEG, inverse_lerp(SIDE_START, 1.0, minf(amount, 1.0)))
	elif amount > CENTER_END:
		angle_deg = SIDE_MIN_DEG * smoothstep(CENTER_END, SIDE_START, amount)
	var angle := deg_to_rad(angle_deg) * signf(s)
	var right := Vector2(-flat.y, flat.x)
	return {
		"direction": (flat * cos(angle) + right * sin(angle)).normalized(),
		"vertical_bonus": CENTER_VERTICAL_BONUS * (1.0 - smoothstep(CENTER_END, SIDE_START, amount)),
	}


static func is_tumble(power: float, perfect: bool) -> bool:
	return perfect or power >= TUMBLE_POWER


## 吹き飛ばしのあとの戻り方（段階 4）。オフライン・ホスト（操作ロックを決める）と両方の画面の見た目が同じ式を使う。
## horizontal_speed・vertical_speed はゲームに入れる吹き飛ばし（横は上限で切った値、縦は上乗せ込み）。
## 戻り値：{"tumble": 転倒か, "air": 滞空（秒。床から飛んだとして）, "landing_speed": 着地の横の速さ,
##         "roll": 立て直しで着地を転がりにするか, "control_lock": 操作ロック（秒）}
static func recovery_plan(power: float, perfect: bool, horizontal_speed: float, vertical_speed: float) -> Dictionary:
	var air := 2.0 * maxf(vertical_speed, 0.0) / QuizGameState.GRAVITY
	var landing_speed := maxf(0.0, horizontal_speed - QuizGameState.EXTERNAL_IMPULSE_DECELERATION * air)
	var lock := lerpf(MIN_CONTROL_LOCK, MAX_CONTROL_LOCK, clampf(power, 0.0, 1.0))
	# 空中で操作が戻るなら、床で転がって起き上がる見せ方はしない（操作できるのに寝ていることになる）。
	var tumble := is_tumble(power, perfect) and lock >= air
	var roll := not tumble and landing_speed >= ROLL_LANDING_SPEED
	return {"tumble": tumble, "air": air, "landing_speed": landing_speed, "roll": roll, "control_lock": lock}
