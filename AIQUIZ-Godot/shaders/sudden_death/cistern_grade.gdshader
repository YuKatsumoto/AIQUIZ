shader_type canvas_item;
// Cistern finishing pass over the 3D view (CisternStage "Grade" layer, under the HUD): a restrained
// vignette and a fine film grain. Both only darken, so the lamp halos keep their peak.

uniform float vignette = 0.32;
uniform float vignette_start = 0.32;
uniform float vignette_end = 0.95;
uniform float grain = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 c = (SCREEN_UV - 0.5) * aspect / max(aspect.x, 1.0) * 2.0;
	float v = smoothstep(vignette_start, vignette_end, length(c)) * vignette;
	float n = hash(floor(FRAGCOORD.xy) + vec2(fract(TIME * 7.13) * 431.0, fract(TIME * 3.71) * 173.0));
	COLOR = vec4(0.0, 0.0, 0.0, clamp(v + grain * n, 0.0, 1.0));
}
