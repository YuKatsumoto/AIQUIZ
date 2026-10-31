class_name CrowdMood
extends RefCounted

## How the match feels to the side stands' crowd (docs/crowd_sim.md): how worth
## watching it is right now, and how each player's fans feel about their player.
## game_world feeds it the same events as CrowdCues and advances it every frame;
## CrowdSim reads it to decide who comes, who goes for a snack and who leaves.
##
## - interest (0..1): a close match, a player down to the last heart and every
##   answer keep it up; a long lull or a lopsided match let it sink. The goal race
##   and sudden death hold it at 1, and then nobody leaves their seat (hurry).
## - morale (per team, 0..1): a player's right answers and the rival's misses
##   lift that player's fans; misses, lost hearts and falling out sink them.
## - after the match (finished): nobody comes any more. The loser's fans and some
##   neutrals go home once the winner dances (exodus_team); after a lost game
##   with no rival (one player, co-op, endless) some of everybody goes.

const BASE_INTEREST := 0.55
## Nothing happened for this long: the match starts to drag.
const LULL_AFTER := 15.0
const LULL_RATE := 0.012
const LULL_MAX := 0.3
const CLOSE_BONUS := 0.1
const PINCH_BONUS := 0.15
const LOPSIDED_DROP := 0.25
## An event's lift fades this fast (per second).
const SPIKE_DECAY := 0.03
const RISE_RATE := 0.25
const FALL_RATE := 0.04
const MORALE_START := 0.6
const MORALE_REST := 0.55
const MORALE_RECOVER := 0.004
## The ceremony and the result screen hold the crowd that stays.
const FINISHED_INTEREST := 0.9
## No winner's dance to follow (no director): the loser's fans go this long into the result.
const RESULT_FALLBACK := 9.0
## A lost game without a rival: people start going home this long after it.
const GAME_OVER_DELAY := 4.0
const FINISHED_STATES: Array[String] = [Constants.STATE_RESULT_CEREMONY, Constants.STATE_CLEAR, Constants.STATE_GAME_OVER]

var interest := BASE_INTEREST
var morale := {1: MORALE_START, 2: MORALE_START}
## The goal race or sudden death: everyone hurries back to their seat.
var hurry := false
## Counts matches: a new one starts with a fresh crowd.
var match_serial := 0
## Players in the match (1: both stands follow P1) and whether they play together.
var players := 2
var coop := false
## The match is over (the ceremony, the result screen, game over).
var finished := false
## Whose fans go home now: -1 nobody, 0 some of everybody, 1 / 2 that player's
## (the rival won), and how long they have been going.
var exodus_team := -1
var exodus_since := 0.0
var _result_for := 0.0
var _spike := 0.0
var _quiet := 0.0
var _state_name := ""


func on_correct(player: int) -> void:
	_event(0.08)
	_lift(player, 0.12)


## A wrong door.
func on_miss(player: int) -> void:
	_event(0.05)
	_lift(player, -0.12)
	_lift(3 - player, 0.05)


func on_hurt(player: int) -> void:
	_event(0.04)
	_lift(player, -0.08)


## Fell into the sea, eaten by a shark or caught by the saw: out of the match.
func on_out(player: int) -> void:
	_event(0.1)
	_lift(player, -0.4)
	_lift(3 - player, 0.1)


