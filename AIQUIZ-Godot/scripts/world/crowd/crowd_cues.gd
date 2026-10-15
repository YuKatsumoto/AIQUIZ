class_name CrowdCues
extends RefCounted

## What the crowd reacts to right now, shared by the goal stand and both side
## stands (docs/crowd_extras.md). game_world feeds it the game's events
## (countdown, start, a wrong door or a fall, lost HP, the saw and the sharks) and
## advances it once per frame; GoalStand and GrandstandCrowd read the snapshot.
##
## Layers, each with its own clock (seconds since it started):
## - cue: one game cue at a time (goal, verdict, countdown, start, miss, hurt),
##   faded in and out. Goal and verdict come from the goal stand's own reading of
##   the finish (GoalStand.side_crowd_reaction), the rest from game events.
## - shock: a local gasp around a point on the course (saw, shark, a fall).
## - wave: the stadium wave, started by the mascot on the right stand, up to the
##   goal stand, across it and back down the left stand. Lulls in play only.
## - chant: the cheer leaders' beat; their side's fans clap along.
## - sync: after the verdict the party people and some of the winner's fans dance
##   the winner's emote in step with the winner on the tower.

enum Cue { NONE, GOAL, VERDICT, COUNTDOWN, START, MISS, HURT }

const FADE_SECONDS := 0.35
const START_SECONDS := 2.6
const MISS_SECONDS := 3.2
const HURT_SECONDS := 2.2
const SHOCK_SECONDS := 3.6
## Priority of a cue over the one running (a verdict is never interrupted).
const PRIORITY := {Cue.NONE: 0, Cue.COUNTDOWN: 1, Cue.START: 2, Cue.HURT: 3, Cue.MISS: 4, Cue.GOAL: 5, Cue.VERDICT: 6}

const WAVE_SPEED := 16.0
const WAVE_FIRST_DELAY := 12.0
const WAVE_GAP := Vector2(42.0, 70.0)
## Half the goal stand's width: the wave crosses it at WAVE_SPEED.
const GOAL_STAND_HALF_WIDTH := 13.0
## SPEC_StandWave lasts 1.33 s; the wave is over once the last seat sat down.
const WAVE_CLIP_SECONDS := 1.4
## The right stand's mascot (and the wave's start) stands in the aisle of block 1.
const WAVE_ORIGIN := 20.0

const CHANT_SECONDS := 7.0
const CHANT_FIRST_DELAY := 24.0
const CHANT_GAP := Vector2(26.0, 44.0)
const CHANT_FADE_IN := 0.4
const CHANT_FADE_OUT := 0.6

## The winner starts dancing at ResultWinnerDance.START; the crowd joins in.
const SYNC_JOIN := 0.6

## Crowd clip for each emote (the floor moves have none: the crowd bounces).
const DANCE_CLIPS := {
	EmoteData.EMOTE_STEP_HIP_HOP: &"SPEC_Dance_StepHipHop",
	EmoteData.EMOTE_GANGNAM: &"SPEC_Dance_Gangnam",
	EmoteData.EMOTE_SLIDE_HIP_HOP: &"SPEC_Dance_SlideHipHop",
	EmoteData.EMOTE_FLAIR: &"SPEC_DanceBounce",
	EmoteData.EMOTE_MOONWALK: &"SPEC_Dance_Moonwalk",
	EmoteData.EMOTE_HIP_HOP: &"SPEC_Dance_HipHop",
	EmoteData.EMOTE_SILLY: &"SPEC_Dance_Silly",
	EmoteData.EMOTE_SWING: &"SPEC_Dance_Swing",
	EmoteData.EMOTE_THRILLER: &"SPEC_Dance_Thriller",
	EmoteData.EMOTE_YMCA: &"SPEC_Dance_YMCA",
	EmoteData.EMOTE_HOUSE: &"SPEC_Dance_House",
	EmoteData.EMOTE_HIP_HOP_1: &"SPEC_Dance_HipHop2",
	EmoteData.EMOTE_HEAD_SPINNING: &"SPEC_DanceBounce",
	EmoteData.EMOTE_RUNNING_MAN: &"SPEC_Dance_RunningMan",
	EmoteData.EMOTE_HOKEY_POKEY: &"SPEC_Dance_HokeyPokey",
	EmoteData.EMOTE_WAVE_HIP_HOP: &"SPEC_Dance_WaveHipHop",
}

var clock := 0.0
## Two players: the rival's fans laugh when a player misses.
var two_players := true
## World z of the side stands' back end, and the goal stand's front along the course.
var course_z := 0.0
var goal_course := 200.0

var cue := Cue.NONE
var cue_team := 0
var cue_started := 0.0
var cue_until := INF

var shock_course := 0.0
var shock_started := -INF

var wave_started := -INF
var wave_origin := WAVE_ORIGIN
var _next_wave := INF

var chant_team := 0
var chant_started := -INF
var chant_until := -INF
var _next_chant := INF
var _chant_side := 1

