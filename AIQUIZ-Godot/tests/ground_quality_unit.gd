extends Node

## Surface stage quality (no gameplay): the belt detail textures follow the graphics tier and keep
## the belt colour, the shaders keep what the sudden death shaft hole and the settings previews
## depend on, the stage atmosphere (fog, grade, probe, vignette) comes and goes with the tier, the
## ocean and the stand paint step down to the old look on low, and the quiz walls keep their
## colour and their object-space mapping.
## Run: Godot --headless --path . --script tests/ground_quality_bootstrap.gd
## (The look itself is checked with tests/ground_look_bootstrap.gd, in a window.)

const StageMaterialsScript = preload("res://scripts/world/stage_materials.gd")
const StageAtmosphereScript = preload("res://scripts/world/stage_atmosphere.gd")
const OceanDetailScript = preload("res://scripts/world/ocean_detail.gd")
const WallMaterialsScript = preload("res://scripts/world/wall_materials.gd")
const StandMaterialsScript = preload("res://scripts/world/aiquiz_stadium/aiquiz_stadium_materials.gd")
const BELT_SHADER: Shader = preload("res://shaders/conveyor_belt_floor.gdshader")
const OCEAN_SHADER: Shader = preload("res://shaders/ocean.gdshader")
const STAND_SHADER: Shader = preload("res://shaders/aiquiz_stand_surface.gdshader")
const STEEL_SHADER: Shader = preload("res://shaders/ground_steel.gdshader")

