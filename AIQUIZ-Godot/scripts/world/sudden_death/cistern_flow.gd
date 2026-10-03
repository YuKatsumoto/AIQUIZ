class_name CisternFlow
extends Node3D

## 地下神殿の水（docs/sudden_death_underground.md 6.6節）。流入トンネルから噴き出した鉄砲水が床を走り、
## 地下神殿を水位 water_level まで満たし、その後も流れ続ける様子を、GPU の流体シミュレーション（浅水方程式、
## shaders/sudden_death/cistern_flow.glsl）で毎フレーム解く。柱とリフトのタワーは流れを分け、その後ろに
## 渦と泡の筋ができる。負けたリフトが沈むとき・走者が落ちたときは、しぶき（splash）で波を立てる。
## 判定は持たない：ルールの水位は SuddenDeathTuning.water_level で決まり、ここはその見た目。
##
## シミュレーションの範囲は地下神殿の全幅（x = −45〜+45m）と上流端から下流 42m まで（z = −30〜+42m）、
## 0.3m の格子（300×240）。本戦のカメラは上流から下流を向き、手前の水と2本のタワーの周りがこの範囲に入る。
## 1/120秒刻みで1フレームに数回進める。範囲より下流は水位に置いた平らな水面（FloodWave の水面の材質）で続ける。描画デバイスがない環境（ヘッドレス）や Compatibility では
## シミュレーションをせず、水位に置いた平らな水面だけを出す。

const COMPUTE_PATH := "res://shaders/sudden_death/cistern_flow.glsl"
const SURFACE_SHADER := preload("res://shaders/sudden_death/cistern_flow_surface.gdshader")
const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")

const GRID := Vector2i(300, 240)
const CELL := 0.3
## World x, z of the corner of cell (0, 0).
const ORIGIN := Vector2(-45.0, -30.0)
const SIM_DT := 1.0 / 120.0
## A long frame is not caught up beyond this many steps (the water just runs a little slow).
const MAX_SUBSTEPS := 4
const GRAVITY := 9.81
## Depth below which a cell counts as dry (m).
const DRY_DEPTH := 0.002
## Floor height of a pillar or wall cell in the bed image (anything at or over 20 m is solid).
const WALL_HEIGHT := 30.0
## Water faster than this is clamped (under half a cell a step). A cell that would empty below zero is
## clamped at zero; the level control puts the little water this adds back where it belongs.
const MAX_SPEED := 0.45 * CELL / SIM_DT
## The tunnel mouth (upstream end wall, x = ±5 m): the flood's opening burst, then the steady inflow.
const INFLOW_HALF_WIDTH := 4.6
const GUSH_LEVEL := 2.2
const GUSH_SPEED := 8.5
const STEADY_SPEED := 3.8
const STEADY_HEAD := 0.5
## Once the front is out (FILL_FROM s), the wet water behind it is pulled up toward this much over the
## target level (the hall filling fast), easing to the level by FILL_SETTLE seconds after the gate opened.
const FILL_OVERSHOOT := 0.3
const FILL_RATE := 1.2
const FILL_FROM := Vector2(1.2, 3.5)
const FILL_SETTLE := 6.5
## Water over the level is let down gently while the flood runs out (so its bore carries on), firmly once
## it has settled.
const RELAX_RATE := Vector2(0.06, 0.25)
## Downstream the simulated water leaves through an absorbing band (no reflection off the grid edge).
const SPONGE_Z := 34.0
const SPONGE_RATE := 3.0
const OUTFLOW_SPEED := 1.2
## Foam: decay time, gain with speed over FOAM_SPEED, gain where the water piles up, at the tunnel mouth.
const FOAM_DECAY := 1.8
const FOAM_SPEED_GAIN := 0.12
const FOAM_COMPRESSION_GAIN := 0.45
const FOAM_INFLOW := 0.7
const FOAM_SPEED := 2.4
const LINEAR_DAMPING := 0.08
const BOTTOM_FRICTION := 0.004
## Foam made where shallow water runs fast (the flood's leading edge).
const FRONT_FOAM_GAIN := 1.2
## Once the hall has filled, the water is steered toward a current running downstream (the pumps at the far
## end draw it on), so the towers stand in a stream and shed eddies into it.
const CURRENT_SPEED := 1.2
const CURRENT_STEER := 0.35
const CURRENT_FROM := Vector2(3.0, 8.0)
## Foam where the current curls (the vorticity over this many radians a second).
const VORTICITY_FOAM := 0.45
const VORTICITY_FROM := 0.5
## The flood's leading edge as the presentation estimates it (the sim runs on the GPU): about this fast
## out of the tunnel, fanning out to the hall's width; spray and mist ride it and hide its ragged rim.
const FRONT_SPEED := 6.8
const FRONT_FAN := 0.9
const FRONT_SPRAY_UNTIL := 72.0
## Splashes queued beyond the two a frame carries wait for the next frame.
const SPLASH_SLOTS := 2
## vec4s in the compute shader's Params block.
const PARAM_VEC4S := 12
const BURST_POOL := 8
## The flat water downstream of the simulation (to the far end of the hall).
const FAR_START_Z := 42.0
const FAR_END_Z := 210.0
const HALL_HALF_WIDTH := 45.0

