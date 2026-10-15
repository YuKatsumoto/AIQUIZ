shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// 離陸のときにローターの風が海に立てる水しぶきの輪（仕様書 S3）。平らな板（PlaneMesh）の上に、
// 半径 radius の白い泡の輪を描く。fade で全体を薄くする。座標は板のローカル（m）。

uniform float radius = 2.0;
uniform float width = 1.6;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 1.0);

varying vec2 v_xz;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_xz = VERTEX.xz;
}

void fragment() {
	float r = length(v_xz);
	float a = atan(v_xz.y, v_xz.x);
	float band = 1.0 - smoothstep(0.0, width, abs(r - radius));
	float inner = smoothstep(radius * 0.2, radius, r) * 0.35;
	float n = vnoise(vec2(a * 9.0, r * 1.3 - TIME * 3.0)) * 0.6 + vnoise(v_xz * 0.9 + TIME) * 0.4;
	float foam = clamp(band * (0.55 + n) + inner * n * band, 0.0, 1.0);
	ALBEDO = foam_color;
	ALPHA = clamp(foam * fade * 0.85, 0.0, 1.0);
}
