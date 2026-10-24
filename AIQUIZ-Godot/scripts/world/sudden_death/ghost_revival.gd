class_name GhostRevival
extends Node3D

## サドンデスへ行くときの幽霊の復活（docs/sudden_death_v2/ghost_revive.md）。1 人ぶん。
## 台座の上の幽霊（本物のアバターに魂の見た目をかけたもの）が宙へ浮いて体を呼ぶと、体の部位が画面の外から 1 つずつ
## 渦を描いて飛んできてはまり、はまった所から体に戻る。全部そろうと身を丸めてため、光を放って弾け、ヒーロー着地で
## 台に降りて立ち上がる。
## 持つのは見た目（アバターの姿・部位の飛行・光・音）だけ。カメラと HUD は監督（HeliSuddenDeathDirector）が、
## take_beats() の拍（snap・burst・land）を見て決める。時計は監督の実時間の時計（advance の delta）。

const FX_SHADER := preload("res://assets/ghost_rider/ghost_fx_additive.gdshader")
const SOLID_SHADER := preload("res://assets/ghost_rider/ghost_rider_solid.gdshader")

# ------------------------------------------------------------------ 時刻（この人の始まりからの秒）
## 浮き上がる（台から腰が FLOAT_HEIGHT 上がるまで。少し行きすぎて戻る）。
## 2026-10-21、ユーザーの指示「もっと早く」で全体を約 5.2 秒から約 3.2 秒に詰めた。
const RISE_TIME := 0.5
const FLOAT_HEIGHT := 0.9
## 体を呼ぶ光（殻と輪）。音 ghost_awaken は吸い込みのぶん 0.16 秒先に鳴らす。
const CALL_AT := 0.2
const CALL_SOUND_LEAD := 0.16
## 部位を引き寄せる風の音（ghost_revive_gather。弾ける瞬間に吸い込みが終わるように作ってある）。
const GATHER_SOUND_AT := 0.25
## 全部そろって身を丸める → 弾ける → 落ちる → 着地。
const CURL_AT := 1.5
const BURST_AT := 1.68
const BURST_HOLD := 0.06
const DROP_TIME := 0.24
const LAND_AT := BURST_AT + BURST_HOLD + DROP_TIME
## 着地からはヒーロー着地（drop_moves の SD_Land_Hero。着地 1.5 秒）を速めて最後まで → 待機の姿へ。
const LAND_CLIP := "SD_Land_Hero"
const LAND_CLIP_FALL := 1.3
const LAND_CLIP_LAND := 1.5
const LAND_CLIP_END := 3.12
const LAND_RATE := 1.75
const SETTLE_TIME := 0.3
const STAND_AT := LAND_AT + (LAND_CLIP_END - LAND_CLIP_LAND) / LAND_RATE
const LENGTH := STAND_AT + SETTLE_TIME
const IDLE_CLIP := "Idle_Loop"
## 台の上に立つ人の腰の高さ（足の裏から。監督・水上機の乗り込みと同じ値）。
const HIPS := 0.95

## 部位：付け根の関節・中身（そのキーの部品と、その下のメッシュ）・はまる時刻・飛ぶ秒・やって来る向き（体から見て。
## +X は人形の r_ の側、+Y が上、+Z が胸の向き）。脚から順に上へ組み上がり、帽子が最後。
const PIECES := [
	{"name": "l_shin", "anchor": "l_knee", "roots": ["l_calf", "l_ankle"], "arrive": 0.58, "fly": 0.56, "from": Vector3(-0.7, -1.0, 0.45)},
	{"name": "r_shin", "anchor": "r_knee", "roots": ["r_calf", "r_ankle"], "arrive": 0.66, "fly": 0.56, "from": Vector3(0.7, -1.0, 0.4)},
	{"name": "l_thigh", "anchor": "l_hip", "roots": ["l_thigh"], "arrive": 0.74, "fly": 0.55, "from": Vector3(-1.0, -0.35, 0.3)},
	{"name": "r_thigh", "anchor": "r_hip", "roots": ["r_thigh"], "arrive": 0.82, "fly": 0.54, "from": Vector3(1.0, -0.3, 0.35)},
	{"name": "waist", "anchor": "pelvis", "roots": ["lower_torso"], "arrive": 0.9, "fly": 0.54, "from": Vector3(-0.35, -0.25, 1.0)},
	{"name": "chest", "anchor": "spine", "roots": ["upper_torso"], "arrive": 0.98, "fly": 0.53, "from": Vector3(0.4, 0.45, 1.0)},
	{"name": "l_upper_arm", "anchor": "l_shoulder", "roots": ["l_upp_arm"], "arrive": 1.06, "fly": 0.52, "from": Vector3(-1.0, 0.55, 0.1)},
	{"name": "r_upper_arm", "anchor": "r_shoulder", "roots": ["r_upp_arm"], "arrive": 1.13, "fly": 0.51, "from": Vector3(1.0, 0.6, 0.05)},
	{"name": "l_forearm", "anchor": "l_elbow", "roots": ["l_low_arm", "l_wrist"], "arrive": 1.2, "fly": 0.5, "from": Vector3(-1.0, 0.1, 0.4)},
	{"name": "r_forearm", "anchor": "r_elbow", "roots": ["r_low_arm", "r_wrist"], "arrive": 1.27, "fly": 0.5, "from": Vector3(1.0, 0.15, 0.45)},
	{"name": "head", "anchor": "head_pivot", "roots": ["head"], "arrive": 1.35, "fly": 0.52, "from": Vector3(0.15, 1.0, 0.35)},
	{"name": "hat", "anchor": "hat_mount", "roots": ["hat_mount"], "arrive": 1.44, "fly": 0.54, "from": Vector3(-0.25, 1.0, -0.2)},
]
## 飛ぶ道の速さ：初めは速く、はまる手前（道の HANG_SHARE）でほとんど止まってから、最後は吸い込まれるようにはまる。
const HANG := 0.84
const HANG_SHARE := 0.9
## はまる音の高さ（長音階で上がっていく。2 人とも幽霊なら 2 人目は少し遅れて追いかける）。
const SNAP_STEPS := [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19]
const SNAP_PITCH := 0.72

