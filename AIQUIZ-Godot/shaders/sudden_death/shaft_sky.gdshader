shader_type spatial;
// The bright daylight disk of the surface opening, seen only from below.
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 sky_color : source_color = vec3(0.62, 0.74, 0.92);
uniform float intensity = 0.0;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	ALBEDO = sky_color * intensity * (1.0 + 0.35 * (1.0 - dot(q, q)));
}
