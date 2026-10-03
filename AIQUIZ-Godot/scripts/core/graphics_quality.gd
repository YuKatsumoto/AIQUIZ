
@tool
extends Node

## Stateless quality rules also support direct Script calls from @tool previews.
## An already-open editor can retain the autoload's old placeholder instance;
## preloading this script and calling its static methods avoids that instance.

const LOW: String = "low"
const BALANCED: String = "balanced"
const HIGH: String = "high"
const ULTRA: String = "ultra"

## Ordered from lightest to heaviest: rank() and the settings menu use this order.
const VALID_QUALITIES: PackedStringArray = [LOW, BALANCED, HIGH, ULTRA]
const HIGH_SUPERSAMPLING_SCALE: float = 1.25
const HIGH_SUPERSAMPLING_MAX_OUTPUT_WIDTH: float = 2560.0
## Ultra renders 3D within a 4K pixel budget and resolves it bilinearly:
## 2x2 SSAA up to 1080p, 1.5x at 1440p, native at 4K, with MSAA on top.
const ULTRA_SUPERSAMPLING_PIXEL_BUDGET: float = 3840.0 * 2160.0
const ULTRA_SUPERSAMPLING_MAX_SCALE: float = 2.0
## From this supersample on, 2x MSAA without SMAA resolves edges as cleanly as
## 4x MSAA + SMAA (compared at 3x zoom) for ~0.9 ms less at 1440p.
const ULTRA_LIGHT_AA_MIN_SCALE: float = 1.5
## Parts smaller than this cast no shadow: a bolt or button shadow is a few
## texels inside its assembly's own, but it is one more draw in every cascade.
const TINY_SHADOW_CASTER_SIZE: float = 0.25
## Ultra's supersample follows the GPU: each viewport's median GPU time over a
## window (loading hitches do not count) is compared with the frame budget; a
## miss drops the scale a quarter step, and it climbs back once the next step
## (assumed to cost pixels squared) fits again.
const ADAPTIVE_STEP: float = 0.25
const ADAPTIVE_WINDOW_SEC: float = 1.0
## Buffers are reallocated after a scale change; skip those frames.
const ADAPTIVE_SETTLE_SEC: float = 0.5
## A freshly built scene still streams and compiles for a moment.
const ADAPTIVE_START_SETTLE_SEC: float = 2.0
## After stepping down, wait this long before trying the higher scale again.
const ADAPTIVE_UP_HOLD_SEC: float = 6.0
const ADAPTIVE_UP_MARGIN: float = 0.85
## GPU share of the frame the supersample may use, at up to 120 fps (60 Hz
## screens get 60 fps worth of budget, 144/240 Hz screens 120 fps worth).
const ADAPTIVE_BUDGET_SHARE: float = 0.85
const ADAPTIVE_MAX_TARGET_FPS: float = 120.0

## Viewport instance id -> adaptive state. Only Ultra text viewports (the root
## Window in a match, the menu background) register.
static var _adaptive: Dictionary = {}
## Tests and benchmarks can impose a budget (ms) to emulate a slower GPU.
static var adaptive_budget_override_ms: float = 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Effect particles never cast shadows. Droplets, sparks and confetti are too
	# small to read in the shadow map, yet each particle is redrawn in all four
	# sun cascades: 85% of the shadow triangles before this rule.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is GPUParticles3D or node is CPUParticles3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	if _adaptive.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var budget: float = adaptive_frame_budget_ms()
	for id: int in _adaptive.keys():
		var entry: Dictionary = _adaptive[id]
		var viewport := (entry["ref"] as WeakRef).get_ref() as Viewport
		if viewport == null or not viewport.is_inside_tree():
			_adaptive.erase(id)
			continue
		if now < float(entry["settle_until"]):
			_restart_adaptive_window(entry, now)
			continue
		var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
		if gpu_ms <= 0.0:
			continue # Not drawn this frame (hidden or not updating).
		var samples: PackedFloat32Array = entry["samples"]
		samples.append(gpu_ms)
		entry["samples"] = samples
		if now - float(entry["window_start"]) < ADAPTIVE_WINDOW_SEC:
			continue
		samples.sort()
		var median: float = samples[samples.size() / 2]
		var scale: float = entry["scale"]
		var next: float = adaptive_next_scale(
			scale, entry["max"], median, budget, now >= float(entry["hold_until"])
		)
		if next < scale:
			entry["hold_until"] = now + ADAPTIVE_UP_HOLD_SEC
		if not is_equal_approx(next, scale):
			_set_adaptive_scale(viewport, entry, next, now)
		_restart_adaptive_window(entry, now)