# ------------------------------------------------------------------ 姿（待機 Idle_Loop に、体の向きの軸で足す角度。度）
## 浮いて体を呼ぶ：胸を張って顔を上げ、腕を横へ大きく開き、脚は少し開いて下へ垂らす。
const POSE_FLOAT := [
	["spine", "x", -14.0], ["head_pivot", "x", -16.0],
	["l_shoulder", "z", -74.0], ["r_shoulder", "z", 74.0], ["l_shoulder", "x", -16.0], ["r_shoulder", "x", -16.0],
	["l_elbow", "x", -22.0], ["r_elbow", "x", -22.0],
	["l_hip", "z", -7.0], ["r_hip", "z", 7.0], ["l_hip", "x", -6.0], ["r_hip", "x", 4.0],
	["l_knee", "x", 24.0], ["r_knee", "x", 15.0], ["l_ankle", "x", 26.0], ["r_ankle", "x", 20.0],
]
## ためる：身を丸め、腕を胸の前で交差させ、ひざを抱え込む。
const POSE_CURL := [
	["spine", "x", 30.0], ["head_pivot", "x", 22.0],
	["l_shoulder", "z", -12.0], ["r_shoulder", "z", 12.0], ["l_shoulder", "x", -78.0], ["r_shoulder", "x", -78.0],
	["l_shoulder", "y", 34.0], ["r_shoulder", "y", -34.0],
	["l_elbow", "x", -104.0], ["r_elbow", "x", -104.0],
	["l_hip", "x", -64.0], ["r_hip", "x", -58.0], ["l_knee", "x", 96.0], ["r_knee", "x", 92.0],
]
## 弾ける：大の字（腕を斜め上へ、脚を開いて、胸を反らす）。
const POSE_BURST := [
	["spine", "x", -20.0], ["head_pivot", "x", -22.0],
	["l_shoulder", "z", -128.0], ["r_shoulder", "z", 128.0], ["l_shoulder", "x", 8.0], ["r_shoulder", "x", 8.0],
	["l_elbow", "x", -6.0], ["r_elbow", "x", -6.0],
	["l_hip", "z", -20.0], ["r_hip", "z", 20.0], ["l_knee", "x", 10.0], ["r_knee", "x", 10.0],
]
## 落ちる間だけヒーロー着地の落ちる姿に足す：ひざを曲げて着地に備え、腕を少し上げて構える。
const POSE_DROP := [
	["spine", "x", 10.0], ["head_pivot", "x", -8.0],
	["l_shoulder", "z", -26.0], ["r_shoulder", "z", 26.0], ["l_elbow", "x", -28.0], ["r_elbow", "x", -18.0],
	["l_hip", "x", -34.0], ["r_hip", "x", -14.0], ["l_knee", "x", 52.0], ["r_knee", "x", 30.0],
]
const AXES := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}
const FRONT_YAW := PI

var player := 1
var lag := 0.0

var _controller: PlayerController = null
var _puppet: StagingPuppet = null
## 台に立ったときの腰の位置（監督が決めた台の上。足の裏は HIPS 下）。
var _pad := Vector3.ZERO
var _shot := Transform3D.IDENTITY
var _shot_fov := 42.0
var _camera: Camera3D = null
var _color := Color(1.0, 0.6, 0.24)
var _clock := 0.0
var _segment := ""
var _start_yaw := FRONT_YAW
var _done := false
var _burst := false
var _beats: Array[StringName] = []
var _cues := {}
var _rng := RandomNumberGenerator.new()
## {"name", "anchor": Node3D, "meshes": Array[MeshInstance3D], "copies": Array[MeshInstance3D], "trail", "arrive", "launch",
##  "from": Vector3, "start", "curl": Vector3, "axis", "spin", "state" ("wait" / "fly" / "in"), "material"}
var _pieces: Array[Dictionary] = []
## 体がはまった衝撃のばね（腰をずらす。ワールド）。
var _jolt := Vector3.ZERO
var _jolt_velocity := Vector3.ZERO
var _soul_pulse := 0.0
var _skin_flash := 0.0
var _light: OmniLight3D = null
var _light_pulse := 0.0
var _effects: Array[Dictionary] = []
var _sparks: FxPool = null
var _motes: FxPool = null
var _vortex: MultiMeshInstance3D = null
var _vortex_seeds: Array[Vector4] = []
var _vortex_blast := -1.0


## 光の粒の入れ物（火花＝速さの向きに伸びる箱、粒＝丸い光）。位置と速さを CPU で進め、MultiMesh 1 つで描く。
class FxPool:
	extends RefCounted
	var node: MultiMeshInstance3D
	var mm: MultiMesh
	var stretch := false
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var age := PackedFloat32Array()
	var life := PackedFloat32Array()
	var size := PackedFloat32Array()
	var drag := PackedFloat32Array()
	var lift := PackedFloat32Array()
	var color := PackedColorArray()
	var _next := 0

	func _init(count: int, mesh: Mesh, material: Material, stretched: bool) -> void:
		stretch = stretched
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = maxi(count, 1)
		node = MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.top_level = true
		node.custom_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
		for i in range(mm.instance_count):
			pos.append(Vector3.ZERO)
			vel.append(Vector3.ZERO)
			age.append(1.0)
			life.append(0.0)
			size.append(0.0)
			drag.append(0.0)
			lift.append(0.0)
			color.append(Color(0, 0, 0, 0))
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -1000, 0)))
			mm.set_instance_color(i, Color(0, 0, 0, 0))

	func emit(at: Vector3, velocity: Vector3, lifetime: float, scale: float, tint: Color, damping := 2.0, buoyancy := 0.0) -> void:
		var i := _next
		_next = (_next + 1) % mm.instance_count
		pos[i] = at
		vel[i] = velocity
		age[i] = 0.0
		life[i] = maxf(lifetime, 0.05)
		size[i] = scale
		drag[i] = damping
		lift[i] = buoyancy
		color[i] = tint

	func step(delta: float, gravity: float) -> void:
		for i in range(mm.instance_count):
			if life[i] <= 0.0:
				continue
			age[i] += delta
			var u := age[i] / life[i]
			if u >= 1.0:
				life[i] = 0.0
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -1000, 0)))
				mm.set_instance_color(i, Color(0, 0, 0, 0))
				continue
			var v := vel[i] * exp(-drag[i] * delta) + Vector3(0.0, (lift[i] - gravity) * delta, 0.0)
			vel[i] = v
			pos[i] += v * delta
			var tint := color[i]
			tint.a *= (1.0 - u) * (1.0 - u) * minf(1.0, age[i] / 0.04)
			mm.set_instance_color(i, tint)
			var s := size[i] * (1.0 - 0.45 * u)
			if stretch:
				var speed := v.length()
				var y := v / speed if speed > 0.001 else Vector3.UP
				var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
				var z := x.cross(y)
				var basis := Basis(x * s, y * s * (1.0 + speed * 0.09), z * s)
				mm.set_instance_transform(i, Transform3D(basis, pos[i]))
			else:
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), pos[i]))


