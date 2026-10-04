shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

// Clear stylized water: transparent, no specular or sky-radiance reflection, and compatible
// with SubViewports.
// Detail (scripts/world/ocean_detail.gd sets it per quality; the defaults below are the
// plain water of the low tier): a Fresnel reflection of the sky's own gradient (zenith to
// horizon colour, handed over with the sun direction, not the sky radiance), sun glints from
// small analytic ripples, and contact foam where the water meets the piles, the pier box and
// the goal stand. All of it is arithmetic: no texture reads beyond the noise and depth reads below.
uniform vec3 deep_color : source_color = vec3(0.012, 0.18, 0.25);
uniform vec3 mid_color : source_color = vec3(0.02, 0.42, 0.54);
uniform vec3 shallow_color : source_color = vec3(0.12, 0.70, 0.72);
uniform vec3 crest_color : source_color = vec3(0.34, 0.82, 0.80);
uniform float wave_speed : hint_range(0.0, 2.0) = 0.42;
uniform float wave_height : hint_range(0.0, 2.0) = 0.52;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.28;
uniform float roughness_val : hint_range(0.0, 1.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.34;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float depth_absorption : hint_range(0.01, 0.3) = 0.08;
uniform sampler2D noise_tex;
uniform sampler2D noise_tex2;
#ifdef SHAFT_HOLE
// Sudden death shaft (StageEnvironment.set_shaft_hole compiles this variant only while the hole
// is open): (centre x, centre z, radius, active). Water inside the circle is cut away.
uniform vec4 shaft_hole = vec4(0.0);
varying vec2 v_world_xz;
#endif

group_uniforms Reflection;
// Share of the (Schlick, F0 = 0.02) reflection. 0 = no reflection (low). A power above the
// physical 5 keeps the reflection to the shallow views toward the horizon, so the water seen
// from above keeps its deep blue-green.
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.0;
uniform float fresnel_power : hint_range(1.0, 10.0) = 5.0;
// The reflection reaches its full strength only from reflect_far_start to reflect_far_end
// metres away; nearer it keeps reflect_near_share of it. The sea seen between the stands'
// piles (50 to 300 m) stays blue-green; the band toward the horizon takes the sky.
uniform float reflect_near_share : hint_range(0.0, 1.0) = 1.0;
uniform float reflect_far_start = 150.0;
uniform float reflect_far_end = 900.0;
// How much the sun's shadow also hides the sky in the reflection (OceanDetail.set_sun: 1 with
// the sun high, when the shadow on the water means a deck or a stand overhead; 0 low or at night).
uniform float reflect_occlusion : hint_range(0.0, 1.0) = 1.0;
// Linear sky colours (already scaled by the sky's energy): zenith, horizon away from the
// sun and horizon toward the sun. OceanDetail.set_sun() follows the day cycle.
uniform vec3 reflect_zenith = vec3(0.113, 0.354, 0.949);
uniform vec3 reflect_horizon = vec3(0.36, 0.734, 0.98);
uniform vec3 reflect_horizon_sun = vec3(0.36, 0.734, 0.98);
// World-space direction toward the sun (only its azimuth tints the horizon at sunset).
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
group_uniforms Ripples;
// Analytic ripples (0 to 6 directional waves, longest first) that bend the reflection and
// carry the glints. Each fades out once a pixel covers a good part of its wavelength.
uniform int ripple_waves : hint_range(0, 6) = 0;
uniform float ripple_slope : hint_range(0.0, 2.0) = 1.0;
uniform float ripple_speed : hint_range(0.0, 2.0) = 0.65;
// Share of the ripples in the normal the Fresnel term uses (the reflected sky colour always
// follows the full ripples); below 1 keeps the ripple streaks soft at grazing angles.
uniform float ripple_fresnel : hint_range(0.0, 1.0) = 1.0;
group_uniforms Glints;
// Sun glints: every glint_cell metres of water holds one facet that flashes for about
// 1 / glint_rate s when it happens to mirror a directional light (sun or moon) into the
// eye. glint_spread is the facets' slope spread, glint_density how many of them can flash.
// Farther out the cells double in size (two blended levels) so that a cell never drops
// under about glint_cell_pixels pixels; each level dims the flashes by glint_level_fade and
// multiplies a cell's chance to flash by glint_level_gain (a bigger cell holds more facets),
// up to glint_max_chance.
// Lit in light(), so the stands' shadows put them out.
uniform float glint_strength : hint_range(0.0, 8.0) = 0.0;
uniform float glint_density : hint_range(0.0, 1.0) = 0.25;
uniform float glint_spread : hint_range(0.05, 1.0) = 0.4;
uniform float glint_cell = 0.9;
uniform float glint_rate = 1.4;
uniform float glint_cell_pixels = 3.0;
uniform float glint_level_fade : hint_range(0.0, 1.0) = 0.35;
uniform float glint_level_gain : hint_range(1.0, 4.0) = 1.0;
uniform float glint_max_chance : hint_range(0.0, 1.0) = 0.15;
group_uniforms Foam;
// Contact foam: a ring about foam_width metres wide where the water meets anything that
// crosses it (from the scene depth already read above), broken up by arithmetic noise.
uniform float foam_strength : hint_range(0.0, 1.0) = 0.0;
uniform float foam_width = 0.55;
uniform vec3 foam_color : source_color = vec3(0.86, 0.94, 0.95);
uniform int foam_octaves : hint_range(1, 2) = 1;
group_uniforms;

varying float v_crest;
varying float v_flow;
// Glint inputs handed from fragment() to light(): the ripple normal (view space) and, for
// the two cell levels, (x, z) the facet's random roll for this flash and (y, w) the flash's
// shape * life * brightness * level weight.
varying vec3 v_glint_normal;
varying vec4 v_glint;
// The two levels' chance multipliers (glint_level_gain ^ level).
varying vec2 v_glint_gain;
// The sky reflection added to EMISSION; light() takes the part the sun's shadow occludes back out.
varying vec3 v_sky_reflection;

// Directional ripples: (direction x, direction z, wavelength m, slope).
const vec4 RIPPLES[6] = vec4[6](
	vec4(0.966, 0.259, 23.0, 0.06),
	vec4(0.766, -0.643, 14.0, 0.065),
	vec4(0.469, 0.883, 8.6, 0.07),
	vec4(0.985, -0.174, 5.1, 0.07),
	vec4(-0.259, 0.966, 3.0, 0.065),
	vec4(0.819, 0.574, 1.8, 0.06)
);

void vertex() {
	float t = TIME * wave_speed;
	vec2 p = VERTEX.xz;

	float swell_a = sin(p.x * 0.055 + t * 1.25) * cos(p.y * 0.042 - t * 0.82);
	float swell_b = sin((p.x + p.y) * 0.085 - t * 1.08);
	float swell_c = cos(p.x * 0.021 - p.y * 0.032 + t * 0.56);

	vec2 noise_uv_a = p * 0.0045 + vec2(t * 0.025, -t * 0.018);
	vec2 noise_uv_b = p * 0.0080 + vec2(-t * 0.016, t * 0.022);
	float noise_a = texture(noise_tex, noise_uv_a).r - 0.5;
	float noise_b = texture(noise_tex2, noise_uv_b).r - 0.5;

	float displacement = (
		swell_a * 0.46
		+ swell_b * 0.28
		+ swell_c * 0.18
		+ noise_a * 0.42
		+ noise_b * 0.24
	) * wave_height;
	VERTEX.y += displacement;
	v_crest = displacement / max(wave_height, 0.001);
	v_flow = noise_a * 0.65 + noise_b * 0.35;
#ifdef SHAFT_HOLE
	v_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
#endif
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// 0..1
float value_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// One glint cell level: (the facet's roll for the current flash, the flash's weight here).
// `size` is the cell size in metres, `footprint` the metres per pixel.
vec2 glint_level(vec2 world_xz, float size, float footprint, float level) {
	vec2 grid = world_xz / size + vec2(TIME * 0.31, -TIME * 0.23) / size * glint_cell;
	vec2 cell = floor(grid) + vec2(level * 101.0, level * 37.0);
	float cycle = TIME * glint_rate + hash12(cell + 19.19);
	float flash = floor(cycle);
	float roll = hash13(vec3(cell, flash));
	vec2 centre = vec2(hash12(cell + 71.7), hash12(cell + 13.3)) * 0.6 + 0.2;
	float cell_pixels = size / max(footprint, 0.0001);
	// A point a few centimetres wide, never under about a pixel.
	float radius = max(0.05, 1.0 / cell_pixels);
	float shape = 1.0 - smoothstep(0.0, radius, length(fract(grid) - centre));
	float life = sin(fract(cycle) * PI);
	float brightness = 0.35 + 0.65 * hash13(vec3(cell + 5.3, flash));
	return vec2(roll, shape * shape * life * brightness);
}

// Slope (d height / d x, d height / d z) of the swell the vertex shader displaces, at the
// plane-local position p (without its texture-noise part).
vec2 swell_slope(vec2 p, float t) {
	float a_x = p.x * 0.055 + t * 1.25;
	float a_z = p.y * 0.042 - t * 0.82;
	float b = (p.x + p.y) * 0.085 - t * 1.08;
	float c = p.x * 0.021 - p.y * 0.032 + t * 0.56;
	vec2 slope = 0.46 * vec2(0.055 * cos(a_x) * cos(a_z), -0.042 * sin(a_x) * sin(a_z));
	slope += 0.28 * vec2(0.085 * cos(b));
	slope += 0.18 * vec2(-0.021 * sin(c), 0.032 * sin(c));
	return slope * wave_height;
}

void fragment() {
#ifdef SHAFT_HOLE
	if (shaft_hole.w > 0.5) {
		vec2 hole_offset = v_world_xz - shaft_hole.xy;
		if (dot(hole_offset, hole_offset) < shaft_hole.z * shaft_hole.z) {
			discard;
		}
	}
#endif
	float t = TIME * wave_speed;
	vec2 flow_uv_a = UV * 7.0 + vec2(t * 0.038, -t * 0.026);
	vec2 flow_uv_b = UV * 11.0 + vec2(-t * 0.031, t * 0.043);

	float a = texture(noise_tex, flow_uv_a).r;
	float b = texture(noise_tex2, flow_uv_b).r;
	float ax = texture(noise_tex, flow_uv_a + vec2(0.012, 0.0)).r - a;
	float az = texture(noise_tex2, flow_uv_b + vec2(0.0, 0.012)).r - b;
	vec3 detail_normal = normalize(vec3(ax * detail_strength * 5.0, az * detail_strength * 5.0, 1.0));
	NORMAL_MAP = detail_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.75;

	float flow = clamp(a * 0.58 + b * 0.42 + v_flow * 0.20, 0.0, 1.0);
	float crest = smoothstep(0.58, 0.92, v_crest + flow * 0.30);

	vec3 water_color = mix(deep_color, mid_color, 0.42 + flow * 0.38);
	water_color = mix(water_color, shallow_color, 0.26);
	water_color = mix(water_color, crest_color, crest * 0.16);
	// Keep surface swimmers readable while deep foundations disappear into water.
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	// At MSAA silhouettes the resolved depth can also be BETWEEN the above-
	// water object and the background. A center-only foreground test misses
	// those samples and leaves bright dots on near-vertical edges. Recover
	// background depth only where the 3x3 footprint touches foreground;
	// wholly submerged surfaces retain their original center depth.
	vec2 depth_texel = 1.0 / vec2(textureSize(depth_texture, 0));
	float nearest_depth = scene_depth;
	float farthest_depth = scene_depth;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			if (x == 0 && y == 0) {
				continue;
			}
			float neighbor_depth = textureLod(
				depth_texture, SCREEN_UV + vec2(float(x), float(y)) * depth_texel, 0.0
			).r;
			// Godot's reverse-Z depth is larger closer to the camera.
			nearest_depth = max(nearest_depth, neighbor_depth);
			farthest_depth = min(farthest_depth, neighbor_depth);
		}
	}
	if (nearest_depth > FRAGCOORD.z) {
		scene_depth = farthest_depth;
	}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, scene_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
#endif
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene_view.xyz /= max(scene_view.w, 0.000001);
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view.xyz, 1.0)).xyz;
	vec3 surface_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float water_depth = max(surface_world.y - scene_world.y, 0.0);
	float deep_amount = 1.0 - exp(-max(water_depth - 4.0, 0.0) * depth_absorption);
	// MSAA resolves one depth for a pixel whose color can contain both the
	// foreground silhouette and water. That foreground is not a submerged
	// surface: using its height makes the uncovered water samples transparent
	// and leaks the bright background along moving floor/wall/stand edges.
	// Keep those samples deep-water colored; retain absorption for geometry
	// actually behind the water so surface swimmers remain visible.
	bool foreground = scene_view.z >= VERTEX.z;
	if (foreground) {
		deep_amount = 1.0;
	}
	water_color = mix(water_color, deep_color, deep_amount * 0.65);
	float alpha = mix(clamp(opacity + crest * 0.02, 0.0, 0.38), 0.995, deep_amount);
	vec3 emission = water_color * 0.02;

	// ---- Detail (all zero on the low tier) ----
	vec2 world_xz = surface_world.xz;
	vec3 to_camera = CAMERA_POSITION_WORLD - surface_world;
	vec3 view_world = normalize(to_camera);
	// Metres of water per pixel along the coarser screen axis (filters ripples and glints).
	float footprint = max(length(dFdx(world_xz)), length(dFdy(world_xz)));

	// Contact foam: a ring of about foam_width m around whatever crosses the surface. The
	// water depth to the object behind grows with the distance from it times the view slope.
	float foam = 0.0;
	if (foam_strength > 0.0 && !foreground) {
		float view_slope = to_camera.y / max(length(to_camera.xz), 0.001);
		float ring = foam_width * clamp(view_slope, 0.08, 1.5);
		float edge = 1.0 - smoothstep(0.0, ring, water_depth);
		if (edge > 0.0) {
			float n = value_noise2(world_xz * 1.7 + vec2(TIME * 0.21, -TIME * 0.17));
			if (foam_octaves > 1) {
				n = n * 0.62 + value_noise2(world_xz * 4.3 - vec2(TIME * 0.33, TIME * 0.12)) * 0.38;
			}
			// Solid only right at the contact line, lace-like further out.
			foam = clamp(edge * 1.25 - (1.0 - n * n) * 1.05, 0.0, 1.0) * foam_strength;
		}
	}
	water_color = mix(water_color, foam_color, foam);
	emission *= 1.0 - foam;
	alpha = max(alpha, foam * 0.9);

	// Surface normal for the reflection and the glints: the swell the vertices follow, the
	// noise detail of NORMAL_MAP and the ripples, each kept only while a pixel resolves it.
	float fresnel = 0.0;
	vec3 sky = vec3(0.0);
	v_glint_normal = NORMAL;
	v_glint = vec4(1.0, 0.0, 1.0, 0.0);
	v_glint_gain = vec2(1.0);
	if (fresnel_strength > 0.0 || glint_strength > 0.0) {
		vec2 broad_slope = swell_slope(world_xz - NODE_POSITION_WORLD.xz, t);
		broad_slope -= vec2(ax, az) * (detail_strength * 5.0 * 0.75);
		vec2 ripple = vec2(0.0);
		for (int i = 0; i < ripple_waves; i++) {
			vec4 wave = RIPPLES[i];
			float k = TAU / wave.z;
			float phase = k * dot(wave.xy, world_xz) - sqrt(9.81 * k) * ripple_speed * TIME + float(i) * 1.7;
			float resolved = 1.0 - smoothstep(0.2 * wave.z, 0.5 * wave.z, footprint);
			ripple += wave.xy * (wave.w * ripple_slope * resolved * cos(phase));
		}
		vec2 slope = broad_slope + ripple;
		vec3 normal_world = normalize(vec3(-slope.x, 1.0, -slope.y));
		vec2 fresnel_slope = broad_slope + ripple * ripple_fresnel;
		vec3 fresnel_normal = normalize(vec3(-fresnel_slope.x, 1.0, -fresnel_slope.y));

		// Fresnel reflection of the sky's gradient (pale toward the horizon, deep blue overhead).
		float cos_view = clamp(dot(fresnel_normal, view_world), 0.0, 1.0);
		fresnel = (0.02 + 0.98 * pow(1.0 - cos_view, fresnel_power)) * fresnel_strength * (1.0 - foam);
		fresnel *= mix(reflect_near_share, 1.0, smoothstep(reflect_far_start, reflect_far_end, length(to_camera)));
		vec3 reflected = reflect(-view_world, normal_world);
		float horizon_mask = pow(1.0 - clamp(reflected.y, 0.0, 1.0), 4.2);
		vec3 sun_flat = vec3(sun_direction.x, 0.0, sun_direction.z);
		sun_flat /= max(length(sun_flat), 0.001);
		vec3 reflected_flat = vec3(reflected.x, 0.0, reflected.z);
		reflected_flat /= max(length(reflected_flat), 0.001);
		float facing = pow(max(dot(reflected_flat, sun_flat), 0.0), 1.6);
		sky = mix(reflect_zenith, mix(reflect_horizon, reflect_horizon_sun, facing), horizon_mask);

		v_glint_normal = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
		if (glint_strength > 0.0) {
			// One facet per cell, drifting with the water; each flash re-rolls the facet. Two
			// cell levels, blended, keep the cells about glint_cell_pixels wide on screen.
			float level = log2(max(footprint * glint_cell_pixels / glint_cell, 1.0));
			float level_0 = floor(level);
			float blend = level - level_0;
			float size_0 = glint_cell * exp2(level_0);
			vec2 near_cell = glint_level(world_xz, size_0, footprint, level_0);
			vec2 far_cell = glint_level(world_xz, size_0 * 2.0, footprint, level_0 + 1.0);
			float keep = (1.0 - foam) / (1.0 + glint_level_fade * level);
			v_glint = vec4(near_cell.x, near_cell.y * (1.0 - blend) * keep, far_cell.x, far_cell.y * blend * keep);
			float gain = pow(glint_level_gain, level_0);
			v_glint_gain = vec2(gain, gain * glint_level_gain);
		}
	}

	// Reflection over the water: the surface hides what is under it in proportion to the
	// reflection (exact for blend_mix), so shallow water near the piles keeps its look when
	// the reflection is weak and the far sea reads as mirror-like.
	float alpha_out = alpha + fresnel * (1.0 - alpha);
	float inverse_alpha = 1.0 / max(alpha_out, 0.001);
	v_sky_reflection = sky * (fresnel * inverse_alpha);
	ALBEDO = water_color * ((1.0 - fresnel) * alpha * inverse_alpha);
	EMISSION = emission * ((1.0 - fresnel) * alpha * inverse_alpha) + v_sky_reflection;
	METALLIC = 0.0;
	ROUGHNESS = roughness_val;
	SPECULAR = 0.0;
	ALPHA = alpha_out;
}

