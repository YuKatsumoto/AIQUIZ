class_name ShaftDescent
extends Node3D

## 降下ローディングの縦穴（docs/sudden_death_underground.md 第5章「黄色いランプの縦穴」）。
##
## 縦穴ローカル座標：原点は縦穴の軸上、+Y が上。演出（SuddenDeathDirector）がこのノード自体を
## 動かす・置き直す。5 m の壁タイル（assets/environment/shaft_descent/shaft_tile.glb）を12枚重ね、
## 模様のずれ（scroll）の 5 m 余りだけ上へずらして無限の縦穴に見せる。
##
## 光：壁・レール・小物は unshaded。ベイクした灯りのライトマップ（5枚重ねの中央）と、
## 同じ単位の解析的なナトリウム灯の項で全段を照らす。実際のライト（人物・デッキ用）は
## デッキに近い3段の12灯（影なし）＋昼光スポット1灯＋回転灯4灯だけ。
## すべて setup() で作る（試合開始の黒画面中に生成される前提）。

const INNER_RADIUS := SuddenDeathLayout.SHAFT_RADIUS
const TILE_HEIGHT := SuddenDeathLayout.SHAFT_TILE_HEIGHT
const TILE_COUNT := SuddenDeathLayout.SHAFT_TILE_COUNT
const TILES_ABOVE := SuddenDeathLayout.SHAFT_TILES_ABOVE

const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const TILE_SCENE := preload("res://assets/environment/shaft_descent/shaft_tile.glb")
const DECK_SCENE := preload("res://assets/environment/shaft_descent/shaft_deck.glb")
const MOUTH_SCENE := preload("res://assets/environment/shaft_descent/shaft_mouth.glb")
const SIGN_SCENE := preload("res://assets/environment/shaft_descent/shaft_sign.glb")
const WALL_SHADER := preload("res://shaders/sudden_death/shaft_wall.gdshader")
const PROP_SHADER := preload("res://shaders/sudden_death/shaft_prop.gdshader")
const GLASS_SHADER := preload("res://shaders/sudden_death/shaft_glass.gdshader")
const HALO_SHADER := preload("res://shaders/sudden_death/shaft_halo.gdshader")
const CONE_SHADER := preload("res://shaders/sudden_death/shaft_cone.gdshader")
const MOTES_SHADER := preload("res://shaders/sudden_death/shaft_motes.gdshader")
const SKY_SHADER := preload("res://shaders/sudden_death/shaft_sky.gdshader")
const GRATING_SHADER := preload("res://shaders/sudden_death/shaft_grating.gdshader")
const HAZARD_SHADER := preload("res://shaders/sudden_death/shaft_hazard.gdshader")
const LENS_SHADER := preload("res://shaders/sudden_death/shaft_beacon_lens.gdshader")
const PLUG_SHADER := preload("res://shaders/sudden_death/shaft_plug.gdshader")
const WALL_MASKS := preload("res://assets/environment/shaft_descent/textures/shaft_wall_masks.png")
const WALL_NORMAL := preload("res://assets/environment/shaft_descent/textures/shaft_wall_normal.png")
const WALL_LIGHT := preload("res://assets/environment/shaft_descent/textures/shaft_wall_light.png")
const DETAIL_NORMAL := preload("res://assets/environment/shaft_descent/textures/shaft_concrete_detail_normal.png")
const SIGN_FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

## Lamp rows (assets/environment/shaft_descent/shaft_descent_layout.json).
const LAMP_Y := 2.95
const LAMP_RADIUS := 6.55
const LAMP_PSI: Array[float] = [45.0, 135.0, 225.0, 315.0]
## shaft_bake.json light_max_over_C: baked lightmap value 1.0 in units of the analytic C·cos/d².
const LIGHT_MAX_OVER_C := 3.1706
## #FFA51F (about 2000 K high-pressure sodium).
const SODIUM := Color(1.0, 0.647, 0.122)
const DAYLIGHT_COLOR := Color(0.80, 0.88, 1.0)
const BEACON_COLOR := Color(1.0, 0.62, 0.08)
const BEACON_RADIUS := 7.3
const BEACON_SPIN := TAU * 1.5
const SIGN_PSI := 90.0
const SIGN_SLOTS := 4
const WIRE_RADIUS := 0.022
const WIRE_REACH := 60.0
## The real lights follow the lamp row nearest to this height above the deck.
const LIGHT_FOCUS := 1.5
## The iris opens by folding every blade down about the tangent through its pivot (the hinge
## under the collar lip, r 7.10). Folded past vertical, a blade lies behind the concrete in the
## wall pocket, so nothing of it shows outside the collar or above the floor.
const IRIS_FOLD := 1.6057 # 92 deg
const FAR := 1.0e6
## The bottomless plug continues the shaft this far below the lowest tile.
const PLUG_DEPTH := 40.0

var quality := GraphicsQualityRules.BALANCED
var lamp_strength := 3.8
var fog_density := 0.032

