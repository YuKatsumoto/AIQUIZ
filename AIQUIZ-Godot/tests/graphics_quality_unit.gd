extends Node

## Graphics quality tiers (no gameplay): the four tiers keep their order, Ultra
## supersamples within a 4K pixel budget, switching down from Ultra leaves FSR at
## a downscale, High and Ultra ground the stage with SSAO (never SSIL), every
## per-tier table knows Ultra, and effect particles and tiny parts skip shadows.
## Run: Godot --headless --path . --script tests/graphics_quality_bootstrap.gd

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
	_check_tiers()
	_check_supersampling_budget()
	_check_text_viewport()
	_check_adaptive_supersampling()
	_check_character_preview()
	_check_environment()
	_check_stage_light()
	_check_tables()
	await _check_cheap_shadows()
	print("GRAPHICS_QUALITY_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_tiers() -> void:
	var tiers := GraphicsQuality.VALID_QUALITIES
	check(tiers == PackedStringArray(["low", "balanced", "high", "ultra"]), "tiers ordered light to heavy")
	check(GraphicsQuality.normalize("ultra") == GraphicsQuality.ULTRA, "ultra survives normalize")
	check(GraphicsQuality.normalize("extreme") == GraphicsQuality.BALANCED, "unknown tier falls back to balanced")
	for index in range(tiers.size()):
		check(GraphicsQuality.rank(tiers[index]) == index, "%s rank matches menu index" % tiers[index])
	check(GraphicsQuality.is_at_least(GraphicsQuality.ULTRA, GraphicsQuality.HIGH), "ultra counts as high")
	check(not GraphicsQuality.is_at_least(GraphicsQuality.BALANCED, GraphicsQuality.HIGH), "balanced is below high")
	check(GraphicsQuality.display_name(GraphicsQuality.ULTRA) == "最高画質", "ultra menu label")
	var names := {}
	for tier: String in tiers:
		names[GraphicsQuality.display_name(tier)] = true
	check(names.size() == tiers.size(), "every tier has its own label")


func _check_supersampling_budget() -> void:
	var cases := {
		Vector2(1280, 720): 2.0,
		Vector2(1920, 1080): 2.0,
		Vector2(2560, 1440): 1.5,
		Vector2(2546, 1292): 1.5,
		Vector2(3440, 1440): 1.25,
		Vector2(3840, 2160): 1.0,
		Vector2(7680, 4320): 1.0,
		Vector2.ZERO: 1.0,
	}
	for output: Vector2 in cases:
		var scale := GraphicsQuality.ultra_supersampling_scale(output)
		check(is_equal_approx(scale, float(cases[output])), "ultra scale at %s is %s (got %s)" % [output, cases[output], scale])
		if scale > 1.0:
			check(output.x * output.y * scale * scale <= GraphicsQuality.ULTRA_SUPERSAMPLING_PIXEL_BUDGET + 1.0,
				"ultra at %s stays within the 4K budget" % output)


func _check_text_viewport() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2560, 1440)
	add_child(viewport)
	GraphicsQuality.apply_text_viewport(viewport, GraphicsQuality.ULTRA)
	check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "ultra resolves bilinearly")
	check(is_equal_approx(viewport.scaling_3d_scale, 1.5), "ultra supersamples 1440p by 1.5x")
	check(viewport.msaa_3d == Viewport.MSAA_2X, "1.5x ultra needs only 2x MSAA")
	check(viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "1.5x ultra drops SMAA")
	check(viewport.msaa_2d == Viewport.MSAA_DISABLED, "ultra leaves 2D MSAA off (godot#122004)")
	check(not viewport.use_taa and not viewport.use_debanding, "ultra avoids TAA ghosting and the debanding atlas hazard")
	check(is_equal_approx(viewport.mesh_lod_threshold, 0.25), "ultra keeps near-lossless LOD")
	check(viewport.anisotropic_filtering_level == Viewport.ANISOTROPY_16X, "ultra filters 16x anisotropic")
	# At 4K there is no supersample left, so ultra keeps the full MSAA + SMAA.
	viewport.size = Vector2i(3840, 2160)
	GraphicsQuality.apply_text_viewport(viewport, GraphicsQuality.ULTRA)
	check(is_equal_approx(viewport.scaling_3d_scale, 1.0), "ultra renders 4K natively")
	check(viewport.msaa_3d == Viewport.MSAA_4X, "native ultra keeps 4x MSAA")
	check(viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "native ultra keeps SMAA")
	viewport.size = Vector2i(2560, 1440)
	# Stepping down must land on FSR at a downscale, never FSR above 1.
	GraphicsQuality.apply_text_viewport(viewport, GraphicsQuality.BALANCED)
	check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR, "balanced upscales with FSR")
	check(is_equal_approx(viewport.scaling_3d_scale, 0.85), "balanced renders at 85%")
	GraphicsQuality.apply_text_viewport(viewport, GraphicsQuality.HIGH)
	check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "high renders natively")
	check(is_equal_approx(viewport.scaling_3d_scale, 1.0), "high renders at 100%")
	viewport.free()


