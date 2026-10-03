shader_type spatial;
// Elevator deck grating: 34 mm bearing bars x 100 mm cross bars, prefiltered coverage so it
// never shimmers, openings closing at grazing angles (the bars are 30 mm deep). Transparent:
// through it the shaft below stays visible. Opaque pad plates replace it under the towers.
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 albedo : source_color = vec3(0.40, 0.41, 0.41);
uniform float metallic = 0.35;
uniform float roughness = 0.5;
uniform float bar_pitch = 0.034;
uniform float bar_width = 0.005;
uniform float bar_depth = 0.03;
uniform float cross_pitch = 0.10;
uniform float cross_width = 0.006;
uniform float pad_x = 2.2;
uniform float pad_r = 1.3;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_pos;

float bar_coverage(float x, float width, float fw) {
	fw = max(fw, 0.0001);
	float x0 = x - 0.5 * fw;
	float x1 = x + 0.5 * fw;
	float f0 = floor(x0) * width + min(fract(x0), width);
	float f1 = floor(x1) * width + min(fract(x1), width);
	return clamp((f1 - f0) / fw, 0.0, 1.0);
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	if (length(v_pos.xz - vec2(pad_x, 0.0)) < pad_r || length(v_pos.xz + vec2(pad_x, 0.0)) < pad_r) {
		discard;
	}
	vec3 view_world = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	vec3 vl = normalize(transpose(mat3(MODEL_MATRIX)) * view_world);
	float vy = max(abs(vl.y), 0.04);
	float wx = clamp((bar_width + bar_depth * abs(vl.x) / vy) / bar_pitch, 0.0, 1.0);
	float wz = clamp((cross_width + 0.022 * abs(vl.z) / vy) / cross_pitch, 0.0, 1.0);
	float x = v_pos.x / bar_pitch;
	float z = v_pos.z / cross_pitch;
	float cx = bar_coverage(x, wx, fwidth(x));
	float cz = bar_coverage(z, wz, fwidth(z));
	float cov = 1.0 - (1.0 - cx) * (1.0 - cz);
	float n = texture(macro_noise, v_pos.xz * 0.21).r;
	float n2 = texture(macro_noise, v_pos.xz * 1.3 + vec2(0.3)).r;
	float dirt = smoothstep(0.45, 0.8, n * 0.6 + n2 * 0.5);
	ALBEDO = mix(albedo, vec3(0.09, 0.07, 0.05), dirt * 0.7);
	METALLIC = metallic * (1.0 - dirt * 0.6);
	ROUGHNESS = mix(roughness, 0.8, dirt);
	ALPHA = cov;
}
