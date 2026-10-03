class_name GoalStandEggs
extends Node3D

## Eggs thrown from the goal stand: ballistic flight, then a break driven by the
## impact velocity and the surface it hits. The egg squashes against the surface,
## shell pieces rebound, tumble under drag, bounce and come to rest flat on the
## conveyor; drops of yolk and white spray out along the surface and leave puddles.
##
## The contents are the Blender meshes in goal_stand_egg_contents.glb (GSE_White,
## GSE_Yolk). The white spreads per angle like a viscous sheet (fast, then braked,
## further in the direction the egg was travelling, thinning as it goes); on a
## steep surface its lower rim creeps downhill and drips. The yolk lands squashed
## and jiggles back on a damped spring, rolls on with the egg's momentum, and on a
## steep surface slides down through the white; once it slides past the rim it
## falls off and bounces to rest on the conveyor. A body splat sticks to whatever
## was hit (riding along with the loser or the referee). World-space (top_level).

const CONTENTS_SCENE := preload("res://assets/goal_stand/goal_stand_egg_contents.glb")
const WHITE_SHADER := preload("res://shaders/goal_stand_egg_white.gdshader")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const FLOOR_Y := StageConstants.FLOOR_TOP_Y
const MAX_STUCK_PER_TARGET := 6
## Cartoon scale: a real-size egg is a couple of pixels from the finale camera.
const EGG_SCALE := 1.6
## The aim point is the target's spine/rig axis; the splat sits this far out on the surface.
const BODY_RADIUS := 0.22
## How much the body splat's facing leans toward the camera so it never goes edge-on.
const CAMERA_FACING := 0.65
## Curvature of the body a splat wraps around (1 / radius).
const BODY_BEND := 1.0 / 0.4
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
## White: rim radius per angle; its spreading speed decays at WHITE_VISCOSITY (1/s).
const RIM_COUNT := 24
const WHITE_VISCOSITY := 12.0
## Downhill creep of the sheet on a steep surface (m/s^2), fading as it thins.
const WHITE_FLOW := 0.4
const WHITE_FLOW_TAU := 1.4
## Plateau thickness once fully spread (m); thicker while still bunched up.
const WHITE_THICKNESS := 0.022
const WHITE_MAX_THICKNESS := 0.07
## Yolk: GSE_Yolk has radius 1; it jiggles on a damped spring after each impact.
const YOLK_STIFFNESS := 480.0
const YOLK_DAMPING := 11.0
const YOLK_DRAG := 4.0
const YOLK_SLIDE := 0.35
const YOLK_RESTITUTION := 0.2
const SPLAT_SETTLE := 4.0
const DRIP_GROW := 0.4
const DROP_MAX_LIFE := 3.0
const MAX_PUDDLES := 40
## Per-quality break detail: shell pieces, spray drops, drips per body hit.
const DETAIL := {
	QualityRules.LOW: {"shards": 4, "drops": 4, "drips": 1},
	QualityRules.BALANCED: {"shards": 6, "drops": 8, "drips": 1},
	QualityRules.HIGH: {"shards": 8, "drops": 12, "drips": 2},
	QualityRules.ULTRA: {"shards": 8, "drops": 12, "drips": 2},
}

var egg_mesh: Mesh
var shard_mesh: Mesh
var white_mesh: Mesh
var yolk_mesh: Mesh
var material: Material
var launched := 0
var hits := 0
var misses := 0
var shards_rested := 0
var drops_landed := 0
var yolks_fallen := 0

var _detail: Dictionary = DETAIL[QualityRules.BALANCED]
var _drop_mesh: SphereMesh
var _yolk: StandardMaterial3D
var _white: StandardMaterial3D
var _flights: Array[Dictionary] = []
var _bursts: Array[Dictionary] = []
var _splats: Array[Dictionary] = []
var _loose_yolks: Array[Dictionary] = []
var _shards: Array[Dictionary] = []
var _drops: Array[Dictionary] = []
var _drips: Array[Dictionary] = []
var _puddles: Array[Node3D] = []
var _stuck := {}
var _floor_layer := 0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


