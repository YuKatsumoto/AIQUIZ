class_name DropMotion
extends RefCounted

## つきやぶれ！スカイゲートの人の動き（docs/sudden_death_v2/skygate_build_plan.md 4.4、heli_drop.md 第2章・3.1）。
## 素材は drop_moves.glb（Quaternius UAL と同じ名前・同じ骨。AnimationRig.SLOT_DROP で読む）と
## drop_moves.json（クリップごとの長さ・端を離れる時刻・腹ばいに落ち着く時刻・着地の時刻・根の動き）。
## 本物のアバター（StagingPuppet）は pose_puppet、人形（EmoteBlockmanPreview.build_player_skeleton）は pose_doll で同じクリップを当てる。
##
## クリップの座標（json の root も同じ）：Godot の向きで +Z が前、+Y が上、+X が体の左。原点はクリップの初めの足もと。
## 骨（pelvis）が持つのは体の姿（体の向き・宙返り・腰の高さ）だけで、進む・跳ぶ・落ちるは json の root に分けてある
## （PlayerController の骨の当て方は腰の前後左右を捨てるため）。置き場所は place（足を床に合わせる）か、呼ぶ側が root_offset で置く。
## 人形は UAL の左右が鏡に映る（AnimationRig の mirror_x）。敬礼などの「右手」は人形の右手になるよう作ってある。

const GLB_PATH := "res://assets/animations/sudden_death/drop_moves.glb"
const INFO_PATH := "res://assets/animations/sudden_death/drop_moves.json"

const BENCH_SIT := "SD_Bench_Sit_Loop"
const BENCH_BELT := "SD_Bench_Belt_Click"
const BENCH_UNBUCKLE := "SD_Bench_Unbuckle_Stand"
const RAMP_RUN_UP := "SD_Ramp_Run_Up"
const RAMP_WALK := "SD_Ramp_Walk"
const RAMP_RUN_OUT := "SD_Ramp_Run_Out"
const BOX_LOOP := "SD_Box_Loop"
const BOX_LEAN_LEFT := "SD_Box_Lean_Left"
const BOX_LEAN_RIGHT := "SD_Box_Lean_Right"
const BOX_LEAN_FORWARD := "SD_Box_Lean_Forward"
const BOX_LEAN_BACK := "SD_Box_Lean_Back"
const HESITATE := "SD_Jump_Hesitate"

const BENCH_CLIPS: Array[String] = [BENCH_SIT, BENCH_BELT, BENCH_UNBUCKLE]
const RAMP_CLIPS: Array[String] = [RAMP_RUN_UP, RAMP_WALK, RAMP_RUN_OUT]
const BASIC_JUMPS: Array[String] = ["SD_Jump_Basic_A", "SD_Jump_Basic_B"]
## かっこいい 4 つ・おもしろ 4 つ（heli_drop.md 2.2 の表の順）。
const SPECIAL_JUMPS: Array[String] = [
	"SD_Jump_Superman", "SD_Jump_Backflip", "SD_Jump_SpinDive", "SD_Jump_Starfish",
	"SD_Jump_Trip", "SD_Jump_Cannonball", "SD_Jump_Salute", HESITATE,
]
const BOX_CLIPS: Array[String] = [BOX_LOOP, BOX_LEAN_LEFT, BOX_LEAN_RIGHT, BOX_LEAN_FORWARD, BOX_LEAN_BACK]
const LANDINGS: Array[String] = ["SD_Land_Hero", "SD_Land_Roll", "SD_Land_Stick"]

## 1 人ごとに特別な降り方になる割合（決定）。
const SPECIAL_CHANCE := 0.15
## どの降り方も、端を離れてからこの秒数以内に共通の腹ばいに落ち着く（heli_drop.md 2.2）。
const SETTLE_LIMIT := 1.2
## 2 人目は 1 人目からこれだけ遅れて駆け出す（heli_drop.md 3.1）。
const JUMP_STAGGER := 0.4

const BASE_Y := -1.2
const FOOT_CLEARANCE := 0.01
const FOOT_FIX_META := &"drop_motion_foot_fix"
const FOOT_MESH_KEYS := ["l_foot", "r_foot", "l_toe_mesh", "r_toe_mesh", "l_calf", "r_calf"]

