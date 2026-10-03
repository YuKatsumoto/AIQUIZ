class_name FloodTumble
extends Node

## The loser of the buzzer duel, gone under with their lift tower (docs/sudden_death_underground.md 6.6).
## Like the saw's SawCatchRagdoll it drives the limp ragdoll: the current drags the body downstream (+Z,
## toward the duel camera), buoys it in the foam band and rolls it; after SINK_FROM seconds it is pulled
## under and at VANISH_AT it is gone (hidden).

const FLOW_SPEED := 4.5
## How quickly the bodies take the current's speed (1/s).
const DRAG := 2.4
## Spring toward the foam band (height of the body centre over the floor), per metre of depth.
const BUOYANCY := 7.0
const FOAM_BAND := 0.9
const SINK_FROM := 0.8
const VANISH_AT := 1.2
const TUMBLE_TORQUE := 2.6

var _bodies: Array[RigidBody3D] = []
var _container: Node3D = null
var _floor_y := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


## [param bodies]: the ragdoll's RigidBody3D parts; [param container] is hidden at the end;
## [param floor_y]: world height of the floor under the body.
func setup(bodies: Array[RigidBody3D], container: Node3D, floor_y: float, seed_value: int = 0) -> void:
	_bodies = bodies
	_container = container
	_floor_y = floor_y
	_rng.seed = seed_value
	for body: RigidBody3D in _bodies:
		body.gravity_scale = 1.0
		body.linear_damp = 0.3
		body.angular_damp = 0.6


func is_gone() -> bool:
	return _time >= VANISH_AT


func _physics_process(delta: float) -> void:
	_time += delta
	var sinking := _time > SINK_FROM
	for body: RigidBody3D in _bodies:
		if not is_instance_valid(body):
			continue
		var velocity := body.linear_velocity
		var force := Vector3(-velocity.x * 0.8, 0.0, FLOW_SPEED - velocity.z) * DRAG * body.mass
		var depth := (_floor_y + FOAM_BAND) - body.global_position.y
		if sinking:
			# Under the surface: the current pulls it down out of sight.
			force.y -= body.mass * 16.0
		else:
			force.y += body.mass * (9.8 * 0.85 + depth * BUOYANCY) - velocity.y * body.mass * 1.2
		body.apply_central_force(force)
		var torque := Vector3(_rng.randf_range(0.6, 1.0), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.5, 0.5))
		body.apply_torque(torque * TUMBLE_TORQUE * body.mass)
	if _time >= VANISH_AT:
		if is_instance_valid(_container):
			_container.visible = false
		for body: RigidBody3D in _bodies:
			if is_instance_valid(body):
				body.freeze = true
		set_physics_process(false)
