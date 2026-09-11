shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform vec4 light_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform vec4 housing_color : source_color = vec4(0.11, 0.095, 0.065, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 3.2;

varying float fixture_level;

void vertex() {
	fixture_level = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
}

void fragment() {
	ALBEDO = mix(housing_color.rgb, light_color.rgb * 0.82, fixture_level * 0.82);
	ROUGHNESS = mix(0.42, 0.24, fixture_level);
	METALLIC = 0.12;
	EMISSION = light_color.rgb * fixture_level * emission_energy;
}
