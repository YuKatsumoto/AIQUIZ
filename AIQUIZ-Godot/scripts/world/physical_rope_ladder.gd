extends Node3D
class_name PhysicalRopeLadder

## A world-space, jointed rope ladder for the main-menu extraction shot.
## The helicopter only owns a lightweight mount point. Every rope section and
## rung remains under this stationary world node so moving parent transforms do
## not fight Godot's rigid-body solver.

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
const ROPE_RADIUS := 0.052
const LADDER_WIDTH := 1.10
const RUNG_RADIUS := 0.058
const RUNG_ROWS: Array[int] = [1, 3, 5, 7, 9, 11, 12]
const GRIP_RUNG_INDEX := 6
const ROPE_MASS := 0.075
const RUNG_MASS := 0.22
const PAYLOAD_MASS := 1.35
const MAX_BODY_SPEED := 24.0
const DEPLOY_RELEASE_THRESHOLD := 0.995

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
	_apply_authored_deployment(0.0)
	set_physics_process(true)


func set_deploy_progress(progress: float) -> void:
	_deploy_progress = clampf(progress, 0.0, 1.0)
	if not _built or _physics_released:
		return
	_apply_authored_deployment(_deploy_progress)
	if _deploy_progress >= DEPLOY_RELEASE_THRESHOLD:
		_release_to_physics()


func set_payload_active(active: bool) -> void:
	_payload_active = active


func is_fully_deployed() -> bool:
	return _physics_released


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
		"velocity": (
			(_left_segments[RUNG_ROWS[GRIP_RUNG_INDEX]].linear_velocity
			+ _right_segments[RUNG_ROWS[GRIP_RUNG_INDEX]].linear_velocity) * 0.5
			if _physics_released else _top_velocity
		),
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
		"physics_released": _physics_released,
		"payload_active": _payload_active,
		"joint_count": _joints.size(),
		"maximum_speed": maximum_speed,
		"grip_position": grip_data.get("center", Vector3.ZERO),
	}


func _physics_process(delta: float) -> void:
	if not _built or _attachment == null or not is_instance_valid(_attachment):
		return
	_physics_time += delta
	_update_top_anchors(delta)
	if not _physics_released:
		_apply_authored_deployment(_deploy_progress)
		return
	var side := -1.0 if _player_index == 1 else 1.0
	var wind := Vector3(
		sin(_physics_time * 2.25 + float(_player_index)) * 0.42,
		-0.08,
		cos(_physics_time * 1.65 + float(_player_index) * 0.7) * 0.30 * side
	)
	var bodies := _all_dynamic_bodies()
	for body_index: int in range(bodies.size()):
		var body: RigidBody3D = bodies[body_index]
		if body == null or not is_instance_valid(body):
			continue
		var depth_ratio := float(body_index + 1) / float(maxi(bodies.size(), 1))
		var relative_velocity := _top_velocity - body.linear_velocity
		var aerodynamic_drag := relative_velocity * body.mass * lerpf(0.38, 0.72, depth_ratio)
		body.apply_central_force(aerodynamic_drag + wind * body.mass)
		if body.linear_velocity.length() > MAX_BODY_SPEED:
			body.linear_velocity = body.linear_velocity.normalized() * MAX_BODY_SPEED
	_stabilize_rope_chain(_top_left, _left_segments)
	_stabilize_rope_chain(_top_right, _right_segments)
	# Rungs brace the side ropes throughout the ladder, including the short rope
	# spans between visible steps. Soft cross-springs prevent the rails from
	# swapping sides while preserving twist and lateral sway.
	for row: int in range(SEGMENT_COUNT):
		var braced := RUNG_ROWS.has(row)
		_apply_rope_spring(
			_left_segments[row],
			_right_segments[row],
			_left_segments[row].global_position,
			_left_segments[row].linear_velocity,
			LADDER_WIDTH,
			128.0 if braced else 76.0,
			5.2 if braced else 3.4,
			52.0 if braced else 34.0
		)
	for rung_index: int in range(RUNG_ROWS.size()):
		var row := RUNG_ROWS[rung_index]
		var rung_weight := Vector3.DOWN * RUNG_MASS * 9.8 * 0.5
		_left_segments[row].apply_central_force(rung_weight)
		_right_segments[row].apply_central_force(rung_weight)
	if _payload_active:
		var grip_row := RUNG_ROWS[GRIP_RUNG_INDEX]
		var payload_force := Vector3.DOWN * PAYLOAD_MASS * 9.8 * 0.5
		_left_segments[grip_row].apply_central_force(payload_force)
		_right_segments[grip_row].apply_central_force(payload_force)
	_update_rungs_from_rope()


