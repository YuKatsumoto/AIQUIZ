shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// 水上機の水しぶきの粒（SuddenDeathFloatplane の GPUParticles3D の描く板）。粒の向き（ParticleProcessMaterial の
// particle_flag_align_y で Y ＝ 飛ぶ向き）に沿って細長く伸ばし、カメラのほうへ向ける。飛び出した直後は細い筋、
// 広がると霧（粒の大きさは scale_curve で大きくなる）。色と濃さは粒の COLOR（color_ramp）。

uniform sampler2D blob : source_color, filter_linear_mipmap;
// 飛ぶ向きへの伸び（1 で丸）。
uniform float stretch = 2.0;
uniform vec4 tint : source_color = vec4(0.97, 0.985, 1.0, 1.0);

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 along = MODEL_MATRIX[1].xyz;
	float size_y = length(along);
	float size_x = length(MODEL_MATRIX[0].xyz);
	vec3 axis = along / max(size_y, 0.0001);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = cross(axis, to_cam);
	float side_len = length(side);
	if (side_len < 0.08) {
		// カメラの方へまっすぐ飛ぶ粒は丸く
		side = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam) + vec3(0.0001));
		axis = cross(to_cam, side);
		size_y = size_x;
	} else {
		side /= side_len;
	}
	float grow = mix(1.0, stretch, clamp(side_len * 1.4, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side * size_x, 0.0), vec4(axis * size_y * grow, 0.0), vec4(to_cam * size_x, 0.0), vec4(center, 1.0));
}

void fragment() {
	vec4 tex = texture(blob, UV);
	ALBEDO = tint.rgb * COLOR.rgb;
	ALPHA = clamp(tex.a * COLOR.a * tint.a, 0.0, 1.0);
}
