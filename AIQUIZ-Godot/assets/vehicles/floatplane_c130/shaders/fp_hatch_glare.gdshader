shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 後ろの扉の開いた所の白とび（暗い機内に目が慣れているあいだ、外の明るさが白く光ってにじむ。docs/sudden_death_v2/c130_float.md 第10章）。
// 開口の奥の板に、ふちの柔らかい白を足す（グローでにじむ）。扉やスロープの手前は深さで隠れる。

uniform vec3 glare_color : source_color = vec3(1.0, 0.97, 0.92);
uniform float intensity = 0.0;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float edge = (1.0 - smoothstep(0.55, 1.0, abs(q.x))) * (1.0 - smoothstep(0.45, 1.0, abs(q.y)));
	ALBEDO = glare_color * intensity * edge;
	ALPHA = 1.0;
}
