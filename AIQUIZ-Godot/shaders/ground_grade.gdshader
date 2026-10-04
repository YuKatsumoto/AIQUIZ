shader_type canvas_item;
// Surface stage finishing pass over the 3D view (StageAtmosphere "Grade" layer, under the HUD): a soft
// vignette that only darkens toward the screen edges and corners. It never reads the screen (no screen
// texture, no grain), so it costs one alpha-blended full-screen quad. Its counterpart underground is
// shaders/sudden_death/cistern_grade.gdshader.

// Darkening at the far corners (0..1 of black).
uniform float strength : hint_range(0.0, 1.0) = 0.16;
// Radius where the darkening starts and where it reaches `strength`. The radius is 1.0 at the middle of
// the left and right edges.
uniform float start : hint_range(0.0, 2.0) = 0.6;
uniform float end : hint_range(0.0, 2.0) = 1.3;
// 0: the shape follows the screen (top and bottom edges as dark as the sides); 1: a circle (top and
// bottom stay clear on a wide screen).
uniform float roundness : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (SCREEN_UV - 0.5) * 2.0;
	p.y /= mix(1.0, max(aspect, 1.0), roundness);
	float v = smoothstep(start, end, length(p)) * strength;
	COLOR = vec4(0.0, 0.0, 0.0, v);
}
