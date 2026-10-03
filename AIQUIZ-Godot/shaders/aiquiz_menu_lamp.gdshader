shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// メインメニューのステージ（assets/aiquiz_menu_stage）の灯（AMS_Lamp）。昼も光る。
// 琥珀の灯（青の成分が小さい頂点色）は位置ごとにずらした周期でゆっくり明滅し、桟橋に沿って光が流れて見える。
// スポットライトのレンズ（白に近い頂点色）は明滅させない。

uniform float energy : hint_range(0.0, 8.0) = 2.6;
uniform float pulse : hint_range(0.0, 1.0) = 0.35;
uniform float speed = 1.7;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float amber = 1.0 - step(0.55, COLOR.b);
	float wave = 0.5 + 0.5 * sin(TIME * speed + world_pos.z * 0.22 + world_pos.x * 0.35);
	float k = mix(1.0, 1.0 - pulse * wave, amber);
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.35;
	EMISSION = COLOR.rgb * energy * k;
}