func _make_rope_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = ROPE_ALBEDO
	material.albedo_color = Color(1.0, 0.94, 0.82, 1.0)
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
	right.y = 0.0
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var left_position := center - right * LADDER_WIDTH * 0.5
	var right_position := center + right * LADDER_WIDTH * 0.5
	if _top_left != null:
		_top_left.global_position = left_position
	if _top_right != null:
		_top_right.global_position = right_position
	if _last_top_center != Vector3.ZERO and delta > 0.0001:
		var measured_velocity := (center - _last_top_center) / delta
		_top_velocity = _top_velocity.lerp(measured_velocity, clampf(delta * 10.0, 0.0, 1.0))
	_last_top_center = center


func _apply_authored_deployment(progress: float) -> void:
	if _attachment == null or not is_instance_valid(_attachment):
		return
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

	for row: int in range(SEGMENT_COUNT):
		var row_delay := float(row) / float(SEGMENT_COUNT) * 0.28
		var row_progress := smoothstep(
			0.0,
			1.0,
			clampf((progress - row_delay) / maxf(1.0 - row_delay, 0.01), 0.0, 1.0)
		)
		var collapsed_depth := -0.08 * float(row + 1)
		var extended_depth := -SEGMENT_LENGTH * (float(row) + 0.5)
		var depth := lerpf(collapsed_depth, extended_depth, row_progress)
		var spread := lerpf(0.14, LADDER_WIDTH * 0.5, row_progress)
		var coil := sin(float(row) * 1.37 + float(_player_index)) * 0.18 * (1.0 - row_progress)
		var left_body := _left_segments[row]
		var right_body := _right_segments[row]
		var reveal := progress > row_delay * 0.72 + 0.015
		left_body.visible = reveal
		right_body.visible = reveal
		left_body.global_transform = Transform3D(
			_basis_from_y_axis(Vector3.UP, right),
			center - right * spread + Vector3.UP * depth + forward * coil
		)
		right_body.global_transform = Transform3D(
			_basis_from_y_axis(Vector3.UP, right),
			center + right * spread + Vector3.UP * depth - forward * coil
		)

	for rung_index: int in range(RUNG_ROWS.size()):
		var row := RUNG_ROWS[rung_index]
		var row_delay := float(row) / float(SEGMENT_COUNT) * 0.28
		var row_progress := smoothstep(
			0.0,
			1.0,
			clampf((progress - row_delay) / maxf(1.0 - row_delay, 0.01), 0.0, 1.0)
		)
		var collapsed_depth := -0.08 * float(row + 1)
		var extended_depth := -SEGMENT_LENGTH * (float(row) + 0.5)
		var depth := lerpf(collapsed_depth, extended_depth, row_progress)
		var coil := sin(float(row) * 1.37 + float(_player_index)) * 0.18 * (1.0 - row_progress)
		var rung := _rungs[rung_index]
		rung.visible = progress > row_delay * 0.72 + 0.025
		rung.global_transform = Transform3D(
			_basis_from_y_axis(right, Vector3.UP),
			center + Vector3.UP * depth + forward * coil
		)


func _release_to_physics() -> void:
	if _physics_released:
		return
	_physics_released = true
	for body: RigidBody3D in _all_dynamic_bodies():
		body.freeze = false
		body.sleeping = false
		body.linear_velocity = _top_velocity + Vector3.DOWN * 0.28
		body.angular_velocity = Vector3.ZERO
	_build_joints()


func _build_joints() -> void:
	for side_index: int in range(2):
		var anchor: AnimatableBody3D = _top_left if side_index == 0 else _top_right
		var segments: Array[RigidBody3D] = _left_segments if side_index == 0 else _right_segments
		var joint_position := anchor.global_position
		_add_pin_joint(anchor, segments[0], joint_position, "Top%d" % side_index)
		for row: int in range(1, SEGMENT_COUNT):
			joint_position = (segments[row - 1].global_position + segments[row].global_position) * 0.5
			_add_pin_joint(
				segments[row - 1],
				segments[row],
				joint_position,
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
	joint.set_param(PinJoint3D.PARAM_BIAS, 0.54)
	joint.set_param(PinJoint3D.PARAM_DAMPING, 1.85)
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
	for rung_index: int in range(_rungs.size()):
		var row := RUNG_ROWS[rung_index]
		var left_position := _left_segments[row].global_position
		var right_position := _right_segments[row].global_position
		var axis := right_position - left_position
		if axis.length_squared() <= 0.0001:
			axis = Vector3.RIGHT
		_rungs[rung_index].global_transform = Transform3D(
			_basis_from_y_axis(axis.normalized(), Vector3.UP),
			(left_position + right_position) * 0.5
		)
		_rungs[rung_index].scale = Vector3(
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
	stiffness: float = 82.0,
	damping: float = 2.8,
	maximum_force: float = 38.0
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
