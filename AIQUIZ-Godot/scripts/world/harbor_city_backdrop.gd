@tool
extends Node3D

## Shared, Blender-authored Cycladic town. The imported datum is sea level.
## The central water corridor stays open for the course, sharks and helicopters.
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const CITY_SCENE: PackedScene = preload("res://assets/environment/santorini_town/town_layout.tscn")

var _window_materials: Array[StandardMaterial3D] = []
var _town_meshes: Array[MeshInstance3D] = []
var _last_night_amount: float = -1.0


func build(weather: WeatherCycle, quality: String = "balanced") -> void:
	position.y = StageConstants.OCEAN_SURFACE_Y
	# Gameplay-only scenery. Left, rear and right coast stay in world coordinates.
	# The +Z course corridor is open, including the long flyover floor.
	var island := CITY_SCENE.instantiate() as Node3D
	island.name = "SantoriniTown"
	add_child(island)
	var materials: Dictionary = {}
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		_town_meshes.append(mesh_instance)
		mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var original := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null or not (
				original.resource_name.begins_with("Santorini Window")
				or original.resource_name.begins_with("Santorini Lantern")
			):
				continue
			var key: int = original.get_instance_id()
			if not materials.has(key):
				var local_material := original.duplicate() as StandardMaterial3D
				local_material.emission_enabled = true
				local_material.emission = Color(1.0, 0.52, 0.17)
				materials[key] = local_material
				_window_materials.append(local_material)
			mesh_instance.set_surface_override_material(surface, materials[key])
	apply_graphics_quality(quality)
	if weather != null and not Engine.is_editor_hint():
		weather.night_amount_changed.connect(_set_night_amount)
		_set_night_amount(weather.night_amount)
	else:
		_set_night_amount(0.0)


func apply_graphics_quality(quality: String) -> void:
	var q := QualityRules.normalize(quality)
	var shadows := q != QualityRules.LOW and not QualityRules.is_mobile_target()
	for mesh_instance: MeshInstance3D in _town_meshes:
		mesh_instance.lod_bias = 1.0 if q == QualityRules.HIGH else (0.7 if q == QualityRules.BALANCED else 0.45)
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)


func _set_night_amount(amount: float) -> void:
	if absf(amount - _last_night_amount) < 0.02:
		return
	_last_night_amount = amount
	for material: StandardMaterial3D in _window_materials:
		material.emission_energy_multiplier = lerpf(0.0, 1.25, smoothstep(0.15, 0.9, amount))
