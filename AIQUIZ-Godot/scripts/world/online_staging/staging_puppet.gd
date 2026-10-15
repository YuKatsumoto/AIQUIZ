class_name StagingPuppet
extends RefCounted

## マッチング演出のキャラ 1 人（PlayerController の箱の人形の 1 体）を、決めた位置・向き・動きで止めて見せる。
## PlayerController の update_from_state（ゲームの動き）は使わず、毎フレーム次の順で置く：
##   1. pose(clip, slot, ratio)：UAL のクリップを位置 0〜1 で当てる（_apply_intro_ual_pose と同じ道）
##   2. stand_at(位置, 向き, 床の高さ) か sit_at(座る Transform3D)：pelvis をワールドで置き直す
## 向き（yaw）は +Z を回す角度（目印の yaw_deg と同じ約束）。UAL のポーズを当てた箱の人形はそのまま +Z が前。
## 立つときは足の裏の実測を床に合わせる（ポーズで BASE_Y から 0.14〜0.19 m ずれるため。仕様書 5）。

const FOOT_CLEARANCE := 0.01
## つなぎ（下の begin_blend）で動かす指（INTRO_CABIN_POSE_KEYS のほかに _apply_skeleton_pose が動かす部位）
const BLEND_FINGER_KEYS := [
	"l_thumb_prox", "l_thumb_dist", "l_index_prox", "l_index_mid", "l_index_dist",
	"l_middle_prox", "l_middle_mid", "l_middle_dist", "l_ring_prox", "l_ring_mid", "l_ring_dist",
	"l_pinky_prox", "l_pinky_mid", "l_pinky_dist",
	"r_thumb_prox", "r_thumb_dist", "r_index_prox", "r_index_mid", "r_index_dist",
	"r_middle_prox", "r_middle_mid", "r_middle_dist", "r_ring_prox", "r_ring_mid", "r_ring_dist",
	"r_pinky_prox", "r_pinky_mid", "r_pinky_dist",
]

var controller: PlayerController
var index := 1   # 1 = p1_parts、2 = p2_parts

var _visible := true
## つなぎ：区切りの直前に見えていた姿（次の apply_blend で差に直す）・新しい動きとの差・長さ・経過
var _blend_snapshot := {}
var _blend_offsets := {}
var _blend_seconds := 0.0
var _blend_time := 0.0


func _init(p_controller: PlayerController, p_index: int) -> void:
	controller = p_controller
	index = p_index


func parts() -> Dictionary:
	return controller.p1_parts if index == 1 else controller.p2_parts


func rig() -> AnimationRig:
	return controller.get("_p1_rig") if index == 1 else controller.get("_p2_rig")


func is_ready() -> bool:
	return not parts().is_empty() and parts().get("pelvis") != null


func set_visible(value: bool) -> void:
	if not is_ready():
		return
	_visible = value
	controller.call("_set_parts_visible", parts(), value)
	controller.call("_set_hat_visible", index == 1, value)
	controller.call("_set_rig_scenes_visible", index == 1, false)


func is_visible() -> bool:
	return _visible


func set_hat(hat_id: int) -> void:
	controller.set_hat(index, hat_id)


## 体の塗り（PlayerSkin 形式、{} はスロットの標準色）。
func set_skin(skin: Dictionary) -> void:
	controller.set_skin(index, skin)


## UAL のクリップを当てる。slot は AnimationRig.SLOT_UAL（UAL1）か SLOT_UAL2。ratio は 0〜1（ループは呼ぶ側で fposmod）。
func pose(clip: String, ratio: float, slot: int = AnimationRig.SLOT_UAL) -> bool:
	var r := rig()
	if r == null or not r.seek_ual_clip(clip, ratio, slot) or r.active_skeleton == null:
		return false
	controller.call("_apply_skeleton_pose", parts(), r.active_skeleton, r.active_bone_indices, r.mirror_x)
	return true


## 2 つのクリップを重み w でまぜる（w = 0 で a、1 で b）。pelvis の高さもまぜる。
func pose_blend(clip_a: String, ratio_a: float, clip_b: String, ratio_b: float, w: float,
		slot_a: int = AnimationRig.SLOT_UAL, slot_b: int = AnimationRig.SLOT_UAL) -> bool:
	if w <= 0.001:
		return pose(clip_a, ratio_a, slot_a)
	if w >= 0.999:
		return pose(clip_b, ratio_b, slot_b)
	if not pose(clip_a, ratio_a, slot_a):
		return pose(clip_b, ratio_b, slot_b)
	var first := _capture()
	if not pose(clip_b, ratio_b, slot_b):
		_restore(first)
		return true
	var second := _capture()
	for key: String in first:
		var a: Transform3D = first[key]
		var b: Transform3D = second.get(key, a)
		var node := parts().get(key) as Node3D
		if node == null:
			continue
		var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), w)
		node.transform = Transform3D(Basis(q), a.origin.lerp(b.origin, w))
	return true


