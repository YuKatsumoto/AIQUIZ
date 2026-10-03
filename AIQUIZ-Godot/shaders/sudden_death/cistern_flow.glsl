#[compute]
#version 450

// 地下神殿の水の流体シミュレーション（docs/sudden_death_underground.md 6.6節）。
// 浅水方程式（shallow water equations）をスタッガード格子で解く。1回の呼び出しで1つのパスを行い、
// pass_id で切り替える：0 移流（流速と泡を半ラグランジュ法で運ぶ）、1 水深（風上の水深でフラックスを
// 取り、流入・水位の保持・下流の吸収・しぶきを足す）、2 流速（水面の勾配で加速、摩擦、乾いた面の遮断、
// 流入と下流の流出）、3 表示（水面の高さ・流速・泡を水面メッシュ用に書き出す）。CisternFlow が
// 1フレームに 0→1→2 を数回（1/120秒刻み）回し、最後に 3 を1回行う。
//
// 状態の画像（(nx+1)×(nz+1)、rgba32f）の画素 (i, j)：
//   r = セル (i, j) の水深 h（m）、g = セルの左の面（x = i）の流速 u（+X 向き、m/s）、
//   b = セルの下の面（z = j）の流速 w（+Z 向き、m/s）、a = セルの泡の量（0〜1.5）。
//   i = nx の列は右端の面の u、j = nz の行は上端の面の w だけを持つ。
// 床の高さ（r32f、nx×nz）は柱と端の壁を高い値（WALL 以上＝固体）で持ち、リフトのタワーは円で上から重ねる。
// 高さはすべて地下神殿の床（FLOOR_Y）から測る。座標は格子の局所座標（m、原点はセル (0,0) の角）。

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform restrict readonly image2D state_in;
layout(set = 0, binding = 1, rgba32f) uniform restrict writeonly image2D state_out;
layout(set = 0, binding = 2, r32f) uniform restrict readonly image2D bed_tex;
layout(set = 0, binding = 3, rgba16f) uniform restrict writeonly image2D display_out;

layout(set = 0, binding = 4, std140) uniform Params {
	vec4 grid;      // nx, nz, cell (m), dt (s)
	vec4 world;     // origin x, origin z (world, the corner of cell (0,0)), gravity, time
	vec4 level;     // target level (m), fill rate (1/s, wet cells below the level), relax rate (1/s, above), dry depth (m)
	vec4 inflow;    // half width (m), surface level at the mouth (m), speed (m/s, +Z), on (0/1)
	vec4 sponge;    // start z (world), rate (1/s), outflow speed (m/s), max speed (m/s)
	vec4 tower_a;   // world x, world z, radius (m, 0 = none), top (m)
	vec4 tower_b;
	vec4 splash_a;  // world x, world z, radius (m), strength (m, 0 = none)
	vec4 splash_b;
	vec4 foam;      // decay time (s), speed gain, compression gain, inflow foam
	vec4 friction;  // linear damping (1/s), bottom friction coefficient, foam speed threshold (m/s), front foam gain
	vec4 current;   // steering rate (1/s) toward the hall's current, vorticity foam gain, vorticity threshold (1/s), current (m/s, +Z)
} P;

layout(push_constant, std430) uniform Push {
	int pass_id;
	int impulse;   // 1 on the first substep of a frame: the splashes are applied once
	float pad0;
	float pad1;
} pc;

const float WALL = 20.0;

ivec2 grid_size() {
	return ivec2(P.grid.xy);
}

float cell() {
	return P.grid.z;
}

float dt() {
	return P.grid.w;
}

bool inside(ivec2 c) {
	ivec2 n = grid_size();
	return c.x >= 0 && c.y >= 0 && c.x < n.x && c.y < n.y;
}

vec2 world_of(vec2 local) {
	return P.world.xy + local;
}

float tower_bed(vec2 p, vec4 t) {
	return (t.z > 0.0 && distance(p, t.xy) < t.z) ? t.w : -1.0;
}

float bed(ivec2 c) {
	if (!inside(c)) {
		return 100.0;
	}
	float b = imageLoad(bed_tex, c).r;
	vec2 p = world_of((vec2(c) + 0.5) * cell());
	b = max(b, tower_bed(p, P.tower_a));
	b = max(b, tower_bed(p, P.tower_b));
	return b;
}

bool solid(ivec2 c) {
	return bed(c) >= WALL;
}

