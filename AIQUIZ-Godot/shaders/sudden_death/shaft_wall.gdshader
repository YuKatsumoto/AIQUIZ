shader_type spatial;
// Shaft concrete (assets/environment/shaft_descent). Unshaded: the baked lamp lightmap
// (shaft_wall_light.png, white light of a 5-tile stack) is the diffuse light, the analytic
// sodium term adds wet specular highlights, and world-space noise in wall coordinates
// (w = local_y - scroll) breaks up the 5 m repeat so no two rows look alike.
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://shaders/sudden_death/shaft_common.gdshaderinc"

uniform sampler2D wall_masks : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_light : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
// shaft_bake.json light_max_over_C
uniform float light_max = 3.17;
uniform float wetness = 1.0;
uniform float detail_strength = 0.6;
uniform float bake_relight = 1.4;
uniform float spec_strength = 2.2;
// > 1 deepens the dark between lamp rows (the bake includes the soft bounce light).
uniform float light_gamma = 1.5;
uniform vec3 concrete_tint : source_color = vec3(1.0, 0.985, 0.955);

varying vec3 v_local;

void vertex() {
	v_local = shaft_local_point(MODEL_MATRIX, VERTEX);
}

void fragment() {
	if (shaft_clipped(v_local)) {
		discard;
	}
	vec4 m = texture(wall_masks, UV);
	vec4 nt = texture(wall_normal, UV);
	float w = v_local.y - scroll;
	// Macro breakup, attached to the wall (moves with scroll): 8 cells around, 6 m tall.
	vec2 mc = vec2(UV.x * 8.0, w / 6.0);
	float n1 = texture(macro_noise, mc).r;
	float n2 = texture(macro_noise, vec2(UV.x * 5.0 + 0.31, w / 17.0 + 0.17)).r;
	float n3 = texture(macro_noise, mc * 2.7 + vec2(0.53, 0.71)).r;
	float n4 = texture(macro_noise, vec2(UV.x * 40.0 + 0.13, w / 9.0 + 0.41)).r;

	// Wetness: the baked seepage varies per row; long damp columns run through several rows.
	float column = smoothstep(0.58, 0.74, n4) * smoothstep(0.35, 0.65, n2);
	float wet = m.g * (0.6 + 1.8 * n1);
	wet = max(wet, smoothstep(0.52, 0.76, n2) * 0.55 * (0.5 + 0.5 * n3));
	wet = max(wet, column * 0.85);
	wet = clamp(wet * wetness, 0.0, 1.0);
	float effl = clamp(m.b * (0.7 + 1.8 * n3), 0.0, 1.0);
	float rust = clamp(m.a * (0.6 + 0.8 * n1), 0.0, 1.0);
	float tone = m.r * (0.78 + 0.44 * n3) * (0.9 + 0.2 * n1);

	vec3 base = vec3(tone) * concrete_tint;
	base *= mix(1.0, 0.38, wet);
	base = mix(base, vec3(0.66, 0.66, 0.62), effl * 0.9);
	base = mix(base, vec3(0.32, 0.135, 0.045) * (0.55 + 1.5 * m.r), rust * 0.8);
	base *= mix(1.0, nt.a, 0.9);
	float rough = mix(0.88, 0.14, wet);
	rough = mix(rough, 0.95, effl * 0.6);

	// Tangent-space relief: baked macro normal + 1 m micro detail (+ a slow water film).
	vec2 nxy = nt.xy * 2.0 - 1.0;
	vec2 duv = vec2(UV.x * 44.0, w);
	vec2 dxy = texture(detail_normal, duv).xy * 2.0 - 1.0;
	vec2 film = texture(detail_normal, vec2(duv.x * 0.5, duv.y * 0.35 + TIME * 0.22)).xy * 2.0 - 1.0;
	nxy += dxy * detail_strength * (1.0 - wet * 0.6) + film * wet * 0.35;
	vec3 nts = normalize(vec3(nxy, 1.0));
	vec3 n_view = normalize(TANGENT * nts.x + BINORMAL * nts.y + NORMAL * nts.z);
	vec3 n = shaft_local_dir(INV_VIEW_MATRIX, n_view);
	vec3 ng = shaft_local_dir(INV_VIEW_MATRIX, NORMAL);
	vec3 cam = (shaft_inv * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 v = normalize(cam - v_local);

	float diff = 0.0;
	vec3 spec = vec3(0.0);
	vec3 l0 = vec3(0.0, 1.0, 0.0);
	shaft_lamps(v_local, n, v, rough, vec3(0.03), 1, true, diff, spec, l0);
	float baked = pow(texture(wall_light, UV).r, 2.2 * light_gamma) * light_max;
	float relight = clamp(1.0 + bake_relight * (dot(n, l0) - dot(ng, l0)), 0.25, 2.2);
	vec3 lamp = lamp_color * lamp_strength * lamps_on;
	vec3 col = base * baked * relight * lamp;
	col += spec * lamp * spec_strength * (0.25 + 0.75 * wet);
	float day = shaft_daylight(v_local, n);
	col += base * day * daylight_color;
	if (day > 0.0) {
		vec3 sky_l = normalize(vec3(0.0, clip_top, 0.0) - v_local);
		col += daylight_color * daylight * daylight_strength * 0.05 * shaft_ggx(n, v, sky_l, rough) * max(dot(n, sky_l), 0.0) * wet;
	}
	col += base * shaft_beacons(v_local, n);
	col += base * ambient_floor;
	ALBEDO = col;
}
