shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// The machinery in the conveyor's open side bays (scripts/world/conveyor_machinery.gd): idlers,
// the ends of the two drums, the posts of the side frames and the lining of the bays. One shader
// and one material for all of them; the mesh says what each vertex is:
//   UV2.x     radius in metres the part turns at (0 = fixed). The part turns about an axis along X
//             by -travel / radius: the angle of a roller of that radius that the belt runs over
//             without slipping. A negative radius turns the other way (idlers under the return belt).
//   CUSTOM0   xy = the (y, z) of that axis in the mesh.
//   UV2.y     finish: 0 steel tube with a rubber spiral, 1 frame paint, 2 bright steel,
//             3 dark cast iron (recessed caps, bearing blocks, gearbox), 4 the far wall of a bay,
//             drawn as a window into the conveyor (see the interior uniforms below), 5 safety
//             yellow (chain guard, emergency stop cord), 6 rubber (cables).
//   UV.x      position along a tube (0 = inner end .. 1 = end at the opening), for its bare collar.
//   COLOR.r   1 = inside a bay (darker the further in it lies), 0 = out in the open.
// The first line stays the shader type declaration and the SHAFT_HOLE block follows
// conveyor_belt_floor.gdshader: StageEnvironment compiles the same variant from this file while the
// sudden death shaft is open. It does so by inserting a #define after every occurrence of that
// first line's text, so that text must not appear again in this file (not in a comment either).

// Belt travel in metres (scroll_z * scroll_sign), wrapped by the script to a whole number of turns.
uniform float travel = 0.0;
// 0 = the spiral shows crisp, 1 = the idlers turn too fast to follow: it melts into its average
// tone (as on a fast roller) instead of strobing against the frame rate.
uniform float spin_blur : hint_range(0.0, 1.0) = 0.0;
// The rubber is wound as `spiral_starts` parallel strips (a whole number), each making
// `spiral_turns` turns per metre of tube.
uniform float spiral_starts : hint_range(1.0, 6.0, 1.0) = 3.0;
uniform float spiral_turns : hint_range(0.0, 4.0) = 1.1;
// Share of the tube's surface the rubber spiral covers.
uniform float spiral_cover : hint_range(0.05, 0.95) = 0.36;
uniform vec4 steel_color : source_color = vec4(0.56, 0.58, 0.60, 1.0);
uniform vec4 rubber_color : source_color = vec4(0.07, 0.075, 0.08, 1.0);
uniform vec4 paint_color : source_color = vec4(0.30, 0.31, 0.33, 1.0);
uniform vec4 cast_color : source_color = vec4(0.115, 0.12, 0.13, 1.0);
uniform vec4 accent_color : source_color = vec4(0.86, 0.60, 0.07, 1.0);
// Strength of the unevenness in tone and gloss (worn paint, handled steel). 0 = flat colours.
uniform float wear : hint_range(0.0, 1.0) = 0.5;
uniform vec4 void_color : source_color = vec4(0.03, 0.034, 0.042, 1.0);
// |x| of the bays' opening (the pier's side face) and how far in they reach.
uniform float bay_outer_x = 12.0;
uniform float bay_depth : hint_range(0.05, 4.0) = 0.47;
// The inside of the conveyor, behind the bays' far wall. Nothing is built there (the quiz walls
// reach down through the pier): the wall's fragments trace their view ray against the shapes
// below and are shaded as what it meets, so the wall reads as an opening onto idlers that run on
// under the belt. Everything is in the machinery node's space (y = 0 the belt top, z = 0 the back
// drum's axis); the script sets the numbers from its own constants.
// World position of the machinery node.
uniform vec3 bay_origin = vec3(0.0);
// (z of the first post, unit length, units drawn, z of the front drum or -1 while it is hidden).
uniform vec4 unit_grid = vec4(0.6, 9.6, 0.0, -1.0);
// (axis y, radius) of the carrying idlers, the return idlers and the drums.
uniform vec2 carry_idler = vec2(-0.365, 0.24);
uniform vec2 return_idler = vec2(-1.25, 0.16);
uniform vec2 drum = vec2(-0.48, 0.48);
// y of (deck underside, pier top, return belt top, return belt underside).
uniform vec4 interior_levels = vec4(-0.12, -1.48, -0.99, -1.09);
// Cross beam at every post: (top y, bottom y, half thickness along z).
uniform vec3 cross_beam = vec3(-0.655, -0.775, 0.06);
// Metres into the conveyor over which the daylight from the opening falls to a third.
uniform float interior_reach : hint_range(0.5, 12.0) = 6.0;
#ifdef SHAFT_HOLE
// Sudden death shaft: (centre x, centre z, radius, active). Fragments inside the circle are cut.
uniform vec4 shaft_hole = vec4(0.0);
#endif

