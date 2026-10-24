class_name GoalStandEggSplat
extends RefCounted

## One splat of raw egg on a surface, as a small physics model. No nodes: the
## contents (GoalStandEggContents) draws it from write_row() and the yolk state.
##
## Coordinates are the splat plane: q = (x, y) along the frame's X and Z axes, and
## the surface normal is the frame's +Y. A real egg filmed close, with the constants
## carried to this egg's size by GoalStandEggRheology:
## - impact: the thin albumen shoots out as a sheet, fastest along the throw, with
##   fingers whose tips shed spray, and stops within 35-70 ms;
## - recoil: the thick albumen gel springs back from its overshoot and the yolk
##   rebounds from flat with one or two overshoots;
## - gravity (steep faces only): the thin film gathers into rivulets that run down
##   and drip off the face's edge, the thick dome creeps and stops as it thins, and
##   the yolk slides through the white once its weight beats the white's hold.
## Volume is booked: what leaves as spray, rivulets and drips is taken off the film.
##
## Box faces fold over their rounded edges (the sheet wraps onto the side faces),
## capsules roll the sheet around their axis. surface() maps a plane point to the
## frame the same way the white shader does.

enum Kind { SPLAT, PUDDLE }
enum Wrap { PLANE, BOX, CAPSULE }

const RIM := 48
const MAX_YOLKS := 3
const MAX_RIVULETS := 3
## Texels per row of the contents' data texture: 48 rim radii, then the header.
const ROW_TEXELS := 59
const HEADER := 48
## The egg's footprint when it bursts (m); the sheet starts there.
const START_RADIUS := 0.085
## Rounded box edges (m): the sheet bends over them instead of creasing. Small, so
## the film's own lift keeps it off the sharp corner of the box underneath.
const EDGE_ROUND := 0.005
## After the sheet the pinned rim backs off this much (thin film keeps ~96 %).
const RIM_PIN := 0.965
const RIM_RELAX := 5.0
## Rim surface tension (1/s): rounds off the outline while the rim is still wet and
## mobile, until SMOOTH_UNTIL; after that the contact line is pinned and the
## fingers stay, as on a real splat.
const RIM_SMOOTHING := 2.5
const SMOOTH_UNTIL := 0.35
## Thick albumen: overshoot over its rest radius, time to the peak, recoil spring.
const THICK_OVERSHOOT := 1.16
const THICK_PEAK_TIME := 0.055
const THICK_OMEGA := 15.0
const THICK_ZETA := 0.5
## Slopes steeper than this (sin) let the white and the yolk run.
const STEEP := 0.3
## Rivulet width (m) and the wet trail it leaves, as a share of the film.
const RIVULET_WIDTH := Vector2(0.03, 0.05)
const RIVULET_TRAIL := 0.3
const RIVULET_FEED_TIME := 0.6
## A yolk stream is thicker than the white's rivulets (real 4-5 mm) and its contact
## line drags far less; it leaves a thick orange trail.
const YOLK_STREAM_HEIGHT := 0.028
const YOLK_STREAM_PINNING := 0.5
const YOLK_STREAM_TRAIL := 0.009
## Liquid still coming down a rivulet that reached the edge goes to its drip in batches (m^3).
const EDGE_BATCH := 1.0e-4
## Yolk: hold on the surface (m/s^2), drag inside the thick dome and in the film (1/s).
const YOLK_STICK := Vector2(5.0, 12.0)
const YOLK_DRAG_THICK := 7.0
const YOLK_DRAG_THIN := 2.6
const YOLK_SLIDE := 0.55
## A torn yolk drains (share of its volume per second) and its sac collapses.
const YOLK_TEAR_TIME := 0.2
const YOLK_DRAIN := 0.5
const SLEEP_SPEED := 0.003
## The fast sheet is stepped at 1/120 s for this long; after it, everything left
## (recoil, creep, the yolk's wobble) is slow enough for one step a frame.
const FINE_STEPS_UNTIL := 0.25
## Liquid only drips off an edge it reaches heading at least this steeply across it.
const DRIP_EDGE := 0.6

var rheology: GoalStandEggRheology
var kind := Kind.SPLAT
var wrap := Wrap.PLANE
## Face bounds in the plane (min x, max x, min y, max y) and the box depth behind
## the face, or the capsule radius.
var extents := Vector4(-INF, INF, -INF, INF)
var depth := 0.0
var seed := 0.0
var age := 0.0
var awake := true
## Drawn opacity (the contents fades evicted splats out).
var alpha := 1.0
## A puddle of spilt yolk rather than white (drawn opaque orange).
var yolk_pool := false

