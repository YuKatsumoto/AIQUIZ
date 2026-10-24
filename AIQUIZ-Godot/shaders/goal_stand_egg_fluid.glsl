#[compute]
#version 450

// Raw egg as a GPU particle fluid (GoalStandEggFluid, HIGH/ULTRA on desktop): the
// splash an egg throws off the surface it breaks on, and the runoff that crawls
// over the body, drips off its edges and pools on the lift deck. Position based
// fluids (Macklin & Mueller 2013): a predicted position is pushed to rest density
// over a few Jacobi iterations, with the tensile correction (s_corr) that makes the
// liquid bead and cling together, XSPH viscosity per phase (thin albumen, thick
// albumen, yolk), and contact with the body's proxies (boxes and capsules from
// GoalStandEggBody) and the deck that sticks or lets slide depending on the slope.
// Then the particles are splatted into a 3D density field that the surface shader
// (goal_stand_egg_fluid_surface.gdshader) raymarches.
//
// One dispatch is one pass (push constant pass_id):
//   0 clear the neighbour hash heads          (per table entry)
//   1 spawn, predict, collide, insert          (per particle)
//   2 density constraint: lambda               (per particle, reads pred[src])
//   3 position correction and collision        (per particle, pred[src] -> pred[1 - src])
//   4 velocity, XSPH viscosity                 (per particle, writes vel_out)
//   5 copy vel_out -> vel, pred -> pos         (per particle)
//   6 splat into the density field             (per particle)
//   7 resolve the field to floats, clear it    (per voxel)
//   8 coarse occupancy (empty space skipping)  (per block)

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Pos { vec4 pos[]; };        // xyz, phase (-1 dead, 0 thin, 1 thick, 2 yolk)
layout(set = 0, binding = 1, std430) restrict buffer Vel { vec4 vel[]; };        // xyz, age (s)
layout(set = 0, binding = 2, std430) restrict buffer PredA { vec4 pred_a[]; };   // xyz, contact (shape + 1, 0 free, -1 deck/floor)
layout(set = 0, binding = 3, std430) restrict buffer PredB { vec4 pred_b[]; };
layout(set = 0, binding = 4, std430) restrict buffer Lambda { float lambda[]; };
layout(set = 0, binding = 5, std430) restrict buffer Heads { int heads[]; };
layout(set = 0, binding = 6, std430) restrict buffer Next { int next_index[]; };
layout(set = 0, binding = 7, std430) restrict buffer VelOut { vec4 vel_out[]; };
layout(set = 0, binding = 8, r32ui) uniform restrict uimage3D density_acc;
layout(set = 0, binding = 9, r32ui) uniform restrict uimage3D yolk_acc;
layout(set = 0, binding = 10, rg16f) uniform restrict image3D field_out;
layout(set = 0, binding = 11, r16f) uniform restrict writeonly image3D coarse_out;

const int MAX_SHAPES = 16;
const int MAX_SPAWNS = 4;

layout(set = 0, binding = 12, std140) uniform Params {
	vec4 sim;        // particle count, dt, h (smoothing radius), rest density
	vec4 tune;       // gravity y, s_corr k, relaxation epsilon, spacing
	vec4 grid_origin;// xyz, voxel size
	vec4 grid_dims;  // nx, ny, nz, coarse block (voxels)
	vec4 world;      // hash table size, shape count, deck on (0/1), floor y
	vec4 deck;       // deck top centre xyz, radius
	vec4 deck_vel;   // deck velocity xyz, render kernel radius (m)
	vec4 viscosity;  // XSPH c: thin, thick, yolk; contact damping (1/s)
	vec4 stick;      // hold on a slope (m/s^2): thin, thick, yolk; particle life (s)
	vec4 spawn_info; // records, -, -, time seed
	vec4 spawn[MAX_SPAWNS * 4];   // per record: origin+reach, normal+normal speed, axis+phase, (tangential xy, start, count)
	vec4 shapes[MAX_SHAPES * 4];  // per shape: GoalStandEggBody.pack_for_gpu
	vec4 shape_vel[MAX_SHAPES];   // per shape: centre velocity xyz
} P;

layout(push_constant, std430) uniform Push {
	int pass_id;
	int src;
	int first;
	int pad;
} pc;

const float PI = 3.14159265;
const int MAX_PER_CELL = 48;
const float MAX_SPEED = 25.0;