## 人形の部位 ← UAL の骨（PlayerController._load_fbx_scene の対応表と同じ骨）。3 つめは骨の向きを X まわりに裏返すか。
const PART_BONES := [
	["spine", "spine_02", false], ["neck", "neck_01", false], ["head_pivot", "Head", false],
	["l_shoulder", "upperarm_l", true], ["l_elbow", "lowerarm_l", true], ["l_wrist", "hand_l", true],
	["r_shoulder", "upperarm_r", true], ["r_elbow", "lowerarm_r", true], ["r_wrist", "hand_r", true],
	["l_hip", "thigh_l", true], ["l_knee", "calf_l", true], ["l_ankle", "foot_l", true], ["l_toe", "ball_l", true],
	["r_hip", "thigh_r", true], ["r_knee", "calf_r", true], ["r_ankle", "foot_r", true], ["r_toe", "ball_r", true],
	["l_thumb_prox", "thumb_01_l", true], ["l_thumb_dist", "thumb_02_l", true],
	["l_index_prox", "index_01_l", true], ["l_index_mid", "index_02_l", true], ["l_index_dist", "index_03_l", true],
	["l_middle_prox", "middle_01_l", true], ["l_middle_mid", "middle_02_l", true], ["l_middle_dist", "middle_03_l", true],
	["l_ring_prox", "ring_01_l", true], ["l_ring_mid", "ring_02_l", true], ["l_ring_dist", "ring_03_l", true],
	["l_pinky_prox", "pinky_01_l", true], ["l_pinky_mid", "pinky_02_l", true], ["l_pinky_dist", "pinky_03_l", true],
	["r_thumb_prox", "thumb_01_r", true], ["r_thumb_dist", "thumb_02_r", true],
	["r_index_prox", "index_01_r", true], ["r_index_mid", "index_02_r", true], ["r_index_dist", "index_03_r", true],
	["r_middle_prox", "middle_01_r", true], ["r_middle_mid", "middle_02_r", true], ["r_middle_dist", "middle_03_r", true],
	["r_ring_prox", "ring_01_r", true], ["r_ring_mid", "ring_02_r", true], ["r_ring_dist", "ring_03_r", true],
	["r_pinky_prox", "pinky_01_r", true], ["r_pinky_mid", "pinky_02_r", true], ["r_pinky_dist", "pinky_03_r", true],
]
const HIPS_BONE := "pelvis"
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

static var _info := {}
static var _info_loaded := false
## 人形用：glb から取り出したクリップ（Animation）と骨の休みの姿・親。
static var _rig_loaded := false
static var _anims := {}
static var _tracks := {}
static var _bone_names: PackedStringArray = []
static var _bone_parent: PackedInt32Array = []
static var _bone_rest: Array[Transform3D] = []


static func all_clips() -> Array[String]:
	var out: Array[String] = []
	for group: Array[String] in [BENCH_CLIPS, RAMP_CLIPS, BASIC_JUMPS, SPECIAL_JUMPS, BOX_CLIPS, LANDINGS]:
		out.append_array(group)
	return out


static func is_jump(clip: String) -> bool:
	return BASIC_JUMPS.has(clip) or SPECIAL_JUMPS.has(clip)


# ------------------------------------------------------------------ 選び方

## 新しい降下の回を始める（choose_jump の前に 1 回）。first は先に飛ぶ人（1 か 2。先はランダム：呼ぶ側が決める）。
## この回の降り方を「前の回」へ移し、2 人目（「ためらい」を出せる人）を覚える。
static func start_drop(last: Dictionary, first: int) -> void:
	last["previous"] = (last.get("current", {}) as Dictionary).duplicate()
	last["current"] = {}
	last["second"] = 3 - first