var rim := PackedFloat32Array()
var rim_speed := PackedFloat32Array()
var rim_decel := PackedFloat32Array()
var rim_pin := PackedFloat32Array()
var _spray_at := PackedByteArray()
var thin_volume := 0.0
var film := 0.0
var thick_volume := 0.0
var thick_center := Vector2.ZERO
var thick_radius := 0.0
var thick_speed := 0.0
var thick_decel := 0.0
var thick_rest := 0.0
var thick_recoil := false
var thick_height := 0.0
var thick_shape := Vector4.ZERO
var thick_travel := 0.0
var thick_dripped := false
var rim_dripped := false
## Each yolk: pos, vel (plane), radius, volume, volume0, flatten/flatten_vel (axial
## mode), stretch/stretch_vel (lateral mode along `axis`), sag (plane), stick, tear
## (-1 intact, 0..1 opening), deflate, seed.
var yolks: Array[Dictionary] = []
## Each rivulet: start, dir (plane), length, width, volume (head), supply, feed,
## height, trail, seed, yolk, edge (reached the face's edge), done.
var rivulets: Array[Dictionary] = []
## White handed to spray, rivulets and drips so far, and yolk run out of a tear.
var emitted := 0.0
var yolk_emitted := 0.0

## Unit directions of the rim samples (shared by every splat).
static var _dirs: PackedVector2Array = _make_dirs()
var _gravity_seen := Vector2.ZERO
var _area := 0.0
var _search := 0
var _pending_edge := {}
var _rng := RandomNumberGenerator.new()


## `impact`: normal_speed (m/s, magnitude), tangential (plane m/s), reach (m),
## wrap, extents, depth, yolks (count), rupture (bool), seed (int), share (of an egg).
static func create(model: GoalStandEggRheology, impact: Dictionary, splat_kind: Kind = Kind.SPLAT) -> GoalStandEggSplat:
	var splat := GoalStandEggSplat.new()
	splat.rheology = model
	splat.kind = splat_kind
	splat.wrap = int(impact.get("wrap", Wrap.PLANE)) as Wrap
	splat.extents = impact.get("extents", Vector4(-INF, INF, -INF, INF))
	splat.depth = float(impact.get("depth", 0.0))
	splat._rng.seed = int(impact.get("seed", 1))
	splat.seed = splat._rng.randf()
	splat.rim.resize(RIM)
	splat.rim_speed.resize(RIM)
	splat.rim_decel.resize(RIM)
	splat.rim_pin.resize(RIM)
	splat._spray_at.resize(RIM)
	var share := float(impact.get("share", 1.0))
	if splat_kind == Kind.PUDDLE:
		splat.thin_volume = float(impact.get("volume", 0.0))
		splat._launch_puddle(float(impact.get("normal_speed", 1.0)))
	else:
		splat.thin_volume = model.thin_volume * share
		splat.thick_volume = model.thick_volume * share
		splat._launch(impact)
		for index in range(int(impact.get("yolks", 1))):
			splat._add_yolk(Vector2.ZERO, impact, bool(impact.get("rupture", false)) and index == 0)
	splat._update_heights()
	return splat


static func _make_dirs() -> PackedVector2Array:
	var dirs := PackedVector2Array()
	for index in range(RIM):
		dirs.append(Vector2.from_angle(TAU * index / RIM))
	return dirs


# ------------------------------------------------------------------ impact

func _launch(impact: Dictionary) -> void:
	var normal_speed := absf(float(impact.get("normal_speed", 10.0)))
	var tangential: Vector2 = impact.get("tangential", Vector2.ZERO)
	var reach := float(impact.get("reach", 0.32))
	var glance := clampf(tangential.length() / maxf(Vector2(normal_speed, tangential.length()).length(), 0.001), 0.0, 1.0)
	var throw_dir := tangential.normalized() if tangential.length() > 0.05 else Vector2.RIGHT
	# Broad lobes, and fingers of random spacing, width and length that grow with
	# the impact speed (a real splat's rim breaks up irregularly).
	var lobes: Array[Vector3] = []
	for _index in range(4):
		lobes.append(Vector3(_rng.randi_range(2, 7), _rng.randf() * TAU, _rng.randf_range(0.02, 0.09)))
	var finger_amp := clampf((normal_speed - 6.0) / 14.0, 0.0, 1.0) * 0.36
	var fingers: Array[Vector3] = []
	for _index in range(_rng.randi_range(9, 17)):
		fingers.append(Vector3(_rng.randf() * TAU, _rng.randf_range(0.035, 0.11), pow(_rng.randf(), 1.6)))
	for index in range(RIM):
		var angle := TAU * index / RIM
		var d := _dirs[index]
		var along := d.dot(throw_dir)
		var throw := 1.0 + 0.9 * glance * maxf(along, 0.0) - 0.35 * glance * maxf(-along, 0.0)
		var lobe := 1.0
		for wave: Vector3 in lobes:
			lobe += wave.z * sin(wave.x * angle + wave.y)
		var finger := 0.0
		for spike: Vector3 in fingers:
			var off := absf(angle_difference(angle, spike.x))
			finger += spike.z * exp(-pow(off / spike.y, 2.0))
		finger *= finger_amp * (1.0 + 0.6 * glance * maxf(along, 0.0))
		var target := reach * lobe * throw * (1.0 + finger)
		var v0 := (0.62 + 0.4 * finger) * normal_speed * sqrt(target / reach) + 0.35 * maxf(0.0, tangential.dot(d))
		_aim_sheet(index, START_RADIUS, target, v0)
		_spray_at[index] = 1 if finger_amp > 0.0 and finger > 0.5 * finger_amp else 0
	thick_rest = clampf(2.35 * rheology.yolk_radius, 0.12, 0.3) * sqrt(maxf(thick_volume / rheology.thick_volume, 0.05))
	thick_radius = START_RADIUS * 0.8
	var peak := thick_rest * THICK_OVERSHOOT
	thick_speed = 2.0 * (peak - thick_radius) / THICK_PEAK_TIME
	thick_decel = thick_speed * thick_speed / (2.0 * maxf(peak - thick_radius, 0.01))
	thick_center = throw_dir * 0.18 * glance * thick_rest
	var lean := 1.0 + glance
	thick_shape = Vector4(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf_range(0.06, 0.1) * lean, _rng.randf_range(0.03, 0.06) * lean)


