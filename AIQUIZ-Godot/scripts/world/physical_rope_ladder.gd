extends Node3D
class_name PhysicalRopeLadder

## A world-space rope ladder for the main-menu extraction shot.
## The helicopter only owns a lightweight mount point. Rope sections stay under
## this stationary world node so the hatch can move without fighting the pose.
##
## After the coil is released, a Verlet rope keeps the rails connected while
## gravity, throw, wind, and hatch motion travel down the chain.

const ROPE_ALBEDO := preload(
	"res://assets/materials/rope_ladder/Rope03D_Color_1K.png"
)
const ROPE_NORMAL := preload(
	"res://assets/materials/rope_ladder/Rope03D_Normal_OpenGL_1K.png"
)
const ROPE_ROUGHNESS := preload(
	"res://assets/materials/rope_ladder/Rope03D_Roughness_1K.png"
)
const ROPE_AO := preload(
	"res://assets/materials/rope_ladder/Rope03D_AmbientOcclusion_1K.png"
)

const SEGMENT_COUNT := 13
const SEGMENT_LENGTH := 0.56
const ROPE_RADIUS := 0.068
const LADDER_WIDTH := 1.10
const RUNG_RADIUS := 0.058
const RUNG_ROWS: Array[int] = [1, 3, 5, 7, 9, 11, 12]
const GRIP_RUNG_INDEX := 6
const ROPE_MASS := 0.075
const RUNG_MASS := 0.22
const PAYLOAD_MASS := 1.35
const MAX_BODY_SPEED := 24.0
const COIL_RADIUS := 0.14
const COIL_STACK := 0.045
const COIL_RAIL_HALF := 0.05
const COIL_LIFT := 0.50
const COIL_DROP_THRESHOLD := 0.02
const UNCOIL_DURATION := 0.62
const HANG_READY_RATIO := 0.78
const ROPE_GRAVITY := 9.81
const ROPE_DAMPING := 0.966
const ROPE_CONSTRAINT_ITERS := 6
const ROPE_THROW_SPEED := 5.8
const ROPE_THROW_SIDE := 2.3
const ROPE_WIND := 1.2
const ROPE_WASH := 0.8
const ROPE_TAUT_RATIO := 0.80
const ROPE_RAIL_BLEND := 0.09
const ROPE_REST_SCALE := 1.02
const ROPE_MID_SAG := 5.4

## Per-sequence release settings leave gameplay arrival at its normal pace.
var deploy_throw_speed := ROPE_THROW_SPEED
var deploy_damping := ROPE_DAMPING
var deploy_recoil_scale := 1.0
var deploy_lateral_scale := 1.0
var inherit_carrier_velocity := false

var _attachment: Node3D = null
var _player_index := 1
var _built := false
var _physics_released := false
var _deploy_progress := 0.0
var _payload_active := false
var _rope_material: StandardMaterial3D = null
var _rung_material: StandardMaterial3D = null
var _top_left: AnimatableBody3D = null
var _top_right: AnimatableBody3D = null
var _left_segments: Array[RigidBody3D] = []
var _right_segments: Array[RigidBody3D] = []
## Hardwood steps are visual cross-braces between the two simulated ropes.
## Their weight is distributed into the adjacent rope bodies. This avoids an
## over-constrained lattice of 40 pin joints that visibly tore apart at speed.
var _rungs: Array[Node3D] = []
var _joints: Array[PinJoint3D] = []
var _last_top_center := Vector3.ZERO
var _top_velocity := Vector3.ZERO
var _physics_time := 0.0
var _release_time := -1.0
var _paid_out := 0
var _sim_left := PackedVector3Array()
var _sim_right := PackedVector3Array()
var _prev_left := PackedVector3Array()
var _prev_right := PackedVector3Array()
var _sim_ready := false
var _did_taut_snap := false
var _grip_velocity := Vector3.ZERO
var _last_grip_center := Vector3.ZERO
var _winch_progress := 0.0


## Pull material through the cabin winch, keeping deployed rung spacing intact.
func set_winch_progress(progress: float) -> void:
	_winch_progress = clampf(progress, 0.0, 1.0)


func _deployed_segment_length(row: int) -> float:
	var reeled_length := _winch_progress * (SEGMENT_LENGTH * SEGMENT_COUNT - 0.42)
	return clampf(SEGMENT_LENGTH * float(row + 1) - reeled_length, 0.0, SEGMENT_LENGTH)


func _apply_winch_coil() -> void:
	if _winch_progress <= 0.0:
		return
	var frame := _cabin_frame()
	var right: Vector3 = frame["right"]
	var left_coil := PackedVector3Array()
	var right_coil := PackedVector3Array()
	for index: int in range(SEGMENT_COUNT + 1):
		var sample := _coil_sample(float(index) * SEGMENT_LENGTH, frame["center"], right, frame["forward"])
		left_coil.append(sample["point"] - sample["radial"] * COIL_RAIL_HALF)
		right_coil.append(sample["point"] + sample["radial"] * COIL_RAIL_HALF)
	for row: int in range(SEGMENT_COUNT):
		if _deployed_segment_length(row) > 0.001:
			continue
		for side_index: int in range(2):
			var points := left_coil if side_index == 0 else right_coil
			var body := _left_segments[row] if side_index == 0 else _right_segments[row]
			var tangent := points[row + 1] - points[row]
			body.global_transform = Transform3D(
				_basis_from_y_axis(tangent.normalized(), right),
				points[row].lerp(points[row + 1], 0.5))
			var visual := body.get_node("BraidedRope") as MeshInstance3D
			visual.scale.y = clampf(tangent.length() / (SEGMENT_LENGTH + ROPE_RADIUS * 1.6), 0.05, 1.0)
	for rung_index: int in range(_rungs.size()):
		_rungs[rung_index].visible = _deployed_segment_length(RUNG_ROWS[rung_index]) > 0.03



