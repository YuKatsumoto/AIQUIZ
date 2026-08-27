class_name WeatherCycle
extends Node

signal night_amount_changed(value: float)

## Shared, sunny day/night presentation for every stage viewport.
## The phase is derived from engine uptime so scene changes never reset the sky.
const DAY_CYCLE_SECONDS: float = 900.0
const START_DAY_PHASE: float = 0.12
const DEBUG_TIME_SCALE: float = 60.0
## Fallback used if the editable orbit control scene is invalid.
const SUNRISE_DIR := Vector3(-0.82, 0.0, -0.57)
## Open this scene and rotate SunOrbitControl directly in the 3D editor.
const SUN_ORBIT_EDITOR_SCENE: PackedScene = preload(
	"res://assets/environment/sky/day_night_sun_path.tscn"
)

const DAY_LIGHT_COLOR := Color(1.0, 0.96, 0.86)
const TWILIGHT_LIGHT_COLOR := Color(1.0, 0.61, 0.39)
const NIGHT_LIGHT_COLOR := Color(0.38, 0.50, 0.82)
const DAY_AMBIENT_COLOR := Color(0.66, 0.74, 0.92)
const TWILIGHT_AMBIENT_COLOR := Color(0.58, 0.55, 0.70)
const NIGHT_AMBIENT_COLOR := Color(0.34, 0.46, 0.72)

var environment: Environment = null
var directional_light: DirectionalLight3D = null
var moon_light: DirectionalLight3D = null
var sky_material: ShaderMaterial = null
## Rotation basis authored with SunOrbitControl in the 3D editor.
var sun_orbit_basis: Basis = Basis.IDENTITY
var day_phase: float = START_DAY_PHASE
var night_amount: float = 0.0

var _forced: bool = false

static var _shared_clock_initialized: bool = false
static var _shared_clock_anchor_ticks_msec: int = 0
static var _shared_clock_anchor_phase: float = START_DAY_PHASE
static var _shared_time_scale: float = 1.0
static var _debug_shortcut_down: bool = false
static var _shared_orbit_basis: Basis = Basis.IDENTITY
static var _shared_orbit_basis_ready: bool = false


static func shared_day_phase() -> float:
	_ensure_shared_clock()
	var elapsed_seconds: float = (
		float(Time.get_ticks_msec() - _shared_clock_anchor_ticks_msec) / 1000.0
	)
	return fposmod(
		_shared_clock_anchor_phase
		+ elapsed_seconds * _shared_time_scale / DAY_CYCLE_SECONDS,
		1.0
	)


## 空が明るい日中か。メニューなど、昼空に溶けるUIの視認性切替に使う。
static func is_bright_sky() -> bool:
	return shared_day_amount() >= 0.42


static func shared_day_amount() -> float:
	return smoothstep(-0.16, 0.28, _shared_sun_elevation())


static func _shared_sun_elevation() -> float:
	var basis: Basis = _shared_sun_orbit_basis()
	var angle: float = shared_day_phase() * TAU
	return (basis.z * cos(angle) + basis.y * sin(angle)).normalized().y


static func _ensure_shared_clock() -> void:
	if _shared_clock_initialized:
		return
	_shared_clock_anchor_ticks_msec = Time.get_ticks_msec()
	_shared_clock_anchor_phase = fposmod(
		START_DAY_PHASE
		+ float(_shared_clock_anchor_ticks_msec) / 1000.0 / DAY_CYCLE_SECONDS,
		1.0
	)
	_shared_clock_initialized = true


static func _set_shared_time_scale(value: float) -> void:
	var current_phase: float = shared_day_phase()
	_shared_clock_anchor_phase = current_phase
	_shared_clock_anchor_ticks_msec = Time.get_ticks_msec()
	_shared_time_scale = value


static func get_debug_time_scale() -> float:
	return _shared_time_scale


func setup(p_environment: Environment, p_light: DirectionalLight3D) -> void:
	environment = p_environment
	directional_light = p_light
	sun_orbit_basis = _load_sun_orbit_basis()
	sky_material = null
	if environment != null and environment.sky != null:
		sky_material = environment.sky.sky_material as ShaderMaterial
	_setup_moon_light()
	day_phase = shared_day_phase()
	_apply(day_phase)


func force_state(_weather_id: String, p_day_phase: float) -> void:
	force_day_phase(p_day_phase)


func force_day_phase(p_day_phase: float) -> void:
	_forced = true
	day_phase = fposmod(p_day_phase, 1.0)
	_apply(day_phase)


func clear_force() -> void:
	_forced = false
	day_phase = shared_day_phase()
	_apply(day_phase)


func _process(_delta: float) -> void:
	_poll_debug_time_shortcut()
	if environment == null or directional_light == null:
		return
	if not _forced:
		day_phase = shared_day_phase()
	_apply(day_phase)


