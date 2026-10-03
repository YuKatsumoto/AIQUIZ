shader_type spatial;
// Well glass of the caged explosion-proof sodium lamps: hot orange-white core, dark when off.
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://shaders/sudden_death/shaft_common.gdshaderinc"

uniform float glass_intensity = 18.0;
uniform vec3 core_color : source_color = vec3(1.0, 0.82, 0.55);

varying vec3 v_local;

void vertex() {
	v_local = shaft_local_point(MODEL_MATRIX, VERTEX);
}

void fragment() {
	if (shaft_clipped(v_local)) {
		discard;
	}
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	vec3 hot = mix(lamp_color, core_color, pow(facing, 3.0) * 0.8);
	vec3 on = hot * glass_intensity * (0.45 + 0.55 * facing);
	vec3 off = vec3(0.018, 0.016, 0.014) + daylight_color * shaft_daylight(v_local, vec3(0.0, 1.0, 0.0)) * 0.05;
	ALBEDO = mix(off, on, lamps_on);
}
