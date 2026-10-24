class_name GoalStandEggFluid
extends Node3D

## Raw egg as a GPU particle fluid on top of GoalStandEggContents (HIGH/ULTRA on
## desktop, with a RenderingDevice): when an egg breaks on a body, a share of its
## thin white is handed over as particles. Three in five fly off with the sheet as
## splash; the rest stay in it as runoff that crawls over the body, drips off its
## edges and pools on the lift deck. The simulation is position based fluids with a
## tensile correction (the liquid beads and clings), XSPH viscosity per phase and
## contact with the body's proxies that holds on gentle slopes and lets go on steep
## ones (shaders/goal_stand_egg_fluid.glsl). The particles are splatted into a 3D
## density field around the target and raymarched as a smooth surface
## (shaders/goal_stand_egg_fluid_surface.gdshader).
##
## Particles live in a ring buffer: the oldest are overwritten first (they also fade
## out after their life), so endless throwing never grows it. Headless, on the
## Compatibility or mobile renderer, or below HIGH, is_supported() is false and the
## contents keep their own spray instead. Same render-thread pattern as CisternFlow.

const COMPUTE_PATH := "res://shaders/goal_stand_egg_fluid.glsl"
const SURFACE_SHADER := preload("res://shaders/goal_stand_egg_fluid_surface.gdshader")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")

const SIM_DT := 1.0 / 120.0
const MAX_SUBSTEPS := 2
const TABLE_SIZE := 32768
const MAX_SHAPES := 16
const MAX_SPAWNS := 4
const PARAM_VEC4S := 10 + MAX_SPAWNS * 4 + MAX_SHAPES * 4 + MAX_SHAPES
const COARSE_BLOCK := 8
## Share of an egg's thin white handed to the fluid on a body hit.
const SHARE := 0.35
## Per quality: particle capacity, spacing (m) and voxel size (m) of the field.
const DETAIL := {
	QualityRules.HIGH: {"capacity": 4096, "spacing": 0.018, "voxel": 0.016},
	QualityRules.ULTRA: {"capacity": 8192, "spacing": 0.015, "voxel": 0.013},
}
## The field around the target (m): wide, tall (from just under the deck), deep.
const FIELD_SIZE := Vector3(1.8, 2.4, 1.8)
const FIELD_BELOW := 0.2
## Phases' XSPH viscosity and how hard they hold on a slope (m/s^2), life (s).
const VISCOSITY := Vector4(0.08, 0.35, 0.25, 4.0)
const STICK := Vector3(4.5, 8.5, 6.0)
const LIFE := 12.0
const S_CORR := 0.12
const RELAXATION := 600.0
const GRAVITY := -9.8

var quality := QualityRules.HIGH
var capacity := 4096
var spacing := 0.018
var voxel := 0.016
var dims := Vector3i.ONE
var emitted := 0
var frames := 0
var steps := 0
var body: GoalStandEggBody
var support := {}

var _uses_gpu := false
var _spirv: RDShaderSPIRV
var _rd: RenderingDevice
var _rd_ready := false
var _shader := RID()
var _pipeline := RID()
var _set := RID()
var _buffers: Array[RID] = []
var _images: Array[RID] = []
var _params := RID()
var _field_texture: Texture3DRD
var _coarse_texture: Texture3DRD
var _surface: MeshInstance3D
var _surface_material: ShaderMaterial
var _head := 0
var _spawns: Array[PackedFloat32Array] = []
var _rest_density := 1.0
var _h := 0.04
var _origin := Vector3.ZERO
var _accumulator := 0.0
var _clock := 0.0
var _shape_centres := PackedVector3Array()
var _deck_point := Vector3.ZERO
var _readback := PackedByteArray()


## Whether this quality and machine run the fluid at all (no node needed).
static func wanted(level: String, mobile: bool) -> bool:
	return DETAIL.has(level) and not mobile and RenderingServer.get_rendering_device() != null \
		and ResourceLoader.exists(COMPUTE_PATH)


