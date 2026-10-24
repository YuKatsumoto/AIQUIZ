shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

// スカイゲートの海鳥（SkyFallFlyers の MultiMesh）。体と 2 枚の翼の小さな板。翼の頂点（頂点色 R＝翼の重み 0..1、
// G＝左右 0 / 1）を体の軸のまわりに回して羽ばたく。INSTANCE_CUSTOM：r＝羽ばたきの位相、g＝速さ、b＝滑空（0..1、羽ばたかない）。
// 見下ろしで白く読めるように、上面は白、翼の先は灰色。

uniform vec3 body_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 tip_color : source_color = vec3(0.32, 0.36, 0.42);
uniform vec3 under_color : source_color = vec3(0.78, 0.82, 0.88);

varying float wing;

void vertex() {
	float w = COLOR.r;
	wing = w;
	float flap = sin(TIME * INSTANCE_CUSTOM.g + INSTANCE_CUSTOM.r * 6.2831853);
	float a = mix(flap * 0.55 + 0.12, 0.06, INSTANCE_CUSTOM.b) * w;
	float side = COLOR.g > 0.5 ? 1.0 : -1.0;
	float x = abs(VERTEX.x);
	VERTEX.x = side * x * cos(a);
	VERTEX.y += x * sin(a);
}

void fragment() {
	vec3 c = mix(body_color, tip_color, smoothstep(0.7, 1.0, wing));
	if (!FRONT_FACING) {
		c = mix(under_color, tip_color, smoothstep(0.7, 1.0, wing));
	}
	ALBEDO = c;
}