func _launch_puddle(speed: float) -> void:
	var settle := sqrt(thin_volume / (PI * rheology.puddle_height()))
	var lobes := Vector2(_rng.randi_range(3, 6), _rng.randf() * TAU)
	for index in range(RIM):
		var angle := TAU * index / RIM
		var target := settle * 1.12 * (1.0 + 0.08 * sin(lobes.x * angle + lobes.y))
		_aim_sheet(index, settle * 0.3, target, 0.55 * speed + 0.4)


## Sheet kinematics for one rim angle: from `from` out to `target`, starting at `v0`
## and braking evenly so it stops right there.
func _aim_sheet(index: int, from: float, target: float, v0: float) -> void:
	rim[index] = from
	rim_speed[index] = maxf(v0, 0.05)
	rim_decel[index] = rim_speed[index] * rim_speed[index] / (2.0 * maxf(target - from, 0.005))
	# While the sheet runs, the pin is where it stops; then the film backs off from it.
	rim_pin[index] = target


func _add_yolk(at: Vector2, impact: Dictionary, rupture: bool) -> void:
	var normal_speed := absf(float(impact.get("normal_speed", 10.0)))
	var tangential: Vector2 = impact.get("tangential", Vector2.ZERO)
	var glance := clampf(tangential.length() / maxf(Vector2(normal_speed, tangential.length()).length(), 0.001), 0.0, 1.0)
	var dir := tangential.normalized() if tangential.length() > 0.05 else Vector2.RIGHT
	var radius := rheology.yolk_radius * _rng.randf_range(0.93, 1.05)
	var volume := 4.0 / 3.0 * PI * pow(radius, 3.0)
	yolks.append({"pos": at + dir * 0.03 * glance, "vel": dir * clampf(tangential.length() * 0.05, 0.0, 0.9),
		"radius": radius, "volume": volume, "volume0": volume,
		"flatten": -clampf(normal_speed / 60.0, 0.12, 0.34), "flatten_vel": 0.0,
		"stretch": 0.3 * glance, "stretch_vel": 0.0, "axis": dir.angle(), "sag": Vector2.ZERO,
		"stick": _rng.randf_range(YOLK_STICK.x, YOLK_STICK.y), "tear": 0.0 if rupture else -1.0,
		"deflate": 0.0, "seed": _rng.randf()})


## Another egg lands on this splat (`at`, plane): its volume joins, the rim is
## pushed out from the new impact and the splat wakes. Returns false when full.
func absorb(at: Vector2, impact: Dictionary) -> bool:
	var share := float(impact.get("share", 1.0))
	var normal_speed := absf(float(impact.get("normal_speed", 10.0)))
	var reach := float(impact.get("reach", 0.3))
	if kind == Kind.PUDDLE:
		thin_volume += float(impact.get("volume", 0.0))
		reach = sqrt(thin_volume / (PI * rheology.puddle_height())) * 1.1
		normal_speed = maxf(normal_speed, 1.0)
	else:
		thin_volume += rheology.thin_volume * share
		var old := thick_volume
		thick_volume += rheology.thick_volume * share
		thick_center = thick_center.lerp(at, rheology.thick_volume * share / maxf(thick_volume, 0.0001))
		thick_rest *= sqrt(thick_volume / maxf(old, 0.0001))
		thick_recoil = true
	for index in range(RIM):
		var angle := TAU * index / RIM
		var d := _dirs[index]
		# Where the new splat's circle crosses this rim direction.
		var b := at.dot(d)
		var c := at.length_squared() - reach * reach
		var disc := b * b - c
		if disc <= 0.0:
			continue
		var target := b + sqrt(disc)
		if target > rim[index] + 0.01:
			var from := rim[index]
			_aim_sheet(index, from, target, 0.5 * normal_speed)
	if kind == Kind.SPLAT and int(impact.get("yolks", 1)) > 0:
		if yolks.size() >= MAX_YOLKS:
			# The new egg bursts the oldest yolk instead of adding one.
			var oldest: Dictionary = yolks[0]
			if float(oldest.tear) < 0.0:
				oldest.tear = 0.0
		else:
			var rupture := bool(impact.get("rupture", false))
			for yolk: Dictionary in yolks:
				if (yolk.pos as Vector2).distance_to(at) < float(yolk.radius) and float(yolk.tear) < 0.0:
					yolk.tear = 0.0
					rupture = true
			_add_yolk(at, impact, rupture)
	awake = true
	return true


