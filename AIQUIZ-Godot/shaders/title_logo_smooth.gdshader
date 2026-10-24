shader_type canvas_item;
render_mode unshaded;

// タイトルロゴの文字の面と厚みの縁をならす（scripts/ui/title_logo/title_logo_intro.gd の Faces・Depth：CanvasGroup）。
// Godot 4 の Polygon2D は縁をなめらかに描かず、CanvasGroup の中には画面の MSAA も届かないので、
// グループに描いた絵を、まわりの点との重み付きの平均（3×3 のテント）で少しだけならし、縁の階段を消す。
// 中の塗りはまわりも同じ色なので変わらない。グループの絵は乗算済みのアルファなので、平均してから割り戻す。

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
// ならす幅（画面ピクセル）
uniform float radius_px = 0.6;

void fragment() {
	vec2 d = SCREEN_PIXEL_SIZE * radius_px;
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0) * 4.0;
	c += textureLod(screen_texture, SCREEN_UV + vec2(d.x, 0.0), 0.0) * 2.0;
	c += textureLod(screen_texture, SCREEN_UV - vec2(d.x, 0.0), 0.0) * 2.0;
	c += textureLod(screen_texture, SCREEN_UV + vec2(0.0, d.y), 0.0) * 2.0;
	c += textureLod(screen_texture, SCREEN_UV - vec2(0.0, d.y), 0.0) * 2.0;
	c += textureLod(screen_texture, SCREEN_UV + d, 0.0);
	c += textureLod(screen_texture, SCREEN_UV - d, 0.0);
	c += textureLod(screen_texture, SCREEN_UV + vec2(d.x, -d.y), 0.0);
	c += textureLod(screen_texture, SCREEN_UV + vec2(-d.x, d.y), 0.0);
	c /= 16.0;
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	COLOR *= c;
}
