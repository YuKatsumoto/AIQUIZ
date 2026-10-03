// Shared by the cistern hall shaders (docs/sudden_death_m3_interface.md, docs/sudden_death_underground.md 6.4–6.5).
//
// The hall is lit by light baked in Blender, never by Godot lights (the meshes sit on visual layer 11 only and
// every real light leaves that layer out of its cull mask). Each module carries its own light map on UV2:
// RGB = (E / light_max)^(1/2.2), A = baked AO. The shaders scale it by the brightness of the light rows
// (global cistern_row_light, written by CisternLighting) and hand it to Godot as IRRADIANCE, so decals
// (they change ALBEDO after fragment()), SSAO and SSIL still act on it; reflection probes and SSR supply the
// specular. The shaft light through the ceiling opening is not baked: its pool is evaluated here.
//
// World coordinates of the stage (SuddenDeathLayout): floor y = -1.2, bay k centred on z = 15 k, a floodlight
// pair per bay on the inner pillar faces (x = +-11.9) 7 m up at bay z + 3.5, the opening centred on x = z = 0.

global uniform sampler2D cistern_row_light;
// x = centre z of bay k = -1, y = bay pitch, z = bay count, w = shaft light amount (Godot side only).
global uniform vec4 cistern_row_grid;
// The flood has wetted everything upstream of this world z (docs 6.6; -1000 = dry). CisternLighting.
global uniform float cistern_wet_z;

const float CIS_FLOOR_Y = -1.2;
const float CIS_LAMP_X = 11.5;
const float CIS_LAMP_Y = 5.8;
const float CIS_LAMP_DZ = 3.5;
const float CIS_OPENING_APEX_Y = 17.6;
const float CIS_PI = 3.14159265;

// Shaft light pool (cool, ~6500 K) and the faint ambient that keeps unlit concrete from going pure black.
uniform vec3 opening_color : source_color = vec3(0.70, 0.82, 1.0);
uniform float opening_strength = 2.4;
uniform vec3 ambient_color : source_color = vec3(0.55, 0.62, 0.72);
uniform float ambient_level = 0.012;
// Camera white balance of the baked light (the review renders use 5000 K): gain per channel, set by the
// build tool so the ~5000 K floodlights read white and the ~2000 K safety lamps amber.
uniform vec3 white_balance = vec3(1.0);

// Brightness of bay k (clamped to the hall; both ends use their end bay).
float cis_bay_value(int k) {
	int last = int(cistern_row_grid.z) - 2;
	int index = clamp(k, -1, last) + 1;
	return texelFetch(cistern_row_light, ivec2(index, 0), 0).r;
}

// Row brightness at world z, interpolated between the lamp rows (bay centre + 3.5 m) so a lit row fades into
// a dark one across the bay instead of stepping at the module seam.
float cis_brightness(float z) {
	float f = (z - cistern_row_grid.x - CIS_LAMP_DZ) / max(cistern_row_grid.y, 0.001);
	float i0 = floor(f);
	float t = smoothstep(0.0, 1.0, f - i0);
	int k0 = int(i0) - 1;
	return mix(cis_bay_value(k0), cis_bay_value(k0 + 1), t);
}

float cis_opening_amount() {
	return cistern_row_grid.w;
}

// 1 where the flood has been, with a ragged edge (noise 0..1 from the world noise).
float cis_flooded(vec3 p, float noise) {
	return 1.0 - smoothstep(cistern_wet_z - 2.5, cistern_wet_z + 0.5, p.z + (noise - 0.5) * 3.0);
}

// Irradiance of the shaft light (a spot straight down through the 14 m opening, 24 deg half angle), plus
// a little light bounced off its pool on the floor.
vec3 cis_opening_light(vec3 p, vec3 n) {
	float amount = cistern_row_grid.w;
	if (amount <= 0.0) {
		return vec3(0.0);
	}
	vec3 d = vec3(0.0, CIS_OPENING_APEX_Y, 0.0) - p;
	float d2 = max(dot(d, d), 1.0);
	vec3 l = d * inversesqrt(d2);
	float cone = smoothstep(0.906, 0.972, l.y);
	float direct = max(dot(n, l), 0.0) * cone * (400.0 / d2);
	vec3 pool = vec3(0.0, CIS_FLOOR_Y, 0.0) - p;
	float r = length(pool);
	vec3 to_pool = pool / max(r, 0.001);
	float bounce = 0.10 * exp(-r * 0.09) * (0.35 + 0.65 * max(dot(n, to_pool), 0.0));
	return opening_color * amount * opening_strength * (direct + bounce);
}

