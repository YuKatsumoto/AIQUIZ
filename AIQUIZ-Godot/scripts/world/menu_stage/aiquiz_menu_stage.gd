class_name AiquizMenuStage
extends Node3D

## Main-menu-only stage "AIQUIZ HARBOR LAUNCH" (assets/aiquiz_menu_stage, built by
## source/blender/build_menu_stage.py in the live Blender). The menu demo (runners,
## walls, saw carriage, service vessel, helicopter pickup) keeps running on the
## StageEnvironment conveyor; this node only dresses it: the stadium's city skyline is
## moved in front of the menu camera so the harbour stands behind the gameplay course.
##
## The round launch deck with its LED screen and AIQUIZ sign (the "island" that stood in
## the sea on the right of the conveyor) is NOT built any more (BUILD_LAUNCH_DECK): the
## LED programme (MenuLedProgram) now plays on the goal stand scoreboard. Its code and
## GLB are kept, switched off, so the deck can be brought back without rebuilding it.
## Since 2026-09-30 nothing else dresses the conveyor: the white piles, far walkways,
## glass balustrades, amber lamps and light towers beside it and the bridge to the deck
## were removed, and so was the white pier fascia on the belt box (the builder's
## KEEP_PIER_FASCIA restores that one).
##
## The menu city (aiquiz_menu_city.glb) is the stadium's AQS_BG_City with its far-view
## foreground (windowless low boxes, flat sea wall, row of round trees) replaced by a
## detailed harbour waterfront: quay with steps and railing, promenade with palms and
## lamps, three rows of shop houses and apartments, a turning Ferris wheel, a market
## hall, a ferry terminal with its ferry, a marina and a lighthouse
## (source/blender/ams_waterfront.py). The Ferris wheel is a static stand
## (AMS_FerrisWheelStand), a rim that turns about the axle (AMS_FerrisWheelRim, origin
## on the axle) and 24 gondolas (AMS_FerrisGondola_00..23, origin at the hang point)
## that this node carries around the rim while they stay upright.
##
## The deck is authored in the menu world's coordinates (belt centre x 0, belt top
## y -1.2, camera looking toward -Z), so its GLB sits at the origin. The city is in its
## own local coordinates; its pose and the camera come from aiquiz_menu_stage_layout.json
## (written by the builder).

## false: the launch deck (island) is not built. Loaded on demand, so its GLB stays
## out of memory while this is off.
const BUILD_LAUNCH_DECK := false
const STAGE_PATH := "res://assets/aiquiz_menu_stage/aiquiz_menu_stage.glb"
const CITY_SCENE: PackedScene = preload("res://assets/aiquiz_menu_stage/aiquiz_menu_city.glb")
const LAYOUT_PATH := "res://assets/aiquiz_menu_stage/aiquiz_menu_stage_layout.json"
const SIGN_TEXTURE_PATH := "res://assets/aiquiz_menu_stage/aiquiz_menu_stage_sign_aiquiz.png"
const StadiumMaterials = preload("res://scripts/world/aiquiz_stadium/aiquiz_stadium_materials.gd")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const LED_SHADER: Shader = preload("res://shaders/aiquiz_menu_led.gdshader")
const SWAY_SHADER: Shader = preload("res://shaders/aiquiz_menu_sway.gdshader")
const LAMP_SHADER: Shader = preload("res://shaders/aiquiz_menu_lamp.gdshader")

## ProjectSettings switch: false restores the previous menu background (the bare
## conveyor with the stadium backdrop behind the camera).
const SETTING_ENABLED := "aiquiz/menu/harbor_stage"

## Camera pitch when the harbour city is shown. The old -14 deg kept the horizon at
## the top edge, so the skyline was only a sliver; -7 deg frames the city behind the
## conveyor while the conveyor demo stays readable.
const CAMERA_ROTATION_DEG := Vector3(-7.0, -19.0, 0.0)

