// 観客船の旗の綱の小旗（SkyGateFlotilla、spectator_boats.glb の Flags）。色は頂点の色（線形）。
// UV.y が付け根 0 → 先 1 で、先ほど風ではためく（旗の面の向きへ揺らす。位置で位相をずらして、旗ごとに違う動きにする）。
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform float flutter = 0.07;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(TIME * 6.5 + world.x * 1.9 + world.z * 1.3) + 0.45 * sin(TIME * 10.7 + world.x * 3.7 - world.z * 2.1);
	VERTEX += NORMAL * wave * flutter * UV.y;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
	BACKLIGHT = COLOR.rgb * 0.45;
}