func setup(egg: Mesh, shard: Mesh, shared_material: Material, seed_value: int, quality: String = QualityRules.BALANCED) -> void:
	name = "Eggs"
	top_level = true
	egg_mesh = egg
	shard_mesh = shard
	material = shared_material
	_rng.seed = seed_value
	var contents := CONTENTS_SCENE.instantiate()
	white_mesh = (contents.find_child("GSE_White", true, false) as MeshInstance3D).mesh
	yolk_mesh = (contents.find_child("GSE_Yolk", true, false) as MeshInstance3D).mesh
	contents.free()
	var level := QualityRules.normalize(quality)
	if QualityRules.is_mobile_target() and QualityRules.is_at_least(level, QualityRules.HIGH):
		level = QualityRules.BALANCED
	_detail = DETAIL.get(level, DETAIL[QualityRules.BALANCED])
	_drop_mesh = SphereMesh.new()
	_drop_mesh.radius = 0.03
	_drop_mesh.height = 0.06
	_drop_mesh.radial_segments = 8
	_drop_mesh.rings = 4
	_yolk = StandardMaterial3D.new()
	_yolk.albedo_color = Color(1.0, 0.6, 0.06)
	_yolk.roughness = 0.1
	_yolk.metallic_specular = 0.7
	_yolk.rim_enabled = true
	_yolk.rim = 0.3
	_white = StandardMaterial3D.new()
	_white.albedo_color = Color(0.98, 0.97, 0.92, 0.8)
	_white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_white.roughness = 0.12


## Throw one egg from `start` so it arrives at `aim` after `flight` seconds.
## `target` (optional) receives the splat when the egg is not a planned miss.
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
	_update_splats(delta)
	_update_loose_yolks(delta)
	_update_drips(delta)
	_update_shards(delta)
	_update_drops(delta)
	return impacts


func _impact(egg: MeshInstance3D, point: Vector3, incoming: Vector3, target: Node3D, camera: Camera3D) -> Dictionary:
	var hit := is_instance_valid(target)
	var normal := Vector3.UP
	var surface := Vector3(point.x, FLOOR_Y, point.z)
	if hit:
		# The egg lands on the side facing the thrower; lean it toward the camera
		# (the audience) so a side-on hit still reads.
		var facing := Vector3(-incoming.x, -incoming.y * 0.5, -incoming.z)
		normal = facing.normalized() if facing.length() > 0.01 else Vector3.BACK
		if is_instance_valid(camera):
			normal = normal.lerp((camera.global_position - point).normalized(), CAMERA_FACING).normalized()
		surface = point + normal * BODY_RADIUS
	var normal_speed := incoming.dot(normal)
	var tangential := incoming - normal * normal_speed
	var glance := clampf(tangential.length() / maxf(incoming.length(), 0.001), 0.0, 1.0)
	var slide_dir := tangential.normalized() if tangential.length() > 0.05 else _any_tangent(normal)
	_burst(egg, surface, normal)
	# Splat frame: +Y is the surface normal, +X the direction the egg was travelling.
	var splat := Node3D.new()
	splat.name = "EggSplat"
	var orientation := Basis(slide_dir, normal, slide_dir.cross(normal))
	var reach := _rng.randf_range(0.22, 0.28) if hit else _rng.randf_range(0.28, 0.36)
	var entry := {"node": splat, "born": _clock, "hit": hit, "reach": reach, "bend": BODY_BEND if hit else 0.0}
	if hit:
		target.add_child(splat)
		splat.global_transform = Transform3D(orientation, surface + normal * 0.01)
		# The torso is roughly an upright cylinder: gravity pulls along its side,
		# whatever tilt the splat got for the camera.
		var side := Vector3(normal.x, 0.0, normal.z)
		side = side.normalized() if side.length() > 0.05 else Vector3.BACK
		entry.target = target
		entry.side = (target.global_basis.orthonormalized().inverse() * side).normalized()
		var stuck: Array = _stuck.get(target.get_instance_id(), [])
		stuck.append(splat)
		if stuck.size() > MAX_STUCK_PER_TARGET:
			(stuck.pop_front() as Node).queue_free()
		_stuck[target.get_instance_id()] = stuck
		hits += 1
	else:
		add_child(splat)
		_floor_layer = (_floor_layer + 1) % 8
		splat.global_transform = Transform3D(orientation, Vector3(surface.x, FLOOR_Y + 0.004 + 0.0015 * _floor_layer, surface.z))
		misses += 1
	_spawn_contents(entry, glance, tangential.length())
	_splats.append(entry)
	if hit:
		for _index in range(int(_detail.drips)):
			_drips.append({"entry": entry, "age": 0.0, "delay": _rng.randf_range(0.5, 1.2), "node": null})
	for _index in range(int(_detail.shards)):
		_spawn_shard(surface + normal * 0.03, normal, incoming, normal_speed, tangential)
	for _index in range(int(_detail.drops)):
		_spawn_drop(surface + normal * 0.03, normal, tangential, glance)
	return {"point": point, "hit": hit}


