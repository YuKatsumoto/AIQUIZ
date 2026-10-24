shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Raw egg yolk on GSE_Yolk (a unit UV sphere, goal_stand_egg_contents.glb), shaped
// and moved by GoalStandEggContents from GoalStandEggSplat's yolk state.
// Shape: a sessile drop (broad flat contact, height over width 0.58 at rest) whose
// axial mode flattens and rebounds it, a lateral mode that stretches it along the
// throw, a lean toward downhill that turns it pendant on a wall, and a sac that
// tears and slumps flat as the yolk runs out.
// Look: the vitelline membrane is a thin wet skin over the orange yolk: a sharp
// clear-coat highlight, light shining through at the rim (backlight), paler at
// grazing angles, the pale germinal disc on top, and fine radial wrinkles that only
// show while the sac is squashed or emptying. Where it tore the bare yolk shows,
// duller and darker, with a pale lip.

// (flatten, stretch, stretch axis angle, deflate)
instance uniform vec4 shape = vec4(0.0);
// (lean x, lean y in the splat plane, tear 0..1 or -1, tear angle)
instance uniform vec4 lean = vec4(0.0, 0.0, -1.0, 0.0);
// (seed, fade, -, -)
instance uniform vec4 look = vec4(0.0);
uniform vec4 yolk_color : source_color = vec4(1.0, 0.58, 0.05, 1.0);
uniform vec4 base_color : source_color = vec4(0.93, 0.4, 0.02, 1.0);
uniform vec4 disc_color : source_color = vec4(1.0, 0.93, 0.72, 1.0);

// A sphere's volume as a half-ellipsoid dome on a flat base of this width and
// height (radii): 2/3 pi W^2 H = 4/3 pi with H / 2W = 0.58.
const float REST_WIDTH = 1.2;
const float REST_HEIGHT = 1.39;

varying vec3 v_sphere;
varying float v_height;
varying float v_wrinkle;

vec3 deform(vec3 p) {
	float flatten = shape.x;
	float deflate = shape.w;
	float axial = max(1.0 + flatten, 0.15);
	// An emptied sac crumples into a small, low skin rather than spreading out.
	float h = REST_HEIGHT * axial * (1.0 - 0.85 * deflate) * (1.0 - look.y);
	float w = REST_WIDTH / sqrt(axial) * (1.0 - 0.5 * deflate) * (1.0 + 0.25 * look.y);
	float yn = clamp(p.y, -1.0, 1.0);
	vec2 dir = length(p.xz) > 0.00001 ? normalize(p.xz) : vec2(1.0, 0.0);
	float radial = sqrt(max(0.0, 1.0 - yn * yn));
	// The upper half is the dome; the lower half folds flat into its contact disc.
	float t = max(yn, 0.0);
	vec2 xz = dir * radial * w;
	// A crumpled skin has a ragged outline.
	if (deflate > 0.0) {
		float azimuth = atan(dir.y, dir.x);
		float ragged = 0.22 * sin(azimuth * 5.0 + look.x * 31.0) + 0.12 * sin(azimuth * 11.0 - look.x * 17.0) + 0.06 * sin(azimuth * 23.0);
		xz *= 1.0 + deflate * ragged;
	}
	// Lateral mode along the throw.
	vec2 axis = vec2(cos(shape.z), sin(shape.z));
	vec2 side = vec2(-axis.y, axis.x);
	float stretch = clamp(shape.y, -0.6, 0.8);
	xz = axis * dot(xz, axis) * (1.0 + stretch) + side * dot(xz, side) / (1.0 + stretch);
	// Lean downhill: the top drifts over and the downhill flank bulges (pendant drop).
	vec2 sag = lean.xy;
	float sag_amount = length(sag);
	if (sag_amount > 0.0001) {
		vec2 down = sag / sag_amount;
		xz += sag * w * (0.3 + 0.9 * t);
		xz += down * max(0.0, dot(dir, down)) * sag_amount * w * 0.9 * (1.0 - 0.5 * t);
	}
	return vec3(xz.x, h * t, xz.y);
}

void vertex() {
	vec3 p = normalize(VERTEX);
	vec3 a = abs(p.y) < 0.99 ? normalize(cross(p, vec3(0.0, 1.0, 0.0))) : vec3(1.0, 0.0, 0.0);
	vec3 b = normalize(cross(p, a));
	float e = 0.01;
	vec3 centre = deform(p);
	vec3 n = normalize(cross(deform(normalize(p + b * e)) - deform(normalize(p - b * e)), deform(normalize(p + a * e)) - deform(normalize(p - a * e))));
	vec3 middle = vec3(0.0, deform(vec3(0.0, 1.0, 0.0)).y * 0.3, 0.0);
	if (p.y < 0.0) {
		n = vec3(0.0, -1.0, 0.0);
	} else if (dot(n, centre - middle) < 0.0) {
		n = -n;
	}
	VERTEX = centre;
	NORMAL = n;
	v_sphere = p;
	v_height = max(p.y, 0.0);
	float squeeze = clamp(-shape.x * 3.5, 0.0, 1.0) * 0.6 + shape.w * 0.9;
	v_wrinkle = squeeze;
}

