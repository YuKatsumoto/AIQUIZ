shader_type canvas_item;

// 中央の線が開く遷移（仕様書 S10、v1.4）。SceneTransition の hold_versus_split が画面いっぱいに置く。
// 写し取ったカットインの画面（screen_tex）を稲妻の線（seam、画面の割合の 6 点）で左右に切る。
// 読み込みが終わると（reveal_current）、SceneTransition が次の値を動かす：
//   strike  0〜1  両陣営の色を編んだ稲妻の頭が、線に沿って上から下へ走る（通ったところは光ったまま）
//   charge  0〜1  線の光が太く明るくなる（溜め）。crack は髪の毛ほどのすき間（px）
//   open    0〜1  左右の半分が外へ開く（外へ傾き、大きくなりながら）。切り口は自分の陣営の色で光る
//   shake_l / shake_r  左右の半分それぞれの振動（px）。重い扉がこすれ合うように別々に震えながら開く（v1.6）
//   burst   0〜1  線から光の壁が横へ広がり、光の筋と衝撃の輪が出て消える
// 切れたところの下は次の画面（透明）。白い光で画面全体を覆うことはしない（仕様書 16）。

uniform sampler2D screen_tex : filter_linear, repeat_disable;
uniform vec2 seam_0 = vec2(0.535, -0.02);
uniform vec2 seam_1 = vec2(0.475, 0.20);
uniform vec2 seam_2 = vec2(0.548, 0.36);
uniform vec2 seam_3 = vec2(0.462, 0.58);
uniform vec2 seam_4 = vec2(0.540, 0.76);
uniform vec2 seam_5 = vec2(0.488, 1.02);
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform vec4 left_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform vec4 right_color : source_color = vec4(0.25, 0.65, 1.0, 1.0);
uniform float strike : hint_range(0.0, 1.0) = 0.0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float crack = 0.0;
uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform float burst : hint_range(0.0, 1.0) = 0.0;
uniform float fx_time = 0.0;
uniform vec2 shake_l = vec2(0.0);
uniform vec2 shake_r = vec2(0.0);
// 飛ぶ距離（画面の幅に対して）・外への傾き（度）・大きくなる割合
uniform float travel = 0.62;
uniform float tilt_deg = 5.0;
uniform float grow = 0.10;

float seam_x(float y) {
	vec2 p[6] = vec2[6](seam_0, seam_1, seam_2, seam_3, seam_4, seam_5);
	if (y <= p[0].y) {
		return p[0].x;
	}
	for (int i = 0; i < 5; i++) {
		if (y <= p[i + 1].y) {
			float t = (y - p[i].y) / max(p[i + 1].y - p[i].y, 0.0001);
			return mix(p[i].x, p[i + 1].x, t);
		}
	}
	return p[5].x;
}

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// 稲妻の頭の高さ（画面の割合）。線の上の端から下の端まで
float head_y() {
	return mix(seam_0.y, seam_5.y, strike);
}

// 両陣営の色をまぜた光の色（y と時刻でゆっくり入れ替わる）
vec3 mixed_color(float y) {
	float k = 0.5 + 0.5 * sin(y * 18.0 + fx_time * 5.0);
	return mix(left_color.rgb, right_color.rgb, k);
}

// 片方の半分の中で、画面の点（px）が写し取った画面のどこ（px）に当たるか
vec2 piece_px(vec2 p, float side) {
	vec2 pivot = vec2(side < 0.0 ? 0.25 : 0.75, 0.5) * rect_size;
	vec2 moved = p - vec2(side * (open * travel * rect_size.x + crack), 0.0) - (side < 0.0 ? shake_l : shake_r);
	float s = 1.0 + grow * open;
	vec2 d = (moved - pivot) / s;
	float a = -side * radians(tilt_deg) * open;
	vec2 r = vec2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
	return r + pivot;
}

// 線分 a-b までの距離（px）
float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
	return length(p - (a + ab * t));
}