## The supersample to use next, given the current one, its cap, the averaged
## GPU time of the viewport and the budget. Pure so it can be tested.
static func adaptive_next_scale(scale: float, max_scale: float, average_ms: float, budget_ms: float, may_rise: bool) -> float:
	if average_ms > budget_ms and scale > 1.0:
		return maxf(1.0, scale - ADAPTIVE_STEP)
	if may_rise and scale < max_scale:
		var next: float = minf(max_scale, scale + ADAPTIVE_STEP)
		# Pessimistic: only the pixel-bound part really grows with the scale.
		if average_ms * (next * next) / (scale * scale) < budget_ms * ADAPTIVE_UP_MARGIN:
			return next
	return scale


static func adaptive_frame_budget_ms() -> float:
	if adaptive_budget_override_ms > 0.0:
		return adaptive_budget_override_ms
	var refresh: float = DisplayServer.screen_get_refresh_rate()
	var target_fps: float = clampf(refresh if refresh > 0.0 else 60.0, 60.0, ADAPTIVE_MAX_TARGET_FPS)
	return 1000.0 / target_fps * ADAPTIVE_BUDGET_SHARE


## Current adaptive supersample of an Ultra viewport, or -1 if it does not adapt.
static func adaptive_scale(viewport: Viewport) -> float:
	var entry: Dictionary = _adaptive.get(viewport.get_instance_id(), {})
	return float(entry.get("scale", -1.0))


static func _register_adaptive(viewport: Viewport, max_scale: float) -> float:
	var id: int = viewport.get_instance_id()
	var now: float = Time.get_ticks_msec() / 1000.0
	var entry: Dictionary = _adaptive.get(id, {})
	# A re-apply (window resize) keeps what the GPU already proved it can hold.
	var scale: float = minf(float(entry.get("scale", max_scale)), max_scale)
	entry["settle_until"] = now + (ADAPTIVE_SETTLE_SEC if entry.has("scale") else ADAPTIVE_START_SETTLE_SEC)
	entry["ref"] = weakref(viewport)
	entry["max"] = max_scale
	entry["scale"] = scale
	if not entry.has("hold_until"):
		entry["hold_until"] = 0.0
	_restart_adaptive_window(entry, now)
	_adaptive[id] = entry
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	return scale


static func _unregister_adaptive(viewport: Viewport) -> void:
	_adaptive.erase(viewport.get_instance_id())


static func _set_adaptive_scale(viewport: Viewport, entry: Dictionary, scale: float, now: float) -> void:
	entry["scale"] = scale
	entry["settle_until"] = now + ADAPTIVE_SETTLE_SEC
	_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_BILINEAR, scale)
	# MSAA stays as chosen for the cap (changing it would rebuild every material
	# pipeline); SMAA returns whenever the supersample falls below 1.5x.
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_DISABLED
		if scale >= ULTRA_LIGHT_AA_MIN_SCALE
		else Viewport.SCREEN_SPACE_AA_SMAA
	)


static func _restart_adaptive_window(entry: Dictionary, now: float) -> void:
	entry["samples"] = PackedFloat32Array()
	entry["window_start"] = now


static func normalize(value: String) -> String:
	return value if value in VALID_QUALITIES else BALANCED


static func rank(value: String) -> int:
	return VALID_QUALITIES.find(normalize(value))


static func is_at_least(value: String, minimum: String) -> bool:
	return rank(value) >= rank(minimum)


static func is_mobile_target() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


static func display_name(value: String) -> String:
	match normalize(value):
		LOW:
			return "軽量"
		HIGH:
			return "高画質"
		ULTRA:
			return "最高画質"
		_:
			return "標準"


static func ocean_subdivisions(value: String) -> int:
	if is_mobile_target():
		match normalize(value):
			LOW:
				return 20
			HIGH, ULTRA:
				return 48
			_:
				return 32
	match normalize(value):
		LOW:
			return 48
		HIGH:
			return 128
		ULTRA:
			# 4 km plane: ~16 m vertex spacing keeps the swell noise from faceting.
			return 256
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
		ULTRA:
			return 1024
		_:
			return 256


static func particle_amount(base_amount: int, value: String) -> int:
	var scale: float = 0.6
	match normalize(value):
		LOW:
			scale = 0.35
		HIGH, ULTRA:
			scale = 1.0
	if is_mobile_target():
		scale *= 0.65
	return maxi(1, roundi(float(base_amount) * scale))


static func preview_shadow_enabled(value: String) -> bool:
	return not is_mobile_target() and is_at_least(value, HIGH)


static func gameplay_shadow_enabled(value: String) -> bool:
	return not is_mobile_target() and normalize(value) != LOW


