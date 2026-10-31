// AIQUIZ STADIUM の夜の灯の本体（aiquiz_vertex_glow.gdshader と、奥を切る aiquiz_vertex_glow_clipped.gdshader）。
// STAND_FAR_CLIP を定義すると、前端のキャップと重なる所を捨てる（aiquiz_stand_far_clip.gdshaderinc）。
uniform float night_glow : hint_range(0.0, 2.0) = 0.0;
uniform float glow_energy : hint_range(0.0, 12.0) = 4.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.4;

#ifdef STAND_FAR_CLIP
#include "res://shaders/aiquiz_stand_far_clip.gdshaderinc"

varying float v_world_z;

void vertex() {
	v_world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
	v_clip_local_x = VERTEX.x;
}
#endif

void fragment() {
#ifdef STAND_FAR_CLIP
	if (far_clipped(v_world_z, v_clip_local_x)) {
		discard;
	}
#endif
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_val;
	EMISSION = COLOR.rgb * night_glow * glow_energy;
}
