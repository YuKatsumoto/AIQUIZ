shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_front, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// スカイゲートの体積雲（SkyFallClouds の MultiMesh。1 つの箱 = 1 つの雲）。
// 参考：ユーザーが示した UE の体積雲（レイマーチで体積の濃さと光を積む。shaderbits の volumetric ray marcher）と同じ方式。
//   形：焼いた 3D の濃さ（sky_fx_cloud_shapes.res、形 6 つを y 方向に積んだもの）を箱の中で読む。
//   ふち：くり返す細かいノイズ（sky_fx_cloud_detail.res の Perlin-Worley と Worley）で外側から削る（ちぎれ・すじ）。
//   光：太陽へ向かって数歩進んで、途中の濃さで光が弱まる（Beer の法則）。前へ散る強い山と後ろへ散る弱い山の
//       Henyey-Greenstein の位相関数（太陽を背にした雲のふちが光る）。多重散乱の近似（薄い吸収の光も足す）。
//       空の光（上は明るい青、下は海の照り返しの暗い青）。エネルギーを保つ積み方（Hillaire 2015）。
//   深さ：不透明なもの（島・人形・ボードの枠）の手前で止める（深さのテクスチャ）。カメラが雲の中でも描く（裏の面）。
// INSTANCE_CUSTOM：r＝形の番号 / 8、g＝濃さの倍率 / 2、b＝0.5 以上で雲海の穴を使う＋模様のずらし、a＝出方（0..1）。
// 前後の順は SkyFallClouds が毎フレーム遠い順に並べる。

uniform sampler3D shape_tex : filter_linear, repeat_disable;
uniform sampler3D detail_tex : filter_linear, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

uniform int shape_count = 6;
uniform int shape_slices = 64;
uniform int shape_pad = 2;

group_uniforms Light;
uniform vec3 sun_dir = vec3(0.533, 0.742, -0.407);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.9);
uniform float sun_intensity = 3.4;
uniform vec3 sky_top : source_color = vec3(0.50, 0.66, 0.96);
uniform vec3 sky_bottom : source_color = vec3(0.22, 0.32, 0.46);
uniform float ambient_intensity = 0.62;
uniform float phase_forward = 0.62;
uniform float phase_back = -0.18;
uniform float phase_mix = 0.32;
uniform float multi_scatter = 0.38;
uniform float powder = 0.5;

group_uniforms Medium;
uniform float extinction = 0.15;
uniform float scatter_albedo = 0.985;
uniform float detail_scale = 0.024;
uniform float detail_strength = 0.55;
uniform float fine_scale = 0.11;
uniform float fine_strength = 0.3;
uniform vec3 wind = vec3(0.6, 0.15, 0.25);
uniform float global_fade = 1.0;

group_uniforms Quality;
uniform int steps = 40;
uniform int light_steps = 4;
uniform float light_reach = 110.0;
uniform bool fine_detail = true;

group_uniforms Hole;
uniform vec2 hole_center = vec2(0.0);
uniform float hole_radius = 0.0;
uniform float hole_soft = 40.0;

group_uniforms Haze;
uniform vec3 haze_color : source_color = vec3(0.66, 0.80, 0.97);
uniform float haze_distance = 3200.0;
uniform float haze_max : hint_range(0.0, 1.0) = 0.4;
group_uniforms;

varying vec3 v_local;
varying vec3 v_cam_local;
varying vec3 v_sun_local;
varying vec3 v_world;
varying flat vec3 v_scale;
varying flat vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	mat3 m = mat3(MODEL_MATRIX);
	v_scale = vec3(length(m[0]), length(m[1]), length(m[2]));
	vec3 origin = MODEL_MATRIX[3].xyz;
	float fade = INSTANCE_CUSTOM.a * global_fade;
	if (INSTANCE_CUSTOM.b >= 0.5) {
		vec2 d2 = origin.xz - hole_center;
		float ang = atan(d2.y, d2.x);
		float r = hole_radius * (1.0 + 0.14 * sin(ang * 3.0 + 1.3) + 0.08 * sin(ang * 7.0 + 0.4));
		fade *= smoothstep(r, r + hole_soft, length(d2));
	}
	v_custom.a = fade;
	mat4 inv = inverse(MODEL_MATRIX);
	v_cam_local = (inv * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	v_sun_local = normalize((inv * vec4(sun_dir, 0.0)).xyz);
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (fade < 0.003) {
		VERTEX = vec3(0.0);
	}
}

float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.566371 * pow(max(1.0 + g2 - 2.0 * g * c, 1e-4), 1.5));
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float shape_at(vec3 p, float w0, float total) {
	vec3 uvw = p + 0.5;
	if (any(lessThan(uvw, vec3(0.0))) || any(greaterThan(uvw, vec3(1.0)))) {
		return 0.0;
	}
	float w = (w0 + uvw.y * float(shape_slices)) / total;
	return texture(shape_tex, vec3(uvw.x, uvw.z, w)).r;
}

