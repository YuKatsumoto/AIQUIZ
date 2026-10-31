class_name GoalStandEggs
extends Node3D

## Eggs thrown from the goal stand: ballistic flight, then a break driven by the
## impact velocity and the surface it hits. The egg squashes against the surface
## for a moment and bursts into shell pieces that rebound, tumble under drag,
## bounce and come to rest flat on the conveyor before fading. On a body some pieces
## stay stuck in the white and some fly off on a thread of albumen.
##
## The raw contents (white, yolk, rivulets, drips, puddles) are GoalStandEggContents:
## a hit on a body breaks on the real surface of the part it reaches (a ray along the
## throw, leaned toward the camera so the audience sees it), a miss on the conveyor.
## The crowd throws for as long as the verdict holds, so the live shell pieces are
## capped, and so is everything in the contents. World-space (top_level).

const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const FLOOR_Y := StageConstants.FLOOR_TOP_Y
## Cartoon scale: a real-size egg is a couple of pixels from the finale camera.
const EGG_SCALE := 1.6
## Without body proxies the egg breaks this far out from the aim point (the spine axis).
const BODY_RADIUS := 0.22
## How much the ray that finds where it breaks leans toward the camera: all the
## way, so the egg breaks on the surface the audience sees at the point it lands
## on screen (eggs are lobbed high and come down onto the target).
const CAMERA_FACING := 1.0
## Where on screen a hit may land (fractions of the view): clear of the edges, the
## result buttons along the bottom and the score panel at the top right.
const SAFE_SCREEN := Rect2(0.06, 0.12, 0.88, 0.72)
const SCORE_PANEL := Rect2(0.72, 0.0, 0.28, 0.5)
## Share of a body hit's shell pieces that stay stuck in the white.
const CAPTURE_SHARE := 0.35
const BURST_TIME := 0.05
## Shell: light, so air drag matters; bounces lose most of their energy.
const SHARD_DRAG := 0.6
const SHARD_RESTITUTION := 0.3
const SHARD_FRICTION := 0.55
const SHARD_MAX_BOUNCES := 3
const SHARD_REST_Y := FLOOR_Y + 0.007
const SHARD_REST_TIME := 2.5
const SHARD_FADE := 0.4
const SHARD_MAX_LIFE := 6.0
## Endless throwing: beyond this many live pieces the oldest go first.
const MAX_SHARDS := 96
## Per-quality break detail: shell pieces per egg.
const DETAIL := {
	QualityRules.LOW: {"shards": 4},
	QualityRules.BALANCED: {"shards": 6},
	QualityRules.HIGH: {"shards": 8},
	QualityRules.ULTRA: {"shards": 8},
}

var egg_mesh: Mesh
var shard_mesh: Mesh
var material: Material
var launched := 0
var hits := 0
var misses := 0
var shards_rested := 0
var contents: GoalStandEggContents
## Smoothed cost of the contents' update (microseconds).
var contents_usec := 0.0
## What drips and fallen yolks land on before the conveyor: {node, top (local y),
## radius} of the loser's lift deck, or empty (GoalStand passes the director's).
var support := {}:
	set(value):
		support = value
		if contents != null:
			contents.support = value

var _detail: Dictionary = DETAIL[QualityRules.BALANCED]
var _flights: Array[Dictionary] = []
var _bursts: Array[Dictionary] = []
var _shards: Array[Dictionary] = []
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


func setup(egg: Mesh, shard: Mesh, shared_material: Material, seed_value: int, quality: String = QualityRules.BALANCED) -> void:
	name = "Eggs"
	top_level = true
	egg_mesh = egg
	shard_mesh = shard
	material = shared_material
	_rng.seed = seed_value
	var mobile := QualityRules.is_mobile_target()
	var level := detail_level(quality, mobile)
	_detail = DETAIL.get(level, DETAIL[QualityRules.BALANCED])
	contents = GoalStandEggContents.new()
	add_child(contents)
	var length := egg_mesh.get_aabb().get_longest_axis_size() * EGG_SCALE if egg_mesh != null else 0.32
	contents.setup(level, GoalStandEggRheology.scale_for_length(length), seed_value + 1, mobile)
	contents.support = support