// The z of floodlight row `row` (row 0 = bay k = -1).
float cis_lamp_z(float row) {
	return cistern_row_grid.x + row * cistern_row_grid.y + CIS_LAMP_DZ;
}

// Direction to the nearest floodlight (for relighting the baked light with the normal map).
vec3 cis_nearest_lamp_dir(vec3 p) {
	float row = clamp(floor((p.z - cistern_row_grid.x - CIS_LAMP_DZ) / cistern_row_grid.y + 0.5), 0.0, cistern_row_grid.z - 1.0);
	vec3 lamp = vec3(p.x >= 0.0 ? CIS_LAMP_X : -CIS_LAMP_X, CIS_LAMP_Y, cis_lamp_z(row));
	// Out in the side aisles the corridor lamps are hidden: light arrives from above and from the corridor.
	if (abs(p.x) > 13.9) {
		lamp = vec3(sign(p.x) * 12.0, CIS_LAMP_Y + 4.0, cis_lamp_z(row));
	}
	return normalize(lamp - p);
}

// GGX highlights of the floodlights on wet surfaces (radiance, before the row brightness). The real lights
// never touch the hall, so the glints the lamps leave on wet concrete come from here.
vec3 cis_lamp_glints(vec3 p, vec3 n, vec3 v, float rough, float f0, vec3 lamp_color) {
	float f = (p.z - cistern_row_grid.x - CIS_LAMP_DZ) / cistern_row_grid.y;
	float r0 = floor(f);
	float a = max(rough * rough, 0.004);
	float a2 = a * a;
	float ndv = max(dot(n, v), 0.001);
	vec3 sum = vec3(0.0);
	for (int dr = -2; dr <= 3; dr++) {
		float row = r0 + float(dr);
		if (row < 0.0 || row > cistern_row_grid.z - 1.0) {
			continue;
		}
		float bright = texelFetch(cistern_row_light, ivec2(int(row), 0), 0).r;
		if (bright <= 0.001) {
			continue;
		}
		float lz = cis_lamp_z(row);
		for (int s = 0; s < 2; s++) {
			float side = s == 0 ? -1.0 : 1.0;
			vec3 lp = vec3(side * CIS_LAMP_X, CIS_LAMP_Y, lz);
			vec3 d = lp - p;
			float d2 = dot(d, d);
			vec3 l = d * inversesqrt(d2);
			float ndl = dot(n, l);
			if (ndl <= 0.0) {
				continue;
			}
			// The fixture aims across the corridor and down (to x = -+2, the floor, 3 m downstream).
			vec3 aim = normalize(vec3(-side * 9.5, -7.0, 3.0));
			// Glare: the LED panel is seen from anywhere in front of it, brightest along its aim.
			float facing = dot(-l, aim);
			float beam = smoothstep(-0.1, 0.3, facing) * (0.3 + 0.7 * smoothstep(0.3, 0.8, facing));
			vec3 h = normalize(l + v);
			float ndh = max(dot(n, h), 0.0);
			float dd = ndh * ndh * (a2 - 1.0) + 1.0;
			float dist = a2 / (CIS_PI * dd * dd);
			float k = (rough + 1.0) * (rough + 1.0) * 0.125;
			float g = (ndl / (ndl * (1.0 - k) + k)) * (ndv / (ndv * (1.0 - k) + k));
			float fres = f0 + (1.0 - f0) * pow(1.0 - max(dot(h, v), 0.0), 5.0);
			sum += lamp_color * (bright * beam * fres * dist * g / (4.0 * ndv + 0.0001) / (d2 + 0.25));
		}
	}
	return sum;
}

// World-space value noise from a tiling texture: three octaves at unrelated scales so the module repeat
// (15 m) and the texture repeat (2 m) never line up.
float cis_macro(sampler2D noise_tex, vec2 w) {
	float n1 = texture(noise_tex, w * (1.0 / 23.0)).r;
	float n2 = texture(noise_tex, w * (1.0 / 7.3) + vec2(0.37, 0.71)).r;
	float n3 = texture(noise_tex, w * (1.0 / 61.0) + vec2(0.13, 0.29)).r;
	return n1 * 0.5 + n2 * 0.25 + n3 * 0.25;
}

// The world plane a surface lies in (floor/ceiling: xz, walls facing x: zy, walls facing z: xy).
vec2 cis_world_plane(vec3 p, vec3 wn) {
	vec3 an = abs(wn);
	if (an.y >= an.x && an.y >= an.z) {
		return p.xz;
	}
	return an.x >= an.z ? p.zy : p.xy;
}