## Crowd dance per side (1 = right stand / P1, 2 = left / P2) while the winner dances.
var sync_clips := {1: &"", 2: &""}
var sync_team := 0
var sync_elapsed := -1.0
var sync_weight := 0.0

var _rng := RandomNumberGenerator.new()
var _state_name := ""
var _held := Cue.NONE


func _init(seed_value: int = 0x5EA7) -> void:
	_rng.seed = seed_value


# ------------------------------------------------------------------ events

func on_countdown_started() -> void:
	_hold(Cue.COUNTDOWN, 0)


func on_start() -> void:
	_fire(Cue.START, 0, START_SECONDS)


## A player chose the wrong door, fell into the sea or was caught by the saw.
func on_miss(player: int) -> void:
	_fire(Cue.MISS, player, MISS_SECONDS)


## A player lost HP (still in the race).
func on_hurt(player: int) -> void:
	_fire(Cue.HURT, player, HURT_SECONDS)


## Something dramatic happened at world z `z`: the nearby crowd gasps.
func on_shock(world_z: float) -> void:
	shock_course = world_z - course_z
	shock_started = clock


func _fire(kind: Cue, team: int, seconds: float) -> void:
	if cue_weight() > 0.05 and PRIORITY[kind] < PRIORITY[cue] and cue_until > clock:
		return
	cue = kind
	cue_team = team
	cue_started = clock
	cue_until = clock + seconds


## A cue that lasts while a game state lasts (countdown, goal, verdict).
func _hold(kind: Cue, team: int) -> void:
	_held = kind
	if cue == kind and cue_team == team and cue_until == INF:
		return
	if cue_weight() > 0.05 and PRIORITY[kind] < PRIORITY[cue] and cue_until > clock:
		return
	cue = kind
	cue_team = team
	cue_started = clock
	cue_until = INF


func _release(kind: Cue) -> void:
	if cue == kind and cue_until == INF:
		cue_until = clock + FADE_SECONDS
	if _held == kind:
		_held = Cue.NONE


# ------------------------------------------------------------------ per frame

## `reaction` is GoalStand.side_crowd_reaction() (goal arrivals and the verdict).
## `director` is the ResultCeremonyDirector (result clock) or null.
func update(delta: float, state: QuizGameState, reaction: Dictionary = {}, director: Node = null) -> void:
	clock += delta
	if state == null:
		return
	two_players = state.num_players >= 2
	var state_name := String(state.game_state)
	if state_name != _state_name:
		_on_state(state_name)
		_state_name = state_name
	# The goal stand reads the finish: arrivals (a short burst) and the verdict.
	var amount := float(reaction.get("amount", 0.0))
	var kind := Cue.VERDICT if bool(reaction.get("verdict", false)) else Cue.GOAL
	if amount > 0.0:
		_hold(kind, int(reaction.get("team", 0)))
	else:
		_release(Cue.GOAL)
		_release(Cue.VERDICT)
	if state_name != Constants.STATE_COUNTDOWN:
		_release(Cue.COUNTDOWN)
	if cue != Cue.NONE and clock > cue_until:
		cue = Cue.NONE
	_update_wave(state_name)
	_update_chant(state_name)
	_update_sync(state, director)


func _on_state(state_name: String) -> void:
	match state_name:
		Constants.STATE_COUNTDOWN:
			on_countdown_started()
		Constants.STATE_PLAYING:
			if _state_name in [Constants.STATE_COUNTDOWN, Constants.STATE_FLYOVER, Constants.STATE_WAITING_START]:
				_release(Cue.COUNTDOWN)
				on_start()
				_next_wave = clock + WAVE_FIRST_DELAY
				_next_chant = clock + CHANT_FIRST_DELAY
		Constants.STATE_MENU, Constants.STATE_WAITING_START:
			_next_wave = INF
			_next_chant = INF
			wave_started = -INF
			chant_until = -INF


func _update_wave(state_name: String) -> void:
	if wave_time() < 0.0 and wave_started > -INF:
		wave_started = -INF
	var lull := state_name in [Constants.STATE_PLAYING, Constants.STATE_CORRECT]
	if not lull:
		return
	if wave_started == -INF and clock >= _next_wave and not chant_active():
		wave_started = clock
		_next_wave = clock + wave_seconds() + _rng.randf_range(WAVE_GAP.x, WAVE_GAP.y)


func _update_chant(state_name: String) -> void:
	if state_name == Constants.STATE_GOAL_RACE:
		# Both sides chant while the players race for the line.
		if chant_until < clock + 1.0:
			if not chant_active():
				chant_started = clock
			chant_team = 0
			chant_until = clock + 1.5
		return
	var lull := state_name in [Constants.STATE_PLAYING, Constants.STATE_CORRECT]
	if lull and clock >= _next_chant and not chant_active() and wave_time() < 0.0:
		chant_started = clock
		chant_until = clock + CHANT_SECONDS
		chant_team = _chant_side if two_players else 0
		_chant_side = 3 - _chant_side
		_next_chant = chant_until + _rng.randf_range(CHANT_GAP.x, CHANT_GAP.y)