func _check_adaptive_supersampling() -> void:
	# Over budget: one quarter step down, never below native.
	check(is_equal_approx(GraphicsQuality.adaptive_next_scale(1.5, 1.5, 9.0, 7.0, true), 1.25), "over budget steps down")
	check(is_equal_approx(GraphicsQuality.adaptive_next_scale(1.0, 1.5, 20.0, 7.0, true), 1.0), "native is the floor")
	# Under budget: step up only while the next scale is predicted to fit.
	check(is_equal_approx(GraphicsQuality.adaptive_next_scale(1.25, 1.5, 3.0, 7.0, true), 1.5), "headroom steps up")
	check(is_equal_approx(GraphicsQuality.adaptive_next_scale(1.25, 1.5, 5.5, 7.0, true), 1.25), "no step up without margin")
	check(is_equal_approx(GraphicsQuality.adaptive_next_scale(1.25, 1.5, 3.0, 7.0, false), 1.25), "hold blocks the step up")
	check(is_equal_approx(GraphicsQuality.adaptive_next_scale(1.5, 1.5, 3.0, 7.0, true), 1.5), "the 4K cap still holds")
	check(GraphicsQuality.adaptive_frame_budget_ms() > 0.0, "a frame budget exists")
	# Registration: Ultra viewports adapt, a re-apply keeps the proven scale,
	# other tiers and the menu reset stop adapting.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child(viewport)
	GraphicsQuality.apply_text_viewport(viewport, GraphicsQuality.ULTRA)
	check(is_equal_approx(GraphicsQuality.adaptive_scale(viewport), 2.0), "ultra 1080p starts at the 2x cap")
	GraphicsQuality._set_adaptive_scale(viewport, GraphicsQuality._adaptive[viewport.get_instance_id()], 1.25, 0.0)
	check(viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "SMAA returns below 1.5x")
	check(viewport.msaa_3d == Viewport.MSAA_2X, "MSAA keeps its sample count while adapting")
	GraphicsQuality.apply_text_viewport(viewport, GraphicsQuality.ULTRA)
	check(is_equal_approx(viewport.scaling_3d_scale, 1.25), "re-apply keeps the adapted scale")
	GraphicsQuality.apply_text_viewport(viewport, GraphicsQuality.HIGH)
	check(GraphicsQuality.adaptive_scale(viewport) < 0.0, "high does not adapt")
	GraphicsQuality.apply_text_viewport(viewport, GraphicsQuality.ULTRA)
	GraphicsQuality.reset_window_3d_quality(viewport)
	check(GraphicsQuality.adaptive_scale(viewport) < 0.0, "menu reset stops adapting")
	viewport.free()


func _check_character_preview() -> void:
	var sized := SubViewport.new()
	sized.size = Vector2i(600, 624)
	add_child(sized)
	GraphicsQuality.apply_character_preview(sized, GraphicsQuality.ULTRA)
	check(is_equal_approx(sized.scaling_3d_scale, GraphicsQuality.ULTRA_SUPERSAMPLING_MAX_SCALE), "small ultra preview gets full 2x2 SSAA")
	GraphicsQuality.apply_character_preview(sized, GraphicsQuality.LOW)
	check(sized.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR and sized.scaling_3d_scale < 1.0, "low preview drops to FSR")
	sized.free()
	var unsized := SubViewport.new()
	unsized.size = Vector2i.ZERO
	add_child(unsized)
	GraphicsQuality.apply_character_preview(unsized, GraphicsQuality.ULTRA)
	check(is_equal_approx(unsized.scaling_3d_scale, GraphicsQuality.ULTRA_SUPERSAMPLING_MAX_SCALE), "unsized ultra preview assumes 2x2 SSAA")
	unsized.free()