varying vec3 v_rest;
varying vec3 v_world;
// Where the wear pattern is looked up: fixed to a turning part, to the world for the rest (the
// lining is one mesh stretched along the course, and every frame unit is the same mesh).
varying vec3 v_wear;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Value noise, 0..1.
float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x00 = mix(hash13(cell), hash13(cell + vec3(1.0, 0.0, 0.0)), f.x);
	float x10 = mix(hash13(cell + vec3(0.0, 1.0, 0.0)), hash13(cell + vec3(1.0, 1.0, 0.0)), f.x);
	float x01 = mix(hash13(cell + vec3(0.0, 0.0, 1.0)), hash13(cell + vec3(1.0, 0.0, 1.0)), f.x);
	float x11 = mix(hash13(cell + vec3(0.0, 1.0, 1.0)), hash13(cell + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

// The helpers below work in the (y, z) plane, written as vec2(y, z): every traced shape runs along
// X. A ray is o + t * d; they return t >= 0, or -1 for a miss.
float hit_circle(vec2 o, vec2 d, vec2 centre, float radius) {
	vec2 oc = o - centre;
	float c = dot(oc, oc) - radius * radius;
	if (c <= 0.0) {
		return 0.0;
	}
	float a = dot(d, d);
	float b = dot(oc, d);
	if (a < 1e-8 || b >= 0.0) {
		return -1.0;
	}
	float disc = b * b - a * c;
	return disc < 0.0 ? -1.0 : (-b - sqrt(disc)) / a;
}

float hit_box(vec2 o, vec2 d, vec2 lo, vec2 hi, out vec2 normal) {
	vec2 sd = vec2(abs(d.x) < 1e-6 ? 1e-6 : d.x, abs(d.y) < 1e-6 ? 1e-6 : d.y);
	vec2 t1 = (lo - o) / sd;
	vec2 t2 = (hi - o) / sd;
	vec2 near = min(t1, t2);
	vec2 far = max(t1, t2);
	float t_near = max(near.x, near.y);
	float t_far = min(far.x, far.y);
	normal = near.x > near.y ? vec2(-sign(sd.x), 0.0) : vec2(0.0, -sign(sd.y));
	if (t_near > t_far || t_far < 0.0) {
		return -1.0;
	}
	return max(t_near, 0.0);
}

// t at which the ray is first between the heights lo and hi, or -1.
float band_entry(vec2 o, vec2 d, float lo, float hi) {
	if (o.x >= lo && o.x <= hi) {
		return 0.0;
	}
	if (abs(d.x) < 1e-6) {
		return -1.0;
	}
	return ((o.x > hi ? hi : lo) - o.x) / d.x;
}

// Index of the first shape of a row (centres at offset + period * k) that a ray can meet once it
// is in the row's band at z. Shapes are far narrower than the period, so the ray meets this one or
// the next one along its way, or none.
float row_first(float z, float offset, float period) {
	return floor((z - offset) / period + 0.5);
}

void vertex() {
	// Position on the part relative to its axis, before it turns: the marks are fixed to the part.
	vec2 axis = CUSTOM0.xy;
	v_rest = vec3(VERTEX.x, VERTEX.yz - axis);
	float radius = UV2.x;
	if (radius != 0.0) {
		float angle = -travel / radius;
		float c = cos(angle);
		float s = sin(angle);
		vec2 arm = v_rest.yz;
		VERTEX.yz = axis + vec2(c * arm.x - s * arm.y, s * arm.x + c * arm.y);
		NORMAL.yz = vec2(c * NORMAL.y - s * NORMAL.z, s * NORMAL.y + c * NORMAL.z);
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wear = radius != 0.0 ? v_rest + vec3(0.0, axis) : v_world;
}

void fragment() {
#ifdef SHAFT_HOLE
	if (shaft_hole.w > 0.5) {
		vec2 hole_offset = v_world.xz - shaft_hole.xy;
		if (dot(hole_offset, hole_offset) < shaft_hole.z * shaft_hole.z) {
			discard;
		}
	}
#endif
	float finish = UV2.y;
	vec3 albedo = paint_color.rgb;
	float rough = 0.6;
	float metal = 0.15;
	// Share left, at what this fragment shows, of the light that comes in through the opening.
	float daylight = 1.0;
	vec3 wear_at = v_wear;
	if (finish > 3.5 && finish < 4.5) {
		// The far wall: a window into the conveyor.
		float side = v_world.x < 0.0 ? -1.0 : 1.0;
		vec3 ray = normalize(v_world - CAMERA_POSITION_WORLD);
		float inward = max(-ray.x * side, 1e-4);
		vec2 o = (v_world - bay_origin).yz;
		vec2 d = ray.yz;
		float best = 1e9;
		// What the ray meets: 1 belt underside, 2 pier top, 3 return belt, 4 idler, 5 drum, 6 beam.
		int kind = 0;
		vec3 normal = vec3(side, 0.0, 0.0);
		vec2 centre = vec2(0.0);
		float spin = 1.0;
		if (d.x > 0.0) {
			best = (interior_levels.x - o.x) / d.x;
			kind = 1;
			normal = vec3(0.0, -1.0, 0.0);
		} else if (d.x < 0.0) {
			best = (interior_levels.y - o.x) / d.x;
			kind = 2;
			normal = vec3(0.0, 1.0, 0.0);
		}
		// Return belt: a slab.
		float belt_t = band_entry(o, d, interior_levels.w, interior_levels.z);
		if (belt_t >= 0.0 && belt_t < best) {
			best = belt_t;
			kind = 3;
			normal = belt_t == 0.0 ? vec3(side, 0.0, 0.0) : vec3(0.0, d.x < 0.0 ? 1.0 : -1.0, 0.0);
		}
		float units = unit_grid.z;
		float heading = d.y >= 0.0 ? 1.0 : -1.0;
		// Carrying idlers (two a unit), return idlers (one a unit, turning the other way).
		for (int row = 0; row < 2; row++) {
			vec2 idler = row == 0 ? carry_idler : return_idler;
			float period = row == 0 ? unit_grid.y * 0.5 : unit_grid.y;
			float offset = unit_grid.x + (row == 0 ? unit_grid.y * 0.25 : unit_grid.y * 0.5);
			float count = row == 0 ? units * 2.0 : units;
			float entry = band_entry(o, d, idler.x - idler.y, idler.x + idler.y);
			if (entry < 0.0 || entry > best) {
				continue;
			}
			float first = row_first(o.y + d.y * entry, offset, period);
			for (int i = 0; i < 2; i++) {
				float k = first + heading * float(i);
				if (k < -0.5 || k > count - 0.5) {
					continue;
				}
				vec2 c = vec2(idler.x, offset + period * k);
				float t = hit_circle(o, d, c, idler.y);
				if (t >= 0.0 && t < best) {
					best = t;
					kind = 4;
					centre = c;
					spin = row == 0 ? idler.y : -idler.y;
				}
			}
		}
		// The drums, with the belt around them.
		for (int end = 0; end < 2; end++) {
			float drum_z = end == 0 ? 0.0 : unit_grid.w;
			if (drum_z < 0.0) {
				continue;
			}
			vec2 c = vec2(drum.x, drum_z);
			float t = hit_circle(o, d, c, drum.y);
			if (t >= 0.0 && t < best) {
				best = t;
				kind = 5;
				centre = c;
			}
		}
		// Cross beams, one at every post.
		float beam_entry = band_entry(o, d, cross_beam.y, cross_beam.x);
		if (beam_entry >= 0.0 && beam_entry < best) {
			float first = row_first(o.y + d.y * beam_entry, unit_grid.x, unit_grid.y);
			for (int i = 0; i < 2; i++) {
				float k = first + heading * float(i);
				if (k < -0.5 || k > units - 0.5) {
					continue;
				}
				float beam_z = unit_grid.x + unit_grid.y * k;
				vec2 beam_normal;
				float t = hit_box(o, d, vec2(cross_beam.y, beam_z - cross_beam.z), vec2(cross_beam.x, beam_z + cross_beam.z), beam_normal);
				if (t >= 0.0 && t < best) {
					best = t;
					kind = 6;
					normal = t == 0.0 ? vec3(side, 0.0, 0.0) : vec3(0.0, beam_normal);
				}
			}
		}
		vec2 hit = o + d * best;
		float depth = best * inward;
		if (kind == 4 || kind == 5) {
			vec2 radial = normalize(hit - centre);
			normal = best == 0.0 ? vec3(side, 0.0, 0.0) : vec3(0.0, radial);
			albedo = rubber_color.rgb;
			rough = 0.88;
			metal = 0.0;
			if (kind == 4) {
				// The same spiral as on the idlers' real ends, carried on behind the wall.
				float around = atan(radial.y, radial.x) + travel / spin;
				float wave = cos(spiral_starts * around - TAU * spiral_turns * depth);
				float threshold = cos(PI * spiral_cover);
				float aa = clamp(fwidth(wave), 1e-4, 1.0);
				float rubber = mix(smoothstep(threshold - aa, threshold + aa, wave), spiral_cover, spin_blur);
				albedo = mix(steel_color.rgb, rubber_color.rgb, rubber);
				rough = mix(0.42, 0.88, rubber);
				metal = mix(0.8, 0.0, rubber);
			}
		} else if (kind == 1 || kind == 3) {
			albedo = kind == 1 ? paint_color.rgb * 0.6 : rubber_color.rgb * 1.6;
			rough = 0.9;
			metal = 0.0;
		} else if (kind == 2) {
			albedo = paint_color.rgb;
			rough = 0.85;
			metal = 0.0;
		}
		daylight = 1.0 / (1.0 + 2.0 * depth / interior_reach) * 1.25;
		// The far side of the conveyor is out of reach: the view ends in the dark.
		float lost = kind == 0 ? 1.0 : smoothstep(0.55, 1.0, depth / (bay_outer_x - bay_depth));
		albedo = mix(albedo, void_color.rgb, lost);
		metal *= min(daylight, 1.0) * (1.0 - lost);
		wear_at = vec3(depth, hit) * (1.0 - lost);
		NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
	} else if (finish < 0.5) {
		// Spiral: cos(starts * angle around the tube + turns along it). The cosine has no seam where
		// atan wraps because `spiral_starts` is whole. The rubber is where it exceeds the threshold
		// for its cover.
		float around = atan(v_rest.z, v_rest.y);
		float along = abs(v_rest.x) - (bay_outer_x - bay_depth);
		float wave = cos(spiral_starts * around + TAU * spiral_turns * along);
		float threshold = cos(PI * spiral_cover);
		float aa = max(fwidth(wave), 1e-4);
		float rubber = smoothstep(threshold - aa, threshold + aa, wave);
		rubber = mix(rubber, spiral_cover, spin_blur);
		// A machined collar at the outer end of the tube stays bare.
		rubber *= 1.0 - smoothstep(0.86, 0.9, UV.x);
		albedo = mix(steel_color.rgb, rubber_color.rgb, rubber);
		rough = mix(0.42, 0.88, rubber);
		metal = mix(0.8, 0.0, rubber);
	} else if (finish < 1.5) {
		albedo = paint_color.rgb;
	} else if (finish < 2.5) {
		albedo = steel_color.rgb;
		rough = 0.36;
		metal = 0.8;
	} else if (finish < 3.5) {
		albedo = cast_color.rgb;
		rough = 0.72;
		metal = 0.35;
	} else if (finish < 5.5) {
		albedo = accent_color.rgb;
		rough = 0.5;
		metal = 0.0;
	} else {
		albedo = rubber_color.rgb;
		rough = 0.9;
		metal = 0.0;
	}
	if (wear > 0.0) {
		// Two sizes of blotches: tone and gloss wander a little, as on paint that has been outdoors.
		float blotch = mix(value_noise(wear_at * 3.1), value_noise(wear_at * 17.0), 0.35);
		albedo *= 1.0 + (blotch - 0.5) * 0.32 * wear;
		rough = clamp(rough + (blotch - 0.5) * 0.3 * wear, 0.05, 1.0);
	}
	// A bay is a recess under the belt: less sky reaches the parts further in.
	float inward = clamp((bay_outer_x - abs(v_world.x)) / bay_depth, 0.0, 1.0);
	float occlusion = 1.0 - 0.6 * smoothstep(0.0, 1.0, inward) * COLOR.r;
	ALBEDO = albedo * mix(1.0, occlusion, 0.6) * daylight;
	ROUGHNESS = rough;
	METALLIC = metal;
	AO = occlusion * min(daylight, 1.0);
	AO_LIGHT_AFFECT = mix(0.9, 0.4, min(daylight, 1.0)) * COLOR.r;
}
