class_name ConveyorEdgeLights
extends Node3D

## Performance-safe night marker lights shared by every conveyor presentation.
const MARKER_SHADER = preload("res://shaders/conveyor_edge_light_marker.gdshader")

const LIGHT_SPACING: float = 10.0
const END_MARGIN: float = 2.0
const MARKER_SIZE := Vector3(0.12, 0.06, 0.30)
const WARM_WHITE_COLOR := Color(1.0, 0.93, 0.78)
const MARKER_EMISSION_ENERGY: float = 3.2
const LOCAL_LIGHT_COUNT: int = 8
const LOCAL_LIGHT_STATIONS: int = 4

# The sun is about 11 degrees below the horizon at phase 0.53. Lights remain
# completely dark until this point, then the electrical start sequence begins.
const POWER_ON_PHASE: float = 0.53
const POWER_OFF_PHASE: float = 0.995
const STATION_SWITCH_DELAY: float = 0.22
const SIDE_SWITCH_DELAY: float = 0.055
const MAX_FIXTURE_STARTUP_TIME: float = 0.72

var _center_z: float = 0.0
var _length: float = 0.0
var _station_count: int = 0
var _first_station_z: float = 0.0
var _night_amount: float = 0.0
var _last_station_start: int = -1
var _powered: bool = false
var _sequence_elapsed: float = -1.0
var _front_is_last_station: bool = true

var _floor_material: ShaderMaterial = null
var _weather_cycle: WeatherCycle = null
var _marker_material: ShaderMaterial = null
var _marker_instances: MultiMeshInstance3D = null
var _local_lights: Array[OmniLight3D] = []
var _local_light_marker_indices: Array[int] = []


func setup(
		center_z: float,
		length: float,
		floor_material: ShaderMaterial,
		weather_cycle: WeatherCycle
	) -> void:
	_disconnect_weather_cycle()
	_floor_material = floor_material
	_weather_cycle = weather_cycle
	_ensure_marker_instances()
	_ensure_local_lights()
	set_geometry(center_z, length)
	if _weather_cycle != null:
		var callback := Callable(self, "set_night_amount")
		if not _weather_cycle.night_amount_changed.is_connected(callback):
			_weather_cycle.night_amount_changed.connect(callback)
		_night_amount = _weather_cycle.night_amount
		_sync_power_state(true)
	else:
		set_night_amount(0.0)


func set_geometry(center_z: float, length: float) -> void:
	_center_z = center_z
	_length = maxf(length, 0.0)
	_station_count = maxi(0, floori(maxf(_length - END_MARGIN * 2.0, 0.0) / LIGHT_SPACING) + 1)
	_first_station_z = _center_z - _length * 0.5 + END_MARGIN
	_last_station_start = -1
	_rebuild_marker_transforms()
	_sync_floor_shader()
	_update_local_light_positions(true)
	_refresh_lighting_visuals()


func set_night_amount(value: float) -> void:
	_night_amount = clampf(value, 0.0, 1.0)
	_sync_power_state(false)


func get_marker_count() -> int:
	return _station_count * 2


func get_active_local_light_count() -> int:
	var active_count: int = 0
	for local_light: OmniLight3D in _local_lights:
		if local_light.visible and local_light.light_energy > 0.0:
			active_count += 1
	return active_count


func get_lit_marker_count() -> int:
	var lit_count: int = 0
	for marker_index: int in range(_station_count * 2):
		if _fixture_level(marker_index) >= 0.98:
			lit_count += 1
	return lit_count


func get_flickering_marker_count() -> int:
	var flickering_count: int = 0
	for marker_index: int in range(_station_count * 2):
		var level: float = _fixture_level(marker_index)
		if level > 0.001 and level < 0.98:
			flickering_count += 1
	return flickering_count


func get_sequence_elapsed() -> float:
	return _sequence_elapsed


func _process(delta: float) -> void:
	if _powered and _sequence_elapsed < _sequence_duration():
		_sequence_elapsed = minf(_sequence_elapsed + delta, _sequence_duration())
		_refresh_lighting_visuals()
	if _powered:
		_update_local_light_positions(false)


func _exit_tree() -> void:
	_disconnect_weather_cycle()


func _disconnect_weather_cycle() -> void:
	if _weather_cycle == null:
		return
	var callback := Callable(self, "set_night_amount")
	if _weather_cycle.night_amount_changed.is_connected(callback):
		_weather_cycle.night_amount_changed.disconnect(callback)
	_weather_cycle = null


func _sync_power_state(initial_sync: bool) -> void:
	var should_power: bool = _should_be_powered()
	if should_power and not _powered:
		_powered = true
		_front_is_last_station = _camera_is_closer_to_last_station()
		_sequence_elapsed = _elapsed_since_power_on_phase()
		if not initial_sync and _sequence_elapsed > _sequence_duration():
			_sequence_elapsed = _sequence_duration()
		_refresh_lighting_visuals()
	elif not should_power and (_powered or initial_sync):
		_powered = false
		_sequence_elapsed = -1.0
		_refresh_lighting_visuals()