## camera_shot は部位が飛び立つときのカメラ（そこから見て画面の外から飛んでくる）。camera は今のカメラ（まだ寄っている
## 途中でも、飛び立つ所が映らないように確かめる）。pad は台に立ったときの腰の位置。
func setup(controller: PlayerController, puppet: StagingPuppet, player_index: int, pad: Vector3, start_lag: float,
		camera_shot: Transform3D, camera_fov: float, camera: Camera3D) -> void:
	_controller = controller
	_puppet = puppet
	player = player_index
	_pad = pad
	lag = maxf(start_lag, 0.0)
	_shot = camera_shot
	_shot_fov = camera_fov
	_camera = camera
	_color = PlayerController.GHOST_RIDER_RIM_P1 if player == 1 else PlayerController.GHOST_RIDER_RIM_P2
	_rng.seed = 7301 + player * 97
	name = "GhostRevivalP%d" % player
	var pelvis := _puppet.parts().get("pelvis") as Node3D
	if pelvis != null:
		var facing := pelvis.global_basis.z
		if Vector2(facing.x, facing.z).length() > 0.05:
			_start_yaw = atan2(facing.x, facing.z)
		# 決着演出の人形と同じ魂の姿（PlayerController.apply_ghost_soul_look）から始める。
		PlayerController.apply_ghost_soul_look(pelvis, player)
	_build_fx()
	_build_pieces()
	_puppet.begin_blend(0.6)


func is_done() -> bool:
	return _done


func has_burst() -> bool:
	return _burst


## 監督が読む拍（&"call"・&"snap"・&"burst"・&"land"・&"stand"）。読んだら消える。
func take_beats() -> Array[StringName]:
	var out := _beats.duplicate()
	_beats.clear()
	return out


func local_time() -> float:
	return _clock - lag


## 体の真ん中（カメラの狙い）。
func body_center() -> Vector3:
	return _puppet.center() if _puppet != null and _puppet.is_ready() else _pad


func advance(delta: float) -> void:
	if _done or _puppet == null or not _puppet.is_ready():
		return
	_clock += maxf(delta, 0.0)
	var t := _clock - lag
	_pose_body(t, delta)
	_update_pieces(t, delta)
	_update_soul(t, delta)
	_update_effects(delta)
	_sparks.step(delta, 7.5)
	_motes.step(delta, 0.0)
	_update_vortex(t)
	if t >= LENGTH:
		_done = true
		_beats.append(&"stand")


## 演出を飛ばす・やめるとき：体を全部戻して終わりにする（姿は呼ぶ側が決める）。
func finish_now() -> void:
	for piece: Dictionary in _pieces:
		_seat_piece(piece, false)
	_make_solid()
	_set_skin_flash(0.0)
	_done = true


## 体を戻し、光を全部消して自分を消す。
func teardown() -> void:
	finish_now()
	queue_free()


func get_debug_snapshot() -> Dictionary:
	var states := {}
	var seen: Array[String] = []
	for piece: Dictionary in _pieces:
		states[piece.name] = str(piece.state)
		if bool(piece.get("start_seen", false)):
			seen.append(str(piece.name))
	return {"t": snappedf(local_time(), 0.01), "segment": _segment, "pieces": states, "burst": _burst, "done": _done,
		"ghost_meshes": _ghost_mesh_count(), "starts_on_screen": seen}


# ------------------------------------------------------------------ 姿

func _pose_body(t: float, delta: float) -> void:
	var segment := "float"
	if t >= STAND_AT:
		segment = "settle"
	elif t >= LAND_AT:
		segment = "land"
	elif t >= BURST_AT + BURST_HOLD:
		segment = "drop"
	elif t >= BURST_AT:
		segment = "burst"
	elif t >= CURL_AT:
		segment = "curl"
	if segment != _segment:
		# 区切りごとに今の姿から慣性でつなぐ（StagingPuppet.begin_blend）。着地は落ちてきた勢いのまま切り替える。
		var blend := {"curl": 0.12, "burst": 0.05, "drop": 0.12, "land": 0.0, "settle": SETTLE_TIME}
		if _segment != "" and float(blend.get(segment, 0.0)) > 0.0:
			_puppet.begin_blend(float(blend[segment]))
		_segment = segment
	var pad_y := _pad.y - HIPS
	var yaw := lerp_angle(_start_yaw, FRONT_YAW, smoothstep(0.0, 0.6, t))
	var body := Basis(Vector3.UP, yaw)
	match segment:
		"float", "curl", "burst":
			_idle(t)
			var lift := FLOAT_HEIGHT * _ease_out_back(clampf(t / RISE_TIME, 0.0, 1.0), 1.25)
			lift += 0.05 * sin(TAU * t / 1.2) * smoothstep(0.4, 0.8, t)
			var rows: Array = []
			var float_w := smoothstep(0.0, 0.4, t)
			_append_rows(rows, POSE_FLOAT, float_w)
			_append_rows(rows, [["l_shoulder", "z", sin(t * TAU / 1.3) * 5.0], ["r_shoulder", "z", -sin(t * TAU / 1.3 + 0.9) * 5.0],
				["l_knee", "x", sin(t * TAU / 1.1) * 6.0], ["r_knee", "x", sin(t * TAU / 1.1 + 1.2) * 6.0],
				["spine", "z", sin(t * TAU / 2.1) * 2.5]], float_w)
			if segment == "curl":
				var k := smoothstep(CURL_AT, CURL_AT + 0.1, t)
				rows.clear()
				_append_rows(rows, POSE_FLOAT, 1.0 - k)
				_append_rows(rows, POSE_CURL, k)
				lift += 0.14 * k
				# 力をためて小刻みに震える
				var shiver := 3.5 * k * smoothstep(CURL_AT, BURST_AT, t)
				_append_rows(rows, [["spine", "z", sin(t * 97.0) * shiver], ["spine", "x", sin(t * 83.0 + 1.0) * shiver]], 1.0)
			elif segment == "burst":
				rows.clear()
				_append_rows(rows, POSE_BURST, 1.0)
				lift += 0.2
			# はまった部位の衝撃で胸が揺れる
			_append_rows(rows, [["spine", "z", -_jolt.dot(body.x) * 260.0], ["spine", "x", _jolt.dot(body.z) * 260.0]], 1.0)
			_puppet.stand_at(_pad, yaw, pad_y + lift)
			_apply_rows(rows, body)
			var pelvis := _puppet.parts().get("pelvis") as Node3D
			if pelvis != null:
				pelvis.global_position += _jolt
		"drop":
			var u := clampf((t - BURST_AT - BURST_HOLD) / DROP_TIME, 0.0, 1.0)
			DropMotion.pose_puppet(_puppet, LAND_CLIP, lerpf(LAND_CLIP_FALL, LAND_CLIP_LAND - 0.02, u))
			var height := (FLOAT_HEIGHT + 0.2) * (1.0 - u * u)
			_puppet.stand_at(_pad, FRONT_YAW, pad_y + height)
			var rows: Array = []
			# 着地の瞬間までひざを曲げたまま（着地でクリップのしゃがみに切り替わる）
			_append_rows(rows, POSE_DROP, smoothstep(0.0, 0.35, u))
			_apply_rows(rows, Basis(Vector3.UP, FRONT_YAW))
		"land":
			DropMotion.pose_puppet(_puppet, LAND_CLIP, LAND_CLIP_LAND + (t - LAND_AT) * LAND_RATE)
			_puppet.stand_at(_pad, FRONT_YAW, pad_y)
		"settle":
			_idle(t)
			_puppet.stand_at(_pad, FRONT_YAW, pad_y)
	_puppet.apply_blend(delta)
	# 衝撃のばね（2.4 Hz、すぐ収まる）
	var accel := -_jolt * 230.0 - _jolt_velocity * 19.0
	_jolt_velocity += accel * delta
	_jolt += _jolt_velocity * delta


