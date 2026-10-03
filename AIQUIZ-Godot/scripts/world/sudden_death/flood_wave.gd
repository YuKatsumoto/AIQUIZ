class_name FloodWave
extends Node3D

## 2Pサドンデスの鉄砲水の表示（docs/sudden_death_underground.md 6.6）。判定は持たない。
## CisternStage が作り、毎フレーム update_wave() で SuddenDeathState の前面の位置・速さ・後退を渡す。
## 前面：Blenderで作った乱流の段波を頂点アニメーションテクスチャ（VAT）に焼いたもの
## （assets/hazards/flood_wave、flood_wave_layout.json）。2.0秒でループし、列ごとに位相がずれる。
## 水面：前面の8m後ろから上流へ、水深1.2mの濁った流れ（屈折・深さの吸収・流れの法線・泡・接触の泡）。
## 粒子：前面のしぶき、霧の大きな板、柱や扉に当たる跳ね返り（burst）、天井からの水滴、照明が消えるときの火花。
## 原点は前面のつま先の床面（ワールド z = 前面、y = 床）。+Z が流れの向き。

const FRONT_GLB_PATH := "res://assets/hazards/flood_wave/flood_front.glb"
## The front's ArrayMesh, saved out of the GLB by tools/sudden_death/build_cistern_scenes.gd.
const FRONT_MESH_PATH := "res://scenes/sudden_death/cistern_generated/flood/front_mesh.res"
const VAT_POS_PATH := "res://assets/hazards/flood_wave/textures/flood_front_vat_pos.exr"
const VAT_NRM_PATH := "res://assets/hazards/flood_wave/textures/flood_front_vat_nrm.png"
const FOAM_PATH := "res://assets/hazards/flood_wave/textures/flood_foam.png"
const WATER_NORMAL_PATH := "res://assets/hazards/flood_wave/textures/flood_water_normal.png"
const SPRAY_PATH := "res://assets/hazards/flood_wave/textures/flood_spray.png"
const FRONT_SHADER := preload("res://shaders/sudden_death/flood_front.gdshader")
const WATER_SHADER := preload("res://shaders/sudden_death/flood_water.gdshader")
## The GraphicsQuality autoload instance can be a stale placeholder in an open editor; its rules are static.
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")

## flood_wave_layout.json (checked by tests/sudden_death_unit.gd).
const VAT_FRAMES := 48
const VAT_ROWS_PER_FRAME := 5
const VAT_WIDTH := 4096
const LOOP_SECONDS := 2.0
const CREST_HEIGHT := 3.4
const WATER_DEPTH := 1.2
const BACK_Z := -9.0
const HALF_WIDTH := 45.0
const FRONT_AABB := AABB(Vector3(-45.2, -0.2, -9.2), Vector3(90.4, 4.2, 11.6))
## The node sits this far behind the state's front: the toe sheet then reaches ~0.9 m past it and the face
## the runner is hit by stands at the front.
const TOE_OFFSET := 0.8
## Water body behind the front, out to the upstream end and into the tunnel.
const BODY_LENGTH := 150.0
const BODY_OVERLAP := 0.6
## The flood fans out of the 10 m tunnel mouth (fan_half(), same as the shaders).
const TUNNEL_Z := -30.0
const FAN_START := 5.0
const FAN_DISTANCE := 22.0
## Spray atlas frames (flood_spray.png, 4 x 4): row 0 mist, 1 dense spray, 2 droplets, 3 streaks.
const ATLAS_MIST := Vector2(0.0, 3.99)
const ATLAS_SPUME := Vector2(4.0, 7.99)
const ATLAS_DROPS := Vector2(8.0, 15.99)
const ATLAS_SPRAY := Vector2(4.0, 15.99)
const ATLAS_STREAK := Vector2(12.0, 15.99)
const BURST_POOL := 8
const SPARK_POOL := 4
## Ceiling drips fall around this point (the runners), over a 34 x 46 m patch.
const DRIP_HEIGHT := 17.5

