shader_type sky;

group_uniforms Sky;
uniform vec4 sky_day : source_color = vec4(0.08, 0.48, 0.98, 1.0);
uniform vec4 horizon_day : source_color = vec4(0.64, 0.88, 1.0, 1.0);
uniform vec4 horizon_sunset : source_color = vec4(1.0, 0.42, 0.16, 1.0);
uniform vec4 sky_sunset : source_color = vec4(0.12, 0.25, 0.60, 1.0);
uniform vec4 horizon_night : source_color = vec4(0.075, 0.15, 0.34, 1.0);
uniform vec4 sky_night : source_color = vec4(0.018, 0.055, 0.16, 1.0);
uniform float day_night_mix : hint_range(-1.0, 1.0, 0.01) = 0.8;
uniform bool use_directional_light = true;
uniform vec3 cycle_sun_direction = vec3(-0.58, 0.58, -0.57);
uniform float horizon_exponent : hint_range(1.0, 12.0, 0.1) = 4.2;
uniform float sunset_amount_exponent : hint_range(0.25, 4.0, 0.05) = 1.15;
uniform float night_amount_exponent : hint_range(0.5, 8.0, 0.1) = 2.2;

group_uniforms Clouds;
uniform sampler2D cloud_tex_01;
uniform sampler2D cloud_tex_02;
uniform vec4 cloud_color : source_color = vec4(0.98, 0.99, 1.0, 1.0);
uniform vec4 cloud_twilight_color : source_color = vec4(1.0, 0.63, 0.67, 1.0);
uniform vec4 cloud_night_color : source_color = vec4(0.36, 0.48, 0.78, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.50, 0.66, 0.86, 1.0);
uniform vec2 cloud_tiling = vec2(1.0, 1.0);
uniform vec2 wind_speed = vec2(0.024, 0.012);
uniform float cloud_density : hint_range(0.05, 1.0, 0.01) = 0.54;
uniform float cloud_depth : hint_range(0.0, 4.0, 0.05) = 0.35;
uniform float cloud_shape_exponent : hint_range(0.05, 4.0, 0.05) = 0.48;
uniform float cloud_occlude_exponent : hint_range(0.25, 6.0, 0.05) = 1.35;

group_uniforms Stars;
uniform sampler2D night_noise_01;
uniform sampler2D night_noise_02;
uniform float star_strength : hint_range(0.0, 3.0, 0.05) = 1.0;

group_uniforms Sun;
uniform float sun_scale : hint_range(0.00025, 0.01, 0.00025) = 0.0005;
uniform float sun_strength : hint_range(0.0, 8.0, 0.05) = 1.75;
uniform vec4 sun_color : source_color = vec4(1.0, 0.84, 0.42, 1.0);

group_uniforms Moon;
uniform float moon_scale : hint_range(0.001, 0.04, 0.0005) = 0.007;
uniform float moon_strength : hint_range(0.0, 4.0, 0.05) = 1.15;
uniform vec4 moon_color : source_color = vec4(0.72, 0.84, 1.0, 1.0);


float remap_cloud(float sample_value) {
	float density = max(cloud_density, 0.001);
	return clamp((sample_value - (1.0 - density)) / density, 0.0, 1.0);
}


