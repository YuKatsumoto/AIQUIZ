// Body of the cistern hall material (cistern_surface.gdshader; cistern_floor.gdshader defines CISTERN_FLOOR and
// cistern_grate.gdshader CISTERN_CUTOUT first).
// Tiling PBR set on UV0 (assets/environment/underground_temple/textures, 3.75 m per UV on concrete and floor) with a
// 1 m detail normal, the module light map on UV2, world-space breakup of the repeat, row brightness and the shaft
// light from cistern_common. See cistern_common.gdshaderinc for the lighting model.
// Vertex colour (cistern_layout.json "vertex_color"): floor R = puddle potential, G = damp, B = silt; painted steel
// = paint tint where the albedo alpha is 1; everything else white.

#ifdef CISTERN_CUTOUT
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx, specular_occlusion_disabled;
#else
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx, specular_occlusion_disabled;
#endif

#include "res://shaders/sudden_death/cistern_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// R = AO, G = roughness, B = metallic (glTF order).
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// 1 m detail relief, sampled at UV0 * detail_scale (detail_scale = metres per UV0 unit).
uniform sampler2D detail_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Module light map (UV2): RGB = (E / light_max)^(1/2.2), A = baked AO.
uniform sampler2D light_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float uv_scale = 1.0;
uniform float detail_scale = 3.75;
uniform float detail_strength = 0.5;
uniform float roughness_scale = 1.0;
uniform float metallic_value = 0.0;
uniform float normal_strength = 1.0;
uniform float light_max = 1.0;
// Baked E (Blender units: outgoing radiance of a white Lambertian surface) to Godot's ambient * albedo.
uniform float light_scale = 1.0;
// > 1 deepens the dark between lamp rows (the bake has the soft bounce in it).
uniform float light_gamma = 1.0;
// The bake already holds its occlusion: AO only darkens the faint ambient and the texture cavities.
uniform float cavity_strength = 0.35;
uniform float macro_strength = 0.12;
uniform float relight = 0.9;
// Seepage on walls and pillars: darker, glossier patches from the world noise.
uniform float seepage = 0.3;
uniform float glint_strength = 0.0;
// Look-dev: 1 = baked light on white Lambert (like the Blender light map checks), 0 = normal.
uniform int debug_view = 0;
uniform vec3 glint_color : source_color = vec3(1.0, 0.85, 0.72);
#ifdef CISTERN_FLOOR
// floor_wet.png on UV0: R = puddle threshold, G = damp, B = silt (README recipe).
uniform sampler2D wet_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
// Added to the vertex puddle potential: > 0 floods more of the floor, < 0 dries it.
uniform float puddle_bias = 0.0;
// World-noise wobble of the water line (0 = exactly as authored).
uniform float puddle_variation = 0.06;
uniform float puddle_roughness = 0.04;
uniform float damp_roughness = 0.28;
// Least dampness anywhere on the slab, and how much darker damp concrete gets (README recipe: 0.45).
uniform float damp_darkening = 0.3;
uniform float floor_dampness = 0.0;
#endif

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec4 albedo_sample = texture(albedo_tex, uv);
	vec3 albedo = albedo_sample.rgb * albedo_color.rgb;
#ifndef CISTERN_FLOOR
	albedo *= mix(vec3(1.0), COLOR.rgb, albedo_sample.a);
#endif
#ifdef CISTERN_CUTOUT
	ALPHA = albedo_sample.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	vec3 orm = texture(orm_tex, uv).rgb;
	vec2 nxy = (texture(normal_tex, uv).xy * 2.0 - 1.0) * normal_strength;
	nxy += (texture(detail_normal_tex, uv * detail_scale).xy * 2.0 - 1.0) * detail_strength;
	vec4 lm = texture(light_tex, UV2);
	vec3 wn = normalize(v_world_normal);
	vec2 plane = cis_world_plane(v_world, wn);
	float macro = cis_macro(macro_noise, plane);
	float fine = texture(macro_noise, plane * 0.61 + vec2(0.5, 0.2)).r;

	// Break the repeat up: tone and roughness drift across metres.
	albedo *= 1.0 + macro_strength * (macro * 2.0 - 1.0) + 0.06 * (fine - 0.5);
	float rough = clamp(orm.g * roughness_scale * (0.92 + 0.16 * fine), 0.02, 1.0);
	float metal = orm.b * metallic_value;
	float wet = 0.0;