## 1 人ぶんの降り方を選ぶ（heli_drop.md 2.2）。85% は基本の 2 通りのどちらか、15% は特別な 8 種類の 1 つ。
## last は呼ぶ側が持ち続ける辞書（はじめは {}）。中身：
##   "second"：この回に 2 人目に飛ぶ人（1 か 2）。「ためらい」はこの人だけ（無いときはだれも「ためらい」にならない）
##   "current"：この回にもう選んだ降り方 {player: clip}（ここで書き足す）。2 人は別の特別、基本どうしは別の型にする
##   "previous"：前の回の降り方 {player: clip}（start_drop が移す）。前の回に出た特別は避ける
static func choose_jump(rng: RandomNumberGenerator, player: int, last: Dictionary) -> String:
	var current: Dictionary = last.get("current", {})
	var other := String(current.get(3 - player, ""))
	var pick := ""
	if rng.randf() < SPECIAL_CHANCE:
		var pool := _special_pool(player, last, other)
		if not pool.is_empty():
			pick = pool[rng.randi_range(0, pool.size() - 1)]
	if pick.is_empty():
		# 2 人とも基本でも同じ動きに見えないよう、相手が基本なら別の型（踏み切る足と腕の広げ方が違う。heli_drop.md 2.1）
		var basic := BASIC_JUMPS.find(other)
		pick = BASIC_JUMPS[1 - basic] if basic >= 0 else BASIC_JUMPS[rng.randi_range(0, BASIC_JUMPS.size() - 1)]
	current[player] = pick
	last["current"] = current
	return pick


## 2 人ぶんを一度に選ぶ（start_drop と choose_jump を順に呼ぶ）。返り値 {1: clip, 2: clip}。
static func choose_pair(rng: RandomNumberGenerator, last: Dictionary, first: int) -> Dictionary:
	start_drop(last, first)
	var out := {}
	out[first] = choose_jump(rng, first, last)
	out[3 - first] = choose_jump(rng, 3 - first, last)
	return out


static func _special_pool(player: int, last: Dictionary, other: String) -> Array[String]:
	var previous: Dictionary = last.get("previous", {})
	var pool: Array[String] = []
	for clip: String in SPECIAL_JUMPS:
		if clip == other:
			continue
		if previous.values().has(clip):
			continue
		if clip == HESITATE and int(last.get("second", 0)) != player:
			continue
		pool.append(clip)
	return pool


# ------------------------------------------------------------------ クリップの情報

## クリップの表（drop_moves.json）。キー：
##   length（秒）・loop・kind（bench / ramp / jump / box / land）
##   leave（端を離れる時刻。無いと -1）・settle（腹ばいに落ち着く時刻。これより後は SD_Box_Loop の (time - settle) と同じ姿）
##   land（着地の時刻）・contact（足が床に着いている区間 [[t0, t1], ...]）
##   edge（初めから端までの前への距離 m。飛ぶクリップは端の edge m 手前から始める）・speed（ループの前への速さ m/s）
##   root（根の動き。fps ごとの [x, y, z]）・drop（着地のクリップの落ちる高さ m）・bench_height（座るクリップの座面の高さ m）
static func clip_info(clip: String) -> Dictionary:
	_load_info()
	var clips: Dictionary = _info.get("clips", {})
	var raw: Dictionary = clips.get(clip, {})
	var out := {
		"name": clip, "length": 0.0, "loop": false, "kind": "", "leave": -1.0, "settle": -1.0, "land": -1.0,
		"contact": [], "edge": 0.0, "speed": 0.0, "root": [], "fps": float(_info.get("fps", 30.0)),
	}
	for key: String in raw:
		out[key] = raw[key]
	out["found"] = not raw.is_empty()
	return out


static func has_assets() -> bool:
	_load_info()
	return not (_info.get("clips", {}) as Dictionary).is_empty() and ResourceLoader.exists(GLB_PATH)


## 端を離れてから腹ばいに落ち着くまでの秒（飛ぶクリップだけ。無いと -1）。
static func settle_delay(clip: String) -> float:
	var info := clip_info(clip)
	if float(info.settle) < 0.0 or float(info.leave) < 0.0:
		return -1.0
	return float(info.settle) - float(info.leave)


## クリップの初めの足もとから見た根の位置（クリップの座標）。ループは 1 周ごとの進みを足していく。
static func root_offset(clip: String, time: float) -> Vector3:
	var info := clip_info(clip)
	var root: Array = info.root
	if root.is_empty():
		return Vector3.ZERO
	var length := maxf(float(info.length), 0.001)
	var base := Vector3.ZERO
	var t := time
	if bool(info.loop):
		var cycles := floorf(time / length)
		base = (_vec(root[root.size() - 1]) - _vec(root[0])) * cycles
		t = time - cycles * length
	var f := clampf(t, 0.0, length) * float(info.fps)
	var i := clampi(int(floorf(f)), 0, root.size() - 1)
	var j := mini(i + 1, root.size() - 1)
	return base + _vec(root[i]).lerp(_vec(root[j]), clampf(f - float(i), 0.0, 1.0))