func configure(attachment: Node3D, player_index: int) -> void:
	if _built:
		return
	_attachment = attachment
	_player_index = clampi(player_index, 1, 2)
	_rope_material = _make_rope_material()
	_rung_material = _make_rung_material()
	_top_left = _make_top_anchor("P%dLadderTopLeft" % _player_index)
	_top_right = _make_top_anchor("P%dLadderTopRight" % _player_index)
	for row: int in range(SEGMENT_COUNT):
		_left_segments.append(_make_rope_segment("LeftRope%02d" % row))
		_right_segments.append(_make_rope_segment("RightRope%02d" % row))
	for rung_index: int in range(RUNG_ROWS.size()):
		_rungs.append(_make_rung("Rung%02d" % rung_index, rung_index))
	_built = true
	_update_top_anchors(1.0 / 60.0)
	_apply_coiled_pose()
	set_physics_process(true)


func set_deploy_progress(progress: float) -> void:
	_deploy_progress = clampf(progress, 0.0, 1.0)
	if not _built:
		return
	if _deploy_progress < COIL_DROP_THRESHOLD:
		_reset_coil_state()
		_apply_coiled_pose()
		return
	if _release_time < 0.0:
		_release_time = _physics_time
		_physics_released = true


func apply_editor_preview(progress: float) -> void:
	_deploy_progress = clampf(progress, 0.0, 1.0)
	if not _built:
		return
	if _deploy_progress <= 0.001:
		_reset_coil_state()
		_update_top_anchors(0.0)
		_apply_coiled_pose()
		return
	if _physics_released:
		return
	_update_top_anchors(0.0)
	_apply_preview_uncoil(_deploy_progress)


func _reset_coil_state() -> void:
	_physics_released = false
	_release_time = -1.0
	_sim_ready = false
	_did_taut_snap = false
	_paid_out = 0
	_winch_progress = 0.0


func set_payload_active(active: bool) -> void:
	_payload_active = active


func is_fully_deployed() -> bool:
	return _physics_released and _hang_ratio() >= HANG_READY_RATIO


## Grounded runners wait until the rope has visibly finished paying out.
func is_ready_for_ground_pickup() -> bool:
	return _physics_released and _hang_ratio() >= 0.95


func get_grip_transform() -> Transform3D:
	var rung := _get_grip_rung()
	if rung == null or not is_instance_valid(rung):
		return Transform3D.IDENTITY
	return rung.global_transform


func get_grip_data() -> Dictionary:
	var rung := _get_grip_rung()
	if rung == null or not is_instance_valid(rung):
		return {"valid": false}
	var horizontal := rung.global_basis.y.normalized()
	if horizontal.length_squared() <= 0.0001:
		horizontal = Vector3.RIGHT
	var forward := Vector3.FORWARD
	if _attachment != null and is_instance_valid(_attachment):
		forward = -_attachment.global_basis.z
		forward.y = 0.0
		if forward.length_squared() <= 0.0001:
			forward = Vector3.FORWARD
		else:
			forward = forward.normalized()
	return {
		"valid": true,
		"center": rung.global_position,
		"left_hand": rung.global_position - horizontal * 0.42,
		"right_hand": rung.global_position + horizontal * 0.42,
		"horizontal": horizontal,
		"forward": forward,
		"velocity": _grip_velocity,
		"deployed": _physics_released,
	}


func get_debug_state() -> Dictionary:
	var maximum_speed := 0.0
	for body: RigidBody3D in _all_dynamic_bodies():
		if body != null and is_instance_valid(body):
			maximum_speed = maxf(maximum_speed, body.linear_velocity.length())
	var grip_data := get_grip_data()
	return {
		"built": _built,
		"deploy_progress": _deploy_progress,
		"winch_progress": _winch_progress,
		"deployed_length": SEGMENT_LENGTH * SEGMENT_COUNT - _winch_progress * (SEGMENT_LENGTH * SEGMENT_COUNT - 0.42),
		"physics_released": _physics_released,
		"payload_active": _payload_active,
		"joint_count": _joints.size(),
		"maximum_speed": maximum_speed,
		"grip_position": grip_data.get("center", Vector3.ZERO),
		"hang_ratio": _hang_ratio(),
		"paid_out": _paid_out,
		"fully_deployed": is_fully_deployed(),
		"max_chain_gap": _max_chain_gap(),
		"tip_offset": _tip_offset(),
	}


func _physics_process(delta: float) -> void:
	if not _built or _attachment == null or not is_instance_valid(_attachment):
		return
	_physics_time += delta
	_update_top_anchors(delta)
	if _release_time < 0.0:
		_apply_coiled_pose()
		return
	if not _sim_ready:
		_init_verlet_sim()
	_step_verlet_sim(delta)
	_apply_verlet_pose()
	_paid_out = clampi(ceili(_hang_ratio() * float(SEGMENT_COUNT)), 0, SEGMENT_COUNT)
	_update_grip_velocity(delta)


func _make_rope_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = ROPE_ALBEDO
	material.albedo_color = Color(1.0, 0.90, 0.72, 1.0)
	material.normal_enabled = true
	material.normal_texture = ROPE_NORMAL
	material.normal_scale = 0.88
	material.roughness = 0.82
	material.roughness_texture = ROPE_ROUGHNESS
	material.ao_enabled = true
	material.ao_texture = ROPE_AO
	# Rope 03D is an atlas of vertical cords. Restrict U to one source cord so
	# the cylindrical mesh receives one continuous braided strand.
	material.uv1_scale = Vector3(0.052, 1.45, 1.0)
	material.uv1_offset = Vector3(0.024, 0.0, 0.0)
	return material