var quality := GraphicsQualityRules.BALANCED
## Seconds of the VAT loop (game time).
var clock := 0.0

var _front: MeshInstance3D = null
var _body: MeshInstance3D = null
var _ladder: MeshInstance3D = null
var _front_material: ShaderMaterial = null
var _body_material: ShaderMaterial = null
var _ladder_material: ShaderMaterial = null
var _spray: GPUParticles3D = null
var _spume: GPUParticles3D = null
var _mist: GPUParticles3D = null
var _drips: GPUParticles3D = null
var _bursts: Array[GPUParticles3D] = []
var _sparks: Array[GPUParticles3D] = []
var _burst_next := 0
var _spark_next := 0
var _height := 1.0
var _travelled := 0.0
## Whitewater boost after the gush out of the tunnel (1 -> 0 over GUSH_FOAM_TIME).
var _boost := 0.0
const GUSH_FOAM_TIME := 3.0
var _front_z := TUNNEL_Z
var _speed := 0.0
var _wave_on := false
var _built := false
var _bursts_fired := 0

static var _shared := {}
static var _warm_samples: Array[Material] = []


# ------------------------------------------------------------------ build

## [param assets] (optional, the cistern scene carries them so they load on the loader's thread):
## [front mesh, VAT position, VAT normal, foam, water normal, spray atlas].
func setup(p_quality: String, assets: Array = []) -> void:
	if _built:
		return
	quality = GraphicsQualityRules.normalize(p_quality)
	_resolve_assets(assets)
	name = "FloodWave" if name.is_empty() or name.begins_with("@") else name
	_front_material = front_material()
	_front = MeshInstance3D.new()
	_front.name = "Front"
	_front.mesh = _shared.front_mesh
	_front.material_override = _front_material
	_front.custom_aabb = FRONT_AABB
	_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_front)

	_body_material = body_material(quality)
	_body = MeshInstance3D.new()
	_body.name = "WaterBody"
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF_WIDTH * 2.0, BODY_LENGTH)
	plane.subdivide_width = 30 if quality == GraphicsQualityRules.LOW else 60
	plane.subdivide_depth = 40 if quality == GraphicsQualityRules.LOW else 90
	_body.mesh = plane
	_body.material_override = _body_material
	_body.position = Vector3(0.0, WATER_DEPTH, BACK_Z + BODY_OVERLAP - BODY_LENGTH * 0.5)
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)

	_ladder_material = body_material(quality)
	_ladder_material.set_shader_parameter("base_foam", 0.32)
	_ladder_material.set_shader_parameter("travelled", 1000.0)
	_ladder = MeshInstance3D.new()
	_ladder.name = "LadderWater"
	var ladder_plane := PlaneMesh.new()
	ladder_plane.size = Vector2(HALF_WIDTH * 2.0, 34.0)
	ladder_plane.subdivide_width = 24
	ladder_plane.subdivide_depth = 12
	_ladder.mesh = ladder_plane
	_ladder.material_override = _ladder_material
	_ladder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ladder.top_level = true
	_ladder.visible = false
	add_child(_ladder)

	var amount := float(GraphicsQualityRules.particle_amount(1000, quality)) / 1000.0
	# Droplets and streaks thrown off the crest, a white spume of dense spray over it, a thin mist ahead.
	_spray = _particles("Spray", int(900 * amount), 0.9, spray_material(ATLAS_DROPS, 0.85))
	_spray.position = Vector3(0.0, CREST_HEIGHT - 0.4, 0.3)
	_spray_process(_spray.process_material as ParticleProcessMaterial, Vector3(0.0, 0.5, 1.0), 28.0, Vector2(2.0, 6.0), Vector2(0.18, 0.55), ATLAS_DROPS)
	_spume = _particles("Spume", maxi(16, int(150 * amount)), 1.0, spray_material(ATLAS_SPUME, 0.38))
	_spume.position = Vector3(0.0, CREST_HEIGHT - 0.2, -0.2)
	_spray_process(_spume.process_material as ParticleProcessMaterial, Vector3(0.0, 0.7, 0.6), 35.0, Vector2(1.0, 3.2), Vector2(0.9, 2.2), ATLAS_SPUME)
	(_spume.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, -4.0, 0.0)
	_mist = _particles("Mist", maxi(8, int(30 * amount)), 1.6, spray_material(ATLAS_MIST, 0.11))
	_mist.position = Vector3(0.0, 2.0, -0.4)
	_spray_process(_mist.process_material as ParticleProcessMaterial, Vector3(0.0, 0.3, 1.0), 20.0, Vector2(0.3, 1.2), Vector2(4.0, 7.5), ATLAS_MIST)
	var mist_process := _mist.process_material as ParticleProcessMaterial
	mist_process.gravity = Vector3(0.0, -0.4, 0.0)
	mist_process.inherit_velocity_ratio = 0.85
	mist_process.damping_min = 1.5
	mist_process.damping_max = 2.5
	_set_fan_width(HALF_WIDTH)
	_drips = _particles("CeilingDrips", maxi(20, int(110 * amount)), 1.9, spray_material(ATLAS_STREAK, 0.55))
	_drips.top_level = true
	var drip_process := _drips.process_material as ParticleProcessMaterial
	drip_process.emission_box_extents = Vector3(17.0, 0.1, 23.0)
	_spray_process(drip_process, Vector3(0.0, -1.0, 0.0), 2.0, Vector2(0.0, 0.6), Vector2(0.12, 0.26), ATLAS_STREAK)
	drip_process.angle_min = 0.0
	drip_process.angle_max = 0.0
	drip_process.inherit_velocity_ratio = 0.0
	for index in range(BURST_POOL):
		var burst := _particles("Burst%d" % index, maxi(16, int(70 * amount)), 1.2, spray_material(ATLAS_SPRAY, 0.7))
		burst.one_shot = true
		burst.explosiveness = 0.92
		burst.emitting = false
		burst.top_level = true
		_spray_process(burst.process_material as ParticleProcessMaterial, Vector3(0.0, 0.7, 1.0), 38.0, Vector2(3.5, 8.5), Vector2(0.3, 1.2), ATLAS_SPRAY)
		(burst.process_material as ParticleProcessMaterial).inherit_velocity_ratio = 0.0
		_bursts.append(burst)
	for index in range(SPARK_POOL):
		var spark := _particles("Spark%d" % index, 40, 0.8, spark_material())
		spark.one_shot = true
		spark.explosiveness = 0.95
		spark.emitting = false
		spark.top_level = true
		var process := spark.process_material as ParticleProcessMaterial
		process.direction = Vector3(0.0, -0.3, 0.0)
		process.spread = 70.0
		process.initial_velocity_min = 2.0
		process.initial_velocity_max = 6.5
		process.gravity = Vector3(0.0, -9.8, 0.0)
		process.scale_min = 0.03
		process.scale_max = 0.07
		process.inherit_velocity_ratio = 0.0
		_sparks.append(spark)
	_built = true
	visible = false
	_apply_uniforms()


