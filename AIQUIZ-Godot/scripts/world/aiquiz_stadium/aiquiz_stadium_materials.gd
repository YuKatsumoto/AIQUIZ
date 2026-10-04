@tool
extends RefCounted

## Runtime materials for the AIQUIZ STADIUM GLBs (assets/aiquiz_stadium, built by
## source/blender/build_stadium.py). glTF cannot say "use the vertex colour", "glow
## at night" or "sway in the wind", so the imported surfaces are swapped here by
## material name. Every stadium mesh shares these materials, so one night update
## reaches the stands, sails, gate, goal stand and backdrop at once. The islands and
## the city use the backdrop shader, which also hazes them with distance.
##
## The painted surfaces (AQS_Painted: side stands, goal gate, goal stand, sailboats)
## use aiquiz_stand_surface.gdshader: the vertex colour (AO and waterline grime baked in
## Blender) plus ALU-only weathering (mottle, wet waterline, rain streaks). Its detail
## follows GameManager.graphics_quality (low = vertex colour only, as before).

const SAIL_SHADER: Shader = preload("res://shaders/aiquiz_sail.gdshader")
const GLOW_SHADER: Shader = preload("res://shaders/aiquiz_vertex_glow.gdshader")
const BACKDROP_SHADER: Shader = preload("res://shaders/aiquiz_backdrop.gdshader")
const PAINT_SHADER: Shader = preload("res://shaders/aiquiz_stand_surface.gdshader")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const OceanDetailScript = preload("res://scripts/world/ocean_detail.gd")
## Instance parameter of the paint shader: 1 = weathering in the object's own space.
const PAINT_OBJECT_SPACE := &"object_space"
## The stage fog (scripts/world/stage_atmosphere.gd, FOG_DENSITY) that the far sea continues
## from the ocean plane's edge, until set_haze() hands over the environment's own value
## ("edge_fog_density").
const ATMOSPHERE_SCRIPT_PATH := "res://scripts/world/stage_atmosphere.gd"
## Share of ocean.gdshader's fresnel_strength the ocean plane reflects at its far edge
## (grazing view: Schlick at about 0.3 degrees).
const FAR_SEA_REFLECT_SHARE := 0.95
## Night glow of the lit city windows relative to the lamps (kept below
## white-out so the warm and cool window colours survive the tonemapper).
const CITY_NIGHT_ENERGY := 1.6
const SAIL_NIGHT_GLOW := 0.95
## Glass curtain walls catch the sky; the islands stay matte, the open sea has no specular.
const FACADE_ROUGHNESS := 0.22
const TERRAIN_ROUGHNESS := 0.88

static var _painted: ShaderMaterial = null
## The graphics quality last applied ("" until the game's quality is known).
static var _quality := ""
static var _quality_watched := false
## The GameManager autoload (looked up once).
static var _manager: WeakRef = null
static var _glow: ShaderMaterial = null
static var _sail: ShaderMaterial = null
static var _textured := {}
static var _backdrop := {}
static var _night := 0.0
static var _haze := {}


## The shared paint (vertex colour + weathering). Every call re-reads the graphics
## quality, so a stage built after a quality change gets the matching detail.
static func painted() -> ShaderMaterial:
	if _painted == null:
		_painted = ShaderMaterial.new()
		_painted.resource_name = "AQS_Painted"
		_painted.shader = PAINT_SHADER
		_painted.set_shader_parameter("sea_level", StageConstants.OCEAN_SURFACE_Y)
		_apply_paint_quality(_painted, _quality)
	_sync_graphics_quality()
	return _painted


## Applies a graphics quality to the shared materials that depend on it:
##   - the paint: low keeps the plain vertex colour (the former StandardMaterial3D look),
##     balanced adds the mottle, wet waterline and streaks, high and ultra the finer second
##     mottle octave and its tint drift;
##   - the far sea: how much of the sky the ocean plane reflects at its edge on this quality.
## GameManager.set_graphics_quality() reaches it through graphics_quality_changed.
static func apply_graphics_quality(quality: String) -> void:
	var q: String = QualityRules.normalize(quality)
	_quality = q
	if _painted != null:
		_apply_paint_quality(_painted, q)
	var far_sea: ShaderMaterial = _backdrop.get("AQS_BG_Sea")
	if far_sea != null:
		far_sea.set_shader_parameter("edge_reflect", _far_sea_reflect(q))


static func _apply_paint_quality(material: ShaderMaterial, quality: String) -> void:
	if quality.is_empty():
		return # Editor previews: the shader's defaults (full detail).
	var plain: bool = quality == QualityRules.LOW or QualityRules.is_mobile_target()
	material.set_shader_parameter("detail", 0.0 if plain else 1.0)
	material.set_shader_parameter("fine_detail", QualityRules.is_at_least(quality, QualityRules.HIGH))


