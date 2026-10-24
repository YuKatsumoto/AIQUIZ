// スカイゲートの花火とクラッカーの煙（SkyGateFireworks）。カメラへ向けた板（QuadMesh 1×1）を CPU で置く。
// 色は MultiMesh の 1 つずつの色（線形、a が濃さ）、INSTANCE_CUSTOM.r が形の種（ふちのもくもくを変える）。昼の打ち上げ花火の薄い煙。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

varying float v_seed;

void vertex() {
	v_seed = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	// ふちのもくもく（角度で半径を少し揺らす）
	float lobes = 0.86 + 0.08 * sin(a * 5.0 + v_seed * 6.28) + 0.06 * sin(a * 9.0 + v_seed * 17.0);
	float r = length(p) / lobes;
	float puff = 1.0 - smoothstep(0.35, 1.0, r);
	ALBEDO = COLOR.rgb * (0.88 + 0.12 * (1.0 - r));
	ALPHA = COLOR.a * puff * puff;
}