func _particles(node_name: String, amount: int, lifetime: float, material: Material) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = maxi(amount, 1)
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.process_material = ParticleProcessMaterial.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-60.0, -6.0, -30.0), Vector3(120.0, 30.0, 60.0))
	particles.emitting = false
	add_child(particles)
	return particles


func _spray_process(process: ParticleProcessMaterial, direction: Vector3, spread: float, speed: Vector2, size: Vector2, frames: Vector2) -> void:
	if process.emission_shape != ParticleProcessMaterial.EMISSION_SHAPE_BOX:
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.direction = direction
	process.spread = spread
	process.initial_velocity_min = speed.x
	process.initial_velocity_max = speed.y
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = size.x
	process.scale_max = size.y
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.damping_min = 0.4
	process.damping_max = 1.2
	process.anim_speed_min = 0.0
	process.anim_speed_max = 0.0
	process.anim_offset_min = frames.x / 16.0
	process.anim_offset_max = frames.y / 16.0
	# The spray travels with the front it was thrown from.
	process.inherit_velocity_ratio = 1.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.65, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp


# ------------------------------------------------------------------ materials (shared, also for the loader's warm-up)

static func _resolve_assets(assets: Array) -> void:
	if _shared.has("front_mesh"):
		return
	var paths := [FRONT_MESH_PATH if ResourceLoader.exists(FRONT_MESH_PATH) else FRONT_GLB_PATH,
		VAT_POS_PATH, VAT_NRM_PATH, FOAM_PATH, WATER_NORMAL_PATH, SPRAY_PATH]
	var resolved: Array = []
	for index in range(paths.size()):
		var resource: Resource = assets[index] if index < assets.size() and assets[index] != null else null
		if resource == null:
			resource = load(paths[index])
		resolved.append(resource)
	var mesh: Mesh = resolved[0] as Mesh
	if mesh == null and resolved[0] is PackedScene:
		mesh = front_mesh_from_scene(resolved[0] as PackedScene)
	_shared = {"front_mesh": mesh, "vat_pos": resolved[1], "vat_nrm": resolved[2], "foam": resolved[3],
		"water_normal": resolved[4], "spray": resolved[5]}


