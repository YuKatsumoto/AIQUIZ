extends RefCounted

## Sound effect cues played through AudioManager.play_sfx() / start_sfx_loop().
## files: paths under res://assets/audio/sfx/ (one is picked at random).
## volume_db / pitch: base level and pitch. pitch_jitter: random +- ratio.
## min_interval: seconds before the same cue may play again (spam guard).
## Sources and licenses: assets/audio/sfx/CREDITS.md.
const CUES := {
	# --- UI (Buttons / Sliders / TabBars are auto-wired by AudioManager) ---
	&"ui_hover": {"files": ["ui/hover.ogg"], "volume_db": -15.0, "pitch_jitter": 0.03, "min_interval": 0.045},
	&"ui_click": {"files": ["ui/click.ogg"], "volume_db": -5.0, "pitch_jitter": 0.02, "min_interval": 0.03},
	&"ui_confirm": {"files": ["ui/confirm.ogg"], "volume_db": -7.0, "min_interval": 0.08},
	&"ui_back": {"files": ["ui/back.ogg"], "volume_db": -8.0, "min_interval": 0.08},
	&"ui_open": {"files": ["ui/open.ogg"], "volume_db": -9.0, "min_interval": 0.08},
	&"ui_toggle_on": {"files": ["ui/toggle_on.ogg"], "volume_db": -4.0, "min_interval": 0.04},
	&"ui_toggle_off": {"files": ["ui/toggle_off.ogg"], "volume_db": -4.0, "min_interval": 0.04},
	&"ui_slider": {"files": ["ui/slider.ogg"], "volume_db": -14.0, "min_interval": 0.055},
	&"ui_tab": {"files": ["ui/tab.ogg"], "volume_db": -2.0, "min_interval": 0.04},
	&"ui_error": {"files": ["ui/error.ogg"], "volume_db": -10.0, "min_interval": 0.15},
	&"ui_wipe_in": {"files": ["ui/wipe_in.ogg"], "volume_db": -10.0, "min_interval": 0.3},
	&"ui_wipe_out": {"files": ["ui/wipe_out.ogg"], "volume_db": -11.0, "min_interval": 0.3},
	&"ui_shutter_slam": {"files": ["ui/shutter_slam.ogg"], "volume_db": -4.0, "min_interval": 0.1},
	&"ui_text_blip": {"files": ["ui/text_blip.ogg"], "volume_db": -12.0, "min_interval": 0.05},
	&"ui_swish": {"files": ["ui/swish.ogg"], "volume_db": -10.0, "pitch_jitter": 0.04, "min_interval": 0.06},
	&"ui_swish_light": {"files": ["ui/swish_light.ogg"], "volume_db": -12.0, "pitch_jitter": 0.04, "min_interval": 0.06},
	&"ui_belt_start": {"files": ["ui/belt_start.ogg"], "volume_db": -10.0, "pitch_jitter": 0.03, "min_interval": 0.05},
	&"ui_belt_stop": {"files": ["ui/belt_stop.ogg"], "volume_db": -9.0, "pitch_jitter": 0.04, "min_interval": 0.05},
	&"ui_hat_land": {"files": ["ui/hat_land.ogg"], "volume_db": -9.0, "pitch_jitter": 0.05, "min_interval": 0.05},
	&"ui_equip": {"files": ["ui/equip.ogg"], "volume_db": -8.0, "min_interval": 0.06},
	&"ui_page_flip": {"files": ["ui/page_flip_1.ogg", "ui/page_flip_2.ogg", "ui/page_flip_3.ogg"], "volume_db": -4.0,
		"pitch_jitter": 0.04, "min_interval": 0.08},
	&"ui_keycap": {"files": ["ui/keycap.ogg"], "volume_db": -8.0, "pitch_jitter": 0.05, "min_interval": 0.035},
	&"ui_ready": {"files": ["ui/ready.ogg"], "volume_db": -6.0, "min_interval": 0.3},
	&"ui_joined": {"files": ["ui/joined.ogg"], "volume_db": -5.0, "min_interval": 0.3},
	&"ui_disconnect": {"files": ["ui/disconnect.ogg"], "volume_db": -8.0, "min_interval": 0.3},
	&"ui_score_tick": {"files": ["ui/score_tick.ogg"], "volume_db": -12.0, "min_interval": 0.045},
	&"ui_score_ding": {"files": ["ui/score_ding.ogg"], "volume_db": -8.0, "min_interval": 0.3},
	&"ui_shimmer": {"files": ["ui/shimmer.ogg"], "volume_db": -12.0, "min_interval": 0.5},
	&"ui_pause_in": {"files": ["ui/pause_in.ogg"], "volume_db": -8.0, "min_interval": 0.1},
	&"ui_pause_out": {"files": ["ui/pause_out.ogg"], "volume_db": -8.0, "min_interval": 0.1},

	# --- Round start ---
	&"wall_slam": {"files": ["game/wall_slam_1.ogg", "game/wall_slam_2.ogg", "game/wall_slam_3.ogg"], "volume_db": -6.0,
		"pitch_jitter": 0.06, "min_interval": 0.05},
	&"barrier_land": {"files": ["game/barrier_land.ogg"], "volume_db": -2.0, "min_interval": 0.5},
	&"countdown_beep": {"files": ["game/countdown_beep.ogg"], "volume_db": -6.0, "min_interval": 0.3},
	&"countdown_go": {"files": ["game/countdown_beep.ogg"], "volume_db": -3.0, "pitch": 2.0, "min_interval": 0.3},
	&"barrier_steam": {"files": ["game/barrier_steam_loop.ogg"], "volume_db": -14.0},
	&"barrier_explode": {"files": ["game/barrier_explode.ogg"], "volume_db": 0.0, "min_interval": 0.5},
	&"flyover": {"files": ["game/flyover.ogg"], "volume_db": -10.0, "min_interval": 1.0},

	# --- Questions / walls ---
	&"question": {"files": ["game/question.ogg"], "volume_db": -8.0, "min_interval": 0.3},
	&"boss_warning": {"files": ["game/boss_warning.ogg"], "volume_db": -4.0, "min_interval": 1.0},
	&"door_smash": {"files": ["game/door_smash_1.ogg", "game/door_smash_2.ogg", "game/door_smash_3.ogg"],
		"volume_db": -4.0, "pitch_jitter": 0.05, "min_interval": 0.08},
	&"buzzer": {"files": ["game/buzzer.ogg"], "volume_db": -4.0, "min_interval": 0.3},
	&"streak": {"files": ["game/streak.ogg"], "volume_db": -10.0, "min_interval": 0.2},

	# --- Players ---
	&"jump": {"files": ["game/jump.ogg"], "volume_db": -10.0, "pitch_jitter": 0.03, "min_interval": 0.05},
	&"land": {"files": ["game/land_1.ogg", "game/land_2.ogg"], "volume_db": -16.0, "pitch_jitter": 0.06, "min_interval": 0.05},
	&"fall_whistle": {"files": ["game/fall_whistle.ogg"], "volume_db": -8.0, "min_interval": 0.2},
	&"splash": {"files": ["game/splash_1.ogg", "game/splash_2.ogg", "game/splash_3.ogg"], "volume_db": -2.0,
		"pitch_jitter": 0.05, "min_interval": 0.1},
	&"splash_small": {"files": ["game/splash_small_1.ogg", "game/splash_small_2.ogg"], "volume_db": -6.0,
		"pitch_jitter": 0.06, "min_interval": 0.1},
	&"bonk": {"files": ["game/bonk_1.ogg", "game/bonk_2.ogg"], "volume_db": -3.0, "pitch_jitter": 0.04, "min_interval": 0.06},
	&"heart_lose": {"files": ["game/heart_lose.ogg"], "volume_db": -8.0, "min_interval": 0.06},
	&"heart_restore": {"files": ["game/heart_restore.ogg"], "volume_db": -6.0, "min_interval": 0.3},
	&"low_hp": {"files": ["game/low_hp.ogg"], "volume_db": -10.0, "min_interval": 0.5},
	&"wall_crash": {"files": ["game/wall_crash.ogg"], "volume_db": -2.0, "pitch_jitter": 0.03, "min_interval": 0.06},
	&"body_pieces": {"files": ["game/body_pieces.ogg"], "volume_db": -8.0, "pitch_jitter": 0.06, "min_interval": 0.06},
	&"player_out": {"files": ["game/player_out.ogg"], "volume_db": -6.0, "min_interval": 0.3},
	&"force_field": {"files": ["game/force_field_1.ogg", "game/force_field_2.ogg"], "volume_db": -8.0,
		"pitch_jitter": 0.05, "min_interval": 0.3},
	&"danger_beep": {"files": ["game/danger_beep.ogg"], "volume_db": -14.0, "min_interval": 0.1},
	&"emote": {"files": ["game/emote.ogg"], "volume_db": -12.0, "pitch_jitter": 0.04, "min_interval": 0.4},
	&"retry": {"files": ["game/retry.ogg"], "volume_db": -8.0, "min_interval": 0.5},
	&"respawn": {"files": ["game/respawn.ogg"], "volume_db": -8.0, "min_interval": 0.3},

	# --- Hazards ---
	&"saw_catch": {"files": ["game/saw_catch.ogg"], "volume_db": -3.0, "pitch_jitter": 0.04, "min_interval": 0.1},
	&"limb_pop": {"files": ["game/limb_pop.ogg"], "volume_db": -10.0},

	# --- Local 2P push duel ---
	&"push_hit": {"files": ["game/push_hit_1.ogg", "game/push_hit_2.ogg", "game/push_hit_3.ogg"], "volume_db": -5.0,
		"pitch_jitter": 0.06, "min_interval": 0.05},
	&"push_clash": {"files": ["game/push_clash.ogg"], "volume_db": -3.0, "pitch_jitter": 0.04, "min_interval": 0.1},
	&"push_contact": {"files": ["game/push_contact.ogg"], "volume_db": -14.0, "pitch_jitter": 0.08, "min_interval": 0.25},

	# --- Goal / celebration ---
	&"whistle": {"files": ["game/whistle.ogg"], "volume_db": -6.0, "min_interval": 0.5},
	&"firework_launch": {"files": ["game/firework_launch.ogg"], "volume_db": -10.0, "pitch_jitter": 0.08, "min_interval": 0.05},
	&"firework_burst": {"files": ["game/firework_burst_1.ogg", "game/firework_burst_2.ogg", "game/firework_burst_3.ogg",
		"game/firework_burst_4.ogg"], "volume_db": -6.0, "pitch_jitter": 0.06, "min_interval": 0.05},

	# --- World: helicopter, dock, seat launch ---
	&"heli_rotor": {"files": ["world/heli_rotor_loop.ogg"], "volume_db": -6.0},
	&"heli_boost": {"files": ["world/heli_boost.ogg"], "volume_db": -2.0, "pitch_jitter": 0.03},
	&"rope_unroll": {"files": ["world/rope_unroll.ogg"], "volume_db": -6.0, "pitch_jitter": 0.05},
	&"runner_land": {"files": ["world/runner_land.ogg"], "volume_db": -4.0, "pitch_jitter": 0.05},
	&"ship_horn": {"files": ["world/ship_horn.ogg"], "volume_db": -4.0},
	&"belt_zip": {"files": ["world/belt_zip.ogg"], "volume_db": -8.0, "pitch_jitter": 0.05},
	&"chair_touchdown": {"files": ["world/chair_touchdown.ogg"], "volume_db": -4.0},

	# --- World: ghost shark ride ---
	&"soul_rise": {"files": ["world/soul_rise.ogg"], "volume_db": -6.0, "min_interval": 0.5},
	&"rider_land": {"files": ["world/rider_land.ogg"], "volume_db": -8.0, "min_interval": 0.3},
	&"beam_fire": {"files": ["world/beam_fire.ogg"], "volume_db": -4.0, "min_interval": 0.3},
	&"charge_loop": {"files": ["world/charge_loop.ogg"], "volume_db": -14.0},
	&"charge_perfect": {"files": ["world/charge_perfect.ogg"], "volume_db": -6.0, "min_interval": 0.2},
	&"charge_release": {"files": ["world/charge_release.ogg"], "volume_db": -8.0, "min_interval": 0.1},
	&"charge_miss": {"files": ["world/charge_miss.ogg"], "volume_db": -8.0, "min_interval": 0.3},
	&"portal_open": {"files": ["world/portal_open.ogg"], "volume_db": -8.0, "min_interval": 0.5},
	&"portal_cross": {"files": ["world/portal_cross.ogg"], "volume_db": -6.0, "min_interval": 0.5},

	# --- Ambience beds (loops) ---
	&"amb_ocean": {"files": ["ambience/ocean_loop.ogg"], "volume_db": -16.0},
	&"amb_belt": {"files": ["ambience/belt_loop.ogg"], "volume_db": -20.0},
}
