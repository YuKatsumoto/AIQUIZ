// スカイゲートの漫画の煙と火の玉（SkyGateEffects）。色は MultiMesh の 1 つずつの色（線形）、光る強さは INSTANCE_CUSTOM.r。
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

varying float v_emit;

void vertex() {
	v_emit = INSTANCE_CUSTOM.r;
}

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = COLOR.rgb * (1.0 - 0.14 * smoothstep(0.55, 0.95, rim));
	ROUGHNESS = 1.0;
	EMISSION = COLOR.rgb * v_emit;
}