func _make_rung_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.31, 0.17, 0.075, 1.0)
	material.roughness = 0.86
	material.metallic = 0.0
	return material


func _make_top_anchor(anchor_name: String) -> AnimatableBody3D:
	var anchor := AnimatableBody3D.new()
	anchor.name = anchor_name
	anchor.sync_to_physics = true
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	add_child(anchor)
	return anchor


func _make_rope_segment(segment_name: String) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = segment_name
	body.mass = ROPE_MASS
	body.gravity_scale = 1.0
	body.linear_damp = 0.36
	body.angular_damp = 0.48
	body.continuous_cd = true
	body.can_sleep = false
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 0
	body.collision_mask = 0

	var visual := MeshInstance3D.new()
	visual.name = "BraidedRope"
	var mesh := CapsuleMesh.new()
	mesh.radius = ROPE_RADIUS
	mesh.height = SEGMENT_LENGTH + ROPE_RADIUS * 1.6
	mesh.radial_segments = 10
	mesh.rings = 3
	visual.mesh = mesh
	visual.material_override = _rope_material
	body.add_child(visual)

	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = ROPE_RADIUS * 0.72
	shape.height = SEGMENT_LENGTH * 0.94
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body


func _make_rung(rung_name: String, rung_index: int) -> Node3D:
	var body := Node3D.new()
	body.name = rung_name

	var visual := MeshInstance3D.new()
	visual.name = "HardwoodStep"
	var mesh := CylinderMesh.new()
	mesh.height = LADDER_WIDTH + 0.16
	mesh.top_radius = RUNG_RADIUS
	mesh.bottom_radius = RUNG_RADIUS
	mesh.radial_segments = 12
	visual.mesh = mesh
	var material := _rung_material.duplicate() as StandardMaterial3D
	material.albedo_color = material.albedo_color.lightened(float(rung_index % 3) * 0.025)
	visual.material_override = material
	body.add_child(visual)

	for side: float in [-1.0, 1.0]:
		var knot := MeshInstance3D.new()
		knot.name = "RopeKnotLeft" if side < 0.0 else "RopeKnotRight"
		var knot_mesh := TorusMesh.new()
		knot_mesh.inner_radius = 0.048
		knot_mesh.outer_radius = 0.082
		knot_mesh.rings = 12
		knot_mesh.ring_segments = 6
		knot.mesh = knot_mesh
		knot.position.y = side * LADDER_WIDTH * 0.5
		knot.material_override = _rope_material
		body.add_child(knot)

	add_child(body)
	return body


func _update_top_anchors(delta: float) -> void:
	var center := _attachment.global_position
	var right := _attachment.global_basis.x
	if _physics_released:
		right.y = 0.0
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var half_width := (
		LADDER_WIDTH * 0.5
		if _physics_released and _deploy_progress >= COIL_DROP_THRESHOLD
		else (COIL_RADIUS + COIL_RAIL_HALF)
	)
	var left_position := center - right * half_width
	var right_position := center + right * half_width
	if _top_left != null:
		_top_left.global_position = left_position
	if _top_right != null:
		_top_right.global_position = right_position
	if _last_top_center != Vector3.ZERO and delta > 0.0001:
		var measured_velocity := (center - _last_top_center) / delta
		_top_velocity = _top_velocity.lerp(measured_velocity, clampf(delta * 10.0, 0.0, 1.0))
	_last_top_center = center


func _apply_coiled_pose() -> void:
	if _attachment == null or not is_instance_valid(_attachment):
		return
	_update_top_anchors(0.0)
	var frame := _cabin_frame()
	var right: Vector3 = frame["right"]
	_pose_side_from_points(_left_segments, _connected_side_points(-1.0), right)
	_pose_side_from_points(_right_segments, _connected_side_points(1.0), right)
	_update_rungs_from_rope()


func _apply_preview_uncoil(progress: float) -> void:
	if _attachment == null or not is_instance_valid(_attachment):
		return
	var frame := _cabin_frame()
	var center: Vector3 = frame["center"]
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var left_mount: Vector3 = _top_left.global_position if _top_left != null else center - right * LADDER_WIDTH * 0.5
	var right_mount: Vector3 = _top_right.global_position if _top_right != null else center + right * LADDER_WIDTH * 0.5
	for row: int in range(SEGMENT_COUNT):
		var row_delay := float(row) / float(SEGMENT_COUNT) * 0.20
		var row_progress := smoothstep(
			0.0,
			1.0,
			clampf((progress - row_delay) / maxf(1.0 - row_delay, 0.01), 0.0, 1.0)
		)
		var hang_depth := -SEGMENT_LENGTH * (float(row) + 0.5)
		var hang_left := left_mount + Vector3.UP * hang_depth
		var hang_right := right_mount + Vector3.UP * hang_depth
		var hang_basis := _basis_from_y_axis(Vector3.DOWN, right)
		var left_body := _left_segments[row]
		var right_body := _right_segments[row]
		left_body.visible = true
		right_body.visible = true
		if row == 0:
			var coil_entry: Dictionary = _coil_sample(SEGMENT_LENGTH, center, right, forward)
			var entry_point: Vector3 = coil_entry["point"]
			var coil_left := left_mount.lerp(entry_point, 0.5)
			var coil_right := right_mount.lerp(entry_point, 0.5)
			var coil_left_basis := _basis_from_y_axis((entry_point - left_mount).normalized(), right)
			var coil_right_basis := _basis_from_y_axis((entry_point - right_mount).normalized(), right)
			left_body.global_transform = Transform3D(
				coil_left_basis.slerp(hang_basis, row_progress),
				coil_left.lerp(hang_left, row_progress)
			)
			right_body.global_transform = Transform3D(
				coil_right_basis.slerp(hang_basis, row_progress),
				coil_right.lerp(hang_right, row_progress)
			)
			continue
		var sample := _coil_sample(float(row) * SEGMENT_LENGTH, center, right, forward)
		var point: Vector3 = sample["point"]
		var tangent: Vector3 = sample["tangent"]
		var radial: Vector3 = sample["radial"]
		var coil_basis := _basis_from_y_axis(tangent, right)
		left_body.global_transform = Transform3D(
			coil_basis.slerp(hang_basis, row_progress),
			(point - radial * COIL_RAIL_HALF).lerp(hang_left, row_progress)
		)
		right_body.global_transform = Transform3D(
			coil_basis.slerp(hang_basis, row_progress),
			(point + radial * COIL_RAIL_HALF).lerp(hang_right, row_progress)
		)
	_update_rungs_from_rope()
	for rung: Node3D in _rungs:
		rung.visible = true


