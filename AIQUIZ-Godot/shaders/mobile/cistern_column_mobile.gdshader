shader_type spatial;
// Mobile variant of shaders/sudden_death/cistern_column.gdshader (GraphicsQuality.is_mobile_target()):
// the same additive cone, but the fade where it meets the floor comes from the cone's own height above
// its foot instead of the depth texture, so the Mobile renderer needs no depth copy for it. Same
// uniforms, plus column_foot_y (CisternStage sets it from the mesh AABB). The UV cannot carry the fade:
// a CylinderMesh maps its side to UV.y 0..0.5 only.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.55, 0.68, 0.9, 0.07);
uniform float strength = 1.0;
uniform float floor_fade = 2.0;
// Model-space height of the cone's foot (where it stands on the floor). The default fades nothing.
uniform float column_foot_y = -100000.0;

varying float foot_height;

void vertex() {
	// Metres above the foot (the node's vertical scale included).
	foot_height = (VERTEX.y - column_foot_y) * length(MODEL_MATRIX[1].xyz);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float top = clamp(1.0 - UV.y, 0.0, 1.0);
	float soft = smoothstep(0.0, max(floor_fade, 0.001), foot_height);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * strength * facing * facing * mix(0.3, 1.0, top) * soft;
}