int count() { return int(P.sim.x); }
float dt() { return P.sim.y; }
float h() { return P.sim.z; }
float rest() { return P.sim.w; }

vec4 pred_at(int src, int i) { return src == 0 ? pred_a[i] : pred_b[i]; }

ivec3 cell_of(vec3 p) { return ivec3(floor(p / h())); }

int hash_cell(ivec3 c) {
	uint n = uint(c.x) * 73856093u ^ uint(c.y) * 19349663u ^ uint(c.z) * 83492791u;
	return int(n & uint(int(P.world.x) - 1));
}

float poly6(float r2) {
	float hh = h() * h();
	if (r2 >= hh) return 0.0;
	float d = hh - r2;
	return 315.0 / (64.0 * PI * pow(h(), 9.0)) * d * d * d;
}

vec3 spiky_grad(vec3 r) {
	float len = length(r);
	if (len <= 0.000001 || len >= h()) return vec3(0.0);
	float d = h() - len;
	return -45.0 / (PI * pow(h(), 6.0)) * d * d * (r / len);
}

float hash01(uint n) {
	n = (n ^ 61u) ^ (n >> 16u);
	n *= 9u;
	n = n ^ (n >> 4u);
	n *= 0x27d4eb2du;
	n = n ^ (n >> 15u);
	return float(n & 0x00ffffffu) / 16777216.0;
}

// Push p out of every proxy it sinks into (keeping `margin` clear); returns the
// contact normal in n (zero when free) and the shape index + 1 in which (-1 deck).
vec3 collide(vec3 p, float margin, out vec3 n, out float which) {
	n = vec3(0.0);
	which = 0.0;
	int shapes = int(P.world.y);
	for (int s = 0; s < MAX_SHAPES; s++) {
		if (s >= shapes) break;
		vec4 a = P.shapes[s * 4];
		if (a.w < 0.5) {
			// Box: centre a.xyz, half axes in the next three.
			vec3 d = p - a.xyz;
			vec3 ax[3] = vec3[3](P.shapes[s * 4 + 1].xyz, P.shapes[s * 4 + 2].xyz, P.shapes[s * 4 + 3].xyz);
			float best = 1e9;
			int best_axis = -1;
			float best_sign = 1.0;
			bool inside = true;
			float outside_gap = -1e9;
			int out_axis = 0;
			float out_sign = 1.0;
			for (int k = 0; k < 3; k++) {
				float len = max(length(ax[k]), 0.0001);
				float q = dot(d, ax[k]) / len;     // metres along the axis
				float room = len + margin - abs(q);
				if (room <= 0.0) inside = false;
				if (room < best) {
					best = room;
					best_axis = k;
					best_sign = sign(q) == 0.0 ? 1.0 : sign(q);
				}
				float gap = abs(q) - len;
				if (gap > outside_gap) {
					outside_gap = gap;
					out_axis = k;
					out_sign = sign(q) == 0.0 ? 1.0 : sign(q);
				}
			}
			if (inside && best_axis >= 0) {
				vec3 axis = normalize(ax[best_axis]) * best_sign;
				p += axis * best;
				n = axis;
				which = float(s + 1);
			} else if (outside_gap < margin * 1.6 && outside_gap > -1e8) {
				n = normalize(ax[out_axis]) * out_sign;
				which = float(s + 1);
			}
		} else {
			// Capsule: a.xyz to b.xyz, radius b.w.
			vec4 b = P.shapes[s * 4 + 1];
			vec3 ab = b.xyz - a.xyz;
			float t = clamp(dot(p - a.xyz, ab) / max(dot(ab, ab), 0.000001), 0.0, 1.0);
			vec3 c = a.xyz + ab * t;
			vec3 d = p - c;
			float dist = length(d);
			float reach = b.w + margin;
			if (dist < reach * 1.25) {
				vec3 dir = dist > 0.00001 ? d / dist : vec3(0.0, 1.0, 0.0);
				if (dist < reach) p = c + dir * reach;
				n = dir;
				which = float(s + 1);
			}
		}
	}
	// The lift deck (a disc) and the conveyor.
	if (P.world.z > 0.5) {
		vec2 flat_off = p.xz - P.deck.xz;
		if (dot(flat_off, flat_off) < P.deck.w * P.deck.w && p.y < P.deck.y + margin && p.y > P.deck.y - 0.25) {
			p.y = P.deck.y + margin;
			n = vec3(0.0, 1.0, 0.0);
			which = -1.0;
		}
	}
	if (p.y < P.world.w + margin) {
		p.y = P.world.w + margin;
		n = vec3(0.0, 1.0, 0.0);
		which = -2.0;
	}
	return p;
}

