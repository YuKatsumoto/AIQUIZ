extends Node
class_name ActiveRagdollDriver

## HFF風アクティブラグドール駆動器。
##
## 表示用スケルトン(キネマティックに _animate_skeleton 等でアニメ)の各ピボットの
## ローカル回転を「目標ローカル回転」として読み取り、対応する物理ボディ(四肢)へ
## 自前PDトルク(apply_torque)を毎 _physics_process で印加して半追従させる。
##
## Jolt には素直な目標角度サーボが無いため、各ボディの「目標ローカル回転と現在
## ローカル回転の差(クォータニオン誤差)」を角速度ベクトル化して
##   torque = Kp*(誤差軸*誤差角) - Kd*angular_velocity
## を印加する(Phase0 PoC で安定検証済みの方式)。
##
## Kp/Kd はボディ質量に比例させ(慣性≒質量)、四肢間で追従の硬さを揃える。
## Kp は意図的に低めにして慣性遅れ=HFFのぐにゃつきを残す。

const RB := preload("res://scripts/world/ragdoll_builder.gd")

var bodies: Dictionary = {}     # key -> RigidBody3D ("anchor" 含む)
var parts: Dictionary = {}      # 表示スケルトンノード辞書(目標源)
var pelvis: Node3D = null       # アンカー追従先

# ゲインは各ボディの慣性に基づき算出する(質量基準だと小さい手等が過剰に硬く
# なり発散するため)。目標自然角周波数 omega_n と減衰比 zeta から、ボディ慣性
# I に対し kp = I*omega_n^2, kd = 2*zeta*I*omega_n を与えると全部位の応答特性
# (硬さ・揺れ)が一定になる。
var omega_n: float = 12.0       # 目標自然角周波数(rad/s)。大きいほど硬い=遅れ少
var zeta: float = 0.5           # 減衰比。<1 で自然なオーバーシュート(HFFの揺れ)
var enabled: bool = true        # false で脱力(トルクOFF=死亡演出用)
var max_torque: float = 600.0   # 安全クランプ(発散防止)

# 重力フィードフォワード: 各ボディのピボット周り重力モーメントを打ち消す保持トルク。
# kp を上げずに「自重に負けた定常垂れ(ヘタり)」を消し、慣性遅れのぐにゃつきだけ残す。
var gravity_ff: bool = true     # false で無効化
var gravity_ff_sign: float = 1.0  # 1.0=保持(垂れ除去)。実機検証用に -1.0 で反転可能
const GRAVITY_MAG := 9.8        # プロジェクト既定重力(project.godot に上書き無し)
const MAX_ANG_VEL := 30.0       # 角速度の安全上限(rad/s≒5回転/s)。衝突や不正トルクで
								# 四肢が暴走するのを直接抑止する発散ガード(max_torque より確実)。

# 体幹物理体(Phase6)の PD ゲイン。位置は剛め(定位置維持=ゲーム進行を壊さない)、
# 回転は柔らかめ(HFFの"よろめき/崩れかける"=慣性遅れの揺れ)。
var torso_omega_pos: float = 22.0   # 位置サーボ自然角周波数。大きいほど定位置に固い
var torso_omega_rot: float = 7.0    # 回転サーボ自然角周波数。小さいほどよく揺れる
var torso_zeta: float = 0.5         # 回転の減衰比(<1 でよろめきの余韻)
var _torso: RigidBody3D = null      # 体幹物理体(無ければ従来のキネマ体幹のまま)
var _torso_target: Node3D = null    # 追従目標(anchor=pelvis 同期キネマ体)
var _torso_kp_pos: float = 0.0
var _torso_kd_pos: float = 0.0
var _torso_kp_rot: float = 0.0
var _torso_kd_rot: float = 0.0
# H7: 目標の並進速度フィードフォワード。位置サーボの減衰を「目標相対速度」基準に
# することで、急ドッジ等で目標が動いても胴体が定常ラグ無く追従する(回転は FF せず
# よろめきを残す)。
var _torso_tgt_prev_pos: Vector3 = Vector3.ZERO
var _torso_has_prev: bool = false

# 駆動対象の事前展開: [{body, parent, pivot, kp, kd}]
var _drives: Array = []


