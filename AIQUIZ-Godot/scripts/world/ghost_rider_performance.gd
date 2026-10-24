class_name GhostRiderPerformance
extends RefCounted

## GOSTRIDER の乗り手の演技（assets/animations/ghost_rider_performance.json）を読み、ブロック人形の部品に当てる。
## 演技は Blender でゲームのブロック人形と同じ寸法の複製リグに付け、鞍のハンドル・足掛けへ IK で焼いてある
## （assets/animations/source/ghost_rider/build_ghost_rider_performance.py）。骨の回転はそのまま部品のローカル回転。
## 乗り手はサメの GhostMountSocket の向きそのままで、大きさ rider_scale × サメのモデルの倍率で乗せる。

const DATA_PATH := "res://assets/animations/ghost_rider_performance.json"
const CLIP_PERFORMANCE := &"performance"
const CLIP_IDLE := &"idle"
const CLIP_WINDUP := &"windup"
const CLIP_DASH := &"dash"
## 指の曲げ（握り 1 のとき、各関節を X 回りにこれだけ足す。度）。
const FINGER_CURL_DEGREES := [-48.0, -62.0, -46.0]
const THUMB_CURL_DEGREES := [-24.0, -38.0]
const FINGERS := ["index", "middle", "ring", "pinky"]

static var _data: Dictionary = {}
static var _loaded := false
static var _bones: PackedStringArray = PackedStringArray()
## クリップ名 -> {frames, rotations: Array[PackedFloat32Array（骨 × 4）], pelvis: PackedVector3Array, grips: PackedVector2Array}
static var _clips: Dictionary = {}
static var _phases: Dictionary = {}
static var _fps := 30.0
static var _rider_scale := 0.7


static func ensure_loaded() -> bool:
	if _loaded:
		return not _clips.is_empty()
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("GhostRiderPerformance: %s is missing" % DATA_PATH)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Dictionary):
		push_warning("GhostRiderPerformance: %s could not be parsed" % DATA_PATH)
		return false
	_data = parsed
	_fps = float(_data.get("fps", 30.0))
	_rider_scale = float(_data.get("rider_scale", 0.7))
	_phases = _data.get("phases", {})
	_bones = PackedStringArray(_data.get("bones", []))
	var clips: Dictionary = _data.get("clips", {})
	for clip_name: String in clips:
		var clip: Dictionary = clips[clip_name]
		var rotations: Array[PackedFloat32Array] = []
		for row: Array in clip.get("rotations", []):
			var flat := PackedFloat32Array()
			flat.resize(row.size() * 4)
			for index: int in range(row.size()):
				var q: Array = row[index]
				flat[index * 4] = float(q[0])
				flat[index * 4 + 1] = float(q[1])
				flat[index * 4 + 2] = float(q[2])
				flat[index * 4 + 3] = float(q[3])
			rotations.append(flat)
		var pelvis := PackedVector3Array()
		for p: Array in clip.get("pelvis", []):
			pelvis.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		var grips := PackedVector2Array()
		for g: Array in clip.get("grips", []):
			grips.append(Vector2(float(g[0]), float(g[1])))
		_clips[StringName(clip_name)] = {
			"frames": int(clip.get("frames", rotations.size())),
			"rotations": rotations,
			"pelvis": pelvis,
			"grips": grips,
		}
	_data.erase("clips")
	return not _clips.is_empty()


static func rider_scale() -> float:
	ensure_loaded()
	return _rider_scale


static func has_clip(clip: StringName) -> bool:
	return ensure_loaded() and _clips.has(clip)


static func clip_length(clip: StringName) -> float:
	if not has_clip(clip):
		return 0.0
	return float(int(_clips[clip].frames) - 1) / _fps


## 演技の時刻（秒）：フェーズの区切り + そのフェーズに入ってからの秒（区切りの長さで止める）。
static func performance_time(phase_name: String, phase_elapsed: float) -> float:
	if not ensure_loaded():
		return 0.0
	var order := ["DEATH_HOLD", "SOUL_RISE", "SOUL_FLIGHT", "MOUNTING", "BEAM_REVEAL", "ENTERING", "END"]
	var index := order.find(phase_name)
	if index < 0:
		return float(_phases.get("END", 0.0))
	var start := float(_phases.get(phase_name, 0.0))
	var finish := float(_phases.get(order[mini(index + 1, order.size() - 1)], start))
	return clampf(start + maxf(0.0, phase_elapsed), start, maxf(start, finish))


static func phase_start(phase_name: String) -> float:
	ensure_loaded()
	return float(_phases.get(phase_name, 0.0))


