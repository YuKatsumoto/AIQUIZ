shader_type spatial;
// Procedural dust motes (kind 0) and falling drips (kind 1) in the shaft air. One MultiMesh
// of quads; every position comes from INSTANCE_ID, so the CPU never touches them. The air
// moves with the walls (scroll) and wraps in a window around the deck.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/sudden_death/shaft_common.gdshaderinc"

uniform mat4 shaft_xform = mat4(1.0);
uniform int kind = 0;
uniform float deck_y = 0.0;
uniform float window_below = 10.0;
uniform float window_height = 28.0;
uniform float particle_size = 0.016;
uniform float strength = 1.0;
uniform float fall_speed = 7.5;
uniform float exposure_time = 0.03;
uniform float fog_density = 0.035;

varying float v_glow;
varying vec3 v_local;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void vertex() {
	float id = float(INSTANCE_ID) + 1.0;
	float a = hash(id * 3.17 + 1.1) * 6.2831853;
	float r;
	float speed;
	float air;
	if (kind == 0) {
		r = sqrt(hash(id * 1.71 + 0.3)) * 6.7;
		speed = (hash(id * 7.93 + 3.3) - 0.5) * 0.3;
		air = hash(id * 5.31 + 2.7) * window_height + speed * TIME;
	} else {
		r = 6.05 + hash(id * 1.71 + 0.3) * 0.85;
		speed = -fall_speed * (0.8 + 0.4 * hash(id * 9.1));
		air = hash(id * 5.31 + 2.7) * window_height * 3.0 + speed * TIME;
	}
	float base = deck_y - window_below;
	float y = base + mod(air + scroll - base, window_height);
	vec3 lp = vec3(cos(a) * r, y, sin(a) * r);
	if (kind == 0) {
		lp.x += sin(TIME * 0.31 + id) * 0.18;
		lp.z += cos(TIME * 0.27 + id * 1.3) * 0.18;
	}
	v_local = lp;
	vec4 world = shaft_xform * vec4(lp, 1.0);
	vec4 cv = VIEW_MATRIX * world;
	vec3 up_v = normalize((VIEW_MATRIX * vec4((shaft_xform * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.0)).xyz);
	vec3 right_v = normalize(cross(up_v, vec3(0.0, 0.0, 1.0)) + vec3(0.0001));
	float rel = abs(motion_speed + speed);
	float size = kind == 0 ? particle_size * (0.6 + 0.8 * hash(id * 4.4)) : particle_size * 0.55;
	float streak = rel * exposure_time + (kind == 1 ? 0.05 : 0.0);
	VERTEX = cv.xyz + right_v * VERTEX.x * size + up_v * VERTEX.y * (size + streak);
	NORMAL = vec3(0.0, 0.0, 1.0);
	// Light: the nearest lamp rows (forward scatter is bright close to a lamp).
	float w = y - scroll;
	float r0 = floor((w - SHAFT_LAMP_Y) / SHAFT_TILE + 0.5);
	float e = 0.0;
	for (int dr = -1; dr <= 1; dr++) {
		float ly = SHAFT_LAMP_Y + (r0 + float(dr)) * SHAFT_TILE + scroll;
		for (int k = 0; k < 4; k++) {
			vec3 d = vec3(SHAFT_LAMP_DIR[k].x * SHAFT_LAMP_R, ly, SHAFT_LAMP_DIR[k].y * SHAFT_LAMP_R) - lp;
			e += shaft_housing(-normalize(d).y) / (dot(d, d) + 0.3);
		}
	}
	float thin = size / (size + streak);
	v_glow = e * thin * exp(-fog_density * length(cv.xyz)) * smoothstep(0.3, 1.2, length(cv.xyz));
}

void fragment() {
	if (shaft_clipped(v_local)) {
		discard;
	}
	vec2 q = UV * 2.0 - 1.0;
	float shape = kind == 0 ? exp(-dot(q, q) * 3.0) : exp(-q.x * q.x * 4.0) * (1.0 - abs(q.y) * 0.4);
	float base_level = kind == 0 ? 0.015 : 0.05;
	float a = shape * (v_glow + base_level) * strength * lamps_on;
	ALBEDO = mix(lamp_color, vec3(1.0, 0.8, 0.6), kind == 1 ? 0.35 : 0.1) * a;
	ALPHA = 1.0;
}