## Waterfront Ferris wheel: seconds per revolution. Positive turns clockwise as seen
## from the menu camera (the wheel's front); negative turns the other way, 0 stops it.
const FERRIS_WHEEL_PERIOD := 180.0
## Gondola sway about its hang point (peak degrees, about the axle direction) and the
## sway period in seconds. Each gondola has its own phase.
const GONDOLA_SWAY_DEG := 1.2
const GONDOLA_SWAY_PERIOD := 5.0
const FERRIS_RIM_NODE := "AMS_FerrisWheelRim"
const FERRIS_GONDOLA_PATTERN := "AMS_FerrisGondola_*"

static var _layout_cache: Dictionary = {}

var layout: Dictionary = {}
## The launch deck; null while BUILD_LAUNCH_DECK is off.
var stage_root: Node3D = null
var city: Node3D = null
## The LED programme of the launch deck; null while BUILD_LAUNCH_DECK is off (the
## programme now plays on the goal stand scoreboard).
var led_program: MenuLedProgram = null
## The turning Ferris wheel (children of `city`, posed in the city's local space);
## null / empty when the city GLB has no separate rim (an older build).
var ferris_rim: Node3D = null
var ferris_gondolas: Array[Node3D] = []
var _materials := {}
var _wheel_axle := Vector3.ZERO
var _wheel_axis := Vector3.FORWARD
var _wheel_phase := 0.0
var _sway_phase := 0.0
var _rim_from_axle := Transform3D.IDENTITY
var _gondola_offsets := PackedVector3Array()
var _gondola_rest: Array[Basis] = []


static func enabled() -> bool:
	return bool(ProjectSettings.get_setting(SETTING_ENABLED, true))