# ------------------------------------------------------------------ stepping

## Advance by `dt`. `gravity` is gravity in the splat plane (m/s^2). Events (spray,
## drips off the edge, yolks that let go) are appended to `events`.
func step(dt: float, gravity: Vector2, events: Array[Dictionary]) -> void:
	if not awake:
		# A tilting body (the loser kneels, sinks) can start things running again.
		if gravity.distance_to(_gravity_seen) > 1.5:
			awake = true
		else:
			return
	var steps := int(ceilf(dt / (1.0 / 120.0))) if age < FINE_STEPS_UNTIL else maxi(1, int(ceilf(dt / (1.0 / 30.0))))
	var h := dt / steps
	for _index in range(steps):
		_step(h, gravity, events)
	_gravity_seen = gravity


func _step(dt: float, gravity: Vector2, events: Array[Dictionary]) -> void:
	age += dt
	var g := gravity.length()
	var sin_theta := clampf(g / GoalStandEggRheology.GRAVITY, 0.0, 1.0)
	var down := gravity / g if g > 0.01 else Vector2.ZERO
	var rim_moving := _step_rim(dt, events)
	var moving := _step_thick(dt, sin_theta, down, events) or rim_moving
	_update_heights(rim_moving or age < SMOOTH_UNTIL)
	if kind == Kind.SPLAT:
		if sin_theta > STEEP and age > 0.1:
			# Looking for where the film gathers is not worth doing every step.
			_search += 1
			if _search % 4 == 0:
				_start_rivulets(sin_theta, down)
			_drip_over_edge(down)
		moving = _step_rivulets(dt, sin_theta, down, events) or moving
		moving = _step_yolks(dt, gravity, sin_theta, down, events) or moving
	if not moving and age > 0.5:
		awake = false


## The sheet, then the pinned film backing off and its outline smoothing.
func _step_rim(dt: float, events: Array[Dictionary]) -> bool:
	var moving := false
	var relax := 1.0 - exp(-RIM_RELAX * dt)
	for index in range(RIM):
		if rim_speed[index] > 0.0:
			var v := rim_speed[index]
			rim[index] += v * dt
			rim_speed[index] = v - rim_decel[index] * dt
			moving = true
			if rim_speed[index] <= 0.0 or rim[index] >= rim_pin[index]:
				rim[index] = minf(rim[index], rim_pin[index])
				rim_speed[index] = 0.0
				rim_pin[index] = rim[index] * RIM_PIN
				if _spray_at[index] == 1:
					_spray_at[index] = 0
					var angle := TAU * index / RIM
					var d := _dirs[index]
					events.append({"type": "spray", "q": d * rim[index], "dir": d, "speed": v + rim_decel[index] * 0.04})
		elif absf(rim[index] - rim_pin[index]) > 0.0005:
			rim[index] += (rim_pin[index] - rim[index]) * relax
			moving = true
	if age > 0.08 and age < SMOOTH_UNTIL:
		var smoothed := rim.duplicate()
		for index in range(RIM):
			if rim_speed[index] > 0.0:
				continue
			var lap := rim[(index + RIM - 1) % RIM] + rim[(index + 1) % RIM] - 2.0 * rim[index]
			smoothed[index] = rim[index] + RIM_SMOOTHING * dt * lap
			rim_pin[index] += RIM_SMOOTHING * dt * lap
		rim = smoothed
	return moving


