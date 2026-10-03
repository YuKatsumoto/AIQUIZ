shader_type spatial;
// Flash-flood front (docs/sudden_death_underground.md 6.6): the turbulent bore baked in Blender to a vertex
// animation texture (assets/hazards/flood_wave, see flood_wave_layout.json). Every vertex reads its position
// (+ foam) and normal for the current frame from the VAT through its UV2 address and blends to the next frame.
// Murky water with whitewater where the VAT foam and the scrolling foam lace agree; lit by the real lights of
// the hall (rows, current-row key) like the runners. Opaque so SSR (high quality and up) reflects in it.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D vat_pos : filter_nearest, repeat_disable;
uniform sampler2D vat_nrm : filter_nearest, repeat_disable;
uniform sampler2D foam_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D water_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float vat_frames = 48.0;
uniform float vat_rows_per_frame = 5.0;
uniform float vat_width = 4096.0;
uniform float loop_seconds = 2.0;
// Seconds of the loop, advanced by FloodWave (game clock, so slow motion slows the water too).
uniform float clock = 0.0;
// 0..1: how tall the front stands (the both-wrong recede flattens it toward the water line).
uniform float height_scale = 1.0;
// The flood leaves the 10 m tunnel mouth and fans out over the hall (cistern_flood_fan in the water
// shader too): beyond the fan the front is cut away, toward its edge it slumps into a thin sheet.
uniform float tunnel_z = -30.0;
uniform float travelled = 100.0;
uniform vec3 water_color : source_color = vec3(0.095, 0.085, 0.064);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.145, 0.105);
uniform vec3 foam_color : source_color = vec3(0.80, 0.83, 0.82);
uniform vec3 backlight_color : source_color = vec3(0.22, 0.27, 0.18);
// Scattering in the turbid water (emission, scaled by how lit the hall is around the front, 0..1).
uniform vec3 rim_color : source_color = vec3(0.12, 0.105, 0.08);
uniform float hall_light = 1.0;
uniform float foam_gain = 1.0;
// Extra whitewater (0..1) right after the flood bursts out of the tunnel.
uniform float foam_boost = 0.0;
uniform float normal_strength = 1.0;
uniform float water_roughness = 0.12;
uniform float foam_roughness = 0.55;
// Look-dev: 1 = foam mask, 2 = normal, 3 = VAT foam (all unshaded).
uniform int debug_view = 0;

varying float v_foam;
varying float v_height;
varying vec3 v_world;
varying float v_fan;

// Half width (m) the flood covers at world z: 5 m out of the tunnel, the whole hall (45 m) further on
// and, as it keeps coming, back toward the tunnel too.
float fan_half(float z) {
	return 5.0 + 40.0 * smoothstep(0.0, 22.0, (z - tunnel_z) + 0.8 * travelled);
}

vec4 vat_sample(sampler2D tex, int px, int row, float frame) {
	int f = int(mod(frame, vat_frames));
	return texelFetch(tex, ivec2(px, f * int(vat_rows_per_frame) + row), 0);
}

void vertex() {
	float f = fract(clock / loop_seconds) * vat_frames;
	float f0 = floor(f);
	float t = f - f0;
	int px = int(UV2.x * vat_width);
	int row = int((1.0 - UV2.y) * 8.0);
	vec4 a = vat_sample(vat_pos, px, row, f0);
	vec4 b = vat_sample(vat_pos, px, row, f0 + 1.0);
	vec4 p = mix(a, b, t);
	vec3 na = vat_sample(vat_nrm, px, row, f0).xyz * 2.0 - 1.0;
	vec3 nb = vat_sample(vat_nrm, px, row, f0 + 1.0).xyz * 2.0 - 1.0;
	vec3 n = normalize(mix(na, nb, t));
	vec3 pos = p.xyz;
	vec3 world = (MODEL_MATRIX * vec4(pos, 1.0)).xyz;
	float half_width = fan_half(world.z);
	// Toward the edge of the fan the bore slumps into a thin sheet.
	float edge = smoothstep(half_width + 0.5, half_width - 5.0, abs(world.x));
	pos.y *= height_scale * mix(0.12, 1.0, edge);
	n = normalize(vec3(n.x, n.y / max(height_scale, 0.05), n.z));
	v_fan = abs(world.x) - half_width;
	VERTEX = pos;
	NORMAL = n;
	vec3 tangent = normalize(vec3(1.0, 0.0, 0.0) - n * n.x);
	TANGENT = tangent;
	BINORMAL = normalize(cross(n, tangent));
	v_foam = p.w;
	v_height = pos.y;
	v_world = (MODEL_MATRIX * vec4(pos, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float edge_noise = texture(foam_tex, uv * 0.5 + vec2(0.0, clock * 0.3)).g;
	// Ragged edge of the fan.
	if (v_fan > (edge_noise - 0.5) * 3.0) {
		discard;
	}
	// Whitewater where the bore breaks (VAT foam), broken into clumps and streaks that run down the face
	// (UV0 is 4 m per unit; v runs back -> over the crest -> down the face). Coarse scales: at play distance
	// the foam reads as patches, not speckle.
	float clumps = texture(foam_tex, uv * 0.55 + vec2(0.0, clock * 0.32)).r;
	float clumps2 = texture(foam_tex, uv * 1.15 + vec2(0.37, clock * 0.55)).r;
	float patches = texture(foam_tex, uv * 0.3 + vec2(0.11, clock * 0.14)).g;
	float streaks = texture(foam_tex, uv * vec2(1.4, 0.22) + vec2(0.0, clock * 0.45)).b;
	float pattern = clumps * 0.15 + clumps2 * 0.1 + patches * 0.45 + streaks * 0.4;
	float density = clamp(v_foam * foam_gain + foam_boost * 0.55 + (pattern - 0.6) * 0.9, 0.0, 1.0);
	float foam = smoothstep(0.45, 0.8, density);
	vec2 n1 = texture(water_normal, uv * 1.1 + vec2(0.0, clock * 0.5)).xy * 2.0 - 1.0;
	vec2 n2 = texture(water_normal, uv * 2.6 + vec2(0.5, clock * 0.9)).xy * 2.0 - 1.0;
	vec2 nxy = (n1 * 0.65 + n2 * 0.35) * normal_strength * (1.0 - 0.7 * foam);
	NORMAL_MAP = normalize(vec3(nxy, 1.0)) * 0.5 + 0.5;
	// Thin water near the floor and the toe is lighter (silt); the body is dark and murky. Thin foam
	// over water is grey, thick foam white.
	vec3 water = mix(shallow_color, water_color, smoothstep(0.2, 1.4, v_height));
	vec3 foam_tint = foam_color * mix(0.55, 1.0, smoothstep(0.6, 1.0, density));
	ALBEDO = mix(water, foam_tint, foam);
	ROUGHNESS = mix(water_roughness, foam_roughness, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
	// Light through the thin lip and the spray-laden crest, and the turbid water's own glow where the
	// view grazes it (what the hall's light does inside the silt): the shape reads in a dark hall.
	BACKLIGHT = backlight_color * (1.0 - foam) * smoothstep(1.2, 3.0, v_height);
	float grazing = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color * hall_light * (grazing * 0.8 + 0.2) * (1.0 - foam);
	if (debug_view > 0) {
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		BACKLIGHT = vec3(0.0);
		EMISSION = debug_view == 1 ? vec3(foam) : (debug_view == 2 ? NORMAL * 0.5 + 0.5 : vec3(v_foam));
	}
}