## その時刻に足が床に着いているか（contact の区間）。
static func is_grounded(clip: String, time: float) -> bool:
	var info := clip_info(clip)
	var t := fposmod(time, maxf(float(info.length), 0.001)) if bool(info.loop) else time
	for span: Array in info.contact:
		if t >= float(span[0]) - 0.0001 and t <= float(span[1]) + 0.0001:
			return true
	return false


# ------------------------------------------------------------------ 当てる

## 本物のアバターに当てる（AnimationRig.SLOT_DROP。StagingPuppet.pose と同じ道）。time は秒（ループは回し、ほかは端で止める）。
## スロットが読めていないとき（素材が無い・古いリグ）は pose_doll と同じやり方で部位へ直接当てる。
static func pose_puppet(puppet: StagingPuppet, clip: String, time: float) -> bool:
	if puppet == null or not puppet.is_ready():
		return false
	var length := puppet.clip_length(clip, AnimationRig.SLOT_DROP)
	if length > 0.0:
		var ratio := _ratio(clip, time, length)
		if puppet.pose(clip, ratio, AnimationRig.SLOT_DROP):
			return true
	return pose_doll(puppet.parts(), clip, time)


## 人形（EmoteBlockmanPreview.build_player_skeleton の部位）に当てる。部位の親（根）が回っていても、根から見た姿で当てる。
## 腰（pelvis）は根から見て (0, BASE_Y + 腰の高さ, 0) に置く。置き場所は呼ぶ側か place で決める。
static func pose_doll(parts: Dictionary, clip: String, time: float) -> bool:
	var pose := sample(clip, time)
	if pose.is_empty():
		return false
	apply_pose(parts, pose)
	return true


## 空中の腹ばいに、動く向きの傾きを混ぜて当てる（W4 用）。move は押している向き（x＝右、y＝前。長さ 0〜1）。
## 右・前・左・後ろの傾きを、腹ばいからの差として足し合わせる（斜めは 2 つが混ざる）。
static func pose_box(parts: Dictionary, move: Vector2, time: float) -> bool:
	var base := sample(BOX_LOOP, time)
	if base.is_empty():
		return false
	var weights := {
		BOX_LEAN_RIGHT: maxf(move.x, 0.0), BOX_LEAN_LEFT: maxf(-move.x, 0.0),
		BOX_LEAN_FORWARD: maxf(move.y, 0.0), BOX_LEAN_BACK: maxf(-move.y, 0.0),
	}
	var mixed := base
	for clip: String in weights:
		var w := clampf(float(weights[clip]), 0.0, 1.0)
		if w <= 0.001:
			continue
		var lean := sample(clip, time)
		if not lean.is_empty():
			mixed = add_pose(mixed, base, lean, w)
	apply_pose(parts, mixed)
	return true


## 2 つのクリップを w でまぜて当てる（w = 0 で a、1 で b）。
static func pose_doll_blend(parts: Dictionary, clip_a: String, time_a: float, clip_b: String, time_b: float, w: float) -> bool:
	var a := sample(clip_a, time_a)
	var b := sample(clip_b, time_b)
	if a.is_empty() or b.is_empty():
		return pose_doll(parts, clip_b if a.is_empty() else clip_a, time_b if a.is_empty() else time_a)
	apply_pose(parts, mix_pose(a, b, w))
	return true


## 姿を当てたあと、腰をワールドに置く。frame はクリップの原点（初めの足もと）の置き場所（basis の +Z が前、+Y が床の上）。
## 毎フレーム「当てる → place」の順に呼ぶ（腰の高さは当てた直後の pelvis から読む）。根の回りは frame に置きかわる。
## 足が床に着いている間（contact）は足の裏を床に合わせ（StagingPuppet.stand_at と同じ）、離れている間はその差を保つ
## （人形と UAL の脚の長さの差。離れた瞬間に跳ねないように）。
static func place(parts: Dictionary, clip: String, time: float, frame: Transform3D) -> void:
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null or not pelvis.is_inside_tree():
		return
	var basis := frame.basis.orthonormalized()
	var up := basis.y
	var hips := pelvis.position.y - BASE_Y
	var foot := frame * root_offset(clip, time)
	pelvis.global_transform = Transform3D(basis * pelvis.basis, foot + up * hips)
	var fix := float(pelvis.get_meta(FOOT_FIX_META, 0.0))
	if is_grounded(clip, time):
		var lowest := _lowest_along(parts, up)
		if is_finite(lowest):
			fix = foot.dot(up) + FOOT_CLEARANCE - lowest
			pelvis.global_position += up * fix
			pelvis.set_meta(FOOT_FIX_META, fix)
			return
	pelvis.global_position += up * fix