## A point on `target`'s surface that `camera` sees, inside SAFE_SCREEN, for an
## egg to land on (the biggest parts first: torso, head, upper limbs). `fallback`
## when there is none.
func visible_aim(target: Node3D, camera: Camera3D, fallback: Vector3) -> Vector3:
	if contents == null or not is_instance_valid(camera) or not is_instance_valid(target):
		return fallback
	var body := contents.body_for(target)
	if body.is_empty():
		return fallback
	var size := camera.get_viewport().get_visible_rect().size
	var order := body.shapes_by_size()
	var eye := camera.global_position
	for _attempt in range(16):
		var index: int = order[_rng.randi_range(0, mini(order.size(), 6) - 1)]
		var probe := body.shape_centre(index) + Vector3(_rng.randf_range(-0.18, 0.18), _rng.randf_range(-0.12, 0.18), _rng.randf_range(-0.18, 0.18))
		# The first surface on the line of sight is the one the camera shows.
		var hit := body.raycast(eye, probe - eye, eye.distance_to(probe) + 1.0)
		if hit.is_empty() or camera.is_position_behind(hit.point):
			continue
		var screen := camera.unproject_position(hit.point) / size
		if SAFE_SCREEN.has_point(screen) and not SCORE_PANEL.has_point(screen):
			return hit.point
	return fallback


## The quality the eggs run at: mobile builds stop at BALANCED.
static func detail_level(quality: String, mobile: bool) -> String:
	var level := QualityRules.normalize(quality)
	if mobile and QualityRules.is_at_least(level, QualityRules.HIGH):
		level = QualityRules.BALANCED
	return level


## Throw one egg from `start` so it arrives at `aim` after `flight` seconds.
## `target` (optional) is where it breaks when the egg is not a planned miss.
func launch(start: Vector3, aim: Vector3, flight: float, target: Node3D, miss: bool) -> void:
	var egg := MeshInstance3D.new()
	egg.mesh = egg_mesh
	egg.material_override = material
	egg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	egg.scale = Vector3.ONE * EGG_SCALE
	add_child(egg)
	egg.global_position = start
	var velocity := (aim - start - 0.5 * GRAVITY * flight * flight) / flight
	var spin := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	_flights.append({"node": egg, "start": start, "velocity": velocity, "age": 0.0, "flight": flight,
		"target": target, "miss": miss, "aim": aim, "spin": spin, "spin_rate": _rng.randf_range(9.0, 15.0),
		"target_offset": target.to_local(aim) if is_instance_valid(target) and not miss else Vector3.ZERO})
	launched += 1


func update(delta: float, camera: Camera3D) -> Array[Dictionary]:
	_clock += delta
	var impacts: Array[Dictionary] = []
	for index in range(_flights.size() - 1, -1, -1):
		var flight: Dictionary = _flights[index]
		var egg := flight.node as MeshInstance3D
		flight.age += delta
		var age := minf(float(flight.age), float(flight.flight))
		var target := _live(flight.target) as Node3D
		var position: Vector3 = flight.start + flight.velocity * age + 0.5 * GRAVITY * age * age
		# Home the last stretch onto a moving target (the loser keeps sinking/kneeling).
		if is_instance_valid(target) and not flight.miss:
			var goal := target.to_global(flight.target_offset)
			var homing := smoothstep(0.55, 1.0, age / float(flight.flight))
			position += (goal - (flight.aim as Vector3)) * homing
		egg.global_position = position
		egg.rotate(flight.spin, float(flight.spin_rate) * delta)
		if float(flight.age) >= float(flight.flight):
			_flights.remove_at(index)
			var incoming: Vector3 = flight.velocity + GRAVITY * float(flight.flight)
			impacts.append(_impact(egg, position, incoming, target if not flight.miss else null, camera))
	_update_bursts(delta)
	_update_shards(delta)
	if contents != null:
		var started := Time.get_ticks_usec()
		contents.update(delta, camera)
		contents_usec = lerpf(contents_usec, float(Time.get_ticks_usec() - started), 0.1)
	return impacts


