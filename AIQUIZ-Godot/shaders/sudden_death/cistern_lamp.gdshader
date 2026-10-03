shader_type spatial;
// Glowing lamp glass of the cistern (CIS_LampLens). Its row's brightness from the global row texture switches it
// with the row; vertex colour tints it (white floodlights, amber safety lamps). Unshaded, so glow picks it up.
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://shaders/sudden_death/cistern_common.gdshaderinc"

uniform sampler2D lens_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 lens_color : source_color = vec4(1.0, 0.93, 0.82, 1.0);
uniform float energy = 14.0;
// Unlit glass still catches a little of the hall.
uniform float off_level = 0.015;

varying float v_bright;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_bright = cis_brightness(v_world.z);
}

void fragment() {
	vec3 tint = lens_color.rgb * COLOR.rgb * texture(lens_tex, UV).rgb;
	ALBEDO = tint * white_balance * (energy * v_bright + off_level);
}
