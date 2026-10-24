shader_type spatial;
// GOSTRIDER の光の輪・光の殻・魂の尾（加算）。頂点色の a で端を消す。
// fresnel_power > 0 のときは、縁ほど明るい殻になる（球の光の波紋）。
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float fresnel_power = 0.0;
uniform float opacity = 1.0;

void fragment() {
	float edge = 1.0;
	if (fresnel_power > 0.0) {
		edge = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), fresnel_power);
	}
	float a = clamp(COLOR.a * color.a * opacity * edge, 0.0, 1.0);
	ALBEDO = COLOR.rgb * color.rgb * energy;
	ALPHA = a;
}
