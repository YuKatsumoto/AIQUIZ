@tool
class_name StageEnvironment
extends Node3D

## メニュープレビューと本編ゲームで共有するステージの「器」。
## 環境・照明・床・コンベアベルト・ローラー・レール・サイドフレーム・海を構築し、
## 床ジオメトリとベルトスクロールの更新 API を公開する。
##
## 壁・プレイヤー・演出は各レイヤー（MenuPreviewLayer / GamePlayLayer）が別に持つ。

const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const CONVEYOR_FLOOR_SHADER: Shader = preload("res://shaders/conveyor_belt_floor.gdshader")
const MOBILE_OCEAN_SHADER: Shader = preload("res://shaders/ocean_mobile.gdshader")
const SHARK_SWIMMER_SCENE: PackedScene = preload("res://scenes/shark_swimmer.tscn")
const SharkSwimmerScript = preload("res://scripts/world/shark_swimmer.gd")
const WeatherCycleScript = preload("res://scripts/world/weather_cycle.gd")
const TerraceStandScript = preload("res://scripts/world/santorini_terrace_stand.gd")
const AiquizStandScript = preload("res://scripts/world/aiquiz_stadium/aiquiz_stadium_stand.gd")
const AiquizBackdropScript = preload("res://scripts/world/aiquiz_stadium/aiquiz_stadium_backdrop.gd")
const HarborCityBackdropScript = preload("res://scripts/world/harbor_city_backdrop.gd")
const WaterfrontScript = preload("res://scripts/world/santorini_waterfront.gd")
const StageMaterialsScript = preload("res://scripts/world/stage_materials.gd")
const StageAtmosphereScript = preload("res://scripts/world/stage_atmosphere.gd")
const OceanDetailScript = preload("res://scripts/world/ocean_detail.gd")
const AIQUIZ_STAGE_SKY_PATH := "res://assets/environment/sky/aiquiz_day_night_sky.tres"
const GRANDSTAND_SIDE_OFFSET: float = 28.0
## Side stands and scenery. "aiquiz": AIQUIZ STADIUM (sails, lighthouse, islands,
## skyline; assets/aiquiz_stadium). "santorini": the previous terrace stands.
const STADIUM_AIQUIZ := "aiquiz"
const STADIUM_SANTORINI := "santorini"
const GENERATED_STAGE_META: StringName = &"stage_environment_generated"

@export_category("Stage Layout")
@export var layout_floor_center_z: float = 4.0:
	set(value):
		layout_floor_center_z = value
		_queue_editor_preview_rebuild()
@export_range(16.0, 512.0, 1.0, "or_greater") var layout_floor_length: float = 160.0:
	set(value):
		layout_floor_length = value
		_queue_editor_preview_rebuild()
@export var layout_include_back_roller: bool = true:
	set(value):
		layout_include_back_roller = value
		_queue_editor_preview_rebuild()
@export var layout_include_floor_collision: bool = true:
	set(value):
		layout_include_floor_collision = value
		_queue_editor_preview_rebuild()
@export var layout_include_sharks: bool = true:
	set(value):
		layout_include_sharks = value
		_queue_editor_preview_rebuild()
@export var layout_include_grandstands: bool = true:
	set(value):
		layout_include_grandstands = value
		_queue_editor_preview_rebuild()
@export var layout_include_left_grandstand: bool = true:
	set(value):
		layout_include_left_grandstand = value
		_queue_editor_preview_rebuild()
@export var layout_include_right_grandstand: bool = true:
	set(value):
		layout_include_right_grandstand = value
		_queue_editor_preview_rebuild()
@export_range(12.0, 80.0, 0.5, "or_greater") var layout_grandstand_side_offset: float = 28.0:
	set(value):
		layout_grandstand_side_offset = value
		_queue_editor_preview_rebuild()

@export_enum("aiquiz", "santorini") var layout_stadium_style: String = STADIUM_AIQUIZ:
	set(value):
		layout_stadium_style = value
		_queue_editor_preview_rebuild()

# Town source/assets remain available; enable this to restore the Santorini backdrop.
@export var layout_include_harbor_city: bool = false:
	set(value):
		layout_include_harbor_city = value
		_queue_editor_preview_rebuild()

@export_category("Spectators")
@export var layout_include_spectators: bool = true:
	set(value):
		layout_include_spectators = value
		_queue_editor_preview_rebuild()
@export_range(0.0, 1.0, 0.05) var layout_spectator_density: float = 0.85:
	set(value):
		layout_spectator_density = value
		_queue_editor_preview_rebuild()

@export_category("3D Editor Preview")
@export var editor_preview_enabled: bool = true:
	set(value):
		editor_preview_enabled = value
		_queue_editor_preview_rebuild()

# --- 構成オプション ---
var _scroll_sign: float = 1.0
var _return_scroll_sign: float = -1.0
var _include_back_roller: bool = true
var _include_floor_collision: bool = true
var _is_preview_environment: bool = false
var _include_sharks: bool = false
var _include_grandstands: bool = false
var _include_left_grandstand: bool = true
var _include_right_grandstand: bool = true
var _grandstand_side_offset: float = GRANDSTAND_SIDE_OFFSET
var _include_spectators: bool = true
var _spectator_density: float = 0.85
var _stadium_style: String = STADIUM_AIQUIZ

# --- ノード参照 ---
var floor_mesh: MeshInstance3D = null
var environment_node: WorldEnvironment = null
var directional_light: DirectionalLight3D = null
var weather_cycle: WeatherCycle = null
var _ocean_surface: MeshInstance3D = null
var _grandstands_container: Node3D = null
var _waterfront: Node3D = null
var _stadium_backdrop: Node3D = null
var _shark_school: Node3D = null
## Reflection probe and vignette (StageAtmosphere.build); freed with the other generated children.
var _atmosphere: Node3D = null

var _floor_belt_material: ShaderMaterial = null
var _floor_collision_body: StaticBody3D = null
var _running_rails: ConveyorRails = null
var _floor_rail_left: MeshInstance3D = null
var _floor_rail_right: MeshInstance3D = null
var _conveyor_roller_front: MeshInstance3D = null
var _conveyor_roller_back: MeshInstance3D = null
var _conveyor_return_belt: MeshInstance3D = null
var _conveyor_return_material: ShaderMaterial = null
var _conveyor_roller_front_material: ShaderMaterial = null
var _conveyor_roller_back_material: ShaderMaterial = null
var _conveyor_side_frame_left: MeshInstance3D = null
var _conveyor_side_frame_right: MeshInstance3D = null

