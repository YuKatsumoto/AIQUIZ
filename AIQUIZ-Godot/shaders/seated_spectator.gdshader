shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Seated goal-stand spectators for the side terraces (SeatedSpectatorKit).
// Every vertex follows exactly one bone: UV2.x is the bone, UV2.y the bit mask
// of hairstyles that own the triangle. bone_texture holds one baked frame per
// row, three texels (rows of a 3x4 matrix) per bone. UV.x is the palette role
// as in goal_stand_spectator.gdshader.
//
// Per instance:
//   COLOR.rgb          shirt (sRGB)
//   INSTANCE_CUSTOM.x  phase 0..1
//   INSTANCE_CUSTOM.y  look  = hairstyle + 7*skin + 42*hair colour + 252*pants + 1260*shoes
//   INSTANCE_CUSTOM.z  habit = idle clip + 8*role (0 calm, 1 fan, 2 dancer) + 32*team (0, 1 P1, 2 P2)
//   INSTANCE_CUSTOM.w  animation speed
uniform sampler2D bone_texture : filter_nearest, repeat_disable;
uniform vec4 clips[16];              // start row, frames, fps, seconds
uniform int idle_clip_count = 5;
uniform int active_clip_count = 5;
uniform int dance_clip_count = 4;
// Share of burst cycles in which a spectator actually moves.
uniform float burst_chance_fan = 0.22;
uniform float burst_chance_calm = 0.12;
uniform float burst_chance_dancer = 0.3;
uniform vec4 skins[8];
uniform vec4 hair_colors[8];
uniform vec4 pants_colors[8];
uniform vec4 shoe_colors[8];
uniform vec4 team_colors[3];
// 0..1 crowd reaction driven by the game (goal, verdict): fans of hype_team
// cheer, fans of the other player despair (verdict only), the rest clap.
// hype_team 0 (a draw) makes everyone cheer.
uniform float hype = 0.0;
uniform int hype_team = 0;
uniform bool hype_verdict = false;
// Beyond this view distance a spectator steps through its baked 20 fps frames
// instead of blending neighbours: half the bone fetches, invisible that far off.
uniform float smooth_distance = 40.0;

varying vec3 v_skin;
varying vec3 v_shirt;
varying vec3 v_pants;
varying vec3 v_hair;
varying vec3 v_shoes;
varying vec3 v_accent;

const vec3 DARK = vec3(0.045, 0.045, 0.06);
const vec3 WHITE = vec3(0.95, 0.95, 0.93);
const vec3 BLUSH = vec3(0.96, 0.55, 0.55);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float hash(float a, float b) {
	return fract(sin(a * 12.9898 + b * 78.233) * 43758.5453);
}

// Rows of the bone matrix for one clip at one time, blended between frames
// (or the current frame alone when `blend` is off).
void bone_rows(int clip, float time, int bone, bool blend, out vec4 r0, out vec4 r1, out vec4 r2) {
	vec4 c = clips[clip];
	float frames = max(c.y, 1.0);
	float f = mod(time * c.z, frames);
	float f0 = floor(f);
	float a = f - f0;
	int row0 = int(c.x + f0);
	int x = bone * 3;
	r0 = texelFetch(bone_texture, ivec2(x, row0), 0);
	r1 = texelFetch(bone_texture, ivec2(x + 1, row0), 0);
	r2 = texelFetch(bone_texture, ivec2(x + 2, row0), 0);
	if (blend) {
		int row1 = int(c.x + mod(f0 + 1.0, frames));
		r0 = mix(r0, texelFetch(bone_texture, ivec2(x, row1), 0), a);
		r1 = mix(r1, texelFetch(bone_texture, ivec2(x + 1, row1), 0), a);
		r2 = mix(r2, texelFetch(bone_texture, ivec2(x + 2, row1), 0), a);
	}
}

void pose(int clip, float time, int bone, bool blend, vec3 point, vec3 normal, out vec3 out_point, out vec3 out_normal) {
	vec4 r0;
	vec4 r1;
	vec4 r2;
	bone_rows(clip, time, bone, blend, r0, r1, r2);
	vec4 p = vec4(point, 1.0);
	out_point = vec3(dot(r0, p), dot(r1, p), dot(r2, p));
	out_normal = vec3(dot(r0.xyz, normal), dot(r1.xyz, normal), dot(r2.xyz, normal));
}

