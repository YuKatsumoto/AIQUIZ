shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// オンラインメニューのヘリパッドの縁の灯（assets/online_heliport の OHP_PadLamp を置き換える）。
// UV2.x : 灯の番号 / 灯の数（パッドの中心から見た角度の順。online_heliport_layout.json の lamp_count）
// ふだんは弱く点灯。chase を上げると、光の粒が 2 つ輪を回る（さがし中：相手のヘリを待つパッド B）。
// flash は全体の明るさの上乗せ（相手のヘリが降りた瞬間など）。

uniform vec3 lamp_color : source_color = vec3(0.36, 0.89, 0.54);
uniform float base_energy : hint_range(0.0, 4.0) = 0.7;
uniform float chase : hint_range(0.0, 1.0) = 0.0;
uniform float chase_speed = 0.55;
uniform float chase_width : hint_range(0.01, 0.5) = 0.09;
uniform float flash : hint_range(0.0, 6.0) = 0.0;

void fragment() {
	float index = UV2.x;
	float head = fract(TIME * chase_speed);
	// 2 つの粒（向かい合わせ）までの輪の上の距離
	float d = abs(fract((index - head) * 2.0 + 0.5) - 0.5) * 0.5;
	float pulse = smoothstep(chase_width, 0.0, d);
	float energy = base_energy * (1.0 - 0.55 * chase) + chase * pulse * 4.0 + flash;
	ALBEDO = lamp_color * 0.35;
	ROUGHNESS = 0.3;
	EMISSION = lamp_color * energy;
}