func setup(level: String) -> void:
	name = "EggFluid"
	top_level = true
	quality = level
	var spec: Dictionary = DETAIL.get(level, DETAIL[QualityRules.HIGH])
	capacity = int(spec.capacity)
	spacing = float(spec.spacing)
	voxel = float(spec.voxel)
	_h = spacing * 2.2
	_rest_density = rest_density(spacing, _h)
	dims = Vector3i((FIELD_SIZE / voxel).ceil())
	_uses_gpu = RenderingServer.get_rendering_device() != null and ResourceLoader.exists(COMPUTE_PATH)
	if _uses_gpu:
		var file := load(COMPUTE_PATH) as RDShaderFile
		_spirv = file.get_spirv() if file != null else null
		if _spirv == null or not _spirv.compile_error_compute.is_empty():
			push_warning("[GoalStandEggFluid] compute shader unavailable: %s" % (_spirv.compile_error_compute if _spirv != null else "missing"))
			_uses_gpu = false
	if not _uses_gpu:
		return
	_build_surface()
	RenderingServer.call_on_render_thread(_rd_init.bind(_spirv))


## Rest density of particles on a cubic lattice of `step` with smoothing radius `h`
## (poly6, the particle itself included): what the solver pushes toward.
static func rest_density(step: float, h: float) -> float:
	var reach := int(ceil(h / step))
	var total := 0.0
	var coefficient := 315.0 / (64.0 * PI * pow(h, 9.0))
	for z in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				var r2 := Vector3(x, y, z).length_squared() * step * step
				if r2 < h * h:
					total += coefficient * pow(h * h - r2, 3.0)
	return total


func is_supported() -> bool:
	return _uses_gpu


func is_simulation_ready() -> bool:
	return _uses_gpu and _rd_ready


## Particles for an egg that broke at `frame` (origin on the surface, +Y the normal,
## +X a surface axis): `reach` the sheet's reach (m), `normal_speed` (m/s),
## `tangential` the glancing velocity in the plane, `volume` (m^3) of thin white.
## Returns the volume actually handed over.
func emit(frame: Transform3D, reach: float, normal_speed: float, tangential: Vector2, volume: float, phase: int = 0) -> float:
	if not is_simulation_ready() or _spawns.size() >= MAX_SPAWNS:
		return 0.0
	var amount := clampi(int(volume / pow(spacing, 3.0)), 8, capacity / 6)
	var n := frame.basis.y.normalized()
	var axis := frame.basis.x.normalized()
	var record := PackedFloat32Array([
		frame.origin.x, frame.origin.y, frame.origin.z, reach,
		n.x, n.y, n.z, normal_speed,
		axis.x, axis.y, axis.z, float(phase),
		tangential.x, tangential.y, float(_head), float(amount),
	])
	_spawns.append(record)
	_head = (_head + amount) % capacity
	emitted += amount
	return float(amount) * pow(spacing, 3.0)


