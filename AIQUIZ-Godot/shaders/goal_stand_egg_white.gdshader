shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Raw egg white from goal_stand_egg_contents.glb (GSE_White): a unit radial disc
// with its thickness profile along +Y. GoalStandEggs simulates the spreading rim
// per angle and passes the radii here; the vertex stage stretches each vertex
// radially to its angle's rim, thins the sheet as it spreads and bends it around
// the body it landed on.

const int RIM_COUNT = 24;

uniform float rim[24];
// Metres at normalised height 1 (the thick-albumen plateau).
uniform float thickness = 0.03;
// 1 / radius of the surface underneath (0 on the conveyor).
uniform float bend = 0.0;
uniform vec4 tint : source_color = vec4(0.97, 0.96, 0.9, 1.0);

varying float v_fraction;

float rim_at(float angle) {
	float a = angle / TAU;
	a -= floor(a);
	float x = a * float(RIM_COUNT);
	int i0 = int(floor(x)) % RIM_COUNT;
	int i1 = (i0 + 1) % RIM_COUNT;
	float t = fract(x);
	t = t * t * (3.0 - 2.0 * t);
	return mix(rim[i0], rim[i1], t);
}

void vertex() {
	vec2 p = VERTEX.xz;
	v_fraction = length(p);
	float r = rim_at(atan(p.y, p.x));
	vec2 q = p * r;
	VERTEX = vec3(q.x, VERTEX.y * thickness - 0.5 * bend * dot(q, q), q.y);
	// Inverse-transpose of the radial/height scale, then the bend's tilt.
	vec3 n = vec3(NORMAL.x * thickness, NORMAL.y * r, NORMAL.z * thickness);
	n = normalize(n);
	n.xz += bend * q * n.y;
	NORMAL = normalize(n);
}

void fragment() {
	float edge = smoothstep(0.55, 1.0, v_fraction);
	ALBEDO = mix(tint.rgb, tint.rgb * vec3(0.97, 0.96, 0.86), edge);
	ROUGHNESS = 0.07;
	SPECULAR = 0.75;
	RIM = 0.25;
	RIM_TINT = 0.6;
	ALPHA = mix(0.97, 0.74, edge);
}
