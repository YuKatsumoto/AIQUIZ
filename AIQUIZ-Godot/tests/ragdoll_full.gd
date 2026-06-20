extends Node3D
## Phase1/2: 全四肢ラグドールの隔離検証ハーネス
##
## 非ツリーの PlayerController から _build_player_skeleton だけを呼び出して
## 静止ポーズのブロックスケルトンを得る(_ready / FBXリグ読込を回避)。
## その大域変換から RagdollBuilder で四肢物理ツリーを生成する。
##
## Phase1: PD駆動なし(受動)で発散しないことを確認。
## Phase2: 表示スケルトンの各ピボットを手続きアニメで動かし、それを目標源として
##         ActiveRagdollDriver が物理四肢(緑)を半追従させる。色付き(目標)に対し
##         緑(物理)が慣性遅れでぐにゃっと追従する HFF らしさを確認する。

const RagdollBuilderRes = preload("res://scripts/world/ragdoll_builder.gd")
const PlayerControllerRes = preload("res://scripts/world/player_controller.gd")
const ActiveRagdollDriverRes = preload("res://scripts/world/active_ragdoll_driver.gd")

@export var drive_enabled: bool = true   # false で Phase1 受動検証
@export var animate_target: bool = true   # 目標ポーズを動かすか

var _pc: Node3D          # ツリー外に保持(GC回避)。_ready は走らない
var _holder: Node3D      # スケルトンの親(ツリー内)
var _parts: Dictionary
var _rag: Dictionary
var _pelvis: Node3D
var _driver: ActiveRagdollDriver

var _t := 0.0
var _frames := 0
var _max_ang_vel := 0.0
var _max_lin_vel := 0.0


var _headless := false

func _ready() -> void:
	_build_environment()
	_build_skeleton()
	_build_ragdoll()
	if drive_enabled:
		_build_driver()
	# ヘッドレスCLI実行(--headless)時は一定フレーム後に診断を出力して終了する。
	# MCPブリッジを介さない物理検証用。インタラクティブ実行には影響しない。
	_headless = DisplayServer.get_name() == "headless"


func _build_environment() -> void:
	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(0.0, 1.4, 3.6), Vector3(0.0, 0.7, 0.0), Vector3.UP)
	add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	light.light_energy = 1.1
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.48)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	# 床 StaticBody (layer1) : 四肢(mask1)が接地する
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -0.2, 0.0)
	add_child(floor_body)
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(8.0, 0.4, 8.0)
	fshape.shape = fbox
	floor_body.add_child(fshape)
	var fmesh := MeshInstance3D.new()
	var fbm := BoxMesh.new()
	fbm.size = Vector3(8.0, 0.4, 8.0)
	fmesh.mesh = fbm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.3, 0.3, 0.34)
	fmesh.material_override = fmat
	floor_body.add_child(fmesh)


func _build_skeleton() -> void:
	# ツリー外で PlayerController を生成(_ready は呼ばれない)。
	_pc = PlayerControllerRes.new()
	_holder = Node3D.new()
	_holder.name = "SkeletonHolder"
	_holder.position = Vector3(0.0, 1.5, 0.0)   # 足が床(top=0)付近に来る高さ
	add_child(_holder)
	# 表示スケルトンを holder 配下に構築 → 大域変換が有効になる
	_parts = _pc._build_player_skeleton(true, _holder)
	_pelvis = _parts["pelvis"]

	# Phase2: 表示スケルトン(色付き)は目標ポーズの参照として表示したまま。
	# Phase1 受動検証時(drive_enabled=false)は隠して緑の物理体だけ見せる。
	if not drive_enabled:
		for m in _parts["meshes"]:
			if is_instance_valid(m):
				m.visible = false


func _build_ragdoll() -> void:
	var container := Node3D.new()
	container.name = "RagdollLimbs"
	add_child(container)
	_rag = RagdollBuilderRes.build(container, _pelvis, _parts)


func _build_driver() -> void:
	_driver = ActiveRagdollDriverRes.new()
	_driver.name = "ActiveRagdollDriver"
	_driver.process_physics_priority = 10   # 目標アニメ更新の後に駆動
	add_child(_driver)
	_driver.setup(_rag, _parts, _pelvis)
	# CLI検証用の上書き: `-- --no-gravity-ff`, `-- --zeta=0.4`, `-- --omega=16` 等
	for a in OS.get_cmdline_user_args():
		if a == "--no-gravity-ff":
			_driver.gravity_ff = false
		elif a.begins_with("--zeta="):
			_driver.zeta = float(a.substr(7))
			_driver.refresh_gains()
		elif a.begins_with("--omega="):
			_driver.omega_n = float(a.substr(8))
			_driver.refresh_gains()


