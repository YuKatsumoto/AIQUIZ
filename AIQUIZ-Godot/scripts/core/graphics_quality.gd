
@tool
extends Node

## Stateless quality rules also support direct Script calls from @tool previews.
## An already-open editor can retain the autoload's old placeholder instance;
## preloading this script and calling its static methods avoids that instance.

const LOW: String = "low"
const BALANCED: String = "balanced"
const HIGH: String = "high"

const VALID_QUALITIES: PackedStringArray = [LOW, BALANCED, HIGH]
const HIGH_SUPERSAMPLING_SCALE: float = 1.25
const HIGH_SUPERSAMPLING_MAX_OUTPUT_WIDTH: float = 2560.0


static func normalize(value: String) -> String:
	return value if value in VALID_QUALITIES else BALANCED


static func is_mobile_target() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


static func display_name(value: String) -> String:
	match normalize(value):
		LOW:
			return "軽量"
		HIGH:
			return "高画質"
		_:
			return "標準"


static func ocean_subdivisions(value: String) -> int:
	if is_mobile_target():
		match normalize(value):
			LOW:
				return 20
			HIGH:
				return 48
			_:
				return 32
	match normalize(value):
		LOW:
			return 48
		HIGH:
			return 128
		_:
			return 80


static func uses_lightweight_ocean(_value: String) -> bool:
	# Desktop low already drops subdivisions, glow, and 3D scale. Keep the
	# stylized transparent ocean there so returning from a match does not
	# suddenly swap in the opaque mobile water (which picks up sky IBL).
	return is_mobile_target()


static func ocean_noise_texture_size(value: String) -> int:
	match normalize(value):
		LOW:
			return 128
		HIGH:
			return 512
		_:
			return 256


static func particle_amount(base_amount: int, value: String) -> int:
	var scale: float = 0.6
	match normalize(value):
		LOW:
			scale = 0.35
		HIGH:
			scale = 1.0
	if is_mobile_target():
		scale *= 0.65
	return maxi(1, roundi(float(base_amount) * scale))


static func preview_shadow_enabled(value: String) -> bool:
	return not is_mobile_target() and normalize(value) == HIGH


static func gameplay_shadow_enabled(value: String) -> bool:
	return not is_mobile_target() and normalize(value) != LOW


static func apply_text_viewport(viewport: Viewport, value: String) -> void:
	if viewport == null:
		return
	var quality: String = normalize(value)
	if is_mobile_target():
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		match quality:
			LOW:
				viewport.scaling_3d_scale = 0.55
			HIGH:
				viewport.scaling_3d_scale = 0.85
			_:
				viewport.scaling_3d_scale = 0.70
		viewport.msaa_3d = Viewport.MSAA_2X if quality == HIGH else Viewport.MSAA_DISABLED
	else:
		match quality:
			LOW:
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				viewport.scaling_3d_scale = 0.70
				viewport.msaa_3d = Viewport.MSAA_DISABLED
			BALANCED:
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				viewport.scaling_3d_scale = 0.85
				viewport.msaa_3d = Viewport.MSAA_2X
			_:
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
				viewport.scaling_3d_scale = 1.0
				viewport.msaa_3d = Viewport.MSAA_4X
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA
		if quality == LOW or is_mobile_target()
		else Viewport.SCREEN_SPACE_AA_SMAA
	)
	viewport.use_taa = false
	_apply_distance_quality(viewport, quality)
	# Godot 4.6ではSubViewportのdebanding切替時に共有フォントアトラスが一時的に
	# 黒く描画される場合があるため、文字を含むViewportでは常に無効化する。
	viewport.use_debanding = false


