shader_type spatial;
// Airborne dust and fine drizzle in the cistern (GPUParticles3D quads, camera-facing). Each speck is lit by the
// row brightness where it floats and by the shaft light near the opening, so the motes appear with the lamps.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/sudden_death/cistern_common.gdshaderinc"

uniform vec3 dust_color : source_color = vec3(0.80, 0.78, 0.72);
uniform float dust_energy = 0.45;
uniform float near_fade = 2.5;
uniform float far_fade = 38.0;

varying float v_light;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vec3 p = MODEL_MATRIX[3].xyz;
	// Brightest inside the corridor, near the lamp height.
	float corridor = smoothstep(16.0, 8.0, abs(p.x));
	float shaft = length(cis_opening_light(p, vec3(0.0, 1.0, 0.0))) * 0.6 * smoothstep(9.0, 5.0, length(p.xz));
	v_light = cis_brightness(p.z) * corridor + shaft;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float disc = smoothstep(1.0, 0.0, dot(c, c));
	float dist = -VERTEX.z;
	float fade = smoothstep(0.3, near_fade, dist) * (1.0 - smoothstep(far_fade * 0.6, far_fade, dist));
	ALBEDO = dust_color * dust_energy * v_light * disc * fade * COLOR.a;
}