void sky() {
	vec3 sun_dir = normalize(cycle_sun_direction);
	float solar_elevation = use_directional_light ? sun_dir.y : day_night_mix;
	float day_amount = smoothstep(-0.16, 0.28, solar_elevation);
	float night_amount = pow(smoothstep(0.04, 0.62, -solar_elevation), night_amount_exponent);
	float twilight_amount = exp(-pow(abs(solar_elevation) / 0.23, 2.0));
	twilight_amount = pow(clamp(twilight_amount, 0.0, 1.0), sunset_amount_exponent);

	vec3 view_flat = vec3(EYEDIR.x, 0.0, EYEDIR.z);
	view_flat /= max(length(view_flat), 0.001);
	vec3 sun_flat = vec3(sun_dir.x, 0.0, sun_dir.z);
	sun_flat /= max(length(sun_flat), 0.001);
	float sunset_facing = pow(max(dot(view_flat, sun_flat), 0.0), 1.6);
	float horizon_mask = pow(1.0 - clamp(abs(EYEDIR.y), 0.0, 1.0), horizon_exponent);
	float sunset_view = twilight_amount * mix(0.28, 1.0, sunset_facing) * horizon_mask;
	vec2 sphere_uv = vec2(
		atan(EYEDIR.z, EYEDIR.x) / TAU + 0.5,
		asin(clamp(EYEDIR.y, -1.0, 1.0)) / PI + 0.5
	);

	vec3 top_color = mix(sky_night.rgb, sky_day.rgb, day_amount);
	top_color = mix(top_color, sky_sunset.rgb, twilight_amount * 0.14);
	vec3 horizon_color = mix(horizon_night.rgb, horizon_day.rgb, day_amount);
	horizon_color = mix(horizon_color, horizon_sunset.rgb, clamp(sunset_view, 0.0, 1.0));
	vec3 sky_color = mix(top_color, horizon_color, horizon_mask);

	if (EYEDIR.y < 0.0) {
		vec3 ground_color = mix(sky_night.rgb * 0.58, horizon_day.rgb * 0.52, day_amount);
		float ground_horizon = smoothstep(-0.85, 0.0, EYEDIR.y);
		sky_color = mix(ground_color, horizon_color, ground_horizon);
	}

	float cloud_value = 0.0;
	float cloud_detail = 0.0;
	if (EYEDIR.y > 0.005) {
		vec2 wind = wind_speed * TIME * 0.08;
		vec2 uv_01 = sphere_uv * vec2(3.4, 1.7) * cloud_tiling + wind;
		vec2 uv_02 = sphere_uv * vec2(6.1, 3.05) * cloud_tiling - wind * 0.54;
		float height_01 = remap_cloud(texture(cloud_tex_01, uv_01).r);
		float height_02 = remap_cloud(texture(cloud_tex_02, uv_02).r);
		vec2 depth_offset = vec2(0.025, 0.012) * height_01 * cloud_depth;
		height_01 = remap_cloud(texture(cloud_tex_01, uv_01 + depth_offset).r);
		height_02 = remap_cloud(texture(cloud_tex_02, uv_02 - depth_offset * 0.7).r);
		cloud_detail = mix(height_02, 1.0, 0.40);
		cloud_value = pow(clamp(height_01 * cloud_detail, 0.0, 1.0), max(cloud_shape_exponent, 0.05));
		cloud_value *= smoothstep(0.02, 0.16, EYEDIR.y);
	}

	vec3 daytime_cloud = mix(cloud_shadow_color.rgb, cloud_color.rgb, 0.70 + cloud_detail * 0.30);
	vec3 lit_cloud = mix(cloud_night_color.rgb, daytime_cloud, day_amount);
	float cloud_twilight = clamp(twilight_amount * (0.18 + sunset_facing * 0.82) * horizon_mask, 0.0, 1.0);
	lit_cloud = mix(lit_cloud, cloud_twilight_color.rgb, cloud_twilight * 0.72);
	sky_color = mix(sky_color, lit_cloud, clamp(cloud_value * 0.92, 0.0, 0.94));

	float star_seed = texture(night_noise_01, sphere_uv * vec2(3.0, 1.5)).r;
	float star_variation = texture(night_noise_02, sphere_uv * vec2(1.7, 1.0)).r;
	// Keep the night sky airy: only the brightest noise peaks become stars.
	// This preserves distinct points without filling every clear patch with them.
	float stars = smoothstep(0.955, 0.995, star_seed) * mix(0.68, 1.0, star_variation);
	stars *= night_amount * smoothstep(0.0, 0.14, EYEDIR.y) * (1.0 - cloud_value * 0.88);
	sky_color += vec3(stars * star_strength);

	float celestial_clear = pow(clamp(1.0 - cloud_value * 0.90, 0.08, 1.0), cloud_occlude_exponent);
	float sun_dot = clamp(dot(EYEDIR, sun_dir), 0.0, 1.0);
	float sun_disc = smoothstep(1.0 - sun_scale, 1.0 - sun_scale * 0.42, sun_dot);
	// Keep the stylized halo compact so the sun reads as a distant disc.
	float sun_glow = pow(sun_dot, 360.0) * 0.12;
	// The sun begins appearing only after its center reaches the horizon.
	// Clip every solar pixel below the horizon so transparent water cannot reveal it.
	float sun_center_visible = smoothstep(0.0, 0.025, solar_elevation);
	float sun_above_horizon = smoothstep(0.0, 0.006, EYEDIR.y);
	sky_color += (
		sun_color.rgb
		* sun_strength
		* (sun_disc + sun_glow)
		* celestial_clear
		* sun_center_visible
		* sun_above_horizon
	);

	vec3 moon_dir = -sun_dir;
	float moon_dot = clamp(dot(EYEDIR, moon_dir), 0.0, 1.0);
	float moon_disc = smoothstep(1.0 - moon_scale, 1.0 - moon_scale * 0.46, moon_dot);
	float moon_halo = pow(moon_dot, 92.0) * 0.18;
	float moon_visible = night_amount * smoothstep(0.01, 0.14, moon_dir.y);
	sky_color += moon_color.rgb * moon_strength * (moon_disc + moon_halo) * celestial_clear * moon_visible;

	COLOR = max(sky_color, vec3(0.0));
}
