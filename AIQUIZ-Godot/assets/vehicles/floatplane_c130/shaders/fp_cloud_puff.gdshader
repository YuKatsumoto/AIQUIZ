shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

// 雲の層の 1 かたまり（FloatplaneCloudPass の MultiMesh の板）。カメラの方を向く板に、ふくらんだ層積雲を描く
// （online_staging_cloud.gdshader と同じ形の作り方。こちらは層の中を通り抜けるので、近い板は薄くし、
// 機体や海に重なるふちは深さで柔らかく消す）。
// INSTANCE_CUSTOM：x = 種、y = 横長の度合い、z = 濃さ、w = 層の中の高さ（0 下〜1 上。下ほど影）。

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 top_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shade_color : source_color = vec3(0.66, 0.72, 0.82);
uniform vec3 sun_dir = vec3(0.5, 0.7, -0.4);
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float near_fade0 = 6.0;
uniform float near_fade1 = 28.0;
uniform float fade_far = 2400.0;
uniform float soft = 6.0;
uniform bool use_soft = true;

varying vec4 v_seed;
varying float v_dist;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y), mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

float body(vec2 q, float seed) {
	float b = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		vec2 c = vec2(sin(seed + fi * 2.3) * 0.5, cos(seed * 1.3 + fi * 1.7) * 0.16 - 0.04);
		float r = 0.32 + 0.14 * sin(seed * 0.7 + fi * 3.1);
		vec2 d = (q - c) / vec2(r * 1.25, r);
		b = max(b, 1.0 - dot(d, d));
	}
	return b;
}

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
	v_seed = INSTANCE_CUSTOM;
	v_dist = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	q.y = -q.y;
	q.x *= 1.0 + v_seed.y * 0.4;
	float seed = v_seed.x * 40.0;
	float b = body(q, seed);
	float n = fbm(vec3(q * 2.3, seed));
	float shape = b + (n - 0.5) * 0.9;
	float edge = 1.0 - smoothstep(0.82, 0.99, max(abs(UV.x * 2.0 - 1.0), abs(UV.y * 2.0 - 1.0)));
	float a = smoothstep(0.02, 0.32, shape) * edge * v_seed.z * opacity;
	// 近い板は薄く（中を通り抜けるときは画面いっぱいの霧が受け持つ）、遠い板も消す
	a *= smoothstep(near_fade0, near_fade1, v_dist) * (1.0 - smoothstep(fade_far * 0.7, fade_far, v_dist));
	if (use_soft) {
		float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
		vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float scene_z = -upos.z / upos.w;
		float frag_z = -VERTEX.z;
		a *= clamp((scene_z - frag_z) / soft, 0.0, 1.0);
	}
	// 陰：形の高さの傾きと、層の中の高さ（下ほど暗い）、太陽の向き
	float e = 0.06;
	float bx = body(q + vec2(e, 0.0), seed) - body(q - vec2(e, 0.0), seed);
	float by = body(q + vec2(0.0, e), seed) - body(q - vec2(0.0, e), seed);
	vec3 nrm_view = normalize(vec3(-bx, -by, 0.35));
	vec3 sun_view = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
	float lit = clamp(dot(nrm_view, sun_view) * 0.5 + 0.55, 0.0, 1.0);
	float height = clamp(v_seed.w * 0.7 + (q.y * 0.5 + 0.5) * 0.3, 0.0, 1.0);
	vec3 col = mix(shade_color, top_color, clamp(lit * 0.6 + height * 0.5 + (n - 0.5) * 0.2, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
