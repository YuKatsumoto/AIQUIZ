extends MeshInstance3D

## Short world-space ribbons left by a fin intersecting the surface.
## No bubbles emitted underwater and no bridge across teleport/portal travel.
const WAKE_SHADER := preload("res://shaders/shark_surface_wake.gdshader")
const LIFETIME := 2.1
const STEP := 0.075
const MAX_POINTS := 30
var surface: MeshInstance3D
var _samples: Array[Dictionary] = []
var _clock := 0.0
var _next_sample := 0.0
var _mesh := ImmediateMesh.new()
var _material := ShaderMaterial.new()
var _emitting := false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_material.shader = WAKE_SHADER
	_material.render_priority = 2
	material_override = _material
	mesh = _mesh


func update_trail(delta: float, anchor: Vector3, forward: Vector3, speed: float,
		strength: float, enabled: bool) -> void:
	_clock += delta
	_emitting = enabled and strength > 0.01 and speed > 0.25 and is_instance_valid(surface)
	while not _samples.is_empty() and _clock - float(_samples[0].time) > LIFETIME:
		_samples.pop_front()
	if is_instance_valid(surface):
		_material.set_shader_parameter("sea_level", surface.global_position.y)
		_material.set_shader_parameter("surface_origin", Vector2(surface.global_position.x, surface.global_position.z))
		var water := surface.material_override as ShaderMaterial
		if water != null:
			for parameter in ["wave_speed", "wave_height", "noise_tex", "noise_tex2"]:
				_material.set_shader_parameter(parameter, water.get_shader_parameter(parameter))
	if _emitting and _clock >= _next_sample:
		_next_sample = _clock + STEP
		if not _samples.is_empty() and anchor.distance_to(_samples[-1].position) > maxf(5.0, speed * STEP * 3.0):
			_samples.clear()
		forward.y = 0.0
		forward = forward.normalized()
		_samples.append({"position": anchor, "side": forward.cross(Vector3.UP),
			"time": _clock, "strength": strength, "speed": speed})
		if _samples.size() > MAX_POINTS:
			_samples.pop_front()
	_rebuild()


func clear_trail() -> void:
	_samples.clear()
	_mesh.clear_surfaces()
	_emitting = false


func debug_state() -> Dictionary:
	return {"emitting": _emitting, "samples": _samples.size(), "surfaces": _mesh.get_surface_count()}


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	var bounds := AABB(_samples[0].position, Vector3.ZERO)
	for point: Dictionary in _samples:
		bounds = bounds.expand(point.position)
	# Vertex displacement puts ribbons above the body-space emission points.
	bounds.position.y = float(_material.get_shader_parameter("sea_level")) - 0.2
	bounds.size.y = 0.4
	custom_aabb = bounds.grow(2.5)
	for wing: float in [-1.0, 1.0]:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for point: Dictionary in _samples:
			var age := _clock - float(point.time)
			var fade := smoothstep(0.0, 0.16, age) * pow(maxf(0.0, 1.0 - age / LIFETIME), 1.7)
			var spread := 0.45 + age * minf(float(point.speed) * 0.14, 1.0)
			var width := 0.14 + age * 0.13
			var center: Vector3 = point.position + point.side * spread * wing
			for edge: float in [-1.0, 1.0]:
				_mesh.surface_set_normal(Vector3.UP)
				_mesh.surface_set_color(Color(1, 1, 1, fade * float(point.strength) * 0.72))
				_mesh.surface_set_uv(Vector2((edge + 1.0) * 0.5, float(point.time) * 2.0))
				_mesh.surface_add_vertex(center + point.side * width * edge)
		_mesh.surface_end()