func update(delta: float) -> void:
	if not is_simulation_ready():
		return
	_clock += delta
	_place_field()
	_accumulator = minf(_accumulator + delta, SIM_DT * float(MAX_SUBSTEPS))
	var substeps := int(floor(_accumulator / SIM_DT + 0.0001))
	_accumulator -= float(substeps) * SIM_DT
	var shapes := body.pack_for_gpu(MAX_SHAPES) if body != null and not body.is_empty() else PackedFloat32Array()
	var shape_count := shapes.size() / 16
	var shape_velocity := PackedFloat32Array()
	shape_velocity.resize(MAX_SHAPES * 4)
	var centres := PackedVector3Array()
	for index in range(shape_count):
		var centre := Vector3(shapes[index * 16], shapes[index * 16 + 1], shapes[index * 16 + 2])
		centres.append(centre)
		if index < _shape_centres.size() and delta > 0.0:
			var v := (centre - _shape_centres[index]) / delta
			shape_velocity[index * 4] = v.x
			shape_velocity[index * 4 + 1] = v.y
			shape_velocity[index * 4 + 2] = v.z
	_shape_centres = centres
	shapes.resize(MAX_SHAPES * 16)
	var deck_on := 0.0
	var deck := Vector4.ZERO
	var deck_velocity := Vector3.ZERO
	var holder := support.get("node") as Node3D if support.has("node") and is_instance_valid(support.get("node")) else null
	if holder != null and holder.is_inside_tree():
		var top := holder.global_transform * Vector3(0.0, float(support.get("top", 0.0)), 0.0)
		deck_velocity = (top - _deck_point) / maxf(delta, 0.0001) if _deck_point != Vector3.ZERO else Vector3.ZERO
		_deck_point = top
		deck = Vector4(top.x, top.y, top.z, float(support.get("radius", 0.0)))
		deck_on = 1.0
	var spawn := PackedFloat32Array()
	spawn.resize(MAX_SPAWNS * 16)
	for index in range(_spawns.size()):
		for k in range(16):
			spawn[index * 16 + k] = _spawns[index][k]
	var params := PackedFloat32Array([
		float(capacity), SIM_DT, _h, _rest_density,
		GRAVITY, S_CORR, RELAXATION, spacing,
		_origin.x, _origin.y, _origin.z, voxel,
		float(dims.x), float(dims.y), float(dims.z), float(COARSE_BLOCK),
		float(TABLE_SIZE), float(shape_count), deck_on, StageConstants.FLOOR_TOP_Y,
		deck.x, deck.y, deck.z, deck.w,
		deck_velocity.x, deck_velocity.y, deck_velocity.z, spacing * 1.6,
		VISCOSITY.x, VISCOSITY.y, VISCOSITY.z, VISCOSITY.w,
		STICK.x, STICK.y, STICK.z, LIFE,
		float(_spawns.size()) if substeps > 0 else 0.0, 0.0, 0.0, fmod(_clock, 1000.0),
	])
	params.append_array(spawn)
	params.append_array(shapes)
	params.append_array(shape_velocity)
	if substeps > 0:
		_spawns.clear()
	frames += 1
	steps += substeps
	_surface_material.set_shader_parameter("grid_origin", _origin)
	RenderingServer.call_on_render_thread(_rd_step.bind(params.to_byte_array(), substeps))


## The field follows the deck (or, on a draw, the body), from just under the deck up.
func _place_field() -> void:
	var centre := Vector3.ZERO
	var floor_y := StageConstants.FLOOR_TOP_Y
	var holder := support.get("node") as Node3D if support.has("node") and is_instance_valid(support.get("node")) else null
	if holder != null and holder.is_inside_tree():
		centre = holder.global_transform * Vector3(0.0, float(support.get("top", 0.0)), 0.0)
		floor_y = centre.y
	elif body != null and not body.is_empty():
		var count := 0
		for index in range(body.shapes.size()):
			if body.shape_transform(index) != null:
				centre += body.shape_centre(index)
				count += 1
		centre /= maxf(float(count), 1.0)
	_origin = Vector3(centre.x - FIELD_SIZE.x * 0.5, floor_y - FIELD_BELOW, centre.z - FIELD_SIZE.z * 0.5)
	_surface.global_position = _origin + FIELD_SIZE * 0.5


func _build_surface() -> void:
	_field_texture = Texture3DRD.new()
	_coarse_texture = Texture3DRD.new()
	_surface_material = ShaderMaterial.new()
	_surface_material.shader = SURFACE_SHADER
	_surface_material.render_priority = 3
	_surface_material.set_shader_parameter("field_tex", _field_texture)
	_surface_material.set_shader_parameter("coarse_tex", _coarse_texture)
	_surface_material.set_shader_parameter("grid_size", FIELD_SIZE)
	_surface_material.set_shader_parameter("voxel", voxel)
	_surface_material.set_shader_parameter("block", float(COARSE_BLOCK))
	var box := BoxMesh.new()
	box.size = FIELD_SIZE
	_surface = MeshInstance3D.new()
	_surface.name = "FluidSurface"
	_surface.mesh = box
	_surface.material_override = _surface_material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_surface.top_level = true
	add_child(_surface)