var _built := false
var _deck_y := 0.0
var _scroll := 0.0
var _tiles_base := 0.0
var _clip_top := FAR
var _clip_bottom := -FAR
var _lamps_on := true
var _daylight := 0.0
var _speed := 0.0
var _beacons_on := false
var _beacon_phase := 0.0
var _mouth_visible := false
var _mouth_y := 0.0
var _iris := 0.0
var _last_xform := Transform3D()
var _vibration_time := 0.0

var _tiles: Node3D
var _tile_meshes: Array[MultiMeshInstance3D] = []
var _halos: MultiMeshInstance3D
var _cones: MultiMeshInstance3D
var _plug: MeshInstance3D
var _deck_root: Node3D
var _deck_body: Node3D
var _deck_anchors: Array[Vector3] = []
var _wires: Array[MeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
var _light_rows: Array[float] = []
var _mouth: Node3D
var _blades: Array[Dictionary] = []
var _beacons: Array[Dictionary] = []
var _day_spot: SpotLight3D
var _sky_disk: MeshInstance3D
var _day_cone: MeshInstance3D
var _day_cone_node: Node3D
var _dust: MultiMeshInstance3D
var _drips: MultiMeshInstance3D
var _signs: Array[Dictionary] = []
var _prewarm: Node3D

var _noise_texture: Texture2D
## Materials using shaft_common.gdshaderinc (scroll / clip / lamp uniforms).
var _shaft_materials: Array[ShaderMaterial] = []
var _mat_wall: ShaderMaterial
var _mat_glass: ShaderMaterial
var _mat_halo: ShaderMaterial
var _mat_cone: ShaderMaterial
var _mat_day_cone: ShaderMaterial
var _mat_dust: ShaderMaterial
var _mat_drips: ShaderMaterial
var _mat_sky: ShaderMaterial
var _mat_lens: ShaderMaterial
var _mat_grating: ShaderMaterial


func _ready() -> void:
	if not _built:
		setup(quality)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_on_frame_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_frame_pre_draw)


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(_on_frame_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)


## GraphicsQuality string. Builds everything on the first call; later calls only change the
## quality-dependent parts (particle counts, cones, daylight shadow).
func setup(new_quality: String) -> void:
	quality = GraphicsQualityRules.normalize(new_quality)
	if not _built:
		_build()
		_built = true
	_apply_quality()
	set_view(_deck_y, _scroll)
	_push_common()


# =================================================================== public API
## Deck top at local y = deck_y. The wall pattern is shifted UP by `scroll` metres.
func set_view(deck_y: float, scroll: float) -> void:
	_deck_y = deck_y
	_scroll = scroll
	if not _built:
		return
	var s := fposmod(scroll, TILE_HEIGHT)
	var deck_tile := floorf((deck_y - s) / TILE_HEIGHT)
	_tiles_base = s + (deck_tile - float(TILE_COUNT - TILES_ABOVE)) * TILE_HEIGHT
	_tiles.position = Vector3(0.0, _tiles_base, 0.0)
	_update_plug()
	_deck_root.position = Vector3(0.0, deck_y, 0.0)
	_dust.position = Vector3(0.0, deck_y, 0.0)
	_drips.position = Vector3(0.0, deck_y, 0.0)
	_set_common("scroll", scroll)
	for m: ShaderMaterial in [_mat_dust, _mat_drips]:
		m.set_shader_parameter("deck_y", deck_y)
	_update_lights()
	_update_wires()


## Walls only between bottom_y and top_y (local). top_y = surface mouth, bottom_y = cistern
## ceiling top (-INF = bottomless).
func set_clip(top_y: float, bottom_y: float) -> void:
	_clip_top = clampf(top_y, -FAR, FAR)
	_clip_bottom = clampf(bottom_y, -FAR, FAR)
	if not _built:
		return
	_set_common("clip_top", _clip_top)
	_set_common("clip_bottom", _clip_bottom)
	_update_plug()
	_sky_disk.position.y = _clip_top + 0.02
	_day_spot.position.y = _clip_top + 1.0
	_day_cone_node.position.y = _clip_top
	_update_lights()
	_update_wires()
	_update_signs()


func set_mouth(mouth_visible: bool, mouth_y: float, iris_open: float) -> void:
	_mouth_visible = mouth_visible
	_mouth_y = mouth_y
	_iris = clampf(iris_open, 0.0, 1.0)
	if not _built:
		return
	_mouth.visible = mouth_visible
	_mouth.position = Vector3(0.0, mouth_y, 0.0)
	_set_common("mouth_y", mouth_y)
	var fold := IRIS_FOLD * smoothstep(0.0, 1.0, _iris)
	for blade: Dictionary in _blades:
		var node := blade.node as Node3D
		var rest: Transform3D = blade.rest
		var tangent: Vector3 = blade.tangent
		# Rotating about the tangent (dir x up) by +fold turns the inward side downward.
		node.transform = Transform3D(Basis(tangent, fold) * rest.basis, rest.origin)
	for beacon: Dictionary in _beacons:
		(beacon.light as SpotLight3D).visible = mouth_visible and _beacons_on


