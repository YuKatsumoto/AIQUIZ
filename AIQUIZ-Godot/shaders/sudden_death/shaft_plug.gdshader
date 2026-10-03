shader_type spatial;
// "Bottomless" plug under the lowest tile: the shaft continues as unlit black walls and a
// black floor far below, so the depth never shows a sky or a floor. Fog still applies, so
// it melts into whatever fog the active environment has.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec3 color : source_color = vec3(0.0);

void fragment() {
	ALBEDO = color;
}