void vertex() {
	int look = int(INSTANCE_CUSTOM.y + 0.5);
	int style = look % 7;
	int habit = int(INSTANCE_CUSTOM.z + 0.5);
	int idle = habit % 8;
	int role = (habit / 8) % 4;
	int team = habit / 32;
	int mask = int(UV2.y + 0.5);
	int bone = int(UV2.x + 0.5);
	float phase = INSTANCE_CUSTOM.x;
	float t = TIME * INSTANCE_CUSTOM.w + phase * 97.0;
	vec3 point = vec3(0.0);
	vec3 normal = vec3(0.0, 1.0, 0.0);
	// Hairstyles this spectator does not wear collapse to a point, so their
	// vertices (about 40% of the merged body) skip the skinning below.
	if (((mask >> style) & 1) != 0) {
		bool blend = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz) < smooth_distance;

		// Everyone sits quietly; now and then somebody moves: a fan cheers, claps or
		// waves, a party person dances, a calm spectator chats or checks the phone.
		// Only some cycles have a burst, so at any moment few people are moving.
		float period = 22.0 + 22.0 * fract(phase * 7.13);
		float cycle = floor(t / period);
		float local_time = t - cycle * period;
		float roll = hash(cycle, phase * 31.0);
		float chance = role == 2 ? burst_chance_dancer : (role == 1 ? burst_chance_fan : burst_chance_calm);
		float active = step(hash(cycle + 17.0, phase * 53.0), chance);
		int burst = 1 + int(roll * float(idle_clip_count - 1)) % (idle_clip_count - 1);
		float burst_length = 4.5;
		if (role == 1) {
			burst = idle_clip_count + int(roll * float(active_clip_count)) % active_clip_count;
			burst_length = 2.5 + 2.0 * fract(roll * 13.0);
		} else if (role == 2) {
			burst = idle_clip_count + active_clip_count + int(roll * float(dance_clip_count)) % dance_clip_count;
			burst_length = 10.0;
		}
		float weight = active * smoothstep(0.0, 0.5, local_time) * (1.0 - smoothstep(burst_length - 0.5, burst_length, local_time));
		float burst_time = local_time;
		// Game reactions override the schedule.
		if (hype > 0.001) {
			burst = idle_clip_count; // Clap
			if (hype_team == 0 || team == hype_team) {
				burst = idle_clip_count + 1; // Cheer
			} else if (hype_verdict && team != 0) {
				burst = idle_clip_count + active_clip_count + dance_clip_count; // Despair
			}
			weight = hype;
			burst_time = t;
		}

		vec3 idle_point;
		vec3 idle_normal;
		pose(idle, t, bone, blend, VERTEX, NORMAL, idle_point, idle_normal);
		point = idle_point;
		normal = idle_normal;
		if (weight > 0.001) {
			vec3 burst_point;
			vec3 burst_normal;
			pose(burst, burst_time, bone, blend, VERTEX, NORMAL, burst_point, burst_normal);
			point = mix(idle_point, burst_point, weight);
			normal = mix(idle_normal, burst_normal, weight);
		}
	}
	VERTEX = point;
	NORMAL = normalize(normal);

	v_skin = to_linear(skins[(look / 7) % 6].rgb);
	v_hair = to_linear(hair_colors[(look / 42) % 6].rgb);
	v_pants = to_linear(pants_colors[(look / 252) % 5].rgb);
	v_shoes = to_linear(shoe_colors[(look / 1260) % 4].rgb);
	v_shirt = to_linear(COLOR.rgb);
	v_accent = to_linear(team_colors[clamp(team, 0, 2)].rgb);
}

void fragment() {
	int role = int(floor(UV.x * 16.0));
	vec3 color = v_skin;
	float rough = 0.78;
	if (role == 1) {
		color = v_shirt;
	} else if (role == 2) {
		color = v_pants;
	} else if (role == 3) {
		color = v_hair;
		rough = 0.6;
	} else if (role == 4) {
		color = v_shoes;
	} else if (role == 5) {
		color = DARK;
		rough = 0.4;
	} else if (role == 6) {
		color = v_accent;
		rough = 0.55;
	} else if (role == 7) {
		color = WHITE;
	} else if (role == 8) {
		color = BLUSH;
	}
	ALBEDO = color;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
