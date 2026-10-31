@tool
extends RefCounted

## Drives the `cloud_time` uniform of assets/environment/sky/aiquiz_day_night_sky.gdshader,
## which replaced TIME there. A sky shader that reads TIME makes Godot re-render and
## re-filter the sky's radiance cubemap every frame, whatever the Sky's process mode.
##
## Desktop: GraphicsQuality._process advances the uniform every frame by the same scaled
## frame step the renderer adds to TIME, wrapped at the same rollover, so the clouds drift
## exactly as before (wind_speed * cloud_time * 0.08).
## Mobile (GraphicsQuality.is_mobile_target()): the clouds hold still. A changed uniform
## marks the radiance dirty, and their drift (a few pixels a second) is not worth a
## cubemap pass on a phone.
##
## Every sky made by StageEnvironment.create_stage_sky() registers here. A sky material
## nobody registered (the .tres opened in the editor) keeps cloud_time = 0: still clouds.

const PARAM := &"cloud_time"
const TIME_ROLLOVER_SETTING := "rendering/limits/time/time_rollover_secs"

static var _materials: Array[WeakRef] = []
## The value TIME would have now (seconds since start, wrapped like TIME).
static var _time: float = 0.0
static var _rollover: float = 0.0


## Starts driving a sky material (does nothing for anything but a ShaderMaterial).
static func register(material: Material, mobile: bool) -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter(PARAM, _time)
	if mobile:
		return # Frozen: set once, never pushed again.
	for ref: WeakRef in _materials:
		if ref.get_ref() == shader_material:
			return
	_materials.append(weakref(shader_material))


## Called every frame (also while the tree is paused, like TIME) with the scaled frame step.
static func advance(delta: float) -> void:
	if _rollover <= 0.0:
		_rollover = maxf(float(ProjectSettings.get_setting(TIME_ROLLOVER_SETTING, 3600.0)), 1.0)
	_time = fmod(_time + delta, _rollover)
	if _materials.is_empty():
		return
	var index := _materials.size() - 1
	while index >= 0:
		var shader_material := _materials[index].get_ref() as ShaderMaterial
		if shader_material == null:
			_materials.remove_at(index)
		else:
			shader_material.set_shader_parameter(PARAM, _time)
		index -= 1


static func current_time() -> float:
	return _time
