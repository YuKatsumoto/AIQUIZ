// Shared by the ShaftDescent materials (scripts/world/sudden_death/shaft_descent.gd).
//
// Shaft-local frame: origin on the shaft axis, +Y up. The wall pattern is shifted UP by
// `scroll`, so a wall point has the wall coordinate w = local_y - scroll. Lamp rows sit at
// w = SHAFT_LAMP_Y + 5 k on the azimuths 45/135/225/315 deg (the guide rails own +-X).
// Only 12 real lights exist, so the sodium lamps are also evaluated analytically here, in the
// units of the baked lightmap (Blender DIFFUSE pass): V = C * cos(theta) / d^2 with C = 1.
// The walls, rails and props are unshaded and use this term for every row, like a lightmap.

uniform mat4 shaft_inv = mat4(1.0);
uniform float scroll = 0.0;
uniform float clip_top = 100000.0;
uniform float clip_bottom = -100000.0;
uniform float lamps_on = 1.0;
// #FFA51F (about 2000 K high-pressure sodium), linear.
uniform vec3 lamp_color = vec3(1.0, 0.376, 0.0137);
uniform float lamp_strength = 2.0;
uniform float daylight = 0.0;
uniform vec3 daylight_color = vec3(0.70, 0.80, 1.0);
uniform float daylight_strength = 1.6;
uniform float mouth_y = 100000.0;
uniform float beacons_on = 0.0;
uniform vec4 beacon_angles = vec4(0.0);
uniform float beacon_strength = 3.0;
uniform float motion_speed = 0.0;
uniform float ambient_floor = 0.004;

const float SHAFT_TILE = 5.0;
const float SHAFT_LAMP_Y = 2.95;
const float SHAFT_LAMP_R = 6.55;
const float SHAFT_WALL_R = 7.0;
const float SHAFT_BEACON_R = 7.3;
const float SHAFT_BEACON_Y = 0.21;
const float SHAFT_PI = 3.14159265;
const vec3 SHAFT_BEACON_COLOR = vec3(1.0, 0.42, 0.02);
const vec2 SHAFT_LAMP_DIR[4] = vec2[4](
	vec2(0.70710678, 0.70710678), vec2(-0.70710678, 0.70710678),
	vec2(-0.70710678, -0.70710678), vec2(0.70710678, -0.70710678));

vec3 shaft_local_point(mat4 model, vec3 vertex) {
	return (shaft_inv * (model * vec4(vertex, 1.0))).xyz;
}

vec3 shaft_local_dir(mat4 inv_view, vec3 view_dir) {
	return normalize((shaft_inv * (inv_view * vec4(view_dir, 0.0))).xyz);
}

bool shaft_clipped(vec3 p) {
	return p.y > clip_top || p.y < clip_bottom;
}

// The cast housing above the well glass shades the upper hemisphere.
float shaft_housing(float dir_y) {
	return mix(0.06, 1.0, smoothstep(0.55, 0.0, dir_y));
}

float shaft_ggx(vec3 n, vec3 v, vec3 l, float rough) {
	vec3 h = normalize(l + v);
	float ndh = max(dot(n, h), 0.0);
	float ndl = max(dot(n, l), 0.0);
	float ndv = max(dot(n, v), 0.001);
	float a = max(rough * rough, 0.002);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float d = a2 / (SHAFT_PI * dd * dd);
	float k = (rough + 1.0) * (rough + 1.0) * 0.125;
	float g = (ndl / (ndl * (1.0 - k) + k)) * (ndv / (ndv * (1.0 - k) + k));
	return d * g / (4.0 * ndl * ndv + 0.0001);
}