func set_beacons(on: bool) -> void:
	_beacons_on = on
	if not _built:
		return
	_mat_lens.set_shader_parameter("on", 1.0 if on else 0.0)
	_set_common("beacons_on", 1.0 if on else 0.0)
	for beacon: Dictionary in _beacons:
		(beacon.light as SpotLight3D).visible = on and _mouth_visible
	_update_beacons(0.0)


## Daylight from the opening above (0..1): a cool spot down the shaft + the bright sky disk.
func set_daylight(amount: float) -> void:
	_daylight = clampf(amount, 0.0, 1.0)
	if not _built:
		return
	_set_common("daylight", _daylight)
	_day_spot.visible = _daylight > 0.001
	_day_spot.light_energy = 7.0 * _daylight
	_sky_disk.visible = _daylight > 0.001
	_mat_sky.set_shader_parameter("intensity", 5.0 * _daylight)
	_day_cone.visible = _daylight > 0.001
	_mat_day_cone.set_shader_parameter("cone_strength", _day_cone_strength() * _daylight)


## Signed deck speed in m/s (+ = descending).
func set_motion_speed(speed: float) -> void:
	_speed = speed
	if _built:
		_set_common("motion_speed", speed)


## Array of {"y": float (local), "text": String}; up to 4 are shown.
func set_depth_signs(signs: Array) -> void:
	if not _built:
		return
	for i in range(SIGN_SLOTS):
		var slot: Dictionary = _signs[i]
		if i < signs.size() and signs[i] is Dictionary:
			var entry: Dictionary = signs[i]
			slot.y = float(entry.get("y", 0.0))
			slot.text = str(entry.get("text", ""))
			slot.used = true
			(slot.label as Label3D).text = slot.text
		else:
			slot.used = false
	_update_signs()


func get_deck() -> Node3D:
	return _deck_root


func set_deck_visible(v: bool) -> void:
	if _deck_root != null:
		_deck_root.visible = v
		for wire: MeshInstance3D in _wires:
			wire.visible = v and wire.get_meta("in_range", false)


func set_lamps_enabled(on: bool) -> void:
	_lamps_on = on
	if not _built:
		return
	_set_common("lamps_on", 1.0 if on else 0.0)
	_update_lights()


## The shaft look: black background, distance fog (volumetric on balanced+), glow, AgX.
## The director animates tonemap_exposure (base exposure 1.0).
static func make_environment(env_quality: String) -> Environment:
	var q := GraphicsQualityRules.normalize(env_quality)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.20, 0.10)
	env.ambient_light_energy = 0.10
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level in range(7):
		env.set_glow_level(level, [0.0, 0.5, 0.8, 1.0, 1.0, 0.7, 0.0][level])
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.050, 0.030, 0.014)
	env.fog_light_energy = 1.0
	env.fog_density = 0.030
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.0
	if q != GraphicsQualityRules.LOW:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.010
		env.volumetric_fog_albedo = Color(0.86, 0.80, 0.72)
		env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
		env.volumetric_fog_anisotropy = 0.45
		env.volumetric_fog_length = 40.0 if q == GraphicsQualityRules.BALANCED else 64.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_gi_inject = 0.0
		env.volumetric_fog_ambient_inject = 0.0
		env.volumetric_fog_sky_affect = 0.0
		env.volumetric_fog_temporal_reprojection_enabled = true
	if GraphicsQualityRules.is_at_least(q, GraphicsQualityRules.HIGH):
		env.ssao_enabled = true
		env.ssao_radius = 1.0
		env.ssao_intensity = 1.6
		env.ssao_power = 1.4
	if q == GraphicsQualityRules.ULTRA:
		env.ssil_enabled = true
		env.ssil_radius = 3.0
		env.ssil_intensity = 0.6
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.0
	return env


## Puts a compact copy of every mesh/material of the shaft in front of `camera` so all
## pipelines compile while the caller renders a few frames. Call end_render_prewarm() after.
func begin_render_prewarm(camera: Camera3D) -> Dictionary:
	var started := Time.get_ticks_usec()
	end_render_prewarm()
	if not _built or camera == null:
		return {"ready": false, "items": 0, "elapsed_msec": 0.0}
	_prewarm = Node3D.new()
	_prewarm.name = "ShaftPrewarm"
	camera.add_child(_prewarm)
	_prewarm.position = Vector3(0.0, 0.0, -3.0)
	var items := 0
	var sources: Array[Node] = []
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		sources.append(node)
	var count := maxi(1, sources.size())
	for i in range(sources.size()):
		var src := sources[i] as GeometryInstance3D
		var copy: GeometryInstance3D = null
		if src is MultiMeshInstance3D:
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = (src as MultiMeshInstance3D).multimesh
			copy = mmi
		elif src is MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.mesh = (src as MeshInstance3D).mesh
			for s in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
				var override := (src as MeshInstance3D).get_surface_override_material(s)
				if override != null:
					mi.set_surface_override_material(s, override)
			copy = mi
		elif src is Label3D:
			var label := Label3D.new()
			label.text = "-0m"
			label.font = SIGN_FONT
			label.font_size = (src as Label3D).font_size
			label.pixel_size = 0.0005
			copy = label
		if copy == null:
			continue
		copy.material_override = src.material_override
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.extra_cull_margin = 16384.0
		var angle := TAU * float(i) / float(count)
		copy.position = Vector3(cos(angle) * 0.6, sin(angle) * 0.35, 0.0)
		copy.scale = Vector3.ONE * 0.004
		_prewarm.add_child(copy)
		items += 1
	return {"ready": items > 0, "items": items, "elapsed_msec": float(Time.get_ticks_usec() - started) / 1000.0}


