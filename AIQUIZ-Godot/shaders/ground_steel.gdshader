shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Steel of the conveyor's side frames and running rails (scripts/world/stage_materials.gd).
// The parts are axis-aligned BoxMeshes (corner vertices only) whose UVs do not fit their size, so
// the textures are projected from world space onto the plane of each face. The parts never move
// along the belt (they only grow or shrink with the course length), so world coordinates keep
// every pattern still. Worn paint along the box edges, section joints and bolt heads are
// procedural: two texture reads per pixel (albedo, ORM), no normal map.
// Textures: assets/environment/underground_temple/textures steel_* (albedo A = paint mask) or
// galv_* (zinc, ORM blue = metal), referenced in place (see conveyor_stage/textures/README.md).

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Colour of the finish (paint or zinc). The texture only modulates it: rgb / tex_mean.
uniform vec4 finish_color : source_color = vec4(0.30, 0.31, 0.33, 1.0);
uniform float tex_mean : hint_range(0.05, 1.0) = 0.69;
// How much of the texture's tone variation shows (1 = as painted, 0 = flat finish colour), and how
// much its ORM blue (metal) varies the metallic finish (0 = not at all).
uniform float tex_contrast : hint_range(0.0, 2.0) = 1.0;
uniform float metal_tex_weight : hint_range(0.0, 1.0) = 1.0;
// Metres per texture tile.
uniform float tex_m : hint_range(0.1, 8.0) = 1.0;
// 1 = painted (albedo A = paint mask): the paint wears off near edges, chips show bare steel.
uniform float paint_mask : hint_range(0.0, 1.0) = 1.0;
uniform vec4 bare_color : source_color = vec4(0.56, 0.57, 0.59, 1.0);
uniform float bare_metallic : hint_range(0.0, 1.0) = 0.9;
uniform float bare_roughness : hint_range(0.0, 1.0) = 0.34;
// Finish metallic = mix(1, orm.b, metal_tex_weight) * finish_metallic + finish_metallic_add;
// roughness = orm.g * roughness_mul + roughness_add.
uniform float finish_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float finish_metallic_add : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_mul : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_add : hint_range(-1.0, 1.0) = 0.0;
// Paint worn along the box edges: width in metres and amount (0 = none).
uniform float edge_width : hint_range(0.0, 0.2) = 0.04;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.0;
// Moves the faces that point along X outward by this many metres (both sides). The side frames'
// outer face lies exactly in the plane of the pier wall; this keeps it from z-fighting.
uniform float push_out_x : hint_range(0.0, 0.05) = 0.0;
// Frame sections along world Z: a joint every section_m and a fresh texture offset per section,
// so the 1 m texture does not repeat along a 160 m frame (0 = one piece).
uniform float section_m : hint_range(0.0, 20.0) = 0.0;
// Polished running band along the middle of the +Y face (rail head, where the saw wheels roll).
uniform float polish_top : hint_range(0.0, 1.0) = 0.0;
uniform float polish_half_width : hint_range(0.0, 0.2) = 0.05;
// Bolt heads every bolt_spacing metres along world Z (0 = none): on the faces pointing along X
// at local y = bolt_rows (bolt_on_top = 0), or on the +Y face at local x = bolt_rows (1).
uniform float bolt_spacing : hint_range(0.0, 4.0) = 0.0;
uniform float bolt_on_top : hint_range(0.0, 1.0) = 0.0;
uniform vec2 bolt_rows = vec2(0.3, -0.3);
uniform float bolt_radius : hint_range(0.005, 0.08) = 0.02;
// Procedural relief (bolt domes, rounded box edges up close): 0 = flat normals (low quality).
uniform float relief : hint_range(0.0, 1.0) = 0.0;
// Dirt from the world noise (darker, rougher), with run-down streaks on the vertical faces.
uniform float grime : hint_range(0.0, 1.0) = 0.3;

varying vec3 v_world;
varying vec3 v_world_n;
varying vec3 v_local;
varying vec3 v_local_n;
varying vec3 v_half;

