// スカイゲートの紙のかけら（紙吹雪・爆発のかけら・破れた紙の垂れ。SkyGateEffects）。
// 色は MultiMesh の 1 つずつの色（線形）。薄い紙なので裏からの光も通し、少し光らせて暗くなりすぎないようにする。
shader_type spatial;
render_mode cull_disabled, specular_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	EMISSION = COLOR.rgb * 0.3;
	BACKLIGHT = COLOR.rgb * 0.55;
}
