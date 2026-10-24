// A drop of raw egg on GSE_Drip (unit rings along -Y at t = 1 - UV.y, the glTF export
// flipping V): hanging off an edge
// (GoalStandEggDrip: a meniscus at the edge, a thread that thins as it stretches, the
// pendant drop) or falling free (just the drop, wobbling). Each ring's radius is the
// smooth union of the three; the normal follows the profile. Thin and thick albumen
// are clear (thick a touch milkier), yolk is opaque orange.

instance uniform vec4 shape = vec4(0.0, 0.0, 0.01, 0.0); // thread length, thread radius, drop radius, base radius
instance uniform vec4 look = vec4(0.0, 0.0, 1.0, 0.0);   // kind (0 thin, 1 thick, 2 yolk), wobble, alpha, seed
uniform vec4 tint : source_color = vec4(0.97, 0.96, 0.87, 1.0);
uniform vec4 yolk_color : source_color = vec4(1.0, 0.6, 0.06, 1.0);
uniform float refraction = 0.04;
#ifdef EGG_REFRACT
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
#endif

varying float v_kind;

float smax(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return max(a, b) + h * h * h * k / 6.0;
}

float profile(float s) {
	float thread = shape.x;
	float rb = shape.z;
	float base_len = max(thread * 0.35, rb * 0.6);
	float base = shape.w * pow(1.0 - smoothstep(0.0, base_len, s), 2.0);
	float centre = thread + rb;
	float bulb = sqrt(max(0.0, rb * rb - (s - centre) * (s - centre)));
	float string = s < centre ? shape.y : 0.0;
	float k = max(rb * 0.5, 0.002);
	return smax(smax(base, string, k * 0.5), bulb, k);
}

void vertex() {
	float total = shape.x + 2.0 * shape.z;
	float t = 1.0 - UV.y;
	float s = t * total;
	vec2 ring = length(VERTEX.xz) > 0.0001 ? normalize(VERTEX.xz) : vec2(0.0);
	float r = profile(s);
	float e = total * 0.01 + 0.0001;
	float slope = (profile(s + e) - profile(s - e)) / (2.0 * e);
	vec3 pos = vec3(ring.x * r, -s, ring.y * r);
	vec3 n = length(ring) > 0.0 ? normalize(vec3(ring.x, slope, ring.y)) : vec3(0.0, t < 0.5 ? 1.0 : -1.0, 0.0);
	// A free drop wobbles about its centre (volume kept).
	float wobble = look.y;
	if (abs(wobble) > 0.0001) {
		float centre = shape.x + shape.z;
		float stretch = 1.0 + wobble;
		pos.y = -centre + (pos.y + centre) * stretch;
		pos.xz /= sqrt(stretch);
	}
	VERTEX = pos;
	NORMAL = n;
	v_kind = look.x;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	if (v_kind > 1.5) {
		ALBEDO = yolk_color.rgb;
		ROUGHNESS = 0.2;
		SPECULAR = 0.5;
		CLEARCOAT = 0.8;
		CLEARCOAT_ROUGHNESS = 0.04;
		BACKLIGHT = vec3(1.0, 0.42, 0.04) * 0.3;
		ALPHA = look.z;
	} else {
		float milk = v_kind > 0.5 ? 0.18 : 0.04;
#ifdef EGG_REFRACT
		// A drop is a lens: the background shows through it bent and flipped.
		vec2 offset = -NORMAL.xy * shape.z * 2.0 * 0.35 * PROJECTION_MATRIX[1][1] * 0.5 / max(-VERTEX.z, 0.05) * 3.0;
		vec3 behind = textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;
		ALBEDO = tint.rgb * milk;
		EMISSION = behind * 0.88 * (1.0 - milk) * (1.0 - fresnel);
		ALPHA = look.z;
#else
		ALBEDO = tint.rgb * (0.6 + milk);
		ALPHA = clamp(0.35 + milk + fresnel * 0.5, 0.0, 1.0) * look.z;
#endif
		ROUGHNESS = 0.04;
		SPECULAR = 0.6;
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.0;
		RIM = 0.3;
		RIM_TINT = 0.85;
	}
}