static func load_layout() -> Dictionary:
	if not _layout_cache.is_empty():
		return _layout_cache
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		push_warning("AiquizMenuStage: %s is missing" % LAYOUT_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_layout_cache = parsed
	return _layout_cache


## Camera rotation for the menu: the layout's value when present (the builder and
## the game share one number), otherwise CAMERA_ROTATION_DEG.
static func camera_rotation_degrees() -> Vector3:
	var camera: Dictionary = load_layout().get("camera", {})
	var rot: Variant = camera.get("rotation_degrees")
	if rot is Array and (rot as Array).size() >= 3:
		return Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	return CAMERA_ROTATION_DEG


func build(quality: String = "") -> void:
	layout = load_layout()
	if BUILD_LAUNCH_DECK:
		_build_stage()
	_build_city()
	_setup_ferris_wheel()
	apply_graphics_quality(quality)


func _process(delta: float) -> void:
	if ferris_rim == null:
		return
	if not is_zero_approx(FERRIS_WHEEL_PERIOD):
		_wheel_phase = fposmod(_wheel_phase + delta / FERRIS_WHEEL_PERIOD, 1.0)
	_sway_phase = fposmod(_sway_phase + delta / GONDOLA_SWAY_PERIOD, 1.0)
	_pose_ferris_wheel(-TAU * _wheel_phase)


## The Ferris wheel's axle point and direction in the city's local space (the
## direction points out of the wheel's front, toward the menu camera).
func ferris_wheel_axle() -> Vector3:
	return _wheel_axle


func ferris_wheel_axis() -> Vector3:
	return _wheel_axis


func apply_graphics_quality(quality: String = "") -> void:
	var q: String = QualityRules.normalize(quality) if not quality.is_empty() else QualityRules.BALANCED
	# Menu shadows follow the preview rule (high only); the stage is near the camera,
	# so it casts on high and stays cheap elsewhere.
	var casts := QualityRules.is_at_least(q, QualityRules.HIGH) and not QualityRules.is_mobile_target()
	if stage_root != null:
		for node: Node in stage_root.find_children("*", "MeshInstance3D", true, false):
			var geometry := node as MeshInstance3D
			geometry.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
			geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _build_stage() -> void:
	var scene := load(STAGE_PATH) as PackedScene
	if scene == null:
		push_warning("AiquizMenuStage: %s is missing" % STAGE_PATH)
		return
	stage_root = scene.instantiate() as Node3D
	stage_root.name = "HarborLaunch"
	add_child(stage_root)
	for node: Node in stage_root.find_children("*", "MeshInstance3D", true, false):
		var geometry := node as MeshInstance3D
		if geometry.mesh == null:
			continue
		for surface: int in range(geometry.mesh.get_surface_count()):
			var original: Material = geometry.mesh.surface_get_material(surface)
			var swapped: Material = _swap_material(original)
			if swapped != original:
				geometry.set_surface_override_material(surface, swapped)


## The menu city, moved in front of the menu camera. It uses the stadium's shared
## backdrop materials (vertex colour, facades, night lamps), so the distance haze and
## the weather follow the rest; the waterfront facades get the same backdrop shader.
func _build_city() -> void:
	var city_layout: Dictionary = layout.get("city", {})
	if city_layout.is_empty():
		return
	city = CITY_SCENE.instantiate() as Node3D
	city.name = "MenuCity"
	add_child(city)
	var pos: Array = city_layout.get("position", [0.0, 0.0, 0.0])
	var yaw := deg_to_rad(float(city_layout.get("yaw_deg", 0.0)))
	city.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
	StadiumMaterials.apply(city)
	for node: Node in city.find_children("*", "MeshInstance3D", true, false):
		var geometry := node as MeshInstance3D
		if geometry.mesh != null:
			for surface: int in range(geometry.mesh.get_surface_count()):
				var material: Material = geometry.mesh.surface_get_material(surface)
				if material != null and material.resource_name.begins_with("AMS_Facade"):
					geometry.mesh.surface_set_material(surface, _facade_material(material))
		# 750 m and more away: no shadow maps, no GI (as the stadium backdrop).
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## Finds the Ferris wheel's rim and gondolas under the city and records their rest
## pose. The layout gives the axle and its direction in Blender's city-local convention
## (x, y, z), which is the glTF / Godot city-local (x, z, -y); without them the rim's
## own origin (built on the axle) and the Blender +y axle are used.
func _setup_ferris_wheel() -> void:
	ferris_rim = null
	ferris_gondolas.clear()
	_gondola_rest.clear()
	_gondola_offsets.resize(0)
	if city != null:
		var rim := city.find_child(FERRIS_RIM_NODE, true, false) as Node3D
		if rim != null and rim.get_parent() == city:
			ferris_rim = rim
	if ferris_rim == null:
		set_process(false)
		return
	var city_layout: Dictionary = layout.get("city", {})
	var waterfront: Dictionary = city_layout.get("waterfront", {})
	_wheel_axle = ferris_rim.position
	var axle: Variant = waterfront.get("wheel_axle_local", waterfront.get("wheel_center_local"))
	if axle is Array and (axle as Array).size() >= 3:
		_wheel_axle = Vector3(float(axle[0]), float(axle[2]), -float(axle[1]))
	_wheel_axis = Vector3(0.0, 0.0, -1.0)
	var axis: Variant = waterfront.get("wheel_axis_local")
	if axis is Array and (axis as Array).size() >= 3:
		var direction := Vector3(float(axis[0]), float(axis[2]), -float(axis[1]))
		if not direction.is_zero_approx():
			_wheel_axis = direction.normalized()
	_rim_from_axle = Transform3D(Basis.IDENTITY, -_wheel_axle) * ferris_rim.transform
	for node: Node in city.find_children(FERRIS_GONDOLA_PATTERN, "Node3D", true, false):
		if node.get_parent() == city:
			ferris_gondolas.append(node as Node3D)
	ferris_gondolas.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	_gondola_offsets.resize(ferris_gondolas.size())
	for i: int in ferris_gondolas.size():
		_gondola_offsets[i] = ferris_gondolas[i].position - _wheel_axle
		_gondola_rest.append(ferris_gondolas[i].basis)
	set_process(true)
	_pose_ferris_wheel(-TAU * _wheel_phase)


## Poses the wheel `angle` radians about its axle (negative = clockwise as seen from the
## menu camera): the rim turns rigidly about the axle, and each gondola's hang point
## turns with it while the gondola only translates (plus a small sway about the axle
## direction through its hang point), so it stays upright. No allocation per call.
func _pose_ferris_wheel(angle: float) -> void:
	var turn := Basis(_wheel_axis, angle)
	ferris_rim.transform = Transform3D(turn, _wheel_axle) * _rim_from_axle
	var sway := deg_to_rad(GONDOLA_SWAY_DEG)
	for i: int in ferris_gondolas.size():
		var swing := sway * sin(TAU * _sway_phase + float(i) * 1.7)
		ferris_gondolas[i].transform = Transform3D(
			Basis(_wheel_axis, swing) * _gondola_rest[i], _wheel_axle + turn * _gondola_offsets[i]
		)


## Waterfront facades (AMS_Facade_*): the backdrop shader with the facade picture and
## its night windows, like the stadium's AQS_CityFacade_* materials.
static func _facade_material(imported: Material) -> Material:
	if imported is ShaderMaterial:
		return imported
	var material := StadiumMaterials.backdrop(imported)
	var source := imported as BaseMaterial3D
	if source != null:
		material.set_shader_parameter("use_facade", true)
		material.set_shader_parameter("facade", source.albedo_texture)
		material.set_shader_parameter("facade_night", source.emission_texture)
		material.set_shader_parameter("roughness_val", StadiumMaterials.FACADE_ROUGHNESS)
	return material


func _swap_material(material: Material) -> Material:
	if material == null:
		return null
	var key := material.resource_name
	if _materials.has(key):
		return _materials[key]
	var out: Material = material
	match key:
		"AQS_Painted", "AQS_NightGlow":
			out = StadiumMaterials.swap_material(material)
		"AMS_Lamp":
			var lamp := ShaderMaterial.new()
			lamp.resource_name = key
			lamp.shader = LAMP_SHADER
			out = lamp
		"AMS_Glass":
			var glass := StandardMaterial3D.new()
			glass.resource_name = key
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color = Color(0.72, 0.9, 0.97, 0.3)
			glass.roughness = 0.06
			glass.metallic_specular = 0.8
			glass.cull_mode = BaseMaterial3D.CULL_BACK
			out = glass
		"AMS_LedScreen":
			var led := ShaderMaterial.new()
			led.resource_name = key
			led.shader = LED_SHADER
			var sign := load(SIGN_TEXTURE_PATH) as Texture2D
			if sign != null:
				led.set_shader_parameter("logo", sign)
			var led_size: Array = layout.get("led_size", [10.4, 4.7])
			var sign_size: Array = layout.get("sign_size", [13.0, 3.4])
			led.set_shader_parameter("screen_aspect", float(led_size[0]) / float(led_size[1]))
			led.set_shader_parameter("sign_aspect", float(sign_size[0]) / float(sign_size[1]))
			led.set_shader_parameter("use_logo", sign != null)
			_attach_led_program(led)
			out = led
		"AMS_Sign":
			var sign_mat := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
			if sign_mat != null:
				sign_mat.emission_enabled = true
				sign_mat.emission_texture = sign_mat.albedo_texture
				sign_mat.emission = Color.WHITE
				sign_mat.emission_energy_multiplier = 0.35
				sign_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				out = sign_mat
		"AMS_Paving":
			var paving := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
			if paving != null:
				paving.vertex_color_use_as_albedo = true
				paving.roughness = 0.82
				paving.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				out = paving
		"AMS_Pennant":
			out = _sway(key, 0.16, 3.1, 0.3, 0.8)
		"AMS_Foliage":
			out = _sway(key, 0.12, 1.25, 0.12, 0.72)
	_materials[key] = out
	return out


## "AIQUIZ VISION": past highlights and records on the LED (MenuLedProgram).
func _attach_led_program(led: ShaderMaterial) -> void:
	var program := MenuLedProgram.new()
	add_child(program)
	if not program.setup():
		program.queue_free()
		return
	led_program = program
	led.set_shader_parameter("program", program.get_texture())
	var level := 1
	for mip: Texture2D in program.get_mip_textures():
		led.set_shader_parameter("program_mip%d" % level, mip)
		level += 1
	led.set_shader_parameter("program_size", Vector2(MenuLedProgram.CANVAS))
	led.set_shader_parameter("use_program", true)


func _sway(key: String, amplitude: float, frequency: float, droop: float, roughness: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.resource_name = key
	mat.shader = SWAY_SHADER
	mat.set_shader_parameter("amplitude", amplitude)
	mat.set_shader_parameter("frequency", frequency)
	mat.set_shader_parameter("droop", droop)
	mat.set_shader_parameter("roughness_val", roughness)
	return mat
