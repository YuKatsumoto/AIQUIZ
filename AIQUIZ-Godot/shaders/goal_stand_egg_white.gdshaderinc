// Raw egg white on GSE_White (goal_stand_egg_contents.glb): a unit radial disc
// whose spokes the vertex stage stretches to the rim GoalStandEggSplat simulates per
// angle, then wraps over the surface it landed on (box edges, a capsule). Like a
// real raw egg it has two layers: a thin, water-clear film (thin albumen) out to the
// rim, with a surface-tension bead at its edge, and a faintly milky, slightly
// turbid dome of thick albumen round the yolk. With EGG_REFRACT the background is
// refracted through it (screen texture); without (LOW, mobile) it is a glossy,
// lightly milky transparent layer. kind 2 is a pool of spilt yolk instead.
//
// The mesh is fine but the outline, the heights' normals and the dome are all
// evaluated per pixel from the splat-plane position; the outer ring is pushed a
// little past the rim so the per-pixel outline is never clipped by a chord.

#include "res://shaders/goal_stand_egg_common.gdshaderinc"

instance uniform int row = 0;
uniform vec4 tint : source_color = vec4(0.97, 0.96, 0.87, 1.0);
uniform vec4 yolk_color : source_color = vec4(1.0, 0.62, 0.07, 1.0);
uniform float refraction = 0.05;
#ifdef EGG_REFRACT
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
#endif

const float RIM_MARGIN = 1.08;
// Keeps the film just off the surface it lies on (no z-fighting, no poking through
// at the folds).
const float LIFT = 0.0018;

varying vec2 v_q;

float fraction_at(vec2 q) {
	return length(q) / max(egg_rim_at(row, atan(q.y, q.x)), 0.001);
}

// Thick albumen coverage at q (1 inside the dome, 0 outside), kept off the rim.
float dome(EggSplat s, vec2 q, float fraction) {
	if (s.thick <= 0.0) {
		return 0.0;
	}
	vec2 d = q - s.thick_center;
	float a = atan(d.y, d.x);
	float radius = s.thick_radius * (1.0 + s.thick_shape.z * sin(3.0 * a + s.thick_shape.x) + s.thick_shape.w * sin(5.0 * a + s.thick_shape.y));
	float x = length(d) / max(radius, 0.001);
	float h = 1.0 - smoothstep(0.25, 1.0, x);
	return h * h * (3.0 - 2.0 * h) * (1.0 - smoothstep(0.75, 0.97, fraction));
}

// Film profile: flat, a surface-tension bead just inside the rim, zero at the rim.
float bead(float fraction) {
	return mix(1.0, 1.45, smoothstep(0.8, 0.94, fraction)) * (1.0 - smoothstep(0.94, 1.0, fraction));
}

float height_at(EggSplat s, vec2 q) {
	float fraction = fraction_at(q);
	return s.film * bead(fraction) + s.thick * dome(s, q, fraction);
}

void vertex() {
	EggSplat s = egg_load(row);
	vec2 p = VERTEX.xz;
	float r = egg_rim_at(row, atan(p.y, p.x));
	vec2 q = p * r * (length(p) > 0.99 ? RIM_MARGIN : 1.0);
	v_q = q;
	if (s.alpha <= 0.0 || r <= 0.0) {
		VERTEX = vec3(0.0);
	} else {
		vec3 pos;
		vec3 n;
		egg_wrap(s, q, height_at(s, q) + LIFT, pos, n);
		VERTEX = pos;
		NORMAL = n;
	}
}

void fragment() {
	EggSplat s = egg_load(row);
	vec2 q = v_q;
	float fraction = fraction_at(q);
	float thick_part = dome(s, q, fraction);
	// Per-pixel normal of the height field, turned onto the fold, in view space.
	float e = 0.003;
	float dx = (height_at(s, q + vec2(e, 0.0)) - height_at(s, q - vec2(e, 0.0))) / (2.0 * e);
	float dz = (height_at(s, q + vec2(0.0, e)) - height_at(s, q - vec2(0.0, e))) / (2.0 * e);
	vec3 surface;
	vec3 fold;
	egg_wrap(s, q, 0.0, surface, fold);
	vec3 n = egg_tilt(normalize(vec3(-dx, 1.0, -dz)), fold);
	n = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);
	// The far side of the rim bead would face away and mirror the ground below the
	// horizon as a dark seam; keep it just facing the viewer.
	NORMAL = normalize(n + VIEW * max(0.0, 0.3 - dot(n, VIEW)));
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = egg_fresnel(facing);
	// The edge melts into the surface instead of ending in a hard line.
	float edge = 1.0 - smoothstep(0.975, 1.0, fraction);
	// The bead catches a thin bright line along the rim.
	float bead_line = smoothstep(0.86, 0.93, fraction) * (1.0 - smoothstep(0.95, 0.99, fraction));
	if (s.kind > 1.5) {
		// Spilt yolk: an opaque, glossy orange pool.
		ALBEDO = mix(yolk_color.rgb, yolk_color.rgb * vec3(0.92, 0.75, 0.6), smoothstep(0.6, 1.0, fraction));
		ROUGHNESS = 0.22;
		SPECULAR = 0.5;
		CLEARCOAT = 0.8;
		CLEARCOAT_ROUGHNESS = 0.05;
		ALPHA = edge * s.alpha;
	} else {
		// Thick albumen is faintly milky, yellow-green and a little turbid; the film is clear.
		float turbid = egg_noise(q * 22.0 + s.seed * 37.0) * 0.6 + egg_noise(q * 61.0 - s.seed * 19.0) * 0.4;
		float cloud = mix(0.03, 0.08 + 0.07 * turbid, thick_part);
#ifdef EGG_REFRACT
		// Bent by the layer's own thickness (the gel dome bends it more than the film).
		float layer = s.film * bead(fraction) + s.thick * thick_part;
		vec2 offset = egg_refraction(NORMAL, layer, -VERTEX.z, PROJECTION_MATRIX[1][1]) * refraction / 0.05;
		vec3 behind = textureLod(screen_tex, SCREEN_UV - offset, 0.0).rgb;
		// Wetting darkens what is underneath a little; the gel tints it yellow-green.
		vec3 through = behind * mix(vec3(0.86), vec3(0.9, 0.93, 0.8), thick_part);
		ALBEDO = tint.rgb * cloud;
		EMISSION = through * (1.0 - cloud) * (1.0 - fresnel) + vec3(bead_line * 0.05);
		ALPHA = edge * s.alpha;
#else
		ALBEDO = tint.rgb * mix(0.6, 0.85, thick_part);
		ALPHA = clamp(mix(0.28, 0.55, thick_part) + fresnel * 0.5 + bead_line * 0.25, 0.0, 1.0) * edge * s.alpha;
#endif
		ROUGHNESS = 0.05;
		SPECULAR = 0.6;
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.0;
		RIM = 0.25;
		RIM_TINT = 0.85;
	}
}
