shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

// UV.x selects a body material; UV.y marks the upper body.
// UV2.x: 1 = raised arm, 2 = resting arm. UV2.y = shoulder X.
// INSTANCE_CUSTOM.y >= 2 marks occasional dancers, with speed in its fraction.
vec3 rotate_z(vec3 point, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec3(c * point.x - s * point.y, s * point.x + c * point.y, point.z);
}

vec3 rotate_x(vec3 point, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec3(point.x, c * point.y - s * point.z, s * point.y + c * point.z);
}

void vertex() {
	float phase = INSTANCE_CUSTOM.x * TAU;
	float speed = fract(INSTANCE_CUSTOM.y);
	float clock = TIME * (1.3 + speed * 0.8) + phase;
	// Independent rests, smooth starts/stops, and a new random emote each cycle.
	float period = 18.0 + speed * 10.0;
	float local_time = TIME + INSTANCE_CUSTOM.x * period;
	float cycle = floor(local_time / period);
	float beat_time = mod(local_time, period);
	float dance = step(2.0, INSTANCE_CUSTOM.y) * smoothstep(0.0, 1.0, beat_time)
		* (1.0 - smoothstep(8.0, 10.0, beat_time));
	float emote = floor(fract(sin(cycle * 12.9898 + phase * 7.31) * 43758.5453) * 4.0);
	float beat = clock * 3.0;
	if (UV2.x > 0.5) {
		vec3 shoulder = vec3(UV2.y, 0.46, 0.0);
		float side = sign(UV2.y);
		float wave = UV2.x < 1.5 ? sin(clock * 1.7) * 0.12 : 0.0;
		float arm_z = 0.0;
		float arm_x = 0.0;
		if (emote < 0.5) { // Alternating fist pumps.
			arm_z = side * (1.15 + sin(beat + side * 1.57) * 0.45);
		} else if (emote < 1.5) { // Side-to-side two-hand dance.
			arm_z = side * 1.65 + sin(beat * 0.65) * 0.45;
		} else if (emote < 2.5) { // Forward hand/clap rhythm.
			arm_z = side * (0.3 + sin(beat) * 0.3);
			arm_x = -1.1 + cos(beat) * 0.25;
		} else { // Alternating shoulder groove.
			arm_z = side * 0.6 + sin(beat + side * 1.57) * 0.45;
			arm_x = sin(beat + side * 1.57) * 0.5;
		}
		// Raised-pose arms already point upward, so lower them toward the same dance.
		if (UV2.x < 1.5) { arm_z -= side * 2.5; }
		float angle = mix(wave, arm_z, dance);
		VERTEX = shoulder + rotate_x(rotate_z(VERTEX - shoulder, angle), arm_x * dance);
		NORMAL = rotate_x(rotate_z(NORMAL, angle), arm_x * dance);
	}
	if (UV.y > 0.5) {
		VERTEX.y = 0.1 + (VERTEX.y - 0.1) * INSTANCE_CUSTOM.w;
		float sway = mix(sin(clock) * 0.022, sin(beat * 0.5) * 0.13, dance);
		VERTEX = vec3(0.0, 0.1, 0.0) + rotate_z(VERTEX - vec3(0.0, 0.1, 0.0), sway);
		VERTEX.y += dance * (0.035 + sin(beat * 2.0) * 0.035);
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
	else if (UV.x > 6.5) { COLOR.rgb = vec3(1.0, 0.68, 0.12); }
	else if (UV.x > 5.5) { COLOR.rgb = mix(COLOR.brg, vec3(0.12, 0.3, 0.6), 0.25); }
	else if (UV.x > 4.5) { COLOR.rgb = vec3(0.025, 0.02, 0.018); }
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
}