## The white and the yolk of a fresh splat. Each rim angle gets its own spreading
## speed: further along the throw (glance), plus a few smooth lobes so no two
## splats share a shape.
func _spawn_contents(entry: Dictionary, glance: float, tangential_speed: float) -> void:
	var splat := entry.node as Node3D
	var white := MeshInstance3D.new()
	white.name = "White"
	white.mesh = white_mesh
	white.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	white.extra_cull_margin = 1.0
	var white_material := ShaderMaterial.new()
	white_material.shader = WHITE_SHADER
	white_material.set_shader_parameter("bend", float(entry.bend))
	white.material_override = white_material
	splat.add_child(white)
	var yolk_radius := _rng.randf_range(0.08, 0.095)
	var start := yolk_radius * 1.15
	var radii := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var lobes: Array[Vector2] = []
	for _index in range(3):
		lobes.append(Vector2(_rng.randi_range(3, 7), _rng.randf_range(0.0, TAU)))
	for index in range(RIM_COUNT):
		var angle := TAU * index / RIM_COUNT
		var along := cos(angle)
		var shape := 1.0 + 0.16 * sin(lobes[0].x * angle + lobes[0].y) + 0.1 * sin(lobes[1].x * angle + lobes[1].y) \
			+ 0.06 * sin(lobes[2].x * angle + lobes[2].y)
		var throw := 1.0 + glance * 0.9 * maxf(along, 0.0) - glance * 0.35 * maxf(-along, 0.0)
		var final := float(entry.reach) * shape * throw
		radii.append(start)
		speeds.append((final - start) * WHITE_VISCOSITY)
	entry.white = white
	entry.material = white_material
	entry.rim = radii
	entry.rim_speed = speeds
	var yolk := MeshInstance3D.new()
	yolk.name = "Yolk"
	yolk.mesh = yolk_mesh
	yolk.material_override = _yolk
	yolk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splat.add_child(yolk)
	entry.yolk = yolk
	entry.yolk_radius = yolk_radius
	# Momentum carries the yolk on along the throw; the impact flattens it.
	entry.yolk_pos = Vector2.ZERO
	entry.yolk_vel = Vector2(clampf(tangential_speed * 0.04, 0.0, 0.8), 0.0)
	entry.squash = -0.55
	entry.squash_vel = 0.0
	# How hard this yolk clings before gravity drags it (m/s^2).
	entry.stick = _rng.randf_range(3.0, 8.0)
	entry.yolk_attached = true
	_apply_contents(entry)


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


func _update_splats(delta: float) -> void:
	for index in range(_splats.size() - 1, -1, -1):
		var entry: Dictionary = _splats[index]
		var splat := _live(entry.node) as Node3D
		if splat == null:
			_splats.remove_at(index)
			continue
		var age := _clock - float(entry.born)
		# Gravity in the splat's plane (x, z), and how steep the surface really is.
		var down := splat.global_basis.orthonormalized().inverse() * Vector3.DOWN
		var downhill := Vector2(down.x, down.z)
		var downhill_dir := downhill.normalized() if downhill.length() > 0.01 else Vector2.ZERO
		var steep := 0.0
		if entry.hit and is_instance_valid(entry.target):
			var side := (entry.target as Node3D).global_basis.orthonormalized() * (entry.side as Vector3)
			steep = sqrt(maxf(0.0, 1.0 - pow(side.dot(Vector3.DOWN), 2.0)))
		_step_white(entry, delta, age, downhill_dir, steep)
		_step_yolk(entry, delta, downhill_dir, steep)
		_apply_contents(entry)
		var yolk_still: bool = not entry.yolk_attached or (entry.yolk_vel as Vector2).length() < 0.005
		if age > SPLAT_SETTLE and absf(float(entry.squash)) < 0.005 and yolk_still:
			_splats.remove_at(index)