func _poll_debug_time_shortcut() -> void:
	if not OS.is_debug_build():
		return
	var shortcut_down: bool = (
		(
			Input.is_key_pressed(KEY_CTRL)
			and Input.is_key_pressed(KEY_K)
		)
		or (
			Input.is_physical_key_pressed(KEY_CTRL)
			and Input.is_physical_key_pressed(KEY_K)
		)
	)
	if shortcut_down and not _debug_shortcut_down:
		_debug_shortcut_down = true
		var accelerated: bool = is_equal_approx(_shared_time_scale, 1.0)
		_set_shared_time_scale(DEBUG_TIME_SCALE if accelerated else 1.0)
		print(
			"[WeatherCycle] Ctrl+K debug time: %s (x%.0f)"
			% ["accelerated" if accelerated else "normal", _shared_time_scale]
		)
	elif not shortcut_down:
		_debug_shortcut_down = false


func _apply(p_day_phase: float) -> void:
	var sun_dir: Vector3 = _sun_direction(p_day_phase)
	var elevation: float = sun_dir.y
	var day_amount: float = smoothstep(-0.16, 0.28, elevation)
	var twilight_amount: float = exp(-pow(absf(elevation) / 0.23, 2.0))
	night_amount = smoothstep(0.04, 0.62, -elevation)

	if directional_light != null:
		_aim_light(directional_light, sun_dir)
		var base_light_color: Color = NIGHT_LIGHT_COLOR.lerp(DAY_LIGHT_COLOR, day_amount)
		directional_light.light_color = base_light_color.lerp(
			TWILIGHT_LIGHT_COLOR,
			clampf(twilight_amount * 0.72, 0.0, 1.0)
		)
		var light_energy: float = lerpf(0.0, 1.05, day_amount)
		directional_light.light_energy = maxf(light_energy, twilight_amount * 0.60)

	if moon_light != null:
		_aim_light(moon_light, -sun_dir)
		moon_light.light_energy = night_amount * 0.46

	if environment != null:
		environment.fog_enabled = false
		environment.volumetric_fog_enabled = false
		# Keep stage visibility independent from the deliberately dark night sky.
		# Reflections still come from the sky, while this soft arcade fill prevents
		# the floor, stands, and characters from crushing to black.
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.ambient_light_sky_contribution = 0.0
		var base_ambient_color: Color = NIGHT_AMBIENT_COLOR.lerp(DAY_AMBIENT_COLOR, day_amount)
		environment.ambient_light_color = base_ambient_color.lerp(
			TWILIGHT_AMBIENT_COLOR,
			clampf(twilight_amount * 0.38, 0.0, 1.0)
		)
		var ambient_energy: float = lerpf(0.88, 1.02, day_amount)
		environment.ambient_light_energy = maxf(ambient_energy, twilight_amount * 0.92)
		var background_energy: float = lerpf(0.74, 0.98, day_amount)
		environment.background_energy_multiplier = maxf(background_energy, twilight_amount * 0.86)

	if sky_material != null:
		sky_material.set_shader_parameter("cycle_sun_direction", sun_dir)

	night_amount_changed.emit(night_amount)


static func _default_sun_orbit_basis() -> Basis:
	var z_axis: Vector3 = SUNRISE_DIR.normalized()
	var y_axis: Vector3 = Vector3.UP
	var x_axis: Vector3 = y_axis.cross(z_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


static func _shared_sun_orbit_basis() -> Basis:
	if _shared_orbit_basis_ready:
		return _shared_orbit_basis
	var orbit_root: Node = SUN_ORBIT_EDITOR_SCENE.instantiate()
	var sun_control := orbit_root.get_node_or_null(^"SunOrbitControl") as DirectionalLight3D
	if sun_control == null:
		push_warning(
			"[WeatherCycle] SunOrbitControl is missing; using the built-in orbit."
		)
		orbit_root.free()
		_shared_orbit_basis = _default_sun_orbit_basis()
	else:
		_shared_orbit_basis = sun_control.basis.orthonormalized()
		orbit_root.free()
	_shared_orbit_basis_ready = true
	return _shared_orbit_basis


func _load_sun_orbit_basis() -> Basis:
	return _shared_sun_orbit_basis()


func _sun_direction(p_day_phase: float) -> Vector3:
	var angle: float = p_day_phase * TAU
	return (
		sun_orbit_basis.z * cos(angle)
		+ sun_orbit_basis.y * sin(angle)
	).normalized()


func _setup_moon_light() -> void:
	if directional_light == null or directional_light.get_parent() == null:
		return
	moon_light = DirectionalLight3D.new()
	moon_light.name = "MoonDirectionalLight3D"
	moon_light.light_color = Color(0.42, 0.56, 0.90)
	moon_light.light_energy = 0.0
	moon_light.shadow_enabled = false
	moon_light.light_volumetric_fog_energy = 0.0
	directional_light.get_parent().add_child(moon_light)


func _aim_light(light: DirectionalLight3D, light_dir: Vector3) -> void:
	var z_axis: Vector3 = light_dir
	var up_ref: Vector3 = Vector3.UP
	if absf(z_axis.dot(up_ref)) > 0.94:
		up_ref = sun_orbit_basis.z
	var x_axis: Vector3 = up_ref.cross(z_axis)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.FORWARD.cross(z_axis)
	x_axis = x_axis.normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	light.basis = Basis(x_axis, y_axis, z_axis)
