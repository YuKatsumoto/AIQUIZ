// A rivulet running down from a raw egg splat, on GSE_Ribbon (UV.x along, UV.y
// across; glTF flips V, so across is 1 - 2 UV.y to keep the strip facing up). GoalStandEggSplat simulates it; this bends the strip along its path in
// the splat plane (start, angle, length from the data texture, with a slight
// meander), gives it a parabolic cross-section that is thin along the wet trail and
// swells into a rounded head at the front, and wraps it over the surface like the
// splat itself. A yolk stream (seed >= 2) is opaque orange.

#include "res://shaders/goal_stand_egg_common.gdshaderinc"

instance uniform int row = 0;
instance uniform int index = 0;
uniform vec4 tint : source_color = vec4(0.97, 0.96, 0.87, 1.0);
uniform vec4 yolk_color : source_color = vec4(1.0, 0.6, 0.06, 1.0);
uniform float refraction = 0.05;
#ifdef EGG_REFRACT
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
#endif

const float LIFT = 0.0024;

varying float v_cross;
varying float v_along;
varying float v_front;
varying float v_height;
varying float v_yolk;
varying float v_alpha;

void vertex() {
	EggSplat s = egg_load(row);
	vec4 a0 = egg_texel(row, EGG_HEADER + 5 + index * 2);
	vec4 a1 = egg_texel(row, EGG_HEADER + 6 + index * 2);
	vec2 start = a0.xy;
	float length_run = a0.w;
	float width = max(a1.x, 0.001);
	float seed = fract(a1.w);
	v_yolk = a1.w >= 2.0 ? 1.0 : 0.0;
	v_alpha = s.alpha;
	if (length_run < 0.003 || s.alpha <= 0.0) {
		VERTEX = vec3(0.0);
	} else {
		float cap = width * 0.6;
		float a = UV.x * (length_run + cap);
		vec2 dir = vec2(cos(a0.z), sin(a0.z));
		vec2 perp = vec2(-dir.y, dir.x);
		float along = min(a, length_run);
		// Yolk is viscous: it runs straighter than the watery white.
		float wander = v_yolk > 0.5 ? 0.35 : 1.0;
		float meander = width * wander * (0.35 * sin(along * 9.0 + seed * 31.0) * smoothstep(0.0, 0.06, along)
			+ 0.18 * sin(along * 23.0 + seed * 7.0) * smoothstep(0.0, 0.1, along));
		vec2 centre = start + dir * a + perp * meander;
		// Narrow along the trail, swelling into the head, rounded at the front, and
		// flaring where it leaves the splat.
		float head_zone = smoothstep(length_run - 2.5 * width, length_run - 0.2 * width, a);
		float front = a > length_run ? sqrt(max(0.0, 1.0 - pow((a - length_run) / cap, 2.0))) : 1.0;
		float flare = 1.0 + 0.7 * (1.0 - smoothstep(0.0, width * 2.0, a));
		if (v_yolk > 0.5) {
			// A broad smear where the sac sat, narrowing into the stream, which itself
			// thins along its trail.
			flare = 1.0 + 1.6 * (1.0 - smoothstep(0.0, width * 3.5, a));
			flare *= mix(1.0, 0.75, smoothstep(0.0, length_run, a)) * (1.0 + 0.12 * sin(a * 31.0 + seed * 13.0));
			// A round end where it begins, under where the sac sat.
			float begin = 1.0 - min(a / (width * 1.4), 1.0);
			flare *= sqrt(max(0.0, 1.0 - begin * begin));
		}
		float w = width * mix(0.7, 1.15, head_zone) * front * flare;
		float c = 1.0 - 2.0 * UV.y;
		vec2 q = centre + perp * c * w * 0.5;
		float peak = mix(a1.z, max(a1.y, a1.z), head_zone) * max(front, 0.35);
		// A viscous stream has a flatter top; the watery one is a round bead.
		float section = v_yolk > 0.5 ? 1.0 - pow(abs(c), 3.0) : 1.0 - c * c;
		float h = peak * section + s.film * (1.0 - smoothstep(0.0, width * 1.5, a)) + LIFT;
		vec3 pos;
		vec3 fold;
		egg_wrap(s, q, h, pos, fold);
		VERTEX = pos;
		// Cross-section slope: the sides lean out.
		float slope = 2.0 * peak * c / max(w * 0.5, 0.001);
		NORMAL = egg_tilt(normalize(vec3(perp.x * slope, 1.0, perp.y * slope)), fold);
		v_cross = c;
		v_along = a / max(length_run, 0.001);
		v_front = front;
		v_height = peak;
	}
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = egg_fresnel(facing);
	float edge = (1.0 - smoothstep(0.8, 1.0, abs(v_cross))) * smoothstep(0.0, 0.25, v_front);
	if (v_yolk > 0.5) {
		// Deep orange where it runs thick, a thin pale yellow wash at its edges and
		// along the trail, where the surface shows through.
		float thin = smoothstep(0.35, 1.0, abs(v_cross)) * 0.7 + smoothstep(0.3, 1.0, v_along) * 0.25 * (1.0 - abs(v_cross));
		ALBEDO = mix(yolk_color.rgb * vec3(1.0, 0.9, 0.8), vec3(1.0, 0.86, 0.42), thin);
		ROUGHNESS = 0.18;
		SPECULAR = 0.5;
		CLEARCOAT = 0.7;
		CLEARCOAT_ROUGHNESS = 0.06;
		ALPHA = (1.0 - smoothstep(0.55, 1.0, abs(v_cross)) * 0.85) * smoothstep(0.0, 0.25, v_front) * mix(1.0, 0.75, thin) * v_alpha;
	} else {
#ifdef EGG_REFRACT
		vec2 offset = egg_refraction(NORMAL, v_height, -VERTEX.z, PROJECTION_MATRIX[1][1]) * refraction / 0.05;
		vec3 behind = textureLod(screen_tex, SCREEN_UV - offset, 0.0).rgb;
		ALBEDO = tint.rgb * 0.05;
		EMISSION = behind * 0.86 * (1.0 - fresnel);
		ALPHA = edge * v_alpha;
#else
		ALBEDO = tint.rgb * 0.6;
		ALPHA = clamp(0.3 + fresnel * 0.5, 0.0, 1.0) * edge * v_alpha;
#endif
		ROUGHNESS = 0.05;
		SPECULAR = 0.6;
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.0;
		RIM = 0.25;
		RIM_TINT = 0.85;
	}
}
