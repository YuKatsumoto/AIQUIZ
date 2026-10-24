// スカイゲートの打ち上げ花火の火の粉（SkyGateFireworks）。四角い板（QuadMesh 1×1）を、火の粉が直前に動いた筋に合わせて CPU で置く：
// ローカルの X が筋（UV.x = 1 が頭）、Y が幅、Z がカメラの向き。色は MultiMesh の 1 つずつの色（線形、a が強さ）。
// 頭ほど明るく（頭の芯は白く熱い）、ふちはやわらかく消える。昼の明るい空に足し算で描くと色が白く飛ぶので、色を重ねて描き、
// 少しだけ 1 を超える明るさでグローに乗せる。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float energy = 1.9;

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float along = clamp(UV.x, 0.0, 1.0);
	float core = pow(across, 1.6);
	// 頭の丸い光と、うしろへ細く消える尾
	float tail = mix(0.12, 1.0, along * along);
	float head = 1.0 - smoothstep(0.86, 1.0, along) * 0.6;
	float hot = core * smoothstep(0.7, 0.95, along);
	ALBEDO = mix(COLOR.rgb, vec3(1.0), hot * 0.35) * energy;
	ALPHA = clamp(COLOR.a * core * tail * head * 1.4, 0.0, 1.0);
}