var quality := GraphicsQualityRules.BALANCED
## Game seconds the water has run (the shader's clock).
var clock := 0.0

var _built := false
var _uses_gpu := false
var _rd_ready := false
var _rd: RenderingDevice = null
var _spirv: RDShaderSPIRV = null
var _shader := RID()
var _pipeline := RID()
var _state: Array[RID] = [RID(), RID()]
var _bed := RID()
var _display := RID()
var _params := RID()
## _sets[0] reads state 0 and writes state 1; _sets[1] the other way.
var _sets: Array[RID] = [RID(), RID()]
## Which state image holds the current water (render thread only).
var _current := 0
var _clear_pending := true

var _surface: MeshInstance3D = null
var _surface_material: ShaderMaterial = null
var _display_texture: Texture2DRD = null
var _far: MeshInstance3D = null
var _far_material: ShaderMaterial = null
var _flat: MeshInstance3D = null
var _flat_material: ShaderMaterial = null
var _bursts: Array[GPUParticles3D] = []
var _burst_next := 0
var _jet: GPUParticles3D = null
var _mist: GPUParticles3D = null
var _front_spray: GPUParticles3D = null
var _front_mist: GPUParticles3D = null
var _drips: GPUParticles3D = null

## Water state the presentation sets.
var _level := 1.2
var _flood_on := false
var _flood_time := 0.0
var _towers: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO]
var _splashes: Array[Vector4] = []
var _accumulator := 0.0
var _frames := 0
var _steps := 0
var _readback := PackedByteArray()
var _readback_frame := -1
var _bursts_fired := 0


# ------------------------------------------------------------------ build

## [param assets]: the cistern scene's flood assets ([front mesh, VAT position, VAT normal, foam,
## water normal, spray atlas]); only the foam, the water normal and the spray atlas are used here.
func setup(p_quality: String, assets: Array = []) -> void:
	if _built:
		return
	quality = GraphicsQualityRules.normalize(p_quality)
	name = "CisternFlow" if name.is_empty() or name.begins_with("@") else name
	var foam: Texture2D = assets[3] if assets.size() > 3 and assets[3] is Texture2D else load(FloodWave.FOAM_PATH)
	var water_normal: Texture2D = assets[4] if assets.size() > 4 and assets[4] is Texture2D else load(FloodWave.WATER_NORMAL_PATH)
	_uses_gpu = RenderingServer.get_rendering_device() != null and ResourceLoader.exists(COMPUTE_PATH)
	if _uses_gpu:
		var file := load(COMPUTE_PATH) as RDShaderFile
		_spirv = file.get_spirv() if file != null else null
		if _spirv == null or not _spirv.compile_error_compute.is_empty():
			push_warning("[CisternFlow] compute shader unavailable: %s" % (_spirv.compile_error_compute if _spirv != null else "missing"))
			_uses_gpu = false
	_build_surface(foam, water_normal)
	_build_far(p_quality)
	_build_particles()
	if _uses_gpu:
		var bed := bed_heights().to_byte_array()
		RenderingServer.call_on_render_thread(_rd_init.bind(bed, _spirv))
	_built = true
	visible = false


