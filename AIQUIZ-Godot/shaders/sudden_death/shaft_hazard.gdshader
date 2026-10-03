shader_type spatial;
// Hazard paint for the mouth collar and the deck edge band (mode 0: diagonal yellow/black
// stripes by azimuth) and the iris blades (mode 1: dark checker plate with a striped leading
// edge, so the pinwheel reads from above). Shaded: lit by the sun at the surface and by the
// real lamps in the shaft.
render_mode cull_back;

uniform int mode = 0;
uniform vec3 yellow : source_color = vec3(0.93, 0.62, 0.04);
uniform vec3 black : source_color = vec3(0.022, 0.022, 0.024);
uniform vec3 steel : source_color = vec3(0.10, 0.105, 0.11);
uniform float stripe_period = 0.34;
// Stripes are laid along this radius so a whole number of them closes the ring.
uniform float stripe_radius = 7.3;
uniform float wear = 0.5;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_pos;

float stripes(float s) {
	float f = fract(s);
	float aa = clamp(fwidth(s) * 1.5, 0.001, 0.5);
	return smoothstep(0.5 - aa, 0.5 + aa, f) * (1.0 - smoothstep(1.0 - aa, 1.0, f)) + (1.0 - smoothstep(0.0, aa, f));
}

vec3 bump_normal(vec3 n, vec3 pos_view, float h) {
	vec3 dpdx = dFdx(pos_view);
	vec3 dpdy = dFdy(pos_view);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - grad);
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	float n1 = texture(macro_noise, v_pos.xz * 0.35).r;
	float n2 = texture(macro_noise, v_pos.xz * 2.1 + vec2(0.37, 0.11)).r;
	float scuff = smoothstep(0.55, 0.85, n1 * 0.55 + n2 * 0.6) * wear;
	vec3 bare = vec3(0.20, 0.19, 0.18);
	if (mode == 0) {
		float r = length(v_pos.xz);
		float ang = atan(v_pos.z, v_pos.x);
		float count = max(1.0, floor(6.2831853 * stripe_radius / stripe_period + 0.5));
		float s = ang / 6.2831853 * count + (r - v_pos.y) * count / (6.2831853 * stripe_radius);
		vec3 paint = mix(black, yellow, stripes(s));
		ALBEDO = mix(paint, bare, scuff * 0.8);
		ROUGHNESS = mix(0.55, 0.75, scuff);
		METALLIC = scuff * 0.6;
	} else {
		// Diamond tread plate in blade space, striped leading edge.
		vec2 p = v_pos.xz / 0.036;
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;
		bool flip = mod(cell.x + cell.y, 2.0) > 0.5;
		vec2 e = flip ? vec2(f.x, f.y * 3.2) : vec2(f.x * 3.2, f.y);
		// Fade the tread once a cell gets smaller than a few pixels (no moire at distance).
		float cell_px = 1.0 / max(fwidth(p.x) + fwidth(p.y), 0.0001);
		float h = smoothstep(0.42, 0.18, length(e)) * 0.0012 * smoothstep(3.0, 9.0, cell_px);
		NORMAL = bump_normal(NORMAL, VERTEX, h);
		float edge = smoothstep(0.86, 0.875, UV.x);
		float s = (v_pos.x + v_pos.z) / 0.22;
		vec3 paint = mix(black, yellow, stripes(s));
		vec3 plate = steel * (0.94 + 0.12 * n1);
		ALBEDO = mix(mix(plate, paint, edge), bare, scuff * 0.15);
		METALLIC = mix(0.7, 0.0, edge);
		ROUGHNESS = mix(0.42, 0.55, edge) + scuff * 0.15;
	}
}
