class_name SurfaceDrain
extends Node3D

## 海沿いの排水口（docs/sudden_death_underground.md 2.3、6.0秒）。サドンデスの敗者は、地表の
## 桟橋（コンベアの床）の側壁にある排水口から水柱で噴き出し、沈んだ自分の台座へ落ちる。
##
## 形：桟橋の側壁に埋め込んだコンクリートの暗渠の吐口（頭壁・笠石・円形の口・奥の闇）と、
## 上端に蝶番のある鋼製の格子フラップ。口の下の壁には濡れた染みと水際の藻。
## 噴出：フラップが跳ね上がり、口から噴き出した水が壁の外で真上へ曲がり、放物線を描いて
## 桟橋の上へ倒れ込む水柱になる（泡の管2本＋同じ弾道の筋の粒子）。口からの横向きの飛沫、
## 頂部の水しぶき・霧・床へ落ちる水滴、海面の波紋と水しぶき。約1.25秒立ってから尾が上へ
## 抜けるように崩れ、口からの流れが海へ落ちて収まる。camera_shake() を呼び出し側が読む。
## 敗者の動きは呼び出し側が mouth_position() → column_point() の弧に沿わせて台座へ落とす。
##
## ローカル座標：+X が海側（壁の外向き）、+Y が上、原点は床の天面の高さで、側壁の線から
## INSET だけ内側。P1（side +1）は +X 側、P2（side −1）は −X 側（Y軸まわりに半回転）。

const QualityRules = preload("res://scripts/core/graphics_quality.gd")

## The drain's origin sits this far inside the pier's side wall: x = ±(FLOOR_HALF_WIDTH − INSET).
const INSET := 0.25
## Pier side wall (the floor box's side face) and the headwall face, local x.
const WALL_X := INSET
const FACE_X := INSET + 0.42
## Outlet (round culvert mouth), local y below the floor top.
const MOUTH_Y := -2.3
const MOUTH_RADIUS := 0.78
const HEADWALL_TOP := -0.5
const HEADWALL_BOTTOM := -4.05
const HEADWALL_HALF_Z := 1.7
## Flap hinge just above the mouth, on the headwall face.
const HINGE_OFFSET := Vector3(0.09, MOUTH_RADIUS + 0.1, 0.0)
## The jet turns up just off the headwall and flies a ballistic arc back over the pier: apex ~8 m
## above the floor ~6.5 m inside the pier edge, the tip ~7 m up over the loser's pad (x ±2.2..2.8).
## Kept low and inboard so a front camera ~10 m from the podium at ~6 m height frames all of it.
const ARC_BASE := Vector2(2.3, -2.15)
const ARC_VELOCITY := Vector2(-6.48, 14.94)
const ARC_GRAVITY := 11.0
const ARC_DURATION := 1.75
const ARC_SAMPLES := 30

# Timeline (seconds after erupt()).
const RISE_START := 0.02
const RISE_END := 0.55
const HOLD_END := 1.25
const COLLAPSE_END := 1.9
const SETTLE_END := 3.4
const SHAKE_TIME := 0.9
const FLAP_OPEN := 2.85
const FLAP_HOLD := 2.45
const FLAP_REST := 0.35

## Base particle counts (HIGH/ULTRA); scaled by GraphicsQuality.particle_amount.
const BASE_AMOUNTS := {
	"burst": 80, "streaks": 320, "spray": 140, "crown": 90, "droplets": 240, "mist": 28, "splash": 100,
}
## [start time, particle node key]: one-shot bursts restarted at these times.
const EMIT_SCHEDULE := [
	[0.0, "burst"], [0.02, "streaks"], [0.08, "splash"], [0.18, "spray"], [0.22, "mist"],
	[0.42, "crown"], [0.5, "droplets"],
]

const NOISE_FUNCTIONS := """
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}
"""

## Foamy water tube (UV.x around, UV.y along 0..1, UV2.x radius): flowing streaks, soft ragged
## silhouette, more break-up toward the tip; reveal_top / reveal_bottom grow and drain it along the path.
const WATER_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.93, 0.97, 1.0, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.5, 0.7, 0.78, 1.0);
uniform float flow_speed = 12.0;
uniform float length_m = 20.0;
uniform float reveal_top : hint_range(0.0, 1.2) = 1.0;
uniform float reveal_bottom : hint_range(0.0, 1.2) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float density = 1.0;
uniform float breakup = 0.6;
uniform float wobble = 0.55;
uniform float seed = 0.0;

varying float along;
varying float around;
%s
void vertex() {
	along = UV.y;
	around = UV.x;
	float w = vnoise(vec3(around * 7.0 + seed, along * length_m * 0.45 - TIME * flow_speed * 0.35, seed * 0.37));
	VERTEX += NORMAL * UV2.x * (w - 0.5) * wobble;
}

void fragment() {
	float a = around * 6.2831853;
	vec3 p = vec3(cos(a) * 1.7, sin(a) * 1.7, along * length_m * 0.34 - TIME * flow_speed * 0.34) + seed;
	vec3 q = vec3(cos(a) * 3.4, sin(a) * 3.4, along * length_m * 0.16 - TIME * flow_speed * 0.16) + seed * 1.7;
	float n = vnoise(p) * 0.5 + vnoise(p * 2.2 + 7.1) * 0.3 + vnoise(p * 4.8 + 3.3) * 0.2;
	float s = vnoise(q) * 0.6 + vnoise(q * 2.7 + 1.3) * 0.4;
	float foam = smoothstep(0.35, 0.75, n);
	float streak = smoothstep(0.45, 0.85, s);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = smoothstep(0.03, 0.5, facing);
	float holes = smoothstep(breakup * along - 0.12, breakup * along + 0.22, n);
	float ragged = (n - 0.5) * 0.2;
	float reveal = smoothstep(reveal_bottom - 0.02, reveal_bottom + 0.07, along + ragged)
		* (1.0 - smoothstep(reveal_top - 0.08, reveal_top, along + ragged));
	float ends = smoothstep(0.0, 0.05, along) * (1.0 - smoothstep(0.84, 1.0, along + ragged));
	ALBEDO = mix(deep_tint.rgb, tint.rgb, clamp(0.3 + 0.5 * foam + 0.45 * streak, 0.0, 1.0));
	ROUGHNESS = 0.22;
	SPECULAR = 0.5;
	BACKLIGHT = vec3(0.55, 0.62, 0.66);
	EMISSION = tint.rgb * 0.07 * intensity;
	ALPHA = clamp((0.3 + 0.45 * foam + 0.4 * streak) * edge * holes * density * intensity * reveal * ends, 0.0, 1.0);
}
""" % NOISE_FUNCTIONS

## Velocity-aligned water streaks (particle Y follows the velocity; the quad turns to face the camera).
const STREAK_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec4 tint : source_color = vec4(0.9, 0.96, 1.0, 1.0);
uniform float opacity = 0.85;

void vertex() {
	vec3 axis = MODEL_MATRIX[1].xyz;
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - center);
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 side = cross(axis, to_cam);
	float side_len = length(side);
	side = side_len > 0.0001 ? side / side_len * width : INV_VIEW_MATRIX[0].xyz * width;
	vec3 facing = normalize(cross(side, axis));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(axis, 0.0), vec4(facing, 0.0), vec4(center, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float across = 1.0 - c.x * c.x;
	float taper = smoothstep(1.0, 0.45, abs(c.y)) * mix(1.0, 0.45, clamp(c.y, 0.0, 1.0));
	ALBEDO = tint.rgb * COLOR.rgb;
	BACKLIGHT = vec3(0.5);
	EMISSION = tint.rgb * 0.06;
	ALPHA = clamp(across * across * taper * COLOR.a * opacity, 0.0, 1.0);
}
"""