func clear() -> void:
	_spawns.clear()
	_head = 0
	if is_simulation_ready():
		RenderingServer.call_on_render_thread(_rd_clear)


# ------------------------------------------------------------------ render thread

func _rd_init(spirv: RDShaderSPIRV) -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null or spirv == null:
		return
	_shader = _rd.shader_create_from_spirv(spirv, "GoalStandEggFluid")
	if not _shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	# pos, vel, pred_a, pred_b, lambda, heads, next, vel_out
	var sizes := [capacity * 16, capacity * 16, capacity * 16, capacity * 16, capacity * 4, TABLE_SIZE * 4, capacity * 4, capacity * 16]
	_buffers.clear()
	for index in range(sizes.size()):
		var bytes := PackedByteArray()
		bytes.resize(int(sizes[index]))
		bytes.fill(0)
		if index == 0:
			# Every particle starts dead (phase -1).
			var dead := PackedFloat32Array()
			dead.resize(capacity * 4)
			for i in range(capacity):
				dead[i * 4 + 3] = -1.0
			bytes = dead.to_byte_array()
		_buffers.append(_rd.storage_buffer_create(bytes.size(), bytes))
	var block := Vector3i((Vector3(dims) / float(COARSE_BLOCK)).ceil())
	_images = [
		_image3d(dims, RenderingDevice.DATA_FORMAT_R32_UINT, false),
		_image3d(dims, RenderingDevice.DATA_FORMAT_R32_UINT, false),
		_image3d(dims, RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, true),
		_image3d(block, RenderingDevice.DATA_FORMAT_R16_SFLOAT, true),
	]
	var zeros := PackedByteArray()
	zeros.resize(PARAM_VEC4S * 16)
	_params = _rd.uniform_buffer_create(zeros.size(), zeros)
	var uniforms: Array[RDUniform] = []
	for index in range(_buffers.size()):
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = index
		uniform.add_id(_buffers[index])
		uniforms.append(uniform)
	for index in range(_images.size()):
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = 8 + index
		uniform.add_id(_images[index])
		uniforms.append(uniform)
	var params := RDUniform.new()
	params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	params.binding = 12
	params.add_id(_params)
	uniforms.append(params)
	_set = _rd.uniform_set_create(uniforms, _shader, 0)
	_rd_ready = _set.is_valid()


func _image3d(size: Vector3i, data_format: RenderingDevice.DataFormat, sampled: bool) -> RID:
	var image_format := RDTextureFormat.new()
	image_format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	image_format.format = data_format
	image_format.width = size.x
	image_format.height = size.y
	image_format.depth = size.z
	image_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	if sampled:
		image_format.usage_bits |= RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var rid := _rd.texture_create(image_format, RDTextureView.new(), [])
	_rd.texture_clear(rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
	return rid


func _rd_step(params: PackedByteArray, substeps: int) -> void:
	if not _rd_ready:
		return
	_rd.buffer_update(_params, 0, params.size(), params)
	var particle_groups := ceili(float(capacity) / 64.0)
	var voxels := dims.x * dims.y * dims.z
	var block := Vector3i((Vector3(dims) / float(COARSE_BLOCK)).ceil())
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, _set, 0)
	for step in range(substeps):
		_pass(list, 0, ceili(float(TABLE_SIZE) / 64.0))
		_pass(list, 1, particle_groups, 0, 1 if step == 0 else 0)
		for iteration in range(2):
			_pass(list, 2, particle_groups, iteration)
			_pass(list, 3, particle_groups, iteration)
		_pass(list, 4, particle_groups)
		_pass(list, 5, particle_groups)
	_pass(list, 6, particle_groups)
	_pass(list, 7, ceili(float(voxels) / 64.0))
	_pass(list, 8, ceili(float(block.x * block.y * block.z) / 64.0))
	_rd.compute_list_end()


