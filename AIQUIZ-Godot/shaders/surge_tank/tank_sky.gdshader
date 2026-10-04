shader_type spatial;
// Daylight through the roof opening of shaft No.1 (TK_Sky): a bright, slightly blue disc seen from the tank.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 sky_color : source_color = vec4(0.82, 0.88, 1.0, 1.0);
uniform float energy = 6.0;

void fragment() {
	ALBEDO = sky_color.rgb * energy;
}
