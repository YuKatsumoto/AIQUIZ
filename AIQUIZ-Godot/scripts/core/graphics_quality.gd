
extends Node

const LOW: String = "low"
const BALANCED: String = "balanced"
const HIGH: String = "high"

const VALID_QUALITIES: PackedStringArray = [LOW, BALANCED, HIGH]
const HIGH_SUPERSAMPLING_SCALE: float = 1.25
const HIGH_SUPERSAMPLING_MAX_OUTPUT_WIDTH: float = 2560.0


func normalize(value: String) -> String:
	return value if value in VALID_QUALITIES else BALANCED


func display_name(value: String) -> String:
	match normalize(value):
		LOW:
			return "軽量"
		HIGH:
			return "高画質"
		_:
			return "標準"


func ocean_subdivisions(value: String) -> int:
	match normalize(value):
		LOW:
			return 64
		HIGH:
			return 200
		_:
			return 128


func particle_amount(base_amount: int, value: String) -> int:
	var scale: float = 0.6
	match normalize(value):
		LOW:
			scale = 0.35
		HIGH:
			scale = 1.0
	return maxi(1, roundi(float(base_amount) * scale))


func preview_shadow_enabled(value: String) -> bool:
	return normalize(value) == HIGH


func gameplay_shadow_enabled(value: String) -> bool:
	return normalize(value) != LOW


func apply_text_viewport(viewport: Viewport, value: String) -> void:
	if viewport == null:
		return
	var quality: String = normalize(value)
	# High uses modest SSAA while the output is at most 1440p. At 4K, native
	# rendering avoids multiplying an already large pixel budget.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = (
		HIGH_SUPERSAMPLING_SCALE
		if quality == HIGH and _can_use_high_supersampling(viewport)
		else 1.0
	)
	viewport.msaa_3d = Viewport.MSAA_4X if quality == HIGH else Viewport.MSAA_2X
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA
		if quality == LOW
		else Viewport.SCREEN_SPACE_AA_SMAA
	)
	viewport.use_taa = false
	_apply_distance_quality(viewport, quality)
	# Godot 4.6ではSubViewportのdebanding切替時に共有フォントアトラスが一時的に
	# 黒く描画される場合があるため、文字を含むViewportでは常に無効化する。
	viewport.use_debanding = false


func apply_character_preview(viewport: Viewport, value: String) -> void:
	if viewport == null:
		return
	var quality: String = normalize(value)
	match quality:
		LOW:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			viewport.scaling_3d_scale = 0.59
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.msaa_2d = Viewport.MSAA_DISABLED
		HIGH:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = (
				HIGH_SUPERSAMPLING_SCALE if _can_use_high_supersampling(viewport) else 1.0
			)
			viewport.msaa_3d = Viewport.MSAA_4X
			viewport.msaa_2d = Viewport.MSAA_2X
		_:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			viewport.scaling_3d_scale = 0.77
			viewport.msaa_3d = Viewport.MSAA_2X
			viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA
		if quality == LOW
		else Viewport.SCREEN_SPACE_AA_SMAA
	)
	viewport.use_taa = false
	viewport.use_debanding = quality == HIGH
	_apply_distance_quality(viewport, quality)


func grandstand_lod_bias(value: String) -> float:
	match normalize(value):
		LOW:
			return 0.75
		HIGH:
			return 1.35
		_:
			return 1.0


func uses_anisotropic_material_filter(value: String) -> bool:
	return normalize(value) != LOW


func directional_shadow_distance(value: String) -> float:
	match normalize(value):
		LOW:
			return 100.0
		HIGH:
			return 220.0
		_:
			return 160.0


func _apply_distance_quality(viewport: Viewport, quality: String) -> void:
	match quality:
		LOW:
			viewport.mesh_lod_threshold = 1.5
			viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_4X
			viewport.texture_mipmap_bias = 0.1
		HIGH:
			# Keep generated LODs active, but switch later than Godot's default.
			viewport.mesh_lod_threshold = 0.6
			viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
			viewport.texture_mipmap_bias = -0.15
		_:
			viewport.mesh_lod_threshold = 1.0
			viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
			viewport.texture_mipmap_bias = 0.0


func _can_use_high_supersampling(viewport: Viewport) -> bool:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return false
	var output_width: float = viewport.get_visible_rect().size.x
	if viewport is Window:
		output_width = float(DisplayServer.window_get_size().x)
	return output_width > 0.0 and output_width <= HIGH_SUPERSAMPLING_MAX_OUTPUT_WIDTH


func apply_environment(environment: Environment, value: String) -> void:
	if environment == null:
		return
	var quality: String = normalize(value)
	environment.glow_enabled = quality != LOW
	if quality == LOW:
		return
	environment.glow_intensity = 0.4 if quality == BALANCED else 0.5
	environment.glow_strength = 0.65 if quality == BALANCED else 0.8
	environment.glow_bloom = 0.03 if quality == BALANCED else 0.05
	environment.set_glow_level(0, true)
	environment.set_glow_level(1, true)
	environment.set_glow_level(2, quality == HIGH)
	environment.set_glow_level(3, false)
