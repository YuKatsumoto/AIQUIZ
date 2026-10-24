shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_front, specular_schlick_ggx;

// The raw egg fluid's surface (GoalStandEggFluid): a box around the target whose
// back faces cast a ray from the camera through the density field the particles
// were splatted into. Empty blocks are skipped with the coarse field; the first
// crossing of the iso level is refined by bisection, lit with the field's gradient
// as its normal, and written to the depth buffer so the body and the white in front
// of it hide it properly. Thin and thick white are clear and bend the background a
// little; where the yolk dominates it is opaque orange.

uniform sampler3D field_tex : filter_linear, repeat_disable;
uniform sampler3D coarse_tex : filter_nearest, repeat_disable;
uniform vec3 grid_origin = vec3(0.0);
uniform vec3 grid_size = vec3(1.0);
uniform float voxel = 0.016;
uniform float block = 8.0;
uniform float iso = 0.4;
uniform vec4 tint : source_color = vec4(0.97, 0.96, 0.87, 1.0);
uniform vec4 yolk_color : source_color = vec4(1.0, 0.6, 0.06, 1.0);
uniform float refraction = 1.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

const int MAX_STEPS = 220;

vec3 to_uvw(vec3 p) {
	return (p - grid_origin) / grid_size;
}

float density(vec3 p) {
	return texture(field_tex, to_uvw(p)).r;
}

void fragment() {
	vec3 camera = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 back = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dir = normalize(back - camera);
	// Where the ray enters the box (or the camera, when inside it).
	vec3 inv = 1.0 / dir;
	vec3 t_lo = (grid_origin - camera) * inv;
	vec3 t_hi = (grid_origin + grid_size - camera) * inv;
	vec3 t_near = min(t_lo, t_hi);
	vec3 t_far = max(t_lo, t_hi);
	float t = max(max(max(t_near.x, t_near.y), t_near.z), 0.0);
	float t_end = min(min(t_far.x, t_far.y), t_far.z);
	float fine = voxel * 0.6;
	float coarse_step = voxel * block * 0.5;
	bool hit = false;
	float previous = t;
	for (int i = 0; i < MAX_STEPS; i++) {
		if (t > t_end) {
			break;
		}
		vec3 p = camera + dir * t;
		vec3 uvw = to_uvw(p);
		if (texture(coarse_tex, uvw).r < iso * 0.5) {
			previous = t;
			t += coarse_step;
			continue;
		}
		if (density(p) >= iso) {
			hit = true;
			break;
		}
		previous = t;
		t += fine;
	}
	if (!hit) {
		discard;
	}
	// Bisect between the last miss and the hit.
	float a = previous;
	float b = t;
	for (int i = 0; i < 6; i++) {
		float m = 0.5 * (a + b);
		if (density(camera + dir * m) >= iso) {
			b = m;
		} else {
			a = m;
		}
	}
	vec3 p = camera + dir * b;
	float e = voxel;
	vec3 gradient = vec3(
		density(p + vec3(e, 0.0, 0.0)) - density(p - vec3(e, 0.0, 0.0)),
		density(p + vec3(0.0, e, 0.0)) - density(p - vec3(0.0, e, 0.0)),
		density(p + vec3(0.0, 0.0, e)) - density(p - vec3(0.0, 0.0, e)));
	vec3 n_world = length(gradient) > 0.00001 ? -normalize(gradient) : -dir;
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	DEPTH = clip.z / clip.w;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float yolk = clamp(texture(field_tex, to_uvw(p)).g, 0.0, 1.0);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	vec4 view_hit = VIEW_MATRIX * vec4(p, 1.0);
	// A blob is a small lens: what is behind it shows bent by its curvature. The hit
	// lies on this pixel's ray, so SCREEN_UV is where it is on screen.
	vec2 offset = -NORMAL.xy * 0.012 * PROJECTION_MATRIX[1][1] / max(-view_hit.z, 0.1) * refraction;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;
	vec3 clear_albedo = tint.rgb * 0.05;
	vec3 clear_emission = behind * 0.88 * (1.0 - fresnel);
	ALBEDO = mix(clear_albedo, yolk_color.rgb, yolk);
	EMISSION = clear_emission * (1.0 - yolk);
	ROUGHNESS = mix(0.04, 0.2, yolk);
	SPECULAR = 0.6;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.0;
	RIM = 0.25;
	RIM_TINT = 0.85;
	ALPHA = 1.0;
}