func _coil_sample(
	s: float,
	center: Vector3,
	right: Vector3,
	forward: Vector3
) -> Dictionary:
	var wind := 1.0 if _player_index == 1 else -1.0
	var up := Vector3.UP
	if _attachment != null and is_instance_valid(_attachment):
		up = _attachment.global_basis.y
		if up.length_squared() <= 0.0001:
			up = Vector3.UP
		else:
			up = up.normalized()
	var circumference := TAU * COIL_RADIUS
	var loop_f := s / circumference
	var theta := wind * loop_f * TAU
	var radial := (right * cos(theta) + forward * sin(theta))
	if radial.length_squared() <= 0.0001:
		radial = right
	else:
		radial = radial.normalized()
	var axis := center + up * COIL_LIFT
	var point := axis + radial * COIL_RADIUS + up * (COIL_STACK * loop_f)
	var tangent := (
		wind * (-right * sin(theta) + forward * cos(theta))
		+ up * (COIL_STACK / circumference)
	)
	if tangent.length_squared() <= 0.0001:
		tangent = -up
	else:
		tangent = tangent.normalized()
	return {
		"point": point,
		"tangent": tangent,
		"radial": radial,
	}


func _attachment_frame() -> Dictionary:
	var center := _attachment.global_position
	var right := _attachment.global_basis.x
	right.y = 0.0
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var forward := -_attachment.global_basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	return {
		"center": center,
		"right": right,
		"forward": forward,
	}


func _cabin_frame() -> Dictionary:
	var center := _attachment.global_position
	var right := _attachment.global_basis.x
	var forward := -_attachment.global_basis.z
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	return {
		"center": center,
		"right": right,
		"forward": forward,
	}


func _side_mount(side_index: int) -> Vector3:
	var frame := _attachment_frame()
	var center: Vector3 = frame["center"]
	var right: Vector3 = frame["right"]
	var side_sign := -1.0 if side_index == 0 else 1.0
	if side_index == 0 and _top_left != null:
		return _top_left.global_position
	if side_index == 1 and _top_right != null:
		return _top_right.global_position
	return center + right * side_sign * LADDER_WIDTH * 0.5


func _payout() -> float:
	if _release_time < 0.0:
		return 0.0
	return smoothstep(0.0, 1.0, clampf(_drop_age() / UNCOIL_DURATION, 0.0, 1.0))


func _apply_payout_pose(payout: float) -> void:
	if _attachment == null or not is_instance_valid(_attachment):
		return
	_update_top_anchors(0.0)
	var frame := _attachment_frame()
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var amount := clampf(payout, 0.0, 1.0)
	var length_scale := lerpf(0.16, 1.0, amount)
	var coil_keep := 1.0 - amount
	for side_index: int in range(2):
		var side_sign := -1.0 if side_index == 0 else 1.0
		var mount: Vector3 = _side_mount(side_index)
		var points := PackedVector3Array()
		points.append(mount)
		var cursor: Vector3 = mount
		for row: int in range(SEGMENT_COUNT):
			var depth := float(row + 1)
			var hang_point: Vector3 = mount + Vector3.DOWN * SEGMENT_LENGTH * depth * length_scale
			var swirl: Vector3 = (
				right * cos(depth * 0.85 + side_sign)
				+ forward * sin(depth * 0.85 + side_sign)
			) * COIL_RADIUS * 0.55 * coil_keep
			var desired: Vector3 = hang_point + swirl * side_sign
			var delta: Vector3 = desired - cursor
			if delta.length_squared() <= 0.0001:
				delta = Vector3.DOWN
			cursor += delta.normalized() * (SEGMENT_LENGTH * length_scale)
			points.append(cursor)
		var segments: Array[RigidBody3D] = _left_segments if side_index == 0 else _right_segments
		_pose_side_from_points(segments, points, right)
	_update_rungs_from_rope()
	for rung: Node3D in _rungs:
		rung.visible = true


