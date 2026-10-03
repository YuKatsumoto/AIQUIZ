shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// LED face of the goal stand scoreboard (GS_ScoreboardScreen). The board's
// SubViewport is sampled once per LED; each LED is a round emitter behind a
// glossy black face, grouped into cabinet modules with thin seams.
//
// Viewport textures have no mipmaps, so far away one screen pixel covers many
// board texels and a single tap shimmers. GoalStandScoreboard keeps a GPU mip
// chain of the board (board_mip1..7, each half the previous size); the board is
// sampled trilinearly from it by the pixel's footprint, and the dot / seam
// pattern only appears once an LED is several pixels wide.

uniform sampler2D board : source_color, filter_linear, repeat_disable;
uniform sampler2D board_mip1 : source_color, filter_linear, repeat_disable;
uniform sampler2D board_mip2 : source_color, filter_linear, repeat_disable;
uniform sampler2D board_mip3 : source_color, filter_linear, repeat_disable;
uniform sampler2D board_mip4 : source_color, filter_linear, repeat_disable;
uniform sampler2D board_mip5 : source_color, filter_linear, repeat_disable;
uniform sampler2D board_mip6 : source_color, filter_linear, repeat_disable;
uniform sampler2D board_mip7 : source_color, filter_linear, repeat_disable;
uniform vec2 board_size = vec2(1400.0, 600.0);
uniform vec2 leds = vec2(448.0, 192.0);        // 2.5 cm pitch on the 11.2 x 4.8 m face
uniform vec2 module_leds = vec2(32.0, 32.0);
uniform float energy = 2.2;
uniform float black_level = 0.012;
uniform float dot_radius = 0.36;              // in LED cells

vec3 board_level(int level, vec2 uv) {
	if (level <= 0) {
		return texture(board, uv).rgb;
	} else if (level == 1) {
		return texture(board_mip1, uv).rgb;
	} else if (level == 2) {
		return texture(board_mip2, uv).rgb;
	} else if (level == 3) {
		return texture(board_mip3, uv).rgb;
	} else if (level == 4) {
		return texture(board_mip4, uv).rgb;
	} else if (level == 5) {
		return texture(board_mip5, uv).rgb;
	} else if (level == 6) {
		return texture(board_mip6, uv).rgb;
	}
	return texture(board_mip7, uv).rgb;
}

vec3 filtered_board(vec2 uv, vec2 du, vec2 dv) {
	float footprint = max(length(du * board_size), length(dv * board_size));
	float lod = clamp(log2(max(footprint, 1e-4)), 0.0, 7.0);
	int level = int(floor(lod));
	vec3 a = board_level(level, uv);
	vec3 b = board_level(min(level + 1, 7), uv);
	return mix(a, b, fract(lod));
}

void fragment() {
	vec2 du = dFdx(UV);
	vec2 dv = dFdy(UV);
	vec2 grid = UV * leds;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	// Screen pixels per LED. Dots resolve from ~3 px, fully from ~6 px.
	vec2 fw = fwidth(grid);
	float led_fw = max(max(fw.x, fw.y), 1e-4);
	float px = 1.0 / led_fw;
	float resolve = smoothstep(3.0, 6.0, px);
	vec3 smooth_color = filtered_board(UV, du, dv);
	vec3 color = smooth_color;
	float mask = 1.0;
	if (resolve > 0.0) {
		vec3 led_color = texture(board, (cell + 0.5) / leds).rgb;
		float coverage = 3.14159 * dot_radius * dot_radius;
		float d = length(local - 0.5);
		float edge = max(0.06, led_fw);
		float dots = (1.0 - smoothstep(dot_radius - edge, dot_radius + edge, d)) / coverage;
		// Module seams, anti-aliased by the LED footprint.
		vec2 m = fract(grid / module_leds) * module_leds;
		vec2 to_edge = min(m, module_leds - m);
		float seam_dist = min(to_edge.x, to_edge.y);
		float seam = 1.0 - smoothstep(0.2, 0.2 + max(led_fw, 0.05), seam_dist);
		mask = mix(1.0, dots * (1.0 - seam * 0.85), resolve);
		color = mix(smooth_color, led_color, resolve);
	}
	// LEDs dim off-axis.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float angle = mix(0.55, 1.0, smoothstep(0.1, 0.8, facing));
	ALBEDO = vec3(black_level);
	ROUGHNESS = 0.28;
	SPECULAR = 0.45;
	METALLIC = 0.0;
	EMISSION = color * mask * energy * angle;
}