## Soft camera-facing puffs of spray and mist with a proximity fade against the pier.
const PUFF_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec4 tint : source_color = vec4(0.94, 0.97, 1.0, 1.0);
uniform float opacity = 0.7;
uniform float edge_noise = 0.5;
uniform float proximity_fade = 0.8;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying float v_seed;
%s
void vertex() {
	float angle = INSTANCE_CUSTOM.x;
	mat4 world = mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
	world = world * mat4(
		vec4(cos(angle), -sin(angle), 0.0, 0.0),
		vec4(sin(angle), cos(angle), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_seed = fract(float(INSTANCE_ID) * 0.61803);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float n = vnoise(vec3(UV * 3.2, v_seed * 17.0)) * 0.65 + vnoise(vec3(UV * 7.0, v_seed * 5.0 + 3.0)) * 0.35;
	float r = clamp(length(c) + (n - 0.5) * edge_noise, 0.0, 1.0);
	float a = pow(1.0 - r, 1.6) * (0.4 + 0.6 * n);
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float fade = clamp(1.0 - smoothstep(behind.z + proximity_fade, behind.z, VERTEX.z), 0.0, 1.0);
	ALBEDO = tint.rgb * COLOR.rgb * mix(0.85, 1.0, n);
	BACKLIGHT = vec3(0.55);
	EMISSION = tint.rgb * 0.05;
	ALPHA = clamp(a * COLOR.a * opacity * fade, 0.0, 1.0);
}
""" % NOISE_FUNCTIONS

## Expanding foam rings on the sea under the outlet (drawn over the transparent ocean).
const RING_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec4 tint : source_color = vec4(0.93, 0.97, 1.0, 1.0);
uniform float ring_a = 0.0;
uniform float ring_b = 0.0;
uniform float alpha_a = 0.0;
uniform float alpha_b = 0.0;
uniform float foam = 0.0;
uniform float half_size = 7.0;

varying vec2 plane;
%s
void vertex() {
	plane = VERTEX.xz;
}

void fragment() {
	float d = length(plane);
	float n = vnoise(vec3(plane * 2.4, TIME * 0.6)) * 0.6 + vnoise(vec3(plane * 6.0, 1.7)) * 0.4;
	float band_a = exp(-pow((d - ring_a) / (0.35 + ring_a * 0.08), 2.0)) * alpha_a;
	float band_b = exp(-pow((d - ring_b) / (0.3 + ring_b * 0.08), 2.0)) * alpha_b;
	float disc = (1.0 - smoothstep(0.0, max(ring_a * 0.85, 0.01), d)) * foam;
	float a = max(max(band_a, band_b), disc * 0.75) * smoothstep(0.25, 0.75, n + 0.25);
	a *= 1.0 - smoothstep(half_size * 0.8, half_size, d);
	ALBEDO = tint.rgb * mix(0.85, 1.0, n);
	ALPHA = clamp(a, 0.0, 1.0);
}
""" % NOISE_FUNCTIONS

static var _water_shader: Shader = null
static var _streak_shader: Shader = null
static var _puff_shader: Shader = null
static var _ring_shader: Shader = null

var _quality: String = QualityRules.BALANCED
var _side: int = 1
var _placed := false
var _built := false
var _erupting := false
var _time := 0.0
var _emitted: Dictionary = {}
var _water_y := StageConstants.OCEAN_SURFACE_Y - StageConstants.FLOOR_TOP_Y
## Column centreline (local) and its normalised arc length, 0 at the mouth, 1 at the tip.
var _path := PackedVector3Array()
var _path_s := PackedFloat32Array()

var _structure: Node3D
var _flap: Node3D
var _effects: Node3D
var _column: MeshInstance3D
var _core: MeshInstance3D
var _cascade: MeshInstance3D
var _ring: MeshInstance3D
var _floor_catcher: GPUParticlesCollisionBox3D
var _sea_catcher: GPUParticlesCollisionBox3D
var _water_materials: Dictionary = {}
var _ring_material: ShaderMaterial
var _particles: Dictionary = {}


func _ready() -> void:
	if not _built:
		setup(_quality)


## Builds the culvert and the eruption effects (and compiles their shaders); particle counts follow the
## quality tier. Call it while loading, e.g. when the draw is detected.
func setup(quality: String) -> void:
	_quality = QualityRules.normalize(quality) if not quality.is_empty() else QualityRules.BALANCED
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_water_materials.clear()
	_particles.clear()
	_structure = Node3D.new()
	_structure.name = "Culvert"
	add_child(_structure)
	_effects = Node3D.new()
	_effects.name = "Eruption"
	add_child(_effects)
	_build_path()
	_build_structure()
	_build_water()
	_build_particles()
	_built = true
	_position_sea_pieces()
	_reset_effects()
	# Parse and compile the effect shaders now (load time) rather than on the first erupt().
	for shader: Shader in [_water_shader, _streak_shader, _puff_shader, _ring_shader]:
		shader.get_shader_uniform_list()
	if not _placed:
		visible = false


## Puts the drain in the pier's side wall beside the podium: side +1 (P1) on +X, −1 (P2) on −X.
func place(podium_center: Vector3, side: int) -> void:
	if not _built:
		setup(_quality)
	_side = 1 if side >= 0 else -1
	var origin := Vector3(float(_side) * (StageConstants.FLOOR_HALF_WIDTH - INSET), podium_center.y, podium_center.z)
	var placed := Transform3D(Basis(Vector3.UP, 0.0 if _side > 0 else PI), origin)
	if is_inside_tree():
		global_transform = placed
	else:
		transform = placed
	_water_y = StageConstants.OCEAN_SURFACE_Y - podium_center.y
	_position_sea_pieces()
	_placed = true
	visible = true


## Where the loser emerges: the middle of the outlet, just out of the mouth.
func mouth_position() -> Vector3:
	return _to_global(Vector3(FACE_X + 0.35, MOUTH_Y, 0.0))


## A point on the water column's centreline: 0 is in the mouth, 1 the tip falling over the pier
## (apex near 0.8). The loser can ride this arc before dropping onto the pad.
func column_point(fraction: float) -> Vector3:
	return _to_global(_path_local(fraction)) if not _path.is_empty() else mouth_position()


func _path_local(fraction: float) -> Vector3:
	var f := clampf(fraction, 0.0, 1.0)
	for i in range(1, _path.size()):
		if _path_s[i] >= f:
			var span := maxf(0.00001, _path_s[i] - _path_s[i - 1])
			return _path[i - 1].lerp(_path[i], (f - _path_s[i - 1]) / span)
	return _path[_path.size() - 1]


## [positions, flow directions] textures for emitting particles along the column (local space).
func _path_emission(count: int, from_s: float, to_s: float) -> Array[ImageTexture]:
	var positions := Image.create(count, 1, false, Image.FORMAT_RGBF)
	var directions := Image.create(count, 1, false, Image.FORMAT_RGBF)
	for i in range(count):
		var s := lerpf(from_s, to_s, (float(i) + 0.5) / float(count))
		var point := _path_local(s)
		var tangent := (_path_local(s + 0.01) - _path_local(s - 0.01)).normalized()
		positions.set_pixel(i, 0, Color(point.x, point.y, point.z))
		directions.set_pixel(i, 0, Color(tangent.x, tangent.y, tangent.z))
	return [ImageTexture.create_from_image(positions), ImageTexture.create_from_image(directions)]


## The flap blows open and the water column stands for ~1.25 s, then drains away and the outflow settles.
func erupt() -> void:
	if not _built:
		setup(_quality)
	visible = true
	_reset_effects()
	_erupting = true
	_time = 0.0
	_effects.visible = true
	_update_eruption(0.0)


func is_erupting() -> bool:
	return _erupting


## 0..1 shake strength for the caller's camera: a hard kick as the flap blows, gone by ~0.9 s.
func camera_shake() -> float:
	if not _erupting or _time >= SHAKE_TIME:
		return 0.0
	var attack := clampf(_time / 0.035, 0.0, 1.0)
	var decay := 1.0 - _time / SHAKE_TIME
	return attack * decay * decay


## Stops the eruption, closes the flap and hides the drain until the next place().
func clear() -> void:
	_erupting = false
	_time = 0.0
	if _built:
		_reset_effects()
	_placed = false
	visible = false


func get_debug_snapshot() -> Dictionary:
	var amounts := {}
	for key: String in _particles.keys():
		amounts[key] = (_particles[key] as GPUParticles3D).amount
	var column_material := _water_materials.get("column") as ShaderMaterial
	return {
		"built": _built,
		"placed": _placed,
		"visible": visible,
		"side": _side,
		"quality": _quality,
		"origin": _to_global(Vector3.ZERO),
		"mouth": mouth_position(),
		"column_apex": column_point(_apex_fraction()),
		"column_tip": column_point(1.0),
		"erupting": _erupting,
		"time": _time,
		"shake": camera_shake(),
		"flap_angle": _flap.rotation.z if _flap != null else 0.0,
		"column_reveal": float(column_material.get_shader_parameter("reveal_top")) if column_material else 0.0,
		"column_drain": float(column_material.get_shader_parameter("reveal_bottom")) if column_material else 0.0,
		"particles": amounts,
		"emitted": _emitted.keys(),
	}


func _process(delta: float) -> void:
	if not _erupting:
		return
	_time += maxf(0.0, delta)
	_update_eruption(_time)
	if _time >= SETTLE_END:
		_erupting = false
		_effects.visible = false


func _to_global(local: Vector3) -> Vector3:
	return global_transform * local if is_inside_tree() else transform * local


# ------------------------------------------------------------------ timeline

func _update_eruption(t: float) -> void:
	for entry: Array in EMIT_SCHEDULE:
		var key := String(entry[1])
		if t >= float(entry[0]) and not _emitted.has(key):
			_emitted[key] = true
			var particles := _particles[key] as GPUParticles3D
			particles.restart()
			particles.emitting = true
	_flap.rotation.z = _flap_angle(t)
	# Column: the front races along the arc, holds, then the tail runs up the arc and it thins out.
	var rise := _ease_out(clampf((t - RISE_START) / (RISE_END - RISE_START), 0.0, 1.0))
	var collapse := smoothstep(HOLD_END, COLLAPSE_END, t)
	var top := rise * 1.15
	var bottom := collapse * 1.1
	var strength := minf(1.0, t / 0.04) * (1.0 - smoothstep(HOLD_END + 0.3, COLLAPSE_END, t))
	_set_water("column", top, bottom, strength)
	_set_water("core", top * 0.98, bottom, strength)
	# Outflow pouring from the mouth into the sea while it settles.
	var pour := smoothstep(0.9, 1.45, t) * (1.0 - smoothstep(2.4, SETTLE_END - 0.15, t))
	_set_water("cascade", 1.1, 0.0, pour)
	_cascade.visible = pour > 0.001
	# Rings on the water: the blast out of the mouth, then the outflow landing.
	var ring_a := _ease_out(clampf((t - 0.06) / 1.5, 0.0, 1.0))
	var ring_b := _ease_out(clampf((t - 1.4) / 1.6, 0.0, 1.0))
	_ring_material.set_shader_parameter("ring_a", lerpf(0.8, 6.2, ring_a))
	_ring_material.set_shader_parameter("alpha_a", (1.0 - ring_a) * float(t >= 0.06))
	_ring_material.set_shader_parameter("ring_b", lerpf(0.9, 5.4, ring_b))
	_ring_material.set_shader_parameter("alpha_b", (1.0 - ring_b) * float(t >= 1.4) * 0.9)
	_ring_material.set_shader_parameter("foam", smoothstep(0.04, 0.2, t) * (1.0 - smoothstep(1.8, SETTLE_END, t)) * 0.85)


func _flap_angle(t: float) -> float:
	if t < 0.08:
		return lerpf(0.0, FLAP_OPEN, _ease_out(t / 0.08))
	if t < 0.7:
		var k := t - 0.08
		return FLAP_HOLD + (FLAP_OPEN - FLAP_HOLD) * cos(k * 21.0) * exp(-k * 7.0)
	if t < HOLD_END:
		return FLAP_HOLD + 0.025 * sin(t * 43.0)
	var settle := smoothstep(HOLD_END, SETTLE_END, t)
	return lerpf(FLAP_HOLD, FLAP_REST, settle) + 0.05 * sin(t * 23.0) * (1.0 - settle)


func _set_water(key: String, top: float, bottom: float, strength: float) -> void:
	var material := _water_materials[key] as ShaderMaterial
	material.set_shader_parameter("reveal_top", top)
	material.set_shader_parameter("reveal_bottom", bottom)
	material.set_shader_parameter("intensity", clampf(strength, 0.0, 1.0))


func _reset_effects() -> void:
	_emitted.clear()
	for particles: GPUParticles3D in _particles.values():
		particles.emitting = false
		particles.restart()
		particles.emitting = false
	if _flap != null:
		_flap.rotation = Vector3.ZERO
	for key: String in _water_materials.keys():
		_set_water(key, 0.0, 0.0, 0.0)
	if _ring_material != null:
		for param: String in ["alpha_a", "alpha_b", "foam"]:
			_ring_material.set_shader_parameter(param, 0.0)
	if _cascade != null:
		_cascade.visible = false
	if _effects != null:
		_effects.visible = false


static func _ease_out(x: float) -> float:
	var inv := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - inv * inv * inv


# ------------------------------------------------------------------ path

static func arc_point(t: float) -> Vector3:
	return Vector3(ARC_BASE.x + ARC_VELOCITY.x * t, ARC_BASE.y + ARC_VELOCITY.y * t - 0.5 * ARC_GRAVITY * t * t, 0.0)


func _apex_fraction() -> float:
	var apex_y := -INF
	var fraction := 0.0
	for i in range(_path.size()):
		if _path[i].y > apex_y:
			apex_y = _path[i].y
			fraction = _path_s[i]
	return fraction


## Mouth → a tight bend just off the headwall → the ballistic arc. Catmull-Rom smoothed.
func _build_path() -> void:
	var keys := PackedVector3Array([
		Vector3(WALL_X + 0.12, MOUTH_Y, 0.0),
		Vector3(FACE_X + 0.55, MOUTH_Y + 0.02, 0.0),
		Vector3(ARC_BASE.x - 0.05, MOUTH_Y + 0.3, 0.0),
	])
	for i in range(1, ARC_SAMPLES + 1):
		keys.append(arc_point(ARC_DURATION * float(i) / float(ARC_SAMPLES)))
	_path = _catmull_rom(keys, 3)
	_path_s = _arc_lengths(_path)


static func _catmull_rom(keys: PackedVector3Array, steps: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(keys.size() - 1):
		var p0 := keys[maxi(0, i - 1)]
		var p1 := keys[i]
		var p2 := keys[i + 1]
		var p3 := keys[mini(keys.size() - 1, i + 2)]
		for step in range(steps):
			var t := float(step) / float(steps)
			var t2 := t * t
			var t3 := t2 * t
			points.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	points.append(keys[keys.size() - 1])
	return points


static func _arc_lengths(points: PackedVector3Array) -> PackedFloat32Array:
	var lengths := PackedFloat32Array()
	lengths.resize(points.size())
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
		lengths[i] = total
	for i in range(points.size()):
		lengths[i] = lengths[i] / maxf(total, 0.0001)
	return lengths


static func _path_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


## Radius along the column: snug in the mouth, swelling into spray at the tip.
static func _column_radius(s: float, scale: float) -> float:
	var keys := [[0.0, 0.62], [0.07, 0.8], [0.14, 0.9], [0.45, 1.0], [0.75, 1.25], [1.0, 1.75]]
	for i in range(1, keys.size()):
		if s <= float(keys[i][0]):
			var f := (s - float(keys[i - 1][0])) / (float(keys[i][0]) - float(keys[i - 1][0]))
			return lerpf(float(keys[i - 1][1]), float(keys[i][1]), f) * scale
	return float(keys[keys.size() - 1][1]) * scale


## Tube along a planar (XY) centreline: UV.x around, UV.y = normalised length, UV2.x = radius.
static func _tube_along(points: PackedVector3Array, radii: PackedFloat32Array, radial: int) -> ArrayMesh:
	var lengths := _arc_lengths(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in range(points.size()):
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := Vector3.BACK
		var normal := side.cross(tangent).normalized()
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for j in range(radial + 1):
			var angle := TAU * float(j) / float(radial)
			var direction := normal * cos(angle) + side * sin(angle)
			ring.append(points[i] + direction * radii[i])
			ring_normals.append(direction)
		rings.append(ring)
		normals.append(ring_normals)
	for i in range(points.size() - 1):
		for j in range(radial):
			var corners := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			var verts: Array[Vector3] = []
			for corner: Array in corners:
				verts.append(rings[corner[0]][corner[1]])
			var face_normal := (normals[i][j] + normals[i + 1][j + 1]).normalized()
			var order := [0, 1, 2, 0, 2, 3]
			if (verts[1] - verts[0]).cross(verts[2] - verts[0]).dot(face_normal) > 0.0:
				order = [0, 2, 1, 0, 3, 2]
			for k: int in order:
				var ring_index: int = corners[k][0]
				var around_index: int = corners[k][1]
				st.set_normal(normals[ring_index][around_index])
				st.set_uv(Vector2(float(around_index) / float(radial), lengths[ring_index]))
				st.set_uv2(Vector2(radii[ring_index], 0.0))
				st.add_vertex(rings[ring_index][around_index])
	return st.commit()


# ------------------------------------------------------------------ culvert

func _build_structure() -> void:
	var concrete := _concrete_material(Color(0.43, 0.42, 0.4), 0.93)
	var cap_concrete := _concrete_material(Color(0.5, 0.49, 0.47), 0.9)
	var inner := _concrete_material(Color(0.18, 0.18, 0.17), 0.96)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.27, 0.25, 0.22)
	steel.metallic = 0.7
	steel.roughness = 0.52
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.01, 0.012, 0.012)
	dark.roughness = 1.0

	# Headwall with the round outlet, set into the wall (its back is hidden inside the pier).
	var headwall := MeshInstance3D.new()
	headwall.name = "Headwall"
	headwall.mesh = _headwall_mesh()
	headwall.material_override = concrete
	_structure.add_child(headwall)
	_structure.add_child(_box("CapStone", Vector3(FACE_X + 0.14 - (WALL_X - 0.1), 0.24, HEADWALL_HALF_Z * 2.0 + 0.3),
		Vector3((FACE_X + 0.14 + WALL_X - 0.1) * 0.5, HEADWALL_TOP + 0.12, 0.0), cap_concrete))
	_structure.add_child(_box("Sill", Vector3(0.22, 0.16, MOUTH_RADIUS * 2.0 + 0.5),
		Vector3(FACE_X + 0.1, MOUTH_Y - MOUTH_RADIUS - 0.1, 0.0), cap_concrete))

	# Barrel: dark concrete tube into the pier with a black back so the opening reads as deep.
	var barrel := MeshInstance3D.new()
	barrel.name = "Barrel"
	barrel.mesh = _barrel_mesh(MOUTH_RADIUS, WALL_X + 0.02, FACE_X + 0.001, 28)
	barrel.material_override = inner
	_structure.add_child(barrel)
	var back := MeshInstance3D.new()
	back.name = "BarrelDark"
	var back_disc := CylinderMesh.new()
	back_disc.top_radius = MOUTH_RADIUS + 0.02
	back_disc.bottom_radius = MOUTH_RADIUS + 0.02
	back_disc.height = 0.02
	back_disc.radial_segments = 28
	back_disc.rings = 1
	back.mesh = back_disc
	back.material_override = dark
	back.rotation.z = -PI * 0.5
	back.position = Vector3(WALL_X + 0.035, MOUTH_Y, 0.0)
	_structure.add_child(back)
	# Steel collar around the mouth.
	var collar := MeshInstance3D.new()
	collar.name = "MouthCollar"
	var torus := TorusMesh.new()
	torus.inner_radius = MOUTH_RADIUS - 0.03
	torus.outer_radius = MOUTH_RADIUS + 0.09
	torus.rings = 32
	torus.ring_segments = 8
	collar.mesh = torus
	collar.material_override = steel
	collar.rotation.z = PI * 0.5
	collar.position = Vector3(FACE_X + 0.015, MOUTH_Y, 0.0)
	collar.scale = Vector3(1.0, 0.35, 1.0)
	_structure.add_child(collar)

	# Hinged steel grate flap (pivot on the hinge; rotation.z > 0 swings the bottom out to sea).
	_flap = Node3D.new()
	_flap.name = "GrateFlap"
	_flap.position = Vector3(FACE_X, MOUTH_Y, 0.0) + HINGE_OFFSET
	_structure.add_child(_flap)
	var flap_center := Vector3(0.0, -HINGE_OFFSET.y, 0.0)
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	var frame_torus := TorusMesh.new()
	frame_torus.inner_radius = MOUTH_RADIUS - 0.02
	frame_torus.outer_radius = MOUTH_RADIUS + 0.08
	frame_torus.rings = 32
	frame_torus.ring_segments = 6
	frame.mesh = frame_torus
	frame.material_override = steel
	frame.rotation.z = PI * 0.5
	frame.position = flap_center
	frame.scale = Vector3(1.0, 0.7, 1.0)
	_flap.add_child(frame)
	var bar_z := -MOUTH_RADIUS + 0.17
	while bar_z < MOUTH_RADIUS - 0.1:
		var chord := 2.0 * sqrt(maxf(0.0, MOUTH_RADIUS * MOUTH_RADIUS - bar_z * bar_z))
		_flap.add_child(_box("Bar", Vector3(0.05, chord, 0.045), flap_center + Vector3(0.0, 0.0, bar_z), steel))
		bar_z += 0.155
	for bar_y: float in [-0.32, 0.0, 0.32]:
		var chord := 2.0 * sqrt(maxf(0.0, MOUTH_RADIUS * MOUTH_RADIUS - bar_y * bar_y))
		_flap.add_child(_box("Rail", Vector3(0.07, 0.06, chord), flap_center + Vector3(0.02, bar_y, 0.0), steel))
	var knuckle := MeshInstance3D.new()
	knuckle.name = "HingeKnuckle"
	var pin := CylinderMesh.new()
	pin.top_radius = 0.055
	pin.bottom_radius = 0.055
	pin.height = 0.62
	pin.radial_segments = 12
	pin.rings = 1
	knuckle.mesh = pin
	knuckle.material_override = steel
	knuckle.rotation.x = PI * 0.5
	_flap.add_child(knuckle)
	for z: float in [-0.42, 0.42]:
		_structure.add_child(_box("HingeBracket", Vector3(0.12, 0.2, 0.12),
			Vector3(FACE_X + 0.05, _flap.position.y + 0.02, z), steel))
		for bolt_y: float in [0.06, -0.06]:
			_structure.add_child(_box("Bolt", Vector3(0.03, 0.04, 0.04),
				Vector3(FACE_X + 0.125, _flap.position.y + 0.02 + bolt_y, z), steel))

	# Wet stain from the mouth down the pier wall, and the weed line at the water.
	_structure.add_child(_stain("HeadwallStain", Vector2(MOUTH_RADIUS * 2.0, MOUTH_Y - MOUTH_RADIUS - HEADWALL_BOTTOM),
		Vector3(FACE_X + 0.012, (MOUTH_Y - MOUTH_RADIUS + HEADWALL_BOTTOM) * 0.5, 0.0), Color(0.07, 0.08, 0.07, 0.6)))
	var wall_stain := _stain("WallStain", Vector2(2.4, 1.0), Vector3.ZERO, Color(0.05, 0.065, 0.06, 0.55))
	wall_stain.set_meta("sea_piece", "stain")
	_structure.add_child(wall_stain)
	var weed := _stain("WeedLine", Vector2(5.5, 1.3), Vector3.ZERO, Color(0.1, 0.16, 0.08, 0.7))
	weed.set_meta("sea_piece", "weed")
	_structure.add_child(weed)


func _position_sea_pieces() -> void:
	for child: Node in _structure.get_children():
		var piece := child as MeshInstance3D
		if piece == null or not piece.has_meta("sea_piece"):
			continue
		var quad := piece.mesh as QuadMesh
		if piece.get_meta("sea_piece") == "stain":
			var top := HEADWALL_BOTTOM
			var bottom := _water_y + 0.3
			quad.size = Vector2(2.4, maxf(0.5, top - bottom))
			piece.position = Vector3(WALL_X + 0.02, (top + bottom) * 0.5, 0.0)
		else:
			piece.position = Vector3(WALL_X + 0.025, _water_y + 0.35, 0.0)
	_ring.position = Vector3(FACE_X + 1.3, _water_y + 0.32, 0.0)
	# Outflow: over the sill, down the wall into the sea.
	var keys := PackedVector3Array([
		Vector3(WALL_X + 0.1, MOUTH_Y - 0.35, 0.0),
		Vector3(FACE_X + 0.35, MOUTH_Y - 0.45, 0.0),
		Vector3(FACE_X + 0.85, MOUTH_Y - 1.4, 0.0),
		Vector3(FACE_X + 1.1, lerpf(MOUTH_Y - 1.4, _water_y, 0.55), 0.0),
		Vector3(FACE_X + 1.2, _water_y - 0.2, 0.0),
	])
	var points := _catmull_rom(keys, 6)
	var radii := PackedFloat32Array()
	var lengths := _arc_lengths(points)
	for i in range(points.size()):
		radii.append(lerpf(0.42, 0.95, lengths[i]))
	_cascade.mesh = _tube_along(points, radii, 16)
	(_water_materials["cascade"] as ShaderMaterial).set_shader_parameter("length_m", _path_length(points))
	(_particles["splash"] as GPUParticles3D).position = Vector3(FACE_X + 1.2, _water_y + 0.2, 0.0)
	_sea_catcher.position = Vector3(0.0, _water_y - 2.0, 0.0)


func _concrete_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.11
	noise.fractal_octaves = 5
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.86, 0.85, 0.83))
	gradient.set_color(1, Color(1.0, 1.0, 0.98))
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = 128
	texture.height = 128
	texture.seamless = true
	texture.color_ramp = gradient
	material.albedo_texture = texture
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.8, 0.8, 0.8)
	return material


