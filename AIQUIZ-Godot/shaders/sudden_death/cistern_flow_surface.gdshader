shader_type spatial;
// 地下神殿の水面（docs/sudden_death_underground.md 6.6節）。CisternFlow の流体シミュレーションが毎フレーム
// 書き出す表示用の画像（r = 水面の高さ m、gb = 流速 m/s、a = 泡の量、乾いたセルは -1）で、格子の各点
// （セルの中心に1頂点）を水面の高さへ動かし、隣のセルの高さから法線を作る。水が流れる向きと速さで
// 細かい波の法線と泡の模様を運び（2つの位相を交互に混ぜるフローマップ）、流れの速い所・水が寄せる所
// （シミュレーションの泡）と岸辺ほど白くする。下の床とタワーの足元は屈折して見え、深さで濁りに沈む。
// 反射は反射プローブ（Godot の画面空間反射は半透明に効かない）、高画質以上は短い画面空間の反射を辿る。
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D display_tex : filter_nearest, repeat_disable;
uniform vec2 grid_origin = vec2(-45.0, -30.0);
uniform float grid_cell = 0.3;
uniform ivec2 grid_size = ivec2(300, 320);

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D water_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 murk_color : source_color = vec3(0.085, 0.076, 0.058);
uniform vec3 foam_color : source_color = vec3(0.74, 0.77, 0.76);
// Per metre of water: the floor 1.2 m down is barely seen, a tower foot just under the surface shows.
uniform float absorption = 2.6;
uniform float refraction = 0.035;
uniform float normal_strength = 0.95;
uniform float base_foam = 0.07;
uniform float clock = 0.0;
// Screen-space reflection march (0 = probes only).
uniform int ssr_steps = 0;
uniform float ssr_strength = 0.6;

varying vec3 v_world;
varying vec2 v_vel;
varying float v_wet;

ivec2 cell_of(vec2 xz) {
	return clamp(ivec2(floor((xz - grid_origin) / grid_cell)), ivec2(0), grid_size - 1);
}