func _update_sync(state: QuizGameState, director: Node) -> void:
	sync_elapsed = -1.0
	sync_weight = 0.0
	if not state.result_presentation_active or director == null or not director.has_method("result_elapsed"):
		return
	var elapsed: float = director.result_elapsed()
	var start := ResultWinnerDance.START
	if elapsed < start:
		return
	sync_team = state.result_winner
	for side: int in [1, 2]:
		sync_clips[side] = crowd_dance_for(state.get_result_winner_emote(side))
	sync_elapsed = elapsed - start
	sync_weight = smoothstep(start, start + SYNC_JOIN, elapsed)
	if state.sudden_death_pending:
		# The whistle stops the draw dance (ResultFinaleStage does the same).
		var branch := QuizGameState.SUDDEN_DEATH_BRANCH_TIME
		sync_weight *= 1.0 - smoothstep(branch, branch + 0.35, elapsed)


static func crowd_dance_for(emote: int) -> StringName:
	return DANCE_CLIPS.get(EmoteData.normalize_emote_id(emote), &"SPEC_DanceBounce")


static var _clip_meta := {}


## The crowd clip's time for `elapsed` seconds of the winner's dance. The source
## FBX can be one 60 fps frame longer than the 30 fps crowd clip, so the loop is
## taken on the source length ("source_seconds") and scaled onto the clip.
static func dance_time(clip: StringName, elapsed: float) -> float:
	if elapsed < 0.0 or clip == &"":
		return -1.0
	if _clip_meta.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/goal_stand/goal_stand_clips.json"))
		_clip_meta = (parsed as Dictionary).get("clips", {}) if parsed is Dictionary else {}
	var info: Dictionary = _clip_meta.get(String(clip), {})
	var crowd := float(info.get("seconds", 1.0))
	var source := maxf(float(info.get("source_seconds", crowd)), 0.01)
	return fposmod(elapsed, source) * crowd / source


## The crowd clip that slot `side` dances: the winner's for both sides, or each
## side its own player's after a draw.
func sync_clip_for(side: int) -> StringName:
	return sync_clips[side] if sync_team == 0 else sync_clips[sync_team]


# ------------------------------------------------------------------ snapshot

func cue_time() -> float:
	return clock - cue_started


func cue_weight() -> float:
	if cue == Cue.NONE:
		return 0.0
	var fade_in := smoothstep(cue_started, cue_started + FADE_SECONDS, clock)
	var fade_out := 1.0 if cue_until == INF else 1.0 - smoothstep(cue_until - FADE_SECONDS, cue_until, clock)
	return clampf(fade_in * fade_out, 0.0, 1.0)


## Seconds since the shock, or -1.
func shock_time() -> float:
	var since := clock - shock_started
	return since if since >= 0.0 and since < SHOCK_SECONDS else -1.0


## Seconds from the wave leaving the mascot until the last seat sat down.
func wave_seconds() -> float:
	return (goal_course - wave_origin) / WAVE_SPEED + wave_cross() + goal_course / WAVE_SPEED + WAVE_CLIP_SECONDS


func wave_cross() -> float:
	return 2.0 * GOAL_STAND_HALF_WIDTH / WAVE_SPEED


## Seconds since the wave started, or -1 when no wave is running.
func wave_time() -> float:
	var since := clock - wave_started
	return since if since >= 0.0 and since < wave_seconds() else -1.0


## When the wave reaches a seat `along` the course on the right (+X) or left stand
## (seated_spectator.gdshader does the same per spectator).
func wave_arrival_side(right: bool, along: float) -> float:
	if right:
		return INF if along < wave_origin else (along - wave_origin) / WAVE_SPEED
	return (goal_course - wave_origin) / WAVE_SPEED + wave_cross() + absf(goal_course - along) / WAVE_SPEED


## When the wave reaches world x `x` along the goal stand (it crosses from +X to -X).
func wave_arrival_goal_stand(x: float) -> float:
	return (goal_course - wave_origin) / WAVE_SPEED + (GOAL_STAND_HALF_WIDTH - x) / WAVE_SPEED


func chant_active() -> bool:
	return clock < chant_until + CHANT_FADE_OUT and chant_started <= clock and chant_started > -INF


## Seconds on the leaders' beat (0 = a beat), or -1.
func chant_time() -> float:
	return clock - chant_started if chant_active() else -1.0


func chant_weight() -> float:
	if not chant_active():
		return 0.0
	return smoothstep(chant_started, chant_started + CHANT_FADE_IN, clock) \
		* (1.0 - smoothstep(chant_until, chant_until + CHANT_FADE_OUT, clock))


func snapshot() -> Dictionary:
	return {"cue": Cue.keys()[cue], "cue_team": cue_team, "cue_weight": snappedf(cue_weight(), 0.01),
		"shock": snappedf(shock_time(), 0.01), "wave": snappedf(wave_time(), 0.01), "chant": snappedf(chant_time(), 0.01),
		"chant_team": chant_team, "sync": snappedf(sync_elapsed, 0.01), "sync_weight": snappedf(sync_weight, 0.01),
		"sync_clips": [String(sync_clip_for(1)), String(sync_clip_for(2))]}