vec3 surface_velocity(float which) {
	if (which > 0.5) return P.shape_vel[int(which) - 1].xyz;
	if (which > -1.5 && which < -0.5) return P.deck_vel.xyz;
	return vec3(0.0);
}

float phase_value(vec4 v, float thin, float thick, float yolk) {
	return v.w < 0.5 ? thin : (v.w < 1.5 ? thick : yolk);
}

void spawn(int i) {
	int records = int(P.spawn_info.x);
	for (int r = 0; r < MAX_SPAWNS; r++) {
		if (r >= records) break;
		vec4 o = P.spawn[r * 4];
		vec4 nrm = P.spawn[r * 4 + 1];
		vec4 axis = P.spawn[r * 4 + 2];
		vec4 extra = P.spawn[r * 4 + 3];
		int start = int(extra.z);
		int amount = int(extra.w);
		int j = (i - start + count()) % count();
		if (j >= amount) continue;
		vec3 n = normalize(nrm.xyz);
		vec3 u = normalize(axis.xyz - n * dot(axis.xyz, n));
		vec3 w = cross(n, u);
		uint seed = uint(i) * 747796405u + uint(P.spawn_info.w * 1000.0);
		float jitter = hash01(seed);
		float jitter2 = hash01(seed ^ 0x9e3779b9u);
		// Three in five fly out with the sheet and leave the surface (splash); the rest
		// stay in it as runoff.
		bool splash = (j % 5) < 3;
		float reach = o.w;
		float frac = splash ? mix(0.45, 0.9, sqrt((float(j) + 0.5) / float(amount))) : 0.85 * sqrt((float(j) + 0.5) / float(amount));
		float angle = float(j) * 2.39996 + jitter * 0.6;
		vec2 dir2 = vec2(cos(angle), sin(angle));
		vec3 along = u * dir2.x + w * dir2.y;
		vec3 p = o.xyz + along * reach * frac + n * P.tune.w * 0.6;
		vec3 v = vec3(0.0);
		vec2 tangential = extra.xy;
		vec3 carry = u * tangential.x + w * tangential.y;
		if (splash) {
			float sheet = nrm.w * mix(0.45, 0.8, jitter) * (0.6 + 0.4 * frac);
			v = along * sheet + carry * 0.35 * max(dot(along, normalize(carry + vec3(0.00001))), 0.0) + n * mix(0.4, 1.8, jitter2);
		} else {
			v = along * mix(0.1, 0.5, jitter) + carry * 0.1;
		}
		pos[i] = vec4(p, axis.w);
		vel[i] = vec4(v, 0.0);
		pred_a[i] = vec4(p, 0.0);
		pred_b[i] = vec4(p, 0.0);
		return;
	}
}