func _apply_hang_sway() -> void:
	if _attachment == null or not is_instance_valid(_attachment):
		return
	var frame := _attachment_frame()
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var side := -1.0 if _player_index == 1 else 1.0
	var phase := _physics_time * 1.55 + float(_player_index)
	for side_index: int in range(2):
		var side_sign := -1.0 if side_index == 0 else 1.0
		var mount: Vector3 = (
			_top_left.global_position
			if side_index == 0 and _top_left != null
			else (
				_top_right.global_position
				if _top_right != null
				else (frame["center"] as Vector3) + right * side_sign * LADDER_WIDTH * 0.5
			)
		)
		var points := PackedVector3Array()
		points.append(mount)
		var cursor: Vector3 = mount
		for row: int in range(SEGMENT_COUNT):
			var depth := float(row + 1) / float(SEGMENT_COUNT)
			var sag := 0.07 if _payload_active and row >= RUNG_ROWS[GRIP_RUNG_INDEX] else 0.0
			var offset: Vector3 = (
				right * sin(phase) * 0.08
				+ forward * cos(phase * 0.82) * 0.05 * side
			) * depth * depth
			offset += Vector3.DOWN * sag * depth
			var desired: Vector3 = mount + Vector3.DOWN * SEGMENT_LENGTH * float(row + 1) + offset
			var delta: Vector3 = desired - cursor
			if delta.length_squared() <= 0.0001:
				delta = Vector3.DOWN
			cursor += delta.normalized() * SEGMENT_LENGTH
			points.append(cursor)
		var segments: Array[RigidBody3D] = _left_segments if side_index == 0 else _right_segments
		_pose_side_from_points(segments, points, right)
	_update_rungs_from_rope()


func _release_to_physics() -> void:
	return


func _build_joints() -> void:
	var frame := _attachment_frame()
	var right: Vector3 = frame["right"]
	for side_index: int in range(2):
		var side_sign := -1.0 if side_index == 0 else 1.0
		var anchor: AnimatableBody3D = _top_left if side_index == 0 else _top_right
		var segments: Array[RigidBody3D] = _left_segments if side_index == 0 else _right_segments
		var points: PackedVector3Array = _connected_side_points(side_sign)
		_pose_side_from_points(segments, points, right)
		_add_pin_joint(anchor, segments[0], points[0], "Top%d" % side_index)
		for row: int in range(1, SEGMENT_COUNT):
			_add_pin_joint(
				segments[row - 1],
				segments[row],
				points[row],
				"Rope%d_%02d" % [side_index, row]
			)


func _add_pin_joint(
	body_a: PhysicsBody3D,
	body_b: PhysicsBody3D,
	world_position: Vector3,
	joint_name: String
) -> void:
	var joint := PinJoint3D.new()
	joint.name = joint_name
	add_child(joint)
	joint.global_position = world_position
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	joint.set_param(PinJoint3D.PARAM_BIAS, 0.86)
	joint.set_param(PinJoint3D.PARAM_DAMPING, 2.35)
	joint.set_param(PinJoint3D.PARAM_IMPULSE_CLAMP, 0.0)
	_joints.append(joint)


func _get_grip_rung() -> Node3D:
	if _rungs.is_empty():
		return null
	return _rungs[clampi(GRIP_RUNG_INDEX, 0, _rungs.size() - 1)]


func _all_dynamic_bodies() -> Array[RigidBody3D]:
	var bodies: Array[RigidBody3D] = []
	bodies.append_array(_left_segments)
	bodies.append_array(_right_segments)
	return bodies


func _update_rungs_from_rope() -> void:
	var show_rungs := _physics_released and _deploy_progress >= COIL_DROP_THRESHOLD
	for rung_index: int in range(_rungs.size()):
		var rung := _rungs[rung_index]
		if not show_rungs:
			rung.visible = false
			continue
		var row := RUNG_ROWS[rung_index]
		var left_position := _left_segments[row].global_position
		var right_position := _right_segments[row].global_position
		var axis := right_position - left_position
		if axis.length_squared() <= 0.0001:
			axis = Vector3.RIGHT
		rung.visible = true
		rung.global_transform = Transform3D(
			_basis_from_y_axis(axis.normalized(), Vector3.UP),
			(left_position + right_position) * 0.5
		)
		rung.scale = Vector3(
			1.0,
			axis.length() / (LADDER_WIDTH + 0.16),
			1.0
		)


func _stabilize_rope_chain(anchor: AnimatableBody3D, segments: Array[RigidBody3D]) -> void:
	if anchor == null or segments.is_empty():
		return
	_apply_rope_spring(
		null,
		segments[0],
		anchor.global_position,
		_top_velocity,
		SEGMENT_LENGTH * 0.5
	)
	for row: int in range(1, segments.size()):
		_apply_rope_spring(
			segments[row - 1],
			segments[row],
			segments[row - 1].global_position,
			segments[row - 1].linear_velocity,
			SEGMENT_LENGTH
		)


func _apply_rope_spring(
	body_a: RigidBody3D,
	body_b: RigidBody3D,
	position_a: Vector3,
	velocity_a: Vector3,
	rest_distance: float,
	stiffness: float = 220.0,
	damping: float = 5.6,
	maximum_force: float = 110.0
) -> void:
	var offset := body_b.global_position - position_a
	var distance := offset.length()
	if distance <= 0.0001:
		return
	var direction := offset / distance
	var relative_speed := (body_b.linear_velocity - velocity_a).dot(direction)
	var force_magnitude := clampf(
		(distance - rest_distance) * stiffness + relative_speed * damping,
		-maximum_force,
		maximum_force
	)
	var force := -direction * force_magnitude
	body_b.apply_central_force(force)
	if body_a != null:
		body_a.apply_central_force(-force)


