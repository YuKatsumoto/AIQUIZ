class_name StageEnvironment
extends Node3D

## メニュープレビューと本編ゲームで共有するステージの「器」。
## 環境・照明・床・コンベアベルト・ローラー・レール・サイドフレーム・海を構築し、
## 床ジオメトリとベルトスクロールの更新 API を公開する。
##
## 壁・プレイヤー・演出は各レイヤー（MenuPreviewLayer / GamePlayLayer）が別に持つ。

const CONVEYOR_FLOOR_SHADER: Shader = preload("res://shaders/conveyor_belt_floor.gdshader")
const MOBILE_OCEAN_SHADER: Shader = preload("res://shaders/ocean_mobile.gdshader")
const SHARK_SWIMMER_SCENE: PackedScene = preload("res://scenes/shark_swimmer.tscn")
const GRANDSTAND_SCENE: PackedScene = preload(
	"res://assets/environment/grandstand/aiquiz_ocean_grandstand_optimized.glb"
)
const SharkSwimmerScript = preload("res://scripts/world/shark_swimmer.gd")
const WeatherCycleScript = preload("res://scripts/world/weather_cycle.gd")
const ConveyorEdgeLightsScript = preload("res://scripts/world/conveyor_edge_lights.gd")
const AIQUIZ_STAGE_SKY_PATH := "res://assets/environment/sky/aiquiz_day_night_sky.tres"
const GRANDSTAND_BASE_LENGTH: float = 160.0
const GRANDSTAND_SIDE_OFFSET: float = 32.0

# --- 構成オプション ---
var _scroll_sign: float = 1.0
var _return_scroll_sign: float = -1.0
var _include_back_roller: bool = true
var _include_floor_collision: bool = true
var _is_preview_environment: bool = false
var _include_sharks: bool = false
var _include_grandstands: bool = false

# --- ノード参照 ---
var floor_mesh: MeshInstance3D = null
var environment_node: WorldEnvironment = null
var directional_light: DirectionalLight3D = null
var weather_cycle: WeatherCycle = null
var conveyor_edge_lights: ConveyorEdgeLights = null

var _floor_belt_material: ShaderMaterial = null
var _floor_collision_body: StaticBody3D = null
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

var _floor_center_z: float = 0.0
var _floor_length: float = 144.0
## 観客スタンドが最後に同期した床長。動的床の縮小では縮めない。
var _grandstand_synced_length: float = 0.0


## ステージを構築する。
## config キー: floor_center_z, floor_length, scroll_sign, return_scroll_sign,
##              include_back_roller, include_floor_collision,
##              is_preview, include_sharks, include_grandstands
func build(config: Dictionary = {}) -> void:
	_floor_center_z = float(config.get("floor_center_z", 0.0))
	_floor_length = float(config.get("floor_length", 144.0))
	_scroll_sign = float(config.get("scroll_sign", 1.0))
	_return_scroll_sign = float(config.get("return_scroll_sign", -1.0))
	_include_back_roller = bool(config.get("include_back_roller", true))
	_include_floor_collision = bool(config.get("include_floor_collision", true))
	_is_preview_environment = bool(config.get("is_preview", false))
	_include_sharks = bool(config.get("include_sharks", false))
	_include_grandstands = bool(config.get("include_grandstands", false))

	_setup_environment()
	_setup_lighting()
	_setup_weather_cycle()
	_setup_floor()
	_setup_floor_conveyor()
	_setup_conveyor_edge_lights()
	_setup_ocean()
	if _include_grandstands:
		_setup_grandstands()
	if _include_sharks:
		_setup_sharks()

	set_floor_geometry(_floor_center_z, _floor_length)


static func _graphics_quality() -> String:
	var raw: Variant = GameManager.get("graphics_quality")
	if typeof(raw) != TYPE_STRING or String(raw).is_empty():
		return GraphicsQuality.BALANCED
	return GraphicsQuality.normalize(String(raw))


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
	GraphicsQuality.apply_environment(env, _graphics_quality())

	environment_node = WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	environment_node.environment = env
	add_child(environment_node)


func _setup_lighting() -> void:
	directional_light = DirectionalLight3D.new()
	directional_light.name = "DirectionalLight3D"
	directional_light.rotation_degrees = Vector3(-50, -20, 0)
	directional_light.light_color = Color(0.90, 0.92, 0.95)
	directional_light.light_energy = 1.2
	directional_light.shadow_enabled = (
		GraphicsQuality.preview_shadow_enabled(_graphics_quality())
		if _is_preview_environment
		else GraphicsQuality.gameplay_shadow_enabled(_graphics_quality())
	)
	add_child(directional_light)


