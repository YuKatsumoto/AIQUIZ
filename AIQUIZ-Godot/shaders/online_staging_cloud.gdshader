shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

// マッチング演出の雲（StagingClouds の MultiMesh の 1 枚の板）。カメラの方を向く板に、ふくらんだ積雲を描く。
// 形：いくつかの丸の和（上は丸く、下は平ら）に 3D の値ノイズでふちを崩す。板のふちでは必ず 0 になる（四角い縁を出さない）。
// 陰影：形の高さから作った法線で、左上からの光（太陽の側）を当てる。外の画像は使わない（仕様書 D14）。
// INSTANCE_CUSTOM：x = 種、y = 横長の度合い、z = 濃さ。

uniform vec3 top_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shade_color : source_color = vec3(0.70, 0.78, 0.90);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.97, 0.90);
uniform float opacity : hint_range(0.0, 1.0) = 0.95;
uniform float fade_near = 18.0;
uniform float fade_far = 1100.0;

varying vec3 v_seed;
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

// 雲の丸みの高さ（ノイズなし。陰の法線に使う安い形）。q は板の座標（-1〜1）
float body(vec2 q, float seed) {
	float b = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		vec2 c = vec2(sin(seed + fi * 2.3) * 0.48, cos(seed * 1.3 + fi * 1.7) * 0.14 - 0.02);
		float r = 0.30 + 0.14 * sin(seed * 0.7 + fi * 3.1);
		vec2 d = (q - c) / vec2(r * 1.2, r);
		b = max(b, 1.0 - dot(d, d));
	}
	return b;
}

// 下は平ら、板のふちでは必ず 0
float frame_mask(vec2 q) {
	return smoothstep(-0.62, -0.32, q.y) * (1.0 - smoothstep(0.78, 0.98, max(abs(q.x), abs(q.y))));
}

void vertex() {
	// 板をカメラへ向ける（大きさは MODEL_MATRIX の縮尺のまま）
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
	v_seed = INSTANCE_CUSTOM.xyz;
	v_dist = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	q.y = -q.y;
	q.x *= 1.0 + v_seed.y * 0.5;
	float seed = v_seed.x * 37.0;
	float mask = frame_mask(q);
	float b = body(q, seed);
	float n = fbm(vec3(q * 3.1, seed + TIME * 0.015));
	float h = (b + (n - 0.5) * 0.45) * mask;
	float alpha = smoothstep(0.0, 0.22, h) * opacity * clamp(v_seed.z, 0.3, 1.0);
	alpha *= smoothstep(fade_near * 0.5, fade_near, v_dist) * (1.0 - smoothstep(fade_far * 0.7, fade_far, v_dist));
	if (alpha < 0.01) {
		discard;
	}
	// 丸みの傾きから法線を作り、左上の光で陰を付ける（ノイズは明るさのむらにだけ使う）
	float e = 0.04;
	float hx = body(q + vec2(e, 0.0), seed) - body(q - vec2(e, 0.0), seed);
	float hy = body(q + vec2(0.0, e), seed) - body(q - vec2(0.0, e), seed);
	vec3 nrm = normalize(vec3(-hx, -hy, e * 3.0));
	vec3 light = normalize(vec3(-0.35, 0.75, 0.55));
	float lit = clamp(dot(nrm, light) * 0.7 + 0.38 + (n - 0.5) * 0.35, 0.0, 1.0);
	lit = mix(lit, 1.0, smoothstep(0.6, 1.0, b) * 0.3);
	vec3 col = mix(shade_color, top_color * sun_tint, lit);
	ALBEDO = col;
	ALPHA = alpha;
}
