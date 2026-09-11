shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

// Opaque, texture-free ocean for mobile and the default balanced preset.
// It avoids transparent overdraw and runtime-generated noise texture sampling.
uniform vec3 deep_color : source_color = vec3(0.012, 0.20, 0.29);
uniform vec3 mid_color : source_color = vec3(0.02, 0.48, 0.61);
uniform vec3 crest_color : source_color = vec3(0.24, 0.78, 0.82);
uniform float wave_speed : hint_range(0.0, 2.0) = 0.42;
uniform float wave_height : hint_range(0.0, 2.0) = 0.42;

varying float crest;
varying vec2 water_position;

void vertex() {
	float t = TIME * wave_speed;
	vec2 p = VERTEX.xz;
	float phase_a = p.x * 0.050 + t * 1.20;
	float phase_b = (p.x + p.y) * 0.075 - t * 0.86;
	float phase_c = (p.x - p.y) * 0.023 + t * 0.48;
	float wave_a = sin(phase_a);
	float wave_b = sin(phase_b);
	float wave_c = cos(phase_c);
	float displacement = (wave_a * 0.52 + wave_b * 0.30 + wave_c * 0.18) * wave_height;
	VERTEX.y += displacement;

	float slope_x = (
		cos(phase_a) * 0.050 * 0.52
		+ cos(phase_b) * 0.075 * 0.30
		- sin(phase_c) * 0.023 * 0.18
	) * wave_height;
	float slope_z = (
		cos(phase_b) * 0.075 * 0.30
		+ sin(phase_c) * 0.023 * 0.18
	) * wave_height;
	NORMAL = normalize(vec3(-slope_x, 1.0, -slope_z));
	crest = displacement / max(wave_height, 0.001);
	water_position = p;
}

void fragment() {
	float t = TIME * wave_speed;
	float flow = sin(water_position.x * 0.028 - water_position.y * 0.018 + t * 0.70) * 0.5 + 0.5;
	float crest_mask = smoothstep(0.45, 0.95, crest);
	vec3 water_color = mix(deep_color, mid_color, 0.38 + flow * 0.30);
	water_color = mix(water_color, crest_color, crest_mask * 0.22);

	ALBEDO = water_color;
	ROUGHNESS = 0.88;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
