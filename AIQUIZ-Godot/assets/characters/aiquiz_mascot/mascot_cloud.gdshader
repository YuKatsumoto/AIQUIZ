shader_type spatial;
render_mode cull_back, specular_disabled;

// ハテナの乗る雲（mascot_cloud.glb。両者脱落の投げ縄の演出）。
// 頂点色 R = ふくらみの間の陰（1 = 開けている）、G = 高さ（底 0 → 上 1）。
// 光は回り込み（wrap）でやわらかく、影の側は青みのある灰色、ふくらみの間は少し濃く、縁は空の光で明るく抜ける。
// ふくらみは時間でゆっくり呼吸する（頂点を法線の向きに少しだけ押し引きする）。

uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.74, 0.79, 0.95, 1.0);
uniform vec4 crease_color : source_color = vec4(0.62, 0.66, 0.88, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform float wrap = 0.6;
uniform float rim_strength = 0.5;
uniform float glow = 0.12;
// 呼吸するふくらみの揺れ（雲の空間の m）と速さ
uniform float puff_amount = 0.022;
uniform float puff_speed = 1.0;
// 走るときに後ろへなびく量（LassoCloudRider が速さから入れる。雲の空間の向き）
uniform vec3 trail = vec3(0.0);

varying float v_ao;
varying float v_height;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = hash13(i);
	float b = hash13(i + vec3(1.0, 0.0, 0.0));
	float c = hash13(i + vec3(0.0, 1.0, 0.0));
	float d = hash13(i + vec3(1.0, 1.0, 0.0));
	float e = hash13(i + vec3(0.0, 0.0, 1.0));
	float g = hash13(i + vec3(1.0, 0.0, 1.0));
	float h = hash13(i + vec3(0.0, 1.0, 1.0));
	float k = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
}

void vertex() {
	v_ao = COLOR.r;
	v_height = COLOR.g;
	float t = TIME * puff_speed;
	float n = noise3(VERTEX * 2.1 + vec3(0.0, t * 0.35, t * 0.22)) * 0.65
		+ noise3(VERTEX * 4.3 - vec3(t * 0.3, 0.0, t * 0.17)) * 0.35;
	// ふくらみの頂（開けた所）ほど動き、谷はほとんど動かない
	float open_amount = smoothstep(0.35, 0.95, v_ao);
	VERTEX += NORMAL * (n - 0.5) * 2.0 * puff_amount * open_amount;
	// 速く走るときは、後ろ側（trail の向き）の表面が少し流れる
	float behind = clamp(dot(NORMAL, normalize(trail + vec3(1e-4))), 0.0, 1.0);
	VERTEX += trail * behind * behind * open_amount;
}

void fragment() {
	float h = smoothstep(0.0, 1.0, v_height);
	vec3 base = mix(shade_color.rgb, top_color.rgb, mix(0.45, 1.0, h));
	base = mix(crease_color.rgb, base, smoothstep(0.2, 0.92, v_ao));
	ALBEDO = base;
	ROUGHNESS = 1.0;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	EMISSION = base * glow + rim_color.rgb * fres * rim_strength * mix(0.35, 1.0, h) * 0.45;
	AO = mix(0.7, 1.0, smoothstep(0.2, 0.95, v_ao));
	AO_LIGHT_AFFECT = 0.5;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float wrapped = clamp((nl + wrap) / (1.0 + wrap), 0.0, 1.0);
	wrapped = wrapped * wrapped * (3.0 - 2.0 * wrapped);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrapped / PI;
	// 光を背にしたときの縁の明るさ（雲の銀色の縁）
	float back = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 6.0);
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * back * edge * 0.6 / PI;
}