func _setup_weather_cycle() -> void:
	var env: Environment = null
	if environment_node != null:
		env = environment_node.environment
	weather_cycle = attach_weather_cycle(self, env, directional_light)


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
	add_child(floor_mesh)


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
	floor_mesh.material_override = _floor_belt_material
	_setup_floor_rails()
	_setup_conveyor_loop_geometry()
	if _include_floor_collision:
		_setup_floor_collision()


func _setup_conveyor_edge_lights() -> void:
	conveyor_edge_lights = ConveyorEdgeLightsScript.new() as ConveyorEdgeLights
	conveyor_edge_lights.name = "ConveyorEdgeLights"
	add_child(conveyor_edge_lights)
	conveyor_edge_lights.setup(
		_floor_center_z,
		_floor_length,
		_floor_belt_material,
		weather_cycle
	)


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
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(StageConstants.FLOOR_RAIL_WIDTH, StageConstants.FLOOR_RAIL_HEIGHT, _floor_length)
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.27, 0.275, 0.28)
	rail_mat.roughness = 0.66
	rail_mat.metallic = 0.22

	_floor_rail_left = MeshInstance3D.new()
	_floor_rail_left.mesh = rail_mesh
	_floor_rail_left.material_override = rail_mat
	add_child(_floor_rail_left)

	_floor_rail_right = MeshInstance3D.new()
	_floor_rail_right.mesh = rail_mesh
	_floor_rail_right.material_override = rail_mat
	add_child(_floor_rail_right)


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
	add_child(_conveyor_roller_front)

	if _include_back_roller:
		_conveyor_roller_back_material = _make_roller_material(_scroll_sign)
		_conveyor_roller_back = _make_roller(roller_mesh, _conveyor_roller_back_material)
		add_child(_conveyor_roller_back)

	var return_mesh := BoxMesh.new()
	return_mesh.size = Vector3(StageConstants.CONVEYOR_ROLLER_LENGTH, StageConstants.CONVEYOR_RETURN_BELT_THICKNESS, 8.0)
	_conveyor_return_belt = MeshInstance3D.new()
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
	_conveyor_return_belt.material_override = _conveyor_return_material
	add_child(_conveyor_return_belt)

	var side_frame_mesh := BoxMesh.new()
	side_frame_mesh.size = Vector3(StageConstants.CONVEYOR_SIDE_FRAME_WIDTH, StageConstants.CONVEYOR_SIDE_FRAME_HEIGHT, _floor_length)
	var side_frame_mat := StandardMaterial3D.new()
	side_frame_mat.albedo_color = Color(0.30, 0.31, 0.33)
	side_frame_mat.roughness = 0.62
	side_frame_mat.metallic = 0.16

	_conveyor_side_frame_left = MeshInstance3D.new()
	_conveyor_side_frame_left.mesh = side_frame_mesh
	_conveyor_side_frame_left.material_override = side_frame_mat
	add_child(_conveyor_side_frame_left)

	_conveyor_side_frame_right = MeshInstance3D.new()
	_conveyor_side_frame_right.mesh = side_frame_mesh
	_conveyor_side_frame_right.material_override = side_frame_mat
	add_child(_conveyor_side_frame_right)


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
	add_child(create_ocean_surface())


func _setup_grandstands() -> void:
	var container := Node3D.new()
	container.name = "Grandstands"
	container.position = Vector3(0.0, 0.0, _floor_center_z)
	add_child(container)

	var side_offsets: Array[float] = [-GRANDSTAND_SIDE_OFFSET, GRANDSTAND_SIDE_OFFSET]
	for side_x: float in side_offsets:
		var stand := GRANDSTAND_SCENE.instantiate() as Node3D
		if stand == null:
			push_warning("Failed to instantiate optimized ocean grandstand")
			continue
		stand.name = "GrandstandLeft" if side_x < 0.0 else "GrandstandRight"
		stand.position = Vector3(side_x, 0.0, 0.0)
		if side_x < 0.0:
			stand.rotation = Vector3(0.0, PI, 0.0)
		stand.process_mode = Node.PROCESS_MODE_DISABLED
		_configure_grandstand_geometry(stand)
		container.add_child(stand)

	_sync_grandstands_to_floor()


