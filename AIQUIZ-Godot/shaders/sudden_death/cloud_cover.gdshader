shader_type canvas_item;

// 雲の覆い（docs/sudden_death_v2/common.md 5.3節）。カメラが雲の層を抜ける間、雲の模様が
// 画面の中心から外へ流れて手前を覆い、真っ白になってから晴れる。テクスチャは使わない（値のノイズ）。
// amount：0 = なし、1 = 真っ白。travel：雲の中を進んだ量（模様が中心から外へ広がる）。

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float travel = 0.0;
uniform vec3 cloud_light : source_color = vec3(0.97, 0.98, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.74, 0.79, 0.86);
uniform vec2 aspect = vec2(1.7778, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 5; i++) {
		total += value_noise(p) * weight;
		p = p * 2.03 + vec2(17.1, 9.2);
		weight *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 centered = (UV - 0.5) * aspect;
	float radius = length(centered);
	vec2 dir = radius > 0.0001 ? centered / radius : vec2(0.0, 1.0);
	// Two layers flowing outward from the centre at different speeds: flying into the bank.
	float near_layer = fbm(dir * 2.2 + vec2(0.0, 1.0 / (radius + 0.25) - travel * 1.6));
	float far_layer = fbm(centered * 3.4 + vec2(travel * 0.7, -travel * 0.4));
	float density = mix(far_layer, near_layer, 0.65);
	// The edges cover first; the centre last (the gap ahead closes).
	float edge = smoothstep(0.05, 0.75, radius);
	float cover = clamp(amount * 1.45 - (1.0 - edge) * 0.45 + (density - 0.5) * 0.9, 0.0, 1.0);
	cover = smoothstep(0.0, 1.0, cover);
	cover = max(cover, smoothstep(0.82, 1.0, amount));
	float shade = clamp(density * 1.3 - 0.15, 0.0, 1.0);
	vec3 color = mix(cloud_shade, cloud_light, shade);
	color = mix(color, cloud_light, smoothstep(0.85, 1.0, amount));
	COLOR = vec4(color, cover);
}
