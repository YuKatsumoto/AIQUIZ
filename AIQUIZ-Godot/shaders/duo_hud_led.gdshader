shader_type canvas_item;

// 2P 対戦カード（scripts/ui/duo_player_status_card.gd）の LED 窓。地下神殿の水門の問題板と同じ、
// 黒い板に琥珀色の粒が灯る表示。正解数・「正解」・連続正解の炎と回数に使う。
// 粒の格子はカードの座標で決める（card_x / card_y / card_origin：キャンバス→カードの変換）。
// 文字が拡大して弾んでも格子は動かず、文字のほうが粒の上を動く。
// panel のとき：窓の板。暗い地に消えた粒を並べる。
// panel でないとき：文字と炎。灯った粒だけを通し、粒のあいだは gap_light だけ残す（小さい画面でも読めるように）。
// 窓（window、カードの座標の x, y, 幅, 高さ）の外は描かない。

uniform vec2 card_x = vec2(1.0, 0.0);
uniform vec2 card_y = vec2(0.0, 1.0);
uniform vec2 card_origin = vec2(0.0);
uniform vec4 window = vec4(0.0, 0.0, 1.0, 1.0);
uniform float pitch = 1.6;
uniform bool panel = false;
uniform vec3 panel_color : source_color = vec3(0.043, 0.043, 0.043);
uniform vec3 off_color : source_color = vec3(0.17, 0.105, 0.05);
uniform float gap_light = 0.5;
uniform float level = 1.0;

// 粒の半径（格子 1 マスに対する比）と、粒が画素より細かいときの平均の明るさ（π·r²）。
const float DOT_RADIUS = 0.38;
const float DOT_MEAN = 0.4536;

varying vec2 card_pos;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	card_pos = card_x * world.x + card_y * world.y + card_origin;
}

float dot_mask(vec2 p) {
	vec2 cell = p / pitch;
	float aa = max(fwidth(cell.x), 1e-4);
	float m = 1.0 - smoothstep(DOT_RADIUS - aa, DOT_RADIUS + aa, length(fract(cell) - 0.5));
	// 1 粒が 4 画素より細かくなるほど、ちらつかないよう平均へ寄せる
	return mix(m, DOT_MEAN, clamp(aa * 2.0 - 0.5, 0.0, 1.0));
}

void fragment() {
	vec2 rel = card_pos - window.xy;
	float inside = step(0.0, rel.x) * step(0.0, rel.y) * step(rel.x, window.z) * step(rel.y, window.w);
	float m = dot_mask(rel);
	if (panel) {
		COLOR = vec4(mix(panel_color, off_color, m), COLOR.a * inside);
	} else {
		COLOR.rgb *= mix(0.78, 1.12, m) * level;
		COLOR.a *= mix(gap_light, 1.0, m) * inside;
	}
}
