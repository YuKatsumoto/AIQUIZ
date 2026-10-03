shader_type spatial;
// The flood behind its front (docs/sudden_death_underground.md 6.6): 1.2 m of fast, murky water over the whole
// hall. Refraction of what is under it (screen texture, bent by the flow normals), absorption by depth (the
// floor 1.2 m down is barely seen, a pillar foot just under the surface shows), flow-aligned normals and foam
// streaks in world space (the water runs downstream, +Z), more foam toward the front, contact foam where the
// water wraps around pillars and gates. Reflections come from the hall's reflection probes (Godot's SSR does
// not apply to transparent surfaces); high quality adds a short screen-space reflection march.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D water_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 murk_color : source_color = vec3(0.085, 0.076, 0.058);
uniform vec3 foam_color : source_color = vec3(0.74, 0.77, 0.76);
// Per metre of water: almost opaque at the 1.2 m depth of the flood.
uniform float absorption = 3.2;
uniform float refraction = 0.035;
// World z of the front (foam builds up toward it), the flow speed (m/s) and the game clock (s).
uniform float front_z = 0.0;
uniform float flow_speed = 7.0;
uniform float clock = 0.0;
// 1 near the front, fading over this many metres behind it.
uniform float front_foam_length = 22.0;
uniform float base_foam = 0.14;
uniform float normal_strength = 0.75;
// The flood's fan out of the tunnel (see flood_front.gdshader).
uniform float tunnel_z = -30.0;
uniform float travelled = 100.0;
// Screen-space reflection march (0 = probes only).
uniform int ssr_steps = 0;
uniform float ssr_strength = 0.6;

varying vec3 v_world;

float fan_half(float z) {
	return 5.0 + 40.0 * smoothstep(0.0, 22.0, (z - tunnel_z) + 0.8 * travelled);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Standing waves of the fast flow (small: the plane is coarse).
	float k = v_world.z - clock * flow_speed * 0.6;
	VERTEX.y += 0.05 * sin(k * 0.9 + v_world.x * 0.35) + 0.035 * sin(k * 1.7 - v_world.x * 0.8);
	v_world.y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

float scene_linear_depth(vec2 uv, mat4 inv_projection) {
	float d = texture(depth_tex, uv).r;
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 flow = vec2(0.0, -clock * flow_speed);
	vec2 w = v_world.xz;
	float edge_noise = texture(foam_tex, w * 0.07 + flow * 0.05).g;
	if (abs(v_world.x) > fan_half(v_world.z) + (edge_noise - 0.5) * 3.0) {
		discard;
	}
	vec2 n1 = texture(water_normal, (w + flow) * 0.11).xy * 2.0 - 1.0;
	vec2 n2 = texture(water_normal, (w * vec2(1.0, 0.55) + flow * 1.3) * 0.27 + vec2(0.3, 0.6)).xy * 2.0 - 1.0;
	vec2 nxy = (n1 * 0.6 + n2 * 0.4) * normal_strength;
	vec3 nts = normalize(vec3(nxy, 1.0));
	NORMAL_MAP = nts * 0.5 + 0.5;

	// Foam: streaks running with the flow, thicker toward the front.
	float near_front = 1.0 - smoothstep(0.0, front_foam_length, front_z - v_world.z);
	float streak = texture(foam_tex, (w * vec2(0.6, 0.12) + flow * vec2(0.6, 0.12)) * 0.25).b;
	float lace = texture(foam_tex, (w + flow * 1.05) * 0.18).r;
	float cover = clamp(base_foam + 0.75 * near_front, 0.0, 1.0);
	float foam = smoothstep(1.0 - cover, 1.0 - cover + 0.3, lace * 0.6 + streak * 0.55);

	// Refraction with depth absorption.
	float surface_depth = -VERTEX.z;
	vec2 offset = nxy * refraction;
	vec2 ruv = SCREEN_UV + offset;
	float floor_depth = scene_linear_depth(ruv, INV_PROJECTION_MATRIX);
	if (floor_depth < surface_depth) {
		ruv = SCREEN_UV;
		floor_depth = scene_linear_depth(ruv, INV_PROJECTION_MATRIX);
	}
	float thickness = max(floor_depth - surface_depth, 0.0);
	// Along the view ray; the water column under the surface is about a third of it at grazing angles.
	vec3 view_dir = normalize(-VERTEX);
	float water_depth = thickness * clamp(abs(dot(view_dir, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz)), 0.2, 1.0);
	float transmit = exp(-absorption * water_depth);
	vec3 below = textureLod(screen_tex, ruv, 0.0).rgb;
	// Contact foam where the water wraps a pillar or a gate post (something solid just under the surface).
	float contact = 1.0 - smoothstep(0.05, 0.45, water_depth);
	foam = max(foam, contact * 0.8 * (0.4 + 0.6 * lace));

	vec3 reflected = vec3(0.0);
	if (ssr_steps > 0) {
		vec3 n_view = normalize(TANGENT * nts.x + BINORMAL * nts.y + NORMAL * nts.z);
		vec3 r = reflect(-view_dir, n_view);
		vec3 p = VERTEX;
		float hit = 0.0;
		for (int i = 0; i < 24; i++) {
			if (i >= ssr_steps) {
				break;
			}
			p += r * (0.35 + float(i) * 0.25);
			vec4 clip = PROJECTION_MATRIX * vec4(p, 1.0);
			vec2 suv = clip.xy / clip.w * 0.5 + 0.5;
			if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
				break;
			}
			float scene = scene_linear_depth(suv, INV_PROJECTION_MATRIX);
			if (-p.z > scene + 0.05 && -p.z < scene + 2.0) {
				float edge = smoothstep(0.0, 0.12, min(min(suv.x, 1.0 - suv.x), min(suv.y, 1.0 - suv.y)));
				reflected = textureLod(screen_tex, suv, 0.0).rgb * edge;
				hit = edge;
				break;
			}
		}
		float fres = 0.02 + 0.98 * pow(1.0 - max(dot(view_dir, n_view), 0.0), 5.0);
		reflected *= fres * ssr_strength * (1.0 - foam);
	}

	ALBEDO = mix(murk_color * (1.0 - transmit), foam_color, foam);
	EMISSION = below * transmit * (1.0 - foam) + reflected;
	ROUGHNESS = mix(0.05, 0.55, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