// Lamp rows within `rows` of the point: diffuse (units of C) and GGX specular (radiance per C),
// plus the direction to the nearest lamp (for normal-map relighting of the baked light).
void shaft_lamps(vec3 p, vec3 n, vec3 v, float rough, vec3 f0, int rows, bool want_spec,
		inout float diffuse, inout vec3 spec, inout vec3 nearest_l) {
	float w = p.y - scroll;
	float r0 = floor((w - SHAFT_LAMP_Y) / SHAFT_TILE + 0.5);
	float best = 1e9;
	float ndv = max(dot(n, v), 0.001);
	for (int dr = -rows; dr <= rows; dr++) {
		float ly = SHAFT_LAMP_Y + (r0 + float(dr)) * SHAFT_TILE + scroll;
		if (ly > clip_top || ly < clip_bottom) {
			continue;
		}
		for (int k = 0; k < 4; k++) {
			vec3 lp = vec3(SHAFT_LAMP_DIR[k].x * SHAFT_LAMP_R, ly, SHAFT_LAMP_DIR[k].y * SHAFT_LAMP_R);
			vec3 d = lp - p;
			float d2 = dot(d, d);
			vec3 l = d * inversesqrt(d2);
			float att = shaft_housing(-l.y) / (d2 + 0.03);
			float ndl = max(dot(n, l), 0.0);
			diffuse += ndl * att;
			if (d2 < best) {
				best = d2;
				nearest_l = l;
			}
			if (want_spec && ndl > 0.0) {
				vec3 h = normalize(l + v);
				vec3 f = f0 + (1.0 - f0) * pow(1.0 - max(dot(h, v), 0.0), 5.0);
				spec += f * shaft_ggx(n, v, l, rough) * ndl * att * SHAFT_PI;
			}
		}
	}
}

// Cool light from the opening at clip_top: a disk of radius 7 m seen from below.
float shaft_daylight(vec3 p, vec3 n) {
	if (daylight <= 0.0) {
		return 0.0;
	}
	vec3 c = vec3(0.0, clip_top, 0.0);
	vec3 d = c - p;
	float depth = max(d.y, 0.0);
	float d2 = dot(d, d);
	vec3 l = d * inversesqrt(max(d2, 0.0001));
	float facing = max(dot(n, l), 0.0) * 0.8 + 0.2 * max(n.y, 0.0);
	float r2 = SHAFT_WALL_R * SHAFT_WALL_R;
	float view = (depth + 0.6) / sqrt(d2 + 0.36) * r2 / (d2 + r2) * exp(-depth * 0.05);
	return daylight * daylight_strength * facing * view;
}

// Rotating amber beacons on the collar at mouth_y (beam = horizontal azimuth beacon_angles[k]).
vec3 shaft_beacons(vec3 p, vec3 n) {
	if (beacons_on <= 0.0) {
		return vec3(0.0);
	}
	float sum = 0.0;
	for (int k = 0; k < 4; k++) {
		vec3 bp = vec3(SHAFT_LAMP_DIR[k].x * SHAFT_BEACON_R, mouth_y + SHAFT_BEACON_Y, SHAFT_LAMP_DIR[k].y * SHAFT_BEACON_R);
		vec3 d = p - bp;
		float d2 = dot(d, d);
		vec3 dir = d * inversesqrt(max(d2, 0.0001));
		float a = beacon_angles[k];
		vec3 beam = vec3(cos(a), 0.0, sin(a));
		float cone = pow(max(dot(dir, beam), 0.0), 10.0);
		sum += cone * max(dot(n, -dir), 0.0) / (d2 + 0.5);
	}
	return SHAFT_BEACON_COLOR * sum * beacons_on * beacon_strength;
}

// Diffuse lamp radiance arriving from the wall around p (cheap bounce for props).
float shaft_wall_bounce(sampler2D light_tex, float light_max, vec3 p) {
	float u = fract(atan(-p.z, p.x) * (1.0 / 6.2831853));
	float v = fract((p.y - scroll) / SHAFT_TILE);
	float e = pow(textureLod(light_tex, vec2(u, 1.0 - v), 3.0).r, 2.2) * light_max;
	return e;
}