func setup(rag: Dictionary, display_parts: Dictionary, pelvis_node: Node3D) -> void:
	bodies = rag["bodies"]
	parts = display_parts
	pelvis = pelvis_node
	_drives.clear()
	for spec in RB.LIMB_SPECS:
		var body: RigidBody3D = bodies.get(spec["key"])
		var parent_body: RigidBody3D = bodies.get(spec["parent"])
		var pivot: Node3D = parts.get(spec["joint"])
		# 物理親の「表示対応ノード」。anchor は pelvis に同期されるので pelvis、
		# それ以外は親ボディに対応する表示メッシュノード(ビルド時の rest 姿勢源)。
		# 目標回転をこのノード基準で相対化し、現在回転(物理親基準)とフレームを揃える。
		# anchor/torso を親とする四肢ルートは pelvis を基準フレームにする(体幹物理体は
		# pelvis 目標へ追従するため、四肢目標は pelvis 相対で表せばフレームが整合する)。
		var parent_display: Node3D = pelvis if str(spec["parent"]) in ["anchor", "torso"] else parts.get(spec["parent"])
		if body == null or parent_body == null or pivot == null or parent_display == null:
			continue
		var d := {
			"body": body,
			"parent": parent_body,
			"parent_display": parent_display,
			"pivot": pivot,
			"i_eff": _box_inertia(spec["ext"], spec["mass"]),
			# ジョイント連結点のボディローカル位置(rest で捕捉, 不変)。重力FFの
			# モーメント腕に使う。表示ピボットは物理体が遅れると乖離するため不可。
			"joint_local": body.global_transform.affine_inverse() * pivot.global_position,
		}
		_apply_gains(d)
		_drives.append(d)
	_setup_torso()


## 体幹物理体の駆動準備。bodies["torso"] が在る場合のみ有効(Phase6)。
## 位置PD(質量基準)+回転PD(慣性基準)で anchor(=pelvis目標)へ追従させる。
func _setup_torso() -> void:
	_torso = bodies.get("torso")
	_torso_target = bodies.get("anchor")
	if _torso == null:
		return
	# 胴体衝突ボックス(0.5,0.82,0.30)の平均主慣性で回転ゲインを質量非依存化。
	var ti := _box_inertia(Vector3(0.25, 0.41, 0.15), _torso.mass)
	_torso_kp_rot = ti * torso_omega_rot * torso_omega_rot
	_torso_kd_rot = 2.0 * torso_zeta * ti * torso_omega_rot
	_torso_kp_pos = _torso.mass * torso_omega_pos * torso_omega_pos
	_torso_kd_pos = 2.0 * _torso.mass * torso_omega_pos


## ボックス(half_extents=ext, 質量=mass)の平均主慣性モーメントを返す。
func _box_inertia(ext: Vector3, mass: float) -> float:
	var sx := ext.x * 2.0
	var sy := ext.y * 2.0
	var sz := ext.z * 2.0
	var ix := (mass / 12.0) * (sy * sy + sz * sz)
	var iy := (mass / 12.0) * (sx * sx + sz * sz)
	var iz := (mass / 12.0) * (sx * sx + sy * sy)
	return (ix + iy + iz) / 3.0


func _apply_gains(d: Dictionary) -> void:
	var i_eff: float = d["i_eff"]
	d["kp"] = i_eff * omega_n * omega_n
	d["kd"] = 2.0 * zeta * i_eff * omega_n


## omega_n/zeta を変更した後に呼ぶとゲインを再計算する。
func refresh_gains() -> void:
	for d in _drives:
		_apply_gains(d)
	_setup_torso()


func _physics_process(delta: float) -> void:
	if bodies.is_empty():
		return
	# 体幹アンカー(目標)を pelvis へ同期
	RB.sync_anchor(bodies.get("anchor"), pelvis)
	if not enabled:
		return
	_drive_torso(delta)
	for d in _drives:
		_drive_one(d)


## 体幹物理体を anchor(=pelvis目標)へ PD 駆動。位置=剛め、回転=柔らかめ。
func _drive_torso(delta: float) -> void:
	if _torso == null or _torso_target == null:
		return
	var tgt := _torso_target.global_transform
	# 目標の並進速度(H7 フィードフォワード)
	var tgt_vel := Vector3.ZERO
	if _torso_has_prev and delta > 0.0:
		tgt_vel = (tgt.origin - _torso_tgt_prev_pos) / delta
	_torso_tgt_prev_pos = tgt.origin
	_torso_has_prev = true
	# 位置PD(定位置維持: ゲーム進行を壊さない)。減衰は目標相対速度基準=移動目標に
	# 定常ラグ無く追従(H7)。
	var pos_err := tgt.origin - _torso.global_position
	_torso.apply_central_force(pos_err * _torso_kp_pos - (_torso.linear_velocity - tgt_vel) * _torso_kd_pos)
	# 回転PD(よろめき: 目標姿勢へ柔らかく追従。誤差はワールド系なので軸変換不要)
	var tq := tgt.basis.get_rotation_quaternion()
	var bq := _torso.global_transform.basis.get_rotation_quaternion()
	var q_err := (tq * bq.inverse()).normalized()
	if q_err.w < 0.0:
		q_err = -q_err
	var axis := Vector3(q_err.x, q_err.y, q_err.z)
	var sh := axis.length()
	var torque: Vector3
	if sh < 1e-6:
		torque = -_torso.angular_velocity * _torso_kd_rot
	else:
		var angle := 2.0 * atan2(sh, q_err.w)
		torque = (axis / sh) * (angle * _torso_kp_rot) - _torso.angular_velocity * _torso_kd_rot
	_torso.apply_torque(torque.limit_length(max_torque))
	if _torso.angular_velocity.length() > MAX_ANG_VEL:
		_torso.angular_velocity = _torso.angular_velocity.normalized() * MAX_ANG_VEL


