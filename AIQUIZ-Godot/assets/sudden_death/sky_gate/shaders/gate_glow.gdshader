// スカイゲートの光（SkyGateEffects）：光の輪（mode 0、UV.x が輪の幅の向き）と、ひらめきの玉（mode 1、ふちほど薄い）。
// 色と強さは MultiMesh の 1 つずつの色（a が強さ）。足し算で描く。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform int mode = 0;

void fragment() {
	float p;
	if (mode == 0) {
		p = sin(3.14159265 * clamp(UV.x, 0.0, 1.0));
		p *= p;
	} else {
		p = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	}
	ALBEDO = COLOR.rgb * p * COLOR.a;
}
