shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// メインメニューのステージ（assets/aiquiz_menu_stage）の旗・吹き流し（AMS_Pennant）とヤシの葉（AMS_Foliage）。
// 色は頂点色。UV2.x が揺れの重み（付け根 0、先 1）で、風の向きへ揺らす。旗は速く小さく、葉はゆっくり大きく。
// 裏の面はメッシュに作ってあるので、片面のまま描く。

uniform float amplitude = 0.14;
uniform float frequency = 2.6;
uniform float spatial_freq = 0.55;
uniform vec3 wind = vec3(0.8, 0.0, 0.6);
uniform float droop = 0.25;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.8;

void vertex() {
	float w = UV2.x;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = dot(world.xz, vec2(spatial_freq, spatial_freq * 0.73));
	float s = sin(TIME * frequency + phase) + 0.35 * sin(TIME * frequency * 2.3 + phase * 1.7);
	vec3 dir = normalize(wind);
	vec3 offset = dir * s * amplitude * w;
	offset.y -= droop * abs(s) * amplitude * w;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_val;
}
