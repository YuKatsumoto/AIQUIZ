shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// 投げ縄（三つよりの麻の縄）。LassoRope が作る管のメッシュ用：
//   UV.x = 縄の長さ方向の距離（m）、UV.y = 管の周り（0〜1）、TANGENT = 縄の向き、BINORMAL = 周りの向き。
// 3 本のより（ストランド）はらせんの座標 s = 周り × 3 − 長さ / ピッチ で決め、より目の溝・ふくらみの
// 法線・より目と逆向きに走る細い繊維・ストランドごとの色むらをシェーダーで描く（テクスチャなし）。

uniform vec4 rope_color : source_color = vec4(0.84, 0.67, 0.44, 1.0);
uniform vec4 crown_color : source_color = vec4(0.95, 0.83, 0.62, 1.0);
uniform vec4 groove_color : source_color = vec4(0.55, 0.40, 0.24, 1.0);
uniform float strands = 3.0;
// 1 本のストランドが管を 1 周する長さ（m）
uniform float twist_pitch = 0.17;
uniform float rope_radius = 0.034;
uniform float fiber_density = 22.0;
uniform float normal_strength = 0.85;
uniform float roughness_value = 0.86;
// 遠くでより目がちらつかないよう、画面の上で細かすぎる模様を弱める
uniform float detail_fade_pixels = 2.5;

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void fragment() {
	float along = UV.x;
	float around = UV.y;
	float s = around * strands - along / twist_pitch;
	float strand_id = floor(s);
	float f = fract(s);
	// ストランドの断面：まんなかが盛り上がり、隣との境が深い溝
	float profile = sin(f * PI);
	float crown = smoothstep(0.0, 0.75, profile);
	float slope = cos(f * PI);
	// より目と逆向き（Z より）に走る繊維
	float fiber_coord = around * fiber_density * strands + along / twist_pitch * 2.4;
	float fiber = 0.5 + 0.5 * sin(fiber_coord * TAU + hash11(strand_id) * 6.0);
	float fiber_slope = cos(fiber_coord * TAU + hash11(strand_id) * 6.0);
	// 画面の上での模様の細かさ（1 ピクセルあたりの s の変化）でより目・繊維を弱める
	float ds = length(vec2(dFdx(s), dFdy(s)));
	float detail = clamp(1.0 - (ds * detail_fade_pixels - 0.25), 0.0, 1.0);
	float fiber_detail = clamp(1.0 - ds * detail_fade_pixels * fiber_density * 0.35, 0.0, 1.0);

	float tone = 0.92 + 0.16 * hash11(strand_id + floor(along / (twist_pitch * 7.0)) * 3.0);
	vec3 strand_col = mix(rope_color.rgb, crown_color.rgb, crown * 0.55) * tone;
	strand_col *= mix(1.0, 0.86 + 0.14 * fiber, fiber_detail);
	vec3 col = mix(groove_color.rgb, strand_col, mix(1.0, crown, detail));
	ALBEDO = col;
	ROUGHNESS = mix(roughness_value, roughness_value - 0.12, crown * detail);
	SPECULAR = 0.32;

	// 法線：s の向き（長さ方向と周りの向きの組み合わせ）へ、断面の傾きの分だけ倒す
	vec2 grad = normalize(vec2(-1.0 / twist_pitch, strands / (TAU * rope_radius)));
	float tilt = (slope * normal_strength * detail + fiber_slope * 0.12 * fiber_detail);
	vec3 bent = NORMAL + (TANGENT * grad.x + BINORMAL * grad.y) * tilt;
	NORMAL = normalize(bent);
	// 溝の奥は光が届きにくい
	AO = mix(0.55, 1.0, mix(1.0, crown, detail));
	AO_LIGHT_AFFECT = 0.35;
}
