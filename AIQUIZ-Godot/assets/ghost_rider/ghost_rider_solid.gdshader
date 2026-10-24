shader_type spatial;
// GOSTRIDER：サメに乗った幽霊。不透明（水面やサメと重なっても透けて破綻しない）で、
// 体の色をうっすら光らせ、輪郭をプレイヤー色で光らせる。
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.62, 0.26, 1.0);
uniform float rim_power = 2.4;
uniform float rim_energy = 1.7;
uniform float core_energy = 0.32;
uniform float flash = 0.0;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	ALBEDO = albedo.rgb;
	EMISSION = albedo.rgb * core_energy + rim_color.rgb * rim * rim_energy + vec3(flash) * 1.8;
	ROUGHNESS = 0.65;
}