func end_render_prewarm() -> void:
	if is_instance_valid(_prewarm):
		_prewarm.queue_free()
	_prewarm = null


func get_debug_snapshot() -> Dictionary:
	var lights: Array = []
	for light: OmniLight3D in _lights:
		lights.append({"y": snappedf(light.position.y, 0.001), "energy": snappedf(light.light_energy, 0.001), "visible": light.visible})
	var wires: Array = []
	for wire: MeshInstance3D in _wires:
		wires.append({"visible": wire.visible, "bottom": snappedf(wire.position.y - wire.scale.y * 0.5, 0.001), "top": snappedf(wire.position.y + wire.scale.y * 0.5, 0.001)})
	var signs: Array = []
	for slot: Dictionary in _signs:
		signs.append({"text": slot.text, "y": slot.y, "visible": (slot.node as Node3D).visible})
	return {
		"built": _built,
		"quality": quality,
		"deck_y": _deck_y,
		"scroll": _scroll,
		"tiles_base": _tiles_base,
		"tiles_range": [_tiles_base, _tiles_base + TILE_HEIGHT * TILE_COUNT],
		"clip": [_clip_top, _clip_bottom],
		"mouth": {"visible": _mouth_visible, "y": _mouth_y, "iris_open": _iris},
		"beacons": _beacons_on,
		"daylight": _daylight,
		"lamps_on": _lamps_on,
		"motion_speed": _speed,
		"lights": lights,
		"wires": wires,
		"signs": signs,
		"dust": _dust.multimesh.instance_count if _dust != null else 0,
		"drips": _drips.multimesh.instance_count if _drips != null else 0,
		"deck_visible": _deck_root.visible if _deck_root != null else false,
		"bottomless_plug": _plug.visible if _plug != null else false,
	}


# =================================================================== frame updates
func _process(delta: float) -> void:
	if not _built:
		return
	if _beacons_on:
		_beacon_phase = fposmod(_beacon_phase + BEACON_SPIN * delta, TAU)
		_update_beacons(delta)
	# Hoist vibration: a millimetre buzz of the deck body (not of get_deck(), whose children
	# must sit exactly on y = 0).
	_vibration_time += delta
	var buzz := clampf(absf(_speed) / 10.0, 0.0, 1.0)
	if _deck_body != null:
		_deck_body.position = Vector3(
			sin(_vibration_time * 71.0) * 0.0012 * buzz,
			sin(_vibration_time * 53.0 + 0.7) * 0.0010 * buzz,
			sin(_vibration_time * 61.0 + 1.9) * 0.0012 * buzz)


func _on_frame_pre_draw() -> void:
	if not _built or not is_inside_tree():
		return
	var xform := global_transform
	if xform != _last_xform:
		_last_xform = xform
		var inv := Projection(xform.affine_inverse())
		var fwd := Projection(xform)
		for m: ShaderMaterial in _shaft_materials:
			m.set_shader_parameter("shaft_inv", inv)
		for m: ShaderMaterial in [_mat_dust, _mat_drips]:
			m.set_shader_parameter("shaft_xform", fwd)


func _set_common(param: StringName, value: Variant) -> void:
	for m: ShaderMaterial in _shaft_materials:
		m.set_shader_parameter(param, value)


func _push_common() -> void:
	var lamp_lin := SODIUM.srgb_to_linear()
	_set_common("lamp_color", Vector3(lamp_lin.r, lamp_lin.g, lamp_lin.b))
	_set_common("lamp_strength", lamp_strength)
	var day_lin := DAYLIGHT_COLOR.srgb_to_linear()
	_set_common("daylight_color", Vector3(day_lin.r, day_lin.g, day_lin.b))
	_set_common("scroll", _scroll)
	_set_common("clip_top", _clip_top)
	_set_common("clip_bottom", _clip_bottom)
	_set_common("lamps_on", 1.0 if _lamps_on else 0.0)
	_set_common("daylight", _daylight)
	_set_common("mouth_y", _mouth_y)
	_set_common("beacons_on", 1.0 if _beacons_on else 0.0)
	_set_common("motion_speed", _speed)
	_last_xform = Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	if is_inside_tree():
		_on_frame_pre_draw()


func _update_lights() -> void:
	var s := fposmod(_scroll, TILE_HEIGHT)
	var focus := _deck_y + LIGHT_FOCUS
	var centre := roundf((focus - s - LAMP_Y) / TILE_HEIGHT)
	for row in range(3):
		var y := s + LAMP_Y + (centre + float(row - 1)) * TILE_HEIGHT
		var weight := smoothstep(7.5, 5.0, absf(y - focus))
		if y > _clip_top or y < _clip_bottom or not _lamps_on:
			weight = 0.0
		for k in range(4):
			var light := _lights[row * 4 + k]
			var a := deg_to_rad(LAMP_PSI[k])
			light.position = Vector3(cos(a) * (LAMP_RADIUS - 0.1), y, sin(a) * (LAMP_RADIUS - 0.1))
			light.light_energy = lamp_strength * 1.25 * weight
			light.visible = weight > 0.001


