shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;

// 開いた後ろの扉から差し込む光の筋（docs/sudden_death_v2/c130_float.md 第10章）。機内を覆う箱の中を、視線に沿って
// 数歩ずつたどり、光の中にある所の空気（ほこり・もや）の明るさを足していく。光の中かどうかは、その点から光の来る向きへ
// さかのぼって、スロープの付け根の面（z ＝ hinge_z）の開いている四角（横 ±half_w、高さ y_low〜y_high）を通るかで決める。
// 座標は機体のローカル（world_to_plane）。人や壁より奥はたどらない（深さ）。

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform mat4 world_to_plane;
uniform vec3 light_dir = vec3(0.1, -0.3, -0.95);   // 光の進む向き（機体のローカル、前へ下へ）
uniform float hinge_z = 4.6;
uniform float half_w = 1.5;
uniform float y_low = 9.0;
uniform float y_high = -9.0;
uniform float floor_y = 1.9;
uniform vec3 box_min = vec3(-2.0, 1.9, -3.5);
uniform vec3 box_max = vec3(2.0, 5.6, 4.9);
uniform vec3 light_color : source_color = vec3(1.0, 0.95, 0.86);
uniform float intensity = 0.0;
uniform float haze = 0.05;
uniform float time = 0.0;
uniform int steps = 12;

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

// その点に光が届く割合（ふちは少し柔らかく）
float lit(vec3 p) {
	vec3 back = -normalize(light_dir);
	float s = (hinge_z - p.z) / max(back.z, 0.05);
	if (s < 0.0) {
		return 0.0;
	}
	vec3 h = p + back * s;
	float soft = 0.06 + s * 0.012;
	float ax = 1.0 - smoothstep(half_w - soft, half_w + soft, abs(h.x));
	float ay = smoothstep(y_low - soft, y_low + soft, h.y) * (1.0 - smoothstep(y_high - soft, y_high + soft, h.y));
	return ax * ay * step(floor_y - 0.02, p.y);
}

void fragment() {
	if (intensity <= 0.0001 || y_high <= y_low) {
		discard;
	}
	vec3 cam_w = INV_VIEW_MATRIX[3].xyz;
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 view = upos.xyz / upos.w;
	float scene_dist = length(view);
	vec3 dir_w = normalize((INV_VIEW_MATRIX * vec4(normalize(view), 0.0)).xyz);
	vec3 ro = (world_to_plane * vec4(cam_w, 1.0)).xyz;
	vec3 rd = normalize((world_to_plane * vec4(dir_w, 0.0)).xyz);
	// 箱との交わり
	vec3 inv = 1.0 / rd;
	vec3 t0 = (box_min - ro) * inv;
	vec3 t1 = (box_max - ro) * inv;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	float enter = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
	float leave = min(min(min(tmax.x, tmax.y), tmax.z), scene_dist);
	if (leave <= enter) {
		discard;
	}
	float len = leave - enter;
	float stepl = len / float(steps);
	float jitter = hash13(vec3(FRAGCOORD.xy, time * 13.0));
	float acc = 0.0;
	for (int i = 0; i < 24; i++) {
		if (i >= steps) {
			break;
		}
		vec3 p = ro + rd * (enter + (float(i) + jitter) * stepl);
		float l = lit(p);
		if (l > 0.0) {
			// 空気のむら（ゆっくり流れる）
			float n = noise3(p * 2.6 + vec3(0.0, time * 0.12, time * 0.3)) * 0.6 + noise3(p * 7.0 - vec3(time * 0.2)) * 0.4;
			acc += l * (0.75 + 0.5 * n) * stepl;
		}
	}
	ALBEDO = light_color * acc * haze * intensity;
	ALPHA = 1.0;
}
