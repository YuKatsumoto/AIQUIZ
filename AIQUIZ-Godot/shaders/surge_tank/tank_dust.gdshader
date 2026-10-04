shader_type spatial;
// Airborne dust in the surge tank (GPUParticles3D quads, camera-facing). Each speck is lit by how close it floats
// to a high-bay (a pendant lamp in the middle of every coffer) and by its row.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/surge_tank/tank_common.gdshaderinc"

uniform vec3 dust_color : source_color = vec3(0.80, 0.78, 0.72);
uniform float dust_energy = 0.5;
uniform float near_fade = 2.5;
uniform float far_fade = 34.0;
// lens height over the trench floor (plan metres) and the floor in the world
uniform float lamp_y = 14.84;
uniform float floor_y = -1.2;

varying float v_light;

// Light of the nearest high-bays at the plan point p: the lamps of line k hang at (7 j, lamp_y, 112 - 14 k) for every free row
// |j| <= 3 of the line (no pillar there).
float tk_lamp_light(vec3 p) {
	int kc = int(round((112.0 - p.z) / 14.0));
	int jc = int(round(p.x / 7.0));
	float sum = 0.0;
	for (int dk = -1; dk <= 1; dk++) {
		for (int dj = -1; dj <= 1; dj++) {
			int k = kc + dk;
			int j = jc + dj;
			if (k < 0 || k > 10 || abs(j) > 3 || tk_has_pillar(k, j)) {
				continue;
			}
			vec3 lamp = vec3(7.0 * float(j), lamp_y, 112.0 - 14.0 * float(k));
			vec3 d = p - lamp;
			// a downward cone of about 65 deg half angle
			float cone = smoothstep(0.35, 0.6, -d.y / max(length(d), 0.001));
			sum += cone * 60.0 / (dot(d, d) + 4.0);
		}
	}
	return sum;
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vec3 p = MODEL_MATRIX[3].xyz;
	vec3 pp = vec3(p.x, p.y - floor_y, p.z) / tank_scale;
	v_light = tk_lamp_light(pp) * tk_brightness(p.z);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float disc = smoothstep(1.0, 0.0, dot(c, c));
	float dist = -VERTEX.z;
	float fade = smoothstep(0.3, near_fade, dist) * (1.0 - smoothstep(far_fade * 0.6, far_fade, dist));
	ALBEDO = dust_color * dust_energy * v_light * disc * fade * COLOR.a;
}