## Shown while the shaft is bottomless below the tile window; hidden once the cistern ceiling
## (bottom_y) is inside the window.
func _update_plug() -> void:
	if _plug != null:
		_plug.visible = _clip_bottom < _tiles_base - 0.01


func _update_wires() -> void:
	var top := minf(_clip_top, _deck_y + WIRE_REACH)
	for i in range(_wires.size()):
		var wire := _wires[i]
		var anchor := _deck_anchors[i]
		var y0 := _deck_y + anchor.y
		var in_range := top > y0 + 0.05
		wire.set_meta("in_range", in_range)
		wire.visible = in_range and _deck_root.visible
		if in_range:
			wire.position = Vector3(anchor.x, (y0 + top) * 0.5, anchor.z)
			wire.scale = Vector3(1.0, top - y0, 1.0)


func _update_signs() -> void:
	for slot: Dictionary in _signs:
		var node := slot.node as Node3D
		var y: float = slot.y
		node.visible = bool(slot.used) and y < _clip_top - 0.5 and y > _clip_bottom + 0.5
		node.position = Vector3(cos(deg_to_rad(SIGN_PSI)) * INNER_RADIUS, y, sin(deg_to_rad(SIGN_PSI)) * INNER_RADIUS)


func _update_beacons(_delta: float) -> void:
	var angles := Vector4.ZERO
	var inv := global_transform.affine_inverse()
	for i in range(_beacons.size()):
		var beacon: Dictionary = _beacons[i]
		var reflector := beacon.reflector as Node3D
		reflector.rotation.y = float(beacon.phase) + _beacon_phase
		var dir_world := reflector.global_transform.basis.x
		var dir_local := inv.basis * dir_world
		var azimuth := atan2(dir_local.z, dir_local.x)
		angles[i] = azimuth
		(beacon.lens as GeometryInstance3D).set_instance_shader_parameter("beam_angle", atan2(dir_world.z, dir_world.x))
	_set_common("beacon_angles", angles)


func _day_cone_strength() -> float:
	return 0.10 if quality == GraphicsQualityRules.LOW else 0.035


# =================================================================== building
func _build() -> void:
	_noise_texture = _make_noise()
	_build_materials()
	_build_tiles()
	_build_deck()
	_build_wires()
	_build_lights()
	_build_mouth()
	_build_daylight()
	_build_motes()
	_build_signs()


