shader_type canvas_item;

// VS カットインの左右のパネル（仕様書 7）。画面いっぱいの ColorRect に描く。
// 稲妻の線（seam、画面の割合の 6 点）で左右に分け、左＝自分の色・右＝相手の色。
// 真ん中ほど明るい放射のグラデーション、網点（dot_px 間隔、12%）、集中線（36 本、8%、外へ流れる）、
// 周辺の暗がり（vignette：パネルの外の 3D も 30% まで暗くする）。
// slide_left / slide_right：パネルの横のずれ（画面の幅の割合。0 で定位置、入ってくるときは ∓1.2 から）。

uniform vec2 seam_0 = vec2(0.535, -0.02);
uniform vec2 seam_1 = vec2(0.475, 0.20);
uniform vec2 seam_2 = vec2(0.548, 0.36);
uniform vec2 seam_3 = vec2(0.462, 0.58);
uniform vec2 seam_4 = vec2(0.540, 0.76);
uniform vec2 seam_5 = vec2(0.488, 1.02);
uniform vec4 left_color : source_color = vec4(0.95, 0.55, 0.20, 1.0);
uniform vec4 right_color : source_color = vec4(0.20, 0.65, 0.90, 1.0);
uniform float slide_left = 0.0;
uniform float slide_right = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float lines : hint_range(0.0, 1.0) = 1.0;
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform float dot_px = 18.0;
uniform float time = 0.0;

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

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float sx = seam_x(uv.y);
	bool in_left = uv.x < sx + slide_left;
	bool in_right = uv.x > sx + slide_right;
	vec2 px = uv * rect_size;
	// 周辺の暗がり（画面の角ほど暗い）
	vec2 q = (uv - 0.5) * vec2(rect_size.x / rect_size.y, 1.0);
	float vig = smoothstep(0.35, 1.05, length(q)) * 0.30 * vignette;
	if (!in_left && !in_right) {
		COLOR = vec4(0.0, 0.0, 0.0, vig);
	} else {
		vec4 base = in_left ? left_color : right_color;
		// パネルの中心（それぞれの側の真ん中の少し上）ほど明るい
		vec2 centre = in_left ? vec2(0.24 + slide_left, 0.42) : vec2(0.76 + slide_right, 0.42);
		vec2 d = (uv - centre) * vec2(rect_size.x / rect_size.y, 1.0);
		float r = length(d);
		float glow = 1.0 - smoothstep(0.0, 0.85, r);
		vec3 col = mix(base.rgb * 0.62, mix(base.rgb, vec3(1.0, 0.97, 0.85), 0.42), glow);
		// 網点（中心から離れるほど大きい点）
		vec2 cell = fract(px / dot_px) - 0.5;
		float dot_r = mix(0.12, 0.36, smoothstep(0.1, 0.9, r));
		float dots = 1.0 - smoothstep(dot_r - 0.06, dot_r + 0.02, length(cell));
		col = mix(col, col * 1.25 + 0.05, dots * 0.12);
		// 集中線：中心からの角度で 36 本、外へ流れる短い線
		float a = atan(d.y, d.x) / 6.2831853 + 0.5;
		float idx = floor(a * 36.0);
		float ray = 1.0 - smoothstep(0.05, 0.13, abs(fract(a * 36.0) - 0.5) * 2.0);
		float dash = step(0.45, fract(r * 2.2 - time * 0.6 + hash11(idx) * 3.0));
		float spoke = ray * dash * smoothstep(0.18, 0.4, r) * lines;
		col = mix(col, vec3(1.0), spoke * 0.16);
		col *= 1.0 - vig;
		COLOR = vec4(col, 1.0);
	}
}
