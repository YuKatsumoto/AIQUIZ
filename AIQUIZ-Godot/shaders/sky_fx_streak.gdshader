shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

// スカイゲートの風の筋（SkyFallWind の帯）：手足と頭から後ろへ流れる白い筋、飛行機雲、小舟の航跡。
// 帯の UV：x＝根元 0 → 先 1、y＝帯を横切る 0..1。頂点色：r＝模様のずらし、a＝濃さ。
// 先ほど薄く、横のふちは柔らかく、流れる筋の模様（ノイズ）を流す。

uniform vec3 color : source_color = vec3(1.0, 1.0, 1.0);
uniform float opacity = 1.0;
uniform float flow_speed = 7.0;
uniform float grain = 6.0;
uniform float edge_soft = 0.65;
uniform float tail_power = 1.0;
uniform float head_soft = 0.06;
// 足し算ふう（白い筋が青い海の上で灰色に濁らない）：色を 1 より明るくして、濃さは控えめに
uniform bool additive = false;

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
	float along = UV.x;
	float across = abs(UV.y - 0.5) * 2.0;
	float body = 1.0 - smoothstep(1.0 - edge_soft, 1.0, across);
	float fade = pow(clamp(1.0 - along, 0.0, 1.0), tail_power) * smoothstep(0.0, head_soft, along);
	float n = vnoise(vec2(along * grain - TIME * flow_speed, UV.y * 3.0 + COLOR.r * 31.0));
	float strands = 0.55 + 0.45 * n;
	float a = body * fade * strands * COLOR.a * opacity;
	ALBEDO = additive ? color * 1.6 : color;
	ALPHA = additive ? a * 0.75 : a;
}
