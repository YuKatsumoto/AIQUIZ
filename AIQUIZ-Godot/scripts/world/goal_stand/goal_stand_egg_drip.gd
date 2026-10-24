class_name GoalStandEggDrip
extends RefCounted

## A drop hanging off an edge of whatever the egg hit, fed by a splat (a rivulet
## that reached the edge, the sheet wrapped over it, or a lip of the thick dome):
## - GROW: liquid comes down into a pendant drop until it weighs Tate's volume;
## - NECK: its weight draws out a thread that thins as it lengthens (it keeps its
##   volume). Thin albumen pinches off fast, the thick gel and the yolk hang on a long
##   thread first;
## - the thread snaps: the drop falls, a satellite droplet from the thread's middle
##   falls after it, and the stub left on the edge recoils into a bead (RECOIL);
## then it grows again while the splat still sends liquid.
## The hanging drop lags behind the edge on a damped spring, so it swings when the
## body it hangs from moves. World space; the contents draws it from shape().

enum Kind { THIN, THICK, YOLK }
enum Phase { GROW, NECK, RECOIL, DONE }

## Per kind: radius of the edge it tears off (m, Tate), extra hold of the gel,
## thread time constant (s), thread length at the snap (m), thread radius over the drop's.
const KINDS := {
	Kind.THIN: {"orifice": 0.016, "hold": 1.0, "tau": 0.09, "snap": Vector2(0.035, 0.07), "thread": 0.42},
	Kind.THICK: {"orifice": 0.03, "hold": 2.4, "tau": 0.5, "snap": Vector2(0.14, 0.38), "thread": 0.3},
	Kind.YOLK: {"orifice": 0.022, "hold": 1.4, "tau": 0.26, "snap": Vector2(0.07, 0.14), "thread": 0.36},
}
const SWING_OMEGA := 9.0
const SWING_ZETA := 0.35
const RECOIL_TIME := 0.035
## A drop left with too little to fall soaks back into the film over this long.
const SOAK_TIME := 0.5

var kind := Kind.THIN
var phase := Phase.GROW
var supply := 0.0
var flux := 0.0
var volume := 0.0
var thread_length := 0.0
var thread_radius := 0.0
var stub := 0.0
var anchor := Vector3.ZERO
var bulb := Vector3.ZERO
var bulb_velocity := Vector3.ZERO
var drops := 0
var age := 0.0

var _rheology: GoalStandEggRheology
var _l0 := 0.0
var _a0 := 0.0
var _neck_time := 0.0
var _snap := 0.0
var _soak := 0.0
var _rng := RandomNumberGenerator.new()


static func create(model: GoalStandEggRheology, drip_kind: Kind, at: Vector3, supply_volume: float, feed: float, seed_value: int) -> GoalStandEggDrip:
	var drip := GoalStandEggDrip.new()
	drip._rheology = model
	drip.kind = drip_kind
	drip.anchor = at
	drip.bulb = at
	drip.supply = supply_volume
	drip.flux = maxf(feed, supply_volume / 3.0)
	drip._rng.seed = seed_value
	return drip


func add_supply(more: float, feed: float) -> void:
	supply += more
	flux = maxf(flux, feed)
	if phase == Phase.DONE:
		phase = Phase.GROW


func critical_volume() -> float:
	var spec: Dictionary = KINDS[kind]
	return _rheology.tate_volume(float(spec.orifice)) * float(spec.hold)


func bulb_radius() -> float:
	return GoalStandEggRheology.sphere_radius(volume)