func _idle(t: float) -> void:
	var length := maxf(_puppet.clip_length(IDLE_CLIP), 0.1)
	_puppet.pose(IDLE_CLIP, fposmod(t / length + 0.31 * float(player), 1.0))


func _append_rows(out: Array, rows: Array, weight: float) -> void:
	if weight <= 0.0001:
		return
	for row: Array in rows:
		out.append([row[0], row[1], float(row[2]) * weight])


## 角度の表を、体の向きの軸でワールドのまま足す（親から順に。子は親についてくる）。
func _apply_rows(rows: Array, body: Basis) -> void:
	var parts := _puppet.parts()
	for row: Array in rows:
		var node := parts.get(row[0]) as Node3D
		var degrees := float(row[2])
		if node == null or absf(degrees) < 0.01:
			continue
		var axis := (body * (AXES[row[1]] as Vector3)).normalized()
		node.global_basis = Basis(axis, deg_to_rad(degrees)) * node.global_basis


static func _ease_out_back(u: float, overshoot: float) -> float:
	var c3 := overshoot + 1.0
	return 1.0 + c3 * pow(u - 1.0, 3.0) + overshoot * pow(u - 1.0, 2.0)


# ------------------------------------------------------------------ 部位

func _build_pieces() -> void:
	var parts := _puppet.parts()
	var pelvis := parts.get("pelvis") as Node3D
	var claimed := {}
	for def: Dictionary in PIECES:
		var anchor := parts.get(def.anchor) as Node3D
		if anchor == null:
			continue
		var meshes: Array[MeshInstance3D] = []
		for key: String in def.roots:
			_collect_meshes(parts.get(key) as Node3D, meshes, claimed, parts.get("hat_mount") as Node3D if def.name == "head" else null)
		if meshes.is_empty():
			continue
		_pieces.append(_make_piece(def, anchor, meshes))
	# どの部位にも入らなかった部品（スキンが足した飾りなど）は胸と一緒に飛んでくる。
	if pelvis != null:
		var extra: Array[MeshInstance3D] = []
		for node: Node in pelvis.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if not claimed.has(mesh) and PlayerController.is_ghost_soul_look(mesh):
				claimed[mesh] = true
				extra.append(mesh)
		for piece: Dictionary in _pieces:
			if piece.name == "chest" and not extra.is_empty():
				for mesh: MeshInstance3D in extra:
					(piece.meshes as Array).append(mesh)
					(piece.copies as Array).append(_make_copy(mesh, piece.material as Material))


func _collect_meshes(root: Node3D, out: Array[MeshInstance3D], claimed: Dictionary, exclude: Node3D) -> void:
	if root == null:
		return
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node: Node in nodes:
		var mesh := node as MeshInstance3D
		if mesh == null or claimed.has(mesh) or mesh.mesh == null:
			continue
		if exclude != null and (exclude == mesh or exclude.is_ancestor_of(mesh)):
			continue
		claimed[mesh] = true
		out.append(mesh)


func _make_piece(def: Dictionary, anchor: Node3D, meshes: Array[MeshInstance3D]) -> Dictionary:
	var albedo := _original_albedo(meshes[0])
	var material := ShaderMaterial.new()
	material.shader = SOLID_SHADER
	material.set_shader_parameter("albedo", albedo)
	material.set_shader_parameter("rim_color", _color)
	material.set_shader_parameter("rim_energy", 2.4)
	material.set_shader_parameter("core_energy", 0.45)
	var copies: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in meshes:
		copies.append(_make_copy(mesh, material))
	var trail := GhostSoulTrail.new()
	trail.name = "Trail_%s" % def.name
	trail.lifetime = 0.34
	trail.head_width = 0.12
	trail.tail_width = 0.012
	add_child(trail)
	trail.set_trail_color(_color)
	trail.color = _color.lerp(Color.WHITE, 0.2)
	var axis := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	if axis.length() < 0.2:
		axis = Vector3(0.3, 1.0, 0.2)
	return {
		"name": def.name, "anchor": anchor, "meshes": meshes, "copies": copies, "trail": trail, "material": material,
		"arrive": float(def.arrive), "launch": float(def.arrive) - float(def.fly), "from": def.from,
		"start": Vector3.ZERO, "curl": Vector3.ZERO, "axis": axis.normalized(),
		"spin": TAU * _rng.randf_range(1.1, 1.9) * (1.0 if _rng.randf() < 0.5 else -1.0),
		"state": "wait", "index": _pieces.size(),
	}


## 飛んでくる部品：元の部品と同じ形で、体の色に縁の光（GOSTRIDER の乗り手と同じシェーダー）。帽子など、元が
## 部品ごとの色（material_override なし）のものは元の見た目のまま飛ばす。
func _make_copy(source: MeshInstance3D, material: Material) -> MeshInstance3D:
	var copy := MeshInstance3D.new()
	copy.name = "Flying_%s" % source.name
	copy.mesh = source.mesh
	var original: Dictionary = source.get_meta(PlayerController.GHOST_ORIGINAL_LOOK_META, {})
	copy.material_override = material if original.get("override") is StandardMaterial3D else original.get("override") as Material
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.top_level = true
	copy.visible = false
	add_child(copy)
	return copy


func _original_albedo(mesh: MeshInstance3D) -> Color:
	var original: Dictionary = mesh.get_meta(PlayerController.GHOST_ORIGINAL_LOOK_META, {})
	var standard := original.get("override") as StandardMaterial3D
	if standard == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		standard = mesh.mesh.surface_get_material(0) as StandardMaterial3D
	var color := standard.albedo_color if standard != null else Color(0.9, 0.9, 0.9)
	color.a = 1.0
	return color


