class_name GoalStandEggs
extends Node3D

## Eggs thrown from the goal stand: ballistic flight, then a yolk splat stuck to
## whatever was hit (it rides along with the loser or the referee) or pressed flat
## on the conveyor for a miss, plus a few shell shards. World-space (top_level).

const SPLAT_TEXTURE: Texture2D = preload("res://assets/goal_stand/textures/egg_splat.png")
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const FLOOR_Y := StageConstants.FLOOR_TOP_Y
const MAX_STUCK_PER_TARGET := 6
const SHARDS_PER_HIT := 6
const SHARD_LIFE := 0.8
## Cartoon scale: a real-size egg is a couple of pixels from the finale camera.
const EGG_SCALE := 1.6

var egg_mesh: Mesh
var shard_mesh: Mesh
var material: Material
var launched := 0
var hits := 0
var misses := 0

var _flights: Array[Dictionary] = []
var _splats: Array[Dictionary] = []
var _shards: Array[Dictionary] = []
var _stuck := {}
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


func setup(egg: Mesh, shard: Mesh, shared_material: Material, seed_value: int) -> void:
	name = "Eggs"
	top_level = true
	egg_mesh = egg
	shard_mesh = shard
	material = shared_material
	_rng.seed = seed_value


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
		var target := flight.target as Node3D
		var position: Vector3 = flight.start + flight.velocity * age + 0.5 * GRAVITY * age * age
		# Home the last stretch onto a moving target (the loser keeps sinking/kneeling).
		if is_instance_valid(target) and not flight.miss:
			var goal := target.to_global(flight.target_offset)
			var homing := smoothstep(0.55, 1.0, age / float(flight.flight))
			position += (goal - (flight.aim as Vector3)) * homing
		egg.global_position = position
		egg.rotate(flight.spin, float(flight.spin_rate) * delta)
		if float(flight.age) >= float(flight.flight):
			egg.queue_free()
			_flights.remove_at(index)
			impacts.append(_impact(position, target if not flight.miss else null, camera))
	_update_splats()
	_update_shards(delta)
	return impacts


func _impact(point: Vector3, target: Node3D, camera: Camera3D) -> Dictionary:
	var splat := Sprite3D.new()
	splat.texture = SPLAT_TEXTURE
	splat.shaded = false
	splat.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	splat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hit := is_instance_valid(target)
	var size := _rng.randf_range(0.62, 0.82) if hit else _rng.randf_range(0.8, 1.1)
	splat.pixel_size = size / float(SPLAT_TEXTURE.get_width())
	if hit:
		# Stick to the body, nudged toward the camera so it sits on the surface.
		splat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		var toward := (camera.global_position - point).normalized() if is_instance_valid(camera) else Vector3.UP
		target.add_child(splat)
		splat.global_position = point + toward * 0.22
		splat.rotation.z = _rng.randf_range(-PI, PI)
		var stuck: Array = _stuck.get(target.get_instance_id(), [])
		stuck.append(splat)
		if stuck.size() > MAX_STUCK_PER_TARGET:
			(stuck.pop_front() as Node).queue_free()
		_stuck[target.get_instance_id()] = stuck
		hits += 1
	else:
		add_child(splat)
		splat.global_position = Vector3(point.x, FLOOR_Y + 0.025, point.z)
		splat.rotation = Vector3(-PI * 0.5, _rng.randf_range(-PI, PI), 0.0)
		misses += 1
	_splats.append({"node": splat, "born": _clock, "scale": splat.scale})
	splat.scale = Vector3.ONE * 0.2
	for _index in range(SHARDS_PER_HIT):
		_spawn_shard(point)
	return {"point": point, "hit": hit}


func _spawn_shard(point: Vector3) -> void:
	var shard := MeshInstance3D.new()
	shard.mesh = shard_mesh
	shard.material_override = material
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shard)
	shard.global_position = point
	var direction := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.4, 1.3), _rng.randf_range(-1, 1))
	_shards.append({"node": shard, "velocity": direction * _rng.randf_range(1.4, 2.6), "age": 0.0,
		"spin": Vector3(_rng.randf_range(-1, 1), 1.0, _rng.randf_range(-1, 1)).normalized()})


func _update_splats() -> void:
	for index in range(_splats.size() - 1, -1, -1):
		var entry: Dictionary = _splats[index]
		var node := entry.node as Node3D
		if not is_instance_valid(node):
			_splats.remove_at(index)
			continue
		var t := clampf((_clock - float(entry.born)) / 0.14, 0.0, 1.0)
		var pop := 1.0 + 0.18 * sin(t * PI)
		node.scale = Vector3.ONE * lerpf(0.2, 1.0, t) * pop
		if t >= 1.0:
			node.scale = Vector3.ONE
			_splats.remove_at(index)


func _update_shards(delta: float) -> void:
	for index in range(_shards.size() - 1, -1, -1):
		var shard: Dictionary = _shards[index]
		var node := shard.node as MeshInstance3D
		shard.age += delta
		shard.velocity += GRAVITY * delta
		node.global_position += shard.velocity * delta
		if node.global_position.y < FLOOR_Y + 0.02:
			node.global_position.y = FLOOR_Y + 0.02
			shard.velocity *= Vector3(0.5, -0.3, 0.5)
		node.rotate(shard.spin, 12.0 * delta)
		node.scale = Vector3.ONE * clampf(1.0 - float(shard.age) / SHARD_LIFE, 0.0, 1.0)
		if float(shard.age) >= SHARD_LIFE:
			node.queue_free()
			_shards.remove_at(index)


func in_flight() -> int:
	return _flights.size()


func clear() -> void:
	for list in [_flights, _shards]:
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
	launched = 0
	hits = 0
	misses = 0