func _step_thick(dt: float, sin_theta: float, down: Vector2, events: Array[Dictionary]) -> bool:
	if thick_volume <= 0.0:
		return false
	var moving := false
	if not thick_recoil:
		thick_radius += thick_speed * dt
		thick_speed -= thick_decel * dt
		moving = true
		if thick_speed <= 0.0:
			thick_speed = 0.0
			thick_recoil = true
	else:
		var s := GoalStandEggRheology.oscillator_step(thick_radius, thick_speed, thick_rest, THICK_OMEGA, THICK_ZETA, dt)
		thick_radius = s.x
		thick_speed = s.y
		moving = absf(thick_speed) > 0.001 or absf(thick_radius - thick_rest) > 0.001
	# The gel creeps down a steep face and stops as the dome thins out.
	if age > 0.1 and sin_theta > STEEP and not thick_dripped:
		var u := rheology.thick_creep_speed(thick_height, sin_theta)
		if u > 0.0005:
			moving = true
			var run := u * dt
			thick_center += down * run
			thick_travel += run
			var keep := exp(-run / rheology.thick_creep_run)
			thin_volume += thick_volume * (1.0 - keep)
			thick_volume *= keep
			var edge := _edge_distance(thick_center, down)
			if edge < thick_radius * 0.55:
				# The lip of the dome hangs over the edge: a gob of gel drips off.
				thick_dripped = true
				var supply := thick_volume * 0.4
				thick_volume -= supply
				emitted += supply
				events.append({"type": "edge", "kind": GoalStandEggDrip.Kind.THICK, "q": thick_center + down * edge,
					"supply": supply, "flux": supply / 1.6})
	# The film always covers the dome (only worth checking while the dome moves).
	if not moving:
		return false
	for index in range(RIM):
		var angle := TAU * index / RIM
		var d := _dirs[index]
		var need := (thick_center.dot(d) + thick_radius * (1.0 + absf(thick_shape.z) + absf(thick_shape.w))) * 1.04
		if rim[index] < need:
			rim[index] = need
			rim_pin[index] = maxf(rim_pin[index], need)
	return moving


func _start_rivulets(sin_theta: float, down: Vector2) -> void:
	var live := 0
	var streams := 0
	for rivulet: Dictionary in rivulets:
		live += 0 if bool(rivulet.yolk) else 1
		streams += 1 if bool(rivulet.yolk) else 0
	# A yolk stream keeps its slot: the white gets what is left.
	var wanted := mini(MAX_RIVULETS - streams, 1 + int(sin_theta * 2.2))
	if live >= wanted or thin_volume <= rheology.thin_volume * 0.08:
		return
	# The film gathers at the lowest lobes of the outline.
	var best := -1
	var best_score := 0.0
	for index in range(RIM):
		var angle := TAU * index / RIM
		var d := _dirs[index]
		var facing := d.dot(down)
		if facing < 0.55 or rim_speed[index] > 0.0:
			continue
		if rim[index] < rim[(index + RIM - 1) % RIM] or rim[index] < rim[(index + 1) % RIM]:
			continue
		var taken := false
		for rivulet: Dictionary in rivulets:
			taken = taken or (rivulet.start as Vector2).normalized().dot(d) > cos(TAU / 12.0)
		var score := facing * rim[index]
		if not taken and score > best_score:
			best_score = score
			best = index
	if best < 0:
		return
	var d := _dirs[best]
	_add_rivulet(d * rim[best] * 0.96, (down * 0.8 + d * 0.2).normalized(), thin_volume * _rng.randf_range(0.1, 0.18), false)


## Only MAX_RIVULETS are drawn (the first ones): a yolk stream goes in front, and
## if the slots are full it takes the place of a white rivulet.
func _add_rivulet(start: Vector2, dir: Vector2, supply: float, yolk: bool) -> void:
	if not yolk and rivulets.size() >= MAX_RIVULETS:
		return
	if yolk and rivulets.size() >= MAX_RIVULETS:
		for index in range(rivulets.size() - 1, -1, -1):
			if not bool(rivulets[index].yolk):
				rivulets.remove_at(index)
				break
		if rivulets.size() >= MAX_RIVULETS:
			return
	if not yolk:
		thin_volume -= supply
		emitted += supply
	rivulets.insert(0 if yolk else rivulets.size(), {"start": start, "dir": dir, "length": 0.0, "width": _rng.randf_range(RIVULET_WIDTH.x, RIVULET_WIDTH.y) * (1.25 if yolk else 1.0),
		"volume": 0.0, "supply": supply, "feed": supply / RIVULET_FEED_TIME, "height": 0.0, "trail": YOLK_STREAM_TRAIL if yolk else film * RIVULET_TRAIL,
		"seed": _rng.randf(), "yolk": yolk, "edge": false, "done": false})