func _check_environment() -> void:
	for tier: String in GraphicsQuality.VALID_QUALITIES:
		var environment := Environment.new()
		GraphicsQuality.apply_environment(environment, tier)
		var grounded := GraphicsQuality.is_at_least(tier, GraphicsQuality.HIGH)
		check(environment.ssao_enabled == grounded, "%s SSAO %s" % [tier, "on" if grounded else "off"])
		check(not environment.ssil_enabled, "%s leaves SSIL off" % tier)
		check(environment.glow_enabled == (tier != GraphicsQuality.LOW), "%s glow" % tier)
		if grounded:
			check(environment.ssao_light_affect > 0.0, "%s AO reaches sunlit faces" % tier)


func _check_stage_light() -> void:
	var light := DirectionalLight3D.new()
	for tier: String in GraphicsQuality.VALID_QUALITIES:
		GraphicsQuality.configure_directional_shadow(light, tier)
		var high := GraphicsQuality.is_at_least(tier, GraphicsQuality.HIGH)
		check(light.directional_shadow_blend_splits == high, "%s cascade blending" % tier)
		check(is_equal_approx(light.directional_shadow_max_distance, GraphicsQuality.directional_shadow_distance(tier)), "%s shadow distance" % tier)
	light.free()
	# Global renderer budgets must accept every tier (dummy renderer when headless).
	for tier: String in GraphicsQuality.VALID_QUALITIES:
		GraphicsQuality.apply_rendering_server(tier)
	GraphicsQuality.apply_rendering_server(GameManager.graphics_quality)
	check(true, "renderer budgets applied for every tier")


func _check_cheap_shadows() -> void:
	# Effect particles lose their shadow as they enter the tree.
	for particles: GeometryInstance3D in [GPUParticles3D.new(), CPUParticles3D.new()]:
		check(particles.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s casts by default" % particles.get_class())
		add_child(particles)
		await get_tree().process_frame
		check(particles.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % particles.get_class())
		particles.free()
	# Detailed props keep the shadows of their large parts only.
	var prop := Node3D.new()
	prop.scale = Vector3.ONE * 2.0
	var bolt := MeshInstance3D.new()
	bolt.mesh = BoxMesh.new()
	(bolt.mesh as BoxMesh).size = Vector3.ONE * 0.1
	var frame := MeshInstance3D.new()
	frame.mesh = BoxMesh.new()
	(frame.mesh as BoxMesh).size = Vector3(1.0, 0.1, 0.1)
	var rib := MeshInstance3D.new()
	rib.mesh = BoxMesh.new()
	(rib.mesh as BoxMesh).size = Vector3.ONE * 0.1
	rib.scale = Vector3.ONE * 2.0
	prop.add_child(bolt)
	prop.add_child(frame)
	prop.add_child(rib)
	var dropped := GraphicsQuality.drop_tiny_shadow_casters(prop)
	check(dropped == 1, "one tiny part dropped (got %d)" % dropped)
	check(bolt.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "0.2 m bolt casts no shadow")
	check(frame.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "2 m frame keeps its shadow")
	check(rib.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "scaled-up 0.4 m part keeps its shadow")
	prop.free()


func _check_tables() -> void:
	check(GoalStandEggs.DETAIL.has(GraphicsQuality.ULTRA), "egg detail table knows ultra")
	check(GraphicsQuality.ocean_subdivisions(GraphicsQuality.ULTRA) > GraphicsQuality.ocean_subdivisions(GraphicsQuality.HIGH), "ultra ocean is denser")
	check(GraphicsQuality.ocean_noise_texture_size(GraphicsQuality.ULTRA) > GraphicsQuality.ocean_noise_texture_size(GraphicsQuality.HIGH), "ultra ocean noise is finer")
	check(GraphicsQuality.grandstand_lod_bias(GraphicsQuality.ULTRA) > GraphicsQuality.grandstand_lod_bias(GraphicsQuality.HIGH), "ultra stands keep detail longer")
	check(GraphicsQuality.particle_amount(100, GraphicsQuality.ULTRA) == GraphicsQuality.particle_amount(100, GraphicsQuality.HIGH), "ultra keeps the authored particle counts")
	check(GraphicsQuality.preview_shadow_enabled(GraphicsQuality.ULTRA), "ultra previews cast shadows")
	check(GraphicsQuality.gameplay_shadow_enabled(GraphicsQuality.ULTRA), "ultra gameplay casts shadows")
