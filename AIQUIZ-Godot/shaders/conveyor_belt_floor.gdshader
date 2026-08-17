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
uniform vec4 edge_light_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform float edge_light_sequence_time = -1.0;
uniform float edge_light_spacing : hint_range(1.0, 16.0) = 10.0;
uniform float edge_light_phase = 2.0;
uniform float edge_light_side_x : hint_range(8.0, 12.5) = 11.86;
uniform float edge_light_pool_intensity : hint_range(0.0, 4.0) = 0.24;
uniform int edge_light_station_count = 0;
uniform float edge_light_front_is_last : hint_range(0.0, 1.0) = 1.0;
uniform float edge_light_station_delay : hint_range(0.05, 1.0) = 0.22;
uniform float edge_light_side_delay : hint_range(0.0, 0.2) = 0.055;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 local_pos;

float fluorescent_start_level(float local_time, float variant) {
	float t = local_time;
	float preheat_time = 0.065 + variant * 0.014;
	if (t < preheat_time) { return 0.025; }
	t -= preheat_time;
	if (t < 0.038) { return 1.0; }
	t -= 0.038;
	float first_extinction = 0.052 + variant * 0.012;
	if (t < first_extinction) { return 0.0; }
	t -= first_extinction;
	if (t < 0.028) { return 0.62; }
	t -= 0.028;
	if (t < 0.045) { return 0.0; }
	t -= 0.045;
	float chatter_time = 0.155 + variant * 0.032;
	if (t < chatter_time) {
		float chatter_step = floor(t / 0.032);
		return mod(chatter_step, 2.0) < 0.5 ? 0.88 : 0.06;
	}
	t -= chatter_time;
	if (variant >= 2.0 && t < 0.050) { return 0.0; }
	if (variant >= 2.0) { t -= 0.050; }
	if (t < 0.060) { return 0.72; }
	return 1.0;
}

float fixture_level(float station_index, float side_index) {
	if (edge_light_sequence_time < 0.0 || edge_light_station_count <= 0) {
		return 0.0;
	}
	float station_order = mix(
		station_index,
		float(edge_light_station_count - 1) - station_index,
		edge_light_front_is_last
	);
	float local_time = edge_light_sequence_time
		- station_order * edge_light_station_delay
		- side_index * edge_light_side_delay;
	if (local_time < 0.0) { return 0.0; }
	float marker_index = station_index * 2.0 + side_index;
	float flicker_pattern = mod(marker_index * 37.0 + 17.0, 13.0);
	if (flicker_pattern >= 2.0) { return 1.0; }
	float variant = mod(marker_index * 13.0 + 5.0, 4.0);
	return fluorescent_start_level(local_time, variant);
}

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float top_mask = smoothstep(0.55, 0.85, abs(world_normal.y));
	float ax = abs(world_pos.x);

	float belt_v = 0.0;
	float stripe_wave = 0.0;
	float groove_wave = 0.0;
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

	float edge_pool = 0.0;
	if (roller_mode < 0.5 && edge_light_sequence_time >= 0.0) {
		float safe_spacing = max(edge_light_spacing, 0.001);
		float station_cycle = (local_pos.z - edge_light_phase) / safe_spacing;
		float station_index = floor(station_cycle + 0.5);
		float station_distance = abs(fract(station_cycle + 0.5) - 0.5) * safe_spacing;
		// Recess the pool slightly onto the belt and use two soft lobes. This
		// avoids the flat, overexposed flashlight-cone shape at grazing angles.
		float inward_distance = edge_light_side_x - abs(local_pos.x);
		float belt_side_mask = smoothstep(-0.04, 0.16, inward_distance);
		float pool_core = exp(-pow((inward_distance - 0.16) / 0.36, 2.0));
		float pool_halo = exp(-pow((inward_distance - 0.28) / 0.62, 2.0));
		float edge_falloff = mix(pool_halo, pool_core, 0.38) * belt_side_mask;
		float station_falloff = exp(-pow(station_distance / 0.72, 2.0));
		float side_index = step(0.0, local_pos.x);
		float light_level = 0.0;
		if (station_index >= 0.0 && station_index < float(edge_light_station_count)) {
			light_level = fixture_level(station_index, side_index);
		}
		edge_pool = edge_falloff * station_falloff * top_mask * light_level;
		final_col += edge_light_color.rgb * edge_pool * 0.025;
	}

	ALBEDO = final_col;
	ROUGHNESS = clamp(roughness_val - rim_meta * 0.25, 0.05, 1.0);
	METALLIC = clamp(metallic_val + rim_meta, 0.0, 1.0);
	EMISSION = edge_light_color.rgb * edge_pool * edge_light_pool_intensity;
}
