shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// オンラインメニューのヘリポートの旗（assets/online_heliport の OHP_Flag を置き換える）。
// 旗は竿の上端が原点で +X へなびく。面は局所の XY、法線は Z。
// UV  : u＝竿から先へ、v＝上から下へ
// UV2 : x＝揺れの重み（竿で 0、先で 1）
// 色は頂点色（線形）をそのまま。旗ごとに位置で位相をずらす。

uniform float wave_amp = 0.17;
uniform float wave_speed = 4.6;
uniform float wave_freq = 5.2;
uniform float droop = 0.06;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;

void vertex() {
	float w = UV2.x;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.37 + origin.z * 0.21;
	float s = sin(TIME * wave_speed - UV.x * wave_freq + phase);
	float s2 = sin(TIME * wave_speed * 1.7 - UV.x * wave_freq * 1.9 + UV.y * 2.3 + phase * 1.3);
	VERTEX.z += (s * 0.75 + s2 * 0.25) * wave_amp * w;
	VERTEX.y -= droop * w * w;
	// 波の傾きで法線を寝かせる（陰影が波打つ）
	float slope = cos(TIME * wave_speed - UV.x * wave_freq + phase) * wave_amp * wave_freq * w * 0.5;
	NORMAL = normalize(NORMAL + vec3(slope, 0.0, 0.0) * sign(NORMAL.z));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_val;
}