func _update_pieces(t: float, delta: float) -> void:
	var body := Basis(Vector3.UP, FRONT_YAW)
	for piece: Dictionary in _pieces:
		var anchor := piece.anchor as Node3D
		var trail := piece.trail as GhostSoulTrail
		match str(piece.state):
			"wait":
				if t >= float(piece.launch):
					_launch(piece, body)
			"fly":
				if t >= float(piece.arrive):
					_seat_piece(piece, true)
		if str(piece.state) == "fly":
			var u := clampf((t - float(piece.launch)) / maxf(float(piece.arrive) - float(piece.launch), 0.05), 0.0, 1.0)
			var s := _path_share(u)
			var target := anchor.global_transform
			var p0: Vector3 = piece.start
			var p1: Vector3 = piece.curl
			var p2: Vector3 = target.origin + (body * (piece.from as Vector3)).normalized() * 0.85
			var p3 := target.origin
			var a := 1.0 - s
			var at := a * a * a * p0 + 3.0 * a * a * s * p1 + 3.0 * a * s * s * p2 + s * s * s * p3
			var rest := target.basis.get_rotation_quaternion()
			var spin := Quaternion(piece.axis as Vector3, float(piece.spin) * pow(1.0 - s, 1.6))
			var flying := Transform3D(Basis(rest * spin).scaled(target.basis.get_scale()), at)
			var to_anchor := target.affine_inverse()
			var meshes: Array = piece.meshes
			var copies: Array = piece.copies
			for i in range(copies.size()):
				var copy := copies[i] as MeshInstance3D
				copy.global_transform = flying * (to_anchor * (meshes[i] as MeshInstance3D).global_transform)
				copy.visible = true
			# はまる手前で白く熱を帯びる
			(piece.material as ShaderMaterial).set_shader_parameter("flash", smoothstep(0.7, 1.0, u) * 0.75)
			trail.emitting = true
			trail.step(delta, at, 1.0)
		elif trail != null:
			trail.emitting = false
			if not trail.is_idle():
				trail.step(delta, anchor.global_position, 1.0)


## 飛ぶ道のうち進んだ割合（0〜1）。速く飛んできて、はまる手前でほとんど止まり、最後に吸い込まれる。
static func _path_share(u: float) -> float:
	if u < HANG:
		return HANG_SHARE * (1.0 - pow(1.0 - u / HANG, 2.4))
	var v := (u - HANG) / (1.0 - HANG)
	return HANG_SHARE + (1.0 - HANG_SHARE) * v * v


## 飛び立つ：画面の外（飛び立つときのカメラと今のカメラの両方の外）から、やって来る向きの側に。
func _launch(piece: Dictionary, body: Basis) -> void:
	piece.state = "fly"
	var target := (piece.anchor as Node3D).global_position
	var toward := (body * (piece.from as Vector3)).normalized()
	var start := _off_screen_point(target, toward, int(piece.index))
	piece.start = start
	if _camera != null and is_instance_valid(_camera) and _camera.is_inside_tree():
		piece["start_seen"] = _on_screen(_camera.global_transform, _camera.fov, start)
	# 渦を巻くように、まっすぐではなく横へふくらませる（左右交互）
	var line := target - start
	var forward := -_shot.basis.z
	var side := line.cross(forward)
	if side.length() < 0.01:
		side = line.cross(Vector3.UP)
	side = side.normalized() * (1.0 if int(piece.index) % 2 == 0 else -1.0)
	piece.curl = start + line * 0.3 + (side * 0.75 + Vector3.UP * 0.3).normalized() * line.length() * 0.38
	piece["toward"] = toward
	(piece.trail as GhostSoulTrail).clear()


func _off_screen_point(target: Vector3, toward: Vector3, index: int) -> Vector3:
	var local := _shot.affine_inverse() * target
	var dir := _shot.basis.inverse() * toward
	# 画面の横と上から飛んでくる（下の縁の外は床の下になるので使わない）。脚は横の低い所から。
	var screen := Vector2(dir.x, maxf(dir.y, -0.15))
	if absf(screen.x) < 0.3 and screen.y < 0.5:
		screen.x = signf(dir.x) * 0.6 if absf(dir.x) > 0.05 else (0.6 if index % 2 == 0 else -0.6)
	screen = screen.normalized()
	# 胸の向き（カメラの方）から来る部位はレンズの横の近くから、背中の側から来る部位は体より奥から。
	var depth := maxf(-local.z - clampf(dir.z, -1.0, 1.0) * 2.6, 2.0)
	var half_y := tan(deg_to_rad(_shot_fov) * 0.5) * depth
	var half_x := half_y * _aspect()
	var at := Vector2(local.x, local.y) * depth / maxf(-local.z, 0.5)
	var reach := INF
	if absf(screen.x) > 0.001:
		reach = minf(reach, (half_x * signf(screen.x) - at.x) / screen.x)
	if absf(screen.y) > 0.001:
		reach = minf(reach, (half_y * signf(screen.y) - at.y) / screen.y)
	reach = maxf(reach, 0.3) * 1.12 + 0.9 + 0.3 * float(index % 3)
	var point := _shot * Vector3(at.x + screen.x * reach, at.y + screen.y * reach, -depth)
	# 床より上に置いたまま、今のカメラ（決着演出の画）にも映らない所まで横へ離す
	var floor_y := _pad.y - HIPS + 0.45 + 0.25 * float(index % 3)
	var lenses: Array = [[_shot, _shot_fov]]
	if _camera != null and is_instance_valid(_camera) and _camera.is_inside_tree():
		lenses.append([_camera.global_transform, _camera.fov])
	for _i in range(14):
		point.y = maxf(point.y, floor_y)
		var seen := false
		for lens: Array in lenses:
			seen = seen or _on_screen(lens[0] as Transform3D, float(lens[1]), point)
		if not seen:
			break
		var away := point - target
		away.y = maxf(away.y, 0.0)
		point = target + away * 1.25
	return point


func _on_screen(pose: Transform3D, fov: float, point: Vector3) -> bool:
	var local := pose.affine_inverse() * point
	if local.z > -0.2:
		return false
	var half_y := tan(deg_to_rad(fov) * 0.5) * -local.z
	var half_x := half_y * _aspect()
	return absf(local.x) < half_x * 1.1 and absf(local.y) < half_y * 1.1


func _aspect() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 16.0 / 9.0
	var size := viewport.get_visible_rect().size
	return size.x / maxf(size.y, 1.0)


