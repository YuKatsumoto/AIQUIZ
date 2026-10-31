shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// shaders/menu_heli_shock_ring.gdshader のモバイル版（GraphicsQuality.is_mobile_target()）。
// 画面のコピーを読まない：後ろの絵のゆがみはなしで、輪の色（tint）とふちの明るさだけを足す。
// Mobile レンダラーでは画面テクスチャを読むたびに描画パスが分かれるため。uniform は元と同じ。

uniform bool billboard = false;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float radius : hint_range(0.0, 1.0) = 0.78;
uniform float width : hint_range(0.01, 0.6) = 0.16;
uniform float distortion = 0.035;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.25);

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	if (r > 1.0) {
		discard;
	}
	float d = r - radius;
	float band = d > 0.0 ? 1.0 - smoothstep(0.0, width * 0.55, d) : 1.0 - smoothstep(0.0, width * 1.6, -d);
	band *= 1.0 - smoothstep(0.92, 1.0, r);
	float fade = 1.0 - smoothstep(0.0, 1.0, progress);
	float k = band * fade;
	float rim = 1.0 - smoothstep(0.0, width * 0.5, abs(d - width * 0.15));
	// 元の絵では「後ろの絵＋色」を k × 1.4 の不透明度で重ねる。ゆがみの分を除いた、足される色だけを出す。
	ALBEDO = tint.rgb * tint.a * (0.55 * band + 0.45 * rim) * fade;
	ALPHA = clamp(k * 1.4, 0.0, 1.0);
}