## Sudden death shaft hole (set_shaft_hole). Kept across rebuilds and quality changes.
const SHAFT_HOLE_PARAM: StringName = &"shaft_hole"
const SHAFT_BASE_SHADER_META: StringName = &"shaft_hole_base_shader"
## Base shader -> the same code compiled with SHAFT_HOLE (see _shaft_hole_variant).
static var _shaft_hole_variants: Dictionary = {}
var _shaft_hole_center: Vector3 = Vector3.ZERO
var _shaft_hole_radius: float = 0.0
var _shaft_hole_active: bool = false
## Stage pieces hidden while the hole is open: wholly below the floor top inside the cylinder.
var _shaft_hidden_nodes: Array[GeometryInstance3D] = []
## Pieces inside the cylinder that also rise above the floor top (left visible; debug only).
var _shaft_crossing_nodes: Array[String] = []

var _floor_center_z: float = 0.0
var _floor_length: float = 144.0
## 観客スタンドが最後に同期した床長。動的床の縮小ではブロックを減らさない。
var _grandstand_synced_length: float = 0.0
var _editor_preview_rebuild_queued: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		_queue_editor_preview_rebuild()


func gameplay_build_config() -> Dictionary:
	return {
		"floor_center_z": layout_floor_center_z,
		"floor_length": layout_floor_length,
		"scroll_sign": 1.0,
		"return_scroll_sign": -1.0,
		"include_back_roller": layout_include_back_roller,
		"include_floor_collision": layout_include_floor_collision,
		"include_sharks": layout_include_sharks,
		"include_grandstands": layout_include_grandstands,
		"include_left_grandstand": layout_include_left_grandstand,
		"include_right_grandstand": layout_include_right_grandstand,
		"grandstand_side_offset": layout_grandstand_side_offset,
		"include_spectators": layout_include_spectators,
		"spectator_density": layout_spectator_density,
		"include_harbor_city": layout_include_harbor_city,
		"stadium_style": layout_stadium_style,
	}


func _queue_editor_preview_rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _editor_preview_rebuild_queued:
		return
	_editor_preview_rebuild_queued = true
	call_deferred("_rebuild_editor_preview")


func _rebuild_editor_preview() -> void:
	_editor_preview_rebuild_queued = false
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_clear_built_stage()
	if editor_preview_enabled:
		build(gameplay_build_config())


func _add_generated_stage_child(node: Node) -> void:
	node.set_meta(GENERATED_STAGE_META, true)
	add_child(node)


func _clear_built_stage() -> void:
	for child: Node in get_children():
		if bool(child.get_meta(GENERATED_STAGE_META, false)):
			remove_child(child)
			child.free()
	environment_node = null
	directional_light = null
	weather_cycle = null
	floor_mesh = null
	_ocean_surface = null
	_grandstands_container = null
	_waterfront = null
	_stadium_backdrop = null
	_shark_school = null
	_atmosphere = null
	_running_rails = null
	_floor_belt_material = null
	_floor_collision_body = null
	_floor_rail_left = null
	_floor_rail_right = null
	_conveyor_roller_front = null
	_conveyor_roller_back = null
	_conveyor_return_belt = null
	_conveyor_side_frame_left = null
	_conveyor_side_frame_right = null
	_conveyor_return_material = null
	_conveyor_roller_front_material = null
	_conveyor_roller_back_material = null
	_grandstand_synced_length = 0.0
	_shaft_hidden_nodes.clear()
	_shaft_crossing_nodes.clear()


## ステージを構築する。
## config キー: floor_center_z, floor_length, scroll_sign, return_scroll_sign,
##              include_back_roller, include_floor_collision,
##              is_preview, include_sharks, include_grandstands,
##              include_left_grandstand, include_right_grandstand,
##              include_harbor_city (default false; retained town data can be re-enabled),
##              include_stadium_scenery (default true; false builds no lighthouse,
##              islands, skyline or sailboats, e.g. in the menu, whose camera can turn
##              round to face them)
func build(config: Dictionary = {}) -> void:
	_clear_built_stage()
	_floor_center_z = float(config.get("floor_center_z", 0.0))
	_floor_length = float(config.get("floor_length", 144.0))
	_scroll_sign = float(config.get("scroll_sign", 1.0))
	_return_scroll_sign = float(config.get("return_scroll_sign", -1.0))
	_include_back_roller = bool(config.get("include_back_roller", true))
	_include_floor_collision = bool(config.get("include_floor_collision", true))
	_is_preview_environment = bool(config.get("is_preview", false))
	_include_sharks = bool(config.get("include_sharks", false))
	_include_grandstands = bool(config.get("include_grandstands", false))
	_include_left_grandstand = bool(config.get("include_left_grandstand", true))
	_include_right_grandstand = bool(config.get("include_right_grandstand", true))
	_grandstand_side_offset = float(config.get("grandstand_side_offset", GRANDSTAND_SIDE_OFFSET))
	_include_spectators = bool(config.get("include_spectators", true))
	_spectator_density = clampf(float(config.get("spectator_density", 0.85)), 0.0, 1.0)
	var include_harbor_city: bool = config.get("include_harbor_city", layout_include_harbor_city) != false
	_stadium_style = String(config.get("stadium_style", layout_stadium_style))
	if _stadium_style != STADIUM_SANTORINI:
		_stadium_style = STADIUM_AIQUIZ

	_setup_environment()
	_setup_lighting()
	_setup_weather_cycle()
	_setup_floor()
	_setup_floor_conveyor()
	_setup_ocean()
	if include_harbor_city:
		_setup_harbor_city()
	if _include_grandstands:
		_setup_grandstands()
	if include_harbor_city or _include_grandstands:
		_waterfront = WaterfrontScript.new()
		_waterfront.name = "WaterfrontInfrastructure"
		_add_generated_stage_child(_waterfront)
		# AIQUIZ STADIUM keeps the seabed but not the Santorini quay stairs and bays.
		var routed_stands: Node3D = _grandstands_container if _stadium_style == STADIUM_SANTORINI else null
		_waterfront.setup(routed_stands, include_harbor_city, _graphics_quality())
	if _stadium_style == STADIUM_AIQUIZ:
		_setup_stadium_backdrop(bool(config.get("include_stadium_scenery", true)))
	if _include_sharks:
		_setup_sharks()
	_atmosphere = StageAtmosphereScript.build(self, _graphics_quality(), not _is_preview_environment)
	if _atmosphere != null:
		_add_generated_stage_child(_atmosphere)

	set_floor_geometry(_floor_center_z, _floor_length)
	if _shaft_hole_active:
		_apply_shaft_hole()