func _update_paid_out() -> void:
	if _attachment == null or not is_instance_valid(_attachment):
		return
	var top := _attachment.global_position
	var bottom := (
		_left_segments[SEGMENT_COUNT - 1].global_position
		+ _right_segments[SEGMENT_COUNT - 1].global_position
	) * 0.5
	var estimated := clampi(
		int(floor(top.distance_to(bottom) / SEGMENT_LENGTH + 1.6)),
		0,
		SEGMENT_COUNT
	)
	_paid_out = maxi(_paid_out, estimated)


func _init_verlet_sim() -> void:
	if _sim_ready:
		return
	var dt := 1.0 / 60.0
	var frame := _attachment_frame()
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var side := -1.0 if _player_index == 1 else 1.0
	_sim_left = _connected_side_points(-1.0)
	_sim_right = _connected_side_points(1.0)
	_prev_left = _sim_left.duplicate()
	_prev_right = _sim_right.duplicate()
	var throw: Vector3 = Vector3.DOWN * deploy_throw_speed + (forward * side + right * 0.35) * ROPE_THROW_SIDE * deploy_lateral_scale
	var right_throw: Vector3 = throw + (right * 0.85 - forward * 0.45) * deploy_lateral_scale
	# A coil released from a moving cabin already carries the aircraft velocity.
	var inherited_velocity := _top_velocity if inherit_carrier_velocity else Vector3.ZERO
	for point_index: int in range(1, _sim_left.size()):
		var depth := float(point_index) / float(maxi(_sim_left.size() - 1, 1))
		_prev_left[point_index] = _sim_left[point_index] - (throw * depth + inherited_velocity) * dt
		_prev_right[point_index] = _sim_right[point_index] - (right_throw * depth + inherited_velocity) * dt
	_sim_ready = true
	_did_taut_snap = false


func _step_verlet_sim(delta: float) -> void:
	var dt := clampf(delta, 0.001, 1.0 / 30.0)
	var frame := _attachment_frame()
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var side := -1.0 if _player_index == 1 else 1.0
	var time := _physics_time
	var wash: Vector3 = (right * sin(time * 3.35) + forward * cos(time * 2.55)) * ROPE_WASH
	var gust: Vector3 = (
		right * sin(time * 1.18 + float(_player_index))
		+ forward * cos(time * 0.86 + float(_player_index) * 0.7)
	) * ROPE_WIND * side
	var left_result: Dictionary = _integrate_rope(_sim_left, _prev_left, _side_mount(0), dt, wash, gust, 0.0)
	_prev_left = left_result["prev"]
	_sim_left = left_result["points"]
	var right_result: Dictionary = _integrate_rope(_sim_right, _prev_right, _side_mount(1), dt, wash, gust, 0.22)
	_prev_right = right_result["prev"]
	_sim_right = right_result["points"]
	_constrain_rope_lengths(_side_mount(0), _side_mount(1))
	_couple_rails()
	if _winch_progress > 0.0:
		# The winch imposes a hard maximum length. Remove swallowed top spans;
		# the remaining rope still carries its integrated lateral momentum.
		for row: int in range(SEGMENT_COUNT):
			var span := _deployed_segment_length(row) * ROPE_REST_SCALE
			for points: PackedVector3Array in [_sim_left, _sim_right]:
				var offset := points[row + 1] - points[row]
				if offset.length() > span:
					points[row + 1] = points[row] + offset.normalized() * span
	else:
		_snap_when_taut(dt, right, side)


func _integrate_rope(
	points: PackedVector3Array,
	prev: PackedVector3Array,
	mount: Vector3,
	dt: float,
	wash: Vector3,
	gust: Vector3,
	phase_offset: float
) -> Dictionary:
	var next_points := PackedVector3Array()
	var next_prev := PackedVector3Array()
	next_points.resize(points.size())
	next_prev.resize(points.size())
	next_points[0] = mount
	next_prev[0] = mount
	var grip_row := RUNG_ROWS[GRIP_RUNG_INDEX] + 1
	var damping := ROPE_DAMPING if _payload_active else lerpf(deploy_damping, ROPE_DAMPING, smoothstep(0.80, 0.98, _hang_ratio()))
	for point_index: int in range(1, points.size()):
		var depth := float(point_index) / float(maxi(points.size() - 1, 1))
		var velocity: Vector3 = (points[point_index] - prev[point_index]) * damping
		var accel: Vector3 = (
			Vector3.DOWN * ROPE_GRAVITY
			+ wash * (1.0 - depth)
			+ gust * depth * depth
		)
		var mid_weight := sin(depth * PI)
		accel += Vector3.DOWN * ROPE_MID_SAG * mid_weight
		accel += gust.rotated(Vector3.UP, PI * 0.5) * mid_weight * 1.35
		accel += (
			wash.rotated(Vector3.UP, phase_offset) * 0.18
			+ gust.rotated(Vector3.UP, phase_offset) * 0.12
		) * depth
		if _payload_active and point_index >= grip_row:
			# Payload changes wind response, not gravitational acceleration.
			accel = Vector3.DOWN * ROPE_GRAVITY + (accel - Vector3.DOWN * ROPE_GRAVITY) * 0.25
		var next: Vector3 = points[point_index] + velocity + accel * dt * dt
		next_prev[point_index] = points[point_index]
		next_points[point_index] = next
	return {
		"points": next_points,
		"prev": next_prev,
	}


func _constrain_rope_lengths(left_mount: Vector3, right_mount: Vector3) -> void:
	for _iter: int in range(ROPE_CONSTRAINT_ITERS):
		_sim_left[0] = left_mount
		_sim_right[0] = right_mount
		_sim_left = _solve_distance_chain(_sim_left)
		_sim_right = _solve_distance_chain(_sim_right)
		_sim_left[0] = left_mount
		_sim_right[0] = right_mount


