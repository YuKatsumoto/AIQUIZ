shader_type spatial;
// Fake light cone under each lamp (the air's scatter). Main look on the low quality, where
// there is no volumetric fog; a faint touch on the others so far rows keep their beams.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

#include "res://shaders/sudden_death/shaft_common.gdshaderinc"

uniform float cone_strength = 0.12;
uniform float fog_density = 0.035;
// >= 0 replaces the sodium colour (the daylight beam from the opening).
uniform vec3 tint_override = vec3(-1.0);

varying vec3 v_local;
varying float v_fade;

void vertex() {
	v_local = shaft_local_point(MODEL_MATRIX, VERTEX);
	vec4 cv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_fade = exp(-fog_density * length(cv.xyz));
}

void fragment() {
	if (shaft_clipped(v_local)) {
		discard;
	}
	float edge = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.5);
	float along = 1.0 - UV.y;
	float a = edge * along * along * cone_strength * v_fade;
	vec3 tint = tint_override.x >= 0.0 ? tint_override : lamp_color;
	float on = tint_override.x >= 0.0 ? 1.0 : lamps_on;
	ALBEDO = tint * a * on;
	ALPHA = 1.0;
}