func _make_noise() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.seed = 4127
	var image := noise.get_seamless_image(256, 256, false, false, 0.12, true)
	image.convert(Image.FORMAT_L8)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _shader_material(shader: Shader, shaft: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	if shaft:
		_shaft_materials.append(m)
	return m


func _prop_material(color: Color, rough: float, metal: float, grime: float, mode := 0) -> ShaderMaterial:
	var m := _shader_material(PROP_SHADER, true)
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("grime", grime)
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("wall_light", WALL_LIGHT)
	m.set_shader_parameter("macro_noise", _noise_texture)
	m.set_shader_parameter("light_max", LIGHT_MAX_OVER_C)
	return m


func _build_materials() -> void:
	_mat_wall = _shader_material(WALL_SHADER, true)
	_mat_wall.set_shader_parameter("wall_masks", WALL_MASKS)
	_mat_wall.set_shader_parameter("wall_normal", WALL_NORMAL)
	_mat_wall.set_shader_parameter("wall_light", WALL_LIGHT)
	_mat_wall.set_shader_parameter("detail_normal", DETAIL_NORMAL)
	_mat_wall.set_shader_parameter("macro_noise", _noise_texture)
	_mat_wall.set_shader_parameter("light_max", LIGHT_MAX_OVER_C)
	_mat_glass = _shader_material(GLASS_SHADER, true)
	_mat_halo = _shader_material(HALO_SHADER, true)
	_mat_cone = _shader_material(CONE_SHADER, true)
	_mat_day_cone = _shader_material(CONE_SHADER, true)
	_mat_dust = _shader_material(MOTES_SHADER, true)
	_mat_dust.set_shader_parameter("kind", 0)
	_mat_drips = _shader_material(MOTES_SHADER, true)
	_mat_drips.set_shader_parameter("kind", 1)
	_mat_drips.set_shader_parameter("particle_size", 0.012)
	_mat_drips.set_shader_parameter("strength", 1.6)
	_mat_drips.set_shader_parameter("window_height", 24.0)
	_mat_drips.set_shader_parameter("window_below", 8.0)
	_mat_sky = _shader_material(SKY_SHADER, false)
	_mat_lens = _shader_material(LENS_SHADER, false)
	for m: ShaderMaterial in [_mat_halo, _mat_cone, _mat_day_cone, _mat_dust, _mat_drips]:
		m.set_shader_parameter("fog_density", fog_density)
	var day_lin := DAYLIGHT_COLOR.srgb_to_linear()
	_mat_day_cone.set_shader_parameter("tint_override", Vector3(day_lin.r, day_lin.g, day_lin.b))
	_mat_grating = _shader_material(GRATING_SHADER, false)
	_mat_grating.set_shader_parameter("macro_noise", _noise_texture)
	_mat_grating.set_shader_parameter("pad_x", SuddenDeathLayout.PAD_X)


func _mesh_by_name(root: Node, node_name: String) -> MeshInstance3D:
	return root.find_child(node_name, true, false) as MeshInstance3D


func _no_shadow(node: GeometryInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _build_tiles() -> void:
	_tiles = Node3D.new()
	_tiles.name = "Tiles"
	add_child(_tiles)
	var scene := TILE_SCENE.instantiate()
	var roles := {
		"SHD_Tile_Wall": _mat_wall,
		"SHD_Tile_Rails": _prop_material(Color(0.33, 0.35, 0.34), 0.5, 0.0, 0.55),
		"SHD_Tile_Galv": _prop_material(Color(0.62, 0.63, 0.62), 0.38, 1.0, 0.45),
		"SHD_Tile_Cables": _prop_material(Color(0.035, 0.035, 0.04), 0.55, 0.0, 0.2),
		"SHD_Tile_LampBody": _prop_material(Color(0.52, 0.52, 0.49), 0.45, 0.25, 0.35),
		"SHD_Tile_LampGlass": _mat_glass,
	}
	for mesh_name: String in roles.keys():
		var source := _mesh_by_name(scene, mesh_name)
		if source == null:
			push_warning("ShaftDescent: %s missing in shaft_tile.glb" % mesh_name)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = source.mesh
		mm.instance_count = TILE_COUNT
		for i in range(TILE_COUNT):
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, TILE_HEIGHT * float(i), 0.0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = mesh_name.trim_prefix("SHD_Tile_")
		mmi.multimesh = mm
		mmi.material_override = roles[mesh_name]
		_no_shadow(mmi)
		_tiles.add_child(mmi)
		_tile_meshes.append(mmi)
	scene.free()
	# Halo sprites and light cones: one per lamp of every tile.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_halos = _lamp_multimesh("Halos", quad, _mat_halo, 6.42, 0.0)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.07
	cone.bottom_radius = 0.95
	cone.height = 3.4
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_cones = _lamp_multimesh("Cones", cone, _mat_cone, 6.1, -1.85)
	_build_plug()


func _build_plug() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 48
	var r := INNER_RADIUS + 0.02
	for i in range(segments):
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var top0 := Vector3(cos(a0) * r, 0.02, sin(a0) * r)
		var top1 := Vector3(cos(a1) * r, 0.02, sin(a1) * r)
		var bot0 := Vector3(cos(a0) * r, -PLUG_DEPTH, sin(a0) * r)
		var bot1 := Vector3(cos(a1) * r, -PLUG_DEPTH, sin(a1) * r)
		# inward-facing wall (seen from inside the shaft)
		for v: Vector3 in [top0, top1, bot1, top0, bot1, bot0]:
			st.add_vertex(v)
		# floor far below, facing up
		for v: Vector3 in [Vector3(0.0, -PLUG_DEPTH, 0.0), bot0, bot1]:
			st.add_vertex(v)
	st.generate_normals()
	var material := ShaderMaterial.new()
	material.shader = PLUG_SHADER
	_plug = MeshInstance3D.new()
	_plug.name = "BottomlessPlug"
	_plug.mesh = st.commit()
	_plug.material_override = material
	_no_shadow(_plug)
	_tiles.add_child(_plug)


func _lamp_multimesh(node_name: String, mesh: Mesh, material: Material, radius: float, y_offset: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = TILE_COUNT * LAMP_PSI.size()
	for i in range(TILE_COUNT):
		for k in range(LAMP_PSI.size()):
			var a := deg_to_rad(LAMP_PSI[k])
			var p := Vector3(cos(a) * radius, TILE_HEIGHT * float(i) + LAMP_Y + y_offset, sin(a) * radius)
			mm.set_instance_transform(i * LAMP_PSI.size() + k, Transform3D(Basis.IDENTITY, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	_no_shadow(mmi)
	_tiles.add_child(mmi)
	return mmi


func _standard(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.5
	return m


func _build_deck() -> void:
	_deck_root = Node3D.new()
	_deck_root.name = "Deck"
	add_child(_deck_root)
	_deck_body = Node3D.new()
	_deck_body.name = "DeckBody"
	_deck_root.add_child(_deck_body)
	var scene := DECK_SCENE.instantiate() as Node3D
	scene.name = "DeckModel"
	_deck_body.add_child(scene)
	var hazard := _shader_material(HAZARD_SHADER, false)
	hazard.set_shader_parameter("mode", 0)
	hazard.set_shader_parameter("stripe_radius", 5.1)
	hazard.set_shader_parameter("macro_noise", _noise_texture)
	var looks := {
		"SHD_Deck_Grating": _mat_grating,
		"SHD_Deck_Band": hazard,
		"SHD_Deck_Frame": _standard(Color(0.075, 0.08, 0.085), 0.55, 0.3),
		"SHD_Deck_PadPlate": _standard(Color(0.22, 0.225, 0.23), 0.42, 0.75),
		"SHD_Deck_Metal": _standard(Color(0.55, 0.56, 0.56), 0.4, 1.0),
	}
	for mesh_name: String in looks.keys():
		var mi := _mesh_by_name(scene, mesh_name)
		if mi == null:
			push_warning("ShaftDescent: %s missing in shaft_deck.glb" % mesh_name)
			continue
		mi.material_override = looks[mesh_name]
		_no_shadow(mi)
	_deck_anchors.clear()
	for k in range(4):
		var anchor := scene.find_child("SHD_Deck_WireAnchor_%d" % k, true, false) as Node3D
		if anchor != null:
			_deck_anchors.append(_accumulated_origin(anchor, scene))
		else:
			var a := deg_to_rad(45.0 + 90.0 * k)
			_deck_anchors.append(Vector3(cos(a) * 4.4, 0.30, sin(a) * 4.4))


func _accumulated_origin(node: Node3D, root: Node3D) -> Vector3:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform.origin


func _build_wires() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = WIRE_RADIUS
	mesh.bottom_radius = WIRE_RADIUS
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var material := _prop_material(Color(0.42, 0.42, 0.41), 0.32, 1.0, 0.1, 2)
	for i in range(4):
		var wire := MeshInstance3D.new()
		wire.name = "Wire%d" % i
		wire.mesh = mesh
		wire.material_override = material
		wire.extra_cull_margin = 2.0
		_no_shadow(wire)
		add_child(wire)
		_wires.append(wire)


func _build_lights() -> void:
	for i in range(12):
		var light := OmniLight3D.new()
		light.name = "Lamp%d" % i
		light.light_color = SODIUM
		light.omni_range = 11.0
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.light_specular = 0.6
		light.light_volumetric_fog_energy = 0.9
		add_child(light)
		_lights.append(light)


func _build_mouth() -> void:
	_mouth = Node3D.new()
	_mouth.name = "Mouth"
	add_child(_mouth)
	_mouth.visible = false
	var scene := MOUTH_SCENE.instantiate() as Node3D
	scene.name = "MouthModel"
	_mouth.add_child(scene)
	var collar := _shader_material(HAZARD_SHADER, false)
	collar.set_shader_parameter("mode", 0)
	collar.set_shader_parameter("stripe_radius", 7.3)
	collar.set_shader_parameter("macro_noise", _noise_texture)
	var blade_mat := _shader_material(HAZARD_SHADER, false)
	blade_mat.set_shader_parameter("mode", 1)
	blade_mat.set_shader_parameter("macro_noise", _noise_texture)
	var looks := {
		"SHD_Mouth_Collar": collar,
		"SHD_Mouth_Liner": _standard(Color(0.13, 0.13, 0.13), 0.5, 0.5),
	}
	for mesh_name: String in looks.keys():
		var mi := _mesh_by_name(scene, mesh_name)
		if mi != null:
			mi.material_override = looks[mesh_name]
			_no_shadow(mi)
	for i in range(8):
		var blade := _mesh_by_name(scene, "SHD_Blade_%d" % i)
		if blade == null:
			continue
		blade.material_override = blade_mat
		_no_shadow(blade)
		var rest := blade.transform
		var dir := Vector3(rest.origin.x, 0.0, rest.origin.z).normalized()
		_blades.append({"node": blade, "rest": rest, "dir": dir, "tangent": dir.cross(Vector3.UP).normalized()})
	var base_mat := _standard(Color(0.80, 0.52, 0.03), 0.45, 0.0)
	var reflector_mat := _standard(Color(0.92, 0.92, 0.92), 0.08, 1.0)
	reflector_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in range(4):
		var base := _mesh_by_name(scene, "SHD_Beacon_%d" % k)
		var lens := _mesh_by_name(scene, "SHD_Beacon_%d_Lens" % k)
		var reflector := _mesh_by_name(scene, "SHD_Beacon_%d_Reflector" % k)
		if base == null or lens == null or reflector == null:
			continue
		base.material_override = base_mat
		lens.material_override = _mat_lens
		reflector.material_override = reflector_mat
		for g: GeometryInstance3D in [base, lens, reflector]:
			_no_shadow(g)
		var light := SpotLight3D.new()
		light.name = "BeaconLight"
		light.light_color = BEACON_COLOR
		light.light_energy = 9.0
		light.spot_range = 18.0
		light.spot_angle = 24.0
		light.spot_attenuation = 1.2
		light.shadow_enabled = false
		light.light_volumetric_fog_energy = 2.0
		light.position = Vector3(0.0, 0.19, 0.0)
		light.rotation = Vector3(deg_to_rad(-6.0), deg_to_rad(-90.0), 0.0)
		light.visible = false
		reflector.add_child(light)
		_beacons.append({"base": base, "lens": lens, "reflector": reflector, "light": light, "phase": TAU * 0.27 * float(k)})


func _build_daylight() -> void:
	_day_spot = SpotLight3D.new()
	_day_spot.name = "Daylight"
	_day_spot.light_color = DAYLIGHT_COLOR
	_day_spot.spot_range = 70.0
	_day_spot.spot_angle = 40.0
	_day_spot.spot_attenuation = 0.9
	_day_spot.spot_angle_attenuation = 1.6
	_day_spot.light_volumetric_fog_energy = 1.6
	_day_spot.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_day_spot.visible = false
	add_child(_day_spot)
	# Sky disk: faces down, so it shows only from inside the shaft.
	var disk := ArrayMesh.new()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var segments := 64
	for i in range(segments):
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		for p: Vector2 in [Vector2.ZERO, Vector2(cos(a1), sin(a1)), Vector2(cos(a0), sin(a0))]:
			verts.append(Vector3(p.x * INNER_RADIUS, 0.0, p.y * INNER_RADIUS))
			normals.append(Vector3.DOWN)
			uvs.append(p * 0.5 + Vector2(0.5, 0.5))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	disk.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_sky_disk = MeshInstance3D.new()
	_sky_disk.name = "SkyDisk"
	_sky_disk.mesh = disk
	_sky_disk.material_override = _mat_sky
	_sky_disk.visible = false
	_no_shadow(_sky_disk)
	add_child(_sky_disk)
	# Daylight shaft through the mist (the visible beam on low quality, a faint one elsewhere).
	var cone := CylinderMesh.new()
	cone.top_radius = 6.6
	cone.bottom_radius = 4.2
	cone.height = 30.0
	cone.radial_segments = 32
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_day_cone = MeshInstance3D.new()
	_day_cone.name = "DaylightCone"
	_day_cone.mesh = cone
	_day_cone.material_override = _mat_day_cone
	_day_cone.visible = false
	_no_shadow(_day_cone)
	_day_cone_node = Node3D.new()
	_day_cone_node.name = "DaylightBeam"
	add_child(_day_cone_node)
	_day_cone_node.add_child(_day_cone)
	# The beam hangs from the opening (set_clip moves the holder to top_y).
	_day_cone.position = Vector3(0.0, -15.0, 0.0)


func _build_motes() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_dust = _motes_instance("Dust", quad, _mat_dust)
	_drips = _motes_instance("Drips", quad, _mat_drips)


func _motes_instance(node_name: String, mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.custom_aabb = AABB(Vector3(-8.0, -14.0, -8.0), Vector3(16.0, 34.0, 16.0))
	_no_shadow(mmi)
	add_child(mmi)
	return mmi


func _set_mote_count(mmi: MultiMeshInstance3D, count: int) -> void:
	var mm := mmi.multimesh
	if mm.instance_count == count:
		return
	mm.instance_count = count
	for i in range(count):
		mm.set_instance_transform(i, Transform3D.IDENTITY)


func _build_signs() -> void:
	for i in range(SIGN_SLOTS):
		var node := SIGN_SCENE.instantiate() as Node3D
		node.name = "DepthSign%d" % i
		add_child(node)
		node.visible = false
		var face := _prop_material(Color(0.80, 0.78, 0.70), 0.3, 0.0, 0.35, 1)
		var frame := _prop_material(Color(0.06, 0.06, 0.065), 0.5, 0.3, 0.4)
		var board := _mesh_by_name(node, "SHD_Sign_Board")
		var frame_mesh := _mesh_by_name(node, "SHD_Sign_Frame")
		if board != null:
			board.material_override = face
			_no_shadow(board)
		if frame_mesh != null:
			frame_mesh.material_override = frame
			_no_shadow(frame_mesh)
		var anchor := node.find_child("SHD_Sign_TextAnchor", true, false) as Node3D
		var label := Label3D.new()
		label.name = "Depth"
		label.font = SIGN_FONT
		label.font_size = 128
		label.pixel_size = 0.0034
		label.modulate = Color(0.045, 0.04, 0.035)
		label.outline_size = 0
		label.shaded = false
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.rotation = Vector3(0.0, PI, 0.0)
		label.position = (_accumulated_origin(anchor, node) if anchor != null else Vector3(0.0, 0.0, -0.13)) + Vector3(0.0, 0.0, -0.004)
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(label)
		_signs.append({"node": node, "label": label, "y": 0.0, "text": "", "used": false})


func _apply_quality() -> void:
	_set_mote_count(_dust, GraphicsQualityRules.particle_amount(320, quality))
	_set_mote_count(_drips, GraphicsQualityRules.particle_amount(90, quality))
	var low := quality == GraphicsQualityRules.LOW
	_mat_cone.set_shader_parameter("cone_strength", 0.16 if low else 0.05)
	_mat_halo.set_shader_parameter("halo_strength", 1.25 if low else 1.0)
	_mat_day_cone.set_shader_parameter("cone_strength", _day_cone_strength() * _daylight)
	_day_spot.shadow_enabled = not low
	_mat_wall.set_shader_parameter("detail_strength", 0.35 if low else 0.6)
