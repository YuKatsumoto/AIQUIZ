// Body of the surge tank hall materials. Defines chosen by the wrapper shaders:
//   TK_WORLD_UV  textures projected from world space (walls, beams, coffers, floor: seamless across the slices)
//   TK_FLOOR     wet concrete floor: silt, damp, puddles (near-mirror), dried mud cracks
//   TK_CUTOUT    alpha-scissor gratings, both faces
//   TK_PAINT     painted steel: vertex colour tints the albedo where its alpha is 1
// Lighting model: tank_common.gdshaderinc.

#ifdef TK_CUTOUT
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;
#else
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;
#endif

#include "res://shaders/surge_tank/tank_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// R = AO, G = roughness, B = metallic (glTF order).
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Module light map (UV2): RGB = (E / light_max)^(1/2.2), A = baked AO.
uniform sampler2D light_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 albedo_tint : source_color = vec3(1.0);
// Metres per texture repeat (world projection) or UV0 scale (mesh UVs).
uniform float uv_metres = 3.75;
uniform float uv_scale = 1.0;
uniform float detail_strength = 0.45;
uniform float normal_strength = 1.0;
uniform float roughness_scale = 1.0;
uniform float roughness_min = 0.0;
uniform float metallic_value = 0.0;
uniform float light_max = 1.0;
uniform float light_scale = 1.0;
uniform float cavity_strength = 0.35;
uniform float macro_strength = 0.12;
// Darker, glossier seepage on walls and pillars.
uniform float seepage = 0.25;
uniform float floor_y = -1.2;
// Look-dev: 1 = baked light on white Lambert.
uniform int debug_view = 0;
#ifdef TK_FLOOR
uniform vec3 silt_color : source_color = vec3(0.42, 0.33, 0.22);
uniform vec3 mud_color : source_color = vec3(0.30, 0.27, 0.23);
// Fraction of the slab under standing water (0..1) and how far the water line wobbles.
uniform float puddle_amount = 0.42;
uniform float puddle_roughness = 0.035;
uniform float damp_roughness = 0.22;
uniform float damp_darkening = 0.32;
// How wet the slab is away from the puddles (0 = dry patches between the puddles, 1 = a wet film everywhere).
uniform float damp_base = 0.15;
uniform float silt_amount = 0.6;
// Dried, cracked mud: strongest toward the shaft end (water stands there longest after a flood).
uniform float mud_amount = 0.55;
uniform float mud_z_fade = 12.0;
#endif

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

#ifdef TK_FLOOR
vec2 tk_hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Cellular edges (0 on a crack, 1 inside a plate) for the dried mud.
float tk_cracks(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + tk_hash2(cell + o) * 0.85 + 0.075 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return smoothstep(0.0, 0.09, sqrt(d2) - sqrt(d1));
}
#endif