## 1 つのクリップの、ある時刻の姿勢 {"rot": {骨: Quaternion}, "pelvis": Vector3, "grips": Vector2}。
static func sample(clip: StringName, seconds: float, looped: bool = false) -> Dictionary:
	if not has_clip(clip):
		return {}
	var data: Dictionary = _clips[clip]
	var frames := int(data.frames)
	var rotations: Array[PackedFloat32Array] = data.rotations
	var pelvis: PackedVector3Array = data.pelvis
	var grips: PackedVector2Array = data.grips
	var position := seconds * _fps
	if looped and frames > 1:
		position = fposmod(position, float(frames - 1))
	position = clampf(position, 0.0, float(frames - 1))
	var index_a := int(floor(position))
	var index_b := mini(index_a + 1, frames - 1)
	var blend := position - float(index_a)
	var row_a := rotations[index_a]
	var row_b := rotations[index_b]
	var rot := {}
	for bone_index: int in range(_bones.size()):
		var base := bone_index * 4
		var qa := Quaternion(row_a[base], row_a[base + 1], row_a[base + 2], row_a[base + 3])
		var qb := Quaternion(row_b[base], row_b[base + 1], row_b[base + 2], row_b[base + 3])
		rot[_bones[bone_index]] = qa.slerp(qb, blend) if blend > 0.0001 else qa
	return {
		"rot": rot,
		"pelvis": pelvis[index_a].lerp(pelvis[index_b], blend),
		"grips": grips[index_a].lerp(grips[index_b], blend),
	}


## 2 つの姿勢を混ぜる（weight 0 で a、1 で b）。
static func blend_poses(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	if a.is_empty():
		return b
	if b.is_empty() or weight <= 0.0:
		return a
	if weight >= 1.0:
		return b
	var rot := {}
	var rot_a: Dictionary = a.rot
	var rot_b: Dictionary = b.rot
	for bone: String in rot_a:
		var qa: Quaternion = rot_a[bone]
		var qb: Quaternion = rot_b.get(bone, qa)
		rot[bone] = qa.slerp(qb, weight)
	return {
		"rot": rot,
		"pelvis": (a.pelvis as Vector3).lerp(b.pelvis, weight),
		"grips": (a.grips as Vector2).lerp(b.grips, weight),
	}


## 姿勢を部品へ当てる。bind_pelvis は腰の組み立て時の位置。only_bones を渡すとその骨だけ当てる。
static func apply_pose(parts: Dictionary, pose: Dictionary, bind_pelvis: Vector3, only_bones: Array = []) -> void:
	if pose.is_empty():
		return
	var rot: Dictionary = pose.rot
	for bone: String in rot:
		if not only_bones.is_empty() and not only_bones.has(bone):
			continue
		var part := parts.get(bone) as Node3D
		if part != null:
			part.quaternion = rot[bone]
	if only_bones.is_empty() or only_bones.has("pelvis"):
		var pelvis := parts.get("pelvis") as Node3D
		if pelvis != null:
			pelvis.position = bind_pelvis + (pose.pelvis as Vector3)
	if only_bones.is_empty() or only_bones.has("fingers"):
		var grips: Vector2 = pose.grips
		_apply_grip(parts, "l_", grips.x)
		_apply_grip(parts, "r_", grips.y)


## 握り（0 = 開く、1 = 拳）。指の関節の組み立て時の向きに、X 回りの曲げを足す。
static func _apply_grip(parts: Dictionary, prefix: String, grip: float) -> void:
	var amount := clampf(grip, 0.0, 1.0)
	for finger: String in FINGERS:
		for joint_index: int in range(3):
			var key: String = prefix + finger + ["_prox", "_mid", "_dist"][joint_index]
			var joint := parts.get(key) as Node3D
			if joint == null:
				continue
			var rest: Basis = _rest_basis(joint)
			joint.basis = rest * Basis(Vector3.RIGHT, deg_to_rad(FINGER_CURL_DEGREES[joint_index] * amount))
	for joint_index: int in range(2):
		var key: String = prefix + ["thumb_prox", "thumb_dist"][joint_index]
		var joint := parts.get(key) as Node3D
		if joint == null:
			continue
		var rest: Basis = _rest_basis(joint)
		joint.basis = rest * Basis(Vector3.RIGHT, deg_to_rad(THUMB_CURL_DEGREES[joint_index] * amount))


## 乗り手を組んだ直後に呼ぶ：指の関節の組み立て時の向きを覚える（踊りの写しで指が動いたあとも戻せる）。
static func remember_rest(parts: Dictionary) -> void:
	for prefix: String in ["l_", "r_"]:
		for finger: String in FINGERS:
			for joint_suffix: String in ["_prox", "_mid", "_dist"]:
				var joint := parts.get(prefix + finger + joint_suffix) as Node3D
				if joint != null:
					joint.set_meta(&"ghost_rider_rest_basis", joint.basis)
		for thumb: String in ["thumb_prox", "thumb_dist"]:
			var joint := parts.get(prefix + thumb) as Node3D
			if joint != null:
				joint.set_meta(&"ghost_rider_rest_basis", joint.basis)


static func _rest_basis(joint: Node3D) -> Basis:
	if not joint.has_meta(&"ghost_rider_rest_basis"):
		joint.set_meta(&"ghost_rider_rest_basis", joint.basis)
	return joint.get_meta(&"ghost_rider_rest_basis")