func _physics_process(delta: float) -> void:
	if _rag.is_empty():
		return
	_t += delta
	if drive_enabled and animate_target:
		_animate_target()
	if not drive_enabled:
		# 受動: アンカー同期だけ行う(ドライバが無いため)
		RagdollBuilderRes.sync_anchor(_rag["anchor"], _pelvis)
	_frames += 1
	for key in _rag["bodies"]:
		if key == "anchor":
			continue
		var b: RigidBody3D = _rag["bodies"][key]
		var av := b.angular_velocity.length()
		var lv := b.linear_velocity.length()
		if av > _max_ang_vel:
			_max_ang_vel = av
		if lv > _max_lin_vel:
			_max_lin_vel = lv
	# ヘッドレス検証: 約5秒(600物理フレーム@120Hz)で整定後に診断を出力し終了。
	if _headless and _frames == 600:
		_print_headless_report()
		get_tree().quit()


func _print_headless_report() -> void:
	var per := []
	if _driver:
		for d in _driver._drives:
			var tl: Quaternion = _driver._target_local(d)
			var pq: Quaternion = d.parent.global_transform.basis.get_rotation_quaternion()
			var bq: Quaternion = d.body.global_transform.basis.get_rotation_quaternion()
			var qe: Quaternion = (tl * (pq.inverse() * bq).inverse()).normalized()
			var al: float = Vector3(qe.x, qe.y, qe.z).length()
			per.append({
				"k": str(d.body.name).replace("RB_", ""),
				"err": snapped(rad_to_deg(2.0 * atan2(al, absf(qe.w))), 0.1),
				"av": snapped(d.body.angular_velocity.length(), 0.1),
			})
		per.sort_custom(func(a, b): return a.err > b.err)
	var torso_info := {}
	if _driver and _driver._torso and _driver._torso_target:
		var tb: RigidBody3D = _driver._torso
		var tt: Node3D = _driver._torso_target
		var aq: Quaternion = tt.global_transform.basis.get_rotation_quaternion()
		var bq: Quaternion = tb.global_transform.basis.get_rotation_quaternion()
		var qe: Quaternion = (aq * bq.inverse()).normalized()
		torso_info = {
			"pos_dev": snapped((tb.global_position - tt.global_position).length(), 0.001),
			"ang_dev": snapped(rad_to_deg(2.0 * atan2(Vector3(qe.x, qe.y, qe.z).length(), absf(qe.w))), 0.1),
			"av": snapped(tb.angular_velocity.length(), 0.1),
		}
	print("HEADLESS_DIAG ", JSON.stringify({"diag": get_diag(), "torso": torso_info, "per": per}))


## 表示スケルトンのピボットを手続きで動かして目標ポーズを生成する
## (空中マーチ風: 肩/肘/股/膝を周期運動)。
func _animate_target() -> void:
	var s := sin(_t * 2.0)
	var c := cos(_t * 2.0)
	# 体幹(spine)ひねり+前後屈: 肩/頭の物理親(anchor=pelvis)と表示親(spine)の
	# 参照フレーム不一致を顕在化させる検証用。フレーム整合修正後は腕/頭が胴の
	# ひねりに追従し、track 誤差が脚と同水準に収まることを確認できる。
	_set_pivot_rot("spine", Vector3(sin(_t * 1.3) * 0.2, sin(_t * 1.7) * 0.35, 0.0))
	# 肩: 前後スイング(X軸)
	_set_pivot_rot("l_shoulder", Vector3(s * 0.9, 0.0, 0.0))
	_set_pivot_rot("r_shoulder", Vector3(-s * 0.9, 0.0, 0.0))
	# 肘: 屈曲(X軸, 0〜1.2rad)
	_set_pivot_rot("l_elbow", Vector3(-(0.6 + 0.6 * c), 0.0, 0.0))
	_set_pivot_rot("r_elbow", Vector3(-(0.6 - 0.6 * c), 0.0, 0.0))
	# 股: 前後スイング(肩と逆位相 = マーチ)
	_set_pivot_rot("l_hip", Vector3(-s * 0.7, 0.0, 0.0))
	_set_pivot_rot("r_hip", Vector3(s * 0.7, 0.0, 0.0))
	# 膝: 屈曲
	_set_pivot_rot("l_knee", Vector3(0.5 + 0.5 * c, 0.0, 0.0))
	_set_pivot_rot("r_knee", Vector3(0.5 - 0.5 * c, 0.0, 0.0))
	# 頭: 軽い傾き
	_set_pivot_rot("neck", Vector3(s * 0.2, 0.0, c * 0.15))
	# pelvis(体幹目標)を揺らし、体幹物理体のよろめき追従と定位置維持を検証する。
	var pv: Node3D = _parts.get("pelvis")
	if pv:
		pv.rotation = Vector3(sin(_t * 1.1) * 0.15, sin(_t * 0.7) * 0.22, cos(_t * 0.9) * 0.15)


func _set_pivot_rot(key: String, euler: Vector3) -> void:
	var n: Node3D = _parts.get(key)
	if n:
		n.rotation = euler


## 数値検証用。
func get_diag() -> Dictionary:
	var out := {
		"frames": _frames,
		"max_ang_vel": snapped(_max_ang_vel, 0.01),
		"max_lin_vel": snapped(_max_lin_vel, 0.01),
		"drive_enabled": drive_enabled,
	}
	if _driver:
		out["track"] = _driver.get_tracking_error()
	return out