func _should_be_powered() -> bool:
	if _weather_cycle == null:
		return _night_amount >= 0.5
	var phase: float = _weather_cycle.day_phase
	return phase >= POWER_ON_PHASE and phase < POWER_OFF_PHASE


func _elapsed_since_power_on_phase() -> float:
	if _weather_cycle == null:
		return 0.0
	return maxf(
		(_weather_cycle.day_phase - POWER_ON_PHASE) * WeatherCycle.DAY_CYCLE_SECONDS,
		0.0
	)


func _sequence_duration() -> float:
	return maxf(float(_station_count - 1) * STATION_SWITCH_DELAY, 0.0) + MAX_FIXTURE_STARTUP_TIME


func _ensure_marker_instances() -> void:
	if _marker_instances != null:
		return
	_marker_material = ShaderMaterial.new()
	_marker_material.shader = MARKER_SHADER
	_marker_material.set_shader_parameter("light_color", WARM_WHITE_COLOR)
	_marker_material.set_shader_parameter("emission_energy", MARKER_EMISSION_ENERGY)

	var marker_mesh := BoxMesh.new()
	marker_mesh.size = MARKER_SIZE
	marker_mesh.material = _marker_material

	_marker_instances = MultiMeshInstance3D.new()
	_marker_instances.name = "WarmWhiteEdgeMarkers"
	_marker_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_instances.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_marker_instances)

	var marker_multimesh := MultiMesh.new()
	marker_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	marker_multimesh.use_custom_data = true
	marker_multimesh.mesh = marker_mesh
	_marker_instances.multimesh = marker_multimesh


func _ensure_local_lights() -> void:
	if not _local_lights.is_empty():
		return
	for index: int in range(LOCAL_LIGHT_COUNT):
		var local_light := OmniLight3D.new()
		local_light.name = "WarmWhitePoolLight%02d" % (index + 1)
		local_light.light_color = WARM_WHITE_COLOR
		local_light.light_energy = 0.0
		local_light.omni_range = 3.2
		local_light.omni_attenuation = 1.5
		local_light.light_specular = 0.2
		local_light.light_volumetric_fog_energy = 0.0
		local_light.light_bake_mode = Light3D.BAKE_DISABLED
		local_light.shadow_enabled = false
		local_light.distance_fade_enabled = true
		local_light.distance_fade_begin = 28.0
		local_light.distance_fade_length = 8.0
		local_light.visible = false
		add_child(local_light)
		_local_lights.append(local_light)
		_local_light_marker_indices.append(-1)


func _rebuild_marker_transforms() -> void:
	if _marker_instances == null or _marker_instances.multimesh == null:
		return
	var marker_multimesh: MultiMesh = _marker_instances.multimesh
	marker_multimesh.instance_count = _station_count * 2
	var rail_x: float = _rail_x()
	var marker_y: float = _marker_y()
	for station_index: int in range(_station_count):
		var station_z: float = _first_station_z + float(station_index) * LIGHT_SPACING
		marker_multimesh.set_instance_transform(
			station_index * 2,
			Transform3D(Basis.IDENTITY, Vector3(-rail_x, marker_y, station_z))
		)
		marker_multimesh.set_instance_transform(
			station_index * 2 + 1,
			Transform3D(Basis.IDENTITY, Vector3(rail_x, marker_y, station_z))
		)
	marker_multimesh.custom_aabb = AABB(
		Vector3(-rail_x - 0.1, marker_y - 0.05, _center_z - _length * 0.5),
		Vector3(rail_x * 2.0 + 0.2, 0.1, _length)
	)


func _sync_floor_shader() -> void:
	if _floor_material == null:
		return
	var local_phase: float = _first_station_z - _center_z
	_floor_material.set_shader_parameter("edge_light_color", WARM_WHITE_COLOR)
	_floor_material.set_shader_parameter("edge_light_spacing", LIGHT_SPACING)
	_floor_material.set_shader_parameter("edge_light_phase", local_phase)
	_floor_material.set_shader_parameter("edge_light_side_x", _rail_x())
	_floor_material.set_shader_parameter("edge_light_station_count", _station_count)
	_floor_material.set_shader_parameter("edge_light_station_delay", STATION_SWITCH_DELAY)
	_floor_material.set_shader_parameter("edge_light_side_delay", SIDE_SWITCH_DELAY)


func _refresh_lighting_visuals() -> void:
	_update_marker_levels()
	if _floor_material != null:
		_floor_material.set_shader_parameter("edge_light_sequence_time", _sequence_elapsed)
		_floor_material.set_shader_parameter(
			"edge_light_front_is_last",
			1.0 if _front_is_last_station else 0.0
		)
	_refresh_local_light_levels()


func _update_marker_levels() -> void:
	if _marker_instances == null or _marker_instances.multimesh == null:
		return
	var marker_multimesh: MultiMesh = _marker_instances.multimesh
	for marker_index: int in range(_station_count * 2):
		marker_multimesh.set_instance_custom_data(
			marker_index,
			Color(_fixture_level(marker_index), 0.0, 0.0, 1.0)
		)


