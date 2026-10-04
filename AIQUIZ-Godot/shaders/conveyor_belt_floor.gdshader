shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform float scroll_z = 0.0;
uniform float scroll_sign : hint_range(-1.0, 1.0) = 1.0;
uniform float roller_mode : hint_range(0.0, 1.0) = 0.0;
uniform float roller_radius : hint_range(0.05, 2.0) = 0.5;
uniform float roller_contact_z = 0.0;
uniform float roller_arc_sign : hint_range(-1.0, 1.0) = 1.0;
uniform float belt_scale : hint_range(0.05, 1.5) = 0.22;
uniform float stripe_scale : hint_range(2.0, 30.0) = 12.0;
uniform float stripe_softness : hint_range(0.01, 0.5) = 0.08;
uniform float groove_strength : hint_range(0.0, 0.5) = 0.12;
uniform vec4 base_color : source_color = vec4(0.40, 0.41, 0.42, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.34, 0.345, 0.35, 1.0);
uniform vec4 side_color : source_color = vec4(0.33, 0.34, 0.35, 1.0);
uniform vec4 rim_color : source_color = vec4(0.26, 0.265, 0.27, 1.0);
uniform float rim_inner_x : hint_range(6.0, 11.5) = 11.15;
uniform float rim_outer_x : hint_range(10.0, 12.5) = 12.0;
uniform float rim_softness : hint_range(0.02, 0.35) = 0.045;
uniform float rim_lip_width : hint_range(0.02, 0.2) = 0.03;
uniform float roller_freq : hint_range(1.0, 24.0) = 7.5;
uniform float roller_sharpness : hint_range(20.0, 400.0) = 180.0;
uniform float roller_depth : hint_range(0.0, 0.55) = 0.22;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.78;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.12;
uniform float rim_metallic_boost : hint_range(0.0, 0.5) = 0.18;
#ifdef SHAFT_HOLE
// Sudden death shaft (StageEnvironment.set_shaft_hole compiles this variant only while the hole
// is open): (centre x, centre z, radius, active). Every face of the belt, pier box, rollers and
// return belt inside the circle is cut away (the shaft wall shows).
uniform vec4 shaft_hole = vec4(0.0);
#endif

// ---------------------------------------------------------------------------------------------
// Surface detail. StageMaterials.belt_detail() sets these per graphics quality. Everything here
// only MODULATES the procedural belt above: the colours still come from base_color /
// stripe_color / rim_color / side_color, so a re-coloured belt keeps its colour. At the defaults
// (detail_strength = 0, no textures) none of it runs and the belt renders exactly as before; the
// menu and settings previews rely on that (they never call belt_detail).
// ---------------------------------------------------------------------------------------------
// Belt cover (assets/environment/conveyor_stage/textures, README there): grey albedo multiplier
// (linear mean 0.94), OpenGL normal map, ORM = AO / roughness 0.73-0.88 / metal 0.
uniform sampler2D detail_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// 0 = plain procedural belt (old look). 1 = full detail: texture albedo / roughness / AO, belt
// wear and grime, the steel look of the guide band, the contact shadow at the side frames.
uniform float detail_strength : hint_range(0.0, 1.0) = 0.0;
// Belt normal map strength. 0 = the normal map is not sampled at all (low quality).
uniform float normal_strength : hint_range(0.0, 2.0) = 0.0;
// Metres of belt per texture tile (U = across the belt = world X, V = along travel = world Z).
uniform float detail_tile_m : hint_range(1.0, 6.0) = 2.5;
// 1 / linear mean of detail_albedo, so the texture keeps the belt colour's average.
uniform float detail_albedo_gain : hint_range(0.8, 1.3) = 1.064;
// Mean of the ORM green channel: roughness_val stays the average roughness.
uniform float detail_rough_mean : hint_range(0.0, 1.0) = 0.826;
// Inner face of the side frames (|x|), where the belt edge gets its contact shadow.
uniform float frame_inner_x : hint_range(10.0, 12.5) = 11.76;
// Pier walls: concrete albedo as a grey modulation of side_color (0 = untouched).
uniform sampler2D side_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float side_detail : hint_range(0.0, 1.0) = 0.0;
// Linear mean of side_albedo and metres per tile.
uniform float side_albedo_mean : hint_range(0.05, 1.0) = 0.29;
uniform float side_tile_m : hint_range(1.0, 8.0) = 3.75;
// Sea level (the wet band on the pier walls sits just above it).
uniform float water_y = -9.2;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 local_pos;