const TIERS: Array[String] = ["low", "balanced", "high", "ultra"]
## The belt shader's uniforms that StageEnvironment, the menu preview and the settings screens
## write by name (a rename would silently break the belt colour or the scroll).
const BELT_EXTERNAL_UNIFORMS: Array[String] = [
	"scroll_z", "scroll_sign", "roller_mode", "roller_radius", "roller_contact_z", "roller_arc_sign",
	"belt_scale", "stripe_scale", "stripe_softness", "groove_strength", "base_color", "stripe_color",
	"side_color", "rim_color", "rim_inner_x", "rim_outer_x", "rim_softness", "rim_lip_width",
	"roller_freq", "roller_sharpness", "roller_depth", "roughness_val", "metallic_val",
	"rim_metallic_boost",
]

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	_check_textures()
	_check_shader_contracts()
	_check_belt_detail()
	_check_steel()
	_check_atmosphere_environment()
	await _check_atmosphere_nodes()
	await _check_weather_cycle()
	_check_ocean_detail()
	_check_wall_materials()
	_check_stand_paint()
	print("GROUND_QUALITY_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_textures() -> void:
	var expected := {
		"res://assets/environment/conveyor_stage/textures/belt_detail_albedo.png": Vector2i(1024, 1024),
		"res://assets/environment/conveyor_stage/textures/belt_detail_normal.png": Vector2i(1024, 1024),
		"res://assets/environment/conveyor_stage/textures/belt_detail_orm.png": Vector2i(1024, 1024),
		"res://assets/environment/conveyor_stage/textures/wall_panel_albedo.png": Vector2i(3072, 1536),
		"res://assets/environment/conveyor_stage/textures/wall_panel_normal.png": Vector2i(3072, 1536),
		"res://assets/environment/conveyor_stage/textures/wall_panel_orm.png": Vector2i(3072, 1536),
	}
	for path: String in expected:
		var texture := load(path) as Texture2D
		check(texture != null, "%s loads" % path.get_file())
		if texture != null:
			check(Vector2i(texture.get_width(), texture.get_height()) == expected[path], "%s size" % path.get_file())


## The sudden death shaft hole compiles a copy of these shaders (StageEnvironment._shaft_hole_variant
## replaces the first line), so the first line and the hole block have to stay as they are.
func _check_shader_contracts() -> void:
	for shader: Shader in [BELT_SHADER, OCEAN_SHADER]:
		var name: String = shader.resource_path.get_file()
		check(shader.code.begins_with("shader_type spatial;"), "%s starts with shader_type spatial;" % name)
		check(shader.code.contains("#ifdef SHAFT_HOLE"), "%s keeps the SHAFT_HOLE block" % name)
		check(shader.code.contains("uniform vec4 shaft_hole"), "%s keeps the shaft_hole uniform" % name)
		check(shader.code.contains("discard;"), "%s keeps the hole discard" % name)
		check(not shader.code.contains("#include"), "%s has no relative #include (the hole variant cannot resolve one)" % name)
	for uniform_name: String in BELT_EXTERNAL_UNIFORMS:
		var declared := BELT_SHADER.code.contains(" %s " % uniform_name) or BELT_SHADER.code.contains(" %s;" % uniform_name)
		check(declared, "belt shader still declares %s" % uniform_name)


func _check_belt_detail() -> void:
	var plain := ShaderMaterial.new()
	plain.shader = BELT_SHADER
	check(plain.get_shader_parameter("detail_strength") == null, "a belt material that skips belt_detail has no detail (previews)")
	for tier: String in TIERS:
		var material := ShaderMaterial.new()
		material.shader = BELT_SHADER
		var red := Color(0.8, 0.1, 0.1)
		material.set_shader_parameter("base_color", red)
		material.set_shader_parameter("scroll_z", 3.5)
		StageMaterialsScript.belt_detail(material, tier)
		check(is_equal_approx(float(material.get_shader_parameter("detail_strength")), 1.0), "%s belt detail on" % tier)
		var normal_strength := float(material.get_shader_parameter("normal_strength"))
		check(is_equal_approx(normal_strength, 0.0 if tier == "low" else 1.0), "%s belt normal strength %s" % [tier, normal_strength])
		check(material.get_shader_parameter("detail_albedo") is Texture2D, "%s belt albedo texture" % tier)
		check(material.get_shader_parameter("detail_orm") is Texture2D, "%s belt ORM texture" % tier)
		check(material.get_shader_parameter("detail_normal") is Texture2D, "%s belt normal texture is bound (strength 0 skips the read)" % tier)
		check((material.get_shader_parameter("base_color") as Color).is_equal_approx(red), "%s belt keeps the customised belt colour" % tier)
		check(is_equal_approx(float(material.get_shader_parameter("scroll_z")), 3.5), "%s belt keeps its scroll" % tier)
		var before: Dictionary = _parameters(material, ["detail_strength", "normal_strength", "detail_tile_m", "detail_albedo_gain", "frame_inner_x", "water_y"])
		StageMaterialsScript.belt_detail(material, tier)
		check(_parameters(material, ["detail_strength", "normal_strength", "detail_tile_m", "detail_albedo_gain", "frame_inner_x", "water_y"]) == before, "%s belt_detail is idempotent" % tier)
	# A quality change re-applies on the same material.
	var changing := ShaderMaterial.new()
	changing.shader = BELT_SHADER
	StageMaterialsScript.belt_detail(changing, "ultra")
	StageMaterialsScript.belt_detail(changing, "low")
	check(is_equal_approx(float(changing.get_shader_parameter("normal_strength")), 0.0), "ultra -> low drops the belt normal map")
	StageMaterialsScript.belt_detail(changing, "high")
	check(is_equal_approx(float(changing.get_shader_parameter("normal_strength")), 1.0), "low -> high brings it back")
	StageMaterialsScript.belt_detail(null, "high")
	check(true, "belt_detail accepts null")


func _parameters(material: ShaderMaterial, names: Array) -> Dictionary:
	var values := {}
	for parameter: String in names:
		values[parameter] = material.get_shader_parameter(parameter)
	return values


func _check_steel() -> void:
	for tier: String in TIERS:
		var frame := StageMaterialsScript.side_frame(tier) as ShaderMaterial
		check(frame != null and frame.shader == STEEL_SHADER, "%s side frame is the steel shader" % tier)
		for material: Material in [StageMaterialsScript.rail_head(tier), StageMaterialsScript.rail_support(tier)]:
			check(material is ShaderMaterial and (material as ShaderMaterial).shader == STEEL_SHADER, "%s rail material is the steel shader" % tier)


func _check_atmosphere_environment() -> void:
	for tier: String in TIERS:
		var env := Environment.new()
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_white = 6.0
		env.background_energy_multiplier = 0.98
		StageAtmosphereScript.apply_environment_quality(env, tier)
		check(env.adjustment_enabled, "%s grade is on" % tier)
		check(is_equal_approx(env.adjustment_contrast, StageAtmosphereScript.GRADE_CONTRAST), "%s grade contrast" % tier)
		check(is_equal_approx(env.adjustment_saturation, 1.0), "%s grade leaves the saturation (runner colours)" % tier)
		check(env.tonemap_mode == Environment.TONE_MAPPER_ACES and is_equal_approx(env.tonemap_white, 6.0), "%s grade keeps the ACES tonemap" % tier)
		# WeatherCycle switches the fog off right before every call: it has to come back.
		for frame: int in range(3):
			env.fog_enabled = false
			StageAtmosphereScript.apply_weather(env, 1.0, 0.0, tier)
			check(env.fog_enabled, "%s fog is back after WeatherCycle's reset (frame %d)" % [tier, frame])
		check(is_equal_approx(env.fog_density, StageAtmosphereScript.FOG_DENSITY), "%s fog density" % tier)
		check(is_equal_approx(env.fog_sky_affect, 0.0), "%s fog leaves the sky" % tier)
		check(is_equal_approx(env.fog_light_energy, env.background_energy_multiplier), "%s fog light follows the sky's energy" % tier)
		# The sudden death descent dims the sky; the fog light is set separately there, but a sky
		# that dims by itself (dusk) takes the fog with it.
		env.background_energy_multiplier = 0.5
		env.fog_enabled = false
		StageAtmosphereScript.apply_weather(env, 1.0, 0.0, tier)
		check(is_equal_approx(env.fog_light_energy, 0.5), "%s fog light follows a dimmer sky" % tier)
		var day_colour := env.fog_light_color
		var night := Environment.new()
		StageAtmosphereScript.apply_weather(night, 0.0, 0.0, tier)
		check(night.fog_light_color.get_luminance() < day_colour.get_luminance(), "%s night fog is darker than day fog" % tier)


func _check_atmosphere_nodes() -> void:
	var probe_on: bool = StageAtmosphereScript.PROBE_ENABLED
	check(not probe_on, "the reflection probe stays off (+134 MB of VRAM for the whole atlas)")
	var expected := {
		# tier: [gameplay vignette, probe]
		"low": [false, false],
		"balanced": [true, false],
		"high": [true, probe_on],
		"ultra": [true, probe_on],
	}
	for tier: String in TIERS:
		var stage := Node3D.new()
		add_child(stage)
		var container := StageAtmosphereScript.build(stage, tier, true)
		check(container != null, "%s atmosphere is built" % tier)
		if container == null:
			stage.queue_free()
			continue
		stage.add_child(container)
		await get_tree().process_frame
		var debug: Dictionary = container.call("get_debug")
		check(bool(debug["vignette"]) == expected[tier][0], "%s vignette %s" % [tier, expected[tier][0]])
		check(bool(debug["probe"]) == expected[tier][1], "%s reflection probe %s" % [tier, expected[tier][1]])
		check(container.get_node_or_null("GroundBounce") is DirectionalLight3D, "%s has the ground bounce light" % tier)
		var bounce := container.get_node("GroundBounce") as DirectionalLight3D
		check(not bounce.shadow_enabled and bounce.light_cull_mask == 1, "%s bounce casts no shadow and lights the stage layer only" % tier)
		if bool(debug["vignette"]):
			stage.visible = false
			await get_tree().process_frame
			check(not bool(container.call("get_debug")["vignette_visible"]), "%s vignette hides with the stage (sudden death)" % tier)
			stage.visible = true
		# A quality change adds and drops the optional nodes.
		StageAtmosphereScript.apply_graphics_quality(container, "low")
		await get_tree().process_frame
		await get_tree().process_frame
		debug = container.call("get_debug")
		check(not bool(debug["vignette"]) and not bool(debug["probe"]), "%s -> low drops the vignette and the probe" % tier)
		StageAtmosphereScript.apply_graphics_quality(container, "high")
		await get_tree().process_frame
		debug = container.call("get_debug")
		check(bool(debug["vignette"]) and bool(debug["probe"]) == probe_on, "low -> high brings the vignette back (probe %s)" % probe_on)
		stage.queue_free()
	# The probe code path still works when it is switched on (nothing else exercises it).
	StageAtmosphereScript.overrides = {"probe": true}
	var probe_stage := Node3D.new()
	add_child(probe_stage)
	var probe_container := StageAtmosphereScript.build(probe_stage, "high", true)
	probe_stage.add_child(probe_container)
	await get_tree().process_frame
	check(bool(probe_container.call("get_debug")["probe"]), "the forced probe is built on high")
	var probe := probe_container.get_node_or_null("CourseProbe") as ReflectionProbe
	check(probe != null and probe.update_mode == ReflectionProbe.UPDATE_ONCE, "the probe renders once")
	check(probe != null and probe.reflection_mask == StageAtmosphereScript.COURSE_REFLECTION_MASK, "the probe lights only the opted-in steel")
	probe_stage.queue_free()
	StageAtmosphereScript.overrides = {}
	# The menu preview has no vignette.
	var menu_stage := Node3D.new()
	add_child(menu_stage)
	var menu_container := StageAtmosphereScript.build(menu_stage, "high", false)
	check(menu_container != null and not bool(menu_container.call("get_debug")["vignette"]), "the menu preview gets no vignette")
	menu_stage.queue_free()
	check(StageAtmosphereScript.build(null, "high", true) == null, "build accepts a null parent")


func _check_weather_cycle() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	var sun := DirectionalLight3D.new()
	var parent := Node3D.new()
	add_child(parent)
	parent.add_child(sun)
	var cycle := WeatherCycle.new()
	parent.add_child(cycle)
	var ocean := ShaderMaterial.new()
	ocean.shader = OCEAN_SHADER
	cycle.ocean_material = ocean
	cycle.setup(env, sun)
	await get_tree().process_frame
	check(env.fog_enabled, "the weather cycle leaves the stage fog on")
	check(is_equal_approx(env.fog_density, StageAtmosphereScript.FOG_DENSITY), "the weather cycle's environment has the stage fog density")
	cycle.refresh_ocean_sun()
	var sun_direction: Variant = ocean.get_shader_parameter("sun_direction")
	check(sun_direction is Vector3, "the ocean is told where the sun is")
	if sun_direction is Vector3:
		# The authored orbit (day_night_sun_path.tscn) rolls the noon sun 30 degrees off the zenith,
		# toward behind-left of the course camera: high, behind the camera (z < 0) and to its left (x > 0).
		var noon: Vector3 = sun_direction
		check(noon.y > 0.8 and noon.y < 0.95, "the noon sun is high but off the zenith (y %.3f)" % noon.y)
		check(noon.z < -0.2, "the noon sun stands behind the course camera, so wall faces are lit (z %.3f)" % noon.z)
		check(noon.x > 0.1, "the noon sun stands to the left of the course camera (x %.3f)" % noon.x)
	check(ocean.get_shader_parameter("reflect_horizon") is Vector3, "the ocean gets the sky colours")
	cycle.ocean_material = null
	cycle.refresh_ocean_sun()
	check(true, "the weather cycle runs without an ocean material")
	parent.queue_free()


func _check_ocean_detail() -> void:
	for tier: String in TIERS:
		check(OceanDetailScript.SETTINGS.has(tier), "ocean settings know %s" % tier)
	var low: Dictionary = OceanDetailScript.SETTINGS["low"]
	check(float(low["fresnel_strength"]) == 0.0 and float(low["glint_strength"]) == 0.0 and float(low["foam_strength"]) == 0.0 and int(low["ripple_waves"]) == 0, "low keeps the plain ocean")
	var balanced: Dictionary = OceanDetailScript.SETTINGS["balanced"]
	var high: Dictionary = OceanDetailScript.SETTINGS["high"]
	check(float(balanced["glint_strength"]) > 0.0 and float(balanced["foam_strength"]) > 0.0 and float(balanced["fresnel_strength"]) > 0.0, "balanced has the reflection, glints and foam")
	check(int(high["ripple_waves"]) >= int(balanced["ripple_waves"]) and int(high["foam_octaves"]) >= int(balanced["foam_octaves"]), "high is at least balanced")
	for tier: String in TIERS:
		var material := ShaderMaterial.new()
		material.shader = OCEAN_SHADER
		OceanDetailScript.configure(material, tier)
		var settings: Dictionary = OceanDetailScript.SETTINGS[tier]
		var written := true
		for parameter: String in settings:
			written = written and material.get_shader_parameter(parameter) == settings[parameter]
		check(written, "%s ocean settings reach the material" % tier)
	OceanDetailScript.configure(null, "high")
	OceanDetailScript.set_sun(null, Vector3.UP)
	check(true, "ocean_detail accepts null")
	var sunny := ShaderMaterial.new()
	sunny.shader = OCEAN_SHADER
	OceanDetailScript.set_sun(sunny, Vector3(0.0, 1.0, 0.0))
	var occlusion := float(sunny.get_shader_parameter("reflect_occlusion"))
	check(occlusion > 0.99, "a noon sun lets deck shadows hide the sky reflection (occlusion %s)" % occlusion)
	var low_sun := ShaderMaterial.new()
	low_sun.shader = OCEAN_SHADER
	OceanDetailScript.set_sun(low_sun, Vector3(0.9, 0.1, 0.0).normalized())
	check(float(low_sun.get_shader_parameter("reflect_occlusion")) < 0.1, "a low sun does not")


func _check_wall_materials() -> void:
	var colours: Array[Color] = [Color(0.5, 0.5, 0.6), Color(0.15, 0.55, 0.95), Color(0.75, 0.12, 0.15)]
	for tier: String in TIERS:
		var textures_expected := {"low": 1, "balanced": 2, "high": 3, "ultra": 3}
		for colour: Color in colours:
			var material := WallMaterialsScript.panel(colour, tier)
			check(material.albedo_color.is_equal_approx(colour), "%s wall keeps its albedo_color (game code reads it)" % tier)
			check(material.uv1_triplanar and not material.uv1_world_triplanar, "%s wall maps in object space (walls move)" % tier)
		var panel := WallMaterialsScript.panel(colours[0], tier)
		var count := 0
		if panel.albedo_texture != null:
			count += 1
		if panel.normal_enabled and panel.normal_texture != null:
			count += 1
		if panel.roughness_texture != null:
			count += 1
		check(count == textures_expected[tier], "%s wall reads %d textures (got %d)" % [tier, textures_expected[tier], count])
	# Shared materials: one per colour instead of one per stripe or spindle.
	var stripe_a := WallMaterialsScript.goal_stripe(Color.WHITE)
	var stripe_b := WallMaterialsScript.goal_stripe(Color.WHITE)
	check(stripe_a == stripe_b, "the goal stripes share their material")
	check(WallMaterialsScript.spindle_steel(Color(0.5, 0.5, 0.5), 0.9, 0.3) == WallMaterialsScript.spindle_steel(Color(0.5, 0.5, 0.5), 0.9, 0.3), "the saw spindles share their material")
	# The retirement fade starts from a transparent copy of a textured panel: it has to keep the colour.
	var wall := (load("res://scenes/quiz_wall.tscn") as PackedScene).instantiate() as Node3D
	add_child(wall)
	wall.call("set_quiz", QuizItem.create("確認", PackedStringArray(["a", "b"]), 0, "", "TEST"), 2)
	var before_colours: Array[Color] = []
	for part: MeshInstance3D in wall.get("wall_parts") + wall.get("doors"):
		before_colours.append((part.material_override as StandardMaterial3D).albedo_color)
	wall.call("prewarm_retirement_fade")
	var index := 0
	var all_transparent := true
	var colours_kept := true
	for part: MeshInstance3D in wall.get("wall_parts") + wall.get("doors"):
		var material := part.material_override as StandardMaterial3D
		all_transparent = all_transparent and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		colours_kept = colours_kept and material.albedo_color.is_equal_approx(before_colours[index])
		index += 1
	check(index > 0 and all_transparent, "prewarm_retirement_fade gives every part the alpha material (%d parts)" % index)
	check(colours_kept, "prewarm_retirement_fade keeps every part's colour")
	wall.queue_free()


func _check_stand_paint() -> void:
	var paint: ShaderMaterial = StandMaterialsScript.painted()
	check(paint != null and paint.shader == STAND_SHADER, "the stand paint is the weathering shader")
	var imported := StandardMaterial3D.new()
	imported.resource_name = "AQS_Painted"
	check(StandMaterialsScript.swap_material(imported) == paint, "AQS_Painted surfaces take the shared paint")
	var glow := StandardMaterial3D.new()
	glow.resource_name = "AQS_NightGlow"
	check(StandMaterialsScript.swap_material(glow) != paint, "the night glow keeps its own material")
	var remembered: String = StandMaterialsScript._quality
	StandMaterialsScript.apply_graphics_quality("low")
	check(is_equal_approx(float(paint.get_shader_parameter("detail")), 0.0), "low paint is the plain vertex colour")
	StandMaterialsScript.apply_graphics_quality("balanced")
	check(is_equal_approx(float(paint.get_shader_parameter("detail")), 1.0), "balanced paint is weathered")
	check(paint.get_shader_parameter("fine_detail") == false, "balanced paint has one mottle octave")
	StandMaterialsScript.apply_graphics_quality("high")
	check(paint.get_shader_parameter("fine_detail") == true, "high paint has the fine octave")
	if not remembered.is_empty():
		StandMaterialsScript.apply_graphics_quality(remembered)