vec4 S(ivec2 c) {
	return imageLoad(state_in, clamp(c, ivec2(0), grid_size()));
}

float depth(ivec2 c) {
	return inside(c) ? S(c).r : 0.0;
}

// Bilinear sample of one channel (picked by [param mask]) whose nodes sit at (i + ox, j + oz) * cell,
// i in [0, max.x], j in [0, max.y].
float sample_channel(vec2 local, vec2 node_offset, ivec2 max_index, vec4 mask) {
	vec2 f = clamp(local / cell() - node_offset, vec2(0.0), vec2(max_index));
	ivec2 i0 = ivec2(floor(f));
	ivec2 i1 = min(i0 + 1, max_index);
	vec2 t = f - vec2(i0);
	float a = dot(S(i0), mask);
	float b = dot(S(ivec2(i1.x, i0.y)), mask);
	float c = dot(S(ivec2(i0.x, i1.y)), mask);
	float d = dot(S(i1), mask);
	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

float sample_u(vec2 local) {
	return sample_channel(local, vec2(0.0, 0.5), grid_size() - ivec2(0, 1), vec4(0.0, 1.0, 0.0, 0.0));
}

float sample_w(vec2 local) {
	return sample_channel(local, vec2(0.5, 0.0), grid_size() - ivec2(1, 0), vec4(0.0, 0.0, 1.0, 0.0));
}

float sample_foam(vec2 local) {
	return sample_channel(local, vec2(0.5, 0.5), grid_size() - ivec2(1, 1), vec4(0.0, 0.0, 0.0, 1.0));
}

// A splash: water thrown up in a ring around a hole where something fell in (m of depth added).
float splash_height(vec2 p, vec4 s) {
	if (s.w == 0.0 || s.z <= 0.0) {
		return 0.0;
	}
	float d = distance(p, s.xy);
	float ring = exp(-pow((d - s.z) / (0.45 * s.z), 2.0));
	float hole = exp(-pow(d / (0.6 * s.z), 2.0));
	return s.w * (ring - 0.9 * hole);
}

// The outward push of a splash (m/s along +direction from its centre).
vec2 splash_velocity(vec2 p, vec4 s) {
	if (s.w == 0.0 || s.z <= 0.0) {
		return vec2(0.0);
	}
	vec2 d = p - s.xy;
	float r = length(d);
	if (r < 0.001) {
		return vec2(0.0);
	}
	float ring = exp(-pow((r - s.z) / (0.6 * s.z), 2.0));
	return d / r * ring * s.w * 6.0;
}

bool in_inflow(vec2 p_world, int row) {
	return P.inflow.w > 0.5 && row < 3 && abs(p_world.x) < P.inflow.x;
}

float sponge_amount(float z_world) {
	return clamp((z_world - P.sponge.x) / 8.0, 0.0, 1.0);
}

// ---------------------------------------------------------------- 0: advection

void pass_advect(ivec2 c) {
	vec4 self = S(c);
	ivec2 n = grid_size();
	float u = 0.0;
	float w = 0.0;
	float f = 0.0;
	if (c.y < n.y) {
		vec2 pos = vec2(float(c.x), float(c.y) + 0.5) * cell();
		vec2 vel = vec2(self.g, sample_w(pos));
		u = sample_u(pos - dt() * vel);
	}
	if (c.x < n.x) {
		vec2 pos = vec2(float(c.x) + 0.5, float(c.y)) * cell();
		vec2 vel = vec2(sample_u(pos), self.b);
		w = sample_w(pos - dt() * vel);
	}
	if (inside(c)) {
		vec2 pos = (vec2(c) + 0.5) * cell();
		float u_right = S(c + ivec2(1, 0)).g;
		float w_top = S(c + ivec2(0, 1)).b;
		vec2 vel = vec2(0.5 * (self.g + u_right), 0.5 * (self.b + w_top));
		f = sample_foam(pos - dt() * vel);
		// White water where it runs fast and where it piles up (the bore of the flood, the wake of a tower).
		float divergence = (u_right - self.g + w_top - self.b) / cell();
		float speed = length(vel);
		float gain = P.foam.y * max(speed - P.friction.z, 0.0) + P.foam.z * max(-divergence, 0.0);
		// The thin, fast leading edge of the flood is white water (deep water stays dark).
		gain += P.friction.w * max(speed - 3.0, 0.0) * exp(-2.5 * self.r);
		// Where the current shears past a tower or a pillar it curls into eddies: streaks of white downstream.
		float u_up = 0.5 * (S(c + ivec2(0, 1)).g + S(c + ivec2(1, 1)).g);
		float u_down = 0.5 * (S(c - ivec2(0, 1)).g + S(c + ivec2(1, -1)).g);
		float w_right = 0.5 * (S(c + ivec2(1, 0)).b + S(c + ivec2(1, 1)).b);
		float w_left = 0.5 * (S(c - ivec2(1, 0)).b + S(c + ivec2(-1, 1)).b);
		float curl = ((w_right - w_left) - (u_up - u_down)) / (2.0 * cell());
		gain += P.current.y * max(abs(curl) - P.current.z, 0.0);
		f = f * exp(-dt() / max(P.foam.x, 0.01)) + dt() * gain;
		if (in_inflow(world_of(pos), c.y)) {
			f = max(f, P.foam.w);
		}
		if (self.r <= P.level.w) {
			f = 0.0;
		}
		f = clamp(f, 0.0, 1.5);
	}
	imageStore(state_out, c, vec4(self.r, u, w, f));
}

// ---------------------------------------------------------------- 1: depth

void pass_height(ivec2 c) {
	vec4 self = S(c);
	if (!inside(c)) {
		imageStore(state_out, c, self);
		return;
	}
	if (solid(c)) {
		imageStore(state_out, c, vec4(0.0, self.g, self.b, 0.0));
		return;
	}
	float h = self.r;
	float u_left = self.g;
	float u_right = S(c + ivec2(1, 0)).g;
	float w_bottom = self.b;
	float w_top = S(c + ivec2(0, 1)).b;
	// Upwind depth on each face: what flows across it comes from the cell it leaves.
	float f_left = u_left * (u_left > 0.0 ? depth(c - ivec2(1, 0)) : h);
	float f_right = u_right * (u_right > 0.0 ? h : depth(c + ivec2(1, 0)));
	float f_bottom = w_bottom * (w_bottom > 0.0 ? depth(c - ivec2(0, 1)) : h);
	float f_top = w_top * (w_top > 0.0 ? h : depth(c + ivec2(0, 1)));
	h -= dt() / cell() * (f_right - f_left + f_top - f_bottom);
	float b = bed(c);
	vec2 p = world_of((vec2(c) + 0.5) * cell());
	if (in_inflow(p, c.y)) {
		h = max(h, P.inflow.y - b);
	}
	if (h > P.level.w) {
		// The hall fills toward (and is held at) the level: below it quickly while the flood comes in,
		// above it gently, so the waves live on.
		float error = P.level.x - (h + b);
		h += dt() * (error > 0.0 ? P.level.y : P.level.z) * error;
		// Downstream the water leaves the simulated part of the hall without reflecting.
		float s = sponge_amount(p.y);
		if (s > 0.0) {
			h += dt() * P.sponge.y * s * (P.level.x - (h + b));
		}
		if (pc.impulse == 1) {
			h += splash_height(p, P.splash_a) + splash_height(p, P.splash_b);
		}
	}
	imageStore(state_out, c, vec4(max(h, 0.0), self.g, self.b, self.a));
}

// ---------------------------------------------------------------- 2: velocity

float face_velocity(float v, ivec2 a, ivec2 b) {
	// a: the cell on the minus side, b: on the plus side.
	if (!inside(a) || !inside(b) || solid(a) || solid(b)) {
		return 0.0;
	}
	float ha = depth(a);
	float hb = depth(b);
	float eps = P.level.w;
	if (ha <= eps && hb <= eps) {
		return 0.0;
	}
	v -= dt() * P.world.z * ((hb + bed(b)) - (ha + bed(a))) / cell();
	float hf = max(0.5 * (ha + hb), 0.05);
	v /= 1.0 + dt() * (P.friction.x + P.friction.y * abs(v) / hf);
	// Water only leaves a cell that has some.
	if ((v > 0.0 && ha <= eps) || (v < 0.0 && hb <= eps)) {
		return 0.0;
	}
	return clamp(v, -P.sponge.w, P.sponge.w);
}

void pass_velocity(ivec2 c) {
	vec4 self = S(c);
	ivec2 n = grid_size();
	float u = 0.0;
	float w = 0.0;
	if (c.y < n.y) {
		u = face_velocity(self.g, c - ivec2(1, 0), c);
		vec2 p = world_of(vec2(float(c.x), float(c.y) + 0.5) * cell());
		if (in_inflow(p, c.y)) {
			u *= 0.5;
		}
		if (pc.impulse == 1) {
			u += (splash_velocity(p, P.splash_a) + splash_velocity(p, P.splash_b)).x;
		}
	}
	if (c.x < n.x) {
		w = face_velocity(self.b, c - ivec2(0, 1), c);
		// The hall runs downstream (the pumps at the far end draw the water on): wet water is steered toward
		// the hall's current, which builds no slope the way a push would.
		if (inside(c) && inside(c - ivec2(0, 1)) && depth(c) > 0.3 && depth(c - ivec2(0, 1)) > 0.3) {
			w += dt() * P.current.x * (P.current.w - w);
		}
		vec2 p = world_of(vec2(float(c.x) + 0.5, float(c.y)) * cell());
		if (in_inflow(p, c.y) && c.y > 0 && !solid(c)) {
			w = P.inflow.z;
		}
		float s = sponge_amount(p.y);
		if (s > 0.0 && inside(c) && depth(c) > P.level.w) {
			w = mix(w, P.sponge.z, clamp(dt() * P.sponge.y * s, 0.0, 1.0));
		}
		if (pc.impulse == 1) {
			w += (splash_velocity(p, P.splash_a) + splash_velocity(p, P.splash_b)).y;
		}
	}
	imageStore(state_out, c, vec4(self.r, clamp(u, -P.sponge.w, P.sponge.w), clamp(w, -P.sponge.w, P.sponge.w), self.a));
}

// ---------------------------------------------------------------- 3: display

void pass_display(ivec2 c) {
	if (!inside(c)) {
		return;
	}
	vec4 self = S(c);
	float h = self.r;
	float b = bed(c);
	vec2 vel = vec2(0.5 * (self.g + S(c + ivec2(1, 0)).g), 0.5 * (self.b + S(c + ivec2(0, 1)).b));
	const float SHOW = 0.01;
	float height;
	float wet;
	if (h > SHOW) {
		// Lightly smoothed with the wet neighbours: the grid's steps do not show on a steep bore.
		float sum = 2.0 * (h + b);
		float count = 2.0;
		for (int k = 0; k < 4; k++) {
			ivec2 q = c + ivec2(k == 0 ? -1 : (k == 1 ? 1 : 0), k == 2 ? -1 : (k == 3 ? 1 : 0));
			if (inside(q) && S(q).r > SHOW) {
				sum += S(q).r + bed(q);
				count += 1.0;
			}
		}
		height = sum / count;
		// The edge of the flood leans toward the dry floor ahead of it instead of standing as a wall.
		bool shore = false;
		for (int k = 0; k < 4; k++) {
			ivec2 q = c + ivec2(k == 0 ? -1 : (k == 1 ? 1 : 0), k == 2 ? -1 : (k == 3 ? 1 : 0));
			if (inside(q) && !solid(q) && S(q).r <= SHOW && bed(q) < b + 0.5) {
				shore = true;
			}
		}
		if (shore) {
			height = b + 0.45 * (height - b);
		}
		wet = self.a;
	} else {
		// Dry: next to water the surface slopes down to the floor here (the thin edge of the flood), or stays
		// at the water level against a tower or a pillar it cannot climb; away from water it is hidden under
		// the floor or inside the tower or pillar it belongs to.
		float sum = 0.0;
		float count = 0.0;
		for (int dz = -1; dz <= 1; dz++) {
			for (int dx = -1; dx <= 1; dx++) {
				ivec2 q = c + ivec2(dx, dz);
				if (inside(q) && S(q).r > SHOW) {
					sum += S(q).r + bed(q);
					count += 1.0;
				}
			}
		}
		height = count > 0.0 ? min(sum / count, b + 0.02) : min(b, 6.0) - 0.3;
		wet = -1.0;
	}
	imageStore(display_out, c, vec4(height, vel, wet));
}

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	ivec2 n = grid_size();
	if (c.x > n.x || c.y > n.y) {
		return;
	}
	if (pc.pass_id == 0) {
		pass_advect(c);
	} else if (pc.pass_id == 1) {
		pass_height(c);
	} else if (pc.pass_id == 2) {
		pass_velocity(c);
	} else {
		pass_display(c);
	}
}