static func apply_character_preview(viewport: Viewport, value: String) -> void:
	if viewport == null:
		return
	# These viewports render 3D cameras; their UI overlays belong to the parent.
	# 2D MSAA with 3D scaling and screen-space AA can create an invalid resolve
	# framebuffer in Godot 4.7 (godotengine/godot#122004). The death wipe first
	# renders after a player loses, so enabling it here can crash at a door.
	# Clear it before changing render scale, including when reapplying quality.
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	var quality: String = normalize(value)
	if is_mobile_target():
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		viewport.scaling_3d_scale = 0.60 if quality == LOW else (0.85 if quality == HIGH else 0.72)
		viewport.msaa_3d = Viewport.MSAA_2X if quality == HIGH else Viewport.MSAA_DISABLED
	else:
		match quality:
			LOW:
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				viewport.scaling_3d_scale = 0.59
				viewport.msaa_3d = Viewport.MSAA_DISABLED
			HIGH:
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
				viewport.scaling_3d_scale = (
					HIGH_SUPERSAMPLING_SCALE if _can_use_high_supersampling(viewport) else 1.0
				)
				viewport.msaa_3d = Viewport.MSAA_4X
			_:
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				viewport.scaling_3d_scale = 0.77
				viewport.msaa_3d = Viewport.MSAA_2X
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA
		if quality == LOW or is_mobile_target()
		else Viewport.SCREEN_SPACE_AA_SMAA
	)
	viewport.use_taa = false
	viewport.use_debanding = quality == HIGH
	_apply_distance_quality(viewport, quality)


static func grandstand_lod_bias(value: String) -> float:
	match normalize(value):
		LOW:
			return 0.75
		HIGH:
			return 1.35
		_:
			return 1.0


static func uses_anisotropic_material_filter(value: String) -> bool:
	return normalize(value) != LOW


static func directional_shadow_distance(value: String) -> float:
	match normalize(value):
		LOW:
			return 100.0
		HIGH:
			return 420.0
		_:
			return 280.0


static func _apply_distance_quality(viewport: Viewport, quality: String) -> void:
	if is_mobile_target():
		match quality:
			LOW:
				viewport.mesh_lod_threshold = 2.0
				viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_2X
				viewport.texture_mipmap_bias = 0.2
			HIGH:
				viewport.mesh_lod_threshold = 1.2
				viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_4X
				viewport.texture_mipmap_bias = 0.0
			_:
				viewport.mesh_lod_threshold = 1.5
				viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_4X
				viewport.texture_mipmap_bias = 0.1
		return
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


static func _can_use_high_supersampling(viewport: Viewport) -> bool:
	if is_mobile_target():
		return false
	var output_width: float = viewport.get_visible_rect().size.x
	if viewport is Window:
		output_width = float(DisplayServer.window_get_size().x)
	return output_width > 0.0 and output_width <= HIGH_SUPERSAMPLING_MAX_OUTPUT_WIDTH


static func reset_window_3d_quality(viewport: Viewport) -> void:
	# The root Window survives scene changes. Gameplay FSR/AA left on that
	# Window can make the next menu SubViewport bake a washed-out sky, which
	# then shows through the ocean.
	if viewport == null:
		return
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = 1.0
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.use_debanding = false
	viewport.mesh_lod_threshold = 1.0
	viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_4X
	viewport.texture_mipmap_bias = 0.0


static func apply_environment(environment: Environment, value: String) -> void:
	if environment == null:
		return
	var quality: String = normalize(value)
	environment.glow_enabled = quality != LOW and not is_mobile_target()
	if quality == LOW or is_mobile_target():
		environment.glow_intensity = 0.0
		environment.glow_strength = 0.0
		environment.glow_bloom = 0.0
		return
	environment.glow_intensity = 0.4 if quality == BALANCED else 0.5
	environment.glow_strength = 0.65 if quality == BALANCED else 0.8
	environment.glow_bloom = 0.03 if quality == BALANCED else 0.05
	environment.set_glow_level(0, true)
	environment.set_glow_level(1, true)
	environment.set_glow_level(2, quality == HIGH)
	environment.set_glow_level(3, false)