func _pass(list: int, pass_id: int, groups: int, source: int = 0, first: int = 0) -> void:
	var push := PackedInt32Array([pass_id, source, first, 0]).to_byte_array()
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, groups, 1, 1)
	_rd.compute_list_add_barrier(list)


func _rd_clear() -> void:
	if not _rd_ready:
		return
	var dead := PackedFloat32Array()
	dead.resize(capacity * 4)
	for i in range(capacity):
		dead[i * 4 + 3] = -1.0
	var bytes := dead.to_byte_array()
	_rd.buffer_update(_buffers[0], 0, bytes.size(), bytes)
	for image: RID in _images:
		_rd.texture_clear(image, Color(0, 0, 0, 0), 0, 1, 0, 1)


func _rd_free() -> void:
	if _rd == null:
		return
	# The set goes first: freeing what it uses would free it too.
	if _set.is_valid() and _rd.uniform_set_is_valid(_set):
		_rd.free_rid(_set)
	for rid: RID in [_pipeline, _shader, _params] + _buffers + _images:
		if rid.is_valid():
			_rd.free_rid(rid)
	_buffers.clear()
	_images.clear()
	_set = RID()
	_rd_ready = false


func _process(_delta: float) -> void:
	# The textures exist once the render thread has made them.
	if _rd_ready and _field_texture != null and _field_texture.texture_rd_rid != _images[2]:
		_field_texture.texture_rd_rid = _images[2]
		_coarse_texture.texture_rd_rid = _images[3]


func _exit_tree() -> void:
	if _field_texture != null:
		_field_texture.texture_rd_rid = RID()
		_coarse_texture.texture_rd_rid = RID()
	if _uses_gpu:
		RenderingServer.call_on_render_thread(_rd_free)


# ------------------------------------------------------------------ tests

func debug_request_readback() -> bool:
	if not is_simulation_ready():
		return false
	RenderingServer.call_on_render_thread(_rd_readback)
	return true


func _rd_readback() -> void:
	if _rd_ready:
		_readback = _rd.buffer_get_data(_buffers[0])


func debug_has_readback() -> bool:
	return not _readback.is_empty()


## Over the last readback: live particles, NaNs, the lowest and highest, and how
## many sit inside a body proxy deeper than half a spacing.
func debug_totals() -> Dictionary:
	if _readback.is_empty():
		return {}
	var live := 0
	var nans := 0
	var low := INF
	var high := -INF
	var inside := 0
	var data := _readback.to_float32_array()
	for i in range(capacity):
		if data[i * 4 + 3] < -0.5:
			continue
		var p := Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
			nans += 1
			continue
		live += 1
		low = minf(low, p.y)
		high = maxf(high, p.y)
		if body != null:
			for index in range(body.shapes.size()):
				var shape: Dictionary = body.shapes[index]
				var xform: Variant = body.shape_transform(index)
				if xform == null or int(shape.kind) != GoalStandEggBody.Shape.BOX:
					continue
				var local := (xform as Transform3D).affine_inverse() * p
				if (shape.aabb as AABB).grow(-spacing * 0.5).has_point(local):
					inside += 1
					break
	return {"live": live, "nans": nans, "lowest": low, "highest": high, "inside": inside}


func get_debug_snapshot() -> Dictionary:
	return {"gpu": _uses_gpu, "ready": _rd_ready, "capacity": capacity, "emitted": emitted, "frames": frames,
		"steps": steps, "dims": dims, "rest_density": _rest_density}