## The front's ArrayMesh out of the imported GLB.
static func front_mesh_from_scene(scene: PackedScene) -> Mesh:
	if scene == null:
		return null
	var root := scene.instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	root.free()
	return mesh


static func front_material() -> ShaderMaterial:
	_resolve_assets([])
	var material := ShaderMaterial.new()
	material.shader = FRONT_SHADER
	material.set_shader_parameter("vat_pos", _shared.vat_pos)
	material.set_shader_parameter("vat_nrm", _shared.vat_nrm)
	material.set_shader_parameter("foam_tex", _shared.foam)
	material.set_shader_parameter("water_normal", _shared.water_normal)
	material.set_shader_parameter("vat_frames", float(VAT_FRAMES))
	material.set_shader_parameter("vat_rows_per_frame", float(VAT_ROWS_PER_FRAME))
	material.set_shader_parameter("vat_width", float(VAT_WIDTH))
	material.set_shader_parameter("loop_seconds", LOOP_SECONDS)
	return material


static func body_material(p_quality: String) -> ShaderMaterial:
	_resolve_assets([])
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("water_normal", _shared.water_normal)
	material.set_shader_parameter("foam_tex", _shared.foam)
	var q := GraphicsQualityRules.normalize(p_quality)
	material.set_shader_parameter("ssr_steps", 0 if not GraphicsQualityRules.is_at_least(q, GraphicsQualityRules.HIGH) else (20 if q == GraphicsQualityRules.ULTRA else 12))
	return material


static func spray_material(frames: Vector2, alpha: float) -> StandardMaterial3D:
	_resolve_assets([])
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.particles_anim_h_frames = 4
	material.particles_anim_v_frames = 4
	material.particles_anim_loop = false
	material.albedo_texture = _shared.spray
	material.albedo_color = Color(0.74, 0.78, 0.78, alpha)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.9 if frames.x < 4.0 else 0.35
	material.roughness = 0.6
	return material


static func spark_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.albedo_color = Color(1.0, 0.72, 0.35)
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color(1.0, 0.6, 0.25)
	material.emission_energy_multiplier = 6.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## Every material this node draws, for SuddenDeathLoader's shader warm-up (all at once).
static func shader_samples(p_quality: String) -> Array[Material]:
	while not warm_up_step(p_quality):
		pass
	return _warm_samples.duplicate()


## One piece of the shared preparation per call (a loader spreads it over frames): the assets, then each
## material kind once (the first use of a shader compiles it). True when done; the samples are kept.
static func warm_up_step(p_quality: String) -> bool:
	if not _shared.has("front_mesh"):
		_resolve_assets([])
		return false
	var makers: Array[Callable] = [front_material, body_material.bind(p_quality), spray_material.bind(ATLAS_DROPS, 0.85),
		spray_material.bind(ATLAS_MIST, 0.11), spark_material]
	if _warm_samples.size() < makers.size():
		var material: Material = makers[_warm_samples.size()].call()
		material.get_rid()
		_warm_samples.append(material)
		return _warm_samples.size() >= makers.size()
	return true


