shader_type spatial;
// マイクラのワールドボーダー風の力場。斜めの縞が流れ、近づいたプレイヤーの周りだけ浮かび上がる。
// 明るい海・空の前でも見えるよう、加算ではなく半透明合成にする。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 border_color : source_color = vec4(0.10, 0.55, 1.0, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.55, 0.88, 1.0, 1.0);
// プレイヤーのワールド座標（遠方の既定値なら何も見えない）。
uniform vec3 player_a = vec3(100000.0);
uniform vec3 player_b = vec3(100000.0);
uniform float fade_radius = 6.5;
uniform float stripe_density = 1.1;
uniform float scroll_speed = 0.5;
// 押し戻した瞬間に 1.0 へ跳ね上げ、スクリプト側で減衰させる。
uniform float flash = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = min(distance(world_pos, player_a), distance(world_pos, player_b));
	float reach = fade_radius * (1.0 + flash * 0.5);
	float near = 1.0 - smoothstep(0.0, reach, d);
	near = sqrt(near);
	// 斜め45°の一方向の縞だけを流す（交差させない）。
	// 面の向きに依らず縞が出るよう、水平方向は x+z で取る。
	vec2 p = vec2(world_pos.x + world_pos.z, world_pos.y) * stripe_density;
	float s1 = fract(p.x + p.y - TIME * scroll_speed);
	float pattern = smoothstep(0.0, 0.04, s1) * (1.0 - smoothstep(0.38, 0.44, s1));
	vec3 col = mix(border_color.rgb, stripe_color.rgb, pattern);
	col = mix(col, vec3(1.0), flash * 0.35);
	ALBEDO = col;
	ALPHA = clamp(near * (0.22 + pattern * 0.6) * (1.0 + flash * 0.6), 0.0, 0.92);
}
