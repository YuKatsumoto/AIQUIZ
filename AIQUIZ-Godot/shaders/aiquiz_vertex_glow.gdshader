shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// AIQUIZ STADIUM の夜の灯（AQS_NightGlow を置き換える）。頂点色の灯の色を、夜の強さに合わせて光らせる。
uniform float night_glow : hint_range(0.0, 2.0) = 0.0;
uniform float glow_energy : hint_range(0.0, 12.0) = 4.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_val;
	EMISSION = COLOR.rgb * night_glow * glow_energy;
}
