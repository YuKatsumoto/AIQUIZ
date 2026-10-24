// スカイゲートの光る枠（SkyGateBoard.set_highlight）。UV.y が帯の幅の向き（0＝外のふち、1＝内のふち）。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform float intensity = 1.0;
uniform float pulse = 0.0;

void fragment() {
	float x = clamp(UV.y, 0.0, 1.0);
	float core = smoothstep(0.0, 0.12, x) * (1.0 - smoothstep(0.62, 1.0, x));
	float line = 1.0 - smoothstep(0.0, 0.1, abs(x - 0.32));
	ALBEDO = mix(color.rgb, vec3(1.0), 0.45 * line * (0.4 + 0.6 * pulse)) * (1.15 + 0.4 * pulse);
	ALPHA = clamp(core * intensity, 0.0, 1.0);
}