## Viscous spreading per rim angle; on a steep surface the downhill rim keeps
## creeping while the sheet is still thick.
func _step_white(entry: Dictionary, delta: float, age: float, downhill: Vector2, steep: float) -> void:
	var radii: PackedFloat32Array = entry.rim
	var speeds: PackedFloat32Array = entry.rim_speed
	var brake := exp(-WHITE_VISCOSITY * delta)
	var flow := WHITE_FLOW * steep * exp(-age / WHITE_FLOW_TAU)
	for index in range(RIM_COUNT):
		var angle := TAU * index / RIM_COUNT
		var toward := maxf(0.0, Vector2(cos(angle), sin(angle)).dot(downhill))
		speeds[index] = speeds[index] * brake + flow * toward * toward * toward * delta
		radii[index] += speeds[index] * delta
	entry.rim = radii
	entry.rim_speed = speeds


## Yolk jiggle (damped spring on its height), momentum and gravity sliding it
## through the white, and falling off once it slides past the rim.
func _step_yolk(entry: Dictionary, delta: float, downhill: Vector2, steep: float) -> void:
	var squash := float(entry.squash)
	var squash_vel := float(entry.squash_vel)
	squash_vel += (-YOLK_STIFFNESS * squash - YOLK_DAMPING * squash_vel) * delta
	squash += squash_vel * delta
	entry.squash = squash
	entry.squash_vel = squash_vel
	if not entry.yolk_attached:
		return
	var pull := maxf(0.0, 9.8 * steep - float(entry.stick)) * YOLK_SLIDE
	var velocity: Vector2 = entry.yolk_vel
	velocity += (downhill * pull - velocity * YOLK_DRAG) * delta
	var position: Vector2 = entry.yolk_pos + velocity * delta
	var limit := _rim_at(entry.rim, atan2(position.y, position.x)) - float(entry.yolk_radius) * 0.4
	if position.length() > limit:
		if pull > 0.0:
			entry.yolk_pos = position
			entry.yolk_vel = velocity
			_release_yolk(entry)
			return
		position = position.normalized() * limit
		velocity = Vector2.ZERO
	entry.yolk_pos = position
	entry.yolk_vel = velocity


func _apply_contents(entry: Dictionary) -> void:
	var radii: PackedFloat32Array = entry.rim
	var mean := 0.0
	for radius in radii:
		mean += radius
	mean /= RIM_COUNT
	# Constant volume: the sheet thins as its area grows.
	var thickness := clampf(WHITE_THICKNESS * pow(float(entry.reach) / maxf(mean, 0.01), 2.0), WHITE_THICKNESS, WHITE_MAX_THICKNESS)
	var white_material := entry.material as ShaderMaterial
	white_material.set_shader_parameter("rim", radii)
	white_material.set_shader_parameter("thickness", thickness)
	if entry.yolk_attached and is_instance_valid(entry.yolk):
		var p: Vector2 = entry.yolk_pos
		var height := thickness * 0.75 - 0.5 * float(entry.bend) * p.length_squared()
		(entry.yolk as Node3D).transform = Transform3D(_squash_basis(float(entry.yolk_radius), float(entry.squash)), Vector3(p.x, height, p.y))


## Volume-keeping squash: shorter yolks bulge sideways.
func _squash_basis(radius: float, squash: float) -> Basis:
	var tall := maxf(1.0 + squash, 0.2)
	var wide := 1.0 / sqrt(tall)
	return Basis.from_scale(Vector3(wide, tall, wide) * radius)


func _rim_at(radii: PackedFloat32Array, angle: float) -> float:
	var x := fposmod(angle / TAU, 1.0) * RIM_COUNT
	var i0 := int(floor(x)) % RIM_COUNT
	var t := smoothstep(0.0, 1.0, x - floor(x))
	return lerpf(radii[i0], radii[(i0 + 1) % RIM_COUNT], t)


## The yolk leaves the white and falls as a free body.
func _release_yolk(entry: Dictionary) -> void:
	var yolk := entry.yolk as MeshInstance3D
	var splat := entry.node as Node3D
	entry.yolk_attached = false
	entry.yolk = null
	var world := yolk.global_transform
	var slide: Vector2 = entry.yolk_vel
	var velocity := splat.global_basis.orthonormalized() * Vector3(slide.x, 0.3, slide.y)
	yolk.get_parent().remove_child(yolk)
	add_child(yolk)
	yolk.global_transform = world
	_loose_yolks.append({"node": yolk, "velocity": velocity, "radius": entry.yolk_radius, "squash": float(entry.squash),
		"squash_vel": float(entry.squash_vel), "landed": false, "up": world.basis.y.normalized()})
	yolks_fallen += 1