## `cues`: the crowd's cues, to start the loser's exodus with the winner's dance.
func update(delta: float, state: QuizGameState, cues: CrowdCues = null) -> void:
	if state == null:
		return
	var state_name := String(state.game_state)
	if state_name != _state_name:
		_on_state(state_name)
	players = maxi(1, int(state.num_players))
	coop = String(state.mode) == Constants.MODE_COOP
	hurry = state_name in [Constants.STATE_GOAL_RACE, Constants.STATE_SUDDEN_DEATH]
	finished = state_name in FINISHED_STATES
	_update_exodus(delta, state, state_name, cues)
	_quiet += delta
	var target := BASE_INTEREST
	var alive1 := bool(state.p1_alive)
	var alive2 := bool(state.p2_alive) or players < 2
	var hp1 := int(state.p1_hp)
	var hp2 := int(state.p2_hp) if players >= 2 else hp1
	if (alive1 and hp1 == 1) or (players >= 2 and alive2 and hp2 == 1):
		target += PINCH_BONUS
	if players >= 2 and not coop:
		if alive1 != alive2 or absi(hp1 - hp2) >= 2:
			target -= LOPSIDED_DROP
		elif hp1 == hp2:
			target += CLOSE_BONUS
	if _quiet > LULL_AFTER:
		target -= minf(LULL_MAX, (_quiet - LULL_AFTER) * LULL_RATE)
	if hurry:
		target = 1.0
	elif finished:
		target = FINISHED_INTEREST
	target = clampf(target + _spike, 0.0, 1.0)
	interest = move_toward(interest, target, delta * (RISE_RATE if target > interest else FALL_RATE))
	_spike = move_toward(_spike, 0.0, SPIKE_DECAY * delta)
	for team: int in [1, 2]:
		morale[team] = move_toward(float(morale[team]), MORALE_REST, MORALE_RECOVER * delta)


## How a team's fans feel: one player moves both stands, a co-op pair moves them together.
func morale_for(team: int) -> float:
	if team == 0:
		return 0.5
	if players < 2:
		return float(morale[1])
	if coop:
		return (float(morale[1]) + float(morale[2])) * 0.5
	return float(morale[team])


## Starts a fresh match: the crowd forgets the last one.
func reset() -> void:
	interest = BASE_INTEREST
	morale = {1: MORALE_START, 2: MORALE_START}
	hurry = false
	finished = false
	exodus_team = -1
	exodus_since = 0.0
	_result_for = 0.0
	_spike = 0.0
	_quiet = 0.0
	match_serial += 1


func snapshot() -> Dictionary:
	return {"interest": snappedf(interest, 0.01), "morale1": snappedf(float(morale[1]), 0.01),
		"morale2": snappedf(float(morale[2]), 0.01), "hurry": hurry, "quiet": snappedf(_quiet, 0.1),
		"finished": finished, "exodus": exodus_team, "match": match_serial}


## After the match: in a two-player match the loser's fans go once the winner
## dances (or a while into the result, without a dance to follow); a draw goes
## to sudden death first. A lost game with nobody to beat (one player, co-op,
## an endless match) sends some of everybody home.
func _update_exodus(delta: float, state: QuizGameState, state_name: String, cues: CrowdCues) -> void:
	if not finished:
		exodus_team = -1
		exodus_since = 0.0
		_result_for = 0.0
		return
	_result_for += delta
	var team := -1
	if players >= 2 and not coop and bool(state.result_presentation_active):
		var winner := int(state.result_winner)
		var dancing := cues != null and cues.sync_elapsed >= 0.0
		if (winner == 1 or winner == 2) and not bool(state.sudden_death_pending) and (dancing or _result_for > RESULT_FALLBACK):
			team = 3 - winner
	elif state_name == Constants.STATE_GAME_OVER and _result_for > GAME_OVER_DELAY:
		team = 0
	if team != exodus_team:
		exodus_team = team
		exodus_since = 0.0
	elif team != -1:
		exodus_since += delta


func _on_state(state_name: String) -> void:
	var was_over := _state_name in ["", Constants.STATE_MENU, Constants.STATE_CLEAR, Constants.STATE_GAME_OVER,
		Constants.STATE_RESULT_CEREMONY]
	if state_name in [Constants.STATE_WAITING_START, Constants.STATE_PRELOADING] \
			or (state_name == Constants.STATE_COUNTDOWN and was_over):
		if _state_name not in [Constants.STATE_WAITING_START, Constants.STATE_PRELOADING]:
			reset()
	_state_name = state_name


func _event(lift: float) -> void:
	_quiet = 0.0
	_spike = minf(0.3, _spike + lift)


func _lift(team: int, amount: float) -> void:
	if team == 1 or team == 2:
		morale[team] = clampf(float(morale[team]) + amount, 0.0, 1.0)
