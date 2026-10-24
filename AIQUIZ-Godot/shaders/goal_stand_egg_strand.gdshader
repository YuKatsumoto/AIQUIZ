shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// A thread of thick albumen (GoalStandEggStrand) on GSE_Strand (unit rings along
// +Y at t = 1 - UV.y, the glTF export flipping V). The node sits at the world origin; the thread is a quadratic
// Bezier through world points p0, p1 (control), p2, thicker where it leaves either
// end, and beaded like a string of pearls as it nears the snap. Glossy, a little
// milky and see-through.

instance uniform vec4 p0 = vec4(0.0);  // xyz, radius
instance uniform vec4 p1 = vec4(0.0);  // xyz, beading 0..1
instance uniform vec4 p2 = vec4(0.0);  // xyz, seed
uniform vec4 tint : source_color = vec4(0.96, 0.95, 0.86, 1.0);

vec3 bezier(float t) {
	float u = 1.0 - t;
	return u * u * p0.xyz + 2.0 * u * t * p1.xyz + t * t * p2.xyz;
}

void vertex() {
	float t = clamp(1.0 - UV.y, 0.0, 1.0);
	vec3 centre = bezier(t);
	vec3 tangent = normalize(2.0 * (1.0 - t) * (p1.xyz - p0.xyz) + 2.0 * t * (p2.xyz - p1.xyz) + vec3(0.0, 0.00001, 0.0));
	vec3 reference = abs(tangent.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 side = normalize(cross(tangent, reference));
	vec3 other = cross(tangent, side);
	float span = distance(p0.xyz, p2.xyz);
	float ends = 1.0 + 1.3 * (exp(-t * span / max(p0.w * 4.0, 0.001)) + exp(-(1.0 - t) * span / max(p0.w * 4.0, 0.001)));
	float beads = 1.0 - 0.35 * p1.w + 0.9 * p1.w * pow(max(0.0, sin(t * span / max(p0.w * 6.0, 0.002) * PI + p2.w * 20.0)), 4.0);
	float radius = p0.w * ends * beads;
	vec2 ring = length(VERTEX.xz) > 0.0001 ? normalize(VERTEX.xz) : vec2(0.0);
	vec3 offset = side * ring.x + other * ring.y;
	VERTEX = centre + offset * radius;
	NORMAL = length(ring) > 0.0 ? offset : (t < 0.5 ? -tangent : tangent);
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	// Mostly a glint: the thread is too thin to show much body.
	ALBEDO = tint.rgb * 0.25;
	ALPHA = clamp(0.08 + fresnel * 0.35, 0.0, 1.0);
	ROUGHNESS = 0.05;
	SPECULAR = 0.6;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.0;
	RIM = 0.3;
	RIM_TINT = 0.85;
}
