shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert;

// --- Uniforms ---
uniform vec3 deep_color : source_color = vec3(0.15, 0.02, 0.0);
uniform vec3 mid_color : source_color = vec3(0.85, 0.18, 0.0);
uniform vec3 hot_color : source_color = vec3(1.0, 0.65, 0.0);
uniform vec3 white_hot : source_color = vec3(1.0, 0.95, 0.6);
uniform float flow_speed : hint_range(0.0, 2.0) = 0.35;
uniform float voronoi_scale : hint_range(1.0, 40.0) = 8.0;
uniform float emission_intensity : hint_range(0.0, 8.0) = 1.5;
uniform float wave_height : hint_range(0.0, 3.0) = 1.2;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D noise_tex;
uniform sampler2D noise_tex2;

varying float v_height;
varying float v_flow;

// --- Voronoi ---
vec2 random2D(vec2 p) {
	return fract(sin(vec2(
		dot(p, vec2(127.1, 311.7)),
		dot(p, vec2(269.5, 183.3))
	)) * 43758.5453);
}

float voronoi(vec2 pos, float t) {
	vec2 p = floor(pos);
	vec2 f = fract(pos);
	float res = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 b = vec2(float(i), float(j));
			vec2 pnt = random2D(p + b);
			pnt = 0.5 + 0.5 * sin(t + 6.2831 * pnt);
			vec2 r = vec2(b) - f + pnt;
			float d = dot(r, r);
			res += exp(-18.0 * d);
		}
	}
	return clamp(-(1.0 / 18.0) * log(max(res, 1e-6)), 0.0, 1.0);
}

void vertex() {
	float t = TIME * flow_speed;

	// Sample noise for organic waves
	vec2 uv1 = VERTEX.xz * 0.008 + vec2(t * 0.3, t * 0.2);
	vec2 uv2 = VERTEX.xz * 0.015 + vec2(-t * 0.15, t * 0.25);
	float n1 = texture(noise_tex, uv1).r;
	float n2 = texture(noise_tex2, uv2).r;

	// Large slow waves
	float wave1 = sin(VERTEX.x * 0.25 + TIME * 0.8) * cos(VERTEX.z * 0.2 + TIME * 0.6) * 0.6;
	float wave2 = sin(VERTEX.x * 0.08 - TIME * 0.5) * sin(VERTEX.z * 0.12 + TIME * 0.3) * 0.8;

	// Noise-driven displacement
	float noise_disp = (n1 * 0.7 + n2 * 0.3) * wave_height;

	// Bubbling hotspots
	float bx = sin(VERTEX.x * 1.2 + TIME * 2.5);
	float bz = cos(VERTEX.z * 1.2 - TIME * 2.0);
	float bubbles = pow(abs(bx * bz), 8.0) * 0.6;

	float total = wave1 + wave2 + noise_disp + bubbles;
	VERTEX.y += total;
	v_height = total;
	v_flow = n1 * 0.6 + n2 * 0.4;
}

void fragment() {
	float t = TIME * flow_speed;

	// Voronoi for crack patterns
	vec2 uv_v = UV * voronoi_scale + vec2(t * 0.4, -t * 0.3);
	float v1 = voronoi(uv_v, TIME * 2.0);
	float v2 = voronoi(uv_v * 0.5 + vec2(5.0, 3.0), TIME * 1.5);
	float cracks = v1 * 0.7 + v2 * 0.3;

	// Flow noise for organic movement
	vec2 fuv1 = UV * 3.0 + vec2(t * 0.6, t * 0.4);
	vec2 fuv2 = UV * 5.0 + vec2(-t * 0.3, t * 0.5);
	float fn1 = texture(noise_tex, fuv1).r;
	float fn2 = texture(noise_tex2, fuv2).r;
	float flow = fn1 * 0.6 + fn2 * 0.4;

	// Combine: cracks reveal hot interior, surface is cooler crust
	float heat = clamp(cracks * 1.2 + flow * 0.3 + v_height * 0.15, 0.0, 1.0);

	// 4-stop color gradient: deep -> mid -> hot -> white-hot
	vec3 col;
	if (heat < 0.3) {
		col = mix(deep_color, mid_color, heat / 0.3);
	} else if (heat < 0.6) {
		col = mix(mid_color, hot_color, (heat - 0.3) / 0.3);
	} else {
		col = mix(hot_color, white_hot, clamp((heat - 0.6) / 0.4, 0.0, 1.0));
	}

	// Pulsing glow on hotspots
	float pulse = 1.0 + sin(TIME * 3.0) * 0.08;

	ALBEDO = col;
	EMISSION = col * emission_intensity * heat * pulse;
	ROUGHNESS = roughness_val + (1.0 - heat) * 0.4;
	METALLIC = 0.0;
}
