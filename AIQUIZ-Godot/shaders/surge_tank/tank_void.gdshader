shader_type spatial;
// Openings that lead nowhere the camera goes (pump intake slots, the stair shaft door, the pool of shaft No.1).
render_mode unshaded, cull_disabled;

uniform vec4 void_color : source_color = vec4(0.006, 0.006, 0.007, 1.0);

void fragment() {
	ALBEDO = void_color.rgb;
}