# ------------------------------------------------------------------ per frame

## Shows / hides the flood (the director lets it out when the inflow gate opens).
func set_wave_on(on: bool) -> void:
	_wave_on = on
	visible = on or (_ladder != null and _ladder.visible)
	if _built:
		_front.visible = on
		_body.visible = on
		_spray.emitting = on
		_spume.emitting = on
		_mist.emitting = on


func is_wave_on() -> bool:
	return _wave_on


## [param front_z]: the state's front (world). [param speed] m/s. [param receding]: the both-wrong pump-back.
## [param game_dt] advances the water (slow motion slows it).
func update_wave(game_dt: float, front_z: float, speed: float, receding: bool) -> void:
	if not _built:
		return
	clock = fmod(clock + maxf(game_dt, 0.0), LOOP_SECONDS * 1000.0)
	_front_z = front_z
	_speed = speed
	_height = move_toward(_height, 0.5 if receding else 1.0, game_dt * (1.6 if receding else 0.8))
	_boost = move_toward(_boost, 0.0, game_dt / GUSH_FOAM_TIME)
	_travelled = maxf(_travelled, front_z - TUNNEL_Z)
	position = Vector3(0.0, SuddenDeathLayout.FLOOR_Y, front_z - TOE_OFFSET)
	var ratio := maxf(clampf(0.25 + 0.75 * speed / 10.0, 0.2, 1.0) * (0.35 if receding else 1.0), _boost)
	_spray.amount_ratio = ratio
	_spume.amount_ratio = ratio
	_set_fan_width(fan_half(front_z, _travelled))
	_apply_uniforms()


## Half width (m) the flood covers at world z after travelling [param travelled] m from the tunnel.
static func fan_half(z: float, travelled: float) -> float:
	var t := clampf(((z - TUNNEL_Z) + 0.8 * travelled) / FAN_DISTANCE, 0.0, 1.0)
	return FAN_START + (HALF_WIDTH - FAN_START) * t * t * (3.0 - 2.0 * t)


func _set_fan_width(half_width: float) -> void:
	for particles: GPUParticles3D in [_spray, _spume, _mist]:
		if particles != null:
			var process := particles.process_material as ParticleProcessMaterial
			var mist := particles == _mist
			process.emission_box_extents = Vector3(maxf(half_width - 1.0, 1.0), 0.9 if mist else 0.45, 1.3 if mist else 0.9)


## Water rising at the exit ladder (state water_level, metres over the floor) in front of the end wall.
func set_ladder_water(level: float, wall_z: float) -> void:
	if not _built:
		return
	_ladder.visible = level > 0.0
	if _ladder.visible:
		_ladder.global_position = Vector3(0.0, SuddenDeathLayout.FLOOR_Y + level, wall_z - 17.0)
		_ladder_material.set_shader_parameter("front_z", wall_z)
		_ladder_material.set_shader_parameter("clock", clock)
		_ladder_material.set_shader_parameter("flow_speed", 1.5)
	visible = _wave_on or _ladder.visible


## How lit the hall is around the front (0..1): the turbid water's scattered glow follows it.
func set_hall_light(amount: float) -> void:
	if _built:
		_front_material.set_shader_parameter("hall_light", clampf(amount, 0.0, 1.0))


## Ceiling drips fall around [param focus] (world).
func set_drips(on: bool, focus: Vector3) -> void:
	if not _built:
		return
	_drips.emitting = on
	_drips.global_position = Vector3(focus.x, SuddenDeathLayout.FLOOR_Y + DRIP_HEIGHT, focus.z + 6.0)