func _solve_distance_chain(points: PackedVector3Array) -> PackedVector3Array:
	for point_index: int in range(points.size() - 1):
		var offset: Vector3 = points[point_index + 1] - points[point_index]
		var distance := offset.length()
		if distance <= 0.0001:
			continue
		var rest_length := _deployed_segment_length(point_index) * ROPE_REST_SCALE
		var error := (distance - rest_length) / distance
		if point_index == 0:
			points[point_index + 1] -= offset * error
		else:
			points[point_index] += offset * error * 0.5
			points[point_index + 1] -= offset * error * 0.5
	return points


func _couple_rails() -> void:
	var count := mini(_sim_left.size(), _sim_right.size())
	for point_index: int in range(1, count):
		var left_point: Vector3 = _sim_left[point_index]
		var right_point: Vector3 = _sim_right[point_index]
		var span: Vector3 = right_point - left_point
		if span.length_squared() <= 0.0001:
			continue
		var mid: Vector3 = (left_point + right_point) * 0.5
		var half: Vector3 = span.normalized() * LADDER_WIDTH * 0.5
		_sim_left[point_index] = left_point.lerp(mid - half, ROPE_RAIL_BLEND)
		_sim_right[point_index] = right_point.lerp(mid + half, ROPE_RAIL_BLEND)


func _snap_when_taut(dt: float, right: Vector3, side: float) -> void:
	if _did_taut_snap or _hang_ratio() < ROPE_TAUT_RATIO:
		return
	_did_taut_snap = true
	var last := _sim_left.size() - 1
	if last <= 0:
		return
	var tip: Vector3 = (_sim_left[last] + _sim_right[last]) * 0.5
	var from_top: Vector3 = tip - _side_mount(0)
	if from_top.length_squared() <= 0.0001:
		from_top = Vector3.DOWN
	else:
		from_top = from_top.normalized()
	var kick: Vector3 = (-from_top * 3.1 + right * 1.7 * side) * deploy_recoil_scale
	for point_index: int in range(1, _sim_left.size()):
		var depth := float(point_index) / float(maxi(_sim_left.size() - 1, 1))
		if depth < 0.32:
			continue
		var impulse: Vector3 = kick * depth * depth * dt
		_prev_left[point_index] = _sim_left[point_index] - impulse
		_prev_right[point_index] = _sim_right[point_index] - impulse


func _apply_verlet_pose() -> void:
	if _sim_left.size() < 2 or _sim_right.size() < 2:
		return
	var frame := _attachment_frame()
	var right: Vector3 = frame["right"]
	_pose_side_from_points(_left_segments, _bowed_points(_sim_left), right)
	_pose_side_from_points(_right_segments, _bowed_points(_sim_right, 0.82), right)
	_update_rungs_from_rope()
	for rung: Node3D in _rungs:
		rung.visible = true
	_apply_winch_coil()


func _bowed_points(points: PackedVector3Array, amount_scale: float = 1.0) -> PackedVector3Array:
	var bowed := points.duplicate()
	if _winch_progress > 0.0 or _payload_active:
		return bowed
	var last := bowed.size() - 1
	if last <= 2:
		return bowed
	var mount: Vector3 = bowed[0]
	var tip: Vector3 = bowed[last]
	var chord: Vector3 = tip - mount
	if chord.length_squared() <= 0.25:
		return bowed
	var chord_dir := chord.normalized()
	var bend_normal := Vector3.UP.cross(chord_dir)
	if bend_normal.length_squared() <= 0.0001:
		var frame := _attachment_frame()
		bend_normal = frame["right"]
	else:
		bend_normal = bend_normal.normalized()
	var age := _drop_age()
	var whip := clampf(1.1 - age * 0.18, 0.40, 1.1)
	var tip_slide := clampf(Vector3(tip.x - mount.x, 0.0, tip.z - mount.z).length(), 0.0, 3.2)
	var bow_amount := clampf((0.38 + tip_slide * 0.12) * whip, 0.0, 0.62) * amount_scale
	var wave := sin(_physics_time * 2.45 + float(_player_index)) * bow_amount
	var wave_b := sin(_physics_time * 3.2 + 0.7) * bow_amount * 0.34
	for point_index: int in range(1, last):
		var depth := float(point_index) / float(last)
		var bell := sin(depth * PI)
		var s_curve := sin(depth * TAU)
		var offset: Vector3 = bend_normal * (wave * bell + wave_b * s_curve)
		offset += Vector3.DOWN * bell * 0.08 * whip
		bowed[point_index] = bowed[point_index] + offset
	return bowed


func _update_grip_velocity(delta: float) -> void:
	var grip := get_grip_data()
	var center: Vector3 = grip.get("center", Vector3.ZERO)
	if _last_grip_center != Vector3.ZERO and delta > 0.0001:
		_grip_velocity = _grip_velocity.lerp(
			(center - _last_grip_center) / delta,
			clampf(delta * 8.0, 0.0, 1.0)
		)
	_last_grip_center = center




func _apply_release_damping() -> void:
	var settle := clampf(_drop_age() / 0.70, 0.0, 1.0)
	var linear_damp := lerpf(0.48, 0.36, settle)
	var angular_damp := lerpf(0.72, 0.48, settle)
	for body: RigidBody3D in _all_dynamic_bodies():
		body.linear_damp = linear_damp
		body.angular_damp = angular_damp


func _drop_age() -> float:
	if _release_time < 0.0:
		return 0.0
	return maxf(_physics_time - _release_time, 0.0)