func _build_surface(foam: Texture2D, water_normal: Texture2D) -> void:
	_surface_material = ShaderMaterial.new()
	_surface_material.shader = SURFACE_SHADER
	_surface_material.set_shader_parameter("grid_origin", ORIGIN)
	_surface_material.set_shader_parameter("grid_cell", CELL)
	_surface_material.set_shader_parameter("grid_size", GRID)
	_surface_material.set_shader_parameter("water_normal", water_normal)
	_surface_material.set_shader_parameter("foam_tex", foam)
	_surface_material.set_shader_parameter("ssr_steps", ssr_steps(quality))
	_display_texture = Texture2DRD.new()
	_surface_material.set_shader_parameter("display_tex", _display_texture)
	var plane := PlaneMesh.new()
	# One vertex at the centre of every cell.
	plane.size = Vector2(float(GRID.x - 1) * CELL, float(GRID.y - 1) * CELL)
	plane.subdivide_width = GRID.x - 2
	plane.subdivide_depth = GRID.y - 2
	_surface = MeshInstance3D.new()
	_surface.name = "FlowSurface"
	_surface.mesh = plane
	_surface.material_override = _surface_material
	_surface.position = Vector3(ORIGIN.x + float(GRID.x) * CELL * 0.5, SuddenDeathLayout.FLOOR_Y,
		ORIGIN.y + float(GRID.y) * CELL * 0.5)
	var half := Vector2(float(GRID.x) * CELL, float(GRID.y) * CELL) * 0.5
	_surface.custom_aabb = AABB(Vector3(-half.x - 1.0, -1.0, -half.y - 1.0), Vector3(half.x * 2.0 + 2.0, 9.0, half.y * 2.0 + 2.0))
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.visible = false
	add_child(_surface)


## Flat water at the level: downstream of the simulation always, and over it without a GPU.
func _build_far(p_quality: String) -> void:
	_far_material = FloodWave.body_material(p_quality)
	_far_material.set_shader_parameter("travelled", 1000.0)
	_far_material.set_shader_parameter("front_z", 10000.0)
	_far_material.set_shader_parameter("base_foam", 0.1)
	_far_material.set_shader_parameter("flow_speed", 1.2)
	_far = _flat_plane("FarWater", FAR_START_Z - 0.3, FAR_END_Z, _far_material)
	_flat_material = FloodWave.body_material(p_quality)
	_flat_material.set_shader_parameter("travelled", 1000.0)
	_flat_material.set_shader_parameter("front_z", 10000.0)
	_flat_material.set_shader_parameter("base_foam", 0.16)
	_flat_material.set_shader_parameter("flow_speed", 2.0)
	_flat = _flat_plane("FlatWater", ORIGIN.y, FAR_START_Z, _flat_material)


func _flat_plane(node_name: String, from_z: float, to_z: float, material: ShaderMaterial) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALL_HALF_WIDTH * 2.0, to_z - from_z)
	plane.subdivide_width = 24
	plane.subdivide_depth = maxi(8, int((to_z - from_z) / 4.0))
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = plane
	instance.material_override = material
	instance.position = Vector3(0.0, SuddenDeathLayout.FLOOR_Y - 1.0, (from_z + to_z) * 0.5)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	add_child(instance)
	return instance


