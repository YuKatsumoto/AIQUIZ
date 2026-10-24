shader_type spatial;
// 回っているプロペラの代わりの円盤（羽根 4 枚の流れた筋。spin で筋が回る）。
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 blade_color : source_color = vec3(0.16, 0.18, 0.21);
uniform vec3 tip_color : source_color = vec3(0.96, 0.78, 0.18);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float spin = 0.0;
uniform float hub_radius = 0.30;
uniform float tip_start = 0.87;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0 || r < hub_radius) {
		discard;
	}
	float a = atan(p.y, p.x) + spin;
	float streak = 0.55 + 0.45 * pow(abs(cos(a * 2.0)), 6.0);
	float edge = smoothstep(1.0, 0.94, r);
	vec3 col = mix(blade_color, tip_color, smoothstep(tip_start - 0.02, tip_start + 0.02, r));
	ALBEDO = col;
	ALPHA = strength * streak * edge * (r > tip_start ? 0.75 : 0.42);
}
