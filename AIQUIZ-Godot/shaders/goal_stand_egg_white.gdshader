shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Raw egg white on GSE_White (goal_stand_egg_contents.glb): a unit radial disc
// whose rings the vertex stage stretches to the rim GoalStandEggs simulates per
// angle. The surface is two layers like a real raw egg: a thin, water-clear film
// (thin albumen) out to the rim with a surface-tension bead at its edge, and a
// round, faintly milky dome of thick albumen hugging the yolk. Both are bent
// around the body the splat landed on. The film is see-through: the background
// is refracted through it.
//
// The mesh is coarse, so the outline, the heights' normals and the dome are all
// evaluated per pixel from the splat-plane position; the outer ring is pushed a
// little past the rim so the per-pixel outline is never clipped by a chord.

const int RIM_COUNT = 48;
const float RIM_MARGIN = 1.1;

uniform float rim[48];
// Thin albumen film thickness (m); thins as the sheet spreads.
uniform float film = 0.006;
// Thick albumen dome height above the film (m); slumps over time.
uniform float thick = 0.03;
// Thick albumen: centre in the splat plane (x, z), radius, and an irregular outline
// (phase 1, phase 2, amplitude 1, amplitude 2 for 3 and 5 lobes).
uniform vec2 thick_center = vec2(0.0);
uniform float thick_radius = 0.16;
uniform vec4 thick_shape = vec4(0.0, 0.0, 0.08, 0.05);
// 1 / radius of the surface underneath (0 on the conveyor).
uniform float bend = 0.0;
uniform vec4 tint : source_color = vec4(0.96, 0.95, 0.86, 1.0);
uniform float refraction = 0.05;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

varying vec2 v_q;

// Catmull-Rom through the rim samples: a smooth outline with no flat steps.
float rim_at(float angle) {
	float a = angle / TAU;
	a -= floor(a);
	float x = a * float(RIM_COUNT);
	int i1 = int(floor(x)) % RIM_COUNT;
	float p0 = rim[(i1 + RIM_COUNT - 1) % RIM_COUNT];
	float p1 = rim[i1];
	float p2 = rim[(i1 + 1) % RIM_COUNT];
	float p3 = rim[(i1 + 2) % RIM_COUNT];
	float t = fract(x);
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)));
}

float fraction_at(vec2 q) {
	return length(q) / max(rim_at(atan(q.y, q.x)), 0.001);
}

// Thick albumen coverage at q (1 inside the dome, 0 outside), kept off the rim.
float dome(vec2 q, float fraction) {
	vec2 d = q - thick_center;
	float a = atan(d.y, d.x);
	float radius = thick_radius * (1.0 + thick_shape.z * sin(3.0 * a + thick_shape.x) + thick_shape.w * sin(5.0 * a + thick_shape.y));
	float x = length(d) / max(radius, 0.001);
	float h = 1.0 - smoothstep(0.3, 1.0, x);
	return h * h * (3.0 - 2.0 * h) * (1.0 - smoothstep(0.7, 0.95, fraction));
}

// Film profile: flat, a surface-tension bead just inside the rim, zero at the rim.
float bead(float fraction) {
	return mix(1.0, 1.4, smoothstep(0.78, 0.93, fraction)) * (1.0 - smoothstep(0.93, 1.0, fraction));
}

float height_at(vec2 q) {
	float fraction = fraction_at(q);
	return film * bead(fraction) + thick * dome(q, fraction);
}

void vertex() {
	vec2 p = VERTEX.xz;
	float r = rim_at(atan(p.y, p.x));
	vec2 q = p * r * (length(p) > 0.99 ? RIM_MARGIN : 1.0);
	v_q = q;
	float sag = -0.5 * bend * dot(q, q);
	float h = VERTEX.y > 0.001 ? height_at(q) : 0.0;
	VERTEX = vec3(q.x, h + sag, q.y);
}

void fragment() {
	vec2 q = v_q;
	float fraction = fraction_at(q);
	float thick_part = dome(q, fraction);
	// Per-pixel normal of the height field, tilted by the bend, in view space.
	float e = 0.0025;
	float dx = (height_at(q + vec2(e, 0.0)) - height_at(q - vec2(e, 0.0))) / (2.0 * e);
	float dz = (height_at(q + vec2(0.0, e)) - height_at(q - vec2(0.0, e))) / (2.0 * e);
	vec3 n = normalize(vec3(-dx, 1.0, -dz));
	n.xz += bend * q * n.y;
	n = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);
	// The far side of the rim bead would face away and mirror the ground below the
	// horizon as a dark seam; keep it just facing the viewer.
	NORMAL = normalize(n + VIEW * max(0.0, 0.3 - dot(n, VIEW)));
	// Thick albumen is faintly milky and yellow-green; the thin film is water-clear.
	float cloud = mix(0.07, 0.24, thick_part);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	float depth = film / 0.006 * 0.3 + thick_part;
	vec2 offset = NORMAL.xy * refraction * depth;
	vec3 behind = textureLod(screen_tex, SCREEN_UV - offset, 0.0).rgb;
	// Wetting darkens what is underneath a little; the dome tints it.
	vec3 through = behind * mix(vec3(0.88), tint.rgb * 0.9, thick_part);
	ALBEDO = tint.rgb * cloud;
	EMISSION = through * (1.0 - cloud) * (1.0 - fresnel);
	ROUGHNESS = 0.03;
	SPECULAR = 0.6;
	RIM = 0.2;
	RIM_TINT = 0.8;
	// The edge melts into the surface instead of ending in a hard line.
	ALPHA = 1.0 - smoothstep(0.975, 1.0, fraction);
}