void fragment() {
	vec3 ro = v_cam_local;
	vec3 rd = normalize(v_local - ro);
	vec3 inv_rd = 1.0 / rd;
	vec3 ta = (vec3(-0.5) - ro) * inv_rd;
	vec3 tb = (vec3(0.5) - ro) * inv_rd;
	vec3 tmin = min(ta, tb);
	vec3 tmax = max(ta, tb);
	float t_enter = max(max(tmin.x, tmin.y), max(tmin.z, 0.0));
	float t_exit = min(min(tmax.x, tmax.y), tmax.z);
	// 不透明なものの手前で止める
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	sv.xyz /= sv.w;
	float t_frag = length(v_local - ro);
	float frac = sv.z / min(VERTEX.z, -1e-4);
	t_exit = min(t_exit, t_frag * frac);
	if (t_exit <= t_enter || v_custom.a < 0.003) {
		discard;
	}
	float total = float(shape_count * (shape_slices + shape_pad * 2));
	float shape_index = floor(v_custom.r * 8.0 + 0.5);
	float w0 = shape_index * float(shape_slices + shape_pad * 2) + float(shape_pad);
	float dens_scale = v_custom.g * 2.0 * v_custom.a;
	float seed = fract(v_custom.b * 2.0) * 97.0;
	float world_per_t = length(rd * v_scale);
	float sun_per_t = max(length(v_sun_local * v_scale), 1e-4);
	vec3 view_world = normalize(v_world - CAMERA_POSITION_WORLD);
	float cos_t = dot(view_world, normalize(sun_dir));
	float phase = mix(hg(cos_t, phase_back), hg(cos_t, phase_forward), phase_mix) * 12.566371;
	float phase_soft = mix(hg(cos_t, phase_back * 0.5), hg(cos_t, phase_forward * 0.5), phase_mix) * 12.566371;
	vec3 sun = sun_color * sun_intensity;
	vec3 drift = wind * TIME;

	int n = max(steps, 4);
	float dt = (t_exit - t_enter) / float(n);
	float ds = dt * world_per_t;
	float t = t_enter + dt * ign(FRAGCOORD.xy);
	float T = 1.0;
	vec3 L = vec3(0.0);
	for (int i = 0; i < n; i++) {
		vec3 p = ro + rd * t;
		t += dt;
		float base = shape_at(p, w0, total);
		if (base < 0.01) {
			continue;
		}
		// 焼いた形のふちの柔らかい帯を締める（芯は 1 のまま）
		base = smoothstep(0.02, 0.7, base);
		// ふちを削る：外側（base が小さい所）ほど深く削れ、芯は残る
		vec3 q = p * v_scale + vec3(seed);
		vec2 nz = texture(detail_tex, (q + drift) * detail_scale).rg;
		float er = nz.r * detail_strength;
		float d = clamp((base - er) / max(1.0 - er, 0.05), 0.0, 1.0);
		if (fine_detail && d > 0.0 && d < 0.6) {
			float fn = texture(detail_tex, (q + drift * 1.7) * fine_scale).g * fine_strength;
			d = clamp((d - fn) / max(1.0 - fn, 0.05), 0.0, 1.0);
		}
		d *= dens_scale;
		if (d < 0.003) {
			continue;
		}
		float sigma = d * extinction;
		// 太陽へ向かって数歩：途中の濃さ（形だけ。細かいノイズは省く）で光が弱まる
		float tau = 0.0;
		float prev = 0.0;
		for (int j = 1; j <= light_steps; j++) {
			float u = float(j) / float(light_steps);
			float dist = light_reach * u * u;
			float seg = dist - prev;
			prev = dist;
			vec3 lp = p + v_sun_local * ((dist - seg * 0.5) / sun_per_t);
			tau += shape_at(lp, w0, total) * dens_scale * extinction * seg;
		}
		float beer = exp(-tau);
		float soft = exp(-tau * 0.22) * multi_scatter;
		float pw = mix(1.0, 1.0 - exp(-sigma * 40.0), powder);
		vec3 uvw = p + 0.5;
		// 空の光：上は青空、下は海の照り返し。雲の奥ほど届かない（太陽へ向かう濃さで近似）
		vec3 amb = mix(sky_bottom, sky_top, smoothstep(0.05, 0.95, uvw.y)) * ambient_intensity * (0.3 + 0.7 * exp(-tau * 0.5));
		vec3 S = sun * (beer * phase + soft * phase_soft) * pw + amb;
		float Ts = exp(-sigma * ds);
		L += T * S * (1.0 - Ts) * scatter_albedo;
		T *= Ts;
		if (T < 0.015) {
			T = 0.0;
			break;
		}
	}
	float alpha = 1.0 - T;
	if (alpha < 0.002) {
		discard;
	}
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float haze = min(haze_max, 1.0 - exp(-dist / haze_distance));
	L = mix(L, haze_color * alpha, haze);
	ALBEDO = L;
	ALPHA = alpha;
}
