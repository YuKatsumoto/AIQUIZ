extends Node

signal sfx_played(cue: StringName)

## BGM tracks (docs/bgm_renewal.md). play starts from its head when the start barrier breaks,
## result plays on the clear screen and the 2P score tower, menu everywhere else. Every loop but
## menu has an intro: after the first pass it loops back to loop_offset (set in the .import).
const MUSIC_TRACK_NONE: StringName = &""
const MUSIC_TRACK_MENU: StringName = &"menu"
const MUSIC_TRACK_PLAY: StringName = &"play"
const MUSIC_TRACK_RESULT: StringName = &"result"
## Online match: while the matching search waits (docs/online_match_staging/spec.md 13).
const MUSIC_TRACK_MATCH: StringName = &"match"
## 2P sudden death (docs/sudden_death_v2/): the showdown from the "SUDDEN DEATH!" cut-in through the
## boarding, the cruise and the drop to the rule card, then the sky-gate main event from its first "GO!".
## The winner's landing hands over to the result loop, which carries on into the replayed verdict.
const MUSIC_TRACK_SUDDEN_DEATH_INTRO: StringName = &"sudden_death_intro"
const MUSIC_TRACK_SUDDEN_DEATH_MAIN: StringName = &"sudden_death_main"
const MUSIC_TRACKS := {
	MUSIC_TRACK_MENU: "res://assets/audio/bgm/quiz_party_loop.ogg",
	MUSIC_TRACK_PLAY: "res://assets/audio/bgm/quiz_play_loop.ogg",
	MUSIC_TRACK_RESULT: "res://assets/audio/bgm/quiz_result_loop.ogg",
	MUSIC_TRACK_MATCH: "res://assets/audio/bgm/quiz_match_loop.ogg",
	MUSIC_TRACK_SUDDEN_DEATH_INTRO: "res://assets/audio/bgm/quiz_sd_intro_loop.ogg",
	MUSIC_TRACK_SUDDEN_DEATH_MAIN: "res://assets/audio/bgm/quiz_sd_skydive_loop.ogg",
}
const MUSIC_TRACK_FADE_SECONDS := 0.35
## Every loop is mastered to -16 LUFS, but CONTEXT_VOLUME_DB was tuned against the
## previous BGM at -25.4 LUFS (docs/bgm_renewal.md); trim to keep that balance.
const BGM_TRACK_GAIN_DB := -9.4
const SETTINGS_PATH := "user://audio_settings.cfg"
## v1 stored the BGM slider as a linear bus gain (1.0 = 0 dB); v2 uses the curve below.
const AUDIO_SETTINGS_VERSION := 2
## BGM slider (0..1) to bus gain. The default position plays at 0 dB (the v1 maximum),
## each halving of the slider is BGM_MAX_GAIN_DB quieter, and the top adds
## BGM_MAX_GAIN_DB, which cancels BGM_TRACK_GAIN_DB so the loop plays at its
## mastered level (peak -4.3 dBFS in gameplay).
const BGM_DEFAULT_VOLUME := 0.5
const BGM_MAX_GAIN_DB := -BGM_TRACK_GAIN_DB
const MUSIC_CONTEXT_MENU: StringName = &"menu"
const MUSIC_CONTEXT_GAMEPLAY: StringName = &"gameplay"
const MUSIC_CONTEXT_PAUSED: StringName = &"paused"
const MUSIC_CONTEXT_RESULT: StringName = &"result"
## 2P sudden death (docs/sudden_death_v2/), from the "SUDDEN DEATH!" cut-in: its own music sits 2 dB under
## gameplay so the floatplane, the wind and the gates stay on top (the menu loop used to play 6 dB lower).
const MUSIC_CONTEXT_SUDDEN_DEATH: StringName = &"sudden_death"
## Online match: from boarding the helicopter until the blackout after the dash, the BGM keeps
## playing but sits 12 dB under the menu level so the helicopter effects lead.
const MUSIC_CONTEXT_ONLINE_STAGING: StringName = &"online_staging"

## Menu, gameplay and results play at the same level, so the music does not jump when the
## game world opens (2026-10-12; gameplay used to be 4 dB louder).
const CONTEXT_VOLUME_DB := {
	MUSIC_CONTEXT_MENU: -4.0,
	MUSIC_CONTEXT_GAMEPLAY: -4.0,
	MUSIC_CONTEXT_PAUSED: -10.0,
	MUSIC_CONTEXT_RESULT: -4.0,
	MUSIC_CONTEXT_SUDDEN_DEATH: -6.0,
	MUSIC_CONTEXT_ONLINE_STAGING: -16.0,
}

