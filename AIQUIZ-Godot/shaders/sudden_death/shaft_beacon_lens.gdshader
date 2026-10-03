shader_type spatial;
// Amber lens of a rotating beacon: the side facing the reflector glows and flashes hard when
// the beam sweeps past the camera. beam_angle is the world azimuth of the beam (per instance).
render_mode unshaded, cull_back;

instance uniform float beam_angle = 0.0;
uniform float on = 0.0;
uniform vec3 amber : source_color = vec3(1.0, 0.45, 0.02);

void fragment() {
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 to_cam = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 beam = vec3(cos(beam_angle), 0.0, sin(beam_angle));
	vec2 nh = normalize(n_world.xz + vec2(0.0001));
	vec2 ch = normalize(to_cam.xz + vec2(0.0001));
	float face = pow(max(dot(nh, beam.xz), 0.0), 2.0);
	float flash = pow(max(dot(ch, beam.xz), 0.0), 24.0);
	vec3 lit = amber * (0.9 + 5.0 * face + 22.0 * flash);
	vec3 off = amber * 0.07;
	ALBEDO = mix(off, lit, on);
}
