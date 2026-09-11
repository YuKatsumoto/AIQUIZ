shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

// Clear stylized water: transparent, non-reflective, and compatible with SubViewports.
uniform vec3 deep_color : source_color = vec3(0.012, 0.18, 0.25);
uniform vec3 mid_color : source_color = vec3(0.02, 0.42, 0.54);
uniform vec3 shallow_color : source_color = vec3(0.12, 0.70, 0.72);
uniform vec3 crest_color : source_color = vec3(0.34, 0.82, 0.80);
uniform float wave_speed : hint_range(0.0, 2.0) = 0.42;
uniform float wave_height : hint_range(0.0, 2.0) = 0.52;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.28;
uniform float roughness_val : hint_range(0.0, 1.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.34;
uniform sampler2D noise_tex;
uniform sampler2D noise_tex2;

varying float v_crest;
varying float v_flow;

void vertex() {
	float t = TIME * wave_speed;
	vec2 p = VERTEX.xz;

	float swell_a = sin(p.x * 0.055 + t * 1.25) * cos(p.y * 0.042 - t * 0.82);
	float swell_b = sin((p.x + p.y) * 0.085 - t * 1.08);
	float swell_c = cos(p.x * 0.021 - p.y * 0.032 + t * 0.56);

	vec2 noise_uv_a = p * 0.0045 + vec2(t * 0.025, -t * 0.018);
	vec2 noise_uv_b = p * 0.0080 + vec2(-t * 0.016, t * 0.022);
	float noise_a = texture(noise_tex, noise_uv_a).r - 0.5;
	float noise_b = texture(noise_tex2, noise_uv_b).r - 0.5;

	float displacement = (
		swell_a * 0.46
		+ swell_b * 0.28
		+ swell_c * 0.18
		+ noise_a * 0.42
		+ noise_b * 0.24
	) * wave_height;
	VERTEX.y += displacement;
	v_crest = displacement / max(wave_height, 0.001);
	v_flow = noise_a * 0.65 + noise_b * 0.35;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 flow_uv_a = UV * 7.0 + vec2(t * 0.038, -t * 0.026);
	vec2 flow_uv_b = UV * 11.0 + vec2(-t * 0.031, t * 0.043);

	float a = texture(noise_tex, flow_uv_a).r;
	float b = texture(noise_tex2, flow_uv_b).r;
	float ax = texture(noise_tex, flow_uv_a + vec2(0.012, 0.0)).r - a;
	float az = texture(noise_tex2, flow_uv_b + vec2(0.0, 0.012)).r - b;
	vec3 detail_normal = normalize(vec3(ax * detail_strength * 5.0, az * detail_strength * 5.0, 1.0));
	NORMAL_MAP = detail_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.75;

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.2);
	float flow = clamp(a * 0.58 + b * 0.42 + v_flow * 0.20, 0.0, 1.0);
	float crest = smoothstep(0.58, 0.92, v_crest + flow * 0.30);

	vec3 water_color = mix(deep_color, mid_color, 0.42 + flow * 0.38);
	water_color = mix(water_color, shallow_color, 0.26);
	water_color = mix(water_color, crest_color, crest * 0.16);

	ALBEDO = water_color;
	EMISSION = water_color * 0.02;
	METALLIC = 0.0;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.0;
	ALPHA = clamp(opacity + crest * 0.02, 0.0, 0.38);
}