func _impact(egg: MeshInstance3D, point: Vector3, incoming: Vector3, target: Node3D, camera: Camera3D) -> Dictionary:
	var hit := is_instance_valid(target)
	var normal := Vector3.UP
	var surface := Vector3(point.x, FLOOR_Y, point.z)
	var splat := {}
	if hit:
		# Where it breaks: the first surface along the throw, leaned toward the camera
		# (the audience) so a side-on hit still lands where it reads.
		var ray := incoming.normalized()
		if is_instance_valid(camera):
			ray = ray.lerp((point - camera.global_position).normalized(), CAMERA_FACING).normalized()
		splat = contents.spawn_on_body(target, point, incoming, ray) if contents != null else {}
		if not splat.is_empty():
			surface = splat.hit
			normal = splat.normal
		else:
			var facing := Vector3(-incoming.x, -incoming.y * 0.5, -incoming.z)
			normal = facing.normalized() if facing.length() > 0.01 else Vector3.BACK
			if is_instance_valid(camera):
				normal = normal.lerp((camera.global_position - point).normalized(), CAMERA_FACING).normalized()
			surface = point + normal * BODY_RADIUS
		hits += 1
	else:
		if contents != null:
			splat = contents.spawn_on_floor(surface, incoming)
		misses += 1
	var normal_speed := incoming.dot(normal)
	var tangential := incoming - normal * normal_speed
	_burst(egg, surface, normal)
	var tethers := 0
	for _index in range(int(_detail.shards)):
		if hit and not splat.is_empty() and _rng.randf() < CAPTURE_SHARE and contents.capture(splat, shard_mesh, material):
			continue
		var shard := _spawn_shard(surface + normal * 0.03, normal, normal_speed, tangential)
		if hit and not splat.is_empty() and tethers < 3 and contents.tether(splat, shard):
			tethers += 1
	return {"point": point, "hit": hit, "surface": surface, "normal": normal}


## The egg flattens against the surface for a couple of frames before it bursts.
func _burst(egg: MeshInstance3D, surface: Vector3, normal: Vector3) -> void:
	egg.global_transform = Transform3D(_basis_y(normal), surface)
	_bursts.append({"node": egg, "age": 0.0, "normal": normal})
	_apply_burst(_bursts.back())


func _apply_burst(burst: Dictionary) -> void:
	var t := clampf(float(burst.age) / BURST_TIME, 0.0, 1.0)
	var node := burst.node as Node3D
	node.global_basis = _basis_y(burst.normal).scaled_local(Vector3(lerpf(1.2, 1.6, t), lerpf(0.7, 0.2, t), lerpf(1.2, 1.6, t)) * EGG_SCALE)


func _update_bursts(delta: float) -> void:
	for index in range(_bursts.size() - 1, -1, -1):
		var burst: Dictionary = _bursts[index]
		burst.age += delta
		if float(burst.age) >= BURST_TIME or not is_instance_valid(burst.node):
			if is_instance_valid(burst.node):
				(burst.node as Node).queue_free()
			_bursts.remove_at(index)
		else:
			_apply_burst(burst)


func _spawn_shard(point: Vector3, normal: Vector3, normal_speed: float, tangential: Vector3) -> Dictionary:
	if _shards.size() >= MAX_SHARDS:
		var oldest: Dictionary = _shards.pop_front()
		if is_instance_valid(oldest.node):
			(oldest.node as Node).queue_free()
	var shard := MeshInstance3D.new()
	shard.mesh = shard_mesh
	shard.material_override = material
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shard)
	shard.global_position = point
	shard.rotate(_random_unit(), _rng.randf_range(0.0, TAU))
	# Rebound off the surface, keep part of the glancing motion, plus a scatter cone.
	var rebound := normal * absf(normal_speed) * _rng.randf_range(0.15, 0.35)
	var carry := tangential * _rng.randf_range(0.25, 0.5)
	var scatter := (_random_unit() + normal * 0.6) * _rng.randf_range(0.6, 1.4)
	var velocity := rebound + carry + scatter
	_shards.append({"node": shard, "velocity": velocity, "age": 0.0, "axis": _random_unit(),
		"spin_rate": velocity.length() * _rng.randf_range(3.0, 6.0), "bounces": 0, "rested": -1.0})
	return _shards.back()