## アバターに当ててワールドに置く（pose_puppet と place）。
static func place_puppet(puppet: StagingPuppet, clip: String, time: float, frame: Transform3D) -> bool:
	if not pose_puppet(puppet, clip, time):
		return false
	place(puppet.parts(), clip, time, frame)
	return true


## 人形に当ててワールドに置く（pose_doll と place）。
static func place_doll(parts: Dictionary, clip: String, time: float, frame: Transform3D) -> bool:
	if not pose_doll(parts, clip, time):
		return false
	place(parts, clip, time, frame)
	return true


# ------------------------------------------------------------------ 姿（骨ごとの親から見た姿）

## その時刻の姿：骨の番号ごとの親から見た Transform3D（休みの姿のうえにクリップを当てたもの）。素材が無いと []。
static func sample(clip: String, time: float) -> Array[Transform3D]:
	_load_rig()
	var anim := _anims.get(clip) as Animation
	if anim == null:
		return []
	var t := _clip_time(clip, time, anim.length)
	var tracks: Dictionary = _tracks[clip]
	var out: Array[Transform3D] = []
	out.resize(_bone_names.size())
	for i in range(_bone_names.size()):
		var rest := _bone_rest[i]
		var pos := rest.origin
		var rot := rest.basis.get_rotation_quaternion()
		var entry: Array = tracks.get(_bone_names[i], [-1, -1])
		if int(entry[0]) >= 0:
			pos = anim.position_track_interpolate(int(entry[0]), t)
		if int(entry[1]) >= 0:
			rot = anim.rotation_track_interpolate(int(entry[1]), t)
		out[i] = Transform3D(Basis(rot.normalized()), pos)
	return out


static func mix_pose(a: Array[Transform3D], b: Array[Transform3D], w: float) -> Array[Transform3D]:
	var k := clampf(w, 0.0, 1.0)
	var out: Array[Transform3D] = []
	out.resize(a.size())
	for i in range(a.size()):
		var qa := a[i].basis.get_rotation_quaternion()
		var qb := b[i].basis.get_rotation_quaternion()
		out[i] = Transform3D(Basis(qa.slerp(qb, k)), a[i].origin.lerp(b[i].origin, k))
	return out