## Shared one-shot effects, UI activation, and gameplay impact/death cues
## (docs/sound_effects.md). files: paths under res://assets/audio/sfx/ (one is picked at
## random). volume_db: base level. pitch_jitter: random +- ratio. min_interval:
## seconds before the same cue may play again. Sources: assets/audio/sfx/CREDITS.md.
const SFX_ROOT := "res://assets/audio/sfx/"
## A BaseButton may set this meta to the cue it plays instead of ui_click (see UI_CUES).
const UI_SOUND_META := &"ui_sound_cue"
## Cues that use the dedicated UI voices, so UI sounds never steal gameplay voices.
## The practice's bubble pop, task tick and clear stamp are UI feedback that also plays over the menus
## (where the in-world effects are muted).
const UI_CUES: Array[StringName] = [&"ui_click", &"ui_start", &"practice_pop", &"practice_tick", &"practice_stamp"]
const SFX_CUES := {
	# UI sounds come from the user-supplied 効果音ラボ files in se_lab/ (not in git; a missing file
	# stays silent). ui_click: カーソル移動1 on every button. ui_start: 決定ボタンを押す53 on the
	# menu's game-start button (it sets the meta UI_SOUND_META on itself).
	&"ui_click": {"files": ["se_lab/ui_click.ogg"], "volume_db": -3.0, "pitch_jitter": 0.015, "min_interval": 0.025},
	&"ui_start": {"files": ["se_lab/ui_start.ogg"], "volume_db": -3.0, "pitch_jitter": 0.0, "min_interval": 0.3},
	&"heli_land": {"files": ["game/heli_land.ogg"], "volume_db": -4.0, "pitch_jitter": 0.025, "min_interval": 0.0},
	&"shark_bite": {"files": ["game/shark_bite.ogg"], "volume_db": -6.0, "pitch_jitter": 0.035, "min_interval": 0.0},
	&"body_burst": {"files": ["game/body_burst.ogg"], "volume_db": -6.0, "pitch_jitter": 0.035, "min_interval": 0.0},
	# Hitting a wall (a wrong door that costs a heart, and the fatal crash). se_lab/ is not in
	# git (se_lab/.gitignore); a missing file stays silent.
	&"bonk": {"files": ["se_lab/wall_hit.ogg"], "volume_db": -11.0, "pitch_jitter": 0.04, "min_interval": 0.06},
	&"wall_crash": {"files": ["se_lab/wall_hit.ogg"], "volume_db": -9.0, "pitch_jitter": 0.03, "min_interval": 0.06},
	# Quiz judgement at each player's door: correct (ding-dong) and wrong (buzzer).
	&"door_correct": {"files": ["game/door_correct.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 0.15},
	&"door_wrong": {"files": ["game/door_wrong.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 0.3},
	# The PV's first question being written by "AI" (docs/ai_question_typing.md; not used in gameplay): a soft
	# tick per token and a short two-note shimmer when the question and choices are complete (tools/audio/make_ai_typing_sfx.py).
	&"ai_type_tick": {"files": ["game/ai_type_tick.ogg"], "volume_db": -12.0, "pitch_jitter": 0.08, "min_interval": 0.03},
	&"ai_type_done": {"files": ["game/ai_type_done.ogg"], "volume_db": -10.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	# 2P push duel (a push lands or both clash) and a player landing from a jump.
	&"push_kick": {"files": ["se_lab/push_kick.ogg"], "volume_db": -13.0, "pitch_jitter": 0.05, "min_interval": 0.08},
	&"jump_land": {"files": ["se_lab/jump_land.ogg"], "volume_db": -5.0, "pitch_jitter": 0.06, "min_interval": 0.05},
	&"countdown_beep": {"files": ["game/countdown_beep.ogg"], "volume_db": -10.0, "pitch_jitter": 0.0, "min_interval": 0.3},
	&"countdown_go": {"files": ["game/countdown_go.ogg"], "volume_db": -10.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	# The practice (tutorial, docs/new_tutorial/phase9_design.md 2章), synthesized for this game (tools/audio/make_practice_sfx.py):
	# Hatena's speech bubble, a task's check mark, the clear card's stamp, the rewind after a miss, the 1-2 fence bounce,
	# the sign wall flying back up and the 2-1 high five.
	&"practice_pop": {"files": ["practice/practice_pop.ogg"], "volume_db": -12.0, "pitch_jitter": 0.04, "min_interval": 0.05},
	&"practice_tick": {"files": ["practice/practice_tick.ogg"], "volume_db": -11.0, "pitch_jitter": 0.0, "min_interval": 0.05},
	&"practice_stamp": {"files": ["practice/practice_stamp.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 0.3},
	&"practice_rewind": {"files": ["practice/practice_rewind.ogg"], "volume_db": -7.0, "pitch_jitter": 0.0, "min_interval": 0.3},
	&"practice_fence": {"files": ["practice/practice_fence.ogg"], "volume_db": -16.0, "pitch_jitter": 0.05, "min_interval": 0.2},
	&"practice_sign_fly": {"files": ["practice/practice_sign_fly.ogg"], "volume_db": -10.0, "pitch_jitter": 0.03, "min_interval": 0.3},
	&"practice_high_five": {"files": ["practice/practice_high_five.ogg"], "volume_db": 0.0, "pitch_jitter": 0.04, "min_interval": 0.1},
	# 2P score tower, from the user-supplied 効果音ラボ files in se_lab/ (not in git): a drum roll
	# over the whole tally and climb (2.0-6.3 s, 4.3 s long), then the closing hit at the verdict (6.9 s).
	&"score_drum_roll": {"files": ["se_lab/score_roll.ogg"], "volume_db": -5.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"score_drum_finish": {"files": ["se_lab/score_roll_finish.ogg"], "volume_db": -5.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	# Quiz wall landing on the conveyor, the countdown wall rumbling (rises over the 5 s countdown, cut
	# when the wall breaks) and breaking. Also se_lab/ (user-supplied 効果音ラボ files, not in git).
	&"wall_land": {"files": ["se_lab/wall_land.ogg"], "volume_db": -4.0, "pitch_jitter": 0.04, "min_interval": 0.03},
	# The countdown wall dropping in and landing (ロボットを殴る3).
	&"barrier_land": {"files": ["se_lab/barrier_land.ogg"], "volume_db": -3.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"countdown_rumble": {"files": ["se_lab/countdown_rumble.ogg"], "volume_db": -8.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"barrier_explosion": {"files": ["se_lab/barrier_explosion.ogg"], "volume_db": -3.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	# Spectators. The crowd files are not in git (assets/audio/sfx/crowd/.gitignore); a missing
	# file just stays silent.
	&"crowd_goal_cheer": {"files": ["crowd/crowd_goal_cheer.ogg"], "volume_db": -6.0, "pitch_jitter": 0.03, "min_interval": 1.5},
	&"crowd_win_cheer": {"files": ["crowd/crowd_win_cheer.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 1.5},
	&"crowd_applause": {"files": ["crowd/crowd_applause.ogg"], "volume_db": -9.0, "pitch_jitter": 0.0, "min_interval": 1.5},
	&"crowd_aww": {"files": ["crowd/crowd_aww.ogg"], "volume_db": -8.0, "pitch_jitter": 0.0, "min_interval": 1.5},
	# Ghost shark ride (GhostSharkRideController), synthesized by tools/audio/make_ghost_shark_sfx.py.
	# The soul leaving the body, the shark rising from the deep and breaking the surface, the spirit
	# pillar after mounting, the PERFECT-band tick, the dash, the hit, the shark fading out after a
	# dash, and the return portal opening / the shark bursting through it. The held charge hum
	# (ghost_shark/ghost_charge_loop.ogg) is a dedicated looping player in the controller.
	&"ghost_soul_rise": {"files": ["ghost_shark/ghost_soul_rise.ogg"], "volume_db": -10.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"ghost_shark_rise": {"files": ["ghost_shark/ghost_shark_rise.ogg"], "volume_db": -8.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"ghost_shark_breach": {"files": ["ghost_shark/ghost_shark_breach.ogg"], "volume_db": -6.0, "pitch_jitter": 0.03, "min_interval": 0.5},
	&"ghost_mount_beam": {"files": ["ghost_shark/ghost_mount_beam.ogg"], "volume_db": -9.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"ghost_dash": {"files": ["ghost_shark/ghost_dash.ogg"], "volume_db": -6.0, "pitch_jitter": 0.03, "min_interval": 0.2},
	&"ghost_hit": {"files": ["ghost_shark/ghost_hit.ogg"], "volume_db": -5.0, "pitch_jitter": 0.04, "min_interval": 0.2},
	# 突進が当たった生き残りの体（docs/ghost_hit_ragdoll_plan.md 段階 6）：鼻先が体に当たる鈍い音（ghost_hit に重ねる）、
	# 吹き飛んだ体が床に落ちる「ドサッ」、転倒して床を転がって擦れる音（受け身の前転は小さく高めに鳴らす）。
	&"ghost_hit_body": {"files": ["ghost_shark/ghost_hit_body.ogg"], "volume_db": -6.0, "pitch_jitter": 0.04, "min_interval": 0.2},
	&"ghost_body_land": {"files": ["ghost_shark/ghost_body_land.ogg"], "volume_db": -5.0, "pitch_jitter": 0.05, "min_interval": 0.3},
	&"ghost_body_tumble": {"files": ["ghost_shark/ghost_body_tumble.ogg"], "volume_db": -9.0, "pitch_jitter": 0.05, "min_interval": 0.3},
	&"ghost_vanish": {"files": ["ghost_shark/ghost_vanish.ogg"], "volume_db": -11.0, "pitch_jitter": 0.03, "min_interval": 0.3},
	&"ghost_portal_open": {"files": ["ghost_shark/ghost_portal_open.ogg"], "volume_db": -9.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"ghost_portal_cross": {"files": ["ghost_shark/ghost_portal_cross.ogg"], "volume_db": -8.0, "pitch_jitter": 0.03, "min_interval": 0.3},
	# GOSTRIDER の搭乗：魂が両腕を広げて目覚める（吸い込みの 0.16 秒あとに和音）、鞍へ落ちて乗り移る。
	&"ghost_awaken": {"files": ["ghost_shark/ghost_awaken.ogg"], "volume_db": -9.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"ghost_mount_land": {"files": ["ghost_shark/ghost_mount_land.ogg"], "volume_db": -6.0, "pitch_jitter": 0.02, "min_interval": 0.5},
	# サドンデスへ行くときの幽霊の復活（docs/sudden_death_v2/ghost_revive.md）：部位を引き寄せる風（弾ける瞬間に吸い込みが
	# 止まる）、部位が 1 つはまる音（GhostRevival が長音階で音程を上げていく）、弾ける光と 0.46 秒後の着地。
	&"ghost_revive_gather": {"files": ["ghost_shark/ghost_revive_gather.ogg"], "volume_db": -8.0, "pitch_jitter": 0.0, "min_interval": 0.1},
	&"ghost_revive_snap": {"files": ["ghost_shark/ghost_revive_snap.ogg"], "volume_db": -9.0, "pitch_jitter": 0.0, "min_interval": 0.0},
	&"ghost_revive_burst": {"files": ["ghost_shark/ghost_revive_burst.ogg"], "volume_db": -5.0, "pitch_jitter": 0.0, "min_interval": 0.1},
	# 両者脱落の投げ縄（EliminationLassoDirector、docs/elimination_lasso.md）。tools/audio/make_lasso_sfx.py で合成：
	# 頭上で回す 1 周ごとのヒュン（回すほど速く・高く鳴らす）、投げて縄が手から出ていく音、2 人に巻きついて締まる音。
	&"lasso_whirl": {"files": ["lasso/lasso_whirl.ogg"], "volume_db": -7.0, "pitch_jitter": 0.02, "min_interval": 0.08},
	&"lasso_throw": {"files": ["lasso/lasso_throw.ogg"], "volume_db": -5.0, "pitch_jitter": 0.02, "min_interval": 0.2},
	&"lasso_cinch": {"files": ["lasso/lasso_cinch.ogg"], "volume_db": -4.0, "pitch_jitter": 0.02, "min_interval": 0.1},
	# サドンデス「つきやぶれ！スカイゲート」（docs/sound_effects.md「サドンデス」）。効果音ラボの素材を
	# tools/audio/make_sudden_death_sfx.py で切り出した se_lab/ の音（git に入れない。ファイルがなければ鳴らない）。
	# 分岐：審判の笛（8.4 秒）、「SUDDEN DEATH!」の警報（8.6 秒）、タワーが沈む・伸び直す／昇降台のモーター。
	&"sd_whistle": {"files": ["se_lab/sd_whistle.ogg"], "volume_db": -7.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"sd_siren": {"files": ["se_lab/sd_siren.ogg"], "volume_db": -2.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"sd_tower_move": {"files": ["se_lab/sd_tower_move.ogg"], "volume_db": -7.0, "pitch_jitter": 0.0, "min_interval": 0.3},
	# 水上機の乗り込み：台座の横のスタンドが塔で上がる・下りる、ハッチのサーボ、油圧のスロープとロック、ベルト。
	&"sd_stand_lift": {"files": ["se_lab/sd_stand_lift.ogg"], "volume_db": -3.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"sd_stand_lower": {"files": ["se_lab/sd_stand_lower.ogg"], "volume_db": -5.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"sd_servo": {"files": ["se_lab/sd_servo.ogg"], "volume_db": -5.0, "pitch_jitter": 0.02, "min_interval": 0.2},
	&"fp_ramp": {"files": ["se_lab/fp_ramp.ogg"], "volume_db": -7.0, "pitch_jitter": 0.0, "min_interval": 0.2},
	&"fp_ramp_latch": {"files": ["se_lab/fp_ramp_latch.ogg"], "volume_db": -9.0, "pitch_jitter": 0.02, "min_interval": 0.3},
	&"fp_belt": {"files": ["helicopter/belt_click.ogg"], "volume_db": -1.0, "pitch_jitter": 0.04, "min_interval": 0.0},
	# 水上機：真上を低く通る（通過の録音。いちばん大きい所が頭から 1.2 秒）、着水のしぶき、降下灯が緑になる合図（スタートの壁が
	# 割れる「ぷーん」と同じ音。前のブザーは不正解のブーとまぎらわしかった）、
	# 開いたスロープから吹き込む風、スロープから飛び出す、雲の覆い（雲を抜ける風）。エンジンは FloatplaneSound。
	&"fp_flyby": {"files": ["se_lab/fp_flyby.ogg"], "volume_db": -1.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"fp_touchdown": {"files": ["se_lab/fp_touchdown.ogg"], "volume_db": -2.0, "pitch_jitter": 0.03, "min_interval": 0.5},
	&"fp_green_light": {"files": ["game/countdown_go.ogg"], "volume_db": -13.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"fp_ramp_wind": {"files": ["se_lab/fp_ramp_wind.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"fp_jump": {"files": ["se_lab/fp_jump.ogg"], "volume_db": -6.0, "pitch_jitter": 0.04, "min_interval": 0.0},
	&"sd_cloud_whoosh": {"files": ["se_lab/sd_cloud_whoosh.ogg"], "volume_db": -1.0, "pitch_jitter": 0.03, "min_interval": 0.4},
	# 本戦：ボードの高さを通る、正解の紙をつき破る（2 通り）、まちがいの紙にはね返される、判定のセーフ、2 人ともアウトからの復活、
	# ROUND 2 からの開始のゴング、2 人とも地上へのファンファーレ、延長戦、ボードの知らせ、パラシュートが開く、着地台のしぶき、勝者の着地。
	&"sg_gate_rush": {"files": ["se_lab/sg_gate_rush.ogg"], "volume_db": -3.0, "pitch_jitter": 0.03, "min_interval": 0.3},
	&"sg_tear": {"files": ["se_lab/sg_tear_a.ogg", "se_lab/sg_tear_b.ogg"], "volume_db": -1.0, "pitch_jitter": 0.06, "min_interval": 0.0},
	&"sg_bounce": {"files": ["se_lab/sg_bounce.ogg"], "volume_db": -4.0, "pitch_jitter": 0.03, "min_interval": 0.0},
	&"sg_safe": {"files": ["se_lab/sg_safe.ogg"], "volume_db": -5.0, "pitch_jitter": 0.0, "min_interval": 0.3},
	&"sg_revive": {"files": ["se_lab/sg_revive.ogg"], "volume_db": -5.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"sg_round_gong": {"files": ["se_lab/sg_round_gong.ogg"], "volume_db": -1.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"sg_round_clear": {"files": ["se_lab/sg_round_clear.ogg"], "volume_db": -2.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"sg_overtime": {"files": ["se_lab/sg_overtime.ogg"], "volume_db": -1.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"sg_notice": {"files": ["se_lab/sg_notice.ogg"], "volume_db": -4.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"sg_chute_open": {"files": ["se_lab/sg_chute_open.ogg"], "volume_db": -1.0, "pitch_jitter": 0.03, "min_interval": 0.0},
	&"sg_float_splash": {"files": ["se_lab/sg_float_splash.ogg"], "volume_db": -7.0, "pitch_jitter": 0.05, "min_interval": 0.05},
	&"sg_winner": {"files": ["se_lab/sg_winner.ogg"], "volume_db": -3.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	# 着地台のまわりの観客船（sky_gate.md 第9章）：クラッカー、打ち上げ花火の上がる音とはじける音。専用の音はまだないので、
	# 手持ちの効果音ラボの音で代用している（クラッカー＝爆発の音を高く短く鳴らす・上がる音＝高速移動の風切り・はじける音＝爆発の音）。
	# 専用の音に替えるときはファイルだけ替える（鳴らす所と音程は SkyGateFireworks）。
	&"sg_popper": {"files": ["se_lab/barrier_explosion.ogg"], "volume_db": -17.0, "pitch_jitter": 0.06, "min_interval": 0.12},
	&"sg_firework_launch": {"files": ["se_lab/sg_gate_rush.ogg"], "volume_db": -15.0, "pitch_jitter": 0.05, "min_interval": 0.25},
	&"sg_firework_burst": {"files": ["se_lab/barrier_explosion.ogg"], "volume_db": -8.0, "pitch_jitter": 0.05, "min_interval": 0.12},
}
## サドンデスで鳴らす単発の音（監督が試合の頭に preload_sfx で読んでおく）。
const SUDDEN_DEATH_SFX_CUES: Array[StringName] = [
	&"sd_whistle", &"sd_siren", &"sd_tower_move", &"sd_stand_lift", &"sd_stand_lower", &"sd_servo", &"fp_ramp",
	&"fp_ramp_latch", &"fp_belt", &"fp_flyby", &"fp_touchdown", &"fp_green_light", &"fp_ramp_wind", &"fp_jump", &"sd_cloud_whoosh",
	&"sg_gate_rush", &"sg_tear", &"sg_bounce", &"sg_safe", &"sg_revive", &"sg_round_gong", &"sg_round_clear", &"sg_overtime",
	&"sg_notice", &"sg_chute_open", &"sg_float_splash", &"sg_winner", &"sg_popper", &"sg_firework_launch", &"sg_firework_burst",
	&"crowd_win_cheer", &"crowd_goal_cheer",
	&"score_drum_roll", &"score_drum_finish", &"door_correct", &"door_wrong", &"countdown_beep", &"countdown_go",
	&"barrier_explosion", &"body_burst", &"ghost_soul_rise", &"wall_crash", &"jump_land",
	&"ghost_awaken", &"ghost_revive_gather", &"ghost_revive_snap", &"ghost_revive_burst",
]
## Spectator beds on the SFX bus (set_crowd_ambience): the stadium murmur before the start,
## the cheering while a race runs. Switching crossfades; a missing file stays silent.
const CROWD_NONE: StringName = &""
const CROWD_MURMUR: StringName = &"murmur"
const CROWD_RACE: StringName = &"race"
const CROWD_AMBIENCES := {
	CROWD_MURMUR: {"path": "res://assets/audio/sfx/crowd/crowd_murmur_loop.ogg", "volume_db": -8.0},
	CROWD_RACE: {"path": "res://assets/audio/sfx/crowd/crowd_race_loop.ogg", "volume_db": -14.0},
}
const CROWD_FADE_SECONDS := 0.8
const AMBIENCE_BUS := "Ambience"
## オンライン対戦のマッチング演出の効果音（docs/online_match_staging/spec.md 13）。今の方針（効果音は壁の音だけ）に合わせて
## 既定では鳴らさない（OnlineStagingTimeline.SFX_ENABLED）。素材は CC0 で assets/audio/sfx/online/ に置き、CREDITS.md に出典を書く。
const STAGING_SFX_CUES := {
	&"door_open": {"files": ["online/door_open.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 0.2},
	&"step_metal": {"files": ["online/step_metal.ogg"], "volume_db": -8.0, "pitch_jitter": 0.05, "min_interval": 0.1},
	&"belt_click": {"files": ["online/belt_click.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 0.2},
	&"rotor_spool": {"files": ["online/rotor_spool.ogg"], "volume_db": -10.0, "pitch_jitter": 0.0, "min_interval": 1.0},
	&"whoosh_flyby": {"files": ["online/whoosh_flyby.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"cutin_lightning": {"files": ["online/cutin_lightning.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"split_whoosh": {"files": ["online/split_whoosh.ogg"], "volume_db": -6.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	# VS 演出（対峙）の効果音。SFX_ENABLED に関係なく鳴らす。1 本の音で演出の時刻に合わせてある（tools/audio/make_versus_sfx.py）
	&"versus_cutin_in": {"files": ["online/versus_cutin_in.ogg"], "volume_db": -3.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"versus_charge": {"files": ["online/versus_charge.ogg"], "volume_db": -9.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"versus_reveal": {"files": ["online/versus_reveal.ogg"], "volume_db": -2.0, "pitch_jitter": 0.0, "min_interval": 0.5},
	&"versus_reveal_short": {"files": ["online/versus_reveal_short.ogg"], "volume_db": -2.0, "pitch_jitter": 0.0, "min_interval": 0.5},
}
## VS 演出の効果音（OnlineMenu が開いたときに preload_sfx で先に読み込む）
const VERSUS_SFX_CUES: Array[StringName] = [&"versus_cutin_in", &"versus_charge", &"versus_reveal", &"versus_reveal_short"]
## 音楽のスティング（BGM の上に 1 回だけ鳴らし、鳴っているあいだ BGM を STING_DUCK_DB 下げる）。素材がなければ鳴らさない
const STINGS := {&"versus": "res://assets/audio/bgm/sting_versus.ogg"}
const STING_DUCK_DB := -8.0
const SFX_VOICES := 8

## オーディオ管理 (Autoload)
## BGM と共通の単発SE。ヘリの持続音とチップソーの起動音は各表示ノードが管理する。

## The player of the current track; the other track's player fades out and stops.
var bgm_player: AudioStreamPlayer
var _music_track: StringName = MUSIC_TRACK_MENU
var _music_started := false  # the first set_music_context() started playback (boot is silent)
var _track_players: Dictionary = {}
var _fade_out_tweens: Dictionary = {}

var sfx_volume: float = 1.0
var bgm_volume: float = BGM_DEFAULT_VOLUME
var _music_context: StringName = MUSIC_CONTEXT_MENU
var _context_before_pause: StringName = MUSIC_CONTEXT_MENU
var _context_tween: Tween = null
var _sfx_voices: Array[AudioStreamPlayer] = []
var _tutorial_ducked: bool = false
var _ui_voices: Array[AudioStreamPlayer] = []
var _sfx_voice_cursor := 0
var _ui_voice_cursor := 0
var _sfx_streams: Dictionary = {}
## While the main menu is on screen, in-world effects (saw, helicopters, wall hits, bursts...) stay
## silent; UI sounds still play. The menu sets this through set_menu_sfx_muted().
var menu_sfx_muted := false
var _menu_sfx_owner: Node = null
var _sfx_last_msec: Dictionary = {}
var _sfx_last_variant: Dictionary = {}
var _sting_player: AudioStreamPlayer = null
var _sting_ducked := false
## Scene-transition fade on the BGM and Ambience buses, following how much of the screen the
## black transition covers (SceneTransition.get_cover_factor): music fades out as the wipe
## closes, stays silent while the next scene loads, and fades back in as the wipe opens.
var _transition_db := 0.0
var _crowd_kind: StringName = CROWD_NONE
var _crowd_players: Dictionary = {}
var _crowd_tweens: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_output_limiter()
	_ensure_bus("BGM")
	_ensure_bus("SFX")
	# Spectator beds get their own bus (into SFX, so the SFX slider still applies) so the
	# scene-transition fade can take them down without touching the wall and countdown sounds.
	_ensure_bus(AMBIENCE_BUS)
	AudioServer.set_bus_send(AudioServer.get_bus_index(AMBIENCE_BUS), "SFX")
	_load_audio_settings()

	for track: StringName in MUSIC_TRACKS:
		var player := AudioStreamPlayer.new()
		player.name = "BGMPlayer" if track == MUSIC_TRACK_MENU else "BGMPlayer_%s" % track
		player.bus = "BGM"
		var stream: AudioStream = load(MUSIC_TRACKS[track]) as AudioStream
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		player.stream = stream
		player.volume_db = CONTEXT_VOLUME_DB[MUSIC_CONTEXT_MENU] + BGM_TRACK_GAIN_DB
		add_child(player)
		_track_players[track] = player
	bgm_player = _track_players[MUSIC_TRACK_MENU]

	for index in range(SFX_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.name = "SfxVoice%d" % index
		voice.bus = "SFX"
		add_child(voice)
		_sfx_voices.append(voice)
	# UI clicks have their own voices so a click never cuts a landing/death sound.
	for index in range(2):
		var voice := AudioStreamPlayer.new()
		voice.name = "UiClickVoice%d" % index
		voice.bus = "SFX"
		add_child(voice)
		_ui_voices.append(voice)
	get_tree().node_added.connect(_queue_ui_sound_hook)
	call_deferred("_hook_existing_ui", get_tree().root)

	_sting_player = AudioStreamPlayer.new()
	_sting_player.name = "StingPlayer"
	_sting_player.bus = "BGM"
	_sting_player.finished.connect(func() -> void:
		_sting_ducked = false
		_apply_music_target(0.4))
	add_child(_sting_player)

	for kind: StringName in CROWD_AMBIENCES:
		var crowd := AudioStreamPlayer.new()
		crowd.name = "Crowd_%s" % kind
		crowd.bus = AMBIENCE_BUS
		var path: String = CROWD_AMBIENCES[kind].path
		if ResourceLoader.exists(path):
			var crowd_stream := load(path) as AudioStream
			if crowd_stream is AudioStreamOggVorbis:
				(crowd_stream as AudioStreamOggVorbis).loop = true
			crowd.stream = crowd_stream
		add_child(crowd)
		_crowd_players[kind] = crowd

	var game_state: QuizGameState = QuizManager.game_state
	game_state.sfx_volume = sfx_volume
	game_state.bgm_volume = bgm_volume

	set_sfx_volume(sfx_volume, false)
	set_bgm_volume(bgm_volume, false)
	# Playback starts on the first set_music_context(), so the startup loading
	# screen stays silent until the menu has actually appeared.


## Only catches overlapping peaks. No input gain, so ordinary music/SFX levels
## and the user's volume sliders stay at their selected level.
func _ensure_output_limiter() -> void:
	for i in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.resource_name = "OutputPeakGuard"
	limiter.pre_gain_db = 0.0
	limiter.ceiling_db = -1.0
	limiter.release = 0.1
	AudioServer.add_bus_effect(0, limiter)


func _process(_delta: float) -> void:
	var transition := get_node_or_null("/root/SceneTransition")
	var cover: float = transition.get_cover_factor() if transition != null else 0.0
	# Equal-power curve: half covered is about -3 dB, fully covered is silent.
	var gain := cos(clampf(cover, 0.0, 1.0) * PI * 0.5)
	var target_db := maxf(-80.0, linear_to_db(gain)) if gain > 0.0001 else -80.0
	if absf(target_db - _transition_db) < 0.05:
		return
	_transition_db = target_db
	_set_bus_volume_db("BGM", bgm_volume_to_db(bgm_volume) + _transition_db)
	_set_bus_volume_db(AMBIENCE_BUS, _transition_db)


## Plays one of SFX_CUES. volume_db and pitch_scale apply on top of the cue's values.
func play_sfx(cue: StringName, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if menu_sfx_muted and cue not in UI_CUES:
		return
	var def: Dictionary = SFX_CUES.get(cue, STAGING_SFX_CUES.get(cue, {}))
	if def.is_empty():
		push_warning("AudioManager: unknown sfx cue '%s'" % cue)
		return
	var now := Time.get_ticks_msec()
	var min_interval_msec := int(float(def.get("min_interval", 0.0)) * 1000.0)
	if min_interval_msec > 0 and now - int(_sfx_last_msec.get(cue, -100000)) < min_interval_msec:
		return
	var stream := _sfx_pick_stream(cue, def)
	if stream == null:
		return
	_sfx_last_msec[cue] = now
	var ui := cue in UI_CUES
	var voices := _ui_voices if ui else _sfx_voices
	var cursor := _ui_voice_cursor if ui else _sfx_voice_cursor
	var player := voices[cursor]
	for voice in voices:
		if not voice.playing:
			player = voice
			break
	player.stream = stream
	player.volume_db = float(def.get("volume_db", 0.0)) + volume_db
	var jitter := float(def.get("pitch_jitter", 0.0))
	player.pitch_scale = maxf(0.05, pitch_scale * (1.0 + randf_range(-jitter, jitter)))
	player.play()
	if ui:
		_ui_voice_cursor = (cursor + 1) % voices.size()
	else:
		_sfx_voice_cursor = (cursor + 1) % voices.size()
	sfx_played.emit(cue)


## The main menu mutes the in-world effects while it is on screen. A menu that is being replaced
## by a new menu instance must not unmute the new one, so only the current owner can release it.
func set_menu_sfx_muted(owner_node: Node, muted: bool) -> void:
	if muted:
		_menu_sfx_owner = owner_node
		menu_sfx_muted = true
		for voice in _sfx_voices:
			voice.stop()
	elif _menu_sfx_owner == owner_node:
		_menu_sfx_owner = null
		menu_sfx_muted = false


## 効果音のファイルを先に読み込んでおく（play_sfx は初めて鳴らすときに読むので、演出の途中で読むとそのフレームが重くなる）。
func preload_sfx(cues: Array) -> void:
	for cue: StringName in cues:
		var def: Dictionary = SFX_CUES.get(cue, STAGING_SFX_CUES.get(cue, {}))
		for file: Variant in def.get("files", []):
			var path: String = SFX_ROOT + String(file)
			if not _sfx_streams.has(path):
				_sfx_streams[path] = load(path) if ResourceLoader.exists(path) else null


## この効果音を鳴らしている声を seconds 秒で消して止める（次の音へつなぐとき、ぷつっと切らない）。
func fade_out_sfx(cue: StringName, seconds: float) -> void:
	var def: Dictionary = SFX_CUES.get(cue, STAGING_SFX_CUES.get(cue, {}))
	for file: Variant in def.get("files", []):
		var stream: AudioStream = _sfx_streams.get(SFX_ROOT + String(file))
		if stream == null:
			continue
		for voice in _sfx_voices:
			if voice.playing and voice.stream == stream:
				var tween := create_tween()
				tween.tween_property(voice, "volume_db", -60.0, maxf(seconds, 0.01))
				tween.tween_callback(func() -> void:
					if voice.stream == stream:
						voice.stop())


## Stops every voice that is playing a file of this cue (a long one-shot must not outlive its scene).
func stop_sfx(cue: StringName) -> void:
	var def: Dictionary = SFX_CUES.get(cue, STAGING_SFX_CUES.get(cue, {}))
	for file: Variant in def.get("files", []):
		var stream: AudioStream = _sfx_streams.get(SFX_ROOT + String(file))
		if stream == null:
			continue
		for voice in _sfx_voices:
			if voice.playing and voice.stream == stream:
				voice.stop()


func _queue_ui_sound_hook(node: Node) -> void:
	if node is BaseButton or node is Slider or node is PopupMenu or node is ItemList or node is TabBar or node is TabContainer or (node is Control and node.has_signal("part_clicked")):
		call_deferred("_hook_ui_sound", node)


func _hook_existing_ui(node: Node) -> void:
	if not is_instance_valid(node):
		return
	_hook_ui_sound(node)
	for child in node.get_children():
		_hook_existing_ui(child)


func _hook_ui_sound(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is BaseButton:
		var callback := _ui_button_pressed.bind(node)
		if not node.pressed.is_connected(callback):
			node.pressed.connect(callback)
	elif node is Slider:
		var callback := _ui_slider_input.bind(node)
		if not node.gui_input.is_connected(callback):
			node.gui_input.connect(callback)
	elif node is PopupMenu:
		if not node.id_pressed.is_connected(_ui_choice_clicked):
			node.id_pressed.connect(_ui_choice_clicked)
	elif node is ItemList:
		if not node.item_clicked.is_connected(_ui_item_clicked):
			node.item_clicked.connect(_ui_item_clicked)
	elif node.has_signal("tab_clicked"):
		if not node.is_connected("tab_clicked", _ui_choice_clicked):
			node.connect("tab_clicked", _ui_choice_clicked)
	elif node is Control and node.has_signal("part_clicked"):
		if not node.is_connected("part_clicked", _ui_choice_clicked):
			node.connect("part_clicked", _ui_choice_clicked)


func _ui_clicked() -> void:
	play_sfx(&"ui_click")


func _ui_button_pressed(button: BaseButton) -> void:
	var cue: StringName = button.get_meta(UI_SOUND_META, &"ui_click") if is_instance_valid(button) else &"ui_click"
	play_sfx(cue)


func _ui_choice_clicked(_choice: Variant) -> void:
	_ui_clicked()


func _ui_item_clicked(_index: int, _position: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_ui_clicked()


func _ui_slider_input(event: InputEvent, slider: Slider) -> void:
	if slider.editable and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_ui_clicked()


func _sfx_pick_stream(cue: StringName, def: Dictionary) -> AudioStream:
	var files: Array = def.get("files", [])
	if files.is_empty():
		return null
	var index := 0
	if files.size() > 1:
		index = randi() % files.size()
		if index == int(_sfx_last_variant.get(cue, -1)):
			index = (index + 1) % files.size()
	_sfx_last_variant[cue] = index
	var path: String = SFX_ROOT + String(files[index])
	if not _sfx_streams.has(path):
		_sfx_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _sfx_streams[path]


## 音楽のスティングを 1 回鳴らす（STINGS）。素材がなければ何もしない。鳴っているあいだ BGM を下げる。
func play_sting(id: StringName) -> bool:
	var path: String = STINGS.get(id, "")
	if path.is_empty() or not ResourceLoader.exists(path) or _sting_player == null:
		return false
	var stream := load(path) as AudioStream
	if stream == null:
		return false
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	_sting_player.stream = stream
	_sting_player.volume_db = BGM_TRACK_GAIN_DB + BGM_MAX_GAIN_DB - 2.0
	_sting_player.play()
	_sting_ducked = true
	_apply_music_target(0.12)
	return true


func set_tutorial_ducked(ducked: bool, fade_seconds: float = 0.22) -> void:
	_tutorial_ducked = ducked
	_apply_music_target(fade_seconds)
	if _crowd_kind != CROWD_NONE:
		_fade_crowd(_crowd_kind, _crowd_target_db(_crowd_kind), fade_seconds, false)

func set_volume(vol: float) -> void:
	set_sfx_volume(vol)

func set_sfx_volume(vol: float, save_setting: bool = true) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_set_bus_linear_volume("SFX", sfx_volume)
	if save_setting:
		_save_audio_settings()

func set_bgm_volume(vol: float, save_setting: bool = true) -> void:
	bgm_volume = clampf(vol, 0.0, 1.0)
	_set_bus_volume_db("BGM", bgm_volume_to_db(bgm_volume) + _transition_db)
	if save_setting:
		_save_audio_settings()

func bgm_volume_to_db(vol: float) -> float:
	if vol <= 0.0:
		return -80.0
	var halvings: float = log(vol / BGM_DEFAULT_VOLUME) / log(1.0 / BGM_DEFAULT_VOLUME)
	return maxf(-80.0, BGM_MAX_GAIN_DB * halvings)

func _bgm_volume_from_db(gain_db: float) -> float:
	if gain_db <= -80.0:
		return 0.0
	return clampf(BGM_DEFAULT_VOLUME * pow(1.0 / BGM_DEFAULT_VOLUME, gain_db / BGM_MAX_GAIN_DB), 0.0, 1.0)

func set_music_context(context: StringName, fade_seconds: float = 0.4) -> void:
	if context != MUSIC_CONTEXT_PAUSED:
		_context_before_pause = context
	_music_context = context
	if not is_instance_valid(bgm_player) or _music_track == MUSIC_TRACK_NONE:
		return
	if not bgm_player.playing and bgm_player.stream != null:
		bgm_player.volume_db = -60.0
		bgm_player.play()
		_music_started = true
		fade_seconds = maxf(fade_seconds, 0.8)
	_apply_music_target(fade_seconds)


## Switches to another of MUSIC_TRACKS: the current one fades out and the new one starts from
## its head. Asking for the track that is already selected does nothing, so it keeps playing.
## MUSIC_TRACK_NONE fades the music out and keeps it silent (the game world before the start,
## where only the spectators are heard) until another track is selected.
func set_music_track(track: StringName, fade_seconds: float = MUSIC_TRACK_FADE_SECONDS) -> void:
	if track == _music_track or (track != MUSIC_TRACK_NONE and not _track_players.has(track)):
		return
	var old_track: StringName = _music_track
	var old_player: AudioStreamPlayer = _track_players.get(old_track)
	_music_track = track
	if is_instance_valid(_context_tween):
		_context_tween.kill()
	if old_player != null and old_player.playing:
		if is_instance_valid(_fade_out_tweens.get(old_track)):
			(_fade_out_tweens[old_track] as Tween).kill()
		var fade_out := create_tween()
		fade_out.tween_property(old_player, "volume_db", -60.0, fade_seconds)
		fade_out.tween_callback(old_player.stop)
		_fade_out_tweens[old_track] = fade_out
	if track == MUSIC_TRACK_NONE:
		return
	bgm_player = _track_players[track]
	if is_instance_valid(_fade_out_tweens.get(track)):
		(_fade_out_tweens[track] as Tween).kill()
	bgm_player.stop()
	# Music that has not started yet (boot) stays silent until the first set_music_context().
	if not _music_started:
		return
	bgm_player.volume_db = -60.0
	bgm_player.play()
	_apply_music_target(fade_seconds)


func get_music_context() -> StringName:
	return _music_context


func get_music_track() -> StringName:
	return _music_track


## Switches the spectator bed (CROWD_MURMUR, CROWD_RACE, or CROWD_NONE for silence). The old
## bed fades out and stops; the new one fades in from a random point so it never sounds
## like the same recording restarting. Asking for the current bed does nothing.
func set_crowd_ambience(kind: StringName, fade_seconds: float = CROWD_FADE_SECONDS) -> void:
	if kind == _crowd_kind or (kind != CROWD_NONE and not _crowd_players.has(kind)):
		return
	var old_kind := _crowd_kind
	_crowd_kind = kind
	if old_kind != CROWD_NONE:
		_fade_crowd(old_kind, -60.0, fade_seconds, true)
	if kind == CROWD_NONE:
		return
	var player: AudioStreamPlayer = _crowd_players[kind]
	if player.stream == null:
		return
	player.volume_db = -60.0
	player.play(randf() * maxf(player.stream.get_length() - 1.0, 0.0))
	_fade_crowd(kind, _crowd_target_db(kind), fade_seconds, false)


func get_crowd_ambience() -> StringName:
	return _crowd_kind


func _crowd_target_db(kind: StringName) -> float:
	return float(CROWD_AMBIENCES[kind].volume_db) - (6.0 if _tutorial_ducked else 0.0)


func _fade_crowd(kind: StringName, target_db: float, seconds: float, stop_after: bool) -> void:
	var player: AudioStreamPlayer = _crowd_players[kind]
	if is_instance_valid(_crowd_tweens.get(kind)):
		(_crowd_tweens[kind] as Tween).kill()
	var tween := create_tween()
	tween.tween_property(player, "volume_db", target_db, maxf(seconds, 0.01))
	if stop_after:
		tween.tween_callback(player.stop)
	_crowd_tweens[kind] = tween


func _apply_music_target(fade_seconds: float) -> void:
	if not is_instance_valid(bgm_player) or _music_track == MUSIC_TRACK_NONE:
		return
	var target_db: float = float(CONTEXT_VOLUME_DB.get(_music_context, 0.0)) + BGM_TRACK_GAIN_DB
	if _tutorial_ducked:
		target_db -= 6.0
	if _sting_ducked:
		target_db += STING_DUCK_DB
	if is_instance_valid(_context_tween):
		_context_tween.kill()
	if fade_seconds <= 0.0:
		bgm_player.volume_db = target_db
		return
	_context_tween = create_tween()
	_context_tween.set_trans(Tween.TRANS_SINE)
	_context_tween.set_ease(Tween.EASE_IN_OUT)
	_context_tween.tween_property(bgm_player, "volume_db", target_db, fade_seconds)


func set_music_paused(paused: bool) -> void:
	if paused:
		set_music_context(MUSIC_CONTEXT_PAUSED)
	else:
		set_music_context(_context_before_pause)
	# The spectators hold their breath while the game is paused.
	for kind: StringName in _crowd_players:
		(_crowd_players[kind] as AudioStreamPlayer).stream_paused = paused

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var bus_index: int = AudioServer.bus_count
	AudioServer.add_bus(bus_index)
	AudioServer.set_bus_name(bus_index, bus_name)


func _set_bus_linear_volume(bus_name: String, linear_volume: float) -> void:
	_set_bus_volume_db(bus_name, linear_to_db(linear_volume) if linear_volume > 0.0 else -80.0)

func _set_bus_volume_db(bus_name: String, volume_db: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(bus_index, volume_db)

func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	bgm_volume = clampf(float(config.get_value("audio", "bgm_volume", bgm_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	if int(config.get_value("audio", "version", 1)) < AUDIO_SETTINGS_VERSION:
		# Keep the loudness a v1 player chose; the slider just moves to the new curve.
		var v1_db: float = linear_to_db(bgm_volume) if bgm_volume > 0.0 else -80.0
		bgm_volume = snappedf(_bgm_volume_from_db(v1_db), 0.05)
		_save_audio_settings()

func _save_audio_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "version", AUDIO_SETTINGS_VERSION)
	config.set_value("audio", "bgm_volume", bgm_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.save(SETTINGS_PATH)
