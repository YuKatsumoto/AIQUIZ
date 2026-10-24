shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

// 雲の中の白さ（docs/sudden_death_v2/c130_float.md 第10章）。画面いっぱいの板に、カメラからの深さで濃くなる霧を描く。
// 雲の層の中を飛ぶとき、遠い景色ほど白く消え、近い機体はうっすら見える（雲の覆いの画面推移の代わりの、本物の雲の中）。
// start より近いもの（機内にカメラがあるときの機内）は霧をかけない。濃さはワールドの 3D ノイズでむらを付ける（雲のかたまり）。

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float density = 0.0;          // 1/m
uniform float start = 0.0;            // m
uniform float max_alpha = 1.0;
uniform vec3 fog_color : source_color = vec3(0.92, 0.94, 0.97);
uniform vec3 shade_color : source_color = vec3(0.70, 0.75, 0.82);
uniform vec3 sun_dir = vec3(0.5, 0.7, -0.4);   // 太陽へ向かう向き（ワールド）
uniform vec3 drift = vec3(0.0);                 // ノイズの流れ（m。ノイズの空間）
uniform mat3 noise_basis = mat3(1.0);           // ワールド → ノイズの空間の向き（雲の中の入れ替えで、むらを機体と一緒に運ぶ）
uniform float patchiness = 0.55;
uniform int samples = 3;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y), mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise3(p);
		p = p * 2.07 + vec3(3.1, 1.7, 5.3);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 view = upos.xyz / max(abs(upos.w), 1e-6) * sign(upos.w);
	float dist = length(view);
	if (depth <= 0.000001) {
		dist = 1.0e6;
	}
	vec3 ray = normalize(view);
	vec3 ray_world = normalize((INV_VIEW_MATRIX * vec4(ray, 0.0)).xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	// 光の通る長さ：start から先。むら：視線の上の数点でノイズを読む（近い所ほど細かく）
	float path = max(dist - start, 0.0);
	float n = 0.0;
	float wsum = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= samples) {
			break;
		}
		float d = start + min(path, 6.0 + 18.0 * float(i * i + i));
		vec3 wp = noise_basis * (cam + ray_world * d) + drift;
		float scale = 0.045 / (1.0 + float(i) * 0.6);
		float w = 1.0 / (1.0 + float(i));
		n += fbm(wp * scale) * w;
		wsum += w;
	}
	n /= max(wsum, 0.001);
	float local_density = density * mix(1.0, 0.35 + 1.3 * n, patchiness);
	float fog = 1.0 - exp(-local_density * path);
	// 太陽の側は明るく、反対と下は少し影
	float sun = clamp(dot(ray_world, normalize(sun_dir)) * 0.5 + 0.5, 0.0, 1.0);
	float below = clamp(-ray_world.y, 0.0, 1.0);
	vec3 col = mix(shade_color, fog_color, clamp(0.55 + 0.45 * sun - 0.25 * below + (n - 0.5) * 0.3, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(fog * max_alpha, 0.0, 1.0);
}
