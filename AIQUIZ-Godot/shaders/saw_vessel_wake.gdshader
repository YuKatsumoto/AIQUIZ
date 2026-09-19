shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float phase = 0.0;
uniform float strength = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float width = mix(0.22, 0.95, UV.y);
	float envelope = (1.0 - smoothstep(width * 0.4, width, abs(p.x))) * sin(UV.y * 3.14159);
	float ribbon = pow(0.5 + 0.5 * sin(UV.y * 36.0 - phase * 4.0 + p.x * p.x * 3.0), 3.0);
	ALBEDO = vec3(0.70, 0.87, 0.88);
	ALPHA = strength * envelope * (0.025 + ribbon * 0.18);
}
