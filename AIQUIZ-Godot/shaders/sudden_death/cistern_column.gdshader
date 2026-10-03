shader_type spatial;
// Low quality has no volumetric fog: the shaft light reads as a soft additive cone, faint at its silhouette
// (facing ratio), brighter near the ceiling, faded where it meets the floor. Outside faces only, so a camera
// inside the column sees nothing. CisternStage drives "strength" with set_opening_light().
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.55, 0.68, 0.9, 0.07);
uniform float strength = 1.0;
uniform float floor_fade = 2.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float top = clamp(1.0 - UV.y, 0.0, 1.0);
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float soft = clamp(1.0 - smoothstep(behind.z + floor_fade, behind.z, VERTEX.z), 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * strength * facing * facing * mix(0.3, 1.0, top) * soft;
}
