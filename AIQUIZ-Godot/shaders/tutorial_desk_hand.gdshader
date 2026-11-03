shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// ローカル2Pのキーボード説明の3Dの机（scripts/ui/tutorial_keyboard_desk_3d.gd）のP1・P2の手。
// 下のキーの色と刻印が透けて見える半透明にし、視線に対して横を向いた面ほど濃く少し光らせて、
// 暗い部屋でも指の形の輪郭を読み取れるようにする。

uniform vec4 albedo : source_color = vec4(1.0);
uniform float body_alpha : hint_range(0.0, 1.0) = 0.5;
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.45;
uniform float edge_power = 1.5;
uniform float edge_glow : hint_range(0.0, 2.0) = 0.45;
// 暗い所でも手の色が沈まないよう、面全体もわずかに光らせる。
uniform float body_glow : hint_range(0.0, 1.0) = 0.12;

void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), edge_power);
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.7;
	METALLIC = 0.1;
	EMISSION = albedo.rgb * (body_glow + edge * edge_glow);
	ALPHA = clamp(body_alpha + edge * edge_alpha, 0.0, 1.0);
}