func _update_loose_yolks(delta: float) -> void:
	for index in range(_loose_yolks.size() - 1, -1, -1):
		var yolk: Dictionary = _loose_yolks[index]
		var node := _live(yolk.node) as MeshInstance3D
		if not is_instance_valid(node):
			_loose_yolks.remove_at(index)
			continue
		var squash := float(yolk.squash)
		var squash_vel := float(yolk.squash_vel) + (-YOLK_STIFFNESS * squash - YOLK_DAMPING * float(yolk.squash_vel)) * delta
		squash += squash_vel * delta
		var velocity: Vector3 = yolk.velocity
		var position := node.global_position
		var up: Vector3 = yolk.up
		if not yolk.landed:
			velocity += GRAVITY * delta
			position += velocity * delta
			# Surface tension pulls it round and it turns upright as it falls.
			up = up.slerp(Vector3.UP, 1.0 - exp(-delta * 4.0)).normalized()
			if position.y <= FLOOR_Y + 0.002 and velocity.y < 0.0:
				position.y = FLOOR_Y + 0.002
				# The membrane holds: it splats flat, rebounds a little and wobbles.
				squash = -clampf(absf(velocity.y) / 6.0, 0.3, 0.65)
				squash_vel = 0.0
				velocity = Vector3(velocity.x * 0.3, absf(velocity.y) * YOLK_RESTITUTION, velocity.z * 0.3)
				up = Vector3.UP
				if velocity.y < 0.4:
					yolk.landed = true
					velocity.y = 0.0
		else:
			velocity *= exp(-YOLK_DRAG * 2.0 * delta)
			position += velocity * delta
			position.y = FLOOR_Y + 0.002
		yolk.velocity = velocity
		yolk.squash = squash
		yolk.squash_vel = squash_vel
		yolk.up = up
		node.global_transform = Transform3D(_basis_y(up) * _squash_basis(float(yolk.radius), squash), position)
		if yolk.landed and absf(squash) < 0.005 and absf(squash_vel) < 0.05 and velocity.length() < 0.01:
			_loose_yolks.remove_at(index)


func _spawn_shard(point: Vector3, normal: Vector3, incoming: Vector3, normal_speed: float, tangential: Vector3) -> void:
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


## A drop of yolk or white sprayed out along the surface plane, biased toward the
## direction the egg was travelling.
func _spawn_drop(point: Vector3, normal: Vector3, tangential: Vector3, glance: float) -> void:
	var first := _any_tangent(normal)
	var second := normal.cross(first)
	var angle := _rng.randf_range(-PI, PI)
	var direction := first * cos(angle) + second * sin(angle)
	if tangential.length() > 0.05:
		direction = (direction + tangential.normalized() * glance * 0.9).normalized()
	var velocity := direction * _rng.randf_range(1.5, 3.5) + normal * _rng.randf_range(0.3, 1.2)
	# The yolk mostly holds together in the splat; the spray is mostly white.
	_add_drop(point, velocity, _rng.randf_range(0.5, 1.1), _rng.randf() < 0.2)


func _add_drop(point: Vector3, velocity: Vector3, size: float, yolk: bool) -> MeshInstance3D:
	var drop := MeshInstance3D.new()
	drop.mesh = _drop_mesh
	drop.material_override = _yolk if yolk else _white
	drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drop)
	drop.global_position = point
	_drops.append({"node": drop, "velocity": velocity, "size": size, "age": 0.0, "yolk": yolk})
	_orient_drop(drop, velocity, size)
	return drop


## Stretch a flying drop along its velocity (volume kept) so it reads as liquid.
func _orient_drop(drop: Node3D, velocity: Vector3, size: float) -> void:
	var speed := velocity.length()
	var stretch := 1.0 + minf(speed * 0.12, 1.2)
	var direction := velocity / speed if speed > 0.01 else Vector3.DOWN
	drop.global_basis = _basis_y(direction).scaled_local(Vector3(1.0 / sqrt(stretch), stretch, 1.0 / sqrt(stretch)) * size)


