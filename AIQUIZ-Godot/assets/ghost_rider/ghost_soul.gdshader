shader_type spatial;
// GOSTRIDER：体から抜けて飛ぶ魂。半透明の芯にプレイヤー色の縁光りと、上へ流れるゆらぎの縞。
// depth_prepass_alpha で手前の面だけを描く（箱の内側の面が透けて重ならない）。
render_mode blend_mix, depth_prepass_alpha, cull_back, specular_disabled, shadows_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.62, 0.26, 1.0);
uniform float rim_power = 2.1;
uniform float rim_energy = 2.8;
uniform float core_energy = 0.7;
uniform float body_alpha = 0.5;
uniform float shimmer = 1.0;
// 目覚めや着座の瞬間の白い光（0〜1）。
uniform float flash = 0.0;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bands = 0.5 + 0.5 * sin(world_position.y * 24.0 - TIME * 6.5);
	float shimmer_term = mix(1.0, 0.72 + 0.28 * bands, shimmer);
	vec3 core = mix(albedo.rgb, rim_color.rgb, 0.35);
	ALBEDO = core * 0.3;
	EMISSION = core * core_energy * shimmer_term + rim_color.rgb * rim * rim_energy + vec3(flash) * 2.2;
	ALPHA = clamp(mix(body_alpha * shimmer_term, 1.0, rim) + flash * 0.35, 0.0, 1.0);
	ROUGHNESS = 0.8;
}
