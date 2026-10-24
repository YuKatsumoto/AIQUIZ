// クラッカーの紙テープ（SkyGateFireworks）。細長い帯（ローカルの Y が付け根 0 → 先 1、X が幅）を CPU で置き、ここで巻いて揺らす：
// ローカルの Z（長さ 1 m の向き）と X（幅で割って m にする）へ、らせんにずらす。先ほど大きく巻く。
// 色は MultiMesh の色（線形）、INSTANCE_CUSTOM：r 巻きの位相、g 巻きの半径（m）、b 揺れの速さ、a 帯の幅（m）。
shader_type spatial;
render_mode cull_disabled, specular_disabled;

void vertex() {
	float y = VERTEX.y;
	float phase = INSTANCE_CUSTOM.r + TIME * INSTANCE_CUSTOM.b;
	float amp = INSTANCE_CUSTOM.g * (0.25 + 0.75 * y);
	VERTEX.z += sin(y * 12.0 + phase) * amp;
	VERTEX.x += cos(y * 12.0 + phase) * amp / max(INSTANCE_CUSTOM.a, 0.001);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.55;
	METALLIC = 0.15;
	EMISSION = COLOR.rgb * 0.22;
	BACKLIGHT = COLOR.rgb * 0.5;
}