static func apply_text_viewport(viewport: Viewport, value: String) -> void:
	if viewport == null:
		return
	var quality: String = normalize(value)
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	if quality != ULTRA or is_mobile_target():
		_unregister_adaptive(viewport)
	if is_mobile_target():
		match quality:
			LOW:
				_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_FSR, 0.55)
			HIGH, ULTRA:
				_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_FSR, 0.85)
			_:
				_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_FSR, 0.70)
		viewport.msaa_3d = Viewport.MSAA_2X if is_at_least(quality, HIGH) else Viewport.MSAA_DISABLED
	else:
		match quality:
			LOW:
				_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_FSR, 0.70)
				viewport.msaa_3d = Viewport.MSAA_DISABLED
			BALANCED:
				_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_FSR, 0.85)
				viewport.msaa_3d = Viewport.MSAA_2X
			ULTRA:
				# Supersampling also resolves Label3D glyphs and far texture detail
				# that MSAA/SMAA cannot reach. The 4K budget is only the cap: the
				# scale then follows the GPU (see _process).
				var max_scale: float = ultra_supersampling_scale(_viewport_output_size(viewport))
				var scale: float = max_scale
				if max_scale > 1.0:
					scale = _register_adaptive(viewport, max_scale)
				else:
					_unregister_adaptive(viewport)
				_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_BILINEAR, scale)
				viewport.msaa_3d = (
					Viewport.MSAA_2X if max_scale >= ULTRA_LIGHT_AA_MIN_SCALE else Viewport.MSAA_4X
				)
			_:
				_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_BILINEAR, 1.0)
				viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA
		if quality == LOW or is_mobile_target()
		else Viewport.SCREEN_SPACE_AA_SMAA
	)
	if quality == ULTRA and not is_mobile_target() and viewport.scaling_3d_scale >= ULTRA_LIGHT_AA_MIN_SCALE:
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
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
		_set_3d_scaling(
			viewport,
			Viewport.SCALING_3D_MODE_FSR,
			0.60 if quality == LOW else (0.85 if is_at_least(quality, HIGH) else 0.72)
		)
		viewport.msaa_3d = Viewport.MSAA_2X if is_at_least(quality, HIGH) else Viewport.MSAA_DISABLED
	else:
		match quality:
			LOW:
				_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_FSR, 0.59)
				viewport.msaa_3d = Viewport.MSAA_DISABLED
			HIGH:
				_set_3d_scaling(
					viewport,
					Viewport.SCALING_3D_MODE_BILINEAR,
					HIGH_SUPERSAMPLING_SCALE if _can_use_high_supersampling(viewport) else 1.0
				)
				viewport.msaa_3d = Viewport.MSAA_4X
			ULTRA:
				# Character previews are small; before a stretch container sizes one,
				# assume the full 2x2 supersample.
				var output: Vector2 = _viewport_output_size(viewport)
				_set_3d_scaling(
					viewport,
					Viewport.SCALING_3D_MODE_BILINEAR,
					(
						ultra_supersampling_scale(output)
						if output.x > 0.0 and output.y > 0.0
						else ULTRA_SUPERSAMPLING_MAX_SCALE
					)
				)
				viewport.msaa_3d = Viewport.MSAA_4X
			_:
				_set_3d_scaling(viewport, Viewport.SCALING_3D_MODE_FSR, 0.77)
				viewport.msaa_3d = Viewport.MSAA_2X
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA
		if quality == LOW or is_mobile_target()
		else Viewport.SCREEN_SPACE_AA_SMAA
	)
	viewport.use_taa = false
	# Same atlas hazard as apply_text_viewport: toggling debanding on any
	# SubViewport can make sibling LOADING labels and other UI glyphs render black.
	viewport.use_debanding = false
	_apply_distance_quality(viewport, quality)


static func grandstand_lod_bias(value: String) -> float:
	match normalize(value):
		LOW:
			return 0.75
		HIGH:
			return 1.35
		ULTRA:
			return 2.0
		_:
			return 1.0


static func uses_anisotropic_material_filter(value: String) -> bool:
	return normalize(value) != LOW


static func directional_shadow_distance(value: String) -> float:
	match normalize(value):
		LOW:
			return 100.0
		HIGH, ULTRA:
			return 420.0
		_:
			return 280.0


## Stage sun: blend cascade seams once the 8K atlas makes the near split sharp.
static func configure_directional_shadow(light: DirectionalLight3D, value: String) -> void:
	if light == null:
		return
	light.directional_shadow_max_distance = directional_shadow_distance(value)
	light.directional_shadow_blend_splits = not is_mobile_target() and is_at_least(value, HIGH)