## 目標ローカル回転を「物理親と同じ基準フレーム」で算出する。
## pivot の表示親(spine 等の非駆動中間ピボット)と物理親(anchor=pelvis 等)が
## 食い違う場合でも、両者を物理親の表示対応ノード basis で相対化することで整合する。
## (旧実装の pivot.transform.basis 直読みは spine 回転を取りこぼし、肩/頭が胴の
##  ひねりから取り残されていた。遠位関節では本式は従来値と一致し回帰しない。)
func _target_local(d: Dictionary) -> Quaternion:
	var pd: Node3D = d["parent_display"]
	var pivot: Node3D = d["pivot"]
	var pdq := pd.global_transform.basis.get_rotation_quaternion()
	var pq := pivot.global_transform.basis.get_rotation_quaternion()
	return (pdq.inverse() * pq).normalized()


func _drive_one(d: Dictionary) -> void:
	var body: RigidBody3D = d["body"]
	var parent_body: RigidBody3D = d["parent"]
	var pivot: Node3D = d["pivot"]

	# 目標ローカル回転(物理親フレーム基準)
	var target_local := _target_local(d)

	# 現在ローカル回転 = parent^-1 * body (ワールド回転から相対化)
	var parent_q := parent_body.global_transform.basis.get_rotation_quaternion()
	var body_q := body.global_transform.basis.get_rotation_quaternion()
	var cur_local := parent_q.inverse() * body_q

	# 誤差クォータニオン(最短弧)
	var q_err := (target_local * cur_local.inverse()).normalized()
	if q_err.w < 0.0:
		q_err = -q_err
	var axis := Vector3(q_err.x, q_err.y, q_err.z)
	var sin_half := axis.length()

	var torque := Vector3.ZERO
	if sin_half < 1e-6:
		# 誤差ほぼ無し: 減衰のみ印加(acos/atan2 特異点を回避)
		torque = -body.angular_velocity * float(d["kd"])
	else:
		# angle = 2*atan2(|v|, w): w≈1 近傍でも安定(acos の傾き発散を回避)
		var angle := 2.0 * atan2(sin_half, q_err.w)
		var axis_world := parent_q * (axis / sin_half)  # 親ローカル軸→ワールド(単位)
		torque = axis_world * (angle * float(d["kp"])) - body.angular_velocity * float(d["kd"])

	# 重力フィードフォワード: ジョイント連結点周りの重力トルク τ_g=r×(m·g) の逆符号を
	# 保持トルクとして加算し、自重に負けた定常垂れ(ヘタり)を消す。モーメント腕 r は
	# ボディローカル固定ベクトル(joint_local)を現姿勢へ回したもの=物理体に追従し、
	# 表示ピボットとの乖離による誤差を生まない。
	if gravity_ff:
		var jl: Vector3 = d["joint_local"]
		var r := -(body.global_transform.basis * jl)
		var tau_g := r.cross(body.mass * Vector3(0.0, -GRAVITY_MAG, 0.0))
		torque += -tau_g * gravity_ff_sign

	torque = torque.limit_length(max_torque)
	body.apply_torque(torque)

	# 発散ガード: 角速度が上限を超えたら直接クランプ(衝突や不正トルクでの暴走防止)。
	var av := body.angular_velocity
	if av.length() > MAX_ANG_VEL:
		body.angular_velocity = av.normalized() * MAX_ANG_VEL


## 追従精度の計測(度)。avg=平均誤差角, max=最大誤差角, max_ang_vel=最大角速度。
func get_tracking_error() -> Dictionary:
	var total := 0.0
	var max_e := 0.0
	var max_av := 0.0
	var n := 0
	for d in _drives:
		var body: RigidBody3D = d["body"]
		var parent_body: RigidBody3D = d["parent"]
		var target_local := _target_local(d)
		var parent_q := parent_body.global_transform.basis.get_rotation_quaternion()
		var body_q := body.global_transform.basis.get_rotation_quaternion()
		var cur_local := parent_q.inverse() * body_q
		var q_err := (target_local * cur_local.inverse()).normalized()
		var axis_len := Vector3(q_err.x, q_err.y, q_err.z).length()
		var ang := rad_to_deg(2.0 * atan2(axis_len, absf(q_err.w)))
		total += ang
		if ang > max_e:
			max_e = ang
		var av := body.angular_velocity.length()
		if av > max_av:
			max_av = av
		n += 1
	return {
		"avg": snapped(total / max(n, 1), 0.1),
		"max": snapped(max_e, 0.1),
		"max_ang_vel": snapped(max_av, 0.01),
	}
