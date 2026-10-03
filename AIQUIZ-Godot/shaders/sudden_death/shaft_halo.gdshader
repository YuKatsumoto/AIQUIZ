shader_type spatial;
// Glow sprite around every lamp (MultiMesh, one instance per lamp of the 12 tiles). Pulled
// toward the camera so the wall never cuts it; faded by distance like the fog it sits in.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/sudden_death/shaft_common.gdshaderinc"

uniform float halo_size = 1.1;
// Extra world size per metre of distance: near lamps get a tight glare, far rows a readable bloom.
uniform float halo_growth = 0.11;
uniform float halo_strength = 1.0;
uniform float fog_density = 0.035;

varying vec3 v_center_local;
varying float v_fade;

void vertex() {
	vec4 center_world = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	v_center_local = (shaft_inv * center_world).xyz;
	vec4 cv = VIEW_MATRIX * center_world;
	float dist = length(cv.xyz);
	cv.xyz -= normalize(cv.xyz) * min(0.6, dist * 0.5);
	// Grows a little with distance so far rows keep a readable glow, like lens bloom.
	float size = halo_size + dist * halo_growth;
	VERTEX = cv.xyz + vec3(VERTEX.xy * size, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	// Close to the lens the sprite would fill the screen: fade it in from 1 m.
	v_fade = exp(-fog_density * 0.6 * dist) * mix(0.35, 1.0, smoothstep(2.0, 9.0, dist)) * smoothstep(0.6, 1.6, dist);
}

void fragment() {
	if (shaft_clipped(v_center_local)) {
		discard;
	}
	vec2 q = UV * 2.0 - 1.0;
	float r2 = dot(q, q);
	float core = exp(-r2 * 110.0) * 4.0;
	float glow = exp(-r2 * 14.0) * 0.85 + exp(-r2 * 3.2) * 0.26;
	float flare = exp(-q.y * q.y * 1400.0) * exp(-q.x * q.x * 3.0) * 0.14;
	float a = (core + glow + flare) * halo_strength * lamps_on * v_fade;
	ALBEDO = mix(lamp_color, vec3(1.0, 0.75, 0.45), clamp(core * 0.3, 0.0, 0.6)) * a;
	ALPHA = 1.0;
}