static func _graphics_quality() -> String:
	var raw: Variant = GameManager.get("graphics_quality")
	if typeof(raw) != TYPE_STRING or String(raw).is_empty():
		return QualityRules.BALANCED
	return QualityRules.normalize(String(raw))


static func create_stage_sky() -> Sky:
	if ResourceLoader.exists(AIQUIZ_STAGE_SKY_PATH):
		var loaded: Resource = load(AIQUIZ_STAGE_SKY_PATH)
		if loaded is Sky:
			var sky: Sky = (loaded as Sky).duplicate(true) as Sky
			sky.radiance_size = Sky.RADIANCE_SIZE_256
			sky.process_mode = Sky.PROCESS_MODE_REALTIME
			return sky
	return _create_procedural_fallback_sky()


static func _create_procedural_fallback_sky() -> Sky:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.08, 0.32, 0.74)
	sky_material.sky_horizon_color = Color(0.48, 0.76, 0.98)
	sky_material.sky_curve = 0.12
	sky_material.sky_energy_multiplier = 1.0
	sky_material.ground_bottom_color = Color(0.08, 0.16, 0.28)
	sky_material.ground_horizon_color = Color(0.48, 0.76, 0.98)
	sky_material.ground_curve = 0.08
	# 地平線では空側と同じ明るさにし、海との間に暗い帯が出ないようにする。
	sky_material.ground_energy_multiplier = 1.0
	sky_material.sun_angle_max = 4.0
	sky_material.sun_curve = 0.08

	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	return sky


static func configure_stage_environment(env: Environment) -> void:
	env.background_mode = Environment.BG_SKY
	env.sky = create_stage_sky()
	env.background_energy_multiplier = 1.0
	env.ambient_light_color = Color(0.58, 0.68, 0.82)
	env.ambient_light_energy = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = false
	env.volumetric_fog_enabled = false


func _setup_environment() -> void:
	var env := Environment.new()
	configure_stage_environment(env)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.8
	env.glow_bloom = 0.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.8
	env.set_glow_level(0, true)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, false)
	QualityRules.apply_environment(env, _graphics_quality())
	StageAtmosphereScript.apply_environment_quality(env, _graphics_quality())

	environment_node = WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	environment_node.environment = env
	_add_generated_stage_child(environment_node)


func apply_graphics_quality(quality: String = "") -> void:
	var q: String = QualityRules.normalize(quality) if not quality.is_empty() else _graphics_quality()
	if environment_node != null and environment_node.environment != null:
		QualityRules.apply_environment(environment_node.environment, q)
		StageAtmosphereScript.apply_environment_quality(environment_node.environment, q)
	_apply_surface_material_quality(q)
	StageAtmosphereScript.apply_graphics_quality(_atmosphere, q)
	if directional_light != null:
		QualityRules.configure_directional_shadow(directional_light, q)
		directional_light.shadow_enabled = (
			QualityRules.preview_shadow_enabled(q)
			if _is_preview_environment
			else QualityRules.gameplay_shadow_enabled(q)
		)
	if _ocean_surface != null and is_instance_valid(_ocean_surface):
		configure_ocean_surface(_ocean_surface, q)
		_link_ocean_to_weather()
		# The ocean gets a fresh material (desktop or mobile shader); carry the shaft hole over.
		_apply_shaft_hole_materials()
	var town := get_node_or_null("HarborCityBackdrop")
	if town != null:
		town.apply_graphics_quality(q)
	if is_instance_valid(_waterfront):
		_waterfront.apply_graphics_quality(q)
	if _grandstands_container == null:
		return
	for child: Node in _grandstands_container.get_children():
		var stand := child as Node3D
		if stand != null:
			_configure_grandstand_geometry(stand)


func _setup_lighting() -> void:
	directional_light = DirectionalLight3D.new()
	directional_light.name = "DirectionalLight3D"
	directional_light.rotation_degrees = Vector3(-50, -20, 0)
	directional_light.light_color = Color(0.90, 0.92, 0.95)
	directional_light.light_energy = 1.2
	QualityRules.configure_directional_shadow(directional_light, _graphics_quality())
	directional_light.shadow_enabled = (
		QualityRules.preview_shadow_enabled(_graphics_quality())
		if _is_preview_environment
		else QualityRules.gameplay_shadow_enabled(_graphics_quality())
	)
	_add_generated_stage_child(directional_light)


func _setup_weather_cycle() -> void:
	var env: Environment = null
	if environment_node != null:
		env = environment_node.environment
	weather_cycle = attach_weather_cycle(self, env, directional_light)
	weather_cycle.set_meta(GENERATED_STAGE_META, true)


static func attach_weather_cycle(
		parent: Node,
		env: Environment,
		light: DirectionalLight3D,
		node_name: String = "WeatherCycle"
	) -> WeatherCycle:
	var cycle: WeatherCycle = WeatherCycleScript.new() as WeatherCycle
	cycle.name = node_name
	parent.add_child(cycle)
	cycle.setup(env, light)
	return cycle


func _setup_floor() -> void:
	floor_mesh = MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var box := BoxMesh.new()
	box.size = Vector3(StageConstants.FLOOR_WIDTH, StageConstants.FLOOR_THICKNESS, _floor_length)
	floor_mesh.mesh = box
	_add_generated_stage_child(floor_mesh)


func _setup_floor_conveyor() -> void:
	if not floor_mesh:
		return
	_floor_belt_material = ShaderMaterial.new()
	_floor_belt_material.shader = CONVEYOR_FLOOR_SHADER
	_floor_belt_material.set_shader_parameter("scroll_z", 0.0)
	_floor_belt_material.set_shader_parameter("scroll_sign", _scroll_sign)
	_floor_belt_material.set_shader_parameter("base_color", StageConstants.CONVEYOR_BELT_BASE_COLOR)
	_floor_belt_material.set_shader_parameter("stripe_color", StageConstants.CONVEYOR_BELT_STRIPE_COLOR)
	_floor_belt_material.set_shader_parameter("side_color", StageConstants.CONVEYOR_BELT_SIDE_COLOR)
	StageMaterialsScript.belt_detail(_floor_belt_material, _graphics_quality())
	floor_mesh.material_override = _floor_belt_material
	_setup_floor_rails()
	_setup_conveyor_loop_geometry()
	if _include_floor_collision:
		_setup_floor_collision()


