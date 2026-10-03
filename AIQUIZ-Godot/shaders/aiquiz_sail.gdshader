shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// AIQUIZ STADIUM の帆の布（assets/aiquiz_stadium の AQS_SailFabric を置き換える）。
// UV  : u＝ラフ→リーチ、v＝フット→ヘッド（布のテクスチャ）
// UV2 : x＝揺れの重み（縁で 0、中央で 1）、y＝高さ v
// 風：法線の向きにふくらみが呼吸し、布の上を細かい波が流れる。帆ごとに位置で位相をずらす。
// 光：BACKLIGHT で布を透かす（ゴール側の太陽を受けた帆が白く光る）。夜は下（ブームの灯）ほど明るく光る。

uniform sampler2D fabric : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 backlight_color : source_color = vec3(0.82, 0.78, 0.70);
uniform float wind_strength : hint_range(0.0, 1.0) = 0.24;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.25;
uniform float ripple_strength : hint_range(0.0, 0.2) = 0.045;
uniform float night_glow : hint_range(0.0, 2.0) = 0.0;
uniform vec3 night_color : source_color = vec3(1.0, 0.86, 0.64);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;

void vertex() {
	float flex = UV2.x;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.z * 0.113 + origin.x * 0.057;
	float gust = 0.65 + 0.35 * sin(TIME * 0.31 + phase * 0.7);
	float breathe = sin(TIME * wind_speed + phase) * 0.62 + sin(TIME * wind_speed * 1.83 + phase * 1.4) * 0.38;
	float ripple = sin(TIME * 4.1 - UV.x * 9.0 + UV.y * 5.0 + phase) * ripple_strength * smoothstep(0.1, 0.6, flex);
	VERTEX += NORMAL * (flex * wind_strength * gust * breathe + ripple);
}

void fragment() {
	vec3 cloth = texture(fabric, UV).rgb * COLOR.rgb;
	ALBEDO = cloth;
	ROUGHNESS = roughness_val;
	BACKLIGHT = backlight_color * cloth;
	EMISSION = night_color * cloth * night_glow * mix(1.0, 0.3, clamp(UV2.y, 0.0, 1.0));
}