func _build_particles() -> void:
	var amount := float(GraphicsQualityRules.particle_amount(1000, quality)) / 1000.0
	for index in range(BURST_POOL):
		var burst := _particles("Splash%d" % index, maxi(16, int(80 * amount)), 1.3, FloodWave.spray_material(FloodWave.ATLAS_SPRAY, 0.75))
		burst.one_shot = true
		burst.explosiveness = 0.9
		_spray_process(burst.process_material as ParticleProcessMaterial, Vector3(0.0, 1.0, 0.0), 32.0, Vector2(3.0, 7.5), Vector2(0.3, 1.1), FloodWave.ATLAS_SPRAY)
		_bursts.append(burst)
	# The burst out of the tunnel mouth: droplets and a white spume over the jet, a mist ahead of it.
	_jet = _particles("TunnelJet", maxi(24, int(500 * amount)), 1.0, FloodWave.spray_material(FloodWave.ATLAS_DROPS, 0.85))
	_spray_process(_jet.process_material as ParticleProcessMaterial, Vector3(0.0, 0.35, 1.0), 22.0, Vector2(4.0, 9.0), Vector2(0.2, 0.6), FloodWave.ATLAS_DROPS)
	(_jet.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(INFLOW_HALF_WIDTH, 0.6, 0.4)
	_jet.position = Vector3(0.0, SuddenDeathLayout.FLOOR_Y + 1.6, ORIGIN.y + 0.8)
	_mist = _particles("TunnelMist", maxi(8, int(36 * amount)), 2.0, FloodWave.spray_material(FloodWave.ATLAS_MIST, 0.12))
	_spray_process(_mist.process_material as ParticleProcessMaterial, Vector3(0.0, 0.25, 1.0), 25.0, Vector2(0.8, 2.4), Vector2(4.0, 7.0), FloodWave.ATLAS_MIST)
	var mist_process := _mist.process_material as ParticleProcessMaterial
	mist_process.emission_box_extents = Vector3(INFLOW_HALF_WIDTH + 1.0, 1.2, 1.0)
	mist_process.gravity = Vector3(0.0, -0.3, 0.0)
	_mist.position = Vector3(0.0, SuddenDeathLayout.FLOOR_Y + 2.2, ORIGIN.y + 2.5)
	_front_spray = _particles("FrontSpray", maxi(24, int(700 * amount)), 0.9, FloodWave.spray_material(FloodWave.ATLAS_DROPS, 0.8))
	_spray_process(_front_spray.process_material as ParticleProcessMaterial, Vector3(0.0, 0.7, 1.0), 30.0, Vector2(2.0, 5.5), Vector2(0.2, 0.6), FloodWave.ATLAS_DROPS)
	_front_mist = _particles("FrontMist", maxi(8, int(60 * amount)), 1.4, FloodWave.spray_material(FloodWave.ATLAS_SPUME, 0.3))
	_spray_process(_front_mist.process_material as ParticleProcessMaterial, Vector3(0.0, 0.6, 0.8), 35.0, Vector2(0.8, 2.6), Vector2(1.0, 2.4), FloodWave.ATLAS_SPUME)
	(_front_mist.process_material as ParticleProcessMaterial).gravity = Vector3(0.0, -3.0, 0.0)
	_drips = _particles("CeilingDrips", maxi(20, int(110 * amount)), 1.9, FloodWave.spray_material(FloodWave.ATLAS_STREAK, 0.55))
	var drip_process := _drips.process_material as ParticleProcessMaterial
	_spray_process(drip_process, Vector3(0.0, -1.0, 0.0), 2.0, Vector2(0.0, 0.6), Vector2(0.12, 0.26), FloodWave.ATLAS_STREAK)
	drip_process.emission_box_extents = Vector3(17.0, 0.1, 23.0)
	drip_process.angle_min = 0.0
	drip_process.angle_max = 0.0


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
	particles.visibility_aabb = AABB(Vector3(-60.0, -6.0, -40.0), Vector3(120.0, 30.0, 120.0))
	particles.emitting = false
	particles.top_level = true
	add_child(particles)
	return particles


func _spray_process(process: ParticleProcessMaterial, direction: Vector3, spread: float, speed: Vector2, size: Vector2, frames: Vector2) -> void:
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.6, 0.2, 0.6)
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
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.65, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp


static var _warm_samples: Array[Material] = []


## One piece of the shared preparation per call (a loader spreads it over frames): each material kind
## the water draws, once (the first use of a shader compiles it). True when done; the samples are kept.
static func warm_up_step(p_quality: String) -> bool:
	var makers: Array[Callable] = [
		func() -> Material:
			var material := ShaderMaterial.new()
			material.shader = SURFACE_SHADER
			material.set_shader_parameter("ssr_steps", ssr_steps(p_quality))
			return material,
		FloodWave.body_material.bind(p_quality),
		FloodWave.spray_material.bind(FloodWave.ATLAS_DROPS, 0.85),
		FloodWave.spray_material.bind(FloodWave.ATLAS_MIST, 0.12),
		FloodWave.spray_material.bind(FloodWave.ATLAS_SPRAY, 0.75),
		FloodWave.spray_material.bind(FloodWave.ATLAS_STREAK, 0.55),
	]
	if _warm_samples.size() < makers.size():
		var material: Material = makers[_warm_samples.size()].call()
		material.get_rid()
		_warm_samples.append(material)
		return _warm_samples.size() >= makers.size()
	return true


static func ssr_steps(p_quality: String) -> int:
	var q := GraphicsQualityRules.normalize(p_quality)
	if not GraphicsQualityRules.is_at_least(q, GraphicsQualityRules.HIGH):
		return 0
	return 20 if q == GraphicsQualityRules.ULTRA else 12


## The hall floor as the simulation sees it (nx * nz heights over the floor, row by row from the
## upstream end): 0 on the open floor, WALL_HEIGHT inside the pillars.
static func bed_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(GRID.x * GRID.y)
	heights.fill(0.0)
	var half := Vector2(SuddenDeathLayout.PILLAR_SIZE.x, SuddenDeathLayout.PILLAR_SIZE.z) * 0.5
	for column: float in SuddenDeathLayout.PILLAR_COLUMNS:
		for row_z: float in SuddenDeathLayout.pillar_row_zs():
			var from := cell_of(Vector2(column - half.x, row_z - half.y))
			var to := cell_of(Vector2(column + half.x, row_z + half.y))
			for j in range(maxi(from.y, 0), mini(to.y + 1, GRID.y)):
				for i in range(maxi(from.x, 0), mini(to.x + 1, GRID.x)):
					var centre := ORIGIN + (Vector2(i, j) + Vector2(0.5, 0.5)) * CELL
					if absf(centre.x - column) <= half.x and absf(centre.y - row_z) <= half.y:
						heights[j * GRID.x + i] = WALL_HEIGHT
	return heights


