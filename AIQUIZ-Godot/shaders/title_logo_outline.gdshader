shader_type canvas_item;
render_mode unshaded;

// タイトルロゴの文字の太い縁（scripts/ui/title_logo/title_logo_intro.gd の Outline：CanvasGroup）。
// グループに描いた文字のブロックの形（不透明度）を、まわりの点の最大で外へ radius_px だけ広げ、縁の色で塗る。
// 元の形（Polygon2D）は縁がなめらかでないので、広げる幅を radius_px ± EDGE_SOFT の 2 通りで測って平均し、
// 縁取りの外の縁を 2 段にならす（平均の太さは radius_px のまま）。

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 outline_color : source_color = vec4(0.04, 0.06, 0.125, 1.0);
// 縁の太さ（画面ピクセル。画面の解像度に合わせてスクリプトが決める）
uniform float radius_px = 6.0;
const float EDGE_SOFT = 0.4;

void fragment() {
	float center = textureLod(screen_texture, SCREEN_UV, 0.0).a;
	float near = center;
	float far = center;
	float r_near = max(radius_px - EDGE_SOFT, 0.0);
	float r_far = radius_px + EDGE_SOFT;
	for (int i = 0; i < 24; i++) {
		vec2 dir = vec2(cos(float(i) * TAU / 24.0), sin(float(i) * TAU / 24.0)) * SCREEN_PIXEL_SIZE;
		near = max(near, textureLod(screen_texture, SCREEN_UV + dir * r_near, 0.0).a);
		near = max(near, textureLod(screen_texture, SCREEN_UV + dir * r_near * 0.5, 0.0).a);
		far = max(far, textureLod(screen_texture, SCREEN_UV + dir * r_far, 0.0).a);
	}
	float a = 0.5 * (near + max(near, far));
	COLOR = vec4(outline_color.rgb, outline_color.a * a);
}
