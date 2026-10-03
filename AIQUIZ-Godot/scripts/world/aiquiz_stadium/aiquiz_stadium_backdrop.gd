@tool
extends Node3D

## Far scenery of AIQUIZ STADIUM: the lush and rocky islands, the glass skyline
## and the sailboats (the lighthouse baked into the GLB is removed on build)
## (assets/aiquiz_stadium/aiquiz_stadium_backdrop.glb, authored in world space
## inside the 5000 m camera far plane). Also drives the night glow that every
## stadium material shares (lamps, sails, city windows) from the weather cycle,
## and the haze of the islands and the city: the backdrop shader fades them with
## distance toward the sky's horizon colour, so it follows the same sun.

const BACKDROP_SCENE: PackedScene = preload("res://assets/aiquiz_stadium/aiquiz_stadium_backdrop.glb")
const Materials = preload("res://scripts/world/aiquiz_stadium/aiquiz_stadium_materials.gd")

var _weather: Node = null


## `show_scenery` false builds no scenery (the main menu has its own harbour city and
## must not show the stadium's behind its camera) but still drives the shared night
## glow and haze, which the menu city's materials follow too.
func build(weather: Node, _quality: String, show_scenery: bool = true) -> void:
	if show_scenery:
		var scene := BACKDROP_SCENE.instantiate() as Node3D
		scene.name = "Scenery"
		# The stage has no lighthouse: drop it before it is ever added to the tree.
		var lighthouse := scene.get_node_or_null("AQS_Lighthouse")
		if lighthouse != null:
			scene.remove_child(lighthouse)
			lighthouse.free()
		add_child(scene)
		Materials.apply(scene)
		for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
			var geometry := node as MeshInstance3D
			# Kilometres away: no shadow maps, no GI.
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_weather = weather
	_copy_horizon_colours()
	if weather != null and weather.has_signal("night_amount_changed"):
		weather.night_amount_changed.connect(_on_night_amount)
		_on_night_amount(float(weather.get("night_amount")))
	else:
		_on_night_amount(0.0)


## The sky shader's horizon colours, so the haze matches the sky behind it.
## Without a shader sky the backdrop shader's defaults (the same values) stay.
func _copy_horizon_colours() -> void:
	var sky := _sky_material()
	if sky == null:
		return
	var colours := {}
	for pair: Array in [["haze_day", "horizon_day"], ["haze_sunset", "horizon_sunset"], ["haze_night", "horizon_night"]]:
		var value: Variant = sky.get_shader_parameter(pair[1])
		if value is Color:
			colours[pair[0]] = value
	Materials.set_haze(colours)


func _sky_material() -> ShaderMaterial:
	if not is_instance_valid(_weather):
		return null
	return _weather.get("sky_material") as ShaderMaterial


## The weather emits every frame it moves the sun, so the haze follows it.
func _update_haze() -> void:
	if not is_instance_valid(_weather):
		return
	var haze := {}
	var sky := _sky_material()
	var light := _weather.get("directional_light") as DirectionalLight3D
	if sky != null and sky.get_shader_parameter("cycle_sun_direction") is Vector3:
		haze["sun_direction"] = sky.get_shader_parameter("cycle_sun_direction")
	elif light != null:
		haze["sun_direction"] = light.global_transform.basis.z.normalized()
	var environment := _weather.get("environment") as Environment
	if environment != null:
		haze["haze_energy"] = environment.background_energy_multiplier
	Materials.set_haze(haze)


func _on_night_amount(amount: float) -> void:
	_update_haze()
	if absf(amount - Materials.night()) < 0.01 and amount > 0.0:
		return
	Materials.set_night(amount)


func _exit_tree() -> void:
	if is_instance_valid(_weather) and _weather.is_connected("night_amount_changed", _on_night_amount):
		_weather.night_amount_changed.disconnect(_on_night_amount)