void fragment() {
	vec3 p = v_sphere;
	float seed = look.x;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	// Lighter and yellower on the crown where the yolk is thickest under a thin
	// membrane, deeper orange toward the base, with a soft mottling underneath.
	vec2 grid = p.xz * 9.0 + seed * 9.0;
	vec2 cell = floor(grid);
	vec2 f = fract(grid);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float h00 = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float h10 = fract(sin(dot(cell + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453);
	float h01 = fract(sin(dot(cell + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	float h11 = fract(sin(dot(cell + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	float mottle = mix(mix(h00, h10, u.x), mix(h01, h11, u.x), u.y);
	vec3 albedo = mix(base_color.rgb, yolk_color.rgb, smoothstep(0.0, 0.45, v_height));
	albedo = mix(albedo, vec3(1.0, 0.72, 0.12), smoothstep(0.6, 1.0, v_height) * 0.35);
	albedo *= 0.94 + 0.06 * mottle;
	// The germinal disc: a small pale spot near the top.
	float az = seed * TAU;
	vec3 disc_dir = normalize(vec3(cos(az) * 0.45, 0.88, sin(az) * 0.45));
	float along = dot(p, disc_dir);
	float disc = smoothstep(0.986, 0.992, along);
	float halo = smoothstep(0.97, 0.982, along) * (1.0 - smoothstep(0.982, 0.99, along));
	albedo = mix(albedo, disc_color.rgb, disc * 0.85 + halo * 0.25);
	// Paler membrane at grazing angles.
	albedo = mix(albedo, vec3(1.0, 0.82, 0.48), fresnel * 0.35);
	// Fine radial wrinkles of a squashed or emptying sac.
	if (v_wrinkle > 0.01) {
		float azimuth = atan(p.z, p.x);
		// Fine, uneven creases, strongest round the bulging flank of the sac.
		float folds = sin(azimuth * 37.0 + sin(azimuth * 7.0 + seed * 20.0) * 3.0 + sin(azimuth * 13.0 - seed * 11.0) * 1.5 + p.y * 9.0);
		float band = smoothstep(0.0, 0.15, v_height) * (1.0 - smoothstep(0.35, 0.7, v_height));
		vec3 tangent = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(-sin(azimuth), 0.0, cos(azimuth), 0.0)).xyz);
		NORMAL = normalize(NORMAL + tangent * folds * v_wrinkle * 0.07 * band);
	}
	// The tear: an irregular opening on the downhill side where the bare yolk
	// shows, wet and a shade deeper, with a pale rim of torn membrane.
	float torn = 0.0;
	float lip = 0.0;
	if (lean.z >= 0.0) {
		float azimuth = atan(p.z, p.x);
		float off = abs(mod(azimuth - lean.w + PI, TAU) - PI);
		float ragged = 0.12 * sin(azimuth * 9.0 + seed * 31.0) + 0.06 * sin(azimuth * 23.0 - seed * 17.0) + 0.1 * (v_height - 0.5);
		float reach = (0.22 + 0.5 * lean.z) + ragged;
		float opening = reach - off;
		torn = smoothstep(0.0, 0.06, opening) * smoothstep(0.05, 0.2, v_height);
		lip = (1.0 - smoothstep(0.0, 0.07, abs(opening))) * smoothstep(0.05, 0.2, v_height) * lean.z;
	}
	ALBEDO = mix(albedo, albedo * vec3(0.97, 0.88, 0.75), torn);
	ALBEDO = mix(ALBEDO, vec3(1.0, 0.86, 0.6), lip * 0.6);
	// The emptied membrane is a pale, dull yellow skin.
	ALBEDO = mix(ALBEDO, vec3(1.0, 0.88, 0.55), shape.w * 0.6);
	ROUGHNESS = 0.16 + disc * 0.2 + torn * 0.06 + shape.w * 0.25;
	SPECULAR = 0.35;
	CLEARCOAT = 0.55 * (1.0 - torn);
	CLEARCOAT_ROUGHNESS = 0.06 + v_wrinkle * 0.05;
	BACKLIGHT = vec3(1.0, 0.42, 0.04) * 0.35;
	RIM = 0.15;
	RIM_TINT = 0.5;
	EMISSION = vec3(1.0, 0.75, 0.4) * lip * 0.03;
}
