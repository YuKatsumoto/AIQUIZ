shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// AIQUIZ STADIUM の塗装（取り込んだ材質 AQS_Painted を置き換える。aiquiz_stadium_materials.gd の painted()）。
// 側面スタンド・GOAL ゲート・ゴール観客席・沖のヨットが共有する。
// 土台は頂点色（Blender で AO・水際の汚れ・低周波のムラを焼き込み済み）。線形の値をそのまま ALBEDO にする
// （StandardMaterial3D の vertex_color_use_as_albedo、vertex_color_is_srgb = false と同じ）。粗さ 0.74。
// その上に、頂点の少ない面（柱は上下の端にしか頂点がない）でも出る細かさを、テクスチャを読まずに ALU だけで足す：
//   ムラ   低周波の値ノイズで明るさ ±6 % と、わずかな色温度の揺れ（面ごとの単調さを崩す。平均は変えない）
//   濡れ   海面から上へ wet_height（1.6 m）まで暗く・艶を出す（粗さを下げる）。水際には薄い緑茶の汚れ。
//          水面下は濡れたまま、さらに深さとともに少し暗く（海越しに見える杭の根元が沈んで見える）
//   雨だれ 縦の面に、縦に伸ばしたノイズの薄い筋。遠くて筋が画素より細くなると消す（ちらつかせない）
//   粗さ   0.74 を中心に小さく揺らす
// 焼き込みの汚れも水面からの指数で頂点に乗っているが、柱は上下の端にしか頂点がなく、下端は海底（-129 m）まで
// 伸ばされる（santorini_waterfront.gd）ので、その汚れは柱の全長に薄く伸びて水際には出ない。ここの濡れは水際の
// 1.6 m だけで、明るさの平均はほとんど変えない（画面のスタンドの白い面の平均で -1 % 前後）。
// detail = 0 で頂点色だけ（低画質。従来の StandardMaterial3D と同じ見た目）。
// 座標：側面スタンドは静止しているので、ムラと筋はワールド座標（20 m のブロックごとに繰り返さない）。
// 走路とともに動く物（GOAL ゲート・ゴール観客席）は AiquizStadiumMaterials.apply() が
// インスタンスの object_space = 1 にするので、ムラと筋はその物の局所座標に付いて動く（流れて見えない）。
// 濡れは常にワールドの高さ（物は水平にしか動かない）。夜の発光はない（夜の灯は aiquiz_vertex_glow.gdshader）。

uniform float detail : hint_range(0.0, 1.0) = 1.0;
// 高画質以上：ムラの 2 つ目のオクターブと色温度の揺れ
uniform bool fine_detail = true;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.74;
uniform float roughness_variation : hint_range(0.0, 0.3) = 0.06;
uniform float sea_level = -9.2;

group_uniforms Mottle;
uniform float mottle_amount : hint_range(0.0, 0.2) = 0.06;
uniform float mottle_period = 7.0;
uniform float mottle_warmth : hint_range(0.0, 1.0) = 0.35;

group_uniforms Wet;
// 濡れの高さ（m）：下の wet_full の割合までは濡れきり、そこから上へ薄れる
uniform float wet_height = 1.6;
uniform float wet_full : hint_range(0.0, 0.9) = 0.25;
// 水際（とその下）での明るさの減り（1 - wet_darken 倍）。焼き込みの汚れで頂点色がすでに暗い所では弱める：
// 頂点色の輝度（線形）が wet_paint_range.x 以下で 0、.y 以上で全量（二重に暗くしない）
uniform float wet_darken : hint_range(0.0, 1.0) = 0.38;
uniform vec2 wet_paint_range = vec2(0.3, 0.7);
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.3;
// 水際の緑茶の汚れ（線形の掛け値）と、その高さ
uniform vec3 algae_tint = vec3(0.78, 0.88, 0.66);
uniform float algae_height = 0.8;
// 水面下は submerged_depth m で、さらに submerged_darken だけ暗くなる（海越しに見える杭を沈んで見せる）
uniform float submerged_darken : hint_range(0.0, 1.0) = 0.25;
uniform float submerged_depth = 2.5;
// 濡れの縁のぎざぎざ（m）
uniform float wet_edge_noise = 0.22;

group_uniforms Streaks;
uniform float streak_strength : hint_range(0.0, 1.0) = 1.0;
// 筋のいちばん濃い所の掛け値（線形）
uniform vec3 streak_tint = vec3(0.84, 0.82, 0.77);
uniform float streak_width = 0.42;
uniform float streak_length = 3.2;
group_uniforms;

// 1：ムラと筋をこのインスタンスの局所座標で付ける（動く物）。0：ワールド座標（静止しているスタンド）
instance uniform float object_space = 0.0;

varying vec3 v_world;
varying vec3 v_noise;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_noise = mix(v_world, VERTEX, object_space);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// -1..1
float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), u.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), u.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), u.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z) * 2.0 - 1.0;
}

// 0..1
float value_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	float rough = roughness_base;
	if (detail > 0.0) {
		vec3 p = v_noise;
		vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		// Horizontal coordinate along the face (x or z, whichever runs along it).
		float along = abs(world_normal.x) > abs(world_normal.z) ? p.z : p.x;

		// Mottle: zero-mean brightness and a slight warm/cool drift.
		float n1 = value_noise3(p / mottle_period);
		float n2 = fine_detail ? value_noise3(p * (2.7 / mottle_period) + vec3(17.3, 5.9, 11.1)) : 0.0;
		float mottle = fine_detail ? (n1 * 0.72 + n2 * 0.28) : n1;
		float warm = fine_detail ? n2 * mottle_warmth : 0.0;
		albedo *= 1.0 + mottle_amount * detail * vec3(mottle + warm, mottle, mottle - warm);
		rough += roughness_variation * detail * mottle;

		// Rain streaks on vertical faces, faded out before they get thinner than a pixel.
		float vertical = 1.0 - smoothstep(0.3, 0.6, abs(world_normal.y));
		float footprint = length(fwidth(p));
		float streak_fade = 1.0 - smoothstep(0.035, 0.09, footprint);
		if (vertical * streak_fade > 0.0) {
			float column = value_noise2(vec2(along / streak_width, 0.5));
			float length_mask = value_noise2(vec2(along / streak_width * 0.37 + 3.1, p.y / streak_length));
			float streak = smoothstep(0.58, 0.84, column) * smoothstep(0.35, 0.75, length_mask);
			albedo *= mix(vec3(1.0), streak_tint, streak * vertical * streak_fade * streak_strength * detail);
		}

		// Wet splash zone at the waterline (world height), with a ragged upper edge.
		float h = v_world.y - sea_level;
		float ragged = wet_edge_noise * (sin(along * 1.7) * 0.6 + sin(along * 4.3 + 1.3) * 0.4);
		float wet = 1.0 - smoothstep(wet_height * wet_full, wet_height, h + ragged);
		float algae = 1.0 - smoothstep(0.0, algae_height, h + ragged * 0.5);
		float submerged = 1.0 - smoothstep(-submerged_depth, 0.0, h);
		float paint_lum = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
		float darken = wet_darken * smoothstep(wet_paint_range.x, wet_paint_range.y, paint_lum);
		albedo *= mix(vec3(1.0), algae_tint, algae * detail);
		albedo *= (1.0 - darken * wet * detail) * (1.0 - submerged_darken * submerged * detail);
		rough = mix(rough, wet_roughness, wet * detail);
	}
	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
}