float st_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float st_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = p - cell;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = st_hash(cell);
	float b = st_hash(cell + vec2(1.0, 0.0));
	float c = st_hash(cell + vec2(0.0, 1.0));
	float d = st_hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	// Every vertex of a BoxMesh sits on a corner, so |VERTEX| is the half size everywhere.
	VERTEX.x += sign(VERTEX.x) * push_out_x;
	v_half = abs(VERTEX);
	v_local = VERTEX;
	v_local_n = NORMAL;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 an = abs(v_local_n);
	vec3 p = v_local;
	vec3 h = v_half;
	// Face plane: a = texture U (metres), b = texture up (metres), and their world directions.
	vec2 ab;
	vec3 t_a;
	vec3 t_b;
	float edge;
	float on_x = 0.0;
	float on_top = 0.0;
	if (an.y >= an.x && an.y >= an.z) {
		ab = vec2(v_world.z, v_world.x);
		t_a = vec3(0.0, 0.0, 1.0);
		t_b = vec3(1.0, 0.0, 0.0);
		edge = min(h.x - abs(p.x), h.z - abs(p.z));
		on_top = step(0.0, v_local_n.y);
	} else if (an.x >= an.z) {
		ab = vec2(v_world.z, v_world.y);
		t_a = vec3(0.0, 0.0, 1.0);
		t_b = vec3(0.0, 1.0, 0.0);
		edge = min(h.y - abs(p.y), h.z - abs(p.z));
		on_x = 1.0;
	} else {
		ab = vec2(v_world.x, v_world.y);
		t_a = vec3(1.0, 0.0, 0.0);
		t_b = vec3(0.0, 1.0, 0.0);
		edge = min(h.x - abs(p.x), h.y - abs(p.y));
	}
	float along_z = 1.0 - an.z;
	float box_edge = edge;

	// Sections along Z: each gets its own texture offset; the joints wear a little like edges.
	vec2 uv_c = vec2(ab.x, -ab.y) / tex_m;
	vec2 uv = uv_c;
	float joint = 0.0;
	float joint_shade = 0.0;
	if (section_m > 0.0) {
		float s = v_world.z / section_m;
		float section = floor(s);
		uv += vec2(st_hash(vec2(section, 3.7)), st_hash(vec2(section, 8.1))) * 7.0;
		float to_joint = abs(fract(s + 0.5) - 0.5) * section_m;
		edge = mix(edge, min(edge, to_joint * 2.5), along_z);
		// A 4 mm gap with a 2 cm shadow beside it, box-filtered by the pixel: once a pixel is wider
		// than the gap, the line gets fainter instead of staying a full-strength pixel-wide line.
		float jw = max(fwidth(v_world.z), 1e-5);
		joint = min(1.0, 0.004 / jw) * (1.0 - smoothstep(0.002, 0.002 + jw, to_joint)) * along_z;
		joint_shade = min(1.0, 0.02 / jw) * (1.0 - smoothstep(0.0, 0.02 + jw, to_joint)) * along_z;
	}
	vec2 gx = dFdx(uv_c);
	vec2 gy = dFdy(uv_c);
	vec4 alb = textureGrad(albedo_tex, uv, gx, gy);
	vec3 orm = textureGrad(orm_tex, uv, gx, gy).rgb;

	float pix = max(fwidth(ab.x), fwidth(ab.y));
	vec3 wn = normalize(v_world_n);

	// ---- Paint and wear ----
	float paint = 1.0;
	// Texels of the texture's own chips (and their blurred mips) are not used as paint colour.
	float texture_paint = mix(1.0, smoothstep(0.85, 0.98, alb.a), paint_mask);
	float near_edge = 1.0 - smoothstep(0.0, edge_width, edge);
	// The worn band along the edges fades out once it is narrower than a couple of pixels (it
	// would only be a flickering bright line by then).
	float wear_amount = edge_wear * smoothstep(1.0, 2.5, edge_width / max(pix, 1e-5));
	if (paint_mask > 0.0 && wear_amount > 0.0 && near_edge > 0.0) {
		near_edge *= near_edge;
		float chip_noise = st_noise(ab * 46.0) * 0.65 + st_noise(ab * 13.0 + 5.0) * 0.35;
		// Fine nicks need a few pixels to show: further away only the broad wear is left.
		chip_noise = mix(0.5, chip_noise, 1.0 - smoothstep(0.004, 0.012, pix));
		float bare = smoothstep(0.63, 0.7, near_edge * wear_amount * 0.95 + chip_noise * 0.42);
		// The texture's own chip shapes only break through close to an edge.
		bare = max(bare, (1.0 - texture_paint) * smoothstep(0.25, 0.7, near_edge * wear_amount));
		paint = 1.0 - bare * paint_mask;
	}
	// Where the texture marks a chip that is kept painted, use plain paint (not its rust colour).
	vec3 finish_mod = mix(vec3(tex_mean), alb.rgb, texture_paint) / tex_mean;
	finish_mod = 1.0 + (finish_mod - 1.0) * tex_contrast;
	vec3 finish = finish_color.rgb * finish_mod;
	float rough_finish = mix(0.54, orm.g, texture_paint) * roughness_mul + roughness_add;
	float metal_finish = mix(1.0, orm.b, metal_tex_weight) * finish_metallic + finish_metallic_add;

	vec3 bare_col = bare_color.rgb;
	if (paint < 1.0) {
		bare_col *= 0.9 + 0.2 * st_noise(ab * 23.0 + 11.0);
	}
	vec3 albedo = mix(bare_col, finish, paint);
	float rough = mix(bare_roughness, rough_finish, paint);
	float metal = mix(bare_metallic, metal_finish, paint);
	float ao = 1.0;

	// ---- Grime: patches, and streaks running down the vertical faces ----
	float patches = smoothstep(0.45, 0.9, st_noise(ab * vec2(0.55, 1.6) + vec2(2.3, 9.1)));
	float runs = smoothstep(0.55, 0.9, st_noise(vec2(ab.x * 7.0, ab.y * 0.7 + 3.0))) * (1.0 - an.y);
	float dirt = clamp(patches * 0.7 + runs * 0.6, 0.0, 1.0) * grime;
	albedo *= 1.0 - 0.28 * dirt;
	rough = mix(rough, max(rough, 0.75), dirt * 0.8);

	// ---- Polished running band (rail head) ----
	if (polish_top > 0.0) {
		float band = (1.0 - smoothstep(polish_half_width * 0.6, polish_half_width, abs(p.x))) * on_top * polish_top;
		float scratch_phase = p.x * 260.0;
		float scratch = mix(0.5, st_noise(vec2(scratch_phase, v_world.z * 0.6)), 1.0 - smoothstep(0.3, 0.8, fwidth(scratch_phase)));
		albedo = mix(albedo, bare_color.rgb * (1.08 + 0.12 * scratch), band);
		rough = mix(rough, 0.16 + 0.1 * scratch, band);
		metal = mix(metal, 1.0, band);
	}

	// ---- Section joints: a thin dark gap in a little shade ----
	albedo *= (1.0 - 0.75 * joint) * (1.0 - 0.12 * joint_shade);
	ao *= 1.0 - 0.5 * max(joint, joint_shade * 0.5);
	rough = mix(rough, 0.8, joint);
	metal *= 1.0 - joint;

	// ---- Bolt heads ----
	vec2 slope = vec2(0.0);
	if (bolt_spacing > 0.0) {
		float face = mix(on_x, on_top, bolt_on_top);
		float across = mix(p.y, p.x, bolt_on_top);
		float cell = v_world.z / bolt_spacing;
		float dz = (fract(cell) - 0.5) * bolt_spacing;
		float d0 = across - bolt_rows.x;
		float d1 = across - bolt_rows.y;
		float dr = abs(d0) < abs(d1) ? d0 : d1;
		vec2 off = vec2(dz, dr);
		float dist = length(off);
		float aa = max(pix, 1e-4);
		// Fades out once a bolt head is only a pixel or two across.
		float visible = face * smoothstep(0.7, 1.6, bolt_radius / aa);
		float head = (1.0 - smoothstep(bolt_radius - aa, bolt_radius + aa, dist)) * visible;
		float washer = (1.0 - smoothstep(bolt_radius * 1.45 - aa, bolt_radius * 1.45 + aa, dist)) * visible;
		float rim = clamp(washer - head, 0.0, 1.0);
		// Painted heads, the paint rubbed thin on the crown; the washer ring sits in shade.
		float crown = 1.0 - smoothstep(0.0, bolt_radius * 0.6, dist);
		albedo = mix(albedo, mix(finish * 1.12, bare_col, 0.2 * crown), head);
		rough = mix(rough, mix(rough_finish * 0.85, bare_roughness, 0.3 * crown), head);
		metal = mix(metal, mix(metal_finish, bare_metallic, 0.25 * crown), head);
		albedo *= 1.0 - 0.3 * rim;
		ao *= 1.0 - 0.5 * rim;
		slope += off / bolt_radius * head * 0.85;
	}

	if (relief > 0.0) {
		vec3 dir_b = mix(t_b, vec3(1.0, 0.0, 0.0), bolt_on_top);
		vec3 tilt = t_a * slope.x + dir_b * slope.y;
		// Fake bevel: the last 8 mm of each face lean toward the edge, so box edges catch the light
		// like rounded steel. Only drawn while it is a few pixels wide: a thinner highlight would
		// break up into dashes along a slanted edge.
		float bevel_w = 0.008;
		float bevel = (1.0 - smoothstep(0.0, bevel_w, box_edge)) * 0.55 * smoothstep(1.5, 3.0, bevel_w / max(pix, 1e-5));
		if (bevel > 0.0) {
			// Direction from the face centre toward its nearest edge, in the face plane (the parts
			// are not rotated, so local axes are world axes).
			vec3 toward = an.y >= an.x && an.y >= an.z
				? (h.x - abs(p.x) < h.z - abs(p.z) ? vec3(sign(p.x), 0.0, 0.0) : vec3(0.0, 0.0, sign(p.z)))
				: (an.x >= an.z
					? (h.y - abs(p.y) < h.z - abs(p.z) ? vec3(0.0, sign(p.y), 0.0) : vec3(0.0, 0.0, sign(p.z)))
					: (h.x - abs(p.x) < h.y - abs(p.y) ? vec3(sign(p.x), 0.0, 0.0) : vec3(0.0, sign(p.y), 0.0)));
			tilt += toward * bevel;
		}
		if (dot(tilt, tilt) > 0.0) {
			vec3 n_world = normalize(wn + tilt * relief);
			NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
		}
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
}