func _update_shards(delta: float) -> void:
	for index in range(_shards.size() - 1, -1, -1):
		var shard: Dictionary = _shards[index]
		var node := _live(shard.node) as MeshInstance3D
		shard.age += delta
		if not is_instance_valid(node):
			_shards.remove_at(index)
			continue
		if float(shard.rested) >= 0.0:
			var resting := _clock - float(shard.rested)
			if resting >= SHARD_REST_TIME:
				var fade := clampf((resting - SHARD_REST_TIME) / SHARD_FADE, 0.0, 1.0)
				node.global_position.y = SHARD_REST_Y - 0.01 * fade
				node.scale = Vector3.ONE * (1.0 - fade)
				if fade >= 1.0:
					node.queue_free()
					_shards.remove_at(index)
			continue
		var velocity: Vector3 = shard.velocity
		velocity += GRAVITY * delta
		velocity -= velocity * velocity.length() * SHARD_DRAG * delta
		var position := node.global_position + velocity * delta
		node.rotate(shard.axis, float(shard.spin_rate) * delta)
		if position.y <= SHARD_REST_Y and velocity.y < 0.0:
			position.y = SHARD_REST_Y
			velocity.y = -velocity.y * SHARD_RESTITUTION
			velocity.x *= SHARD_FRICTION
			velocity.z *= SHARD_FRICTION
			shard.spin_rate = float(shard.spin_rate) * 0.5
			shard.axis = (shard.axis as Vector3).lerp(_random_unit(), 0.5).normalized()
			shard.bounces = int(shard.bounces) + 1
			if int(shard.bounces) >= SHARD_MAX_BOUNCES or velocity.length() < 0.5:
				# Settle flat, keeping the heading it landed with.
				var heading := node.global_basis.x
				var yaw := atan2(heading.x, heading.z) if Vector2(heading.x, heading.z).length() > 0.01 else _rng.randf_range(-PI, PI)
				node.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(position.x, SHARD_REST_Y, position.z))
				shard.rested = _clock
				shards_rested += 1
				continue
		shard.velocity = velocity
		node.global_position = position
		if float(shard.age) >= SHARD_MAX_LIFE:
			node.queue_free()
			_shards.remove_at(index)


func in_flight() -> int:
	return _flights.size()


func active_counts() -> Dictionary:
	var counts := {"shards": _shards.size(), "shards_rested": shards_rested}
	if contents != null:
		counts.merge(contents.counts())
	return counts


func clear() -> void:
	for list in [_flights, _bursts, _shards]:
		for entry: Dictionary in list:
			if is_instance_valid(entry.node):
				(entry.node as Node).queue_free()
			list.clear()
	if contents != null:
		contents.clear()
	for child in get_children():
		if child != contents:
			child.queue_free()
	launched = 0
	hits = 0
	misses = 0
	shards_rested = 0


## `value` if it is a node that still exists, else null (casting a freed node errors).
static func _live(value: Variant) -> Node:
	return value if is_instance_valid(value) else null


func _random_unit() -> Vector3:
	var v := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
	return v.normalized() if v.length() > 0.01 else Vector3.UP


## Any unit vector perpendicular to `normal`.
static func _any_tangent(normal: Vector3) -> Vector3:
	var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return reference.cross(normal).normalized()


## Orthonormal basis whose Y axis is `direction`.
static func _basis_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var x := _any_tangent(y)
	return Basis(x, y, x.cross(y))