## A splash thrown up where the flood hits something (a pillar face, a gate post, a swallowed runner).
## [param direction]: the main throw (world).
func burst(at: Vector3, direction: Vector3 = Vector3(0.0, 0.7, 1.0), strength: float = 1.0) -> void:
	if not _built or _bursts.is_empty():
		return
	var particles := _bursts[_burst_next]
	_burst_next = (_burst_next + 1) % _bursts.size()
	var process := particles.process_material as ParticleProcessMaterial
	process.direction = direction.normalized()
	process.initial_velocity_min = 3.0 * strength
	process.initial_velocity_max = 8.5 * strength
	particles.global_position = at
	particles.restart()
	particles.emitting = true
	_bursts_fired += 1


## Sparks from a light fitting dying in the flood.
func spark(at: Vector3) -> void:
	if not _built or _sparks.is_empty():
		return
	var particles := _sparks[_spark_next]
	_spark_next = (_spark_next + 1) % _sparks.size()
	particles.global_position = at
	particles.restart()
	particles.emitting = true


## The flood bursts out of the inflow tunnel as the gate lifts.
func gush(tunnel_center: Vector3) -> void:
	_boost = 1.0
	for index in range(5):
		var across := float(index - 2)
		burst(tunnel_center + Vector3(across * 1.8, -2.4 + absf(across) * 0.3, 1.0), Vector3(across * 0.2, 0.45, 1.0), 2.0)


func _apply_uniforms() -> void:
	_front_material.set_shader_parameter("clock", clock)
	_front_material.set_shader_parameter("height_scale", _height)
	_front_material.set_shader_parameter("travelled", _travelled)
	_front_material.set_shader_parameter("foam_boost", _boost)
	_body_material.set_shader_parameter("travelled", _travelled)
	_body_material.set_shader_parameter("clock", clock)
	_body_material.set_shader_parameter("front_z", _front_z)
	_body_material.set_shader_parameter("flow_speed", maxf(_speed * 0.75, 2.0))
	_body.position.y = WATER_DEPTH * _height


## For the loader's pipeline warm-up, in [param at] (world z): stage 1 the water (front, body, ladder
## water), stage 2 the particles (spray, mist, drips, a burst, sparks). One stage per frame keeps each
## frame's first-draw compiles short. prewarm(false) puts everything away.
func prewarm(on: bool, at_z: float, stage: int = 3) -> void:
	if not _built:
		return
	if on:
		if stage & 1:
			_wave_on = true
			visible = true
			_front.visible = true
			_body.visible = true
			update_wave(0.016, at_z, 9.0, false)
			set_ladder_water(1.0, at_z + 30.0)
		if stage & 2:
			set_wave_on(true)
			update_wave(0.016, at_z, 9.0, false)
			set_drips(true, Vector3(0.0, 0.0, at_z + 4.0))
			burst(Vector3(0.0, SuddenDeathLayout.FLOOR_Y + 1.0, at_z + 2.0))
			spark(Vector3(4.0, SuddenDeathLayout.FLOOR_Y + 5.0, at_z + 4.0))
	else:
		set_wave_on(false)
		_travelled = 0.0
		_boost = 0.0
		_height = 1.0
		set_ladder_water(0.0, 0.0)
		set_drips(false, Vector3.ZERO)
		for particles: GPUParticles3D in _bursts + _sparks:
			particles.emitting = false
			particles.restart()
			particles.emitting = false


func get_debug_snapshot() -> Dictionary:
	return {"built": _built, "on": _wave_on, "visible": visible, "front_z": snappedf(_front_z, 0.01),
		"node_z": snappedf(position.z, 0.01), "height": snappedf(_height, 0.01), "travelled": snappedf(_travelled, 0.01),
		"fan_half": snappedf(fan_half(_front_z, _travelled), 0.01),
		"clock": snappedf(clock, 0.01), "ladder": _ladder != null and _ladder.visible,
		"spray": _spray != null and _spray.emitting, "drips": _drips != null and _drips.emitting,
		"bursts": _bursts_fired}