func _fixture_level(marker_index: int) -> float:
	if not _powered or _sequence_elapsed < 0.0:
		return 0.0
	var station_index: int = floori(float(marker_index) / 2.0)
	var side_index: int = marker_index % 2
	var station_order: int = _station_count - 1 - station_index if _front_is_last_station else station_index
	var local_time: float = (
		_sequence_elapsed
		- float(station_order) * STATION_SWITCH_DELAY
		- float(side_index) * SIDE_SWITCH_DELAY
	)
	if local_time < 0.0:
		return 0.0

	# Roughly two out of thirteen fixtures use the aged fluorescent starter path.
	# The modular pattern is deterministic, so scene transitions cannot change
	# which physical fixture hesitates or the timing of its restrike cycle.
	var flicker_pattern: int = (marker_index * 37 + 17) % 13
	if flicker_pattern >= 2:
		return 1.0
	var variant: int = (marker_index * 13 + 5) % 4
	return _fluorescent_start_level(local_time, variant)


func _fluorescent_start_level(local_time: float, variant: int) -> float:
	var t: float = local_time
	var preheat_time: float = 0.065 + float(variant) * 0.014
	if t < preheat_time:
		return 0.025
	t -= preheat_time
	if t < 0.038:
		return 1.0
	t -= 0.038
	var first_extinction: float = 0.052 + float(variant) * 0.012
	if t < first_extinction:
		return 0.0
	t -= first_extinction
	if t < 0.028:
		return 0.62
	t -= 0.028
	if t < 0.045:
		return 0.0
	t -= 0.045
	var chatter_time: float = 0.155 + float(variant) * 0.032
	if t < chatter_time:
		var chatter_step: int = floori(t / 0.032)
		return 0.88 if chatter_step % 2 == 0 else 0.06
	t -= chatter_time
	if variant >= 2 and t < 0.050:
		return 0.0
	if variant >= 2:
		t -= 0.050
	if t < 0.060:
		return 0.72
	return 1.0


func _update_local_light_positions(force_update: bool) -> void:
	if _local_lights.is_empty():
		return
	if _station_count <= 0:
		for local_light: OmniLight3D in _local_lights:
			local_light.visible = false
		return
	var camera_z: float = _camera_local_z()
	var nearest_index: int = clampi(
		roundi((camera_z - _first_station_z) / LIGHT_SPACING),
		0,
		_station_count - 1
	)
	var max_start: int = maxi(_station_count - LOCAL_LIGHT_STATIONS, 0)
	var station_start: int = clampi(nearest_index - 1, 0, max_start)
	if not force_update and station_start == _last_station_start:
		return
	_last_station_start = station_start
	var rail_x: float = _rail_x()
	var marker_y: float = _marker_y()
	for station_offset: int in range(LOCAL_LIGHT_STATIONS):
		var station_index: int = station_start + station_offset
		for side_index: int in range(2):
			var light_index: int = station_offset * 2 + side_index
			var local_light: OmniLight3D = _local_lights[light_index]
			if station_index >= _station_count:
				_local_light_marker_indices[light_index] = -1
				local_light.visible = false
				continue
			var marker_index: int = station_index * 2 + side_index
			_local_light_marker_indices[light_index] = marker_index
			var side_sign: float = -1.0 if side_index == 0 else 1.0
			local_light.position = Vector3(
				rail_x * side_sign,
				marker_y,
				_first_station_z + float(station_index) * LIGHT_SPACING
			)
	_refresh_local_light_levels()


func _refresh_local_light_levels() -> void:
	for light_index: int in range(_local_lights.size()):
		var marker_index: int = _local_light_marker_indices[light_index]
		var level: float = _fixture_level(marker_index) if marker_index >= 0 else 0.0
		var local_light: OmniLight3D = _local_lights[light_index]
		local_light.light_energy = 0.70 * level
		local_light.visible = level > 0.001


func _camera_is_closer_to_last_station() -> bool:
	if _station_count <= 1:
		return true
	var camera_z: float = _camera_local_z()
	var last_station_z: float = _first_station_z + float(_station_count - 1) * LIGHT_SPACING
	return absf(camera_z - last_station_z) <= absf(camera_z - _first_station_z)


func _camera_local_z() -> float:
	var active_camera: Camera3D = get_viewport().get_camera_3d()
	if active_camera != null:
		return to_local(active_camera.global_position).z
	return _center_z + _length * 0.5


func _rail_x() -> float:
	return (
		StageConstants.FLOOR_HALF_WIDTH
		- StageConstants.FLOOR_RAIL_WIDTH * 0.5
		- StageConstants.FLOOR_RAIL_INSET
	)


func _marker_y() -> float:
	return (
		StageConstants.FLOOR_TOP_Y
		+ StageConstants.FLOOR_RAIL_HEIGHT
		+ MARKER_SIZE.y * 0.5
		+ 0.01
	)
