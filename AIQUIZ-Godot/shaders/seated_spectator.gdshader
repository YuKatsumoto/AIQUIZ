shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Seated goal-stand spectators for the side stands (SeatedSpectatorKit,
// GrandstandCrowd). Every vertex follows exactly one bone: UV2.x is the bone,
// UV2.y a bit mask (bits 0..6 the hairstyles owning the triangle, bit 6 + prop
// for a prop triangle). bone_texture holds one baked frame per row, three texels
// (rows of a 3x4 matrix) per bone. UV.x is the palette role as in
// goal_stand_spectator.gdshader.
//
// Per instance:
//   COLOR.rgb          shirt (sRGB)
//   INSTANCE_CUSTOM.x  phase 0..1 (pair partners share it, so they move together)
//   INSTANCE_CUSTOM.y  look  = hairstyle + 7*skin + 42*hair colour + 252*pants + 1260*shoes + 5040*prop
//   INSTANCE_CUSTOM.z  habit = idle clip + 8*role + 128*team (0, 1 P1, 2 P2)
//   INSTANCE_CUSTOM.w  animation speed
//
// What a spectator plays, highest priority first (docs/crowd_extras.md):
//   the stadium wave passing its seat > a local shock (saw, shark, a fall) >
//   the winner's dance > the game's cue (goal, verdict, countdown, start, a
//   miss, lost HP) > the leaders' chant > its own occasional burst > rest.
uniform sampler2D bone_texture : filter_nearest, repeat_disable;
uniform sampler2D sync_bones_1 : filter_nearest, repeat_disable;
uniform sampler2D sync_bones_2 : filter_nearest, repeat_disable;
uniform vec4 clips[40];              // start row, frames, fps, seconds (SeatedSpectatorKit.CLIPS)
uniform vec4 sync_clip_1 = vec4(0.0); // the winner's dance per side; frames 0 = not baked yet
uniform vec4 sync_clip_2 = vec4(0.0);
// Share of burst cycles in which a spectator actually moves.
uniform float burst_chance_fan = 0.22;
uniform float burst_chance_calm = 0.12;
uniform float burst_chance_dancer = 0.3;
uniform vec4 skins[8];
uniform vec4 hair_colors[8];
uniform vec4 pants_colors[8];
uniform vec4 shoe_colors[8];
uniform vec4 team_colors[3];
// Beyond this view distance a spectator steps through its baked 20 fps frames
// instead of blending neighbours: half the bone fetches, invisible that far off.
uniform float smooth_distance = 40.0;

// The game's cue (CrowdCues.Cue): 1 goal, 2 verdict, 3 countdown, 4 start, 5 miss, 6 hurt.
uniform int cue_kind = 0;
uniform int cue_team = 0;
uniform float cue_time = 0.0;
uniform float cue_weight = 0.0;
uniform bool rivals_react = true;    // two players: the rival's fans laugh at a miss
// Positions along the course: world z minus course_z (the stands' back end).
uniform float course_z = 0.0;
uniform float shock_z = 0.0;
uniform float shock_time = -1.0;
uniform float shock_radius = 24.0;
// The wave leaves the right stand at wave_origin, runs to the goal stand
// (wave_goal), crosses it in wave_cross seconds and comes back down the left stand.
uniform float wave_time = -1.0;
uniform float wave_speed = 16.0;
uniform float wave_origin = 20.0;
uniform float wave_goal = 200.0;
uniform float wave_cross = 1.6;
// The leaders' chant: fans clap on their beat, pairs sway arm in arm.
uniform float chant_time = -1.0;
uniform float chant_weight = 0.0;
uniform int chant_team = 0;          // 0 both sides
// The winner's dance: slot 1 holds P1's emote, slot 2 P2's; after a draw each
// side dances its own player's, otherwise everybody the winner's.
uniform float sync_time_1 = -1.0;
uniform float sync_time_2 = -1.0;
uniform float sync_weight = 0.0;
uniform int sync_team = 0;           // the winner, 0 a draw (each side its own player's dance)

varying vec3 v_skin;
varying vec3 v_shirt;
varying vec3 v_pants;
varying vec3 v_hair;
varying vec3 v_shoes;
varying vec3 v_accent;

const vec3 DARK = vec3(0.045, 0.045, 0.06);
const vec3 WHITE = vec3(0.95, 0.95, 0.93);
const vec3 BLUSH = vec3(0.96, 0.55, 0.55);
const vec3 EGG = vec3(0.97, 0.93, 0.84);
const vec3 CARTON = vec3(0.72, 0.64, 0.52);
const vec3 WOOD = vec3(0.58, 0.42, 0.26);
const vec3 POPCORN = vec3(0.97, 0.84, 0.42);
const vec3 RED = vec3(0.80, 0.16, 0.13);
const vec3 METAL = vec3(0.72, 0.75, 0.79);
const vec3 BUN = vec3(0.80, 0.52, 0.27);

// SeatedSpectatorKit.CLIPS
const int C_FOLD = 1;
const int C_TALK = 2;
const int C_CLAP = 5;
const int C_CHEER = 6;
const int C_ANTICIPATE = 9;
const int C_DANCE0 = 10;
const int C_DESPAIR = 14;
const int C_SHAKE = 15;
const int C_LAUGH = 16;
const int C_GASP = 17;
const int C_DOZE = 18;
const int C_WAKE = 19;
const int C_EAT = 20;
const int C_SELFIE = 21;
const int C_BINOCULARS = 22;
const int C_MEGAPHONE = 23;
const int C_DRUM = 24;
const int C_CHANT = 25;
const int C_STANDWAVE = 26;
const int C_TOWEL = 27;
const int C_HIGHFIVE_L = 28;
const int C_HIGHFIVE_R = 29;
const int C_SHOULDER_L = 30;
const int C_SHOULDER_R = 31;
const int C_SYNC_1 = 100;
const int C_SYNC_2 = 101;
// GrandstandCrowd roles
const int R_CALM = 0;
const int R_FAN = 1;
const int R_DANCER = 2;
const int R_SLEEPER = 3;
const int R_EATER = 4;
const int R_SELFIE = 5;
const int R_BINOCULARS = 6;
const int R_LEADER = 7;
const int R_TOWEL = 8;
const int R_PAIR_L = 9;
const int R_PAIR_R = 10;
// SeatedSpectatorKit props
const int P_MEGAPHONE = 5;
const int P_TOWEL = 7;
const int P_TOWEL_NECK = 8;
const int PROP_BIT_BASE = 6;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float hash(float a, float b) {
	return fract(sin(a * 12.9898 + b * 78.233) * 43758.5453);
}

// Rows of the bone matrix for one clip at one time, blended between frames
// (or the current frame alone when `blend` is off). `once` holds the last frame.
void bone_rows(int clip, float time, int bone, bool blend, bool once, out vec4 r0, out vec4 r1, out vec4 r2) {
	vec4 c = clip == C_SYNC_1 ? sync_clip_1 : (clip == C_SYNC_2 ? sync_clip_2 : clips[clip]);
	float frames = max(c.y, 1.0);
	float f = once ? clamp(time * c.z, 0.0, frames - 1.0) : mod(time * c.z, frames);
	float f0 = floor(f);
	float a = f - f0;
	int row0 = int(c.x + f0);
	int row1 = int(c.x + (once ? min(f0 + 1.0, frames - 1.0) : mod(f0 + 1.0, frames)));
	int x = bone * 3;
	if (clip == C_SYNC_1) {
		r0 = texelFetch(sync_bones_1, ivec2(x, row0), 0);
		r1 = texelFetch(sync_bones_1, ivec2(x + 1, row0), 0);
		r2 = texelFetch(sync_bones_1, ivec2(x + 2, row0), 0);
		if (blend) {
			r0 = mix(r0, texelFetch(sync_bones_1, ivec2(x, row1), 0), a);
			r1 = mix(r1, texelFetch(sync_bones_1, ivec2(x + 1, row1), 0), a);
			r2 = mix(r2, texelFetch(sync_bones_1, ivec2(x + 2, row1), 0), a);
		}
	} else if (clip == C_SYNC_2) {
		r0 = texelFetch(sync_bones_2, ivec2(x, row0), 0);
		r1 = texelFetch(sync_bones_2, ivec2(x + 1, row0), 0);
		r2 = texelFetch(sync_bones_2, ivec2(x + 2, row0), 0);
		if (blend) {
			r0 = mix(r0, texelFetch(sync_bones_2, ivec2(x, row1), 0), a);
			r1 = mix(r1, texelFetch(sync_bones_2, ivec2(x + 1, row1), 0), a);
			r2 = mix(r2, texelFetch(sync_bones_2, ivec2(x + 2, row1), 0), a);
		}
	} else {
		r0 = texelFetch(bone_texture, ivec2(x, row0), 0);
		r1 = texelFetch(bone_texture, ivec2(x + 1, row0), 0);
		r2 = texelFetch(bone_texture, ivec2(x + 2, row0), 0);
		if (blend) {
			r0 = mix(r0, texelFetch(bone_texture, ivec2(x, row1), 0), a);
			r1 = mix(r1, texelFetch(bone_texture, ivec2(x + 1, row1), 0), a);
			r2 = mix(r2, texelFetch(bone_texture, ivec2(x + 2, row1), 0), a);
		}
	}
}

void pose(int clip, float time, int bone, bool blend, bool once, vec3 point, vec3 normal, out vec3 out_point, out vec3 out_normal) {
	vec4 r0;
	vec4 r1;
	vec4 r2;
	bone_rows(clip, time, bone, blend, once, r0, r1, r2);
	vec4 p = vec4(point, 1.0);
	out_point = vec3(dot(r0, p), dot(r1, p), dot(r2, p));
	out_normal = vec3(dot(r0.xyz, normal), dot(r1.xyz, normal), dot(r2.xyz, normal));
}

float fade(float t, float len, float edge) {
	return smoothstep(0.0, edge, t) * (1.0 - smoothstep(len - edge, len, t));
}

// The cheer that suits a spectator's role (team fans on a goal or the start).
int cheer_for(int role, int prop) {
	if (role == R_TOWEL) {
		return C_TOWEL;
	}
	if (role == R_PAIR_L) {
		return C_HIGHFIVE_L;
	}
	if (role == R_PAIR_R) {
		return C_HIGHFIVE_R;
	}
	if (role == R_LEADER) {
		return prop == P_MEGAPHONE ? C_MEGAPHONE : C_DRUM;
	}
	if (role == R_SLEEPER) {
		return C_WAKE;
	}
	return C_CHEER;
}

void vertex() {
	int look = int(INSTANCE_CUSTOM.y + 0.5);
	int style = look % 7;
	int prop = look / 5040;
	int habit = int(INSTANCE_CUSTOM.z + 0.5);
	int idle = habit % 8;
	int role = (habit / 8) % 16;
	int team = habit / 128;
	int mask = int(UV2.y + 0.5);
	int bone = int(UV2.x + 0.5);
	float phase = INSTANCE_CUSTOM.x;
	float t = TIME * INSTANCE_CUSTOM.w + phase * 97.0;
	bool prop_triangle = mask >= (1 << (PROP_BIT_BASE + 1));
	vec3 point = vec3(0.0);
	vec3 normal = vec3(0.0, 1.0, 0.0);
	// Hairstyles this spectator does not wear and props it does not hold collapse
	// to a point, so their vertices skip the skinning below.
	bool wanted = prop_triangle ? (prop > 0 && ((mask >> (PROP_BIT_BASE + prop)) & 1) != 0) : (((mask >> style) & 1) != 0);
	bool neck_towel = prop_triangle && prop == P_TOWEL && ((mask >> (PROP_BIT_BASE + P_TOWEL_NECK)) & 1) != 0;
	if (wanted || neck_towel) {
		vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		bool blend = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz) < smooth_distance;
		bool right_stand = origin.x > 0.0;
		float along = origin.z - course_z;
		bool fan = team != 0;

		// Resting pose: a quiet idle or folded arms; personalities have their own.
		int base = idle;
		if (role == R_SLEEPER) {
			base = C_DOZE;
		} else if (role == R_EATER) {
			base = C_EAT;
		} else if (role == R_BINOCULARS) {
			base = C_BINOCULARS;
		}

		// Everyone sits quietly; now and then somebody moves: a fan cheers, claps or
		// waves, a party person dances, a calm spectator chats or checks the phone.
		// Only some cycles have a burst, so at any moment few people are moving.
		float period = 22.0 + 22.0 * fract(phase * 7.13);
		float cycle = floor(t / period);
		float local_time = t - cycle * period;
		float roll = hash(cycle, phase * 31.0);
		float chance = role == R_DANCER ? burst_chance_dancer : (fan ? burst_chance_fan : burst_chance_calm);
		int active = 2 + int(roll * 3.0) % 3;                    // Talk / Phone / Nod
		float active_length = 4.5;
		if (fan) {
			active = C_CLAP + int(roll * 5.0) % 5;
			active_length = 2.5 + 2.0 * fract(roll * 13.0);
		}
		if (role == R_DANCER) {
			active = C_DANCE0 + int(roll * 4.0) % 4;
			active_length = 10.0;
		} else if (role == R_SLEEPER) {
			active = C_WAKE;                                     // a jolt now and then, then back to sleep
			active_length = 1.25;
			chance = 0.10;
		} else if (role == R_EATER || role == R_BINOCULARS) {
			chance = 0.0;
		} else if (role == R_SELFIE) {
			active = C_SELFIE;
			active_length = 6.0;
			chance = 0.4;
		} else if (role == R_LEADER) {
			active = prop == P_MEGAPHONE ? C_MEGAPHONE : C_DRUM;
			active_length = 5.0;
			chance = 0.35;
		} else if (role == R_TOWEL && fract(roll * 7.0) < 0.45) {
			active = C_TOWEL;
			active_length = 4.0;
		} else if ((role == R_PAIR_L || role == R_PAIR_R) && fract(roll * 5.0) < 0.4) {
			active = role == R_PAIR_L ? C_HIGHFIVE_L : C_HIGHFIVE_R;
			active_length = 3.0;
		}
		float active_time = local_time;
		bool once = active == C_WAKE;
		float weight = step(hash(cycle + 17.0, phase * 53.0), chance) * fade(local_time, active_length, 0.5);

		// The leaders' chant, all on one beat: fans clap over their heads, pairs
		// sway arm in arm, the leaders drum or shout.
		if (chant_weight > 0.001 && chant_time >= 0.0 && fan && (chant_team == 0 || team == chant_team)) {
			int chant = -1;
			if (role == R_LEADER) {
				chant = prop == P_MEGAPHONE ? C_MEGAPHONE : C_DRUM;
			} else if (role == R_PAIR_L) {
				chant = C_SHOULDER_L;
			} else if (role == R_PAIR_R) {
				chant = C_SHOULDER_R;
			} else if (role == R_FAN || role == R_TOWEL) {
				chant = C_CHANT;
			}
			if (chant >= 0) {
				active = chant;
				active_time = chant_time;
				once = false;
				weight = chant_weight;
			}
		}

		// Game cues override the schedule.
		if (cue_weight > 0.001) {
			int cued = -1;
			if (cue_kind == 1) {                 // a player reached the goal
				cued = (fan && team == cue_team) ? cheer_for(role, prop) : (role == R_SLEEPER ? C_WAKE : C_CLAP);
			} else if (cue_kind == 2) {          // the verdict
				if (cue_team == 0 || team == cue_team) {
					cued = cheer_for(role, prop);
				} else if (fan) {
					cued = C_DESPAIR;
				} else {
					cued = role == R_SLEEPER ? C_WAKE : C_CLAP;
				}
			} else if (cue_kind == 3) {          // countdown: everyone leans in (sleepers sleep on)
				cued = role == R_SLEEPER ? -1 : C_ANTICIPATE;
			} else if (cue_kind == 4) {          // the start
				cued = cheer_for(role, prop);
			} else if (cue_kind == 5) {          // a player fell or chose the wrong door
				if (fan && team == cue_team) {
					cued = role == R_SLEEPER ? C_WAKE : C_DESPAIR;
				} else if (fan && rivals_react) {
					cued = role == R_SLEEPER ? C_WAKE : C_LAUGH;
				} else {
					cued = role == R_SLEEPER ? C_WAKE : (role == R_EATER ? C_GASP : C_SHAKE);
				}
			} else if (cue_kind == 6) {          // lost HP: that player's fans groan
				cued = (fan && team == cue_team && role != R_SLEEPER) ? C_SHAKE : -1;
			}
			if (cued >= 0) {
				active = cued;
				active_time = cue_time;
				once = cued == C_WAKE;
				weight = cue_weight;
			}
		}

		// The winner's dance: the party people and some of the winner's fans dance
		// it in step with the winner on the tower (over the verdict's cheer).
		if (sync_weight > 0.001) {
			int slot = sync_team == 0 ? (right_stand ? 1 : 2) : sync_team;
			vec4 c = slot == 1 ? sync_clip_1 : sync_clip_2;
			float sync_time = slot == 1 ? sync_time_1 : sync_time_2;
			bool joins = role == R_DANCER
				|| ((sync_team == 0 || team == sync_team) && fan && role != R_LEADER && role != R_PAIR_L && role != R_PAIR_R
					&& hash(phase * 17.0, 3.0) < 0.38);
			if (joins && c.y > 0.5 && sync_time >= 0.0) {
				active = slot == 1 ? C_SYNC_1 : C_SYNC_2;
				active_time = sync_time;
				once = false;
				weight = sync_weight;
			}
		}

		// A saw catch, a shark or a fall near this seat: gasp, rippling outwards.
		if (shock_time >= 0.0) {
			float d = abs(along - shock_z);
			if (d < shock_radius) {
				float since = shock_time - d / 25.0;
				if (since >= 0.0 && since < 2.6) {
					active = role == R_SLEEPER ? C_WAKE : C_GASP;
					active_time = since;
					once = active == C_WAKE;
					weight = fade(since, 2.6, 0.15) * (1.0 - 0.5 * d / shock_radius);
				}
			}
		}

		// The stadium wave passing this seat (sleepers miss it). It starts at the
		// mascot on the right stand, so seats behind it are left out.
		if (wave_time >= 0.0 && role != R_SLEEPER) {
			float arrival = right_stand
				? (along < wave_origin ? 1.0e6 : (along - wave_origin) / wave_speed)
				: (wave_goal - wave_origin) / wave_speed + wave_cross + abs(wave_goal - along) / wave_speed;
			float since = wave_time - arrival;
			float len = clips[C_STANDWAVE].w;
			if (since >= 0.0 && since < len) {
				active = C_STANDWAVE;
				active_time = since;
				once = true;
				weight = fade(since, len, 0.12);
			}
		}

		vec3 idle_point;
		vec3 idle_normal;
		pose(base, t, bone, blend, false, VERTEX, NORMAL, idle_point, idle_normal);
		point = idle_point;
		normal = idle_normal;
		if (weight > 0.001) {
			vec3 active_point;
			vec3 active_normal;
			pose(active, active_time, bone, blend, once, VERTEX, NORMAL, active_point, active_normal);
			point = mix(idle_point, active_point, weight);
			normal = mix(idle_normal, active_normal, weight);
		}
		// The towel fan twirls the hand towel; otherwise it hangs round the neck.
		if (prop_triangle && prop == P_TOWEL) {
			bool spinning = active == C_TOWEL && weight > 0.5;
			if (spinning == neck_towel || (!wanted && !neck_towel)) {
				point = vec3(0.0);
			}
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
	} else if (role == 9) {
		color = EGG;
		rough = 0.35;
	} else if (role == 10) {
		color = CARTON;
	} else if (role == 11) {
		color = WOOD;
	} else if (role == 12) {
		color = POPCORN;
		rough = 0.6;
	} else if (role == 13) {
		color = RED;
		rough = 0.55;
	} else if (role == 14) {
		color = METAL;
		rough = 0.3;
	} else if (role == 15) {
		color = BUN;
	}
	ALBEDO = color;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