## 部位がはまる：飛んできた部品を消して本物の部品を体に戻し、光と音。fx = false は光も音も出さない（飛ばすとき）。
func _seat_piece(piece: Dictionary, fx: bool) -> void:
	if str(piece.state) == "in":
		return
	var was_flying := str(piece.state) == "fly"
	piece.state = "in"
	for copy: Variant in piece.copies:
		(copy as MeshInstance3D).visible = false
	for mesh: Variant in piece.meshes:
		var soul := (mesh as MeshInstance3D).get_meta(&"ghost_soul_material", null) as ShaderMaterial
		if soul != null:
			soul.set_shader_parameter("flash", 0.0)
		PlayerController.restore_ghost_soul_mesh(mesh as MeshInstance3D)
	if not fx or not was_flying:
		return
	var meshes: Array = piece.meshes
	var center := Vector3.ZERO
	for mesh: Variant in meshes:
		center += (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb().get_center()
	center /= float(maxi(meshes.size(), 1))
	var travel := -(piece.get("toward", Vector3.UP) as Vector3)
	_spawn_glow_shell(meshes)
	_spawn_ring(center, (_shot.origin - center).normalized(), 0.06, 0.62, 0.24, _color.lerp(Color.WHITE, 0.5), 2.6, 0.022)
	for _i in range(GraphicsQuality.particle_amount(12, GameManager.graphics_quality)):
		var dir := (-travel * 0.6 + _random_unit()).normalized()
		_sparks.emit(center, dir * _rng.randf_range(2.2, 5.0), _rng.randf_range(0.22, 0.4), _rng.randf_range(0.7, 1.1),
			_color.lerp(Color.WHITE, _rng.randf_range(0.3, 0.8)), 3.2)
	_jolt_velocity += travel * 0.55
	_soul_pulse = minf(_soul_pulse + 0.45, 0.9)
	_light_pulse = minf(_light_pulse + 1.4, 3.0)
	var step := int(SNAP_STEPS[mini(int(piece.index), SNAP_STEPS.size() - 1)])
	AudioManager.play_sfx(&"ghost_revive_snap", -2.0, SNAP_PITCH * pow(2.0, float(step) / 12.0))
	_beats.append(&"snap")


func _random_unit() -> Vector3:
	var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	return v.normalized() if v.length() > 0.05 else Vector3.UP


# ------------------------------------------------------------------ 魂の光・弾ける・着地

func _update_soul(t: float, delta: float) -> void:
	_soul_pulse = maxf(0.0, _soul_pulse - delta * 2.6)
	_light_pulse = maxf(0.0, _light_pulse - delta * 5.0)
	var gather := smoothstep(CALL_AT, CURL_AT, t)
	if _cue("call_sound", t >= CALL_AT - CALL_SOUND_LEAD):
		AudioManager.play_sfx(&"ghost_awaken", -1.0)
	if _cue("call", t >= CALL_AT):
		_play_call()
	if _cue("gather_sound", t >= GATHER_SOUND_AT):
		AudioManager.play_sfx(&"ghost_revive_gather", -2.0)
	if _cue("burst", t >= BURST_AT):
		_play_burst()
	if _cue("land", t >= LAND_AT):
		_play_land()
	# まだ魂のままの部品：体が戻ってくるほど明るく、はまるたびに光る（白くとばない程度に）
	var curl := smoothstep(CURL_AT, BURST_AT, t)
	var flash := 0.04 + 0.1 * gather + 0.55 * _soul_pulse + 0.35 * curl
	if not _burst:
		for piece: Dictionary in _pieces:
			if str(piece.state) == "in":
				continue
			for mesh: Variant in piece.meshes:
				var soul := (mesh as MeshInstance3D).get_meta(&"ghost_soul_material", null) as ShaderMaterial
				if soul != null:
					soul.set_shader_parameter("flash", clampf(flash, 0.0, 1.0))
	# 体の灯り（プレイヤー色。ためる間に白く強く、弾けた瞬間にいちばん明るい）
	var center := body_center()
	_light.global_position = center + Vector3(0.0, 0.15, 0.0)
	var burst_glow := 0.0
	if t >= BURST_AT:
		burst_glow = 10.0 * exp(-(t - BURST_AT) / 0.16)
	_light.light_color = _color.lerp(Color.WHITE, 0.25 + 0.5 * curl + minf(burst_glow / 10.0, 0.6))
	_light.light_energy = (0.5 + 1.3 * gather) * (1.0 - smoothstep(BURST_AT, BURST_AT + 0.4, t)) + _light_pulse + 2.4 * curl + burst_glow
	_light.omni_range = 4.5 + 4.0 * minf(burst_glow / 10.0, 1.0)
	_light.visible = t >= 0.0 and t < LAND_AT + 0.8
	# 弾けた体の白い光（スキンの発光）が引いていく
	if _skin_flash > 0.0:
		_skin_flash = maxf(0.0, _skin_flash - delta * 3.6)
		_set_skin_flash(_skin_flash)


func _play_call() -> void:
	var center := body_center()
	_spawn_shell(center, 0.25, 1.9, 0.4, _color.lerp(Color.WHITE, 0.45), 1.6, 3.0)
	_spawn_ring(center, (_shot.origin - center).normalized(), 0.3, 2.2, 0.38, _color.lerp(Color.WHITE, 0.3), 2.2, 0.035)
	_spawn_ring(Vector3(_pad.x, _pad.y - HIPS + 0.04, _pad.z), Vector3.UP, 0.4, 2.6, 0.5, _color, 1.8, 0.05)
	for _i in range(GraphicsQuality.particle_amount(30, GameManager.graphics_quality)):
		var dir := (Vector3.UP * 1.2 + _random_unit()).normalized()
		_motes.emit(center + _random_unit() * 0.4, dir * _rng.randf_range(0.8, 2.8), _rng.randf_range(0.6, 1.1),
			_rng.randf_range(0.7, 1.3), _color.lerp(Color.WHITE, _rng.randf_range(0.2, 0.7)), 1.6, 1.2)
	_soul_pulse = 0.8
	_light_pulse = 2.4
	_beats.append(&"call")


func _play_burst() -> void:
	_burst = true
	for piece: Dictionary in _pieces:
		_seat_piece(piece, false)
	_make_solid()
	_skin_flash = 1.6
	_set_skin_flash(_skin_flash)
	var center := body_center()
	_spawn_shell(center, 0.3, 2.8, 0.42, Color(1.0, 0.97, 0.9).lerp(_color, 0.25), 2.0, 2.4)
	_spawn_shell(center, 0.2, 1.3, 0.2, Color.WHITE, 2.4, 1.2)
	_spawn_ring(center, Vector3.UP, 0.4, 4.6, 0.48, _color.lerp(Color.WHITE, 0.35), 2.6, 0.07)
	_spawn_ring(center, (_shot.origin - center).normalized(), 0.3, 3.2, 0.4, Color.WHITE.lerp(_color, 0.3), 2.4, 0.05)
	_spawn_ring(center, (_shot.origin - center).normalized(), 0.2, 2.0, 0.3, _color, 2.0, 0.025, 0.06)
	var quality := GameManager.graphics_quality
	for _i in range(GraphicsQuality.particle_amount(56, quality)):
		var dir := _random_unit()
		_sparks.emit(center + dir * 0.2, dir * _rng.randf_range(5.0, 11.0), _rng.randf_range(0.35, 0.7), _rng.randf_range(0.9, 1.5),
			_color.lerp(Color.WHITE, _rng.randf_range(0.2, 0.9)), 2.6)
	for _i in range(GraphicsQuality.particle_amount(40, quality)):
		var dir := (_random_unit() + Vector3.UP * 0.4).normalized()
		_motes.emit(center + dir * 0.3, dir * _rng.randf_range(1.5, 4.5), _rng.randf_range(0.7, 1.3), _rng.randf_range(0.8, 1.6),
			_color.lerp(Color.WHITE, _rng.randf_range(0.3, 0.8)), 2.2, 1.0)
	_vortex_blast = 0.0
	AudioManager.play_sfx(&"ghost_revive_burst", 0.0)
	AudioManager.play_sfx(&"sg_revive", -3.0)
	_beats.append(&"burst")


func _play_land() -> void:
	var floor_point := Vector3(_pad.x, _pad.y - HIPS + 0.03, _pad.z)
	_spawn_ring(floor_point, Vector3.UP, 0.25, 3.0, 0.5, _color.lerp(Color.WHITE, 0.5), 2.2, 0.06)
	_spawn_ring(floor_point, Vector3.UP, 0.15, 1.7, 0.32, Color.WHITE, 1.8, 0.03)
	for _i in range(GraphicsQuality.particle_amount(26, GameManager.graphics_quality)):
		var angle := _rng.randf() * TAU
		var dir := Vector3(cos(angle), _rng.randf_range(0.05, 0.4), sin(angle)).normalized()
		_sparks.emit(floor_point + dir * 0.25, dir * _rng.randf_range(3.0, 6.5), _rng.randf_range(0.25, 0.45), _rng.randf_range(0.6, 1.0),
			Color(1.0, 0.96, 0.88).lerp(_color, _rng.randf_range(0.0, 0.5)), 4.0)
	_light_pulse = 2.0
	_beats.append(&"land")


## 体を全部戻す（魂の見た目・光の粒・淡い灯りを消す）。
func _make_solid() -> void:
	var pelvis := _puppet.parts().get("pelvis") as Node3D if _puppet != null else null
	if pelvis != null:
		PlayerController.remove_ghost_soul_look(pelvis)


## 弾けた瞬間の体の白い光。スキンのマテリアル（PlayerSkinRig。発光はいつも有効で黒）の発光の色を変える。
func _set_skin_flash(amount: float) -> void:
	var pelvis := _puppet.parts().get("pelvis") as Node3D if _puppet != null else null
	if pelvis == null or not pelvis.has_meta(PlayerSkinRig.MATERIALS_META):
		return
	var materials: Dictionary = pelvis.get_meta(PlayerSkinRig.MATERIALS_META)
	var glow := Color(1.0, 0.97, 0.92).lerp(_color, 0.3) * clampf(amount, 0.0, 2.0)
	for material: Variant in materials.values():
		(material as StandardMaterial3D).emission = Color(glow.r, glow.g, glow.b) if amount > 0.001 else Color.BLACK


func _ghost_mesh_count() -> int:
	var pelvis := _puppet.parts().get("pelvis") as Node3D if _puppet != null else null
	if pelvis == null:
		return 0
	var count := 0
	for node: Node in pelvis.find_children("*", "MeshInstance3D", true, false):
		if PlayerController.is_ghost_soul_look(node as MeshInstance3D):
			count += 1
	return count


func _cue(cue_name: String, when: bool) -> bool:
	if not when or _cues.has(cue_name):
		return false
	_cues[cue_name] = _clock
	return true


# ------------------------------------------------------------------ 光の部品（GhostRiderPresentation と同じ作り）

func _build_fx() -> void:
	_light = OmniLight3D.new()
	_light.name = "RevivalLight"
	_light.light_color = _color
	_light.light_energy = 0.0
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	_light.top_level = true
	_light.visible = false
	add_child(_light)
	var quality := GameManager.graphics_quality
	_sparks = FxPool.new(GraphicsQuality.particle_amount(180, quality), _spark_mesh(), _glow_material(false), true)
	_sparks.node.name = "RevivalSparks"
	add_child(_sparks.node)
	_motes = FxPool.new(GraphicsQuality.particle_amount(120, quality), _mote_mesh(), _glow_material(true), false)
	_motes.node.name = "RevivalMotes"
	add_child(_motes.node)
	_build_vortex(GraphicsQuality.particle_amount(72, quality))


static func _spark_mesh() -> Mesh:
	var spark := BoxMesh.new()
	spark.size = Vector3(0.03, 0.26, 0.03)
	return spark


static func _mote_mesh() -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	return quad


## 加算の光（頂点色＝粒ごとの色）。billboard は丸いぼかしの板。
static func _glow_material(billboard: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.disable_fog = true
	material.disable_receive_shadows = true
	if billboard:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.add_point(0.35, Color(1, 1, 1, 0.55))
		gradient.set_color(2, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		material.albedo_texture = texture
	return material


func _fx_material(color: Color, energy: float, fresnel_power: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FX_SHADER
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("energy", energy)
	material.set_shader_parameter("fresnel_power", fresnel_power)
	material.set_shader_parameter("opacity", 1.0)
	return material


## 体のまわりを渦巻いて吸い込まれていく光の粒（体を呼んでいる間）。弾けると外へ散る。
func _build_vortex(count: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mote_mesh()
	mm.instance_count = maxi(count, 1)
	_vortex = MultiMeshInstance3D.new()
	_vortex.name = "RevivalVortex"
	_vortex.multimesh = mm
	_vortex.material_override = _glow_material(true)
	_vortex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vortex.top_level = true
	_vortex.custom_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	add_child(_vortex)
	for i in range(mm.instance_count):
		# x: 回る向きの角度、y: 高さのずれ、z: 1 周期の秒、w: 周期のずれ
		_vortex_seeds.append(Vector4(_rng.randf() * TAU, _rng.randf_range(-1.0, 1.0), _rng.randf_range(0.8, 1.35), _rng.randf()))
		mm.set_instance_color(i, Color(0, 0, 0, 0))


func _update_vortex(t: float) -> void:
	var mm := _vortex.multimesh
	var center := body_center()
	var strength := smoothstep(CALL_AT - 0.1, CALL_AT + 0.3, t) * (1.0 - smoothstep(BURST_AT - 0.05, BURST_AT + 0.02, t))
	var blast := t - BURST_AT if t >= BURST_AT else -1.0
	var visible_now := strength > 0.001 or (blast >= 0.0 and blast < 0.7)
	_vortex.visible = visible_now
	if not visible_now:
		return
	var gather := smoothstep(CALL_AT, CURL_AT, t)
	for i in range(mm.instance_count):
		var mote := _vortex_seeds[i]
		var period := mote.z * lerpf(0.7, 0.42, gather)
		var k := fposmod(t / period + mote.w, 1.0)
		var radius := lerpf(2.6, 1.6, gather) * pow(1.0 - k, 1.25) + 0.12
		var angle := mote.x + k * TAU * 1.35 * (1.0 if i % 2 == 0 else -1.0)
		var height := mote.y * 1.1 * (1.0 - k) + 0.1 * sin(angle * 2.0)
		var at := center + Vector3(cos(angle) * radius, height, sin(angle) * radius)
		var alpha := sin(PI * k) * strength * (0.55 + 0.45 * gather)
		var size := 0.55 + 0.6 * (1.0 - k)
		if blast >= 0.0:
			# 弾けた瞬間に外へ散る
			var out := (at - center).normalized()
			at += out * blast * 9.0 * (1.0 - blast)
			alpha = sin(PI * maxf(k, 0.3)) * (1.0 - blast / 0.7)
		var tint := _color.lerp(Color.WHITE, 0.35 + 0.4 * k)
		tint.a = clampf(alpha, 0.0, 1.0)
		mm.set_instance_color(i, tint)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), at))


## はまった部品と同じ形の光の殻が、ふくらみながら消える。
func _spawn_glow_shell(meshes: Array) -> void:
	var material := _fx_material(_color.lerp(Color.WHITE, 0.6), 2.6, 0.0)
	var nodes: Array[MeshInstance3D] = []
	var sources: Array[MeshInstance3D] = []
	for source: Variant in meshes:
		var mesh := source as MeshInstance3D
		var shell := MeshInstance3D.new()
		shell.name = "SnapGlow"
		shell.mesh = mesh.mesh
		shell.material_override = material
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shell.top_level = true
		add_child(shell)
		nodes.append(shell)
		sources.append(mesh)
	_effects.append({"kind": "glow", "nodes": nodes, "sources": sources, "age": 0.0, "duration": 0.22, "material": material})


func _spawn_ring(position: Vector3, normal: Vector3, start_radius: float, end_radius: float, duration: float,
		color: Color, energy: float, thickness: float, delay := 0.0) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "RevivalRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 1.0
	torus.rings = 64
	torus.ring_segments = 6
	ring.mesh = torus
	var material := _fx_material(color, energy, 0.0)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true
	ring.visible = false
	add_child(ring)
	var axis := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var ring_basis := Basis(Quaternion(Vector3.UP, axis))
	ring.global_transform = Transform3D(ring_basis.scaled(Vector3.ONE * maxf(start_radius, 0.01)), position)
	_effects.append({"kind": "ring", "node": ring, "age": -delay, "duration": duration, "from": start_radius, "to": end_radius,
		"thickness": thickness, "basis": ring_basis, "material": material, "origin": position})


func _spawn_shell(position: Vector3, start_radius: float, end_radius: float, duration: float, color: Color,
		energy: float, fresnel_power: float) -> void:
	var shell := MeshInstance3D.new()
	shell.name = "RevivalShell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	shell.mesh = sphere
	var material := _fx_material(color, energy, fresnel_power)
	shell.material_override = material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.top_level = true
	add_child(shell)
	shell.global_transform = Transform3D(Basis().scaled(Vector3.ONE * start_radius), position)
	_effects.append({"kind": "shell", "node": shell, "age": 0.0, "duration": duration, "from": start_radius, "to": end_radius,
		"material": material, "origin": position})


func _update_effects(delta: float) -> void:
	for index in range(_effects.size() - 1, -1, -1):
		var effect: Dictionary = _effects[index]
		effect.age = float(effect.age) + delta
		if float(effect.age) < 0.0:
			continue
		var progress := clampf(float(effect.age) / maxf(0.001, float(effect.duration)), 0.0, 1.0)
		var material := effect.material as ShaderMaterial
		match str(effect.kind):
			"ring":
				var node := effect.node as MeshInstance3D
				node.visible = true
				var eased := 1.0 - pow(1.0 - progress, 3.0)
				var radius := lerpf(float(effect.from), float(effect.to), eased)
				var thickness := float(effect.thickness) * (1.0 - progress * 0.6)
				(node.mesh as TorusMesh).inner_radius = clampf(1.0 - thickness / maxf(radius, 0.001), 0.0, 0.995)
				node.global_transform = Transform3D((effect.basis as Basis).scaled(Vector3.ONE * radius), effect.origin as Vector3)
				material.set_shader_parameter("opacity", pow(1.0 - progress, 1.6))
			"shell":
				var eased_shell := 1.0 - pow(1.0 - progress, 2.4)
				var radius := lerpf(float(effect.from), float(effect.to), eased_shell)
				(effect.node as Node3D).global_transform = Transform3D(Basis().scaled(Vector3.ONE * radius), effect.origin as Vector3)
				material.set_shader_parameter("opacity", pow(1.0 - progress, 2.0))
			"glow":
				var grow := 1.0 + 0.4 * (1.0 - pow(1.0 - progress, 2.0))
				var sources: Array = effect.sources
				var nodes: Array = effect.nodes
				for i in range(nodes.size()):
					var source := sources[i] as MeshInstance3D
					var node := nodes[i] as MeshInstance3D
					if source == null or not is_instance_valid(source):
						continue
					var xf := source.global_transform
					var center := xf * source.get_aabb().get_center()
					node.global_transform = Transform3D(xf.basis.scaled(Vector3.ONE * grow), center - xf.basis * source.get_aabb().get_center() * grow)
				material.set_shader_parameter("opacity", pow(1.0 - progress, 1.8))
		if progress >= 1.0:
			if effect.has("node"):
				(effect.node as Node).queue_free()
			if effect.has("nodes"):
				for node: Variant in effect.nodes:
					(node as Node).queue_free()
			_effects.remove_at(index)


# ------------------------------------------------------------------ 試合の頭の予熱

## 復活の光（飛ぶ部品の縁光り・加算の殻と輪・火花・粒）を、試合の頭の予熱のカメラの前に 1 つずつ置く（初めて描く
## ときに止まらないように。HeliSuddenDeathDirector.begin_render_prewarm）。消すのは呼ぶ側。
static func build_prewarm(parent: Node3D, at: Transform3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "GhostRevivalPrewarm"
	parent.add_child(holder)
	holder.global_transform = at
	var solid := ShaderMaterial.new()
	solid.shader = SOLID_SHADER
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	var piece := MeshInstance3D.new()
	piece.mesh = box
	piece.material_override = solid
	holder.add_child(piece)
	var fx := ShaderMaterial.new()
	fx.shader = FX_SHADER
	var torus := TorusMesh.new()
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = fx
	ring.position = Vector3(0.8, 0.0, 0.0)
	holder.add_child(ring)
	for pool: FxPool in [FxPool.new(1, _spark_mesh(), _glow_material(false), true), FxPool.new(1, _mote_mesh(), _glow_material(true), false)]:
		pool.node.top_level = false
		holder.add_child(pool.node)
		pool.emit(Vector3(-0.8, 0.0, 0.0), Vector3.UP, 1.0, 1.0, Color.WHITE)
		pool.step(0.016, 0.0)
	return holder