func _setup_floor_collision() -> void:
	if not floor_mesh:
		return
	var floor_box: BoxMesh = floor_mesh.mesh as BoxMesh
	if not floor_box:
		return
	var half_thickness := StageConstants.FLOOR_THICKNESS * 0.5
	const COL_HEIGHT := 0.5
	_floor_collision_body = StaticBody3D.new()
	_floor_collision_body.collision_layer = 1
	_floor_collision_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(floor_box.size.x, COL_HEIGHT, floor_box.size.z)
	col.shape = shape
	_floor_collision_body.add_child(col)
	# コリジョン上面を FLOOR_TOP_Y（床上面）に合わせる
	_floor_collision_body.position = Vector3(0, half_thickness - COL_HEIGHT * 0.5, 0)
	floor_mesh.add_child(_floor_collision_body)


func _setup_floor_rails() -> void:
	_running_rails = preload("res://scripts/world/conveyor_rails.gd").new()
	_running_rails.name = "ConveyorRunningRails"
	_add_generated_stage_child(_running_rails)
	_running_rails.build(_floor_center_z, _floor_length, StageConstants.FLOOR_TOP_Y)
	_floor_rail_left = _running_rails.left_head
	_floor_rail_right = _running_rails.right_head


func _setup_conveyor_loop_geometry() -> void:
	var roller_mesh := CylinderMesh.new()
	roller_mesh.top_radius = StageConstants.CONVEYOR_ROLLER_RADIUS
	roller_mesh.bottom_radius = StageConstants.CONVEYOR_ROLLER_RADIUS
	roller_mesh.height = StageConstants.CONVEYOR_ROLLER_LENGTH
	roller_mesh.radial_segments = 64
	roller_mesh.rings = 4

	# ローラーのベルト巻き取り向きはスクロール方向に追従させる
	# （本編 scroll_sign=+1 → 前 -1 / 後 +1、メニュー scroll_sign=-1 → 前 +1 / 後 -1）
	_conveyor_roller_front_material = _make_roller_material(-_scroll_sign)
	_conveyor_roller_front = _make_roller(roller_mesh, _conveyor_roller_front_material)
	_conveyor_roller_front.name = "ConveyorRollerFront"
	_add_generated_stage_child(_conveyor_roller_front)

	if _include_back_roller:
		_conveyor_roller_back_material = _make_roller_material(_scroll_sign)
		_conveyor_roller_back = _make_roller(roller_mesh, _conveyor_roller_back_material)
		_conveyor_roller_back.name = "ConveyorRollerBack"
		_add_generated_stage_child(_conveyor_roller_back)

	var return_mesh := BoxMesh.new()
	return_mesh.size = Vector3(StageConstants.CONVEYOR_ROLLER_LENGTH, StageConstants.CONVEYOR_RETURN_BELT_THICKNESS, 8.0)
	_conveyor_return_belt = MeshInstance3D.new()
	_conveyor_return_belt.name = "ConveyorReturnBelt"
	_conveyor_return_belt.mesh = return_mesh
	_conveyor_return_material = ShaderMaterial.new()
	_conveyor_return_material.shader = CONVEYOR_FLOOR_SHADER
	_conveyor_return_material.set_shader_parameter("scroll_z", 0.0)
	_conveyor_return_material.set_shader_parameter("scroll_sign", _return_scroll_sign)
	_conveyor_return_material.set_shader_parameter("base_color", StageConstants.CONVEYOR_BELT_BASE_COLOR)
	_conveyor_return_material.set_shader_parameter("stripe_color", StageConstants.CONVEYOR_BELT_STRIPE_COLOR)
	_conveyor_return_material.set_shader_parameter("side_color", StageConstants.CONVEYOR_BELT_SIDE_COLOR)
	_conveyor_return_material.set_shader_parameter("rim_inner_x", 12.0)
	_conveyor_return_material.set_shader_parameter("rim_softness", 0.02)
	StageMaterialsScript.belt_detail(_conveyor_return_material, _graphics_quality())
	_conveyor_return_belt.material_override = _conveyor_return_material
	_add_generated_stage_child(_conveyor_return_belt)

	var side_frame_mesh := BoxMesh.new()
	side_frame_mesh.size = Vector3(StageConstants.CONVEYOR_SIDE_FRAME_WIDTH, StageConstants.CONVEYOR_SIDE_FRAME_HEIGHT, _floor_length)
	var side_frame_mat: Material = StageMaterialsScript.side_frame(_graphics_quality())

	_conveyor_side_frame_left = MeshInstance3D.new()
	_conveyor_side_frame_left.name = "ConveyorSideFrameLeft"
	_conveyor_side_frame_left.mesh = side_frame_mesh
	_conveyor_side_frame_left.material_override = side_frame_mat
	_add_generated_stage_child(_conveyor_side_frame_left)

	_conveyor_side_frame_right = MeshInstance3D.new()
	_conveyor_side_frame_right.name = "ConveyorSideFrameRight"
	_conveyor_side_frame_right.mesh = side_frame_mesh
	_conveyor_side_frame_right.material_override = side_frame_mat
	_add_generated_stage_child(_conveyor_side_frame_right)
