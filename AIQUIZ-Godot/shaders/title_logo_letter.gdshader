shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// メニューの立体ロゴの文字（scripts/ui/title_logo）。頂点色の r = 1 が表と裏の面（白）、0 が側面と面取り（金）。
// 表は少し自分で光らせて、夜や逆光でも 2D のロゴと同じく白く読めるようにする。
// shine_pos はリグ座標（ロゴのピクセル）で左から右へ走る光の帯、flash は部品ごとの「はまった」光。

uniform vec4 face_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 側面は表の縁で明るい金、奥へ行くほど濃い琥珀（輪郭が締まって、明るい空の前でも字が読める）
uniform vec4 side_color : source_color = vec4(1.0, 0.76, 0.16, 1.0);
uniform vec4 side_back_color : source_color = vec4(0.62, 0.30, 0.04, 1.0);
uniform float depth = 40.0;
uniform float face_emission = 0.42;
uniform float side_emission = 0.06;
uniform mat4 rig_from_world = mat4(1.0);
uniform float shine_pos = -100000.0;
uniform float shine_width = 46.0;
uniform float shine_strength = 2.4;
instance uniform float flash = 0.0;
instance uniform float fade = 1.0;

varying float v_face;
varying float v_back;
varying vec3 v_world;

void vertex() {
	v_face = COLOR.r;
	v_back = clamp(0.5 - VERTEX.z / depth, 0.0, 1.0);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 side = mix(side_color.rgb, side_back_color.rgb, smoothstep(0.05, 0.95, v_back));
	vec3 base = mix(side, face_color.rgb, v_face);
	ALBEDO = base;
	ROUGHNESS = mix(0.32, 0.46, v_face);
	METALLIC = mix(0.35, 0.0, v_face);
	SPECULAR = 0.55;
	vec3 rp = (rig_from_world * vec4(v_world, 1.0)).xyz;
	float band = 1.0 - smoothstep(0.0, shine_width, abs(rp.x + rp.y * 0.6 - shine_pos));
	vec3 glow = vec3(1.0, 0.96, 0.86) * (band * shine_strength + flash * 1.6);
	EMISSION = base * mix(side_emission, face_emission, v_face) * fade + glow;
}