func _step_rivulets(dt: float, sin_theta: float, down: Vector2, events: Array[Dictionary]) -> bool:
	var moving := false
	for rivulet: Dictionary in rivulets:
		if bool(rivulet.done):
			continue
		var fed := minf(float(rivulet.feed) * dt, float(rivulet.supply))
		rivulet.supply = float(rivulet.supply) - fed
		var width := float(rivulet.width)
		if bool(rivulet.edge):
			# Over the edge: what still comes down feeds the drip hanging there.
			rivulet.pending = float(rivulet.get("pending", 0.0)) + fed
			if float(rivulet.pending) > EDGE_BATCH or (float(rivulet.supply) <= 0.0 and float(rivulet.pending) > 0.0):
				events.append({"type": "edge", "kind": GoalStandEggDrip.Kind.YOLK if bool(rivulet.yolk) else GoalStandEggDrip.Kind.THIN,
					"q": (rivulet.start as Vector2) + (rivulet.dir as Vector2) * float(rivulet.length), "supply": float(rivulet.pending), "flux": float(rivulet.feed)})
				rivulet.pending = 0.0
			rivulet.done = float(rivulet.supply) <= 0.0 and not bool(rivulet.yolk)
			moving = moving or float(rivulet.supply) > 0.0
			continue
		rivulet.volume = float(rivulet.volume) + fed
		var yolk := bool(rivulet.yolk)
		var tallest := YOLK_STREAM_HEIGHT if yolk else maxf(film, 0.004) * 1.8
		var head := clampf(float(rivulet.volume) / (width * width * 2.4), 0.0, tallest)
		rivulet.height = head
		var nu := rheology.yolk_nu if yolk else rheology.thin_nu
		var pinning := YOLK_STREAM_PINNING if yolk else GoalStandEggRheology.FILM_PINNING
		var u := pinning * GoalStandEggRheology.GRAVITY * sin_theta * head * head / (3.0 * nu)
		u *= maxf((rivulet.dir as Vector2).dot(down), 0.0)
		if u < 0.002 and float(rivulet.supply) <= 0.0 and float(rivulet.volume) < width * width * 0.002:
			rivulet.done = true
			continue
		moving = true
		var run := u * dt
		var reach := _edge_distance(rivulet.start, rivulet.dir)
		if float(rivulet.length) + run >= reach:
			rivulet.length = reach
			rivulet.edge = true
			var supply := float(rivulet.volume) + float(rivulet.supply)
			rivulet.supply = 0.0
			rivulet.volume = 0.0
			events.append({"type": "edge", "kind": GoalStandEggDrip.Kind.YOLK if bool(rivulet.yolk) else GoalStandEggDrip.Kind.THIN,
				"q": (rivulet.start as Vector2) + (rivulet.dir as Vector2) * reach, "supply": supply, "flux": maxf(float(rivulet.feed), supply / 1.2)})
			continue
		rivulet.length = float(rivulet.length) + run
		rivulet.volume = maxf(0.0, float(rivulet.volume) - run * width * float(rivulet.trail))
	return moving


## Once: where the sheet itself wrapped over the lower edge, the film drips off it.
func _drip_over_edge(down: Vector2) -> void:
	if rim_dripped or wrap == Wrap.PLANE:
		return
	var angle := down.angle()
	var reach := rim_at(angle)
	var edge := _edge_distance(Vector2.ZERO, down)
	if reach < edge + 0.02:
		return
	rim_dripped = true
	var supply := thin_volume * 0.1
	thin_volume -= supply
	emitted += supply
	_pending_edge = {"type": "edge", "kind": GoalStandEggDrip.Kind.THIN, "q": down * edge, "supply": supply, "flux": supply / 2.0}



func _step_yolks(dt: float, gravity: Vector2, sin_theta: float, down: Vector2, events: Array[Dictionary]) -> bool:
	if not _pending_edge.is_empty():
		events.append(_pending_edge)
		_pending_edge = {}
	var moving := false
	for index in range(yolks.size() - 1, -1, -1):
		var yolk: Dictionary = yolks[index]
		var omega := rheology.yolk_omega
		var f := GoalStandEggRheology.oscillator_step(float(yolk.flatten), float(yolk.flatten_vel), _yolk_rest_flatten(yolk), omega, GoalStandEggRheology.YOLK_DAMPING_RATIO, dt)
		yolk.flatten = f.x
		yolk.flatten_vel = f.y
		var s := GoalStandEggRheology.oscillator_step(float(yolk.stretch), float(yolk.stretch_vel), 0.0, omega * 1.3, GoalStandEggRheology.YOLK_DAMPING_RATIO, dt)
		yolk.stretch = s.x
		yolk.stretch_vel = s.y
		# Quasi-static lean of the drop toward downhill (sessile to pendant).
		yolk.sag = (yolk.sag as Vector2).lerp(down * sin_theta * 0.24, 1.0 - exp(-6.0 * dt))
		var radius := float(yolk.radius)
		var pos: Vector2 = yolk.pos
		var vel: Vector2 = yolk.vel
		var pull := maxf(0.0, gravity.length() - float(yolk.stick)) * YOLK_SLIDE
		var inside := pos.distance_to(thick_center) < thick_radius
		var drag := YOLK_DRAG_THICK if inside else YOLK_DRAG_THIN
		vel += (down * pull - vel * drag) * dt
		pos += vel * dt
		var released := false
		var limit := rim_at(pos.angle()) - radius * 0.35
		if pos.length() > limit and pos.length() > 0.001:
			if pull > 0.0:
				released = true
			else:
				pos = pos.normalized() * limit
				vel = Vector2.ZERO
		if pull > 0.0 and _edge_distance(pos, down) < radius * 0.25:
			released = true
		yolk.pos = pos
		yolk.vel = vel
		if float(yolk.tear) >= 0.0:
			_step_tear(yolk, dt, sin_theta, down)
		if released:
			events.append({"type": "yolk", "yolk": yolk, "q": pos, "vel": vel})
			yolks.remove_at(index)
			moving = true
			continue
		var still := vel.length() < SLEEP_SPEED and absf(float(yolk.flatten) - _yolk_rest_flatten(yolk)) < 0.004 \
			and absf(float(yolk.flatten_vel)) < 0.02 and absf(float(yolk.stretch)) < 0.004
		var draining := float(yolk.tear) >= 0.0 and float(yolk.tear) < 1.0
		moving = moving or not still or draining
	return moving