func _box(node_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = at
	return mesh_instance


func _stain(node_name: String, size: Vector2, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var quad := QuadMesh.new()
	quad.size = size
	mesh_instance.mesh = quad
	mesh_instance.rotation.y = PI * 0.5
	mesh_instance.position = at
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.roughness = 0.35
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.0))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	gradient.add_point(0.35, Color(1, 1, 1, 1.0))
	gradient.add_point(0.65, Color(1, 1, 1, 1.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 8
	material.albedo_texture = texture
	mesh_instance.material_override = material
	return mesh_instance


## Headwall: front face with a round hole, plus top, bottom and end faces (the back is inside the pier).
func _headwall_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := HEADWALL_TOP - MOUTH_Y
	var bottom := HEADWALL_BOTTOM - MOUTH_Y
	var half := HEADWALL_HALF_Z
	var angles: Array[float] = []
	var segments := 40
	for i in range(segments):
		angles.append(TAU * float(i) / float(segments))
	for corner: Vector2 in [Vector2(half, top), Vector2(-half, top), Vector2(-half, bottom), Vector2(half, bottom)]:
		angles.append(fposmod(atan2(corner.y, corner.x), TAU))
	angles.sort()
	var face_normal := Vector3.RIGHT
	for i in range(angles.size()):
		var a0 := angles[i]
		var a1 := angles[(i + 1) % angles.size()]
		var inner0 := _face_point(Vector2(cos(a0), sin(a0)) * MOUTH_RADIUS)
		var inner1 := _face_point(Vector2(cos(a1), sin(a1)) * MOUTH_RADIUS)
		var outer0 := _face_point(_rect_hit(a0, half, top, bottom))
		var outer1 := _face_point(_rect_hit(a1, half, top, bottom))
		_tri(st, inner0, outer0, outer1, face_normal)
		_tri(st, inner0, outer1, inner1, face_normal)
	var x0 := WALL_X - 0.12
	var x1 := FACE_X
	var y0 := HEADWALL_BOTTOM
	var y1 := HEADWALL_TOP
	_quad(st, Vector3(x0, y1, -half), Vector3(x1, y1, -half), Vector3(x1, y1, half), Vector3(x0, y1, half), Vector3.UP)
	_quad(st, Vector3(x0, y0, -half), Vector3(x1, y0, -half), Vector3(x1, y0, half), Vector3(x0, y0, half), Vector3.DOWN)
	_quad(st, Vector3(x0, y0, half), Vector3(x1, y0, half), Vector3(x1, y1, half), Vector3(x0, y1, half), Vector3.BACK)
	_quad(st, Vector3(x0, y0, -half), Vector3(x1, y0, -half), Vector3(x1, y1, -half), Vector3(x0, y1, -half), Vector3.FORWARD)
	return st.commit()


static func _face_point(p: Vector2) -> Vector3:
	return Vector3(FACE_X, MOUTH_Y + p.y, p.x)


## Where a ray from the mouth centre at `angle` (x = local z, y = up) leaves the headwall rectangle.
static func _rect_hit(angle: float, half: float, top: float, bottom: float) -> Vector2:
	var dir := Vector2(cos(angle), sin(angle))
	var t := INF
	if dir.x > 0.0001:
		t = minf(t, half / dir.x)
	elif dir.x < -0.0001:
		t = minf(t, -half / dir.x)
	if dir.y > 0.0001:
		t = minf(t, top / dir.y)
	elif dir.y < -0.0001:
		t = minf(t, bottom / dir.y)
	return dir * t


## Inward-facing tube along local +X from x0 to x1 at the mouth height.
func _barrel_mesh(radius: float, x0: float, x1: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var r0 := Vector2(cos(a0), sin(a0))
		var r1 := Vector2(cos(a1), sin(a1))
		var p00 := Vector3(x0, MOUTH_Y + r0.y * radius, r0.x * radius)
		var p01 := Vector3(x1, MOUTH_Y + r0.y * radius, r0.x * radius)
		var p10 := Vector3(x0, MOUTH_Y + r1.y * radius, r1.x * radius)
		var p11 := Vector3(x1, MOUTH_Y + r1.y * radius, r1.x * radius)
		var inward := -Vector3(0.0, (r0.y + r1.y) * 0.5, (r0.x + r1.x) * 0.5).normalized()
		_quad(st, p00, p01, p11, p10, inward)
	return st.commit()


## Triangle wound so its front faces `normal` (Godot's front faces are clockwise).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap := b
		b = c
		c = swap
	for p: Vector3 in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_tri(st, a, b, c, normal)
	_tri(st, a, c, d, normal)


# ------------------------------------------------------------------ water

static func _shader(code: String, cache: Shader) -> Shader:
	if cache != null:
		return cache
	var shader := Shader.new()
	shader.code = code
	return shader


func _water_material(key: String, flow_speed: float, length_m: float, density: float, seed: float,
		breakup: float, wobble: float) -> ShaderMaterial:
	_water_shader = _shader(WATER_SHADER_CODE, _water_shader)
	var material := ShaderMaterial.new()
	material.shader = _water_shader
	material.set_shader_parameter("flow_speed", flow_speed)
	material.set_shader_parameter("length_m", length_m)
	material.set_shader_parameter("density", density)
	material.set_shader_parameter("seed", seed)
	material.set_shader_parameter("breakup", breakup)
	material.set_shader_parameter("wobble", wobble)
	_water_materials[key] = material
	return material


func _water_instance(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return instance


func _build_water() -> void:
	var length := _path_length(_path)
	var sheath_radii := PackedFloat32Array()
	var core_radii := PackedFloat32Array()
	for s: float in _path_s:
		sheath_radii.append(_column_radius(s, 1.0))
		core_radii.append(_column_radius(s, 0.55))
	# Column: a spray sheath and a denser, faster core along the same arc.
	_column = _water_instance("ColumnSpray", _tube_along(_path, sheath_radii, 24),
		_water_material("column", 12.0, length, 0.95, 5.3, 0.75, 0.6))
	_effects.add_child(_column)
	_core = _water_instance("ColumnCore", _tube_along(_path, core_radii, 20),
		_water_material("core", 16.0, length, 1.5, 11.9, 0.45, 0.45))
	_effects.add_child(_core)
	# Outflow falling from the mouth into the sea while the eruption settles (mesh set per placement).
	_cascade = _water_instance("Outflow", null, _water_material("cascade", 8.0, 6.0, 1.15, 21.4, 0.35, 0.4))
	_effects.add_child(_cascade)
	# Foam rings on the sea, drawn after the (transparent) ocean.
	_ring_shader = _shader(RING_SHADER_CODE, _ring_shader)
	_ring_material = ShaderMaterial.new()
	_ring_material.shader = _ring_shader
	_ring_material.render_priority = 2
	_ring_material.set_shader_parameter("half_size", 7.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	_ring = _water_instance("SplashRing", plane, _ring_material)
	_effects.add_child(_ring)
	# Droplets and streaks vanish where they meet the pier floor or the sea.
	_floor_catcher = GPUParticlesCollisionBox3D.new()
	_floor_catcher.name = "FloorCatcher"
	_floor_catcher.size = Vector3(24.0, 1.0, 28.0)
	_floor_catcher.position = Vector3(WALL_X - 12.0, -0.5, 0.0)
	_effects.add_child(_floor_catcher)
	_sea_catcher = GPUParticlesCollisionBox3D.new()
	_sea_catcher.name = "SeaCatcher"
	_sea_catcher.size = Vector3(60.0, 4.0, 60.0)
	_effects.add_child(_sea_catcher)


# ------------------------------------------------------------------ particles

func _amount(key: String) -> int:
	return QualityRules.particle_amount(int(BASE_AMOUNTS[key]), _quality)


func _new_particles(key: String, at: Vector3, lifetime: float, explosiveness: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = key.capitalize().replace(" ", "")
	particles.amount = _amount(key)
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = explosiveness
	particles.randomness = 0.4
	particles.emitting = false
	particles.local_coords = false
	particles.fixed_fps = 60
	particles.position = at
	particles.collision_base_size = 0.05
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-16.0, -16.0, -14.0), Vector3(32.0, 40.0, 28.0))
	_effects.add_child(particles)
	_particles[key] = particles
	return particles


static func _ramp(points: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()
	for point: Array in points:
		gradient.add_point(float(point[0]), point[1] as Color)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 64
	return texture


static func _curve(points: Array) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 2.0
	for point: Vector2 in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	texture.width = 64
	return texture


func _streak_material(opacity: float, tint: Color) -> ShaderMaterial:
	_streak_shader = _shader(STREAK_SHADER_CODE, _streak_shader)
	var material := ShaderMaterial.new()
	material.shader = _streak_shader
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("tint", tint)
	return material


func _puff_material(opacity: float, tint: Color, fade: float) -> ShaderMaterial:
	_puff_shader = _shader(PUFF_SHADER_CODE, _puff_shader)
	var material := ShaderMaterial.new()
	material.shader = _puff_shader
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("proximity_fade", fade)
	return material


func _quad_mesh(size: Vector2, material: Material) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material
	return quad


func _build_particles() -> void:
	var white := Color(0.93, 0.97, 1.0)
	var launch := Vector3(ARC_VELOCITY.x, ARC_VELOCITY.y, 0.0)
	var speed := launch.length()
	var gravity := Vector3(0.0, -ARC_GRAVITY, 0.0)
	var base := Vector3(ARC_BASE.x, ARC_BASE.y + 0.3, 0.0)

	# Blast straight out of the mouth as the flap flies open (falls into the sea).
	var burst := _new_particles("burst", Vector3(FACE_X + 0.25, MOUTH_Y, 0.0), 1.1, 0.92)
	var burst_process := ParticleProcessMaterial.new()
	burst_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	burst_process.emission_sphere_radius = 0.55
	burst_process.direction = Vector3(1.0, 0.25, 0.0)
	burst_process.spread = 30.0
	burst_process.initial_velocity_min = 5.0
	burst_process.initial_velocity_max = 12.0
	burst_process.gravity = gravity
	burst_process.particle_flag_align_y = true
	burst_process.scale_min = 0.6
	burst_process.scale_max = 1.3
	burst_process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	burst_process.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.95)], [0.7, Color(0.95, 0.98, 1.0, 0.7)],
		[1.0, Color(0.9, 0.95, 1.0, 0.0)]])
	burst.process_material = burst_process
	burst.draw_pass_1 = _quad_mesh(Vector2(0.08, 0.9), _streak_material(0.9, white))

	# Streaks flying the column's own ballistic arc (same launch, a little scatter).
	var streaks := _new_particles("streaks", base, 2.0, 0.45)
	var streak_process := ParticleProcessMaterial.new()
	streak_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	streak_process.emission_sphere_radius = 0.55
	streak_process.direction = launch.normalized()
	streak_process.spread = 5.0
	streak_process.initial_velocity_min = speed * 0.86
	streak_process.initial_velocity_max = speed * 1.07
	streak_process.gravity = gravity
	streak_process.particle_flag_align_y = true
	streak_process.scale_min = 0.7
	streak_process.scale_max = 1.5
	streak_process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	streak_process.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.04, Color(1, 1, 1, 0.95)],
		[0.7, Color(0.95, 0.98, 1.0, 0.75)], [1.0, Color(0.9, 0.95, 1.0, 0.0)]])
	streaks.process_material = streak_process
	streaks.draw_pass_1 = _quad_mesh(Vector2(0.1, 1.35), _streak_material(0.9, white))

	# Spray puffs peeling off all along the column, drifting with the flow (directed points on the arc).
	var spray := _new_particles("spray", Vector3.ZERO, 1.3, 0.2)
	var spray_process := ParticleProcessMaterial.new()
	var spray_points := _path_emission(64, 0.1, 0.97)
	spray_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
	spray_process.emission_point_texture = spray_points[0]
	spray_process.emission_normal_texture = spray_points[1]
	spray_process.emission_point_count = 64
	spray_process.direction = Vector3(0.0, 0.0, 1.0)
	spray_process.spread = 30.0
	spray_process.initial_velocity_min = 1.5
	spray_process.initial_velocity_max = 6.0
	spray_process.gravity = gravity * 0.35
	spray_process.damping_min = 2.0
	spray_process.damping_max = 4.5
	spray_process.angle_min = -180.0
	spray_process.angle_max = 180.0
	spray_process.scale_min = 1.0
	spray_process.scale_max = 2.4
	spray_process.scale_curve = _curve([Vector2(0.0, 0.45), Vector2(0.35, 0.95), Vector2(1.0, 1.5)])
	spray_process.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.08, Color(1, 1, 1, 0.85)],
		[1.0, Color(0.92, 0.96, 1.0, 0.0)]])
	spray.process_material = spray_process
	spray.draw_pass_1 = _quad_mesh(Vector2(1.0, 1.0), _puff_material(0.6, white, 0.6))

	# Crown of spray at the top of the arc.
	var apex := arc_point(ARC_VELOCITY.y / ARC_GRAVITY)
	var crown := _new_particles("crown", apex + Vector3(-0.6, 0.0, 0.0), 1.9, 0.6)
	var crown_process := ParticleProcessMaterial.new()
	crown_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	crown_process.emission_sphere_radius = 1.3
	crown_process.direction = Vector3(-0.6, 0.6, 0.0)
	crown_process.spread = 75.0
	crown_process.initial_velocity_min = 2.0
	crown_process.initial_velocity_max = 7.0
	crown_process.gravity = gravity * 0.75
	crown_process.damping_min = 0.8
	crown_process.damping_max = 2.0
	crown_process.angle_min = -180.0
	crown_process.angle_max = 180.0
	crown_process.scale_min = 1.0
	crown_process.scale_max = 2.3
	crown_process.scale_curve = _curve([Vector2(0.0, 0.5), Vector2(0.4, 1.0), Vector2(1.0, 1.5)])
	crown_process.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.08, Color(1, 1, 1, 0.85)],
		[1.0, Color(0.93, 0.97, 1.0, 0.0)]])
	crown.process_material = crown_process
	crown.draw_pass_1 = _quad_mesh(Vector2(1.2, 1.2), _puff_material(0.75, white, 0.6))

	# Droplets raining from the far end of the arc onto the pier (gone where they hit the floor).
	var droplets := _new_particles("droplets", arc_point(ARC_DURATION * 0.92), 2.0, 0.4)
	var droplet_process := ParticleProcessMaterial.new()
	droplet_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	droplet_process.emission_sphere_radius = 1.5
	droplet_process.direction = Vector3(-0.7, 0.35, 0.0)
	droplet_process.spread = 60.0
	droplet_process.initial_velocity_min = 2.0
	droplet_process.initial_velocity_max = 6.5
	droplet_process.gravity = gravity
	droplet_process.particle_flag_align_y = true
	droplet_process.scale_min = 0.6
	droplet_process.scale_max = 1.4
	droplet_process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	droplet_process.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.06, Color(0.95, 0.98, 1.0, 0.9)],
		[0.9, Color(0.9, 0.95, 1.0, 0.8)], [1.0, Color(0.9, 0.95, 1.0, 0.0)]])
	droplets.process_material = droplet_process
	droplets.draw_pass_1 = _quad_mesh(Vector2(0.05, 0.45), _streak_material(0.9, Color(0.88, 0.95, 1.0)))

	# Mist: big soft billows along the arc, drifting in over the pier edge.
	var mist := _new_particles("mist", Vector3.ZERO, 3.0, 0.55)
	var mist_process := ParticleProcessMaterial.new()
	var mist_points := _path_emission(32, 0.15, 1.0)
	mist_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	mist_process.emission_point_texture = mist_points[0]
	mist_process.emission_point_count = 32
	mist_process.direction = Vector3(-0.4, 1.0, 0.0)
	mist_process.spread = 60.0
	mist_process.initial_velocity_min = 0.5
	mist_process.initial_velocity_max = 1.8
	mist_process.gravity = Vector3(0.0, -0.35, 0.0)
	mist_process.damping_min = 0.3
	mist_process.damping_max = 0.8
	mist_process.angle_min = -180.0
	mist_process.angle_max = 180.0
	mist_process.scale_min = 2.6
	mist_process.scale_max = 5.0
	mist_process.scale_curve = _curve([Vector2(0.0, 0.45), Vector2(0.5, 0.95), Vector2(1.0, 1.4)])
	mist_process.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.15, Color(1, 1, 1, 0.4)],
		[1.0, Color(0.95, 0.97, 1.0, 0.0)]])
	mist.process_material = mist_process
	mist.draw_pass_1 = _quad_mesh(Vector2(1.0, 1.0), _puff_material(0.5, Color(0.95, 0.97, 1.0), 1.5))

	# Splash where the blast and the outflow hit the sea.
	var splash := _new_particles("splash", Vector3(FACE_X + 1.2, _water_y + 0.2, 0.0), 1.5, 0.6)
	var splash_process := ParticleProcessMaterial.new()
	splash_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	splash_process.emission_ring_axis = Vector3.UP
	splash_process.emission_ring_radius = 1.5
	splash_process.emission_ring_inner_radius = 0.6
	splash_process.emission_ring_height = 0.2
	splash_process.direction = Vector3.UP
	splash_process.spread = 35.0
	splash_process.initial_velocity_min = 3.5
	splash_process.initial_velocity_max = 9.0
	splash_process.radial_velocity_min = 1.5
	splash_process.radial_velocity_max = 4.0
	splash_process.gravity = gravity
	splash_process.angle_min = -180.0
	splash_process.angle_max = 180.0
	splash_process.scale_min = 0.8
	splash_process.scale_max = 1.9
	splash_process.scale_curve = _curve([Vector2(0.0, 0.5), Vector2(1.0, 1.3)])
	splash_process.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.0)], [0.08, Color(1, 1, 1, 0.85)],
		[1.0, Color(0.9, 0.95, 1.0, 0.0)]])
	splash.process_material = splash_process
	splash.draw_pass_1 = _quad_mesh(Vector2(1.0, 1.0), _puff_material(0.5, white, 0.5))
