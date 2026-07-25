extends Node3D
class_name MamaChariVisual

const BIKE_SCENE: PackedScene = preload("res://TripoModels/city_utility_bicycle_3d_model/city_utility_bicycle_3d_model.fbx")
const BIKE_RULES_SCRIPT = preload("res://scripts/core/bike_race_rules.gd")
const BIKE_COURSE_SCRIPT = preload("res://scripts/world/bike_course.gd")
const BIKE_SCALE: float = 1.8

@export_range(1, 2, 1) var player_index: int = 1

var _bike_body: RigidBody3D
var _lean_root: Node3D
var _model_pivot: Node3D
var _wheel_blurs: Array[MeshInstance3D] = []
var _ragdoll_bodies: Array[RigidBody3D] = []
var _ragdoll_joints: Array[Joint3D] = []
var _ragdoll_torso: RigidBody3D
var _ragdoll_head: RigidBody3D
var _ragdoll_left_arm: RigidBody3D
var _ragdoll_right_arm: RigidBody3D
var _ragdoll_left_leg: RigidBody3D
var _ragdoll_right_leg: RigidBody3D
var _visual_time: float = 0.0
var _built: bool = false
var _last_recovery_state: String = ""
var _last_crash_revision: int = -1


func _ready() -> void:
	visible = false
	position = Vector3.ZERO
	build_visual()


func configure(index: int) -> void:
	player_index = clampi(index, 1, 2)
	if is_inside_tree():
		build_visual()


func build_visual() -> void:
	if _built:
		_update_player_plate()
		return
	_built = true
	_build_bike_body()
	_build_ragdoll_bodies()
	_build_wheel_blur()
	_build_player_plate()


func _build_bike_body() -> void:
	_bike_body = _make_physics_body("BikePhysicsBody", 18.0)
	_bike_body.gravity_scale = 1.18
	_bike_body.linear_damp = 0.24
	_bike_body.angular_damp = 0.20
	add_child(_bike_body)

	var bike_collision := CollisionShape3D.new()
	bike_collision.name = "BikeCollision"
	var bike_shape := BoxShape3D.new()
	bike_shape.size = Vector3(0.78, 0.82, 1.72)
	bike_collision.shape = bike_shape
	bike_collision.position = Vector3(0.0, 0.52, 0.0)
	_bike_body.add_child(bike_collision)

	_lean_root = Node3D.new()
	_lean_root.name = "LeanRoot"
	_bike_body.add_child(_lean_root)

	_model_pivot = Node3D.new()
	_model_pivot.name = "TripoBikePivot"
	_model_pivot.rotation.y = PI * 0.5
	_model_pivot.scale = Vector3.ONE * BIKE_SCALE
	_lean_root.add_child(_model_pivot)
	var bike_model: Node = BIKE_SCENE.instantiate()
	bike_model.name = "TripoMamaChari"
	_model_pivot.add_child(bike_model)


func _build_ragdoll_bodies() -> void:
	var body_color: Color = _player_color()
	var limb_color: Color = body_color.darkened(0.12)
	var skin_color := Color(0.92, 0.69, 0.48)

	_ragdoll_torso = _create_box_ragdoll_body(
		"RagdollTorso",
		Vector3(0.58, 0.78, 0.34),
		body_color,
		22.0
	)
	_ragdoll_head = _create_sphere_ragdoll_body(
		"RagdollHead",
		0.23,
		skin_color,
		5.0
	)
	_ragdoll_left_arm = _create_box_ragdoll_body(
		"RagdollLeftArm",
		Vector3(0.17, 0.70, 0.17),
		limb_color,
		4.5
	)
	_ragdoll_right_arm = _create_box_ragdoll_body(
		"RagdollRightArm",
		Vector3(0.17, 0.70, 0.17),
		limb_color,
		4.5
	)
	_ragdoll_left_leg = _create_box_ragdoll_body(
		"RagdollLeftLeg",
		Vector3(0.21, 0.82, 0.22),
		limb_color.darkened(0.25),
		8.0
	)
	_ragdoll_right_leg = _create_box_ragdoll_body(
		"RagdollRightLeg",
		Vector3(0.21, 0.82, 0.22),
		limb_color.darkened(0.25),
		8.0
	)


