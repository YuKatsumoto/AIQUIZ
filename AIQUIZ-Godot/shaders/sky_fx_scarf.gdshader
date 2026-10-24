shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

// スカイゲートのマフラー（SkyFallScarf）。首の輪とはためく 2 本の端。毛糸の編み目（縦のうね・V の目）と、
// 端の近くの 2 本の白い線、先のふさ（すき間を捨てる）。裏も同じ色（両面）。
// UV：x＝幅を横切る 0..1、y＝長さ（端は根元 0 → 先 1、輪は 1 周で 0 → 1）。is_tail＝端か。

uniform vec3 base_color : source_color = vec3(0.94, 0.33, 0.14);
uniform vec3 stripe_color : source_color = vec3(0.98, 0.95, 0.86);
uniform bool is_tail = true;
uniform float ribs = 6.0;
uniform float stitch_rows = 46.0;
uniform float fringe_start = 0.93;

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float rib = 0.5 + 0.5 * cos(uv.x * 6.2831853 * ribs);
	float vx = abs(fract(uv.x * ribs) - 0.5);
	float stitch = 0.5 + 0.5 * cos((uv.y * stitch_rows + vx * 1.6) * 6.2831853);
	vec3 c = base_color * (0.78 + 0.22 * rib) * (0.9 + 0.1 * stitch);
	if (is_tail) {
		float s = step(0.74, uv.y) * step(uv.y, 0.785) + step(0.82, uv.y) * step(uv.y, 0.85);
		c = mix(c, stripe_color * (0.85 + 0.15 * rib), s);
		if (uv.y > fringe_start) {
			float k = floor(uv.x * 9.0);
			float strand = abs(fract(uv.x * 9.0) - 0.5);
			float reach = fringe_start + (1.0 - fringe_start) * (0.65 + 0.35 * hash1(k + 3.0));
			if (strand > 0.26 || uv.y > reach) {
				discard;
			}
			c *= 0.92;
		}
	} else {
		// 輪：結び目の側（uv.y の 0 付近）は少しふくらんで暗い
		c *= 0.9 + 0.1 * smoothstep(0.0, 0.12, min(uv.y, 1.0 - uv.y));
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