## pose に (target − base) を w だけ足す（傾きを腹ばいからの差として重ねる）。
static func add_pose(pose: Array[Transform3D], base: Array[Transform3D], target: Array[Transform3D], w: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(pose.size())
	for i in range(pose.size()):
		var qb := base[i].basis.get_rotation_quaternion()
		var delta := qb.inverse() * target[i].basis.get_rotation_quaternion()
		var q := pose[i].basis.get_rotation_quaternion() * Quaternion.IDENTITY.slerp(delta, w)
		out[i] = Transform3D(Basis(q.normalized()), pose[i].origin + (target[i].origin - base[i].origin) * w)
	return out


## 骨の空間（Skeleton3D のグローバル）での姿 {骨の名前: Transform3D}。
static func globals(pose: Array[Transform3D]) -> Dictionary:
	var world: Array[Transform3D] = []
	world.resize(pose.size())
	var done: Array[bool] = []
	done.resize(pose.size())
	var out := {}
	for i in range(pose.size()):
		_global_of(i, pose, world, done)
		out[_bone_names[i]] = world[i]
	return out


## 姿を人形の部位へ当てる（PlayerController._apply_skeleton_pose と同じ当て方。左右は鏡、根の回りは保つ）。
static func apply_pose(parts: Dictionary, pose: Array[Transform3D]) -> void:
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null or pose.is_empty():
		return
	var world := globals(pose)
	var root_basis := Basis.IDENTITY
	var parent := pelvis.get_parent() as Node3D
	if parent != null and parent.is_inside_tree():
		root_basis = parent.global_basis.orthonormalized()
	var hips: Transform3D = world.get(HIPS_BONE, Transform3D.IDENTITY)
	pelvis.position = Vector3(0.0, BASE_Y + hips.origin.y, 0.0)
	pelvis.quaternion = Quaternion(MIRROR * hips.basis.orthonormalized() * MIRROR)
	for row: Array in PART_BONES:
		var node := parts.get(row[0]) as Node3D
		if node == null or not world.has(row[1]) or not node.is_inside_tree():
			continue
		var b := MIRROR * (world[row[1]] as Transform3D).basis.orthonormalized() * MIRROR
		if bool(row[2]):
			b = b * Basis(Vector3.RIGHT, PI)
		node.global_basis = root_basis * b


# ------------------------------------------------------------------ 中身

static func _ratio(clip: String, time: float, length: float) -> float:
	return _clip_time(clip, time, length) / maxf(length, 0.001)


## ループは回し、ほかは端で止める（端そのものは避ける。ループの設定のクリップは端で初めへ戻るため）。
static func _clip_time(clip: String, time: float, length: float) -> float:
	if length <= 0.0:
		return 0.0
	var info := clip_info(clip)
	var loop := bool(info.loop) if bool(info.found) else clip.ends_with("_Loop")
	if loop:
		return fposmod(time, length)
	return clampf(time, 0.0, maxf(length - 0.0005, 0.0))


static func _global_of(i: int, pose: Array[Transform3D], world: Array[Transform3D], done: Array[bool]) -> Transform3D:
	if done[i]:
		return world[i]
	var p := _bone_parent[i]
	world[i] = (_global_of(p, pose, world, done) * pose[i]) if p >= 0 else pose[i]
	done[i] = true
	return world[i]


static func _lowest_along(parts: Dictionary, up: Vector3) -> float:
	var lowest := INF
	for key: String in FOOT_MESH_KEYS:
		var mesh := parts.get(key) as MeshInstance3D
		if mesh == null or not is_instance_valid(mesh) or not mesh.is_inside_tree():
			continue
		var aabb := mesh.get_aabb()
		var xf := mesh.global_transform
		for c in range(8):
			lowest = minf(lowest, (xf * aabb.get_endpoint(c)).dot(up))
	return lowest


static func _vec(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _load_info() -> void:
	if _info_loaded:
		return
	_info_loaded = true
	if not FileAccess.file_exists(INFO_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INFO_PATH))
	if parsed is Dictionary:
		_info = parsed


## 人形用に glb を 1 度だけ開き、クリップと骨の休みの姿を取り出す（シーンは捨てる。AnimationPlayer は使わない）。
static func _load_rig() -> void:
	if _rig_loaded:
		return
	_rig_loaded = true
	if not ResourceLoader.exists(GLB_PATH):
		return
	var scene := load(GLB_PATH) as PackedScene
	if scene == null:
		return
	var node := scene.instantiate()
	var skeleton: Skeleton3D = null
	for child in node.find_children("*", "Skeleton3D", true, false):
		skeleton = child as Skeleton3D
		break
	var ap: AnimationPlayer = null
	for child in node.find_children("*", "AnimationPlayer", true, false):
		ap = child as AnimationPlayer
		break
	if skeleton != null and ap != null:
		for i in range(skeleton.get_bone_count()):
			_bone_names.append(skeleton.get_bone_name(i))
			_bone_parent.append(skeleton.get_bone_parent(i))
			_bone_rest.append(skeleton.get_bone_rest(i))
		for lib_name: StringName in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lib_name)
			for anim_name: StringName in lib.get_animation_list():
				var anim := lib.get_animation(anim_name)
				var tracks := {}
				for t in range(anim.get_track_count()):
					var bone := String(anim.track_get_path(t).get_concatenated_subnames())
					if bone.is_empty():
						continue
					var entry: Array = tracks.get(bone, [-1, -1])
					match anim.track_get_type(t):
						Animation.TYPE_POSITION_3D:
							entry[0] = t
						Animation.TYPE_ROTATION_3D:
							entry[1] = t
					tracks[bone] = entry
				var clip := String(anim_name)
				_anims[clip] = anim
				_tracks[clip] = tracks
				# 読み込みで "_Loop" が外れても、外れなくても同じ名前で引ける
				var alias := clip.trim_suffix("_Loop") if clip.ends_with("_Loop") else clip + "_Loop"
				if not _anims.has(alias):
					_anims[alias] = anim
					_tracks[alias] = tracks
	node.free()