static func cell_of(world_xz: Vector2) -> Vector2i:
	return Vector2i(floori((world_xz.x - ORIGIN.x) / CELL), floori((world_xz.y - ORIGIN.y) / CELL))


# ------------------------------------------------------------------ control (main thread)

## Shows the water and lets the flood out of the tunnel (the inflow gate has lifted).
func start_flood() -> void:
	_flood_on = true
	_flood_time = 0.0
	visible = true
	_jet.emitting = true
	_mist.emitting = true
	for index in range(5):
		var across := float(index - 2)
		burst(Vector3(across * 1.8, SuddenDeathLayout.FLOOR_Y + 2.0 + absf(across) * 0.2, ORIGIN.y + 1.0),
			Vector3(across * 0.15, 0.45, 1.0), 2.0)


func is_flooding() -> bool:
	return _flood_on


## Game seconds since the gate opened (0 before).
func flood_time() -> float:
	return _flood_time


## The level the hall fills to and is held at (m over the floor).
func set_level(level: float) -> void:
	_level = maxf(level, 0.0)


func level() -> float:
	return _level


## A lift tower standing in the water: [param top] its platform's height over the floor (the water
## flows over it once it is under). [param radius] 0 removes it.
func set_tower(index: int, world_xz: Vector2, radius: float, top: float) -> void:
	if index >= 0 and index < _towers.size():
		_towers[index] = Vector4(world_xz.x, world_xz.y, radius, top)


## Something hit the water at [param at] (world): a ring of water thrown up around a hole
## [param radius] m across, [param strength] m high, and a burst of spray.
func splash(at: Vector3, radius: float, strength: float, spray := true) -> void:
	_splashes.append(Vector4(at.x, at.z, maxf(radius, CELL * 2.0), strength))
	if spray:
		burst(Vector3(at.x, SuddenDeathLayout.FLOOR_Y + _level + 0.1, at.z), Vector3(0.0, 1.0, 0.0), clampf(strength * 2.2, 0.5, 2.0))


## A burst of spray at [param at] (world), thrown along [param direction].
func burst(at: Vector3, direction: Vector3 = Vector3.UP, strength: float = 1.0) -> void:
	if _bursts.is_empty():
		return
	var particles := _bursts[_burst_next]
	_burst_next = (_burst_next + 1) % _bursts.size()
	var process := particles.process_material as ParticleProcessMaterial
	process.direction = direction.normalized()
	process.initial_velocity_min = 2.5 * strength
	process.initial_velocity_max = 7.0 * strength
	particles.global_position = at
	particles.restart()
	particles.emitting = true
	_bursts_fired += 1


## Ceiling drips fall around [param focus] (world).
func set_drips(on: bool, focus: Vector3) -> void:
	_drips.emitting = on
	_drips.global_position = Vector3(focus.x, SuddenDeathLayout.FLOOR_Y + 17.5, focus.z)


## Dry hall, no flood (a new match, or after the prewarm).
func reset() -> void:
	_flood_on = false
	_flood_time = 0.0
	_splashes.clear()
	_accumulator = 0.0
	visible = false
	if _jet != null:
		_jet.emitting = false
		_mist.emitting = false
		_drips.emitting = false
		_front_spray.emitting = false
		_front_mist.emitting = false
	_clear_pending = true
	if _uses_gpu:
		RenderingServer.call_on_render_thread(_rd_clear)


func uses_simulation() -> bool:
	return _uses_gpu


func is_simulation_ready() -> bool:
	return _uses_gpu and _rd_ready