// Hash without sine (Dave Hoskins): stable on the integer lattice of the value noise below,
// also for the large coordinates of a belt that has scrolled a long way.
float sd_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise, 0..1.
float sd_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = p - cell;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = sd_hash(cell);
	float b = sd_hash(cell + vec2(1.0, 0.0));
	float c = sd_hash(cell + vec2(0.0, 1.0));
	float d = sd_hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
#ifdef SHAFT_HOLE
	if (shaft_hole.w > 0.5) {
		vec2 hole_offset = world_pos.xz - shaft_hole.xy;
		if (dot(hole_offset, hole_offset) < shaft_hole.z * shaft_hole.z) {
			discard;
		}
	}
#endif
	float top_mask = smoothstep(0.55, 0.85, abs(world_normal.y));
	float ax = abs(world_pos.x);

	float belt_v = 0.0;
	float stripe_wave = 0.0;
	float groove_wave = 0.0;
	// Belt coordinates in metres without the scroll (detail layer): across the belt, along travel.
	float across = world_pos.x;
	float travel_rest = world_pos.z;
	if (roller_mode > 0.5) {
		// ローラー: 幅方向は円柱のローカルY軸（回転後はワールドX方向に対応）
		ax = abs(local_pos.y);

		// 円柱のローカル座標から角度を計算し、弧の長さを求めることで巻き付きを表現
		float angle = atan(local_pos.z, local_pos.x);
		float arc_dist = angle * roller_radius;
		float base_v = roller_contact_z + scroll_z * scroll_sign;

		belt_v = (base_v + arc_dist * roller_arc_sign) * belt_scale;
		stripe_wave = sin(belt_v * stripe_scale);
		groove_wave = sin(belt_v * stripe_scale * 2.05);
		top_mask = 1.0;
		// The roller turns local +Y into world -X.
		across = -local_pos.y;
		travel_rest = roller_contact_z + arc_dist * roller_arc_sign;
	} else {
		belt_v = (world_pos.z + scroll_z * scroll_sign) * belt_scale;
		stripe_wave = sin(belt_v * stripe_scale);
		groove_wave = sin(belt_v * stripe_scale * 2.05);
	}

	// Filter the procedural bands by their screen-space footprint. This keeps
	// the moving floor stable at distance instead of producing sub-pixel moire.
	float stripe_phase = belt_v * stripe_scale;
	float stripe_footprint = fwidth(stripe_phase);
	float stripe_edge = max(stripe_softness, fwidth(stripe_wave));
	float stripe = smoothstep(-stripe_edge, stripe_edge, stripe_wave);
	float stripe_visibility = 1.0 - smoothstep(0.55, 1.8, stripe_footprint);
	stripe = mix(0.5, stripe, stripe_visibility);

	float groove_phase = belt_v * stripe_scale * 2.05;
	float groove_footprint = fwidth(groove_phase);
	float groove_visibility = 1.0 - smoothstep(0.4, 1.5, groove_footprint);
	float groove = mix(0.5, 0.5 + 0.5 * groove_wave, groove_visibility);

	vec3 belt_col = mix(base_color.rgb, stripe_color.rgb, stripe);
	belt_col *= mix(1.0 - groove_strength, 1.0, groove);

	float roller_phase = belt_v * roller_freq;
	float fp = fract(roller_phase);
	float roller_distance = min(fp, 1.0 - fp);
	float roller_line = exp(-roller_distance * roller_distance * roller_sharpness);
	float roller_visibility = 1.0 - smoothstep(0.35, 1.1, fwidth(roller_phase));
	roller_line *= roller_visibility;
	belt_col *= mix(1.0 - roller_depth, 1.0, 1.0 - roller_line);

	// 狭いガイドレール帯（色＋内側の影線で立体感）
	float rim_band = 0.0;
	vec3 final_col = belt_col;
	float rim_meta = 0.0;

	rim_band = smoothstep(rim_inner_x - rim_softness, rim_inner_x + rim_softness * 0.35, ax);
	rim_band *= 1.0 - smoothstep(rim_outer_x - rim_softness * 0.4, rim_outer_x + 0.01, ax);
	vec3 with_rim = mix(belt_col, rim_color.rgb, rim_band * top_mask);

	float lip = exp(-pow((ax - rim_inner_x) / rim_lip_width, 2.0)) * top_mask;
	with_rim = mix(with_rim, rim_color.rgb * 0.88, clamp(lip * 0.9, 0.0, 1.0));

	// 外縁の細いハイライト（レール上面の錯覚）
	float outer_edge = smoothstep(rim_outer_x - 0.18, rim_outer_x - 0.02, ax);
	outer_edge *= 1.0 - smoothstep(rim_outer_x - 0.02, rim_outer_x + 0.02, ax);
	with_rim = mix(with_rim, vec3(0.48, 0.49, 0.50), outer_edge * top_mask * 0.35);

	if (roller_mode > 0.5) {
		// ローラー: ベルト模様＋縁のみ（side_colorブレンドなし）
		final_col = with_rim;
	} else {
		// フラットベルト: 上面=ベルト+縁、側面=side_color
		final_col = mix(side_color.rgb, with_rim, top_mask);
	}
	rim_meta = rim_band * top_mask * rim_metallic_boost;

	float rough_out = clamp(roughness_val - rim_meta * 0.25, 0.05, 1.0);
	float metal_out = clamp(metallic_val + rim_meta, 0.0, 1.0);

	if (detail_strength > 0.0) {
		float d = detail_strength;
		if (top_mask > 0.5) {
			// ---- Belt top and rollers: the cover texture moves with the belt ----------------
			float inv_tile = 1.0 / detail_tile_m;
			float scroll_m = scroll_z * scroll_sign;
			// The texture repeats every tile, so only the fractional scroll is added (keeps the
			// coordinates small on long runs). Same phase as belt_v: the weave moves with the stripes.
			vec2 belt_uv = vec2(across, travel_rest) * inv_tile + vec2(0.0, fract(scroll_m * inv_tile));
			vec2 texels = vec2(textureSize(detail_albedo, 0));
			vec2 tdx = dFdx(belt_uv) * texels;
			vec2 tdy = dFdy(belt_uv) * texels;
			// Texels per pixel along the long axis of the pixel footprint.
			float footprint = sqrt(max(dot(tdx, tdx), dot(tdy, tdy)));
			// The weave (8 px threads) is only shown while mip 0-1 resolve it; past that it fades
			// to the texture mean instead of beating against the pixel grid.
			float near_detail = 1.0 - smoothstep(2.5, 9.0, footprint);

			vec3 tex_albedo = texture(detail_albedo, belt_uv).rgb;
			vec3 tex_orm = texture(detail_orm, belt_uv).rgb;

			// Belt coordinates that move with the belt (metres), for the non-repeating wear.
			vec2 belt_m = vec2(across, travel_rest + scroll_m);
			// Large soft grime patches and their finer breakup (no tiling: value noise in world metres).
			float macro_a = sd_noise(belt_m * vec2(0.42, 0.21) + vec2(3.7, 1.3));
			float macro_b = sd_noise(belt_m * vec2(1.35, 0.55) + vec2(11.1, 7.9));
			float macro = macro_a * 0.62 + macro_b * 0.38;
			// How strongly the cover texture shows here: worn-in areas are flatter and cleaner.
			float contrast = mix(0.55, 1.3, smoothstep(0.2, 0.8, macro));

			float tex_mod = dot(tex_albedo, vec3(0.3333)) * detail_albedo_gain;
			float albedo_mod = 1.0 + (tex_mod - 1.0) * contrast * mix(0.55, 1.0, near_detail);
			// Grime: dirt picked up in patches and along travel; it darkens a little and roughens.
			float grime = smoothstep(0.45, 0.9, macro_a) * (0.6 + 0.4 * macro_b);
			albedo_mod *= 1.0 - 0.07 * grime + 0.025 * (macro_b - 0.5);

			// Roughness: the texture's scuffs are smoother (the sun glints off them), grime rougher.
			float rough_belt = rough_out + (tex_orm.g - detail_rough_mean) * 2.2 * contrast + 0.06 * grime - 0.03;
			float ao_belt = 1.0 - (1.0 - tex_orm.r) * 0.5 * mix(0.6, 1.0, near_detail);

			// ---- Guide band (|x| >= rim_inner_x): fixed brushed steel, never scrolls ----------
			vec2 still_m = vec2(across, travel_rest);
			float streak_coarse = sd_noise(vec2(across * 36.0, travel_rest * 0.09));
			float fine_phase = across * 130.0;
			float fine_fade = 1.0 - smoothstep(0.35, 0.9, fwidth(fine_phase));
			float streak_fine = mix(0.5, sd_noise(vec2(fine_phase, travel_rest * 0.45 + 31.0)), fine_fade);
			float streak = streak_coarse * 0.6 + streak_fine * 0.4;
			float rim_grime = smoothstep(0.5, 0.95, sd_noise(still_m * vec2(1.6, 0.28) + vec2(5.3, 2.9)));
			// The belt edge rubs the inner lip bright.
			float rub = exp(-pow((ax - rim_inner_x - 0.045) / 0.022, 2.0));
			float rim_mod = (0.88 + 0.24 * streak) * (1.0 - 0.18 * rim_grime) * (1.0 + 0.35 * rub);
			float rough_rim = clamp(0.36 + 0.22 * (1.0 - streak) + 0.25 * rim_grime - 0.14 * rub, 0.12, 0.9);
			float metal_rim = clamp(metal_out + 0.25 * streak + 0.3 * rub - 0.2 * rim_grime, 0.0, 1.0);

			// Contact shadow where the belt and the rollers meet the side frames.
			float frame_gap = max(frame_inner_x - ax, 0.0);
			float contact = exp(-frame_gap * 14.0);

			float rim_w = rim_band;
			float mod_out = mix(albedo_mod, rim_mod, rim_w) * (1.0 - 0.22 * contact);
			final_col *= mix(1.0, mod_out, d);
			rough_out = clamp(mix(rough_out, mix(rough_belt, rough_rim, rim_w), d), 0.05, 1.0);
			metal_out = mix(metal_out, mix(metal_out, metal_rim, rim_w), d);
			AO = mix(1.0, mix(ao_belt, 1.0, rim_w) * (1.0 - 0.45 * contact), d);
			AO_LIGHT_AFFECT = 0.2 * d;

			if (normal_strength > 0.0) {
				// The meshes have no UVs that match these coordinates, so the tangent frame is built
				// here. Belt top: U = world +X, image up (OpenGL +Y) = world -Z (V runs along +Z).
				vec2 nxy = texture(detail_normal, belt_uv).rg * 2.0 - 1.0;
				nxy *= normal_strength * d * (1.0 - rim_w) * mix(0.35, 1.0, near_detail) * mix(0.75, 1.0, contrast);
				vec3 n_geo = normalize(world_normal);
				vec3 t_u;
				vec3 t_up;
				if (roller_mode > 0.5) {
					// Roller: U along the axis (world X), V along the arc in the direction of the stripes.
					vec3 axis = normalize((MODEL_MATRIX * vec4(0.0, -1.0, 0.0, 0.0)).xyz);
					vec3 arc_dir = normalize((MODEL_MATRIX * vec4(-local_pos.z, 0.0, local_pos.x, 0.0)).xyz);
					t_u = axis;
					t_up = -arc_dir * roller_arc_sign;
					// The end caps keep their plain normal.
					nxy *= 1.0 - smoothstep(0.4, 0.7, abs(dot(n_geo, axis)));
				} else {
					t_u = vec3(1.0, 0.0, 0.0);
					t_up = vec3(0.0, 0.0, -1.0);
				}
				vec3 n_world = normalize(n_geo + t_u * nxy.x + t_up * nxy.y);
				NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
			}
		} else {
			// ---- Pier walls: fixed, side_color modulated by concrete, wet band, streaks -------
			vec3 an = abs(world_normal);
			vec2 plane = an.x >= an.z ? world_pos.zy : world_pos.xy;
			float wall_mod = 1.0;
			if (side_detail > 0.0) {
				vec3 conc = texture(side_albedo, plane / side_tile_m).rgb;
				wall_mod = mix(1.0, dot(conc, vec3(0.3333)) / side_albedo_mean, side_detail);
			}
			// Streaks running down from the deck edge and a darker, glossier wet band above the sea.
			float height = world_pos.y - water_y;
			float streaks = sd_noise(vec2(plane.x * 2.3, world_pos.y * 0.12 + 17.0));
			float drip = smoothstep(0.55, 0.85, streaks) * (1.0 - smoothstep(0.0, 6.5, -(world_pos.y + 1.2)));
			float wave = sd_noise(vec2(plane.x * 0.9, 3.0)) * 0.35 + sd_noise(vec2(plane.x * 3.1, 9.0)) * 0.15;
			float wet = 1.0 - smoothstep(0.15 + wave, 0.55 + wave * 1.4, height);
			wall_mod *= (1.0 - 0.14 * drip) * (1.0 - 0.32 * wet);
			final_col *= mix(1.0, wall_mod, d);
			rough_out = mix(rough_out, clamp(rough_out - 0.38 * wet + 0.06 * drip, 0.05, 1.0), d);
		}
	}

	ALBEDO = final_col;
	ROUGHNESS = rough_out;
	METALLIC = metal_out;
}
