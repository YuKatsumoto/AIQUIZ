@tool
extends Node3D

## Keeps the authored AIQUIZ sky synchronized with the DirectionalLight3D gizmo.
## The light's local Z axis is the sun direction at phase 0. Its local Y axis
## defines the direction in which the sun rises, so local Z roll tilts the orbit.

var _last_sun_direction := Vector3.INF


func _enter_tree() -> void:
	set_process(Engine.is_editor_hint())
	call_deferred("_sync_preview")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_preview()


func _sync_preview() -> void:
	var sun_control := get_node_or_null(^"SunOrbitControl") as DirectionalLight3D
	var world_environment := get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if sun_control == null or world_environment == null:
		return
	if world_environment.environment == null or world_environment.environment.sky == null:
		return

	var sun_direction: Vector3 = sun_control.basis.z.normalized()
	if sun_direction.is_equal_approx(_last_sun_direction):
		return
	_last_sun_direction = sun_direction

	var sky_material := world_environment.environment.sky.sky_material as ShaderMaterial
	if sky_material != null:
		sky_material.set_shader_parameter("cycle_sun_direction", sun_direction)

	var elevation: float = sun_direction.y
	var day_amount: float = smoothstep(-0.16, 0.28, elevation)
	var twilight_amount: float = exp(-pow(absf(elevation) / 0.23, 2.0))
	var base_color := Color(0.38, 0.50, 0.82).lerp(
		Color(1.0, 0.96, 0.86),
		day_amount
	)
	sun_control.light_color = base_color.lerp(
		Color(1.0, 0.61, 0.39),
		clampf(twilight_amount * 0.72, 0.0, 1.0)
	)
	sun_control.light_energy = maxf(
		lerpf(0.0, 1.05, day_amount),
		twilight_amount * 0.60
	)
