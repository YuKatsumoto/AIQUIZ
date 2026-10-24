class_name GoalStandEggStrand
extends RefCounted

## A thread of thick albumen drawn out between a shell piece flying off and the
## splat it came from. It keeps its volume, so it thins as it stretches
## (r = r0 sqrt(L0 / L)), sags less the tighter it is, beads up like a string of
## pearls close to the snap, and pulls back a little on the shell piece. Once it
## snaps the splat's end recoils onto the splat. World space.

## Elastic pull on the shell piece per metre of stretch (m/s^2 / m), and its cap.
const PULL := 22.0
const PULL_MAX := 28.0
const RECOIL_TIME := 0.06
## Albumen threads do not last: past this age (s) one snaps however slack it is.
const MAX_AGE := 0.6

var rest := 0.0
var radius0 := 0.0
var snap := 0.0
var length := 0.0
var broken := false
var recoil := 1.0
var a := Vector3.ZERO
var b := Vector3.ZERO
var seed := 0.0
var age := 0.0


static func create(from: Vector3, to: Vector3, thickness: float, snap_length: float, seed_value: float) -> GoalStandEggStrand:
	var strand := GoalStandEggStrand.new()
	strand.a = from
	strand.b = to
	strand.rest = maxf(from.distance_to(to), 0.02)
	strand.length = strand.rest
	strand.radius0 = thickness
	strand.snap = maxf(snap_length, strand.rest * 2.0)
	strand.seed = seed_value
	return strand


## Advance with the splat end at `from` and the shell piece at `to`. Returns the
## pull on the shell piece (m/s^2); zero once snapped.
func step(dt: float, from: Vector3, to: Vector3) -> Vector3:
	a = from
	age += dt
	if broken:
		recoil *= exp(-dt / RECOIL_TIME)
		return Vector3.ZERO
	b = to
	length = a.distance_to(b)
	if length >= snap or age >= MAX_AGE:
		broken = true
		return Vector3.ZERO
	var stretch := maxf(0.0, length - rest)
	var dir := (a - b) / maxf(length, 0.001)
	return dir * minf(PULL * stretch, PULL_MAX)


func radius() -> float:
	return radius0 * sqrt(rest / maxf(length, rest))


## Beads on a string: 0 while slack, 1 just before the snap.
func beading() -> float:
	return smoothstep(0.55, 1.0, length / snap)


## Quadratic Bezier (p0, control, p2) and radius for drawing. A snapped strand is
## the splat's half shrinking back.
func shape() -> Dictionary:
	var end := b if not broken else a.lerp(b, 0.5 * recoil)
	var span := a.distance_to(end)
	# Slack threads hang; a tight one is nearly straight.
	var slack := clampf(1.0 - length / snap, 0.0, 1.0)
	var control := a.lerp(end, 0.5) + Vector3.DOWN * minf(0.3 * span * span + 0.03, 0.28) * (0.45 + 0.55 * slack)
	return {"p0": a, "p1": control, "p2": end, "radius": radius() * (1.0 if not broken else recoil * 1.4),
		"beading": beading() if not broken else 0.6 * recoil}


func is_done() -> bool:
	return broken and recoil < 0.05
