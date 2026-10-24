shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled;

// 水上機の航跡（scripts/world/sudden_death/floatplane/floatplane_wake.gd）。頂点はワールドの履歴（海面の高さ）で、
// 海（shaders/ocean.gdshader）と同じ波の上下に乗せる（流れ flow_offset も同じ）。白い泡は、ちぎれた筋が進む向きに伸びる。
// COLOR.a：泡の濃さ。UV.x：帯の横（0〜1）、UV.y：進む向きの距離（m）。COLOR.r：泡の荒さ（0＝細かい筋、1＝崩れた泡）。

uniform float wave_speed = 0.42;
uniform float wave_height = 0.52;
uniform sampler2D noise_tex;
uniform sampler2D noise_tex2;
uniform vec2 surface_origin = vec2(0.0);
uniform vec2 flow_offset = vec2(0.0);
uniform float sea_level = -9.2;
// 海のメッシュ（PlaneMesh）の大きさと分割。描かれる海面は頂点の間をまっすぐつないだ面なので、同じ格子の 4 隅の高さから補間する
// （正確な波の式のままだと、粗い格子の海面の下に沈んで見えなくなる）。
uniform vec2 surface_size = vec2(4000.0);
uniform vec2 surface_cells = vec2(128.0);
varying vec2 foam_position;

float displacement(vec2 local, float t) {
	vec2 p = local + flow_offset;
	float swell_a = sin(p.x * 0.055 + t * 1.25) * cos(p.y * 0.042 - t * 0.82);
	float swell_b = sin((p.x + p.y) * 0.085 - t * 1.08);
	float swell_c = cos(p.x * 0.021 - p.y * 0.032 + t * 0.56);
	float noise_a = texture(noise_tex, p * 0.0045 + vec2(t * 0.025, -t * 0.018)).r - 0.5;
	float noise_b = texture(noise_tex2, p * 0.0080 + vec2(-t * 0.016, t * 0.022)).r - 0.5;
	return (swell_a * 0.46 + swell_b * 0.28 + swell_c * 0.18 + noise_a * 0.42 + noise_b * 0.24) * wave_height;
}

float foam_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float foam_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(foam_hash(cell), foam_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(foam_hash(cell + vec2(0.0, 1.0)), foam_hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	float t = TIME * wave_speed;
	vec2 local = VERTEX.xz - surface_origin;
	foam_position = VERTEX.xz;
	vec2 step = surface_size / max(surface_cells, vec2(1.0));
	vec2 cell = (local + surface_size * 0.5) / step;
	vec2 base = floor(cell);
	vec2 f = cell - base;
	vec2 corner = base * step - surface_size * 0.5;
	float h00 = displacement(corner, t);
	float h10 = displacement(corner + vec2(step.x, 0.0), t);
	float h01 = displacement(corner + vec2(0.0, step.y), t);
	float h11 = displacement(corner + step, t);
	float h = mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
	VERTEX.y = sea_level + h + 0.12;
}

void fragment() {
	// 帯の横：ふちはぼかし、ちぎれた筋（進む向きに伸ばしたノイズ）で抜く
	float coarse = foam_noise(foam_position * 1.4);
	float streak = foam_noise(vec2(UV.x * 7.0, UV.y * 0.55) + vec2(coarse * 2.0, 0.0));
	float fine = foam_noise(foam_position * 9.0 + vec2(17.0, 3.0));
	float edge_offset = (coarse - 0.5) * 0.3;
	float across = UV.x + edge_offset;
	float edge = smoothstep(0.0, 0.3, across) * (1.0 - smoothstep(0.7, 1.0, across));
	float rough = COLOR.r;
	float breakup = smoothstep(0.30 + 0.12 * (1.0 - rough), 0.72, mix(streak, coarse, 0.35 + 0.35 * rough) * 0.7 + fine * 0.3);
	ALBEDO = vec3(0.90, 0.97, 1.0);
	ROUGHNESS = 0.9;
	EMISSION = vec3(0.04, 0.055, 0.06);
	ALPHA = clamp(COLOR.a * edge * breakup * 1.35, 0.0, 1.0);
}
