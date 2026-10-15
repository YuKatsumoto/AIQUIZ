shader_type canvas_item;
render_mode blend_add;

// VS カットインの稲妻の線（仕様書 7、S8〜S10）。画面いっぱいの ColorRect に加算で描く。
// 芯は白（core_px）、外の光は左右それぞれの色（glow_px）。draw：上から下へ描いていく進み（0〜1）。
// sparks：線に沿って上から下へ流れる光の粒（1.2 秒周期、読み込みのあいだ）。fade：全体の明るさ。

uniform vec2 seam_0 = vec2(0.535, -0.02);
uniform vec2 seam_1 = vec2(0.475, 0.20);
uniform vec2 seam_2 = vec2(0.548, 0.36);
uniform vec2 seam_3 = vec2(0.462, 0.58);
uniform vec2 seam_4 = vec2(0.540, 0.76);
uniform vec2 seam_5 = vec2(0.488, 1.02);
uniform vec4 left_color : source_color = vec4(0.95, 0.55, 0.20, 1.0);
uniform vec4 right_color : source_color = vec4(0.20, 0.65, 0.90, 1.0);
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform float core_px = 7.0;
uniform float glow_px = 22.0;
uniform float draw : hint_range(0.0, 1.0) = 1.0;
uniform float sparks : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float time = 0.0;

float seg_dist(vec2 p, vec2 a, vec2 b, out float t) {
	vec2 ab = b - a;
	t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
	return length(p - (a + ab * t));
}

void fragment() {
	vec2 p[6] = vec2[6](seam_0, seam_1, seam_2, seam_3, seam_4, seam_5);
	vec2 px = UV * rect_size;
	float best = 1e9;
	float along = 0.0;
	float side_x = 0.0;
	for (int i = 0; i < 5; i++) {
		vec2 a = p[i] * rect_size;
		vec2 b = p[i + 1] * rect_size;
		float t;
		float d = seg_dist(px, a, b, t);
		if (d < best) {
			best = d;
			along = mix(p[i].y, p[i + 1].y, t);
			side_x = mix(a.x, b.x, t);
		}
	}
	// 上から下へ描く：まだ届いていない所は出さない
	float shown = 1.0 - smoothstep(draw * 1.05 - 0.04, draw * 1.05, along + 0.02);
	float core = 1.0 - smoothstep(core_px * 0.5 - 1.0, core_px * 0.5 + 1.0, best);
	float glow = exp(-best / (glow_px * 0.5));
	vec3 side = px.x < side_x ? left_color.rgb : right_color.rgb;
	// 光の粒：線に沿って下へ流れる（1.2 秒周期）
	float lane = fract(along * 5.0 - time / 1.2);
	float spark = smoothstep(0.9, 1.0, lane) * exp(-best / 6.0) * sparks;
	vec3 col = vec3(1.0) * core + side * glow * 0.9 + vec3(1.0, 0.95, 0.75) * spark * 1.5;
	COLOR = vec4(col * shown * fade, 1.0);
}
