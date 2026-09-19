shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled;
uniform float wave_speed = 0.42;
uniform float wave_height = 0.52;
uniform sampler2D noise_tex;
uniform sampler2D noise_tex2;
uniform vec2 surface_origin = vec2(0.0);
uniform float sea_level = -9.2;
varying vec2 foam_position;

float foam_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float foam_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(foam_hash(cell), foam_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(foam_hash(cell + vec2(0.0, 1.0)), foam_hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	// Vertices are world-space history, not attached to the current shark pose.
	// Match the existing ocean's displacement and TIME, including its noise.
	float t = TIME * wave_speed;
	vec2 p = VERTEX.xz - surface_origin;
	foam_position = VERTEX.xz;
	float swell_a = sin(p.x * 0.055 + t * 1.25) * cos(p.y * 0.042 - t * 0.82);
	float swell_b = sin((p.x + p.y) * 0.085 - t * 1.08);
	float swell_c = cos(p.x * 0.021 - p.y * 0.032 + t * 0.56);
	float noise_a = texture(noise_tex, p * 0.0045 + vec2(t * 0.025, -t * 0.018)).r - 0.5;
	float noise_b = texture(noise_tex2, p * 0.0080 + vec2(-t * 0.016, t * 0.022)).r - 0.5;
	VERTEX.y = sea_level + (swell_a * 0.46 + swell_b * 0.28 + swell_c * 0.18
		+ noise_a * 0.42 + noise_b * 0.24) * wave_height + 0.045;
}

void fragment() {
	// Two-dimensional, world-anchored foam avoids synchronized ladder stripes.
	float coarse = foam_noise(foam_position * 3.6);
	float fine = foam_noise(foam_position * 14.0 + vec2(17.0, 3.0));
	float edge_offset = (coarse - 0.5) * 0.28;
	float cross_wake = UV.x + edge_offset;
	float edge = smoothstep(0.0, 0.32, cross_wake) * (1.0 - smoothstep(0.68, 1.0, cross_wake));
	float breakup = smoothstep(0.34, 0.66, coarse * 0.65 + fine * 0.35);
	ALBEDO = vec3(0.88, 0.98, 1.0);
	ROUGHNESS = 0.9;
	EMISSION = vec3(0.035, 0.05, 0.055);
	ALPHA = COLOR.a * edge * breakup;
}