func _tip_offset() -> float:
	if _left_segments.is_empty() or _attachment == null or not is_instance_valid(_attachment):
		return 0.0
	var top := _attachment.global_position
	var tip: Vector3 = (
		_left_segments[SEGMENT_COUNT - 1].global_position
		+ _right_segments[SEGMENT_COUNT - 1].global_position
	) * 0.5
	var planar := Vector3(tip.x - top.x, 0.0, tip.z - top.z)
	return planar.length()


func _hang_ratio() -> float:
	if (
		_attachment == null
		or not is_instance_valid(_attachment)
		or _left_segments.is_empty()
		or _right_segments.is_empty()
	):
		return 0.0
	var top := _attachment.global_position
	var bottom := (
		_left_segments[SEGMENT_COUNT - 1].global_position
		+ _right_segments[SEGMENT_COUNT - 1].global_position
	) * 0.5
	var full := SEGMENT_LENGTH * float(SEGMENT_COUNT)
	return clampf(top.distance_to(bottom) / full, 0.0, 1.0)


func _connected_side_points(side_sign: float) -> PackedVector3Array:
	var frame := _cabin_frame()
	var center: Vector3 = frame["center"]
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var mount := (
		_top_left.global_position
		if side_sign < 0.0 and _top_left != null
		else (
			_top_right.global_position
			if side_sign > 0.0 and _top_right != null
			else center + right * side_sign * LADDER_WIDTH * 0.5
		)
	)
	var points := PackedVector3Array()
	points.append(mount)
	for row: int in range(SEGMENT_COUNT):
		var sample := _coil_sample(
			float(row + 1) * SEGMENT_LENGTH,
			center,
			right,
			forward
		)
		points.append(sample["point"] + sample["radial"] * side_sign * COIL_RAIL_HALF)
	return points


func _pose_side_from_points(
	segments: Array[RigidBody3D],
	points: PackedVector3Array,
	right_hint: Vector3
) -> void:
	for row: int in range(SEGMENT_COUNT):
		var start: Vector3 = points[row]
		var finish: Vector3 = points[row + 1]
		var tangent := finish - start
		var length := tangent.length()
		if length <= 0.0001:
			tangent = Vector3.DOWN
			length = SEGMENT_LENGTH
		segments[row].visible = true
		segments[row].scale = Vector3.ONE
		segments[row].global_transform = Transform3D(
			_basis_from_y_axis(tangent.normalized(), right_hint),
			start.lerp(finish, 0.5)
		)
		var visual := segments[row].get_node_or_null("BraidedRope") as MeshInstance3D
		if visual != null:
			var visual_height := SEGMENT_LENGTH + ROPE_RADIUS * 1.6
			visual.scale = Vector3(1.0, clampf(length / visual_height, 0.20, 1.0), 1.0)


func _constrain_rope_chain(anchor: AnimatableBody3D, segments: Array[RigidBody3D]) -> void:
	if anchor == null or segments.is_empty():
		return
	var previous := anchor.global_position
	var rest := SEGMENT_LENGTH * 0.5
	for row: int in range(segments.size()):
		var body := segments[row]
		var offset := body.global_position - previous
		var distance := offset.length()
		if distance <= 0.0001:
			previous = body.global_position
			rest = SEGMENT_LENGTH
			continue
		var direction := offset / distance
		var error := distance - rest
		if absf(error) > 0.0008:
			var xf := body.global_transform
			xf.origin = previous + direction * rest
			body.global_transform = xf
			var separating := body.linear_velocity.dot(direction)
			if (error > 0.0 and separating > 0.0) or (error < 0.0 and separating < 0.0):
				body.linear_velocity -= direction * separating * 0.92
		previous = body.global_position
		rest = SEGMENT_LENGTH


func _align_rope_segments(
	anchor: AnimatableBody3D,
	segments: Array[RigidBody3D],
	right_hint: Vector3
) -> void:
	if anchor == null or segments.is_empty():
		return
	var previous := anchor.global_position
	for row: int in range(segments.size()):
		var body := segments[row]
		var tangent := body.global_position - previous
		if tangent.length_squared() <= 0.0001:
			tangent = Vector3.DOWN
		body.global_transform = Transform3D(
			_basis_from_y_axis(tangent.normalized(), right_hint),
			body.global_position
		)
		previous = body.global_position


func _max_chain_gap() -> float:
	var worst := 0.0
	for side_index: int in range(2):
		var anchor: AnimatableBody3D = _top_left if side_index == 0 else _top_right
		var segments: Array[RigidBody3D] = _left_segments if side_index == 0 else _right_segments
		if anchor == null or segments.is_empty():
			continue
		var previous := anchor.global_position
		var rest := SEGMENT_LENGTH * 0.5
		for body: RigidBody3D in segments:
			worst = maxf(worst, absf(body.global_position.distance_to(previous) - rest))
			previous = body.global_position
			rest = SEGMENT_LENGTH
	return worst


func _basis_from_y_axis(direction: Vector3, x_hint: Vector3) -> Basis:
	var y_axis := direction.normalized()
	if y_axis.length_squared() <= 0.0001:
		y_axis = Vector3.UP
	var x_axis := x_hint - y_axis * y_axis.dot(x_hint)
	if x_axis.length_squared() <= 0.0001:
		x_axis = Vector3.RIGHT - y_axis * y_axis.dot(Vector3.RIGHT)
	if x_axis.length_squared() <= 0.0001:
		x_axis = Vector3.FORWARD - y_axis * y_axis.dot(Vector3.FORWARD)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()
