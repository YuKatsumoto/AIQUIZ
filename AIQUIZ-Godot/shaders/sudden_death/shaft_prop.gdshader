shader_type spatial;
// Shaft hardware (rails, galvanized pipes/ladder/tray/conduit, cables, lamp housings, depth
// signs, deck wires). Unshaded: lit by the analytic sodium rows + a wall bounce estimate, so
// rows far from the 12 real lights stay lit. mode: 0 generic, 1 enamel sign face, 2 wire.
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://shaders/sudden_death/shaft_common.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness : hint_range(0.02, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float grime : hint_range(0.0, 1.0) = 0.4;
uniform vec3 grime_color : source_color = vec3(0.16, 0.085, 0.04);
uniform float bounce = 0.35;
uniform int mode = 0;
uniform sampler2D wall_light : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float light_max = 3.17;

varying vec3 v_local;

void vertex() {
	if (mode == 2) {
		// Hoist wire: a faint lateral shimmer that grows with the deck speed.
		float amp = 0.006 * clamp(abs(motion_speed) / 10.0, 0.0, 1.0);
		vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
		VERTEX.x += sin(TIME * 23.0 + world.y * 1.7) * amp / max(length(MODEL_MATRIX[0].xyz), 0.001);
	}
	v_local = shaft_local_point(MODEL_MATRIX, VERTEX);
}

void fragment() {
	if (mode != 2 && shaft_clipped(v_local)) {
		discard;
	}
	if (mode == 2 && v_local.y > clip_top) {
		discard;
	}
	float w = v_local.y - scroll;
	float ang = atan(-v_local.z, v_local.x) * (1.0 / 6.2831853);
	float g1 = texture(macro_noise, vec2(ang * 31.0, w * 0.9)).r;
	float g2 = texture(macro_noise, vec2(ang * 7.0 + 0.4, w * 0.21)).r;
	float dirt = clamp(grime * smoothstep(0.45, 0.85, g1 * 0.7 + g2 * 0.5), 0.0, 1.0);
	vec3 alb = mix(albedo, grime_color, dirt);
	float rough = mix(roughness, 0.85, dirt * 0.7);
	float metal = metallic * (1.0 - dirt * 0.8);
	if (mode == 1) {
		vec2 e = min(UV, 1.0 - UV);
		float border = 1.0 - step(0.03, min(e.x * 2.0, e.y));
		float inner = step(0.05, min(e.x * 2.0, e.y)) * (1.0 - step(0.065, min(e.x * 2.0, e.y)));
		alb = mix(alb, vec3(0.02), max(border, inner));
		alb = mix(alb, vec3(0.40, 0.33, 0.20), smoothstep(0.6, 0.9, g1) * 0.35);
	}
	vec3 n = shaft_local_dir(INV_VIEW_MATRIX, NORMAL);
	vec3 cam = (shaft_inv * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 v = normalize(cam - v_local);
	vec3 f0 = mix(vec3(0.04), alb, metal);
	float diff = 0.0;
	vec3 spec = vec3(0.0);
	vec3 l0 = vec3(0.0, 1.0, 0.0);
	shaft_lamps(v_local, n, v, rough, f0, 1, true, diff, spec, l0);
	float wall_e = shaft_wall_bounce(wall_light, light_max, v_local);
	vec3 lamp = lamp_color * lamp_strength * lamps_on;
	vec3 diffuse_alb = alb * (1.0 - metal);
	// Metals see the lit wall around them: a rough environment term keeps them from going black.
	vec3 env = f0 * wall_e * bounce * 0.9;
	vec3 col = (diffuse_alb * (diff + wall_e * bounce) + spec + env) * lamp;
	float day = shaft_daylight(v_local, n);
	col += (diffuse_alb + f0 * 0.5) * day * daylight_color;
	col += diffuse_alb * shaft_beacons(v_local, n);
	col += diffuse_alb * ambient_floor;
	ALBEDO = col;
}