## Rest shape of the axial mode: a torn yolk's sac slumps flat.
func _yolk_rest_flatten(yolk: Dictionary) -> float:
	return -0.55 * float(yolk.deflate)


func _step_tear(yolk: Dictionary, dt: float, sin_theta: float, down: Vector2) -> void:
	yolk.tear = minf(1.0, float(yolk.tear) + dt / YOLK_TEAR_TIME)
	var volume0 := float(yolk.volume0)
	if sin_theta > STEEP:
		# Yolk runs out of the tear as a stream down the face.
		var drained := minf(float(yolk.volume) - volume0 * 0.35, volume0 * YOLK_DRAIN * dt)
		if drained > 0.0:
			yolk.volume = float(yolk.volume) - drained
			yolk_emitted += drained
			var stream: Dictionary = yolk.get("stream_rivulet", {})
			if stream.is_empty() or bool(stream.done):
				_add_rivulet((yolk.pos as Vector2) + down * float(yolk.radius) * 0.7, down, 0.0, true)
				stream = rivulets.front() if not rivulets.is_empty() and bool(rivulets.front().yolk) else {}
				yolk.stream_rivulet = stream
			if not stream.is_empty():
				stream.supply = float(stream.supply) + drained
				stream.feed = maxf(float(stream.feed), volume0 * YOLK_DRAIN)
		yolk.deflate = clampf(1.0 - float(yolk.volume) / volume0, 0.0, 0.65) / 0.65
	else:
		# On the flat the yolk spills out of its sac into a low yellow pool.
		yolk.deflate = minf(1.0, float(yolk.deflate) + dt / 0.6)


## Film and dome heights from their volumes; the rim's area is only re-measured
## while the rim moves.
func _update_heights(rim_changed: bool = true) -> void:
	if rim_changed or _area <= 0.0:
		_area = polygon_area()
	film = thin_volume / maxf(_area, 0.001)
	if kind == Kind.PUDDLE:
		film = minf(film, rheology.puddle_height())
	thick_height = thick_volume / maxf(GoalStandEggRheology.dome_volume(thick_radius, 1.0), 0.0001) if thick_volume > 0.0 else 0.0


# ------------------------------------------------------------------ geometry

## Area inside the rim outline (m^2).
func polygon_area() -> float:
	var area := 0.0
	var step := TAU / RIM
	for index in range(RIM):
		area += 0.5 * rim[index] * rim[(index + 1) % RIM] * sin(step)
	return area


## Rim radius at `angle`, Catmull-Rom through the samples (as the shader draws it).
func rim_at(angle: float) -> float:
	var x := fposmod(angle / TAU, 1.0) * RIM
	var i1 := int(floorf(x)) % RIM
	var p0 := rim[(i1 + RIM - 1) % RIM]
	var p1 := rim[i1]
	var p2 := rim[(i1 + 1) % RIM]
	var p3 := rim[(i1 + 2) % RIM]
	var t := x - floorf(x)
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)))


func mean_radius() -> float:
	var total := 0.0
	for radius in rim:
		total += radius
	return total / RIM


## Distance from `from` along `dir` (plane) to where the liquid drips off the face:
## an edge it crosses heading downward (over a side edge it just wraps on round the
## side face), or the underside of a capsule. INF on a plane.
func _edge_distance(from: Vector2, dir: Vector2) -> float:
	if wrap == Wrap.PLANE or dir.length() < 0.01:
		return INF
	var best := INF
	if wrap == Wrap.BOX:
		var bounds := [Vector2(extents.x, extents.y), Vector2(extents.z, extents.w)]
		for axis in range(2):
			var d := dir[axis]
			if absf(d) < DRIP_EDGE:
				continue
			var bound: float = (bounds[axis] as Vector2).y if d > 0.0 else (bounds[axis] as Vector2).x
			best = minf(best, maxf(0.0, (bound - from[axis]) / d))
	else:
		# Around a capsule the liquid hangs off its underside (half way round).
		var bottom := PI * depth * 0.92
		if absf(dir.y) > 0.0001:
			best = maxf(0.0, ((bottom if dir.y > 0.0 else -bottom) - from.y) / dir.y)
	return best


## Frame-local position and normal of plane point `q` at height `h` over the
## surface, wrapped the way the white shader wraps it.
func surface(q: Vector2, h: float = 0.0) -> Dictionary:
	return GoalStandEggSplat.wrap_point(wrap, extents, depth, q, h)