func _make_roller_material(arc_sign: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CONVEYOR_FLOOR_SHADER
	mat.set_shader_parameter("scroll_z", 0.0)
	mat.set_shader_parameter("scroll_sign", _scroll_sign)
	mat.set_shader_parameter("roller_mode", 1.0)
	mat.set_shader_parameter("roller_radius", StageConstants.CONVEYOR_ROLLER_RADIUS)
	mat.set_shader_parameter("roller_contact_z", 0.0)
	mat.set_shader_parameter("roller_arc_sign", arc_sign)
	mat.set_shader_parameter("base_color", StageConstants.CONVEYOR_BELT_BASE_COLOR)
	mat.set_shader_parameter("stripe_color", StageConstants.CONVEYOR_BELT_STRIPE_COLOR)
	mat.set_shader_parameter("side_color", StageConstants.CONVEYOR_BELT_SIDE_COLOR)
	mat.set_shader_parameter("stripe_scale", 12.0)
	mat.set_shader_parameter("stripe_softness", 0.08)
	mat.set_shader_parameter("groove_strength", 0.12)
	mat.set_shader_parameter("roller_depth", 0.0)
	mat.set_shader_parameter("roughness_val", 0.72)
	mat.set_shader_parameter("metallic_val", 0.16)
	StageMaterialsScript.belt_detail(mat, _graphics_quality())
	return mat


func _make_roller(roller_mesh: CylinderMesh, mat: ShaderMaterial) -> MeshInstance3D:
	var roller := MeshInstance3D.new()
	roller.mesh = roller_mesh
	roller.material_override = mat
	roller.rotation = Vector3(0.0, 0.0, PI * 0.5)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = StageConstants.CONVEYOR_ROLLER_RADIUS
	shape.height = StageConstants.CONVEYOR_ROLLER_LENGTH
	col.shape = shape
	body.add_child(col)
	roller.add_child(body)
	return roller


func _setup_ocean() -> void:
	_ocean_surface = create_ocean_surface()
	_add_generated_stage_child(_ocean_surface)
	_link_ocean_to_weather()


## The day cycle hands the sun direction to the desktop ocean material. The material is
## replaced on every quality change, so the link is renewed with it.
func _link_ocean_to_weather() -> void:
	# In the editor preview the (non-tool) WeatherCycle is only a placeholder instance.
	if weather_cycle == null or Engine.is_editor_hint():
		return
	weather_cycle.ocean_material = (
		_ocean_surface.material_override as ShaderMaterial
		if _ocean_surface != null and is_instance_valid(_ocean_surface)
		else null
	)
	weather_cycle.refresh_ocean_sun()


## Re-applies the quality-dependent surface materials (belt detail textures, side frames,
## rails) after a graphics quality change.
func _apply_surface_material_quality(q: String) -> void:
	for material: ShaderMaterial in [
		_floor_belt_material,
		_conveyor_return_material,
		_conveyor_roller_front_material,
		_conveyor_roller_back_material,
	]:
		if material != null:
			StageMaterialsScript.belt_detail(material, q)
	if _conveyor_side_frame_left != null or _conveyor_side_frame_right != null:
		var frame_material: Material = StageMaterialsScript.side_frame(q)
		for frame: MeshInstance3D in [_conveyor_side_frame_left, _conveyor_side_frame_right]:
			if frame != null:
				frame.material_override = frame_material
	if is_instance_valid(_running_rails) and _running_rails.has_method("apply_graphics_quality"):
		_running_rails.call("apply_graphics_quality", q)


func _setup_harbor_city() -> void:
	var city := HarborCityBackdropScript.new()
	city.name = "HarborCityBackdrop"
	_add_generated_stage_child(city)
	city.build(weather_cycle, _graphics_quality())


func _stand_script() -> GDScript:
	return AiquizStandScript if _stadium_style == STADIUM_AIQUIZ else TerraceStandScript


## Lighthouse, islands, skyline and sailboats; also drives the stadium's night glow.
func _setup_stadium_backdrop(show_scenery: bool = true) -> void:
	_stadium_backdrop = AiquizBackdropScript.new()
	_stadium_backdrop.name = "StadiumBackdrop"
	_add_generated_stage_child(_stadium_backdrop)
	_stadium_backdrop.build(weather_cycle, _graphics_quality(), show_scenery)


func _setup_grandstands() -> void:
	var container := Node3D.new()
	container.name = "Grandstands"
	container.position = Vector3(0.0, 0.0, _floor_center_z - _floor_length * 0.5)
	_grandstands_container = container
	_add_generated_stage_child(container)

	var side_offsets: Array[float] = []
	if _include_left_grandstand:
		side_offsets.append(-_grandstand_side_offset)
	if _include_right_grandstand:
		side_offsets.append(_grandstand_side_offset)
	var density: float = _spectator_density if _include_spectators else 0.0
	for side_x: float in side_offsets:
		var stand: Node3D = _stand_script().new()
		container.add_child(stand)
		stand.setup(signf(side_x), density, 1729 if side_x < 0.0 else 7919)
		stand.position = Vector3(side_x, 0.0, 0.0)
		stand.process_mode = Node.PROCESS_MODE_DISABLED

	_sync_grandstands_to_floor()


func _configure_grandstand_geometry(stand: Node3D) -> void:
	var quality: String = _graphics_quality()
	var casts_shadows: bool = QualityRules.is_at_least(quality, QualityRules.HIGH) and not QualityRules.is_mobile_target()
	for node: Node in stand.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.lod_bias = QualityRules.grandstand_lod_bias(quality)
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if casts_shadows
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _sync_grandstands_to_floor() -> void:
	var container: Node3D = _grandstands_container
	if container == null:
		return
	# スタンドは 20 m のブロックを床の後端から前方へ並べる。床が伸びたらブロックを足し、
	# カウントダウン以降の短い動的床では減らさない（位置が跳ねないようにする）。
	if _grandstand_synced_length > 0.0 and _floor_length < _grandstand_synced_length:
		return
	_grandstand_synced_length = _floor_length
	container.position.z = _floor_center_z - _floor_length * 0.5
	var blocks: int = _stand_script().blocks_for_length(_floor_length)
	for child: Node in container.get_children():
		if child.has_method("ensure_blocks") and child.ensure_blocks(blocks):
			_configure_grandstand_geometry(child as Node3D)
	if is_instance_valid(_waterfront) and _stadium_style == STADIUM_SANTORINI:
		# Routes are keyed on the stand layout, so an unchanged stand is a no-op.
		_waterfront.sync_to_stands(container)


func _setup_sharks() -> void:
	var school: Node3D = Node3D.new()
	school.name = "OceanSharks"
	_shark_school = school
	_add_generated_stage_child(school)

	var centers: Array[Vector3]
	var radii: Array[Vector2]
	var speeds: Array[float]
	var phases: Array[float]
	var scales: Array[float]

	# 回遊の Z 端をコンベア前後端に合わせる（手前側のローラー端まで届くようにする）。
	var half_len: float = _floor_length * 0.5
	var orbit_center_z: float = _floor_center_z
	var orbit_z_radius: float = half_len

	if _is_preview_environment:
		# 奥側から画面手前まで、床の左側をコンベア端まで大きく往復するメニュー用回遊ルート。
		centers = [
			Vector3(-17.0, StageConstants.OCEAN_SURFACE_Y + 0.55, orbit_center_z),
		]
		radii = [
			Vector2(2.0, orbit_z_radius),
		]
		speeds = [0.09]
		phases = [0.25]
		scales = [1.45]
	else:
		centers = [
			Vector3(-18.0, StageConstants.OCEAN_SURFACE_Y - 0.42, orbit_center_z),
			Vector3(18.0, StageConstants.OCEAN_SURFACE_Y - 0.42, orbit_center_z),
		]
		radii = [
			Vector2(2.3, orbit_z_radius),
			Vector2(2.3, orbit_z_radius),
		]
		speeds = [0.24, 0.22]
		phases = [0.0, PI]
		scales = [1.25, 1.18]

	for index: int in range(centers.size()):
		var shark: SharkSwimmerScript = SHARK_SWIMMER_SCENE.instantiate() as SharkSwimmerScript
		if shark == null:
			push_warning("Failed to instantiate ocean shark %d" % (index + 1))
			continue
		shark.name = (
			"PreviewShark_%02d" % (index + 1)
			if _is_preview_environment
			else "AmbientShark_%02d" % (index + 1)
		)
		shark.position = centers[index]
		shark.orbit_radius = radii[index]
		shark.swim_speed = speeds[index]
		shark.phase = phases[index]
		shark.animation_speed = 0.92 + float(index) * 0.08
		shark.model_scale = scales[index]
		shark.ocean_surface = _ocean_surface
		shark.bite_distance = maxf(shark.bite_distance, shark.model_scale * 4.0)
		school.add_child(shark)


func get_ocean_sharks() -> Array[SharkSwimmerScript]:
	var sharks: Array[SharkSwimmerScript] = []
	var school: Node3D = _shark_school
	if school == null:
		return sharks
	for child: Node in school.get_children():
		var shark: SharkSwimmerScript = child as SharkSwimmerScript
		if shark != null:
			sharks.append(shark)
	return sharks


func get_grandstand_count() -> int:
	return _grandstands_container.get_child_count() if _grandstands_container != null else 0


func has_ocean_surface() -> bool:
	return _ocean_surface != null and is_instance_valid(_ocean_surface)


func get_floor_center_z() -> float:
	return _floor_center_z


func get_floor_length() -> float:
	return _floor_length


## A round hole in the surface stage for the sudden death shaft: floor, ocean (both shader variants) and every
## stage piece that would show inside the cylinder (centre.xz, radius) below the floor top are cut away or hidden.
## While the hole is open, the pier box (floor), conveyor return belt, rollers and ocean run a variant of their
## shader compiled with SHAFT_HOLE that discards fragments inside the circle (all faces, so the pier's inside never
## shows; the shaft wall does). Other stage meshes that sit wholly below the floor top and whose triangles reach
## into the circle (the seabed) are hidden. Inactive, every material is back on its original shader with no hole
## parameter and nothing is hidden: the stage renders exactly as before, at no extra cost.
func set_shaft_hole(center: Vector3, radius: float, active: bool) -> void:
	_shaft_hole_center = center
	_shaft_hole_radius = maxf(radius, 0.0)
	_shaft_hole_active = active and _shaft_hole_radius > 0.0
	_apply_shaft_hole()


## Optional: compiles the SHAFT_HOLE shader variants ahead of set_shaft_hole() (e.g. when the draw is detected),
## so opening the hole does not stall on shader compilation.
func prepare_shaft_hole() -> void:
	for entry: Array in _shaft_hole_material_entries():
		var variant: Shader = _shaft_hole_variant(_shaft_hole_base_shader(entry[1] as ShaderMaterial))
		# Waits for the rendering server to parse and compile it now rather than when the hole opens.
		variant.get_shader_uniform_list()


func get_shaft_hole_debug() -> Dictionary:
	var materials: Array[Dictionary] = []
	for entry: Array in _shaft_hole_material_entries():
		var material := entry[1] as ShaderMaterial
		materials.append({
			"name": String(entry[0]),
			"variant": material.has_meta(SHAFT_BASE_SHADER_META),
			"shader": String(_shaft_hole_base_shader(material).resource_path),
			"value": material.get_shader_parameter(SHAFT_HOLE_PARAM),
		})
	var hidden: Array[String] = []
	for node: GeometryInstance3D in _shaft_hidden_nodes:
		if is_instance_valid(node):
			hidden.append(String(get_path_to(node)))
	return {
		"active": _shaft_hole_active,
		"center": _shaft_hole_center,
		"radius": _shaft_hole_radius,
		"floor_top_y": StageConstants.FLOOR_TOP_Y,
		"cut_materials": materials,
		"hidden": hidden,
		"crossing": _shaft_crossing_nodes.duplicate(),
	}


## [label, ShaderMaterial] for every material that cuts the hole in its fragment shader.
func _shaft_hole_material_entries() -> Array[Array]:
	var entries: Array[Array] = []
	var candidates: Array = [
		["floor", _floor_belt_material],
		["return_belt", _conveyor_return_material],
		["roller_front", _conveyor_roller_front_material],
		["roller_back", _conveyor_roller_back_material],
	]
	if has_ocean_surface():
		candidates.append(["ocean", _ocean_surface.material_override])
	for candidate: Array in candidates:
		var material := candidate[1] as ShaderMaterial
		if material != null and material.shader != null:
			entries.append([candidate[0], material])
	return entries


static func _shaft_hole_base_shader(material: ShaderMaterial) -> Shader:
	if material.has_meta(SHAFT_BASE_SHADER_META):
		return material.get_meta(SHAFT_BASE_SHADER_META) as Shader
	return material.shader


## The same shader compiled with SHAFT_HOLE defined (one per base shader, shared by all stages).
static func _shaft_hole_variant(base: Shader) -> Shader:
	if _shaft_hole_variants.has(base):
		return _shaft_hole_variants[base] as Shader
	var variant := Shader.new()
	variant.code = base.code.replace("shader_type spatial;", "shader_type spatial;
#define SHAFT_HOLE")
	_shaft_hole_variants[base] = variant
	return variant


func _apply_shaft_hole() -> void:
	_apply_shaft_hole_materials()
	_restore_shaft_hidden()
	if _shaft_hole_active:
		_hide_shaft_pieces()


## Swaps each cutting material onto its SHAFT_HOLE variant (active) or back to the original shader with the
## hole parameter removed (inactive). Shader swaps keep the materials' other parameters.
func _apply_shaft_hole_materials() -> void:
	var value := Vector4(_shaft_hole_center.x, _shaft_hole_center.z, _shaft_hole_radius, 1.0)
	for entry: Array in _shaft_hole_material_entries():
		var material := entry[1] as ShaderMaterial
		if _shaft_hole_active:
			if not material.has_meta(SHAFT_BASE_SHADER_META):
				var base: Shader = material.shader
				material.set_meta(SHAFT_BASE_SHADER_META, base)
				material.shader = _shaft_hole_variant(base)
			material.set_shader_parameter(SHAFT_HOLE_PARAM, value)
		elif material.has_meta(SHAFT_BASE_SHADER_META):
			material.shader = material.get_meta(SHAFT_BASE_SHADER_META) as Shader
			material.remove_meta(SHAFT_BASE_SHADER_META)
			material.set_shader_parameter(SHAFT_HOLE_PARAM, null)


func _restore_shaft_hidden() -> void:
	for node: GeometryInstance3D in _shaft_hidden_nodes:
		if is_instance_valid(node):
			node.visible = true
	_shaft_hidden_nodes.clear()
	_shaft_crossing_nodes.clear()


## Hides the stage meshes that reach into the shaft cylinder but lie wholly below the floor top: they are only
## ever seen through the water from above (the seabed, 120 m down), so hiding them changes nothing up there.
## Meshes that also rise above the floor are left alone and listed in the debug snapshot.
func _hide_shaft_pieces() -> void:
	var cut_nodes: Array[Node] = [floor_mesh, _ocean_surface, _conveyor_return_belt,
		_conveyor_roller_front, _conveyor_roller_back]
	var top_y: float = StageConstants.FLOOR_TOP_Y
	var center := Vector2(_shaft_hole_center.x, _shaft_hole_center.z)
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry in cut_nodes or not geometry.is_visible_in_tree():
			continue
		var bounds: AABB = geometry.global_transform * geometry.get_aabb()
		if bounds.position.y >= top_y or not _aabb_reaches_disc(bounds, center, _shaft_hole_radius):
			continue
		# A big bounding box is not enough: the far-sea backdrop is a ring 1.8 km out whose box covers
		# everything. Check the triangles themselves.
		var mesh_instance := geometry as MeshInstance3D
		if mesh_instance != null and not _mesh_reaches_disc(mesh_instance, center, _shaft_hole_radius):
			continue
		if bounds.end.y <= top_y + 0.02:
			geometry.visible = false
			_shaft_hidden_nodes.append(geometry)
		else:
			_shaft_crossing_nodes.append(String(get_path_to(geometry)))


static func _aabb_reaches_disc(bounds: AABB, center: Vector2, radius: float) -> bool:
	var nearest := Vector2(
		clampf(center.x, bounds.position.x, bounds.end.x),
		clampf(center.y, bounds.position.z, bounds.end.z)
	)
	return nearest.distance_squared_to(center) < radius * radius


## True when any triangle of the mesh overlaps the disc in plan view (very dense meshes count as overlapping).
static func _mesh_reaches_disc(mesh_instance: MeshInstance3D, center: Vector2, radius: float) -> bool:
	if mesh_instance.mesh == null:
		return false
	var faces: PackedVector3Array = mesh_instance.mesh.get_faces()
	if faces.size() > 150000:
		return true
	var xform: Transform3D = mesh_instance.global_transform
	var radius_sq: float = radius * radius
	for i in range(0, faces.size() - 2, 3):
		var a3: Vector3 = xform * faces[i]
		var b3: Vector3 = xform * faces[i + 1]
		var c3: Vector3 = xform * faces[i + 2]
		var a := Vector2(a3.x, a3.z)
		var b := Vector2(b3.x, b3.z)
		var c := Vector2(c3.x, c3.z)
		var d1: float = (b - a).cross(center - a)
		var d2: float = (c - b).cross(center - b)
		var d3: float = (a - c).cross(center - c)
		var has_negative: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
		var has_positive: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
		if not (has_negative and has_positive):
			return true
		for edge: Array in [[a, b], [b, c], [c, a]]:
			var p: Vector2 = edge[0]
			var q: Vector2 = edge[1]
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(center, p, q)
			if closest.distance_squared_to(center) < radius_sq:
				return true
	return false


static func create_ocean_surface() -> MeshInstance3D:
	var ocean_mesh := MeshInstance3D.new()
	ocean_mesh.name = "Ocean"
	configure_ocean_surface(ocean_mesh, _graphics_quality())
	return ocean_mesh


static func configure_ocean_surface(ocean_mesh: MeshInstance3D, quality: String = "") -> void:
	if ocean_mesh == null:
		return
	var q: String = QualityRules.normalize(quality) if not quality.is_empty() else _graphics_quality()
	ocean_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var plane := ocean_mesh.mesh as PlaneMesh
	if plane == null:
		plane = PlaneMesh.new()
		ocean_mesh.mesh = plane
	plane.size = StageConstants.OCEAN_SIZE
	var subdivisions: int = QualityRules.ocean_subdivisions(q)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	ocean_mesh.position = Vector3(0.0, StageConstants.OCEAN_SURFACE_Y, StageConstants.OCEAN_CENTER_Z)
	var ocean_half_size: Vector2 = StageConstants.OCEAN_SIZE * 0.5
	ocean_mesh.custom_aabb = AABB(
		Vector3(-ocean_half_size.x, -3.0, -ocean_half_size.y),
		Vector3(StageConstants.OCEAN_SIZE.x, 6.0, StageConstants.OCEAN_SIZE.y)
	)

	var mat := ShaderMaterial.new()
	var use_lightweight_shader: bool = QualityRules.uses_lightweight_ocean(q)
	mat.shader = MOBILE_OCEAN_SHADER if use_lightweight_shader else StageConstants.OCEAN_SHADER

	if not use_lightweight_shader:
		var noise_size: int = QualityRules.ocean_noise_texture_size(q)
		var noise1 := NoiseTexture2D.new()
		var fnl1 := FastNoiseLite.new()
		fnl1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fnl1.frequency = 0.01
		fnl1.fractal_octaves = 4
		fnl1.fractal_lacunarity = 2.0
		fnl1.fractal_gain = 0.5
		noise1.noise = fnl1
		noise1.seamless = true
		noise1.width = noise_size
		noise1.height = noise_size
		mat.set_shader_parameter("noise_tex", noise1)

		var noise2 := NoiseTexture2D.new()
		var fnl2 := FastNoiseLite.new()
		fnl2.noise_type = FastNoiseLite.TYPE_CELLULAR
		fnl2.frequency = 0.015
		fnl2.fractal_octaves = 3
		fnl2.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		fnl2.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		noise2.noise = fnl2
		noise2.seamless = true
		noise2.width = noise_size
		noise2.height = noise_size
		mat.set_shader_parameter("noise_tex2", noise2)
		OceanDetailScript.configure(mat, q)

	ocean_mesh.material_override = mat


## 床ボックスのサイズ・位置と、それに追従するレール／ローラー／サイドフレームを更新する。
func set_floor_geometry(center_z: float, length: float) -> void:
	_floor_center_z = center_z
	_floor_length = length
	_sync_grandstands_to_floor()
	if not floor_mesh:
		return
	var box: BoxMesh = floor_mesh.mesh as BoxMesh
	if box:
		box.size = Vector3(StageConstants.FLOOR_WIDTH, StageConstants.FLOOR_THICKNESS, length)
	floor_mesh.position = Vector3(0, StageConstants.FLOOR_CENTER_Y, center_z)
	if _floor_collision_body:
		var col := _floor_collision_body.get_child(0) as CollisionShape3D
		if col and col.shape is BoxShape3D:
			(col.shape as BoxShape3D).size = Vector3(StageConstants.FLOOR_WIDTH, 0.5, length)
	_update_floor_rails()
	_update_conveyor_loop_geometry()


func _update_floor_rails() -> void:
	if is_instance_valid(_running_rails):
		_running_rails.set_geometry(_floor_center_z, _floor_length, StageConstants.FLOOR_TOP_Y)


func _update_conveyor_loop_geometry() -> void:
	var half_len: float = _floor_length * 0.5
	var front_z: float = _floor_center_z + half_len
	var back_z: float = _floor_center_z - half_len
	var top_front_contact_z: float = front_z
	var top_back_contact_z: float = back_z
	var roller_center_y: float = StageConstants.FLOOR_TOP_Y - StageConstants.CONVEYOR_ROLLER_RADIUS

	if _conveyor_roller_front:
		_conveyor_roller_front.position = Vector3(0.0, roller_center_y, front_z)
		if _conveyor_roller_front_material:
			_conveyor_roller_front_material.set_shader_parameter("roller_contact_z", top_front_contact_z)
	if _conveyor_roller_back:
		_conveyor_roller_back.position = Vector3(0.0, roller_center_y, back_z)
		if _conveyor_roller_back_material:
			_conveyor_roller_back_material.set_shader_parameter("roller_contact_z", top_back_contact_z)

	if _conveyor_return_belt:
		var return_len: float = maxf(0.2, _floor_length - 0.12)
		var return_mesh: BoxMesh = _conveyor_return_belt.mesh as BoxMesh
		if return_mesh:
			return_mesh.size = Vector3(StageConstants.CONVEYOR_ROLLER_LENGTH, StageConstants.CONVEYOR_RETURN_BELT_THICKNESS, return_len)
		var return_y: float = roller_center_y - StageConstants.CONVEYOR_ROLLER_RADIUS - StageConstants.CONVEYOR_RETURN_BELT_GAP - StageConstants.CONVEYOR_RETURN_BELT_THICKNESS * 0.5
		_conveyor_return_belt.position = Vector3(0.0, return_y, _floor_center_z)

	var frame_len: float = _floor_length + StageConstants.CONVEYOR_SIDE_FRAME_OVERHANG * 2.0
	var frame_center_y: float = StageConstants.FLOOR_TOP_Y + StageConstants.CONVEYOR_SIDE_FRAME_TOP_CLEARANCE - StageConstants.CONVEYOR_SIDE_FRAME_HEIGHT * 0.5
	var frame_x: float = StageConstants.FLOOR_HALF_WIDTH - StageConstants.CONVEYOR_SIDE_FRAME_WIDTH * 0.5
	if _conveyor_side_frame_left:
		var fl := _conveyor_side_frame_left.mesh as BoxMesh
		if fl:
			fl.size = Vector3(StageConstants.CONVEYOR_SIDE_FRAME_WIDTH, StageConstants.CONVEYOR_SIDE_FRAME_HEIGHT, frame_len)
		_conveyor_side_frame_left.position = Vector3(-frame_x, frame_center_y, _floor_center_z)
	if _conveyor_side_frame_right:
		var fr := _conveyor_side_frame_right.mesh as BoxMesh
		if fr:
			fr.size = Vector3(StageConstants.CONVEYOR_SIDE_FRAME_WIDTH, StageConstants.CONVEYOR_SIDE_FRAME_HEIGHT, frame_len)
		_conveyor_side_frame_right.position = Vector3(frame_x, frame_center_y, _floor_center_z)


## ベルトのスクロール量（world_scroll_z 相当）を反映する。
func set_scroll_z(z: float) -> void:
	if _floor_belt_material:
		_floor_belt_material.set_shader_parameter("scroll_z", z)
	if _conveyor_roller_front_material:
		_conveyor_roller_front_material.set_shader_parameter("scroll_z", z)
	if _conveyor_roller_back_material:
		_conveyor_roller_back_material.set_shader_parameter("scroll_z", z)
	if _conveyor_return_material:
		_conveyor_return_material.set_shader_parameter("scroll_z", z)


func reset_scroll() -> void:
	set_scroll_z(0.0)


func apply_menu_config() -> void:
	_scroll_sign = -1.0
	_return_scroll_sign = 1.0
	_apply_scroll_signs()
	set_floor_geometry(StageConstants.GAME_FLOOR_CENTER_Z, StageConstants.GAME_FLOOR_LENGTH)


func apply_game_config() -> void:
	_scroll_sign = 1.0
	_return_scroll_sign = -1.0
	_apply_scroll_signs()
	set_floor_geometry(StageConstants.GAME_FLOOR_CENTER_Z, StageConstants.GAME_FLOOR_LENGTH)


func _apply_scroll_signs() -> void:
	if _floor_belt_material:
		_floor_belt_material.set_shader_parameter("scroll_sign", _scroll_sign)
	if _conveyor_return_material:
		_conveyor_return_material.set_shader_parameter("scroll_sign", _return_scroll_sign)
	if _conveyor_roller_front_material:
		_conveyor_roller_front_material.set_shader_parameter("scroll_sign", _scroll_sign)
		_conveyor_roller_front_material.set_shader_parameter("roller_arc_sign", -_scroll_sign)
	if _conveyor_roller_back_material:
		_conveyor_roller_back_material.set_shader_parameter("scroll_sign", _scroll_sign)
		_conveyor_roller_back_material.set_shader_parameter("roller_arc_sign", _scroll_sign)
