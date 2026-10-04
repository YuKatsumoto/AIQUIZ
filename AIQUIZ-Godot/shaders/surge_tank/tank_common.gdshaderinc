// Shared by the surge tank hall shaders (assets/environment/surge_tank, docs/surge_tank_reproduction.md).
//
// The hall is lit by light baked in Blender (Cycles, every lamp of the real tank): each module carries its own
// light map on UV2, RGB = (E / light_max)^(1/2.2), A = baked AO, E = outgoing radiance of a white Lambertian
// surface. The shaders hand E to Godot as IRRADIANCE (decals, SSAO and SSIL still act on it); reflection probes
// and SSR give the specular, and the real lights (the same lamps, placed by the build tool) add only their
// specular highlight in light(): the glints of the high-bays in the wet floor and on damp concrete.
//
// Layout (MLIT plan of the tank): pillar lines k = 0..10 at z = 112 - 14 k (line 0 next to the pump end), rows x = 7 j
// (j = -4..4). The lamps of a line hang in its coffers at the line's z: a pendant high-bay at every free row
// |j| <= 3 (no pillar on that line), i.e. midway between two pillars of the same row.
// Light row r (CisternLighting) = line 10 - r: rows run from the shaft end (r = 0, line z = -28) toward the pumps.
// Floor: a central trench (y = floor) between shelves 5 m higher, 60 deg slopes; side walls at x = +-35.5,
// closing in to +-20 over the last 15.2 m before the shaft-side end wall (z = -38.6).

global uniform sampler2D cistern_row_light;
// x = z of the pillar line of row 0 (-28), y = line pitch (14), z = row count (11), w = unused by the tank.
global uniform vec4 cistern_row_grid;
// The water has wetted everything upstream of this world z (-1000 = dry).
global uniform float cistern_wet_z;

const float TK_LAMP_OFFSET = 0.0;
const float TK_PI = 3.14159265;
const float TK_FLOOR_Y = -1.2;

// The stage is the plan (metres of the MLIT drawings) scaled by this about the landing point (SuddenDeathLayout.TANK_SCALE):
// every plan-based lookup below takes plan coordinates, i.e. (world - (0, floor, 0)) / tank_scale.
uniform float tank_scale = 1.0;
// Faint ambient keeping unlit concrete off pure black (the bake already holds every bounce).
uniform vec3 ambient_color : source_color = vec3(0.55, 0.6, 0.66);
uniform float ambient_level = 0.006;
// Camera white balance of the bake (the lamps are ~4800 K): gain per channel, set by the build tool.
uniform vec3 white_balance = vec3(1.0);
// Real-light highlights on the hall (light()): 0 turns them off.
uniform float light_specular_scale = 1.0;

float tk_row_value(int r) {
	int last = max(int(cistern_row_grid.z) - 1, 0);
	return texelFetch(cistern_row_light, ivec2(clamp(r, 0, last), 0), 0).r;
}

// Row brightness at world z, interpolated between the lamp rows so a lit line fades into a dark one.
float tk_brightness(float z) {
	float pitch = max(cistern_row_grid.y, 0.001);
	float f = (z - (cistern_row_grid.x - TK_LAMP_OFFSET)) / pitch;
	float i0 = floor(f);
	float t = smoothstep(0.0, 1.0, f - i0);
	return mix(tk_row_value(int(i0)), tk_row_value(int(i0) + 1), t);
}

// 1 where the water has been, with a ragged edge.
float tk_flooded(vec3 p, float noise) {
	return 1.0 - smoothstep(cistern_wet_z - 2.5, cistern_wet_z + 0.5, p.z + (noise - 0.5) * 3.0);
}

// Value noise from a tiling texture at three unrelated scales (no repeat lines up with the 13.5 m slices).
float tk_macro(sampler2D noise_tex, vec2 w) {
	float n1 = texture(noise_tex, w * (1.0 / 23.0)).r;
	float n2 = texture(noise_tex, w * (1.0 / 7.3) + vec2(0.37, 0.71)).r;
	float n3 = texture(noise_tex, w * (1.0 / 61.0) + vec2(0.13, 0.29)).r;
	return n1 * 0.5 + n2 * 0.25 + n3 * 0.25;
}

// World-planar projection by the dominant axis of the world normal: uv (metres), and the world directions of
// increasing u and of "up" in the texture (v grows downward in the image, so up = -dv).
void tk_world_plane(vec3 p, vec3 wn, out vec2 uv, out vec3 tu, out vec3 tup) {
	vec3 an = abs(wn);
	if (an.y >= an.x && an.y >= an.z) {
		float s = wn.y >= 0.0 ? 1.0 : -1.0;
		uv = vec2(p.x, p.z * s);
		tu = vec3(1.0, 0.0, 0.0);
		tup = vec3(0.0, 0.0, -s);
	} else if (an.x >= an.z) {
		float s = wn.x >= 0.0 ? 1.0 : -1.0;
		uv = vec2(-p.z * s, -p.y);
		tu = vec3(0.0, 0.0, -s);
		tup = vec3(0.0, 1.0, 0.0);
	} else {
		float s = wn.z >= 0.0 ? 1.0 : -1.0;
		uv = vec2(p.x * s, -p.y);
		tu = vec3(s, 0.0, 0.0);
		tup = vec3(0.0, 1.0, 0.0);
	}
}

// Half width of the trench at its crest (top of the slopes): 27 m at the pump end, 20 m in the main stretch,
// 15 m at the shaft-side end wall.
float tk_trench_crest(float z) {
	float u = 132.8 - z;
	float c = mix(27.0, 20.0, clamp((u - 41.7) / 27.7, 0.0, 1.0));
	return mix(c, 15.0, clamp((u - 153.8) / 17.6, 0.0, 1.0));
}

// Floor height above the trench floor at xz: 0 in the trench, the 60 deg slope (2.9 m run), 5 m on the shelves.
float tk_floor_height(vec2 xz) {
	float toe = tk_trench_crest(xz.y) - 2.9;
	return clamp((abs(xz.x) - toe) / 2.9, 0.0, 1.0) * 5.0;
}

// Half width of the tank at z (inner face of the side walls).
float tk_wall_half(float z) {
	return mix(35.5, 20.0, clamp((-23.4 - z) / 15.2, 0.0, 1.0));
}

// Pillar of line k in row j? Odd lines: j = 0, +-2, +-4; even lines: j = +-1, +-3, +-4 (line 10: +-1, +-3).
bool tk_has_pillar(int k, int j) {
	if (k < 0 || k > 10 || j < -4 || j > 4) {
		return false;
	}
	int aj = abs(j);
	if (k % 2 == 1) {
		return aj % 2 == 0;
	}
	return aj % 2 == 1 || (aj == 4 && k != 10);
}

// Distance (m) from a floor point to the nearest pillar (7 x 2 m, half-round ends, long axis along z).
float tk_pillar_distance(vec2 xz) {
	int kc = int(round((112.0 - xz.y) / 14.0));
	int jc = int(round(xz.x / 7.0));
	float best = 1e6;
	for (int dk = -1; dk <= 1; dk++) {
		for (int dj = -1; dj <= 1; dj++) {
			int k = kc + dk;
			int j = jc + dj;
			if (!tk_has_pillar(k, j)) {
				continue;
			}
			vec2 d = xz - vec2(7.0 * float(j), 112.0 - 14.0 * float(k));
			d.y = d.y - clamp(d.y, -2.5, 2.5);
			best = min(best, length(d) - 1.0);
		}
	}
	return best;
}
