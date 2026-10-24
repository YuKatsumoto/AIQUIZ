shader_type spatial;
// GOSTRIDER：幽霊が乗り移ったサメ（体に重ねる material_overlay）。
// 乗った瞬間、鞍（origin）から頭と尾へ光の帯（sweep）が走る。走り抜けたところは、
// 輪郭が細くプレイヤー色で光り、胴の上を光の筋が尾へ流れ続ける（サメの青は残す）。
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.62, 0.26, 1.0);
// モデルの空間（skinning 後の頂点）での鞍の位置と、帯が届く最大の距離。
uniform vec3 origin = vec3(1.3, 0.6, 0.0);
uniform float reach = 6.0;
// 0 → 1 で帯が origin から reach まで進む。
uniform float sweep = 0.0;
uniform float band_width = 0.9;
uniform float band_energy = 2.4;
uniform float rim_power = 4.0;
uniform float rim_energy = 1.1;
// 胴を流れる光の筋（モデルの X = サメの前後）。
uniform float flow_frequency = 5.5;
uniform float flow_speed = 7.0;
uniform float flow_energy = 0.3;
// 全体の強さ（フェードイン・アウト）。
uniform float intensity = 1.0;
// 柱が立っている間などの脈打ち（0〜1）。
uniform float pulse = 0.0;

varying vec3 model_position;

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	float distance_from_seat = length(model_position - origin);
	float front = sweep * reach;
	float band = 1.0 - smoothstep(0.0, band_width, abs(distance_from_seat - front));
	band *= step(0.001, sweep) * (1.0 - smoothstep(0.85, 1.0, sweep));
	float possessed = 1.0 - smoothstep(front - 0.25, front + 0.05, distance_from_seat);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	float wave = sin(model_position.x * flow_frequency + TIME * flow_speed);
	float flow = smoothstep(0.93, 0.995, wave) * (0.5 + 0.5 * facing);
	// 光の筋は柱が立っている間（pulse）に強く流れ、ふだんはかすかに残す。
	float glow = (rim * rim_energy * (1.0 + pulse * 0.8) + flow * flow_energy * (0.25 + pulse * 1.6)) * possessed + band * band_energy;
	// 加算は「色 × 不透明度」で足されるので、強さは色に入れて不透明度は 1 にする。
	ALBEDO = color.rgb * glow * intensity;
	ALPHA = 1.0;
}