void fragment() {
	vec3 wn = normalize(v_world_normal);
	// plan coordinates: textures, dirt and the plan lookups scale with the stage
	vec3 pp = vec3(v_world.x, v_world.y - floor_y, v_world.z) / tank_scale;
	vec2 uv;
	vec3 ng = NORMAL;
	vec3 tan_v;
	vec3 up_v;
#ifdef TK_WORLD_UV
	vec2 wuv;
	vec3 tu_w;
	vec3 tup_w;
	tk_world_plane(pp, wn, wuv, tu_w, tup_w);
	uv = wuv / uv_metres;
	tan_v = normalize((VIEW_MATRIX * vec4(tu_w, 0.0)).xyz);
	up_v = normalize((VIEW_MATRIX * vec4(tup_w, 0.0)).xyz);
#else
	uv = UV * uv_scale;
	tan_v = TANGENT;
	up_v = BINORMAL;
#endif
	vec4 albedo_sample = texture(albedo_tex, uv);
	vec3 albedo = albedo_sample.rgb * albedo_tint;
#ifdef TK_PAINT
	albedo = mix(albedo, albedo * COLOR.rgb, albedo_sample.a);
#endif
#ifdef TK_CUTOUT
	ALPHA = albedo_sample.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	vec3 orm = texture(orm_tex, uv).rgb;
	vec2 nxy = (texture(normal_tex, uv).xy * 2.0 - 1.0) * normal_strength;
	nxy += (texture(detail_normal_tex, uv * uv_metres).xy * 2.0 - 1.0) * detail_strength;
	vec4 lm = texture(light_tex, UV2);
	vec2 plane = wn.y > 0.7 || wn.y < -0.7 ? pp.xz : (abs(wn.x) > abs(wn.z) ? pp.zy : pp.xy);
	float macro = tk_macro(macro_noise, plane);
	float fine = texture(macro_noise, plane * 0.61 + vec2(0.5, 0.2)).r;
	albedo *= 1.0 + macro_strength * (macro * 2.0 - 1.0) + 0.06 * (fine - 0.5);
	float rough = clamp(orm.g * roughness_scale * (0.92 + 0.16 * fine), max(roughness_min, 0.02), 1.0);
	float metal = orm.b * metallic_value;
	// height over the trench floor in plan metres; the water of the current game is in world metres
	float height = pp.y;
	float water_height = v_world.y - floor_y;

#ifdef TK_FLOOR
	vec2 xz = pp.xz;
	float big = tk_macro(macro_noise, xz * 0.55 + vec2(11.0, 3.0));
	float wobble = texture(macro_noise, xz * 0.13 + vec2(0.31, 0.62)).r;
	// silt: rings round the pillar feet, drifts against the walls, patches
	float dp = tk_pillar_distance(xz);
	float dw = tk_wall_half(xz.y) - abs(xz.x);
	// on the trench floor the silt drifts against the foot of the slopes instead of the walls
	float dt = tk_trench_crest(xz.y) - 2.9 - abs(xz.x);
	float in_trench = 1.0 - smoothstep(1.5, 3.0, height);
	float edge = mix(dw - 2.6, dt, in_trench);
	float silt = silt_amount * max(max(smoothstep(1.8, 0.2, dp + (wobble - 0.5) * 1.2), smoothstep(4.5, 1.0, edge + (wobble - 0.5) * 2.0)),
		smoothstep(0.62, 0.78, big * 0.8 + wobble * 0.35));
	// standing water in the low spots (large patches, sharp shore), damp around it
	float pnoise = big * 0.75 + wobble * 0.25 + (fine - 0.5) * 0.05;
	float th = 1.0 - puddle_amount * 0.92;
	float puddle = smoothstep(th - 0.012, th + 0.012, pnoise) * (1.0 - 0.7 * smoothstep(0.2, 0.7, silt));
	float damp = clamp(smoothstep(th - 0.14, th, pnoise) * (1.0 - damp_base) + damp_base, 0.0, 1.0);
	// the water has passed: everything soaked
	float flood = tk_flooded(v_world, macro);
	puddle = max(puddle, flood * smoothstep(0.45, 0.6, pnoise));
	damp = max(damp, flood);
	// dried mud plates near the shaft end
	float mud_mask = mud_amount * smoothstep(mud_z_fade, -38.6, xz.y + (big - 0.5) * 18.0) * (1.0 - puddle) * smoothstep(0.35, 0.6, big + wobble * 0.3);
	float plates = tk_cracks(xz * 1.6 + vec2(big * 0.6, wobble * 0.6));
	albedo = mix(albedo, silt_color * (0.85 + 0.3 * fine), silt);
	albedo = mix(albedo, mud_color * (0.8 + 0.4 * fine) * mix(0.45, 1.0, plates), mud_mask);
	albedo *= (1.0 - damp_darkening * damp * (1.0 - mud_mask)) * (1.0 - 0.22 * puddle);
	rough = mix(rough, damp_roughness, damp * (1.0 - mud_mask));
	rough = mix(rough, 0.85, mud_mask);
	rough = mix(rough, 0.55, silt * 0.6);
	rough = mix(rough, puddle_roughness, puddle);
	nxy *= (1.0 - puddle) * (1.0 + mud_mask * (1.0 - plates) * 2.0);
#else
	// seepage streaks, darker and glossier, on vertical concrete
	float streak = texture(macro_noise, vec2(plane.x * 0.21, plane.y * 0.035) + vec2(0.31, 0.77)).r;
	float seep = seepage * smoothstep(0.55, 0.8, streak * 0.7 + macro * 0.5) * (1.0 - abs(wn.y));
	// wet foot and the line the water reached (when the hall has been flooded)
	float flood_line = 3.0 + (fine - 0.5) * 1.3 + (macro - 0.5) * 0.8;
	float flood = tk_flooded(v_world, macro) * (1.0 - smoothstep(flood_line - 0.6, flood_line, water_height));
	float foot = smoothstep(0.5, 0.0, height - tk_floor_height(pp.xz)) * 0.6;
	seep = max(max(seep, flood), foot);
	albedo *= mix(1.0, 0.7, seep);
	rough = mix(rough, rough * 0.45, seep);
#endif

	vec3 nts = normalize(vec3(nxy, 1.0));
	vec3 n = normalize(tan_v * nts.x + up_v * nts.y + ng * nts.z);
	NORMAL = n;

	vec3 e = pow(max(lm.rgb, vec3(0.0)), vec3(2.2)) * light_max;
	float bright = tk_brightness(v_world.z);
	vec3 irr = e * (light_scale * bright) * white_balance + ambient_color * ambient_level * lm.a;
	if (debug_view == 1) {
		albedo = vec3(1.0);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.5 * clamp(bright, 0.0, 1.0);
	AO = mix(1.0, orm.r, cavity_strength);
	AO_LIGHT_AFFECT = 0.0;
	IRRADIANCE = vec4(irr, 1.0);
}

// The real lamps add only their highlight (the bake is the diffuse).
void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (ndl > 0.0 && light_specular_scale > 0.0) {
		vec3 h = normalize(VIEW + LIGHT);
		float ndh = max(dot(NORMAL, h), 0.0);
		float ndv = max(dot(NORMAL, VIEW), 0.001);
		float r = max(ROUGHNESS, 0.07);
		float a = r * r;
		float a2 = a * a;
		float dd = ndh * ndh * (a2 - 1.0) + 1.0;
		float d = a2 / (TK_PI * dd * dd);
		float k = a * 0.5;
		float g = (ndl / (ndl * (1.0 - k) + k)) * (ndv / (ndv * (1.0 - k) + k));
		vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
		float vh = max(dot(VIEW, h), 0.0);
		vec3 f = f0 + (vec3(1.0) - f0) * pow(1.0 - vh, 5.0);
		SPECULAR_LIGHT += (d * g / (4.0 * ndv)) * f * LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * light_specular_scale;
	}
}
