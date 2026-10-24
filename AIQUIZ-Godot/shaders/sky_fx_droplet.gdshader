shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled, skip_vertex_transform;

// スカイゲートの風切りの水滴（SkyFallWind の MultiMesh、板 1 枚 = 1 粒）。2 人のまわりを上へ流れる小さな水滴の筋。
// 板はカメラを向き、上（ワールドの +Y、落ちる 2 人に対して空気が流れる向き）へ動いたときの画面の動きの向きに伸ばす。
// 見下ろしでは上へ流れる粒は画面の真ん中から外へ広がるので、速さの線と同じ向きの筋になる。
// INSTANCE_CUSTOM：g＝濃さ、b＝模様のずらし、a＝伸ばす量。

uniform float stretch = 1.0;
uniform float opacity = 1.0;
uniform vec3 drop_color : source_color = vec3(0.88, 0.96, 1.0);

varying float inst_alpha;

void vertex() {
	inst_alpha = INSTANCE_CUSTOM.g;
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// 画面の動き：点 P が速度 V で動くとき、画面の位置 P.xy / -P.z の変化の向き ∝ -V.xy * P.z + P.xy * V.z
	vec2 dir = -up.xy * c.z + c.xy * up.z;
	float len = length(dir);
	vec2 u = len > 1e-4 ? dir / len : vec2(0.0, 1.0);
	vec2 v = vec2(-u.y, u.x);
	float st = 1.0 + stretch * INSTANCE_CUSTOM.a;
	vec2 offs = u * VERTEX.y * size * st + v * VERTEX.x * size;
	VERTEX = c + vec3(offs, 0.0);
	if (inst_alpha < 0.004) {
		VERTEX = vec3(0.0, 0.0, 1.0);
	}
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p * vec2(2.4, 1.0)) * 2.0;
	float a = smoothstep(1.0, 0.0, r);
	ALBEDO = drop_color;
	ALPHA = a * a * inst_alpha * opacity;
}