## Advances the water by [param game_dt] (slow motion slows it) and draws it. CisternStage calls this
## every frame while the hall is shown.
func update_flow(game_dt: float) -> void:
	if not _built:
		return
	var dt := clampf(game_dt, 0.0, 0.25)
	clock = fmod(clock + dt, 3600.0)
	if _flood_on:
		_flood_time += dt
	var target := _target_level()
	var inflow := _inflow()
	_surface_material.set_shader_parameter("clock", clock)
	_far_material.set_shader_parameter("clock", clock)
	_flat_material.set_shader_parameter("clock", clock)
	# Downstream and (without a GPU) over the simulated part: flat water rising with the fill.
	# The simulated flood reaches the far end of its grid after about ten seconds.
	var fill := smoothstep(7.0, 10.5, _flood_time) if _flood_on else 0.0
	_far.visible = _flood_on and fill > 0.01
	_far.position.y = SuddenDeathLayout.FLOOR_Y + lerpf(-0.6, _level, fill)
	_flat.visible = _flood_on and not is_simulation_ready()
	_flat.position.y = SuddenDeathLayout.FLOOR_Y + lerpf(-0.6, _level, smoothstep(0.0, 3.0, _flood_time))
	_surface.visible = _flood_on and is_simulation_ready()
	if _jet != null:
		(_jet.process_material as ParticleProcessMaterial).initial_velocity_max = lerpf(9.0, 4.0, smoothstep(1.5, FILL_SETTLE, _flood_time))
		_jet.amount_ratio = lerpf(1.0, 0.35, smoothstep(1.5, FILL_SETTLE, _flood_time))
		_update_front()
	if not _uses_gpu or not _rd_ready:
		_splashes.clear()
		return
	if _display_texture.texture_rd_rid != _display:
		_display_texture.texture_rd_rid = _display
	if not _flood_on:
		return
	_accumulator = minf(_accumulator + dt, SIM_DT * float(MAX_SUBSTEPS))
	var steps := int(floor(_accumulator / SIM_DT + 0.0001))
	_accumulator -= float(steps) * SIM_DT
	var splash_a := Vector4.ZERO
	var splash_b := Vector4.ZERO
	if steps > 0:
		splash_a = _splashes.pop_front() if not _splashes.is_empty() else Vector4.ZERO
		splash_b = _splashes.pop_front() if not _splashes.is_empty() else Vector4.ZERO
	var params := PackedFloat32Array([
		float(GRID.x), float(GRID.y), CELL, SIM_DT,
		ORIGIN.x, ORIGIN.y, GRAVITY, clock,
		target.x, target.y, lerpf(RELAX_RATE.x, RELAX_RATE.y, smoothstep(2.5, FILL_SETTLE, _flood_time)), DRY_DEPTH,
		INFLOW_HALF_WIDTH, inflow.x, inflow.y, 1.0 if _flood_on else 0.0,
		SPONGE_Z, SPONGE_RATE, OUTFLOW_SPEED, MAX_SPEED,
		_towers[0].x, _towers[0].y, _towers[0].z, _towers[0].w,
		_towers[1].x, _towers[1].y, _towers[1].z, _towers[1].w,
		splash_a.x, splash_a.y, splash_a.z, splash_a.w,
		splash_b.x, splash_b.y, splash_b.z, splash_b.w,
		FOAM_DECAY, FOAM_SPEED_GAIN, FOAM_COMPRESSION_GAIN, FOAM_INFLOW,
		LINEAR_DAMPING, BOTTOM_FRICTION, FOAM_SPEED, FRONT_FOAM_GAIN,
		CURRENT_STEER * smoothstep(CURRENT_FROM.x, CURRENT_FROM.y, _flood_time), VORTICITY_FOAM, VORTICITY_FROM, CURRENT_SPEED,
	])
	_frames += 1
	_steps += steps
	RenderingServer.call_on_render_thread(_rd_step.bind(params.to_byte_array(), steps))