void main() {
	uint gid = gl_GlobalInvocationID.x;
	if (pc.pass_id == 0) {
		if (gid < uint(P.world.x)) heads[gid] = -1;
		return;
	}
	if (pc.pass_id == 7) {
		ivec3 dims = ivec3(P.grid_dims.xyz);
		int total = dims.x * dims.y * dims.z;
		if (int(gid) >= total) return;
		ivec3 v = ivec3(int(gid) % dims.x, (int(gid) / dims.x) % dims.y, int(gid) / (dims.x * dims.y));
		float d = float(imageLoad(density_acc, v).r) / 1024.0;
		float y = float(imageLoad(yolk_acc, v).r) / 1024.0;
		imageStore(field_out, v, vec4(d, d > 0.0001 ? y / d : 0.0, 0.0, 0.0));
		imageStore(density_acc, v, uvec4(0u));
		imageStore(yolk_acc, v, uvec4(0u));
		return;
	}
	if (pc.pass_id == 8) {
		ivec3 dims = ivec3(P.grid_dims.xyz);
		int block = int(P.grid_dims.w);
		ivec3 coarse = (dims + block - 1) / block;
		int total = coarse.x * coarse.y * coarse.z;
		if (int(gid) >= total) return;
		ivec3 c = ivec3(int(gid) % coarse.x, (int(gid) / coarse.x) % coarse.y, int(gid) / (coarse.x * coarse.y));
		float most = 0.0;
		// One voxel of overlap so the fine march never steps past a surface at a block seam.
		for (int z = -1; z <= block; z++) {
			for (int yy = -1; yy <= block; yy++) {
				for (int x = -1; x <= block; x++) {
					ivec3 v = clamp(c * block + ivec3(x, yy, z), ivec3(0), dims - 1);
					most = max(most, imageLoad(field_out, v).r);
				}
			}
		}
		imageStore(coarse_out, c, vec4(most));
		return;
	}
	int i = int(gid);
	if (i >= count()) return;
	if (pc.pass_id == 1) {
		if (pc.first == 1) spawn(i);
		vec4 x = pos[i];
		if (x.w < -0.5) {
			pred_a[i] = vec4(x.xyz, 0.0);
			next_index[i] = -1;
			return;
		}
		vec4 v = vel[i];
		v.w += dt();
		float margin = P.tune.w * 0.5;
		vec3 n;
		float which;
		collide(x.xyz, margin, n, which);
		vec3 g = vec3(0.0, P.tune.x, 0.0);
		vec3 vv = v.xyz + g * dt();
		if (which != 0.0) {
			// On a surface: slide down it only when the slope beats the liquid's hold;
			// either way the part it lies on carries it along.
			vec3 carrier = surface_velocity(which);
			vec3 rel = vv - carrier;
			float vn = dot(rel, n);
			vec3 vt = rel - n * vn;
			vec3 gt = g - n * dot(g, n);
			float hold = phase_value(x, P.stick.x, P.stick.y, P.stick.z);
			float damping = P.viscosity.w * (length(gt) < hold ? 6.0 : 1.0) * phase_value(x, 1.0, 2.5, 2.0);
			vt *= exp(-damping * dt());
			if (vn > 0.0 && vn < 0.6) vn *= 0.4;   // adhesion: slow partings stay wet
			vv = carrier + vt + n * vn;
		}
		vel[i] = vec4(vv, v.w);
		vec3 p = x.xyz + vv * dt();
		p = collide(p, margin, n, which);
		pred_a[i] = vec4(p, which);
		ivec3 c = cell_of(p);
		int slot = hash_cell(c);
		next_index[i] = atomicExchange(heads[slot], i);
		return;
	}
	if (pc.pass_id == 2) {
		vec4 pi = pred_at(pc.src, i);
		if (pos[i].w < -0.5) {
			lambda[i] = 0.0;
			return;
		}
		float rho = 0.0;
		vec3 grad_i = vec3(0.0);
		float sum_grad = 0.0;
		ivec3 c = cell_of(pi.xyz);
		for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
			int j = heads[hash_cell(c + ivec3(x, y, z))];
			int guard = 0;
			while (j >= 0 && guard < MAX_PER_CELL) {
				guard++;
				if (pos[j].w > -0.5) {
					vec3 r = pi.xyz - pred_at(pc.src, j).xyz;
					float r2 = dot(r, r);
					if (r2 < h() * h()) {
						rho += poly6(r2);
						if (j != i) {
							vec3 gj = spiky_grad(r) / rest();
							sum_grad += dot(gj, gj);
							grad_i += gj;
						}
					}
				}
				j = next_index[j];
			}
		}
		// Unilateral: only pushes apart (a free surface must not be sucked in).
		float constraint = max(rho / rest() - 1.0, 0.0);
		lambda[i] = -constraint / (sum_grad + dot(grad_i, grad_i) + P.tune.z);
		return;
	}
	if (pc.pass_id == 3) {
		vec4 pi = pred_at(pc.src, i);
		if (pos[i].w < -0.5) {
			if (pc.src == 0) pred_b[i] = pi; else pred_a[i] = pi;
			return;
		}
		vec3 delta = vec3(0.0);
		float w_dq = poly6(0.04 * h() * h());
		ivec3 c = cell_of(pi.xyz);
		for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
			int j = heads[hash_cell(c + ivec3(x, y, z))];
			int guard = 0;
			while (j >= 0 && guard < MAX_PER_CELL) {
				guard++;
				if (j != i && pos[j].w > -0.5) {
					vec3 r = pi.xyz - pred_at(pc.src, j).xyz;
					float r2 = dot(r, r);
					if (r2 < h() * h()) {
						// Tensile correction: a little attraction at mid range beads and holds the liquid.
						float ratio = poly6(r2) / w_dq;
						float s_corr = -P.tune.y * ratio * ratio * ratio * ratio;
						delta += (lambda[i] + lambda[j] + s_corr) * spiky_grad(r);
					}
				}
				j = next_index[j];
			}
		}
		// A correction never moves a particle more than a quarter spacing at once (two
		// that land on top of each other would otherwise blow apart).
		vec3 correction = delta / rest();
		float most = P.tune.w * 0.25;
		if (length(correction) > most) correction *= most / length(correction);
		vec3 p = pi.xyz + correction;
		vec3 n;
		float which;
		p = collide(p, P.tune.w * 0.5, n, which);
		vec4 result = vec4(p, which != 0.0 ? which : pi.w);
		if (pc.src == 0) pred_b[i] = result; else pred_a[i] = result;
		return;
	}
	if (pc.pass_id == 4) {
		vec4 x = pos[i];
		if (x.w < -0.5) {
			vel_out[i] = vel[i];
			return;
		}
		vec4 pi = pred_a[i];
		vec3 v = (pi.xyz - x.xyz) / dt();
		// XSPH: neighbours drag each other toward their mean motion (thick gel most).
		vec3 drag = vec3(0.0);
		float c_visc = phase_value(x, P.viscosity.x, P.viscosity.y, P.viscosity.z);
		ivec3 c = cell_of(pi.xyz);
		for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int xx = -1; xx <= 1; xx++) {
			int j = heads[hash_cell(c + ivec3(xx, y, z))];
			int guard = 0;
			while (j >= 0 && guard < MAX_PER_CELL) {
				guard++;
				if (j != i && pos[j].w > -0.5) {
					vec3 r = pi.xyz - pred_a[j].xyz;
					float r2 = dot(r, r);
					if (r2 < h() * h()) {
						drag += (vel[j].xyz - v) * poly6(r2) / rest();
					}
				}
				j = next_index[j];
			}
		}
		v += c_visc * drag;
		// Nothing in an egg moves faster than its throw.
		float speed = length(v);
		if (speed > MAX_SPEED) v *= MAX_SPEED / speed;
		// Spent: past its life, fallen well below the conveyor, or far out of the field.
		float phase = x.w;
		vec3 field_min = P.grid_origin.xyz - vec3(2.0);
		vec3 field_max = P.grid_origin.xyz + P.grid_dims.xyz * P.grid_origin.w + vec3(2.0);
		if (vel[i].w > P.stick.w || pi.y < P.world.w - 0.5 || any(lessThan(pi.xyz, field_min)) || any(greaterThan(pi.xyz, field_max))) phase = -1.0;
		vel_out[i] = vec4(v, vel[i].w);
		pos[i] = vec4(x.xyz, phase);
		return;
	}
	if (pc.pass_id == 5) {
		vel[i] = vel_out[i];
		if (pos[i].w > -0.5) pos[i] = vec4(pred_a[i].xyz, pos[i].w);
		return;
	}
	if (pc.pass_id == 6) {
		vec4 x = pos[i];
		if (x.w < -0.5) return;
		float life = P.stick.w;
		float weight = 1.0 - smoothstep(life * 0.75, life, vel[i].w);
		if (weight <= 0.0) return;
		float voxel = P.grid_origin.w;
		float radius = P.deck_vel.w;
		vec3 g = (x.xyz - P.grid_origin.xyz) / voxel;
		ivec3 dims = ivec3(P.grid_dims.xyz);
		int reach = int(ceil(radius / voxel));
		ivec3 base = ivec3(floor(g));
		if (any(lessThan(base, ivec3(-reach))) || any(greaterThanEqual(base, dims + reach))) return;
		bool yolk = x.w > 1.5;
		for (int z = -reach; z <= reach + 1; z++) for (int y = -reach; y <= reach + 1; y++) for (int xx = -reach; xx <= reach + 1; xx++) {
			ivec3 v = base + ivec3(xx, y, z);
			if (any(lessThan(v, ivec3(0))) || any(greaterThanEqual(v, dims))) continue;
			vec3 centre = (vec3(v) + 0.5) * voxel + P.grid_origin.xyz;
			float d = length(centre - x.xyz) / radius;
			if (d >= 1.0) continue;
			float k = 1.0 - d * d;
			uint amount = uint(k * k * k * weight * 1024.0);
			if (amount == 0u) continue;
			imageAtomicAdd(density_acc, v, amount);
			if (yolk) imageAtomicAdd(yolk_acc, v, amount);
		}
		return;
	}
}
