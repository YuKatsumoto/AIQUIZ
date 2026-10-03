shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// メインメニューのステージ（assets/aiquiz_menu_stage）の LED 画面。AMS_LedScreen を置き換える。
// 2026-10-01 から発進デッキは組み立てていない（AiquizMenuStage.BUILD_LAUNCH_DECK）ので、いまは使われない。
// 番組はゴール側の電光掲示板（goal_stand_scoreboard_led.gdshader）で映す。
// use_program のとき：LED 番組（MenuLedProgram の SubViewport、1296×588）を映す。ビューポートの
// 画像にはミップが無いので、番組側が半分ずつ縮めた program_mip1..4 を GPU で作り、遠くでは画素の
// 大きさに合う段から、LED の粒が見える近さでは粒 1 個（6×6 画素）の平均を取る。
// use_program でないとき（番組が読めない）：濃紺の地に、左は橙（P1）・右は水色（P2）の斜めの帯が流れ、
// ときどき看板の画像（AIQUIZ のロゴ）を映す。
// LED の粒（dots 個）ごとに色を決めて、粒のあいだを暗くする。画面は自ら光る（EMISSION）。
// 看板の画像は横長（sign_aspect）なので、画面の縦横比（screen_aspect）に合わせて上下に地の色を足して映す。

uniform vec3 base_col : source_color = vec3(0.055, 0.086, 0.17);
uniform vec3 orange : source_color = vec3(0.949, 0.549, 0.2);
uniform vec3 blue : source_color = vec3(0.2, 0.651, 0.902);
uniform float speed = 0.32;
uniform float stripes = 3.2;
uniform float energy : hint_range(0.0, 8.0) = 1.9;
uniform vec2 dots = vec2(216.0, 98.0);
uniform sampler2D logo : source_color, filter_linear_mipmap_anisotropic;
uniform bool use_logo = true;
uniform float screen_aspect = 2.21;
uniform float sign_aspect = 3.82;
uniform float logo_period = 11.0;
uniform float logo_hold = 3.2;
uniform bool use_program = false;
uniform sampler2D program : source_color, filter_linear, repeat_disable;
uniform sampler2D program_mip1 : source_color, filter_linear, repeat_disable;
uniform sampler2D program_mip2 : source_color, filter_linear, repeat_disable;
uniform sampler2D program_mip3 : source_color, filter_linear, repeat_disable;
uniform sampler2D program_mip4 : source_color, filter_linear, repeat_disable;
uniform vec2 program_size = vec2(1296.0, 588.0);

// Mean of the round-dot mask over one LED cell: what a grid of sub-pixel LEDs
// averages out to on screen.
const float DOT_MASK_MEAN = 0.357;

vec3 stripes_at(vec2 cell) {
	float t = cell.x * stripes + cell.y * 1.9 - TIME * speed;
	float band = step(fract(t), 0.42);
	float k = smoothstep(0.44, 0.56, cell.x);
	vec3 col = mix(orange, blue, k);
	float centre = exp(-pow((cell.x - 0.5) / 0.13, 2.0));
	// 帯のふちを少し明るく（流れが読みやすいように）
	float edge = smoothstep(0.36, 0.42, fract(t)) * band;
	return mix(base_col, col * (1.0 + 0.35 * edge), band * (1.0 - 0.85 * centre));
}

vec3 logo_at(vec2 cell, vec2 uv_dx, vec2 uv_dy) {
	// 横幅を合わせ、縦は看板の比に合わせて中央に置く
	float squash = sign_aspect / screen_aspect;
	float v = 0.5 + (cell.y - 0.5) * squash;
	// Filter by the pixel's own footprint: quantized LED coordinates have no
	// usable derivatives, and no fetch may depend on divergent control flow.
	vec2 scale = vec2(1.0, squash);
	vec3 picture = textureGrad(logo, vec2(cell.x, clamp(v, 0.0, 1.0)), uv_dx * scale, uv_dy * scale).rgb;
	return (v < 0.0 || v > 1.0) ? base_col : picture;
}

vec3 screen_image(vec2 cell, vec2 uv_dx, vec2 uv_dy) {
	vec3 img = stripes_at(cell);
	if (use_logo) {
		float phase = mod(TIME, logo_period);
		float show = smoothstep(0.0, 0.4, phase) * (1.0 - smoothstep(logo_hold, logo_hold + 0.4, phase));
		// 切り替えは上から下へ走査するように
		float sweep = step(1.0 - cell.y, show * 1.02);
		img = mix(img, logo_at(cell, uv_dx, uv_dy), sweep);
	}
	return img;
}

vec3 program_level(int level, vec2 uv) {
	if (level <= 0) {
		return texture(program, uv).rgb;
	} else if (level == 1) {
		return texture(program_mip1, uv).rgb;
	} else if (level == 2) {
		return texture(program_mip2, uv).rgb;
	} else if (level == 3) {
		return texture(program_mip3, uv).rgb;
	}
	return texture(program_mip4, uv).rgb;
}

// Trilinear between the programme's half-size copies.
vec3 program_at(vec2 uv, float lod) {
	lod = clamp(lod, 0.0, 4.0);
	int level = int(floor(lod));
	return mix(program_level(level, uv), program_level(min(level + 1, 4), uv), fract(lod));
}

void fragment() {
	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	vec2 grid = UV * dots;
	// Screen pixels per LED. The dot grid appears from ~1.5 px per LED and fully
	// from ~3 px; smaller LEDs alias into moire (the menu camera sees ~1.3 px at
	// 1440p), so the image then shows unquantized at the grid's average glow, as
	// on the goal stand scoreboard.
	vec2 fw = fwidth(grid);
	float resolve = smoothstep(1.5, 3.0, 1.0 / max(max(fw.x, fw.y), 1e-4));
	vec2 cell = (floor(grid) + 0.5) / dots;
	vec3 img;
	if (use_program) {
		// Far: filtered by the pixel's footprint. Near: one LED shows the mean of its cell.
		float footprint = max(length(uv_dx * program_size), length(uv_dy * program_size));
		vec3 far_img = program_at(UV, log2(max(footprint, 1.0)));
		vec3 led_img = program_at(cell, log2(program_size.x / dots.x));
		img = mix(far_img, led_img, resolve);
	} else {
		img = mix(screen_image(UV, uv_dx, uv_dy), screen_image(cell, uv_dx, uv_dy), resolve);
	}
	vec2 f = fract(grid) - 0.5;
	float dot_mask = mix(DOT_MASK_MEAN, clamp(1.25 - length(f) / 0.42, 0.0, 1.0), resolve);
	vec3 lit = img * (0.2 + 0.9 * dot_mask);
	ALBEDO = vec3(0.02);
	ROUGHNESS = 0.35;
	SPECULAR = 0.4;
	EMISSION = lit * energy;
}