## The spray and mist on the flood's leading edge (estimated: it fans out of the tunnel at FRONT_SPEED).
func _update_front() -> void:
	var travelled := FRONT_SPEED * _flood_time
	var on := _flood_on and travelled < FRONT_SPRAY_UNTIL
	if _front_spray.emitting != on:
		_front_spray.emitting = on
		_front_mist.emitting = on
	if not on:
		return
	var half := clampf(INFLOW_HALF_WIDTH + FRONT_FAN * travelled, INFLOW_HALF_WIDTH, HALL_HALF_WIDTH - 1.0)
	var at := Vector3(0.0, SuddenDeathLayout.FLOOR_Y + 0.5, ORIGIN.y + travelled)
	for particles: GPUParticles3D in [_front_spray, _front_mist]:
		particles.global_position = at
		(particles.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(half, 0.35, 0.8)
		# Thinner as it spreads.
		particles.amount_ratio = clampf(1.0 - travelled / FRONT_SPRAY_UNTIL, 0.25, 1.0)


func front_distance() -> float:
	return FRONT_SPEED * _flood_time if _flood_on else 0.0


## (target level, fill rate): overfilled while the flood comes in, then held at the level.
func _target_level() -> Vector2:
	if not _flood_on:
		return Vector2(0.0, 0.0)
	var settle := smoothstep(2.5, FILL_SETTLE, _flood_time)
	return Vector2(_level + FILL_OVERSHOOT * (1.0 - settle), FILL_RATE * smoothstep(FILL_FROM.x, FILL_FROM.y, _flood_time))


## (surface level at the tunnel mouth, speed): the burst, then the steady current.
func _inflow() -> Vector2:
	var settle := smoothstep(1.5, FILL_SETTLE, _flood_time)
	return Vector2(lerpf(GUSH_LEVEL, _level + STEADY_HEAD, settle), lerpf(GUSH_SPEED, STEADY_SPEED, settle))


# ------------------------------------------------------------------ render thread

func _rd_init(bed_bytes: PackedByteArray, spirv: RDShaderSPIRV) -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null or spirv == null:
		return
	_shader = _rd.shader_create_from_spirv(spirv, "CisternFlow")
	if not _shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var state_format := RDTextureFormat.new()
	state_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	state_format.width = GRID.x + 1
	state_format.height = GRID.y + 1
	state_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	for index in range(2):
		_state[index] = _rd.texture_create(state_format, RDTextureView.new(), [])
		_rd.texture_clear(_state[index], Color(0, 0, 0, 0), 0, 1, 0, 1)
	var bed_format := RDTextureFormat.new()
	bed_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	bed_format.width = GRID.x
	bed_format.height = GRID.y
	bed_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_bed = _rd.texture_create(bed_format, RDTextureView.new(), [bed_bytes])
	var display_format := RDTextureFormat.new()
	display_format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	display_format.width = GRID.x
	display_format.height = GRID.y
	display_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	_display = _rd.texture_create(display_format, RDTextureView.new(), [])
	_rd.texture_clear(_display, Color(-0.3, 0.0, 0.0, -1.0), 0, 1, 0, 1)
	var zeros := PackedByteArray()
	zeros.resize(PARAM_VEC4S * 16)
	_params = _rd.uniform_buffer_create(zeros.size(), zeros)
	for index in range(2):
		var uniforms: Array[RDUniform] = [
			_image_uniform(0, _state[index]), _image_uniform(1, _state[1 - index]),
			_image_uniform(2, _bed), _image_uniform(3, _display),
		]
		var buffer := RDUniform.new()
		buffer.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		buffer.binding = 4
		buffer.add_id(_params)
		uniforms.append(buffer)
		_sets[index] = _rd.uniform_set_create(uniforms, _shader, 0)
	_current = 0
	_rd_ready = true


static func _image_uniform(binding: int, texture: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(texture)
	return uniform


func _rd_clear() -> void:
	if not _rd_ready:
		return
	for index in range(2):
		_rd.texture_clear(_state[index], Color(0, 0, 0, 0), 0, 1, 0, 1)
	_rd.texture_clear(_display, Color(-0.3, 0.0, 0.0, -1.0), 0, 1, 0, 1)
	_current = 0


func _rd_step(params: PackedByteArray, steps: int) -> void:
	if not _rd_ready:
		return
	_rd.buffer_update(_params, 0, params.size(), params)
	var groups := Vector2i(ceili(float(GRID.x + 1) / 8.0), ceili(float(GRID.y + 1) / 8.0))
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	for step in range(steps):
		for pass_id in range(3):
			_rd.compute_list_bind_uniform_set(list, _sets[_current], 0)
			var push := PackedInt32Array([pass_id, 1 if step == 0 else 0, 0, 0]).to_byte_array()
			_rd.compute_list_set_push_constant(list, push, push.size())
			_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
			_rd.compute_list_add_barrier(list)
			_current = 1 - _current
	_rd.compute_list_bind_uniform_set(list, _sets[_current], 0)
	var display_push := PackedInt32Array([3, 0, 0, 0]).to_byte_array()
	_rd.compute_list_set_push_constant(list, display_push, display_push.size())
	_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
	_rd.compute_list_end()


func _rd_free() -> void:
	if _rd == null:
		return
	# The sets go first: freeing what they use would free them too.
	for rid: RID in _sets:
		if rid.is_valid() and _rd.uniform_set_is_valid(rid):
			_rd.free_rid(rid)
	for rid: RID in [_pipeline, _shader, _params, _display, _bed] + _state:
		if rid.is_valid():
			_rd.free_rid(rid)
	_sets = [RID(), RID()]
	_state = [RID(), RID()]
	_rd_ready = false


func _exit_tree() -> void:
	if _display_texture != null:
		_display_texture.texture_rd_rid = RID()
	if _uses_gpu:
		RenderingServer.call_on_render_thread(_rd_free)


# ------------------------------------------------------------------ prewarm and tests

## For the loader's pipeline warm-up: the water and the spray shown once (stage 1 the surface, stage 2
## the particles). prewarm(false) puts everything away and leaves the hall dry.
func prewarm(on: bool, at_z: float, stage: int = 3) -> void:
	if not _built:
		return
	if on:
		visible = true
		if stage & 1:
			_surface.visible = is_simulation_ready()
			_flat.visible = true
			_flat.position.y = SuddenDeathLayout.FLOOR_Y + _level
			_far.visible = true
			_far.position.y = SuddenDeathLayout.FLOOR_Y + _level
		if stage & 2:
			_jet.emitting = true
			_mist.emitting = true
			set_drips(true, Vector3(0.0, 0.0, at_z))
			burst(Vector3(0.0, SuddenDeathLayout.FLOOR_Y + 1.0, at_z + 2.0))
	else:
		for particles: GPUParticles3D in _bursts:
			particles.emitting = false
			particles.restart()
			particles.emitting = false
		reset()


## Tests: asks the render thread for a copy of the water state; read it a frame later with
## debug_depth_at(). Returns false without a simulation.
func debug_request_readback() -> bool:
	if not is_simulation_ready():
		return false
	RenderingServer.call_on_render_thread(_rd_readback.bind(Engine.get_process_frames()))
	return true


func _rd_readback(frame: int) -> void:
	if not _rd_ready:
		return
	_readback = _rd.texture_get_data(_state[_current], 0)
	_readback_frame = frame


func debug_has_readback() -> bool:
	return not _readback.is_empty()


## Water depth (m) at [param world_xz] from the last readback (-1 without one).
func debug_depth_at(world_xz: Vector2) -> float:
	if _readback.is_empty():
		return -1.0
	return debug_sample(world_xz).x


## (depth, u, w, foam) of the cell under [param world_xz] from the last readback (-1 depth without one).
func debug_sample(world_xz: Vector2) -> Vector4:
	if _readback.is_empty():
		return Vector4(-1.0, 0.0, 0.0, 0.0)
	var c := cell_of(world_xz)
	if c.x < 0 or c.y < 0 or c.x >= GRID.x or c.y >= GRID.y:
		return Vector4(-1.0, 0.0, 0.0, 0.0)
	var offset := ((c.y * (GRID.x + 1)) + c.x) * 16
	return Vector4(_readback.decode_float(offset), _readback.decode_float(offset + 4),
		_readback.decode_float(offset + 8), _readback.decode_float(offset + 12))


## Totals over the last readback: wet area (m²), water volume (m³), mean depth of the wet cells (m),
## fastest flow (m/s) and the foamed area (m²).
func debug_totals() -> Dictionary:
	if _readback.is_empty():
		return {}
	var wet := 0
	var volume := 0.0
	var fastest := 0.0
	var foamed := 0
	for j in range(GRID.y):
		for i in range(GRID.x):
			var offset := ((j * (GRID.x + 1)) + i) * 16
			var h := _readback.decode_float(offset)
			if h > 0.01:
				wet += 1
				volume += h
				fastest = maxf(fastest, Vector2(_readback.decode_float(offset + 4), _readback.decode_float(offset + 8)).length())
				if _readback.decode_float(offset + 12) > 0.3:
					foamed += 1
	var area := CELL * CELL
	return {"wet_m2": snappedf(float(wet) * area, 0.1), "volume_m3": snappedf(volume * area, 0.1),
		"mean_depth": snappedf(volume / maxf(float(wet), 1.0), 0.001), "fastest": snappedf(fastest, 0.01),
		"foam_m2": snappedf(float(foamed) * area, 0.1)}


func get_debug_snapshot() -> Dictionary:
	return {"built": _built, "gpu": _uses_gpu, "ready": _rd_ready, "flooding": _flood_on,
		"flood_time": snappedf(_flood_time, 0.01), "level": _level, "frames": _frames, "steps": _steps,
		"towers": [_towers[0], _towers[1]], "splashes_queued": _splashes.size(), "bursts": _bursts_fired,
		"surface": _surface != null and _surface.visible, "flat": _flat != null and _flat.visible,
		"far": _far != null and _far.visible}
