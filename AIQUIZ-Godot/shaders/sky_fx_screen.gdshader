shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

// スカイゲートの画面のふちの速さの線（SkyFallWind がカメラの子に置く 1 枚の板。画面全体に広げる）。
// 画面の真ん中（focus）から外へ走る白い細い線。画面のふちだけに出し、真ん中（ボードと 2 人）にはかからない。
// 強さは wind（0〜1.4）：線の本数・速さ・濃さが増える。
// 板はクリップ空間に直接置く（POSITION）。カメラの near の内側でも描く（深さを見ない）。

uniform float wind : hint_range(0.0, 1.5) = 1.0;
uniform vec2 focus = vec2(0.5, 0.46);
uniform vec3 line_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float line_opacity = 0.55;
uniform float line_count = 150.0;
uniform float inner_clear = 0.34;
uniform float outer_full = 0.78;

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec2 aspect = vec2(VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0), 1.0);
	vec2 d = (SCREEN_UV - focus) * aspect;
	float r = length(d);
	float ang = atan(d.y, d.x);
	// 角度で細い区画に分け、区画ごとに出る・出ない、速さ、長さを決める
	float a01 = ang / 6.2831853 + 0.5;
	float cell = floor(a01 * line_count);
	float cf = fract(a01 * line_count);
	float h1 = hash1(cell + 0.37);
	float h2 = hash1(cell * 1.913 + 4.1);
	float h3 = hash1(cell * 3.17 + 9.4);
	float w = clamp(wind, 0.0, 1.5);
	float present = step(1.0 - clamp(0.18 + 0.3 * w, 0.0, 0.8), h1);
	float speed = (0.9 + 1.6 * h2) * (0.55 + 0.45 * w);
	float head = fract(TIME * speed + h3 * 7.0) * 1.6 + 0.2;
	float len = 0.18 + 0.3 * h3;
	float dash = smoothstep(head - len, head - len * 0.3, r) * (1.0 - smoothstep(head - 0.01, head + 0.015, r));
	float thin = 1.0 - smoothstep(0.0, 0.1 + 0.16 * h2, abs(cf - 0.5));
	float edge = smoothstep(inner_clear, outer_full, r);
	ALBEDO = line_color;
	ALPHA = clamp(present * dash * thin * edge * min(w, 1.4) / 1.4 * line_opacity * (0.6 + 0.4 * h2), 0.0, 1.0);
}
