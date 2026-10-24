shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

// スカイゲートの雲が海と島に落とす影（SkyFallClouds の MultiMesh、海の少し上の横向きの板）。
// 形は雲の形を真上から見た濃さ（sky_fx_cloud_shadows.png、形ごとに横へ並べたもの）。板は光の向きに沿って
// 雲の真下からずらして置く（SkyFallClouds）。海（半透明）のあと、雲の前に描く（render_priority）。
// INSTANCE_CUSTOM：r＝形の番号 / 8、g＝濃さ。

uniform sampler2D shadow_atlas : filter_linear, repeat_disable;
uniform int shape_count = 6;
uniform vec3 shadow_color : source_color = vec3(0.0, 0.05, 0.14);
uniform float strength = 0.42;
uniform float softness = 0.6;

varying flat float v_shape;
varying flat float v_alpha;

void vertex() {
	v_shape = floor(INSTANCE_CUSTOM.r * 8.0 + 0.5);
	v_alpha = INSTANCE_CUSTOM.g;
	if (v_alpha < 0.003) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	vec2 uv = clamp(UV, 0.0, 1.0);
	float cell = 1.0 / float(shape_count);
	vec2 a = vec2((v_shape + uv.x) * cell, uv.y);
	// 影のふちはぼける（太陽の大きさと拡散光）：4 点の平均
	float o = 0.02 * softness;
	float s = texture(shadow_atlas, a).r * 0.4
		+ texture(shadow_atlas, a + vec2(o * cell, 0.0)).r * 0.15 + texture(shadow_atlas, a - vec2(o * cell, 0.0)).r * 0.15
		+ texture(shadow_atlas, a + vec2(0.0, o)).r * 0.15 + texture(shadow_atlas, a - vec2(0.0, o)).r * 0.15;
	float edge = smoothstep(0.0, 0.04, uv.x) * smoothstep(1.0, 0.96, uv.x) * smoothstep(0.0, 0.04, uv.y) * smoothstep(1.0, 0.96, uv.y);
	ALBEDO = shadow_color;
	ALPHA = s * strength * v_alpha * edge;
}