#ifdef CISTERN_FLOOR
	// The module's own recipe (assets/environment/underground_temple/README.md): standing water where the vertex
	// puddle potential beats the texture threshold, damp and silt from vertex colour x texture. puddle_bias moves
	// the water line for the whole hall; the world noise only nudges it so repeats of a bay variant differ.
	vec3 w = texture(wet_tex, uv).rgb;
	float nudge = (texture(macro_noise, v_world.xz * 0.019 + vec2(0.31, 0.62)).r - 0.5) * puddle_variation;
	float puddle = smoothstep(-0.035, 0.035, COLOR.r - w.r + puddle_bias + nudge);
	// Behind the flood the whole slab is soaked and the low spots hold water.
	float flood = cis_flooded(v_world, macro);
	puddle = max(puddle, flood * smoothstep(0.4, 0.62, fine * 0.7 + macro * 0.5));
	float damp = clamp(max(max(COLOR.g * (0.55 + 0.6 * w.g), floor_dampness), flood), 0.0, 1.0);
	float silt = clamp(COLOR.b * (0.3 + 0.9 * w.b), 0.0, 1.0);
	albedo *= (1.0 - damp_darkening * damp) * (1.0 - 0.25 * puddle);
	albedo = mix(albedo, albedo * vec3(0.62, 0.55, 0.44), silt);
	rough = mix(mix(rough, damp_roughness, damp), 0.6, 0.5 * silt);
	rough = mix(rough, puddle_roughness, puddle);
	nxy *= 1.0 - puddle;
	wet = max(damp * 0.6, puddle);
#else
	// Damp streaks running down walls and pillars.
	float streak = texture(macro_noise, vec2(plane.x * 0.21, plane.y * 0.035) + vec2(0.31, 0.77)).r;
	float seep = seepage * smoothstep(0.55, 0.8, streak * 0.7 + macro * 0.5) * (1.0 - abs(wn.y));
	// Where the flood has passed, walls and pillars are soaked up to the height it reached (ragged line).
	float flood_line = CIS_FLOOR_Y + 3.0 + (fine - 0.5) * 1.3 + (macro - 0.5) * 0.8;
	float flood = cis_flooded(v_world, macro) * (1.0 - smoothstep(flood_line - 0.6, flood_line, v_world.y));
	seep = max(seep, flood);
	wet = seep;
	albedo *= mix(1.0, 0.66, seep);
	rough = mix(rough, rough * 0.35, seep);
#endif

	vec3 ng = NORMAL;
	vec3 nts = normalize(vec3(nxy, 1.0));
	vec3 n = normalize(TANGENT * nts.x + BINORMAL * nts.y + ng * nts.z);
	NORMAL = n;

	// Baked light, re-lit by the normal map toward the nearest floodlight.
	vec3 e = pow(max(lm.rgb, vec3(0.0)), vec3(2.2 * light_gamma)) * light_max;
	vec3 l0 = (VIEW_MATRIX * vec4(cis_nearest_lamp_dir(v_world), 0.0)).xyz;
	float relit = clamp(1.0 + relight * (dot(n, l0) - dot(ng, l0)), 0.35, 1.9);
	float bright = cis_brightness(v_world.z);
	vec3 nw = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
	vec3 irr = e * (light_scale * bright * relit) * white_balance;
	irr += cis_opening_light(v_world, nw);
	irr += ambient_color * ambient_level * lm.a;

	// Reflections (probes, SSR) follow the rows too: a dark bay reflects nothing but the shaft light.
	float near_opening = smoothstep(26.0, 9.0, length(v_world.xz));
	float reflect_scale = max(bright, cis_opening_amount() * near_opening);

	if (debug_view == 1) {
		albedo = vec3(1.0);
		reflect_scale = 0.0;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal * reflect_scale;
	SPECULAR = 0.5 * reflect_scale;
	AO = mix(1.0, orm.r, cavity_strength);
	AO_LIGHT_AFFECT = 0.0;
	IRRADIANCE = vec4(irr, 1.0);

	if (glint_strength > 0.0 && wet > 0.02) {
		vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
		float f0 = 0.02 + 0.02 * (1.0 - wet);
		EMISSION = cis_lamp_glints(v_world, nw, v, max(rough, 0.06), f0, glint_color * white_balance) * (glint_strength * wet);
	}
}
