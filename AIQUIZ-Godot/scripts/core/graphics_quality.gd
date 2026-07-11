class_name GraphicsQuality
extends RefCounted

const LOW: String = "low"
const BALANCED: String = "balanced"
const HIGH: String = "high"

const VALID_QUALITIES: PackedStringArray = [LOW, BALANCED, HIGH]


static func normalize(value: String) -> String:
	return value if value in VALID_QUALITIES else BALANCED


static func display_name(value: String) -> String:
	match normalize(value):
		LOW:
			return "軽量"
		HIGH:
			return "高画質"
		_:
			return "標準"


static func ocean_subdivisions(value: String) -> int:
	match normalize(value):
		LOW:
			return 64
		HIGH:
			return 200
		_:
			return 128


static func particle_amount(base_amount: int, value: String) -> int:
	var scale: float = 0.6
	match normalize(value):
		LOW:
			scale = 0.35
		HIGH:
			scale = 1.0
	return maxi(1, roundi(float(base_amount) * scale))


static func preview_shadow_enabled(value: String) -> bool:
	return normalize(value) == HIGH


static func gameplay_shadow_enabled(value: String) -> bool:
	return normalize(value) != LOW


static func apply_text_viewport(viewport: Viewport, value: String) -> void:
	if viewport == null:
		return
	var quality: String = normalize(value)
	# Quiz labels and HUD-adjacent 3D text always render at native resolution.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = 1.0
	viewport.msaa_3d = Viewport.MSAA_4X if quality == HIGH else Viewport.MSAA_2X
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	# Godot 4.6ではSubViewportのdebanding切替時に共有フォントアトラスが一時的に
	# 黒く描画される場合があるため、文字を含むViewportでは常に無効化する。
	viewport.use_debanding = false


static func apply_character_preview(viewport: Viewport, value: String) -> void:
	if viewport == null:
		return
	var quality: String = normalize(value)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	match quality:
		LOW:
			viewport.scaling_3d_scale = 0.5
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.msaa_2d = Viewport.MSAA_DISABLED
		HIGH:
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_4X
			viewport.msaa_2d = Viewport.MSAA_2X
		_:
			viewport.scaling_3d_scale = 0.67
			viewport.msaa_3d = Viewport.MSAA_2X
			viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.use_debanding = quality == HIGH


static func apply_environment(environment: Environment, value: String) -> void:
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
