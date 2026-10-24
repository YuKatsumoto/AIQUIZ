shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

// スカイゲートの海のサングリント（SkyFallSea の板。海面のすぐ上に重ねて足す）。
// 空から見下ろす海は、太陽が映る所（鏡の向き）のまわりだけが明るく光る。波の斜面のばらつき（風の強さ）で
// 光の広がりが決まる（Cox-Munk：風 5 m/s で斜面のばらつき約 0.17）。GGX の鏡面の山で、なめらかな光の帯にする。
// 風の弱い所（スリック）は波が細かくなくて鏡に近く、帯の中に明るい筋と暗い筋の模様が出る（大きなノイズで粗さを変える）。
// 海のシェーダー（shaders/ocean.gdshader、ステージの海）は変えずに、その上に足す。

uniform sampler2D slick_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.285, 0.866, -0.411);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.88);
uniform float intensity = 1.1;
uniform float roughness = 0.22;
uniform float slick_scale = 0.0009;
uniform float slick_strength = 0.7;
uniform float wave_scale = 0.006;
uniform float wave_tilt = 0.08;
uniform vec2 drift = vec2(0.6, 0.25);
uniform float fade = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 L = normalize(sun_dir);
	vec2 xz = world_pos.xz;
	float slick = texture(slick_noise, xz * slick_scale + drift * TIME * 0.0005).r;
	float w1 = texture(slick_noise, xz * wave_scale + drift * TIME * 0.004).r;
	float w2 = texture(slick_noise, xz * wave_scale * 2.7 - drift.yx * TIME * 0.006).r;
	// うねりの斜面（細かくは海のシェーダーの波。ここでは帯の中のむら）
	vec3 N = normalize(vec3((w1 - 0.5) * wave_tilt, 1.0, (w2 - 0.5) * wave_tilt));
	float rough = roughness * mix(1.0 - slick_strength * 0.55, 1.0 + slick_strength * 0.35, smoothstep(0.3, 0.7, slick));
	float a = rough * rough;
	float a2 = a * a;
	vec3 H = normalize(V + L);
	float ndh = max(dot(N, H), 0.0);
	float denom = ndh * ndh * (a2 - 1.0) + 1.0;
	float D = a2 / (PI * denom * denom);
	float ndl = max(dot(N, L), 0.0);
	float ndv = max(dot(N, V), 0.05);
	float F = 0.02 + 0.98 * pow(1.0 - max(dot(V, H), 0.0), 5.0);
	float spec = D * F * ndl / (4.0 * ndv);
	// 近いと光の点がまぶしくにじむ（グロー）ので、上限を抑える
	ALBEDO = sun_color * intensity * min(spec, 2.2) * fade;
}
