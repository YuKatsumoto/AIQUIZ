shader_type spatial;
// 水上機 C-130 の文字（ステンシル・登録記号・注意書き）。textures/fp_decals.png のアトラスをアルファで重ねる。
// 面のすぐ手前（数 mm）に浮かせた板なので、深度は書かず、ほかの半透明より先に描く（render_priority は GDScript で）。
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float ao_light_affect : hint_range(0.0, 1.0) = 0.12;
uniform float opacity : hint_range(0.0, 1.0) = 0.92;

varying float v_ao;

void vertex() {
	v_ao = COLOR.r;
}

void fragment() {
	vec4 c = texture(atlas, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity;
	ROUGHNESS = roughness;
	AO = mix(1.0, clamp(v_ao, 0.0, 1.0), ao_strength);
	AO_LIGHT_AFFECT = ao_light_affect;
}
