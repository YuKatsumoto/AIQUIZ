shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

// UV.x selects a body material; UV.y marks the upper body.
// UV2.x marks an animated arm, UV2.y stores its shoulder's horizontal offset.
vec3 rotate_z(vec3 point, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec3(c * point.x - s * point.y, s * point.x + c * point.y, point.z);
}

void vertex() {
	float phase = INSTANCE_CUSTOM.x * TAU;
	float clock = TIME * (1.3 + INSTANCE_CUSTOM.y * 0.8) + phase;
	if (UV2.x > 0.5) {
		vec3 shoulder = vec3(UV2.y, 0.46, 0.0);
		float wave = sin(clock * 1.7) * 0.12;
		VERTEX = shoulder + rotate_z(VERTEX - shoulder, wave);
		NORMAL = rotate_z(NORMAL, wave);
	}
	if (UV.y > 0.5) {
		VERTEX.y = 0.1 + (VERTEX.y - 0.1) * INSTANCE_CUSTOM.w;
		float sway = sin(clock) * 0.022;
		VERTEX = vec3(0.0, 0.1, 0.0) + rotate_z(VERTEX - vec3(0.0, 0.1, 0.0), sway);
		NORMAL = rotate_z(NORMAL, sway);
	}
	float skin = floor(INSTANCE_CUSTOM.z * 5.0);
	vec3 skin_color = vec3(0.82, 0.55, 0.34);
	if (skin < 0.5) { skin_color = vec3(0.96, 0.74, 0.55); }
	else if (skin < 1.5) { skin_color = vec3(0.64, 0.36, 0.21); }
	else if (skin < 2.5) { skin_color = vec3(0.91, 0.64, 0.43); }
	else if (skin < 3.5) { skin_color = vec3(0.40, 0.21, 0.13); }
	float hair = fract(INSTANCE_CUSTOM.z * 17.0);
	vec3 hair_color = vec3(0.07, 0.045, 0.035);
	if (hair < 0.25) { hair_color = vec3(0.25, 0.11, 0.045); }
	else if (hair < 0.48) { hair_color = vec3(0.71, 0.43, 0.14); }
	else if (hair < 0.63) { hair_color = vec3(0.56, 0.57, 0.59); }
	if (UV.x > 0.5 && UV.x < 1.5) { COLOR.rgb = skin_color; }
	else if (UV.x < 2.5 && UV.x > 1.5) { COLOR.rgb = hair_color; }
	else if (UV.x < 3.5 && UV.x > 2.5) { COLOR.rgb = mix(vec3(0.055, 0.095, 0.16), vec3(0.24, 0.29, 0.36), hair); }
	else if (UV.x < 4.5 && UV.x > 3.5) { COLOR.rgb = vec3(0.12, 0.14, 0.18); }
	else if (UV.x > 4.5) { COLOR.rgb = vec3(0.025, 0.02, 0.018); }
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
}
