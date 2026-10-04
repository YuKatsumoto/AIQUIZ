shader_type spatial;
// Glowing lens of the surge tank lamps (TK_Lens): the LED high-bays, the wall floods, the strip lights. The row
// brightness switches them with their line; unshaded, so the glow picks them up.
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://shaders/surge_tank/tank_common.gdshaderinc"

uniform vec4 lens_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform float energy = 30.0;
uniform float off_level = 0.012;

varying float v_bright;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// the lamp of a row hangs 6.75 m on the shaft side of its pillar line: sample the row at the lamp itself
	v_bright = tk_brightness(w.z);
}

void fragment() {
	ALBEDO = lens_color.rgb * white_balance * (energy * v_bright + off_level);
}
