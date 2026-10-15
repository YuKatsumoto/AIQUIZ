shader_type spatial;
// 乗り込めるヘリのガラス（材質 Windows の面に OnlineHeliportHelicopter が貼る）。
// 正面は透けて中の顔が見え、縁ほど空を映して白く光る（フレネル）。風防（ノード Windows）だけ、上の方にサンバイザーの帯。
// 帯の高さは GLB の y（helicopter_boarding_layout.json の glass.visor_y）。顔と「?」の視線より上に置く。
render_mode blend_mix, depth_prepass_alpha, cull_disabled, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.62, 0.84, 0.95, 0.22);
uniform vec3 edge_color : source_color = vec3(0.86, 0.93, 1.0);
uniform float edge_alpha = 0.50;
uniform float fresnel_power = 5.0;
uniform float visor_strength = 0.0;     // 風防だけ 1（ドアのガラスは原点が回るので 0）
uniform float visor_y0 = 1.25;          // 地面から 3.00
uniform float visor_y1 = 1.45;          // 地面から 3.20
uniform vec3 visor_color : source_color = vec3(0.10, 0.20, 0.32);
uniform float visor_alpha = 0.62;
uniform float roughness_v = 0.04;
uniform float specular_v = 0.65;

varying float v_y;

void vertex() {
	v_y = VERTEX.y;   // Windows はヘリの原点と同じ向き・位置なので GLB の座標
}

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	float f = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), fresnel_power);
	float visor = visor_strength * smoothstep(visor_y0, visor_y1, v_y);
	ALBEDO = mix(mix(tint.rgb, visor_color, visor), edge_color, f * 0.35);
	ALPHA = mix(mix(tint.a, visor_alpha, visor), edge_alpha, f);
	ROUGHNESS = roughness_v;
	METALLIC = 0.0;
	SPECULAR = specular_v;
}