## Renderer-wide shadow and screen-space effect budgets. These are global
## RenderingServer settings, so only runtime code (GameManager) applies them;
## lower tiers restore the project defaults.
static func apply_rendering_server(value: String) -> void:
	var quality: String = normalize(value)
	var mobile: bool = is_mobile_target()
	# Soft Medium doubles Soft Low's PCF taps at the same kernel radius. Soft High
	# and Ultra also widen the kernel and the depth bias with it, which erases the
	# shadows of the saws gliding just above the belt; Ultra's supersampling
	# already averages the remaining penumbra grain.
	var shadow_quality: RenderingServer.ShadowQuality = (
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
		if not mobile and is_at_least(quality, HIGH)
		else RenderingServer.SHADOW_QUALITY_SOFT_LOW
	)
	RenderingServer.directional_shadow_atlas_set_size(
		8192 if not mobile and is_at_least(quality, HIGH) else 4096,
		true
	)
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_quality)
	RenderingServer.positional_soft_shadow_filter_set_quality(shadow_quality)
	if quality == ULTRA and not mobile:
		RenderingServer.environment_set_ssao_quality(
			RenderingServer.ENV_SSAO_QUALITY_ULTRA, true, 0.5, 3, 50.0, 300.0
		)
	else:
		RenderingServer.environment_set_ssao_quality(
			RenderingServer.ENV_SSAO_QUALITY_HIGH if quality == HIGH and not mobile
			else RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
			true, 0.5, 2, 50.0, 300.0
		)


## Turns off shadows for the small parts of a detailed prop (bolts, buttons,
## cooling ribs). Returns how many parts stopped casting.
static func drop_tiny_shadow_casters(root: Node3D, max_size: float = TINY_SHADOW_CASTER_SIZE) -> int:
	var dropped := 0
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var basis := Basis.IDENTITY
		var walk: Node = geometry
		while walk != null and walk != root.get_parent():
			if walk is Node3D:
				basis = (walk as Node3D).transform.basis * basis
			walk = walk.get_parent()
		var size: Vector3 = geometry.get_aabb().size * basis.get_scale()
		if maxf(size.x, maxf(size.y, size.z)) < max_size:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dropped += 1
	return dropped


static func ultra_supersampling_scale(output_size: Vector2) -> float:
	var pixels: float = output_size.x * output_size.y
	if pixels <= 0.0:
		return 1.0
	var scale: float = sqrt(ULTRA_SUPERSAMPLING_PIXEL_BUDGET / pixels)
	# Quarter steps keep the bilinear resolve predictable and stay within budget.
	return clampf(floorf(scale * 4.0) / 4.0, 1.0, ULTRA_SUPERSAMPLING_MAX_SCALE)


## FSR cannot downsample. Pass through bilinear so switching from a supersampled
## tier never pairs FSR with a scale above 1 (Godot warns and falls back).
static func _set_3d_scaling(viewport: Viewport, mode: Viewport.Scaling3DMode, scale: float) -> void:
	if viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = scale
	viewport.scaling_3d_mode = mode


static func _viewport_output_size(viewport: Viewport) -> Vector2:
	if viewport is Window:
		return Vector2(DisplayServer.window_get_size())
	return viewport.get_visible_rect().size


static func _apply_distance_quality(viewport: Viewport, quality: String) -> void:
	if is_mobile_target():
		match quality:
			LOW:
				viewport.mesh_lod_threshold = 2.0
				viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_2X
				viewport.texture_mipmap_bias = 0.2
			HIGH, ULTRA:
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
		ULTRA:
			# Near-lossless LOD: the skyline and crowds keep their silhouettes.
			viewport.mesh_lod_threshold = 0.25
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
	_unregister_adaptive(viewport)
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
	var mobile: bool = is_mobile_target()
	# Contact shading where players, saws, and walls meet the flat-colored stage.
	var use_ssao: bool = not mobile and is_at_least(quality, HIGH)
	environment.ssao_enabled = use_ssao
	if use_ssao:
		environment.ssao_radius = 1.5
		environment.ssao_intensity = 2.5
		environment.ssao_power = 1.5
		environment.ssao_detail = 0.5
		environment.ssao_horizon = 0.06
		environment.ssao_sharpness = 0.98
		# Ambient-only AO all but vanishes in full sun; let it touch lit faces a little.
		environment.ssao_light_affect = 0.2
		environment.ssao_ao_channel_affect = 0.0
	# No SSIL: bounce off the sunlit belt lifts the wall and pillar creases that
	# AO just grounded, reading as a glow band for ~0.9 ms at 1440p Ultra.
	environment.glow_enabled = quality != LOW and not mobile
	if quality == LOW or mobile:
		environment.glow_intensity = 0.0
		environment.glow_strength = 0.0
		environment.glow_bloom = 0.0
		return
	environment.glow_intensity = 0.4 if quality == BALANCED else 0.5
	environment.glow_strength = 0.65 if quality == BALANCED else 0.8
	environment.glow_bloom = 0.03 if quality == BALANCED else 0.05
	environment.set_glow_level(0, true)
	environment.set_glow_level(1, true)
	environment.set_glow_level(2, is_at_least(quality, HIGH))
	environment.set_glow_level(3, false)