func _make_physics_body(body_name: String, body_mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = body_name
	body.mass = body_mass
	body.gravity_scale = 1.0
	body.linear_damp = 0.30
	body.angular_damp = 0.22
	body.continuous_cd = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.collision_layer = 2
	body.collision_mask = 1
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.36
	physics_material.bounce = 0.06
	body.physics_material_override = physics_material
	return body


func _create_box_ragdoll_body(
	body_name: String,
	size: Vector3,
	color: Color,
	body_mass: float
) -> RigidBody3D:
	var body: RigidBody3D = _make_physics_body(body_name, body_mass)
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(color)
	body.add_child(visual)
	body.visible = false
	_ragdoll_bodies.append(body)
	return body


func _create_sphere_ragdoll_body(
	body_name: String,
	radius: float,
	color: Color,
	body_mass: float
) -> RigidBody3D:
	var body: RigidBody3D = _make_physics_body(body_name, body_mass)
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	visual.mesh = mesh
	visual.material_override = _material(color)
	body.add_child(visual)
	body.visible = false
	_ragdoll_bodies.append(body)
	return body


func update_from_state(gs: QuizGameState, dt: float) -> void:
	visible = (
		gs.game_state == Constants.STATE_ATHLETIC_RACE
		and gs.race_phase == Constants.RACE_PHASE_BIKE
	)
	if not visible:
		_freeze_all_physics()
		return

	position = Vector3.ZERO
	_visual_time += dt
	var px: float = gs.player_x if player_index == 1 else gs.player2_x
	var pz: float = gs.player_z if player_index == 1 else gs.player2_z
	var speed: float = gs.bike_p1_speed if player_index == 1 else gs.bike_p2_speed
	var steer: float = gs.bike_p1_steer if player_index == 1 else gs.bike_p2_steer
	var wobble: float = gs.bike_p1_wobble if player_index == 1 else gs.bike_p2_wobble
	var recovery_state: String = (
		gs.bike_p1_recovery_state if player_index == 1 else gs.bike_p2_recovery_state
	)
	var crash_revision: int = (
		gs.bike_p1_crash_revision if player_index == 1 else gs.bike_p2_crash_revision
	)
	var crash_strength: float = (
		gs.bike_p1_crash_strength if player_index == 1 else gs.bike_p2_crash_strength
	)
	var relative_z: float = pz - gs.bike_start_z
	var course_height: float = BIKE_COURSE_SCRIPT.get_course_height(relative_z)
	var course_pitch: float = BIKE_COURSE_SCRIPT.get_course_pitch(relative_z)
	var bike_position := Vector3(
		px,
		BIKE_RULES_SCRIPT.COURSE_SURFACE_Y + course_height,
		pz - gs.world_scroll_z
	)

	if (
		recovery_state == BIKE_RULES_SCRIPT.RIDER_TUMBLING
		and crash_revision != _last_crash_revision
	):
		_start_physics_crash(
			bike_position,
			course_pitch,
			crash_strength,
			crash_revision
		)

	if recovery_state == BIKE_RULES_SCRIPT.RIDER_RIDING:
		_update_riding_visual(
			bike_position,
			course_pitch,
			speed,
			steer,
			wobble,
			dt
		)
	elif recovery_state == BIKE_RULES_SCRIPT.RIDER_TUMBLING:
		_lean_root.rotation = Vector3.ZERO
		_sync_physics_to_state(gs)

	for blur: MeshInstance3D in _wheel_blurs:
		blur.visible = (
			recovery_state == BIKE_RULES_SCRIPT.RIDER_RIDING
			and speed > 2.2
		)
		if blur.visible:
			blur.rotation.x = fmod(blur.rotation.x + speed * dt / 0.34, TAU)

	_last_recovery_state = recovery_state


func _update_riding_visual(
	bike_position: Vector3,
	course_pitch: float,
	speed: float,
	steer: float,
	wobble: float,
	dt: float
) -> void:
	if _last_recovery_state != BIKE_RULES_SCRIPT.RIDER_RIDING:
		_clear_ragdoll_joints()
		_freeze_ragdoll(true)
		_bike_body.freeze = true
		_bike_body.linear_velocity = Vector3.ZERO
		_bike_body.angular_velocity = Vector3.ZERO
	_bike_body.freeze = true
	_bike_body.global_transform = Transform3D(Basis.IDENTITY, bike_position)

	var speed_ratio: float = clampf(
		speed / BIKE_RULES_SCRIPT.BOOST_MAX_SPEED,
		0.0,
		1.0
	)
	var wobble_wave: float = (
		sin(_visual_time * lerpf(5.0, 12.0, speed_ratio) + float(player_index))
		* wobble
	)
	var target_lean: float = clampf(
		-steer * lerpf(0.08, 0.27, speed_ratio) + wobble_wave * 0.16,
		-0.48,
		0.48
	)
	_lean_root.rotation.x = lerp_angle(
		_lean_root.rotation.x,
		course_pitch,
		minf(1.0, dt * 10.0)
	)
	_lean_root.rotation.z = lerp_angle(
		_lean_root.rotation.z,
		target_lean,
		minf(1.0, dt * 12.0)
	)
	_lean_root.rotation.y = lerp_angle(
		_lean_root.rotation.y,
		steer * 0.085,
		minf(1.0, dt * 6.0)
	)


func _start_physics_crash(
	bike_position: Vector3,
	course_pitch: float,
	crash_strength: float,
	crash_revision: int
) -> void:
	_last_crash_revision = crash_revision
	_clear_ragdoll_joints()
	var side: float = 1.0 if player_index == 1 else -1.0
	if absf(bike_position.x) > 0.15:
		side = signf(bike_position.x)
	var strength: float = clampf(crash_strength, 0.45, 1.25)
	var crash_basis := Basis(Vector3.RIGHT, course_pitch)

	_bike_body.freeze = true
	_bike_body.global_transform = Transform3D(
		crash_basis,
		bike_position + Vector3(0.0, 0.22, 0.0)
	)
	_place_ragdoll_for_crash(bike_position, crash_basis)
	_build_ragdoll_joints(bike_position)

	_bike_body.freeze = false
	_bike_body.sleeping = false
	_bike_body.linear_velocity = Vector3(
		side * (2.0 + strength * 1.2),
		3.0 + strength * 1.5,
		4.5 + strength * 2.8
	)
	_bike_body.angular_velocity = Vector3(
		4.2 + strength * 2.5,
		-side * (1.0 + strength),
		-side * (5.8 + strength * 3.2)
	)
	_bike_body.apply_impulse(
		Vector3(
			side * (2.8 + strength * 2.0),
			2.2 + strength * 1.2,
			4.0 + strength * 2.5
		),
		Vector3(0.0, 0.42, -0.50)
	)

	for index: int in range(_ragdoll_bodies.size()):
		var body: RigidBody3D = _ragdoll_bodies[index]
		# Physics proxies drive the original rider. They must never replace its appearance.
		body.visible = false
		body.freeze = false
		body.sleeping = false
		body.linear_velocity = _bike_body.linear_velocity + Vector3(
			side * (float(index % 2) - 0.5) * 0.7,
			0.5 + float(index) * 0.06,
			0.6 + float(index) * 0.08
		)
		body.angular_velocity = Vector3(
			side * (3.5 + float(index) * 0.8),
			-1.5 + float(index) * 0.55,
			-side * (4.0 + float(index) * 0.9)
		)


func _place_ragdoll_for_crash(bike_position: Vector3, crash_basis: Basis) -> void:
	var poses: Array[Vector3] = [
		Vector3(0.0, 1.30, -0.03),
		Vector3(0.0, 1.88, 0.02),
		Vector3(-0.40, 1.34, 0.02),
		Vector3(0.40, 1.34, 0.02),
		Vector3(-0.19, 0.70, -0.05),
		Vector3(0.19, 0.70, -0.05),
	]
	for index: int in range(_ragdoll_bodies.size()):
		var body: RigidBody3D = _ragdoll_bodies[index]
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.global_transform = Transform3D(
			crash_basis,
			bike_position + crash_basis * poses[index]
		)


func _build_ragdoll_joints(bike_position: Vector3) -> void:
	var saddle_joint := PinJoint3D.new()
	saddle_joint.name = "BikePelvisJoint"
	add_child(saddle_joint)
	saddle_joint.global_position = bike_position + Vector3(0.0, 0.92, -0.02)
	saddle_joint.node_a = saddle_joint.get_path_to(_bike_body)
	saddle_joint.node_b = saddle_joint.get_path_to(_ragdoll_torso)
	saddle_joint.set_param(PinJoint3D.PARAM_BIAS, 0.82)
	saddle_joint.set_param(PinJoint3D.PARAM_DAMPING, 1.7)
	saddle_joint.exclude_nodes_from_collision = true
	_ragdoll_joints.append(saddle_joint)

	_add_limb_joint(
		"NeckJoint",
		_ragdoll_torso,
		_ragdoll_head,
		bike_position + Vector3(0.0, 1.66, 0.0),
		0.42,
		0.26
	)
	_add_limb_joint(
		"LeftShoulderJoint",
		_ragdoll_torso,
		_ragdoll_left_arm,
		bike_position + Vector3(-0.29, 1.50, 0.0),
		1.05,
		0.72
	)
	_add_limb_joint(
		"RightShoulderJoint",
		_ragdoll_torso,
		_ragdoll_right_arm,
		bike_position + Vector3(0.29, 1.50, 0.0),
		1.05,
		0.72
	)
	_add_limb_joint(
		"LeftHipJoint",
		_ragdoll_torso,
		_ragdoll_left_leg,
		bike_position + Vector3(-0.18, 1.00, -0.03),
		0.82,
		0.52
	)
	_add_limb_joint(
		"RightHipJoint",
		_ragdoll_torso,
		_ragdoll_right_leg,
		bike_position + Vector3(0.18, 1.00, -0.03),
		0.82,
		0.52
	)


func _add_limb_joint(
	joint_name: String,
	parent_body: RigidBody3D,
	child_body: RigidBody3D,
	anchor: Vector3,
	swing_span: float,
	twist_span: float
) -> void:
	var joint := ConeTwistJoint3D.new()
	joint.name = joint_name
	add_child(joint)
	joint.global_position = anchor
	joint.node_a = joint.get_path_to(parent_body)
	joint.node_b = joint.get_path_to(child_body)
	joint.swing_span = swing_span
	joint.twist_span = twist_span
	joint.bias = 0.42
	joint.softness = 0.78
	joint.relaxation = 1.15
	joint.exclude_nodes_from_collision = true
	_ragdoll_joints.append(joint)


func _clear_ragdoll_joints() -> void:
	for joint: Joint3D in _ragdoll_joints:
		if is_instance_valid(joint):
			joint.queue_free()
	_ragdoll_joints.clear()


func _freeze_ragdoll(hide_visuals: bool) -> void:
	for body: RigidBody3D in _ragdoll_bodies:
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		if hide_visuals:
			body.visible = false


func _freeze_all_physics() -> void:
	if _bike_body != null:
		_bike_body.freeze = true
	_freeze_ragdoll(true)
	_clear_ragdoll_joints()


func _sync_physics_to_state(gs: QuizGameState) -> void:
	if _bike_body == null:
		return
	var bike_world := _bike_body.global_position
	if player_index == 1:
		gs.bike_p1_bike_x = bike_world.x
		gs.bike_p1_bike_z = bike_world.z + gs.world_scroll_z
		gs.player_x = gs.bike_p1_bike_x
		gs.player_z = gs.bike_p1_bike_z
	else:
		gs.bike_p2_bike_x = bike_world.x
		gs.bike_p2_bike_z = bike_world.z + gs.world_scroll_z
		gs.player2_x = gs.bike_p2_bike_x
		gs.player2_z = gs.bike_p2_bike_z


func get_rider_visual_transform() -> Dictionary:
	var active: bool = (
		_last_recovery_state == BIKE_RULES_SCRIPT.RIDER_TUMBLING
		and _ragdoll_torso != null
		and is_instance_valid(_ragdoll_torso)
	)
	if not active:
		return {
			"active": false,
			"hide_original": false,
		}

	# Keep the authored rider visible and transfer the invisible physics proxy pose
	# onto it. The rider root is centered on the torso in the authored skeleton.
	var torso_transform: Transform3D = _ragdoll_torso.global_transform.orthonormalized()
	return {
		"active": true,
		"hide_original": false,
		"transform": torso_transform,
		"head_basis": _relative_ragdoll_basis(_ragdoll_head),
		"left_arm_basis": _relative_ragdoll_basis(_ragdoll_left_arm),
		"right_arm_basis": _relative_ragdoll_basis(_ragdoll_right_arm),
		"left_leg_basis": _relative_ragdoll_basis(_ragdoll_left_leg),
		"right_leg_basis": _relative_ragdoll_basis(_ragdoll_right_leg),
		"left_arm_spin": _ragdoll_left_arm.angular_velocity,
		"right_arm_spin": _ragdoll_right_arm.angular_velocity,
		"left_leg_spin": _ragdoll_left_leg.angular_velocity,
		"right_leg_spin": _ragdoll_right_leg.angular_velocity,
	}


func _relative_ragdoll_basis(body: RigidBody3D) -> Basis:
	if body == null or not is_instance_valid(body):
		return Basis.IDENTITY
	return (
		_ragdoll_torso.global_transform.basis.inverse()
		* body.global_transform.basis
	).orthonormalized()


func get_ragdoll_debug_state() -> Dictionary:
	var max_distance: float = 0.0
	if _bike_body != null:
		for body: RigidBody3D in _ragdoll_bodies:
			max_distance = maxf(
				max_distance,
				body.global_position.distance_to(_bike_body.global_position)
			)
	return {
		"active": _last_recovery_state == BIKE_RULES_SCRIPT.RIDER_TUMBLING,
		"body_count": _ragdoll_bodies.size(),
		"joint_count": _ragdoll_joints.size(),
		"max_distance": max_distance,
		"bike_speed": _bike_body.linear_velocity.length() if _bike_body != null else 0.0,
		"bike_angular_speed": _bike_body.angular_velocity.length() if _bike_body != null else 0.0,
	}


func get_visual_lean() -> float:
	if _last_recovery_state == BIKE_RULES_SCRIPT.RIDER_TUMBLING:
		return 0.0
	return _lean_root.rotation.z if _lean_root != null else 0.0


func get_visual_pitch() -> float:
	return _lean_root.rotation.x if _lean_root != null else 0.0


func _build_wheel_blur() -> void:
	var blur_material: StandardMaterial3D = _material(
		Color(0.55, 0.82, 1.0, 0.19),
		true
	)
	for z_pos: float in [-0.72, 0.72]:
		var blur := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.37
		mesh.bottom_radius = 0.37
		mesh.height = 0.018
		mesh.radial_segments = 28
		blur.mesh = mesh
		blur.material_override = blur_material
		blur.rotation.z = PI * 0.5
		blur.position = Vector3(0.0, 0.37, z_pos)
		blur.visible = false
		_lean_root.add_child(blur)
		_wheel_blurs.append(blur)


func _build_player_plate() -> void:
	var plate := Label3D.new()
	plate.name = "PlayerPlate"
	plate.text = "P%d" % player_index
	plate.font_size = 38
	plate.pixel_size = 0.009
	plate.modulate = _player_color()
	plate.outline_modulate = Color(0.02, 0.03, 0.05)
	plate.outline_size = 8
	plate.position = Vector3(0.0, 1.05, 0.84)
	plate.rotation.y = PI
	_lean_root.add_child(plate)


func _update_player_plate() -> void:
	var plate: Label3D = (
		_lean_root.get_node_or_null("PlayerPlate") as Label3D
		if _lean_root != null
		else null
	)
	if plate != null:
		plate.text = "P%d" % player_index
		plate.modulate = _player_color()


func _player_color() -> Color:
	return (
		Color(1.0, 0.48, 0.12)
		if player_index == 1
		else Color(0.16, 0.62, 1.0)
	)


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	if transparent or color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