## Advance by `dt` with the edge now at `edge` (world). Falling drops are appended
## to `events` as {type: "fall", position, velocity, radius, kind}.
func step(dt: float, edge: Vector3, events: Array[Dictionary]) -> void:
	age += dt
	var edge_velocity := (edge - anchor) / maxf(dt, 0.0001)
	anchor = edge
	var spec: Dictionary = KINDS[kind]
	match phase:
		Phase.GROW:
			var inflow := minf(flux * dt, supply)
			volume += inflow
			supply -= inflow
			if volume >= critical_volume():
				_begin_neck(spec)
			elif supply <= 0.0:
				if volume >= critical_volume() * 0.4:
					_begin_neck(spec)
				else:
					_soak += dt
					volume *= exp(-dt / SOAK_TIME)
					if _soak > SOAK_TIME * 3.0 or volume < 1.0e-7:
						phase = Phase.DONE
		Phase.NECK:
			var inflow := minf(flux * 0.5 * dt, supply)
			volume += inflow
			supply -= inflow
			_neck_time += dt
			thread_length = GoalStandEggRheology.thread_length(_l0, _neck_time, float(spec.tau))
			thread_radius = GoalStandEggRheology.thread_radius(_a0, _l0, thread_length)
			if thread_length >= _snap:
				_pinch(events, edge_velocity)
		Phase.RECOIL:
			stub *= exp(-dt / RECOIL_TIME)
			if stub < 0.003:
				stub = 0.0
				thread_length = 0.0
				phase = Phase.GROW if supply > 0.0 else Phase.DONE
	_swing(dt, edge_velocity)


func _begin_neck(spec: Dictionary) -> void:
	phase = Phase.NECK
	var r := bulb_radius()
	_l0 = r * 0.35
	_a0 = r * float(spec.thread)
	_neck_time = 0.0
	thread_length = _l0
	thread_radius = _a0
	_snap = _rng.randf_range((spec.snap as Vector2).x, (spec.snap as Vector2).y)


func _pinch(events: Array[Dictionary], edge_velocity: Vector3) -> void:
	var spec: Dictionary = KINDS[kind]
	var stretch_rate := thread_length / float(spec.tau)
	var velocity := bulb_velocity + Vector3.DOWN * stretch_rate * 0.6
	events.append({"type": "fall", "position": bulb, "velocity": velocity, "radius": bulb_radius(), "kind": kind})
	# The thread's middle beads up into a satellite droplet.
	var satellite := maxf(thread_radius * 1.7, 0.004)
	var middle := anchor.lerp(bulb, 0.5)
	events.append({"type": "fall", "position": middle, "velocity": edge_velocity * 0.5 + velocity * 0.4, "radius": satellite, "kind": kind})
	drops += 1
	stub = thread_length * 0.4
	volume = 0.0
	phase = Phase.RECOIL
	bulb = anchor
	bulb_velocity = edge_velocity


## The hanging drop trails its edge on a damped spring (it swings, then settles).
func _swing(dt: float, edge_velocity: Vector3) -> void:
	var r := bulb_radius()
	var reach := (thread_length if phase == Phase.NECK else 0.0) + r * 0.9
	var target := anchor + Vector3.DOWN * reach
	var offset := bulb - target
	bulb_velocity += (-SWING_OMEGA * SWING_OMEGA * offset - 2.0 * SWING_ZETA * SWING_OMEGA * (bulb_velocity - edge_velocity)) * dt
	bulb += bulb_velocity * dt
	# The thread does not stretch sideways: keep the drop at its length from the edge.
	var hang := bulb - anchor
	if hang.length() > reach and reach > 0.0:
		bulb = anchor + hang.normalized() * reach


## Drawing: (thread length, thread radius, drop radius, base radius) along the axis
## from the edge to the drop. RECOIL draws the retracting stub with its bead.
func shape() -> Vector4:
	match phase:
		Phase.GROW:
			var r := bulb_radius()
			return Vector4(0.0, r * 0.5, r, r * 0.75)
		Phase.NECK:
			var r := bulb_radius()
			var base := lerpf(r * 0.75, thread_radius * 2.4, clampf(_neck_time / 0.15, 0.0, 1.0))
			return Vector4(thread_length, thread_radius, r, base)
		Phase.RECOIL:
			var bead := maxf(thread_radius * 1.6, 0.004)
			return Vector4(stub, thread_radius, bead, bead * 1.2)
	return Vector4.ZERO


## Unit direction from the edge toward the hanging drop.
func axis() -> Vector3:
	var hang := bulb - anchor
	return hang.normalized() if hang.length() > 0.001 else Vector3.DOWN


func is_done() -> bool:
	return phase == Phase.DONE