float schlick_weight(float u) {
	float m = clamp(1.0 - u, 0.0, 1.0);
	float m2 = m * m;
	return m2 * m2 * m;
}

void light() {
	// Godot's own diffuse_burley term, unchanged (a light() replaces the built-in lighting).
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float n_dot_v = max(dot(NORMAL, VIEW), 0.0001);
	// normalize() without the NaN when the view is exactly opposite the light (an overhead
	// camera and a light shining straight up, like the stage's ground bounce).
	vec3 half_vector = VIEW + LIGHT;
	half_vector *= inversesqrt(max(dot(half_vector, half_vector), 1e-8));
	float l_dot_h = clamp(dot(LIGHT, half_vector), 0.0, 1.0);
	float fd90_minus_1 = 2.0 * l_dot_h * l_dot_h * ROUGHNESS - 0.5;
	float fd_view = 1.0 + fd90_minus_1 * schlick_weight(n_dot_v);
	float fd_light = 1.0 + fd90_minus_1 * schlick_weight(n_dot_l);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (fd_view * fd_light * n_dot_l / PI);

	// Water in the shadow of a deck or a stand under a high sun sees that deck, not the sky:
	// take the shadowed share of the sky reflection back out (never below zero, as EMISSION
	// holds all of it). Only the sun casts shadows (the moon's ATTENUATION is 1).
	if (LIGHT_IS_DIRECTIONAL && reflect_occlusion > 0.0) {
		SPECULAR_LIGHT -= v_sky_reflection * (reflect_occlusion * (1.0 - clamp(ATTENUATION, 0.0, 1.0)));
	}

	// Sun (and moon) glints: the facet flashes when its slope, drawn from a spread around the
	// ripple normal, mirrors this light into the eye. ATTENUATION carries the shadows.
	if (glint_strength > 0.0 && LIGHT_IS_DIRECTIONAL && v_glint.y + v_glint.w > 0.0) {
		float c = clamp(dot(half_vector, v_glint_normal), 0.001, 1.0);
		float c2 = c * c;
		float facets = glint_density * exp(-(1.0 - c2) / (c2 * glint_spread * glint_spread));
		vec2 chance = min(facets * v_glint_gain, vec2(glint_max_chance));
		float flash = step(v_glint.x, chance.x) * v_glint.y + step(v_glint.z, chance.y) * v_glint.w;
		// ALPHA scales the whole colour in the blend; undo it so a glint is as bright over shallow water.
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (flash * glint_strength / max(ALPHA, 0.3));
	}
}
