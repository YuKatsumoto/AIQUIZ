// スカイゲートの紙のパネル（SkyGateBoard）。少し透ける紙に、破れた穴（ぎざぎざ）・光る枠の色・ひらめきを足す。
// UV の 0〜1 がパネルの見える範囲。穴の大きさは m で持つ（panel_size で UV を m にする）。
// 時間切れで体が当たったところのへこみ（dent_a・dent_b：UV の中心 xy・深さ z（m、下が +）・半径 w（m））を頂点で下げる。
// ふちは枠に留まっているので動かさない。まちがいのパネルは strain で赤く張りつめる（破れない）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 paper_color : source_color = vec4(0.56, 0.89, 0.71, 1.0);
uniform float paper_alpha = 0.9;
uniform vec2 panel_size = vec2(6.39, 3.34);
uniform vec2 hole_center = vec2(0.5, 0.5);
uniform float hole_radius = 0.0;
uniform float hole_seed = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float glow = 0.0;
uniform float flash = 0.0;
uniform vec4 dent_a = vec4(0.5, 0.5, 0.0, 1.25);
uniform vec4 dent_b = vec4(0.5, 0.5, 0.0, 1.25);
uniform float strain = 0.0;
// 通りすぎたボードが消えていく（1 → 0。SkyGateBoard.set_fade）
uniform float fade = 1.0;

varying float v_dent;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 穴のふちのぎざぎざ（SkyGateEffects.jag と同じ式）
float jag(float a, float seed) {
	return 0.16 * sin(a * 7.0 + seed) + 0.10 * sin(a * 13.0 + seed * 2.3) + 0.06 * sin(a * 29.0 + seed * 4.1);
}

// へこみの深さと、その傾き（m あたり）。形は体の大きさのやわらかい釣り鐘。
vec3 dent_of(vec2 uv, vec4 dent) {
	if (abs(dent.z) < 0.0001) {
		return vec3(0.0);
	}
	vec2 m = (uv - dent.xy) * panel_size;
	float k = 2.4 / max(dent.w * dent.w, 0.0001);
	float f = dent.z * exp(-dot(m, m) * k);
	return vec3(f, -2.0 * k * f * m);
}

void vertex() {
	// 2人が同じパネルに当たったら、深い方のへこみ（足すと深くなりすぎる）
	vec3 da = dent_of(UV, dent_a);
	vec3 db = dent_of(UV, dent_b);
	vec3 d = abs(da.x) >= abs(db.x) ? da : db;
	// 枠に留まったふちは動かない
	vec2 e = min(UV, 1.0 - UV) * panel_size;
	float pin = smoothstep(0.0, 0.6, min(e.x, e.y));
	VERTEX.y -= d.x * pin;
	// 面の y = -f なので、法線は (df/dx, 1, df/dz)（UV.y はローカルの +Z の向き）
	NORMAL = normalize(vec3(d.y * pin, 1.0, d.z * pin));
	v_dent = d.x * pin;
}

void fragment() {
	vec2 pm = UV * panel_size;
	float rim = 0.0;
	if (hole_radius > 0.001) {
		vec2 m = (UV - hole_center) * panel_size;
		float r = length(m);
		float edge_r = hole_radius * (1.0 + jag(atan(m.y, m.x), hole_seed));
		if (r < edge_r) {
			discard;
		}
		rim = 1.0 - smoothstep(0.0, 0.09, r - edge_r);
	}
	float fibre = vnoise(pm * 9.0) * 0.5 + vnoise(pm * 23.0) * 0.5;
	float wrinkle = vnoise(vec2(pm.x * 0.9 + pm.y * 0.4, pm.y * 2.6 - pm.x * 0.3) * 1.7);
	vec2 e = min(UV, 1.0 - UV) * panel_size;
	float shade = mix(0.84, 1.0, smoothstep(0.0, 0.42, min(e.x, e.y)));
	vec3 col = paper_color.rgb * (0.94 + 0.06 * fibre + 0.05 * wrinkle) * shade;
	// 光る枠のとき：紙を明るくし、ふちの近くに自分の色がにじむ
	float edge_glow = (1.0 - smoothstep(0.0, 0.7, min(e.x, e.y))) * glow;
	col = mix(col, vec3(1.0), glow * 0.22);
	col = mix(col, glow_color.rgb, edge_glow * 0.5);
	col = mix(col, vec3(1.0), rim * 0.7);
	// 張りつめた紙（まちがい）：へこんだところほど赤く
	float tense = strain * (0.88 + 0.12 * clamp(v_dent / 0.5, 0.0, 1.0));
	// 本戦の空は明るい（露出が高い）ので、暗い赤を混ぜないと桃色に飛ぶ
	col = mix(col, vec3(0.42, 0.03, 0.02), tense);
	col = mix(col, vec3(1.0), flash * 0.55);
	ALBEDO = col;
	ROUGHNESS = 0.82;
	// 横から見ると空の照り返しで色が飛ぶので、張りつめている間は照り返しを消す
	SPECULAR = 0.22 * (1.0 - tense);
	// 張りつめている間は紙自身の光（黄色っぽく飛ばす）を弱めて、赤く脈打たせる
	EMISSION = (paper_color.rgb * (0.07 + glow * 0.22) + glow_color.rgb * edge_glow * 0.35) * (1.0 - tense * 0.9) + vec3(flash * 0.9)
		// 斜面が影で黒くなる（穴に見える）のを、赤い光で埋める
		+ vec3(0.55, 0.04, 0.03) * tense * (0.75 + 0.25 * sin(TIME * 30.0));
	BACKLIGHT = paper_color.rgb * 0.55 * (1.0 - tense);
	ALPHA = clamp(mix(paper_alpha, 1.0, rim * 0.6 + flash * 0.3 + tense), 0.0, 1.0) * fade;
}
