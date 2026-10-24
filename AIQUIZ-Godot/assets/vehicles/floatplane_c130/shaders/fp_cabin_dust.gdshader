shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 機内の空気のほこり（docs/sudden_death_v2/c130_float.md 第10章）。小さな粒は、後ろの扉から差し込む光の中にあるときだけ光る
// （fp_light_shaft.gdshader と同じ、光の来る向きへさかのぼる決め方）。

uniform mat4 world_to_plane;
uniform vec3 light_dir = vec3(0.1, -0.3, -0.95);
uniform float hinge_z = 4.6;
uniform float half_w = 1.5;
uniform float y_low = 9.0;
uniform float y_high = -9.0;
uniform vec3 light_color : source_color = vec3(1.0, 0.95, 0.86);
uniform float intensity = 0.0;
uniform float base = 0.04;

varying float v_lit;

float lit(vec3 p) {
	vec3 back = -normalize(light_dir);
	float s = (hinge_z - p.z) / max(back.z, 0.05);
	if (s < 0.0) {
		return 0.0;
	}
	vec3 h = p + back * s;
	float ax = 1.0 - smoothstep(half_w - 0.08, half_w + 0.08, abs(h.x));
	float ay = smoothstep(y_low - 0.08, y_low + 0.08, h.y) * (1.0 - smoothstep(y_high - 0.08, y_high + 0.08, h.y));
	return ax * ay;
}

void vertex() {
	// 粒の板をカメラへ向ける（大きさは粒の縮尺のまま）
	float scale = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale, INV_VIEW_MATRIX[1] * scale, INV_VIEW_MATRIX[2] * scale, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vec3 world = MODEL_MATRIX[3].xyz;
	v_lit = lit((world_to_plane * vec4(world, 1.0)).xyz);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float dot_ = exp(-dot(q, q) * 4.0);
	ALBEDO = light_color * dot_ * (base + v_lit) * intensity * COLOR.a;
	ALPHA = 1.0;
}
