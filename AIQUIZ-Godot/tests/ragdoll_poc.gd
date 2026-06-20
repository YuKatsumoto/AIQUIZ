extends Node3D
## Phase 0: 単一関節アクティブラグドール PoC
## キネマアンカー(肩)から上腕1本を ConeTwistJoint3D でぶら下げ、
## apply_torque による自前PD制御で目標ローカル回転へ半追従させる。
## 目的: Jolt 物理 120Hz で爆発・スナップ・角速度発散が起きないことを検証する。

# PDゲイン（_update_bobblehead の spring_k=18 / damping=3.5 を初期指針に）
const KP := 14.0
const KD := 2.0

# l_upp_arm の実寸法（_create_box は引数=半径で size=引数×2）
const ARM_SIZE := Vector3(0.24, 0.52, 0.24)
const ARM_MASS := 2.5

# 肩アンカーの基準ワールド位置（観察しやすい高さ）
const SHOULDER_BASE := Vector3(0.0, 2.0, 0.0)

var _anchor: RigidBody3D
var _arm: RigidBody3D
var _t := 0.0
var _max_ang_vel := 0.0   # 観察用: 角速度の最大値（発散検出）
var _frames := 0

func _ready() -> void:
	_build_environment()
	_build_joint_chain()

func _build_environment() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.7, 3.6)
	cam.look_at_from_position(Vector3(0.0, 1.7, 3.6), Vector3(0.0, 1.5, 0.0), Vector3.UP)
	cam.current = true
	add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	add_child(light)

	# 床（既存ゲームと同じ layer1）
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -0.2, 0.0)
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(8.0, 0.4, 8.0)
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	add_child(floor_body)

func _make_box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	return mi

func _build_joint_chain() -> void:
	# 肩アンカー（キネマRB: 物理で動かされず、こちらが position を駆動する）
	_anchor = RigidBody3D.new()
	_anchor.freeze = true
	_anchor.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_anchor.position = SHOULDER_BASE
	add_child(_anchor)
	_anchor.add_child(_make_box(Vector3(0.18, 0.18, 0.18), Color(0.9, 0.3, 0.3)))

	# 上腕 RB（肩から下へ伸びる: 中心は肩 - 半長）
	_arm = RigidBody3D.new()
	_arm.mass = ARM_MASS
	_arm.gravity_scale = 1.0
	_arm.linear_damp = 0.4
	_arm.angular_damp = 1.0
	_arm.can_sleep = false
	_arm.collision_layer = 2   # ragdoll
	_arm.collision_mask = 1    # 床のみ
	_arm.position = SHOULDER_BASE + Vector3(0.0, -ARM_SIZE.y * 0.5, 0.0)
	add_child(_arm)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = ARM_SIZE
	col.shape = shape
	_arm.add_child(col)
	_arm.add_child(_make_box(ARM_SIZE, Color(0.85, 0.48, 0.18)))

	# ConeTwistJoint: 肩位置を回転中心に anchor <-> arm を連結
	var joint := ConeTwistJoint3D.new()
	add_child(joint)
	joint.position = SHOULDER_BASE
	joint.node_a = _anchor.get_path()
	joint.node_b = _arm.get_path()
	joint.set("swing_span", deg_to_rad(80.0))
	joint.set("twist_span", deg_to_rad(40.0))
	joint.exclude_nodes_from_collision = true

func _physics_process(delta: float) -> void:
	_t += delta
	_frames += 1
	# アンカー（肩）を左右にゆっくり揺らし、目標が動く状況を作る
	var sway := sin(_t * 1.2) * 0.8
	_anchor.position = SHOULDER_BASE + Vector3(sway, 0.0, 0.0)
	# 目標ローカル回転: 上腕を前後にスイング（X軸）
	var target_local := Quaternion(Vector3(1.0, 0.0, 0.0), sin(_t * 1.8) * 0.7)
	_drive_pd(_arm, _anchor, target_local)
	# 観察用: 角速度の最大値を記録
	var av := _arm.angular_velocity.length()
	if av > _max_ang_vel:
		_max_ang_vel = av

# 親基準の目標ローカル回転へ向けて PD トルクを印加する
func _drive_pd(body: RigidBody3D, parent: RigidBody3D, target_local: Quaternion) -> void:
	var parent_q := parent.global_transform.basis.get_rotation_quaternion()
	var body_q := body.global_transform.basis.get_rotation_quaternion()
	# 現在のローカル回転（親基準）
	var cur_local := parent_q.inverse() * body_q
	# 目標との誤差（親ローカル空間）
	var q_err := (target_local * cur_local.inverse()).normalized()
	if q_err.w < 0.0:
		q_err = Quaternion(-q_err.x, -q_err.y, -q_err.z, -q_err.w)
	var angle := 2.0 * acos(clampf(q_err.w, -1.0, 1.0))
	var axis := Vector3(q_err.x, q_err.y, q_err.z)
	if axis.length() < 0.0001:
		body.apply_torque(-body.angular_velocity * KD)
		return
	axis = axis.normalized()
	# 誤差軸は親ローカル空間 -> ワールド空間へ変換
	var axis_world := (parent_q * axis).normalized()
	var torque := axis_world * (angle * KP) - body.angular_velocity * KD
	body.apply_torque(torque)

# MCP からの検証用: 観察値を返す
func get_diag() -> Dictionary:
	return {
		"t": _t,
		"frames": _frames,
		"max_ang_vel": _max_ang_vel,
		"arm_ang_vel": _arm.angular_velocity.length() if is_instance_valid(_arm) else -1.0,
		"arm_pos": _arm.global_position if is_instance_valid(_arm) else Vector3.ZERO,
	}