func clip_length(clip: String, slot: int = AnimationRig.SLOT_UAL) -> float:
	var r := rig()
	return r.get_ual_clip_length(clip, slot) if r != null else 0.0


## 立たせる：位置（x, z を使う）・向き・床の高さ（ワールド）。足の裏の低いほうを床に合わせる。
func stand_at(position: Vector3, yaw: float, ground_y: float, frame: Basis = Basis.IDENTITY) -> void:
	var pelvis := parts().get("pelvis") as Node3D
	if pelvis == null:
		return
	var pose_basis := pelvis.basis
	var hips := pelvis.position.y - PlayerController.BASE_Y
	pelvis.global_transform = Transform3D(frame * Basis(Vector3.UP, yaw) * pose_basis, Vector3(position.x, ground_y + hips, position.z))
	var lowest: float = controller.call("_lowest_intro_foot_mesh_y", parts())
	if is_finite(lowest):
		pelvis.global_position.y += ground_y + FOOT_CLEARANCE - lowest


## 座らせる：seat は pelvis の置き場所（目印 MK_SeatPassenger をワールドに直したもの。basis が向き）。
func sit_at(seat: Transform3D) -> void:
	var pelvis := parts().get("pelvis") as Node3D
	if pelvis == null:
		return
	pelvis.global_transform = Transform3D(seat.basis * pelvis.basis, seat.origin)


## 体の中心あたり（カメラの注視などに使う）。
func center() -> Vector3:
	var spine := parts().get("spine") as Node3D
	return spine.global_position if spine != null else Vector3.ZERO


## 動きの区切り（立つ → 歩く → 座る → ハンドルを握る）を 1 つの動きとしてつなぐ（慣性ブレンド）。
## 区切りが変わったフレームで、pose・stand_at／sit_at より前に呼ぶ。そのとき見えている姿（前の動きの最後）を覚え、
## 同じフレームの apply_blend で新しい動きとの差に直して、seconds 秒かけて差を 0 にする（新しい動きの速さは保つ）。
func begin_blend(seconds: float) -> void:
	if not is_ready() or seconds <= 0.0:
		cancel_blend()
		return
	_blend_snapshot = _capture_display()
	_blend_offsets = {}
	_blend_seconds = seconds
	_blend_time = 0.0


func cancel_blend() -> void:
	_blend_snapshot = {}
	_blend_offsets = {}
	_blend_seconds = 0.0
	_blend_time = 0.0


func is_blending() -> bool:
	return _blend_seconds > 0.0


## 毎フレーム、pose と stand_at／sit_at のあとに呼ぶ（delta は演出の時計の進み）。
func apply_blend(delta: float) -> void:
	if _blend_seconds <= 0.0 or not is_ready():
		return
	var target := _capture_display()
	if not _blend_snapshot.is_empty():
		for key: String in _blend_snapshot:
			if not target.has(key):
				continue
			var from: Transform3D = _blend_snapshot[key]
			var to: Transform3D = target[key]
			_blend_offsets[key] = [
				from.basis.get_rotation_quaternion() * to.basis.get_rotation_quaternion().inverse(),
				from.origin - to.origin,
			]
		_blend_snapshot = {}
	else:
		_blend_time += delta
	var k := 1.0 - smoothstep(0.0, 1.0, _blend_time / _blend_seconds)
	if k <= 0.0:
		cancel_blend()
		return
	var all := parts()
	for key: String in _blend_offsets:
		var node := all.get(key) as Node3D
		if node == null or not target.has(key):
			continue
		var to: Transform3D = target[key]
		var offset: Array = _blend_offsets[key]
		var q := Quaternion.IDENTITY.slerp(offset[0] as Quaternion, k) * to.basis.get_rotation_quaternion()
		var blended := Transform3D(Basis(q) * Basis.from_scale(to.basis.get_scale()), to.origin + (offset[1] as Vector3) * k)
		# pelvis はワールド（置き場所ごと）、ほかは親からの姿（ポーズ）でつなぐ
		if key == "pelvis":
			node.global_transform = blended
		else:
			node.transform = blended


## 今見えている姿：pelvis はワールド、ほかは親から。
func _capture_display() -> Dictionary:
	var out := {}
	var all := parts()
	for key: String in PlayerController.INTRO_CABIN_POSE_KEYS + BLEND_FINGER_KEYS:
		var node := all.get(key) as Node3D
		if node == null or not node.is_inside_tree():
			continue
		out[key] = node.global_transform if key == "pelvis" else node.transform
	return out


func _capture() -> Dictionary:
	var out := {}
	for key: String in PlayerController.INTRO_CABIN_POSE_KEYS:
		var node := parts().get(key) as Node3D
		if node != null:
			out[key] = node.transform
	return out


func _restore(pose_data: Dictionary) -> void:
	for key: String in pose_data:
		var node := parts().get(key) as Node3D
		if node != null:
			node.transform = pose_data[key]
