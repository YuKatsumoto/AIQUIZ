shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// メニューの「ゲーム開始」でヘリが発進するときの衝撃波（HelicopterArrivalDirector）。
// 2 × 2 の板（QuadMesh か PlaneMesh）に描く、ふちのやわらかい輪。輪の帯の中だけ後ろの絵を外へずらし（空気のゆがみ）、
// うすく色をのせる。広がる大きさは板の縮尺で、薄れ方は progress（0 → 1）で動かす。
// billboard = true でカメラを向く（空中の輪）。false なら板の向きのまま（甲板・海の上の輪）。

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform bool billboard = false;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float radius : hint_range(0.0, 1.0) = 0.78;    // 板の半径を 1 とした輪の中心
uniform float width : hint_range(0.01, 0.6) = 0.16;    // 輪の帯の半分の幅
uniform float distortion = 0.035;                      // 画面のずれ（UV）
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
	// 外側はくっきり、内側へ長く尾を引く帯
	float d = r - radius;
	float band = d > 0.0 ? 1.0 - smoothstep(0.0, width * 0.55, d) : 1.0 - smoothstep(0.0, width * 1.6, -d);
	band *= 1.0 - smoothstep(0.92, 1.0, r);
	float fade = 1.0 - smoothstep(0.0, 1.0, progress);
	float k = band * fade;
	vec2 outward = r > 0.0001 ? c / r : vec2(0.0);
	vec3 behind = textureLod(screen_texture, SCREEN_UV - vec2(outward.x, -outward.y) * distortion * k, 0.0).rgb;
	// 帯の外側のふちだけ少し明るく
	float rim = 1.0 - smoothstep(0.0, width * 0.5, abs(d - width * 0.15));
	ALBEDO = behind + tint.rgb * tint.a * (0.55 * band + 0.45 * rim) * fade;
	ALPHA = clamp(k * 1.4, 0.0, 1.0);
}