void fragment() {
	vec2 p = UV * rect_size;
	vec4 col = vec4(0.0);
	float hy = head_y();
	float lit_any = strike > 0.0 ? 1.0 : 0.0;
	// 太さは 1080 の高さを基準に画面の大きさへ合わせる
	float S = rect_size.y / 1080.0;
	// ---- 左右の半分 ----
	for (int k = 0; k < 2; k++) {
		float side = k == 0 ? -1.0 : 1.0;
		vec2 qp = piece_px(p, side);
		vec2 q = qp / rect_size;
		if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) {
			continue;
		}
		float edge = q.x - seam_x(q.y);
		bool inside = side < 0.0 ? edge <= 0.0 : edge >= 0.0;
		if (!inside) {
			continue;
		}
		vec4 c = texture(screen_tex, q);
		// 切り口の光：稲妻が通ったところ（上から頭まで）は光ったまま。溜めで太く、開くと自分の陣営の色で尾を引く
		float d = abs(edge) * rect_size.x;
		float passed = lit_any * smoothstep(hy + 0.015, hy - 0.015, q.y);
		// 稲妻と溜めのあいだ、線から離れた所を暗くして光を目立たせる（開くと戻る）
		float dim = 0.38 * max(charge, 0.5 * strike * lit_any) * (1.0 - smoothstep(0.0, 0.35, open));
		c.rgb *= 1.0 - dim * (1.0 - exp(-d / (260.0 * S)));
		float width = (8.0 + 40.0 * charge + 30.0 * open) * S;
		vec3 own = side < 0.0 ? left_color.rgb : right_color.rgb;
		vec3 tint = mix(mixed_color(q.y), own, smoothstep(0.0, 0.3, open));
		float glow = exp(-d / width) * passed * (0.6 + 0.6 * charge) * (1.0 - smoothstep(0.55, 1.0, open));
		float core = exp(-d / ((2.0 + 5.0 * charge) * S)) * passed * (0.3 + 0.7 * charge) * (1.0 - smoothstep(0.2, 0.7, open));
		c.rgb = c.rgb + tint * glow * 1.1;
		c.rgb = mix(c.rgb, vec3(1.0), clamp(core, 0.0, 1.0));
		col = c;
	}
	// ---- 溜めのすき間（開く前）：下の画面ではなく、あふれる光で埋める ----
	if (col.a <= 0.0 && open <= 0.0) {
		col = vec4(mix(mixed_color(UV.y), vec3(1.0), 0.75), 1.0);
	}
	// ---- 割れ目から出る光（開いてから）：横へ広がる光の壁・光の筋・衝撃の輪 ----
	if (burst > 0.0) {
		float sx = seam_x(UV.y) * rect_size.x;
		float dx = p.x - sx;
		float e = 1.0 - pow(1.0 - burst, 3.0);
		float fade = pow(1.0 - burst, 1.6);
		float wall_w = 30.0 + e * rect_size.x * 0.42;
		float wall = exp(-abs(dx) / wall_w) * fade;
		vec3 wall_col = mix(left_color.rgb, right_color.rgb, smoothstep(-wall_w, wall_w, dx));
		wall_col = mix(wall_col, vec3(1.0), exp(-abs(dx) / (14.0 + 40.0 * e)) * 0.8);
		vec2 centre = vec2(seam_x(0.5) * rect_size.x, rect_size.y * 0.5);
		vec2 rel = p - centre;
		float ang = atan(rel.y, rel.x);
		float rays = pow(max(sin(ang * 16.0 + fx_time * 1.5) * 0.5 + 0.5, 0.0), 10.0);
		rays *= exp(-length(rel) / (rect_size.x * (0.25 + 0.5 * e))) * fade;
		float ring_r = e * rect_size.x * 0.9;
		float ring = exp(-abs(length(rel * vec2(1.0, 1.6)) - ring_r) / (22.0 * S)) * fade * 0.8;
		vec3 light = wall_col * wall + mixed_color(UV.y) * (rays * 0.7 + ring);
		float light_a = clamp(wall * 0.9 + rays * 0.6 + ring * 0.7, 0.0, 0.92);
		if (col.a > 0.0) {
			col.rgb += light;
		} else {
			col = vec4(light / max(light_a, 0.001), light_a);
		}
	}
	// ---- 稲妻（両陣営の色の 2 本が編むように線を下りる。白い芯・明るい頭・枝） ----
	float bolt_fade = (1.0 - smoothstep(0.0, 0.35, burst)) * lit_any;
	if (bolt_fade > 0.0 && UV.y <= hy + 0.03) {
		float y = UV.y;
		// ぎざぎざは時間で少しずつ這うように変える（点滅させない）
		float jag = (noise1(y * 46.0 + fx_time * 9.0) - 0.5) * 16.0 * S;
		float xb = seam_x(y) * rect_size.x + jag;
		float braid = sin(y * rect_size.y / (30.0 * S) - fx_time * 14.0) * 20.0 * S;
		float d1 = abs(p.x - (xb + braid));
		float d2 = abs(p.x - (xb - braid));
		float above = smoothstep(hy + 0.004, hy - 0.004, y);
		// 2 本の筋はそれぞれの陣営の色そのまま（白にとばさない）。白い芯は 2 本が交わる所だけ
		vec3 c1 = left_color.rgb * 1.15;
		vec3 c2 = right_color.rgb * 1.15;
		float s1 = exp(-d1 / (3.2 * S)) * 0.95 + exp(-d1 / (16.0 * S)) * 0.5;
		float s2 = exp(-d2 / (3.2 * S)) * 0.95 + exp(-d2 / (16.0 * S)) * 0.5;
		float coreb = exp(-abs(p.x - xb) / (1.8 * S)) * smoothstep(9.0 * S, 0.0, abs(braid));
		// 溜めのあいだは稲妻ごと太く明るくなる
		float swell = 1.0 + 0.5 * charge;
		vec3 bolt = ((c1 * s1 + c2 * s2) + vec3(1.0) * coreb) * above * swell;
		float bolt_a = clamp((s1 + s2) * 0.85 + coreb, 0.0, 1.0) * above;
		// 頭：まぜた色の大きな光の玉と、横へのびる光の筋
		vec2 head = vec2(seam_x(hy) * rect_size.x, hy * rect_size.y);
		vec2 hr = p - head;
		float hd = length(hr);
		float strike_live = 1.0 - smoothstep(0.97, 1.0, strike);
		float streak = exp(-abs(hr.y) / (4.0 * S)) * exp(-abs(hr.x) / (260.0 * S));
		float head_glow = (exp(-hd / (16.0 * S)) + exp(-hd / (90.0 * S)) * 0.75 + streak * 0.9) * strike_live;
		bolt += mix(mixed_color(hy), vec3(1.0), exp(-hd / (14.0 * S))) * head_glow * 1.3;
		bolt_a = max(bolt_a, clamp(head_glow, 0.0, 1.0));
		// 枝：線の折れ目を頭が過ぎると、左右へ短い枝が出て消えていく
		vec2 pts[4] = vec2[4](seam_1, seam_2, seam_3, seam_4);
		for (int i = 0; i < 4; i++) {
			float age = (hy - pts[i].y) / 0.18;
			if (age <= 0.0 || age >= 1.0) {
				continue;
			}
			vec2 a = pts[i] * rect_size;
			float dir = (i % 2 == 0) ? -1.0 : 1.0;
			vec2 b = a + vec2(dir * 150.0, 110.0) * S;
			vec2 m = mix(a, b, 0.5) + vec2(dir * 22.0, -30.0) * S * (noise1(fx_time * 20.0 + float(i)) - 0.5) * 2.0;
			float db = min(seg_dist(p, a, m), seg_dist(p, m, b));
			float br = (exp(-db / (2.6 * S)) + exp(-db / (12.0 * S)) * 0.5) * (1.0 - age);
			bolt += mix(i % 2 == 0 ? c1 : c2, vec3(1.0), 0.4) * br;
			bolt_a = max(bolt_a, clamp(br, 0.0, 1.0));
		}
		bolt *= bolt_fade;
		bolt_a *= bolt_fade;
		if (col.a > 0.0) {
			// スクリーン合成：重なっても白くとびにくく、色が残る
			col.rgb = vec3(1.0) - (vec3(1.0) - col.rgb) * (vec3(1.0) - clamp(bolt, 0.0, 1.0));
		} else {
			col = vec4(bolt / max(bolt_a, 0.001), bolt_a);
		}
	}
	COLOR = col;
}
