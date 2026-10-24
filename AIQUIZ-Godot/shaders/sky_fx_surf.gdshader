shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

// スカイゲートの島の白波（SkyFallIslands、sky_fx_islands.glb の SFI_Surf）：波打ち際の帯と、礁の縁で砕ける帯。
// UV：x＝帯に沿った長さ（m ÷ 20）、y＝帯を横切る 0（内）..1（外）。頂点色 A＝強さ（ところどころ切れる）。
// 外から内へ寄せる波の列（うねり）と、細かい泡のノイズを流す。海（半透明）より後に描く（render_priority）。

uniform float strength = 1.0;
uniform float set_speed = 0.9;
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float t = TIME;
	float across = UV.y;
	float band = smoothstep(0.0, 0.22, across) * (1.0 - smoothstep(0.6, 1.0, across));
	float n1 = vnoise(vec2(UV.x * 4.0 + t * 0.12, across * 2.0 + t * 0.25));
	float n2 = vnoise(vec2(UV.x * 13.0 - t * 0.35, across * 6.0 - t * 0.5));
	float sets = 0.5 + 0.5 * sin(UV.x * 1.7 + n1 * 2.0 - t * set_speed + across * 5.0);
	float foam = band * smoothstep(0.42, 0.78, n1 * 0.45 + n2 * 0.35 + sets * 0.35);
	foam = max(foam, band * 0.35 * smoothstep(0.55, 0.85, n2));
	ALBEDO = foam_color;
	ALPHA = clamp(foam * COLOR.a * strength, 0.0, 1.0);
}