float neighbour_height(ivec2 c, float fallback) {
	vec4 d = texelFetch(display_tex, clamp(c, ivec2(0), grid_size - 1), 0);
	// A dry neighbour (a shore, a tower, a pillar) does not tilt the surface.
	return d.a < -0.5 ? fallback : d.r;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ivec2 c = cell_of(world.xz);
	vec4 d = texelFetch(display_tex, c, 0);
	// The node sits at the hall floor: the sim's heights are over the floor.
	VERTEX.y = d.r;
	float h_left = neighbour_height(c - ivec2(1, 0), d.r);
	float h_right = neighbour_height(c + ivec2(1, 0), d.r);
	float h_back = neighbour_height(c - ivec2(0, 1), d.r);
	float h_front = neighbour_height(c + ivec2(0, 1), d.r);
	NORMAL = normalize(vec3(h_left - h_right, 2.0 * grid_cell, h_back - h_front));
	TANGENT = normalize(vec3(2.0 * grid_cell, h_right - h_left, 0.0));
	BINORMAL = normalize(cross(TANGENT, NORMAL));
	v_vel = d.gb;
	v_wet = d.a;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float scene_linear_depth(vec2 uv, mat4 inv_projection) {
	float d = texture(depth_tex, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -view.z / view.w;
}

void fragment() {
	// The dry node of a shore triangle lies on the floor: the water thins out to nothing toward it.
	if (v_wet < -0.97) {
		discard;
	}
	float shore = 1.0 - smoothstep(-0.97, 0.05, v_wet);
	float edge = smoothstep(-0.97, -0.35, v_wet);
	float churn = clamp(max(v_wet, 0.0), 0.0, 1.2);
	vec2 flow = v_vel;
	float speed = length(flow);
	// Flow map: two phases half a cycle apart, each pulled along the current, cross-faded so neither
	// stretches too far.
	float cycle = clock * 0.55;
	float phase0 = fract(cycle);
	float phase1 = fract(cycle + 0.5);
	float weight = abs(1.0 - 2.0 * phase0);
	vec2 w = v_world.xz;
	vec2 drift0 = flow * phase0 * 0.9;
	vec2 drift1 = flow * phase1 * 0.9;
	vec2 n0 = texture(water_normal, (w - drift0) * 0.13).xy * 2.0 - 1.0;
	vec2 n1 = texture(water_normal, (w - drift1) * 0.13 + vec2(0.37, 0.61)).xy * 2.0 - 1.0;
	vec2 m0 = texture(water_normal, (w - drift0 * 1.4) * 0.31 + vec2(0.21, 0.05)).xy * 2.0 - 1.0;
	vec2 m1 = texture(water_normal, (w - drift1 * 1.4) * 0.31 + vec2(0.71, 0.44)).xy * 2.0 - 1.0;
	vec2 nxy = mix(n1, n0, weight) * 0.6 + mix(m1, m0, weight) * 0.4;
	nxy *= normal_strength * (0.55 + 0.45 * clamp(speed / 2.5, 0.0, 1.0) + 0.5 * churn);
	vec3 nts = normalize(vec3(nxy, 1.0));
	NORMAL_MAP = nts * 0.5 + 0.5;

	// Foam: the simulation's white water, laced with a texture carried by the same flow.
	float lace0 = texture(foam_tex, (w - drift0 * 1.1) * 0.19).r;
	float lace1 = texture(foam_tex, (w - drift1 * 1.1) * 0.19 + vec2(0.5, 0.25)).r;
	float streak0 = texture(foam_tex, (w - drift0) * vec2(0.09, 0.05) * 2.0).b;
	float streak1 = texture(foam_tex, (w - drift1) * vec2(0.09, 0.05) * 2.0 + vec2(0.3, 0.8)).b;
	float lace = mix(lace1, lace0, weight) * 0.65 + mix(streak1, streak0, weight) * 0.45;
	float cover = clamp(base_foam + 0.4 * churn + 0.3 * shore + 0.04 * clamp(speed - 1.0, 0.0, 3.0), 0.0, 0.8);
	float foam = smoothstep(1.0 - cover, 1.0 - cover + 0.22, lace);
	foam = max(foam, smoothstep(0.85, 1.3, churn) * 0.85);

	// Refraction with depth absorption.
	float surface_depth = -VERTEX.z;
	vec2 ruv = SCREEN_UV + nxy * refraction;
	float floor_depth = scene_linear_depth(ruv, INV_PROJECTION_MATRIX);
	if (floor_depth < surface_depth) {
		ruv = SCREEN_UV;
		floor_depth = scene_linear_depth(ruv, INV_PROJECTION_MATRIX);
	}
	float thickness = max(floor_depth - surface_depth, 0.0);
	vec3 view_dir = normalize(-VERTEX);
	float water_depth = thickness * clamp(abs(dot(view_dir, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz)), 0.2, 1.0);
	float transmit = exp(-absorption * water_depth);
	vec3 below = textureLod(screen_tex, ruv, 0.0).rgb;
	// Contact foam where the water wraps a tower or a pillar (something solid just under the surface).
	float contact = 1.0 - smoothstep(0.04, 0.35, water_depth);
	foam = max(foam, contact * 0.75 * (0.35 + 0.65 * lace));

	vec3 reflected = vec3(0.0);
	if (ssr_steps > 0) {
		vec3 n_view = normalize(TANGENT * nts.x + BINORMAL * nts.y + NORMAL * nts.z);
		vec3 r = reflect(-view_dir, n_view);
		vec3 p = VERTEX;
		for (int i = 0; i < 24; i++) {
			if (i >= ssr_steps) {
				break;
			}
			p += r * (0.35 + float(i) * 0.25);
			vec4 clip = PROJECTION_MATRIX * vec4(p, 1.0);
			vec2 suv = clip.xy / clip.w * 0.5 + 0.5;
			if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
				break;
			}
			float scene = scene_linear_depth(suv, INV_PROJECTION_MATRIX);
			if (-p.z > scene + 0.05 && -p.z < scene + 2.0) {
				float edge = smoothstep(0.0, 0.12, min(min(suv.x, 1.0 - suv.x), min(suv.y, 1.0 - suv.y)));
				reflected = textureLod(screen_tex, suv, 0.0).rgb * edge;
				break;
			}
		}
		float fres = 0.02 + 0.98 * pow(1.0 - max(dot(view_dir, n_view), 0.0), 5.0);
		reflected *= fres * ssr_strength * (1.0 - foam);
	}

	ALBEDO = mix(murk_color * (1.0 - transmit), foam_color, foam);
	EMISSION = below * transmit * (1.0 - foam) + reflected;
	ROUGHNESS = mix(0.04, 0.55, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
	// The thin leading edge of the flood fades in over the dry floor.
	ALPHA = mix(1.0, 0.35, shore * (1.0 - foam)) * edge;
}