func _configure_grandstand_geometry(stand: Node3D) -> void:
	var quality: String = _graphics_quality()
	var casts_shadows: bool = quality == GraphicsQuality.HIGH and not GraphicsQuality.is_mobile_target()
	for node: Node in stand.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.lod_bias = GraphicsQuality.grandstand_lod_bias(quality)
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if casts_shadows
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _sync_grandstands_to_floor() -> void:
	var container := get_node_or_null("Grandstands") as Node3D
	if container == null:
		return
	# フライオーバー等で伸ばしたスタンドを、カウントダウン以降の短い動的床に合わせて
	# 縮め直すと位置・スケールが跳ねるので、同期済み長さより短い更新は無視する。
	if _grandstand_synced_length > 0.0 and _floor_length < _grandstand_synced_length:
		return
	_grandstand_synced_length = _floor_length
	container.position.z = _floor_center_z
	var longitudinal_scale := maxf(_floor_length / GRANDSTAND_BASE_LENGTH, 0.01)
	for child: Node in container.get_children():
		var stand := child as Node3D
		if stand != null:
			stand.scale = Vector3(1.0, 1.0, longitudinal_scale)


func _setup_sharks() -> void:
	var school: Node3D = Node3D.new()
	school.name = "OceanSharks"
	add_child(school)

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
		shark.bite_distance = maxf(shark.bite_distance, shark.model_scale * 4.0)
		school.add_child(shark)


func get_ocean_sharks() -> Array[SharkSwimmerScript]:
	var sharks: Array[SharkSwimmerScript] = []
	var school: Node3D = get_node_or_null("OceanSharks") as Node3D
	if school == null:
		return sharks
	for child: Node in school.get_children():
		var shark: SharkSwimmerScript = child as SharkSwimmerScript
		if shark != null:
			sharks.append(shark)
	return sharks


func get_floor_center_z() -> float:
	return _floor_center_z


func get_floor_length() -> float:
	return _floor_length


static func create_ocean_surface() -> MeshInstance3D:
	var ocean_mesh := MeshInstance3D.new()
	ocean_mesh.name = "Ocean"
	ocean_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var plane := PlaneMesh.new()
	plane.size = StageConstants.OCEAN_SIZE
	var subdivisions: int = GraphicsQuality.ocean_subdivisions(_graphics_quality())
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	ocean_mesh.mesh = plane
	ocean_mesh.position = Vector3(0.0, StageConstants.OCEAN_SURFACE_Y, StageConstants.OCEAN_CENTER_Z)
	var ocean_half_size: Vector2 = StageConstants.OCEAN_SIZE * 0.5
	ocean_mesh.custom_aabb = AABB(
		Vector3(-ocean_half_size.x, -3.0, -ocean_half_size.y),
		Vector3(StageConstants.OCEAN_SIZE.x, 6.0, StageConstants.OCEAN_SIZE.y)
	)

	var mat := ShaderMaterial.new()
	var use_lightweight_shader: bool = GraphicsQuality.uses_lightweight_ocean(
		_graphics_quality()
	)
	mat.shader = MOBILE_OCEAN_SHADER if use_lightweight_shader else StageConstants.OCEAN_SHADER

	if not use_lightweight_shader:
		var noise_size: int = GraphicsQuality.ocean_noise_texture_size(
			_graphics_quality()
		)
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

	ocean_mesh.material_override = mat
	return ocean_mesh


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
	if conveyor_edge_lights != null:
		conveyor_edge_lights.set_geometry(_floor_center_z, _floor_length)


func _update_floor_rails() -> void:
	if not _floor_rail_left or not _floor_rail_right:
		return
	var rail_l := _floor_rail_left.mesh as BoxMesh
	var rail_r := _floor_rail_right.mesh as BoxMesh
	if rail_l:
		rail_l.size = Vector3(StageConstants.FLOOR_RAIL_WIDTH, StageConstants.FLOOR_RAIL_HEIGHT, _floor_length)
	if rail_r:
		rail_r.size = Vector3(StageConstants.FLOOR_RAIL_WIDTH, StageConstants.FLOOR_RAIL_HEIGHT, _floor_length)
	var rail_y: float = StageConstants.FLOOR_TOP_Y + StageConstants.FLOOR_RAIL_HEIGHT * 0.5
	var rail_x: float = StageConstants.FLOOR_HALF_WIDTH - StageConstants.FLOOR_RAIL_WIDTH * 0.5 - StageConstants.FLOOR_RAIL_INSET
	_floor_rail_left.position = Vector3(-rail_x, rail_y, _floor_center_z)
	_floor_rail_right.position = Vector3(rail_x, rail_y, _floor_center_z)


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
