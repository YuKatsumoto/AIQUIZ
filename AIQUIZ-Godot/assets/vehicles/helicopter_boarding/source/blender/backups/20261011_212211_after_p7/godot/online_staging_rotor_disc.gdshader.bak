shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// 速く回るローターの代わりの円盤（OnlineHeliportHelicopter）。メインローターと、尾のフェネストロンのファンで使う。
// 羽根 blade_count 枚の残像（向きに沿って薄くなる縞）、先の帯（白、または赤・白・赤）、まん中の黒いハブ（hub_radius = 0 で描かない）。
// spin は羽根の角度（ラジアン）。既定の値は、羽根 2 枚・白い先・黒いハブの今までの見た目と同じ。

uniform float spin = 0.0;
uniform float r_max = 5.3;
uniform float blade_count = 2.0;
uniform float root_radius = 0.424;     // ここから外に羽根の残像
uniform float root_ramp = 0.424;
uniform float hub_radius = 0.424;      // 0 でハブを描かない（ハブの形が見えているとき）
uniform float trail_length = 5.0;
uniform float tip_amount = 1.0;        // 白い先の帯
uniform float hazard_amount = 0.0;     // 赤・白・赤の先の帯
uniform vec4 tip_bands = vec4(4.70, 4.88, 5.06, 5.30);   // 赤の始まり、白の始まり、赤の始まり、先（m）
uniform vec3 blade_color : source_color = vec3(0.13, 0.15, 0.18);
uniform vec3 tip_color : source_color = vec3(0.95, 0.95, 0.93);
uniform vec3 hazard_color : source_color = vec3(0.86, 0.20, 0.16);
uniform float strength : hint_range(0.0, 1.0) = 0.42;

varying vec2 v_xz;

void vertex() {
	v_xz = VERTEX.xz;
}

void fragment() {
	float rm = length(v_xz);
	if (rm > r_max) {
		discard;
	}
	float r = rm / r_max;
	float a = atan(v_xz.y, v_xz.x) - spin;
	// 羽根の角度に近いほど濃く、後ろへ尾を引く
	float lag = fract(a * blade_count / 6.28318531);
	float trail = exp(-lag * trail_length) + exp(-(1.0 - lag) * 26.0) * 0.6;
	float body = smoothstep(root_radius, root_radius + root_ramp, rm) * (1.0 - smoothstep(0.96, 1.0, r));
	float tip = tip_amount * smoothstep(0.86, 0.9, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float e = 0.03;
	float red = hazard_amount * (smoothstep(tip_bands.x - e, tip_bands.x + e, rm) * (1.0 - smoothstep(tip_bands.y - e, tip_bands.y + e, rm))
			+ smoothstep(tip_bands.z - e, tip_bands.z + e, rm) * (1.0 - smoothstep(r_max - 0.12, r_max, rm)));
	float white = hazard_amount * smoothstep(tip_bands.y - e, tip_bands.y + e, rm) * (1.0 - smoothstep(tip_bands.z - e, tip_bands.z + e, rm));
	float hub = hub_radius > 0.0 ? 1.0 - smoothstep(hub_radius * 0.75, hub_radius, rm) : 0.0;
	vec3 col = mix(mix(blade_color, tip_color, max(tip, white)), hazard_color, red);
	ALBEDO = mix(col, vec3(0.08, 0.09, 0.1), hub);
	ALPHA = clamp((0.10 + 0.55 * trail) * strength * body + (tip + red + white) * 0.35 * strength + hub * 0.95, 0.0, 1.0);
}
