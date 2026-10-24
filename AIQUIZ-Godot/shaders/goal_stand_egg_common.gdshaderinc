// Shared by the raw egg shaders (goal_stand_egg_white / _rivulet): the splat data
// texture GoalStandEggContents writes, the rim outline, and the wrap that bends a
// splat over box edges or around a capsule. Mirrors GoalStandEggSplat.wrap_point()
// and write_row(), so CPU and GPU agree where the liquid is.
//
// Row layout (RGBA float texels): 0..47 rim radius (r), then
//   48 (film, thick height, alpha, seed)   49 (thick centre xy, thick radius, wrap)
//   50 extents (min x, max x, min y, max y) 51 (depth, edge round, kind, -)
//   52 thick shape (phase 1, phase 2, amp 3 lobes, amp 5 lobes)
//   53 + 2 i, 54 + 2 i: rivulet i (start xy, angle, length), (width, head h, trail h, seed)

uniform sampler2D splat_data : filter_nearest, repeat_disable;

const int EGG_RIM = 48;
const int EGG_HEADER = 48;
const int WRAP_PLANE = 0;
const int WRAP_BOX = 1;
const int WRAP_CAPSULE = 2;

struct EggSplat {
	float film;
	float thick;
	float alpha;
	float seed;
	vec2 thick_center;
	float thick_radius;
	int wrap;
	vec4 extents;
	float depth;
	float edge_round;
	float kind;
	vec4 thick_shape;
};

vec4 egg_texel(int row, int col) {
	return texelFetch(splat_data, ivec2(col, row), 0);
}

EggSplat egg_load(int row) {
	EggSplat s;
	vec4 h0 = egg_texel(row, EGG_HEADER);
	vec4 h1 = egg_texel(row, EGG_HEADER + 1);
	vec4 h3 = egg_texel(row, EGG_HEADER + 3);
	s.film = h0.x;
	s.thick = h0.y;
	s.alpha = h0.z;
	s.seed = h0.w;
	s.thick_center = h1.xy;
	s.thick_radius = h1.z;
	s.wrap = int(h1.w + 0.5);
	s.extents = egg_texel(row, EGG_HEADER + 2);
	s.depth = h3.x;
	s.edge_round = h3.y;
	s.kind = h3.z;
	s.thick_shape = egg_texel(row, EGG_HEADER + 4);
	return s;
}

// Catmull-Rom through the rim samples (GoalStandEggSplat.rim_at).
float egg_rim_at(int row, float angle) {
	float a = angle / TAU;
	a -= floor(a);
	float x = a * float(EGG_RIM);
	int i1 = int(floor(x)) % EGG_RIM;
	float p0 = egg_texel(row, (i1 + EGG_RIM - 1) % EGG_RIM).r;
	float p1 = egg_texel(row, i1).r;
	float p2 = egg_texel(row, (i1 + 1) % EGG_RIM).r;
	float p3 = egg_texel(row, (i1 + 2) % EGG_RIM).r;
	float t = fract(x);
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)));
}

// One axis of the box fold: (coordinate, drop below the face, normal sin, normal cos).
vec4 egg_fold(float x, float lo, float hi, float deep, float r) {
	float over;
	float side = 1.0;
	float edge;
	if (x > hi - r) {
		over = x - (hi - r);
		edge = hi - r;
	} else if (x < lo + r) {
		over = (lo + r) - x;
		edge = lo + r;
		side = -1.0;
	} else {
		return vec4(x, 0.0, 0.0, 1.0);
	}
	float arc = r * PI * 0.5;
	if (over < arc) {
		float a = over / r;
		return vec4(edge + side * r * sin(a), r * (1.0 - cos(a)), side * sin(a), cos(a));
	}
	float down = min(over - arc, max(deep - r, 0.0));
	return vec4(edge + side * r, r + down, side, 0.0);
}

// Frame-local position and normal of plane point q at height h over the surface.
void egg_wrap(EggSplat s, vec2 q, float h, out vec3 pos, out vec3 n) {
	if (s.wrap == WRAP_CAPSULE) {
		float a = clamp(q.y / max(s.depth, 0.01), -PI * 0.95, PI * 0.95);
		n = vec3(0.0, cos(a), sin(a));
		pos = vec3(q.x, (s.depth + h) * cos(a) - s.depth, (s.depth + h) * sin(a));
	} else if (s.wrap == WRAP_BOX) {
		vec4 fx = egg_fold(q.x, s.extents.x, s.extents.y, s.depth, s.edge_round);
		vec4 fz = egg_fold(q.y, s.extents.z, s.extents.w, s.depth, s.edge_round);
		n = normalize(vec3(fx.z, fx.w * fz.w, fz.z));
		pos = vec3(fx.x, -fx.y - fz.y, fz.x) + n * h;
	} else {
		n = vec3(0.0, 1.0, 0.0);
		pos = vec3(q.x, h, q.y);
	}
}

// Rotate v by the rotation that takes +Y to n (a plane normal onto the fold).
vec3 egg_tilt(vec3 v, vec3 n) {
	vec3 axis = vec3(n.z, 0.0, -n.x);
	float s = length(axis);
	float c = n.y;
	if (s < 0.00001) {
		return c > 0.0 ? v : vec3(v.x, -v.y, -v.z);
	}
	axis /= s;
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

float egg_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise in [0, 1].
float egg_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(egg_hash(i), egg_hash(i + vec2(1.0, 0.0)), u.x),
		mix(egg_hash(i + vec2(0.0, 1.0)), egg_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Screen-space shift of what is seen through a layer `thickness` (m) thick whose
// view-space normal is n, at view depth `depth` (m): the layer bends rays by about
// (n - 1) = 0.35 of its slope over its thickness. `focal` is PROJECTION_MATRIX[1][1].
vec2 egg_refraction(vec3 n, float thickness, float depth, float focal) {
	return n.xy * thickness * 0.35 * focal * 0.5 / max(depth, 0.05);
}

float egg_fresnel(float facing) {
	return 0.02 + 0.98 * pow(1.0 - clamp(facing, 0.0, 1.0), 5.0);
}