## The share of the sky the desktop ocean reflects at the plane's far edge on `quality`
## (ocean_detail.gd); the mobile ocean reflects nothing.
static func _far_sea_reflect(quality: String) -> float:
	if quality.is_empty() or QualityRules.is_mobile_target():
		return 0.0
	var settings: Dictionary = OceanDetailScript.SETTINGS.get(quality, OceanDetailScript.SETTINGS["balanced"])
	return float(settings.get("fresnel_strength", 0.0)) * FAR_SEA_REFLECT_SHARE


## The stage fog's density as stage_atmosphere.gd sets it (0 without that script).
static func _stage_fog_density() -> float:
	if not ResourceLoader.exists(ATMOSPHERE_SCRIPT_PATH):
		return 0.0
	var script := load(ATMOSPHERE_SCRIPT_PATH) as Script
	if script == null:
		return 0.0
	return float(script.get_script_constant_map().get("FOG_DENSITY", 0.0))


## Picks up the game's current quality (and starts following its changes). Also runs
## from set_haze(), which the backdrop calls every frame the weather moves, so a quality
## assigned without the signal (tests, previews) reaches the shared materials too.
static func _sync_graphics_quality() -> void:
	_watch_graphics_quality()
	var quality := _current_graphics_quality()
	if not quality.is_empty() and QualityRules.normalize(quality) != _quality:
		apply_graphics_quality(quality)


static func _game_manager() -> Node:
	var manager: Node = _manager.get_ref() as Node if _manager != null else null
	if manager != null:
		return manager
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	manager = tree.root.get_node_or_null(^"GameManager")
	if manager != null:
		_manager = weakref(manager)
	return manager


## The running game's quality ("" in the editor, where there is no GameManager).
static func _current_graphics_quality() -> String:
	var manager := _game_manager()
	if manager == null:
		return ""
	var raw: Variant = manager.get("graphics_quality")
	return String(raw) if typeof(raw) == TYPE_STRING else ""


## Follows GameManager.set_graphics_quality() while the game runs (the cached
## stand meshes keep this material, so it is retuned in place).
static func _watch_graphics_quality() -> void:
	if _quality_watched:
		return
	var manager := _game_manager()
	if manager == null or not manager.has_signal(&"graphics_quality_changed"):
		return
	manager.connect(&"graphics_quality_changed", _on_graphics_quality_changed)
	_quality_watched = true


static func _on_graphics_quality_changed(quality: String) -> void:
	apply_graphics_quality(quality)


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
		# specular), hazed from the plane's edge outward. Its FOG replaces the
		# environment fog, so it carries on the fog and the sky reflection the
		# ocean plane has at its edge itself (no dark seam at the horizon).
		material.set_shader_parameter("roughness_val", 1.0)
		material.set_shader_parameter("specular_val", 0.0)
		material.set_shader_parameter("fade_from_ocean_edge", true)
		material.set_shader_parameter("ocean_half", StageConstants.OCEAN_SIZE * 0.5)
		material.set_shader_parameter("ocean_center_z", StageConstants.OCEAN_CENTER_Z)
		_sync_graphics_quality()
		material.set_shader_parameter("edge_reflect", _far_sea_reflect(_quality))
		material.set_shader_parameter("edge_fog_density", _stage_fog_density())
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
## The painted instances found here keep their weathering in their own space
## (instance parameter object_space): the goal gate and the goal stand ride the
## course, so world-space mottle would slide over them. The side stand blocks are
## made later from cached meshes (aiquiz_stadium_stand.gd), never move and keep the
## world-space weathering, which does not repeat from one 20 m block to the next.
static func apply(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var geometry := node as MeshInstance3D
		if geometry.mesh == null:
			continue
		var uses_paint := false
		for surface: int in range(geometry.mesh.get_surface_count()):
			var original: Material = geometry.mesh.surface_get_material(surface)
			var swapped: Material = swap_material(original)
			if swapped != original:
				geometry.mesh.surface_set_material(surface, swapped)
			uses_paint = uses_paint or (swapped != null and swapped == _painted)
		if uses_paint:
			geometry.set_instance_shader_parameter(PAINT_OBJECT_SPACE, 1.0)


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
	_sync_graphics_quality()
	for parameter: String in parameters:
		_haze[parameter] = parameters[parameter]
		for material: ShaderMaterial in _backdrop.values():
			material.set_shader_parameter(parameter, parameters[parameter])
