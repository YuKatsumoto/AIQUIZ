extends Node
class_name SawCatchRagdoll

## A slipping tooth catch drives the existing physical body; detached limbs keep
## their transforms and momentum. No teleports or replacement fragment meshes.
const RELEASE_START := 0.52
const RELEASE_STEP := 0.14
var elapsed := 0.0
var finished := false
var released: Dictionary = {}
var release_events: Array[Dictionary] = []
var blade_index := -1
var bodies: Dictionary
var joints: Dictionary
var saw: SawChaseController
var _origin := Vector3.ZERO
var _start_offset := Vector3.ZERO
var _last_target := Vector3.ZERO
var _angle := 0.0
var _groups: Array[Array] = []

func setup(rag: Dictionary, carriage: SawChaseController) -> void:
	bodies = rag.get("bodies", {})
	joints = rag.get("joints", {})
	saw = carriage
	var torso := bodies.get("torso") as RigidBody3D
	if torso == null:
		finished = true
		return
	if is_instance_valid(saw):
		blade_index = saw.nearest_blade(torso.global_position)
		_origin = saw.blade_center(blade_index)
	else:
		_origin = torso.global_position - Vector3(0.0, 0.4, 1.0)
	_start_offset = torso.global_position - _origin
	_angle = atan2(_start_offset.z, _start_offset.x)
	_last_target = torso.global_position
	var near_left := (bodies.l_thigh as RigidBody3D).global_position.distance_squared_to(_origin) < (bodies.r_thigh as RigidBody3D).global_position.distance_squared_to(_origin)
	var near_side := "l_" if near_left else "r_"
	var far_side := "r_" if near_left else "l_"
	_groups = [
		[near_side + "thigh", near_side + "calf", near_side + "foot"],
		[near_side + "upp_arm", near_side + "low_arm", near_side + "hand"],
		[far_side + "thigh", far_side + "calf", far_side + "foot"],
		[far_side + "upp_arm", far_side + "low_arm", far_side + "hand"],
		["head"],
	]
	for key: String in bodies:
		if key == "anchor": continue
		var body := bodies[key] as RigidBody3D
		body.gravity_scale = 1.0
		body.collision_mask |= SawChaseState.WALL_COLLISION_LAYER
		body.continuous_cd = true
		body.sleeping = false
		body.linear_damp = 0.45
		body.angular_damp = 0.65
		body.linear_velocity = (_origin - torso.global_position).normalized() * 1.6
		body.angular_velocity = Vector3(-1.5, -2.5, 0.5)

func _physics_process(dt: float) -> void:
	if finished: return
	elapsed += dt
	if is_instance_valid(saw) and blade_index >= 0:
		_origin = saw.blade_center(blade_index)
	# The trunk is pulled across the teeth while its unconstrained limbs lag and
	# fold. Slip limits the body's turn to an arc instead of matching blade RPM.
	var draw_in := smoothstep(0.06, 0.42, elapsed)
	var turn := maxf(0.0, elapsed - 0.10) * 2.8
	# Spin_Loop rotates -Y in Godot, i.e. increasing atan2(z, x).
	var radial := Vector3(cos(_angle + turn), 0.0, sin(_angle + turn))
	var caught_offset := radial * 0.78 + Vector3.UP * 0.24
	var target := _origin + _start_offset.lerp(caught_offset, draw_in)
	var target_velocity := ((target - _last_target) / maxf(dt, 0.001)).limit_length(10.0)
	_last_target = target
	var torso := bodies.get("torso") as RigidBody3D
	if is_instance_valid(torso):
		var acceleration := (target - torso.global_position) * 105.0 + (target_velocity - torso.linear_velocity) * 16.0 + Vector3.UP * 9.8
		torso.apply_central_force(acceleration.limit_length(95.0) * torso.mass)
		torso.apply_torque(Vector3(-5.0, -5.0, 2.0) - torso.angular_velocity * 1.6)
	for i: int in _groups.size():
		if elapsed >= RELEASE_START + RELEASE_STEP * i:
			_release_group(_groups[i], i)
	if elapsed >= SawChaseState.CUT_SCATTER_DELAY:
		finish()

func _release_group(keys: Array, order: int) -> void:
	if released.has(keys[0]): return
	# Remove only the shoulder/hip first, leaving the limb recognizable in flight.
	_disconnect(str(keys[0]))
	var primary := bodies.get(keys[0]) as RigidBody3D
	var radial := (primary.global_position - _origin) if is_instance_valid(primary) else Vector3.RIGHT
	radial.y = 0.0
	radial = radial.normalized() if radial.length_squared() > 0.01 else Vector3.RIGHT
	var tangent := Vector3(-radial.z, 0.0, radial.x)
	for key: String in keys:
		released[key] = true
		var body := bodies.get(key) as RigidBody3D
		if not is_instance_valid(body): continue
		body.linear_damp = 0.12
		body.angular_damp = 0.18
		body.linear_velocity = body.linear_velocity.limit_length(4.5) + tangent * (3.0 + order * 0.35) + radial * 2.0 + Vector3.UP * (3.2 + order * 0.25)
		body.angular_velocity = Vector3(2.0, -5.0, -2.5) * (1.0 if order % 2 == 0 else -1.0)
	release_events.append({"part":keys[0], "time":elapsed})

func _disconnect(key: String) -> void:
	var joint := joints.get(key) as Joint3D
	if is_instance_valid(joint):
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		joint.queue_free()
	joints.erase(key)

func finish() -> void:
	if finished: return
	for i: int in _groups.size():
		_release_group(_groups[i], i)
	for key: String in joints.keys():
		_disconnect(key)
	var torso := bodies.get("torso") as RigidBody3D
	if is_instance_valid(torso):
		torso.linear_velocity = torso.linear_velocity.limit_length(5.0) + Vector3.UP * 2.5
	finished = true
	set_physics_process(false)
