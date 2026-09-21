extends RefCounted

## Same Verlet / distance-constraint principle as PhysicalRopeLadder.
## Simulated in the chair frame: gravity, launch momentum, body contact and a
## receiver spring drive the free tip. No sampled flight curve drives it.
const COUNT := 24
const STEP := 1.0 / 120.0
const FIRE := .30
const LOCK := 1.95
const SETTLED := 2.50
const ITERATIONS := 18
var points := PackedVector3Array()
var previous := PackedVector3Array()
var rest := PackedVector3Array()
var lengths := PackedFloat32Array()
var tick := 0
var fired := false
var locked := false
var side := 1.0
var peak_speed := 0.0
var lock_distance := 0.0

func setup(shape: PackedVector3Array, sign_x: float) -> void:
	rest = shape
	side = sign_x
	lengths.resize(COUNT)
	for i in COUNT: lengths[i] = rest[i].distance_to(rest[i + 1])
	reset()

func reset() -> void:
	tick = 0
	fired = false
	locked = false
	peak_speed = 0.0
	lock_distance = 0.0
	points.resize(COUNT + 1)
	previous.resize(COUNT + 1)
	for i in COUNT + 1:
		points[i] = rest[0] + Vector3(0, .0001, .0002) * i
		previous[i] = points[i]

static func smooth_ratio(a: float, b: float, time: float) -> float:
	var u := clampf((time - a) / (b - a), 0.0, 1.0)
	return u * u * u * (u * (6.0 * u - 15.0) + 10.0)

func seek(time: float) -> void:
	var target := int(floor((minf(time, SETTLED) + .000001) / STEP))
	if target < tick: reset()
	while tick < target:
		tick += 1
		_step(tick * STEP)

func kick(index: int, velocity: Vector3) -> void:
	# Also used by acceptance to prove that momentum propagates down the chain.
	previous[index] -= velocity * STEP

func _step(time: float) -> void:
	if time < FIRE: return
	if not fired:
		fired = true
		for i in range(1, COUNT + 1):
			kick(i, Vector3(side * .12, 2.5, 2.9) * float(i) / COUNT)
	var payout := smooth_ratio(FIRE, .82, time)
	var docking := smooth_ratio(.95, 1.65, time)
	var tighten := smooth_ratio(LOCK, SETTLED, time)
	if time >= LOCK and not locked:
		lock_distance = points[COUNT].distance_to(rest[COUNT])
		locked = true
	for i in range(1, COUNT + 1):
		var velocity := ((points[i] - previous[i]) / STEP).limit_length(7.0)
		peak_speed = maxf(peak_speed, velocity.length())
		var acceleration := Vector3.DOWN * 9.81
		if time < .74:
			acceleration += Vector3(0, 45.0, 50.0) * (float(i) / COUNT) * (1.0 - smooth_ratio(.55, .74, time))
		if i == COUNT and time < .68:
			# A brief powered launch pays material off the reel. Applying only
			# one impulse to a still-coiled chain would be eaten by its constraints.
			acceleration += Vector3(side * 1.8, 70.0, 65.0) * (1.0 - smooth_ratio(.52, .68, time))
		# A narrow reel guides sideways drift; the Y/Z chain remains dynamic.
		acceleration.x += (rest[i].x - points[i].x) * 42.0 - velocity.x * 3.5
		if i == COUNT and not locked:
			# The seat receiver draws the free tongue into its mouth, as a damped
			# physical spring, only after the initial ballistic throw.
			acceleration += ((rest[COUNT] - points[i]) * 420.0 - velocity * 38.0 + Vector3.UP * 9.81) * docking
		if locked:
			acceleration += ((rest[i] - points[i]) * 380.0 - velocity * 30.0) * tighten
		previous[i] = points[i]
		points[i] += velocity * exp(-1.15 * STEP) * STEP + acceleration * STEP * STEP
	for iteration in ITERATIONS:
		points[0] = rest[0]
		if locked: points[COUNT] = rest[COUNT]
		for i in COUNT:
			var offset := points[i + 1] - points[i]
			var distance := offset.length()
			if distance < .000001: continue
			var span := lengths[i] * maxf(.001, payout) * lerpf(1.08, 1.0, tighten)
			var correction := offset * ((distance - span) / distance)
			var a := 0.0 if i == 0 else 1.0
			var b := 0.0 if locked and i + 1 == COUNT else (.35 if i + 1 == COUNT else 1.0)
			points[i] += correction * a / (a + b)
			points[i + 1] -= correction * b / (a + b)
		for i in range(1, COUNT + 1):
			if locked and i == COUNT: continue
			points[i].x = clampf(points[i].x, rest[i].x - .025, rest[i].x + .025)
			points[i] = _collide_body(points[i], tighten)
	# Once the winch is fully tensioned, the body supports the strip along the
	# measured contact route. Blend this support in during the last .25 s.
	var supported := smooth_ratio(2.25, SETTLED, time)
	if supported > 0.0:
		for i in range(1, COUNT): points[i] = points[i].lerp(rest[i], supported)
	points[0] = rest[0]
	if locked: points[COUNT] = rest[COUNT]

func _collide_body(p: Vector3, tighten: float) -> Vector3:
	# Conservative soft contact shells for the rounded torso and head tips.
	# The exact measured surface becomes the support as the winch tightens.
	var result := _outside_ellipsoid(p, Vector3(0,1.73,-.22), Vector3(.425,.375,.425))
	for sign_x in [-1.0, 1.0]:
		result = _outside_ellipsoid(result, Vector3(sign_x * .17,2.15,-.22), Vector3(.135,.145,.15))
	return result.lerp(p, tighten)

func _outside_ellipsoid(p: Vector3, center: Vector3, radius: Vector3) -> Vector3:
	# Keep the belt in its reel's narrow channel while resolving the rounded
	# body in the Y/Z section; radial X projection would throw it off the side.
	var section := 1.0 - pow((p.x - center.x) / radius.x, 2.0)
	if section <= .0: return p
	var radii := Vector2(radius.y, radius.z) * sqrt(section)
	var q := Vector2(p.y - center.y, p.z - center.z) / radii
	var distance := q.length()
	if distance >= 1.075: return p
	var yz := q.normalized() * radii * 1.075 if distance > .00001 else Vector2(0, radii.y * 1.075)
	return Vector3(p.x, center.y + yz.x, center.z + yz.y)

func sample(u: float) -> Vector3:
	var f := clampf(u, 0.0, 1.0) * COUNT
	var i := mini(int(f), COUNT - 1)
	return points[i].cubic_interpolate(points[i + 1], points[maxi(0,i - 1)], points[mini(COUNT,i + 2)], f - i)
