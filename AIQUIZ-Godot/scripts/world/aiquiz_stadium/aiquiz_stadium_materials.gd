@tool
extends RefCounted

## Runtime materials for the AIQUIZ STADIUM GLBs (assets/aiquiz_stadium, built by
## source/blender/build_stadium.py). glTF cannot say "use the vertex colour", "glow
## at night" or "sway in the wind", so the imported surfaces are swapped here by
## material name. Every stadium mesh shares these materials, so one night update
## reaches the stands, sails, gate, goal stand and backdrop at once. The islands and
## the city use the backdrop shader, which also hazes them with distance.

const SAIL_SHADER: Shader = preload("res://shaders/aiquiz_sail.gdshader")
const GLOW_SHADER: Shader = preload("res://shaders/aiquiz_vertex_glow.gdshader")
const BACKDROP_SHADER: Shader = preload("res://shaders/aiquiz_backdrop.gdshader")
## Night glow of the lit city windows relative to the lamps (kept below
## white-out so the warm and cool window colours survive the tonemapper).
const CITY_NIGHT_ENERGY := 1.6
const SAIL_NIGHT_GLOW := 0.95
## Glass curtain walls catch the sky; the islands stay matte, the open sea has no specular.
const FACADE_ROUGHNESS := 0.22
const TERRAIN_ROUGHNESS := 0.88

static var _painted: StandardMaterial3D = null
static var _glow: ShaderMaterial = null
static var _sail: ShaderMaterial = null
static var _textured := {}
static var _backdrop := {}
static var _night := 0.0
static var _haze := {}


static func painted() -> StandardMaterial3D:
	if _painted == null:
		_painted = StandardMaterial3D.new()
		_painted.resource_name = "AQS_Painted"
		_painted.vertex_color_use_as_albedo = true
		_painted.roughness = 0.74
	return _painted


static func glow() -> ShaderMaterial:
	if _glow == null:
		_glow = ShaderMaterial.new()
		_glow.resource_name = "AQS_NightGlow"
		_glow.shader = GLOW_SHADER
		_glow.set_shader_parameter("night_glow", _night)
	return _glow


static func sail(imported: Material) -> ShaderMaterial:
	if _sail == null:
		_sail = ShaderMaterial.new()
		_sail.resource_name = "AQS_SailFabric"
		_sail.shader = SAIL_SHADER
		var source := imported as BaseMaterial3D
		if source != null:
			_sail.set_shader_parameter("fabric", source.albedo_texture)
		_sail.set_shader_parameter("night_glow", _night * SAIL_NIGHT_GLOW)
	return _sail


static func sail_material() -> ShaderMaterial:
	return _sail


## Picture materials keep their texture and take the vertex colour. They are signs
## read at a slant, so they sample anisotropically (the viewport sets the level).
static func textured(imported: Material) -> Material:
	var key := imported.resource_name
	if _textured.has(key):
		return _textured[key]
	var copy := imported.duplicate() as BaseMaterial3D
	if copy == null:
		return imported
	copy.vertex_color_use_as_albedo = true
	copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_textured[key] = copy
	return copy


## Islands and city: vertex colour (and the facade picture with its night
## windows, carried by the GLB as the emission texture), hazed with distance
## toward the sky's horizon colour.
static func backdrop(imported: Material) -> ShaderMaterial:
	var key := imported.resource_name
	if _backdrop.has(key):
		return _backdrop[key]
	var material := ShaderMaterial.new()
	material.resource_name = key
	material.shader = BACKDROP_SHADER
	var source := imported as BaseMaterial3D
	material.set_shader_parameter("sea_level", StageConstants.OCEAN_SURFACE_Y)
	if key.begins_with("AQS_CityFacade") and source != null:
		material.set_shader_parameter("use_facade", true)
		material.set_shader_parameter("facade", source.albedo_texture)
		material.set_shader_parameter("facade_night", source.emission_texture)
		material.set_shader_parameter("roughness_val", FACADE_ROUGHNESS)
	elif key == "AQS_BG_Sea":
		# The open sea beyond the ocean plane: lit like ocean.gdshader (no
		# specular), hazed only from the plane's edge outward.
		material.set_shader_parameter("roughness_val", 1.0)
		material.set_shader_parameter("specular_val", 0.0)
		material.set_shader_parameter("fade_from_ocean_edge", true)
		material.set_shader_parameter("ocean_half", StageConstants.OCEAN_SIZE * 0.5)
		material.set_shader_parameter("ocean_center_z", StageConstants.OCEAN_CENTER_Z)
	else:
		material.set_shader_parameter("roughness_val", TERRAIN_ROUGHNESS)
	material.set_shader_parameter("night_energy", _night * CITY_NIGHT_ENERGY)
	material.set_shader_parameter("night_amount", _night)
	for parameter: String in _haze:
		material.set_shader_parameter(parameter, _haze[parameter])
	_backdrop[key] = material
	return material


static func swap_material(material: Material) -> Material:
	if material == null:
		return null
	var key := material.resource_name
	if key == "AQS_Painted":
		return painted()
	if key == "AQS_NightGlow":
		return glow()
	if key == "AQS_SailFabric":
		return material if material is ShaderMaterial else sail(material)
	if key in ["AQS_BG_Painted", "AQS_BG_Sea"] or key.begins_with("AQS_CityFacade"):
		return material if material is ShaderMaterial else backdrop(material)
	if key in ["AQS_BoothScreen", "AQS_LighthouseSign", "AQS_GoalBoard", "GS_SBHeaderSign"]:
		return textured(material)
	return material


## Swaps the imported surface materials of every mesh under `root`. The meshes
## are the shared imported resources, so each one only needs this once.
static func apply(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var geometry := node as MeshInstance3D
		if geometry.mesh == null:
			continue
		for surface: int in range(geometry.mesh.get_surface_count()):
			var original: Material = geometry.mesh.surface_get_material(surface)
			var swapped: Material = swap_material(original)
			if swapped != original:
				geometry.mesh.surface_set_material(surface, swapped)


static func set_night(amount: float) -> void:
	_night = clampf(amount, 0.0, 1.0)
	if _glow != null:
		_glow.set_shader_parameter("night_glow", _night)
	if _sail != null:
		_sail.set_shader_parameter("night_glow", _night * SAIL_NIGHT_GLOW)
	for material: ShaderMaterial in _backdrop.values():
		material.set_shader_parameter("night_energy", _night * CITY_NIGHT_ENERGY)
		material.set_shader_parameter("night_amount", _night)


static func night() -> float:
	return _night


## Haze of the far scenery: the sky's horizon colours (day / sunset / night),
## the direction toward the sun and the sky's energy. Kept for materials made later.
static func set_haze(parameters: Dictionary) -> void:
	for parameter: String in parameters:
		_haze[parameter] = parameters[parameter]
		for material: ShaderMaterial in _backdrop.values():
			material.set_shader_parameter(parameter, parameters[parameter])