func _update_drops(delta: float) -> void:
	for index in range(_drops.size() - 1, -1, -1):
		var drop: Dictionary = _drops[index]
		var node := _live(drop.node) as MeshInstance3D
		drop.age += delta
		if not is_instance_valid(node) or float(drop.age) >= DROP_MAX_LIFE:
			if is_instance_valid(node):
				node.queue_free()
			_drops.remove_at(index)
			continue
		var velocity: Vector3 = drop.velocity + GRAVITY * delta
		var position := node.global_position + velocity * delta
		if position.y <= FLOOR_Y + 0.01:
			_puddle(Vector3(position.x, FLOOR_Y, position.z), velocity, float(drop.size), node.material_override)
			node.queue_free()
			_drops.remove_at(index)
			drops_landed += 1
			continue
		drop.velocity = velocity
		node.global_position = position
		_orient_drop(node, velocity, float(drop.size))


## A landed drop flattens into a small glossy puddle, smeared along its skid.
func _puddle(point: Vector3, velocity: Vector3, size: float, drop_material: Material) -> void:
	var puddle := MeshInstance3D.new()
	puddle.mesh = _drop_mesh
	puddle.material_override = drop_material
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puddle)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var skid := 1.0 + minf(horizontal.length() * 0.15, 0.8)
	var along := horizontal.normalized() if horizontal.length() > 0.05 else Vector3.RIGHT
	var width := size * _rng.randf_range(1.6, 2.2)
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP)).scaled_local(Vector3(width * skid, 0.12, width))
	puddle.global_transform = Transform3D(basis, point + Vector3(0.0, 0.004, 0.0) + along * 0.02 * skid)
	_puddles.append(puddle)
	if _puddles.size() > MAX_PUDDLES:
		var oldest := _puddles.pop_front() as Node
		if is_instance_valid(oldest):
			oldest.queue_free()


## Drips gather at the lowest point of a body splat's white, stretch, and let go.
func _update_drips(delta: float) -> void:
	for index in range(_drips.size() - 1, -1, -1):
		var drip: Dictionary = _drips[index]
		var entry: Dictionary = drip.entry
		var splat := _live(entry.node) as Node3D
		drip.age += delta
		var node := _live(drip.node) as MeshInstance3D
		if not is_instance_valid(splat):
			if is_instance_valid(node):
				node.queue_free()
			_drips.remove_at(index)
			continue
		if float(drip.age) < float(drip.delay):
			continue
		var down := splat.global_basis.orthonormalized().inverse() * Vector3.DOWN
		var downhill := Vector2(down.x, down.z)
		if downhill.length() < 0.3:
			# The splat faces up: nothing hangs off it.
			_drips.remove_at(index)
			continue
		var angle := atan2(downhill.y, downhill.x)
		var reach := _rim_at(entry.rim, angle) * 0.97
		var edge := splat.to_global(Vector3(cos(angle) * reach, -0.5 * float(entry.bend) * reach * reach, sin(angle) * reach))
		var grow := clampf((float(drip.age) - float(drip.delay)) / DRIP_GROW, 0.0, 1.0)
		if node == null:
			node = MeshInstance3D.new()
			node.mesh = _drop_mesh
			node.material_override = _white
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			drip.node = node
		var size := 0.4 + 0.5 * grow
		var stretch := 1.0 + 1.4 * grow
		node.global_transform = Transform3D(Basis.from_scale(Vector3(size, size * stretch, size)),
			edge + Vector3.DOWN * 0.03 * stretch * size)
		if grow >= 1.0:
			_drops.append({"node": node, "velocity": Vector3.DOWN * 0.3, "size": size, "age": 0.0, "yolk": false})
			_drips.remove_at(index)


func in_flight() -> int:
	return _flights.size()


func active_counts() -> Dictionary:
	return {"shards": _shards.size(), "drops": _drops.size(), "drips": _drips.size(), "puddles": _puddles.size(),
		"splats_animating": _splats.size(), "loose_yolks": _loose_yolks.size(), "shards_rested": shards_rested,
		"drops_landed": drops_landed, "yolks_fallen": yolks_fallen}


func clear() -> void:
	for list in [_flights, _bursts, _shards, _drops, _drips, _loose_yolks]:
		for entry: Dictionary in list:
			if is_instance_valid(entry.node):
				(entry.node as Node).queue_free()
		list.clear()
	for stuck: Array in _stuck.values():
		for node: Variant in stuck:
			if is_instance_valid(node):
				(node as Node).queue_free()
	_stuck.clear()
	for child in get_children():
		child.queue_free()
	_splats.clear()
	_puddles.clear()
	launched = 0
	hits = 0
	misses = 0
	shards_rested = 0
	drops_landed = 0
	yolks_fallen = 0


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