## Frame-local position only (no normal), without building a dictionary.
func surface_position(q: Vector2, h: float = 0.0) -> Vector3:
	if wrap == Wrap.PLANE:
		return Vector3(q.x, h, q.y)
	return wrap_point(wrap, extents, depth, q, h).position


static func wrap_point(wrap_mode: int, bounds: Vector4, deep: float, q: Vector2, h: float) -> Dictionary:
	if wrap_mode == Wrap.CAPSULE:
		var a := clampf(q.y / maxf(deep, 0.01), -PI * 0.95, PI * 0.95)
		var n := Vector3(0.0, cos(a), sin(a))
		return {"position": Vector3(q.x, (deep + h) * cos(a) - deep, (deep + h) * sin(a)), "normal": n}
	if wrap_mode == Wrap.PLANE:
		return {"position": Vector3(q.x, h, q.y), "normal": Vector3.UP}
	var fx := _fold(q.x, bounds.x, bounds.y, deep)
	var fz := _fold(q.y, bounds.z, bounds.w, deep)
	var normal := Vector3(fx.z, fx.w * fz.w, fz.z).normalized()
	return {"position": Vector3(fx.x, -fx.y - fz.y, fz.x) + normal * h, "normal": normal}


## One axis of the box fold: (coordinate, drop below the face, normal sin, normal cos).
static func _fold(x: float, lo: float, hi: float, deep: float) -> Vector4:
	var r := EDGE_ROUND
	var over := 0.0
	var side := 1.0
	var edge := 0.0
	if x > hi - r:
		over = x - (hi - r)
		edge = hi - r
	elif x < lo + r:
		over = (lo + r) - x
		edge = lo + r
		side = -1.0
	else:
		return Vector4(x, 0.0, 0.0, 1.0)
	var arc := r * PI * 0.5
	if over < arc:
		var a := over / r
		return Vector4(edge + side * r * sin(a), r * (1.0 - cos(a)), side * sin(a), cos(a))
	var down := minf(over - arc, maxf(deep - r, 0.0))
	return Vector4(edge + side * r, r + down, side, 0.0)


# ------------------------------------------------------------------ drawing data

## Write this splat into row `row` of the contents' data texture (RGBA floats).
func write_row(data: PackedFloat32Array, row: int) -> void:
	var base := row * ROW_TEXELS * 4
	for index in range(RIM):
		data[base + index * 4] = rim[index]
	var header := base + HEADER * 4
	data[header] = film
	data[header + 1] = thick_height if thick_volume > 0.0 else 0.0
	data[header + 2] = alpha
	data[header + 3] = seed
	data[header + 4] = thick_center.x
	data[header + 5] = thick_center.y
	data[header + 6] = thick_radius
	data[header + 7] = float(wrap)
	# Open bounds (a plane) are stored as a large finite number.
	data[header + 8] = clampf(extents.x, -1.0e6, 1.0e6)
	data[header + 9] = clampf(extents.y, -1.0e6, 1.0e6)
	data[header + 10] = clampf(extents.z, -1.0e6, 1.0e6)
	data[header + 11] = clampf(extents.w, -1.0e6, 1.0e6)
	data[header + 12] = depth
	data[header + 13] = EDGE_ROUND
	data[header + 14] = float(kind) + (1.0 if yolk_pool else 0.0)
	data[header + 15] = 0.0
	data[header + 16] = thick_shape.x
	data[header + 17] = thick_shape.y
	data[header + 18] = thick_shape.z
	data[header + 19] = thick_shape.w
	# Rivulets: (start x, start y, dir angle, length), (width, head height, trail, seed).
	var slot := 0
	for rivulet: Dictionary in rivulets:
		if slot >= MAX_RIVULETS:
			break
		var at := header + 20 + slot * 8
		var start: Vector2 = rivulet.start
		data[at] = start.x
		data[at + 1] = start.y
		data[at + 2] = (rivulet.dir as Vector2).angle()
		data[at + 3] = float(rivulet.length)
		data[at + 4] = float(rivulet.width)
		data[at + 5] = float(rivulet.height)
		data[at + 6] = float(rivulet.trail) * (1.0 if not bool(rivulet.done) else 0.8)
		data[at + 7] = float(rivulet.seed) + (2.0 if bool(rivulet.yolk) else 0.0)
		slot += 1
	for empty in range(slot, MAX_RIVULETS):
		var at := header + 20 + empty * 8
		for index in range(8):
			data[at + index] = 0.0


## White on the surface plus what has left it (for the volume checks).
func booked_volume() -> float:
	return thin_volume + thick_volume + emitted


## Yolk in the sacs plus what has run out of them.
func booked_yolk() -> float:
	var total := yolk_emitted
	for yolk: Dictionary in yolks:
		total += float(yolk.volume)
	return total
