class_name MatchReel
extends Node

## Keeps the match being played for the LED programme on the goal stand scoreboard
## (MenuLedProgram, played after the winner's cut-in once is_ready()).
##
## Counts every player's answers and streaks, marks highlight moments for
## HighlightCapture (streaks, close calls with the saw, falls into the sea and the
## shark's bite, ghost shark hits, push hits, eliminations, the finale verdict, the
## moment a local 2P sudden death is decided underground, a 1P clear), and once the
## match ends (after a sudden death, at its final clear_game()) appends it to
## MatchHistory with its clips in
## HighlightStore: every moment of the match, up to MAX_CLIPS (the highest priority
## ones when there are more), which the menu replays in match order. GameWorld
## creates one per match (not for replays or the tutorial) and forwards state changes.
## A match left through the pause menu is not recorded.

const MAX_CLIPS := 16
const STREAK_MARKS: Array[int] = [3, 5, 7, 10]
## Saw clearance (m, 0 = touching) that counts as a close call once the player gets away.
const NEAR_MISS_CLEARANCE := 0.45
const NEAR_MISS_ESCAPED := 2.0
## After the match ends, clips still collecting frames get this long before the
## record is written without them.
const END_TIMEOUT := 6.0

const PRIORITY := {
	"sudden_death": 94, "win": 90, "draw": 86, "perfect": 88, "goal": 76, "ghost_hit": 72, "clear": 70,
	"near_miss": 62, "shark": 60, "ocean": 58, "saw": 55, "push": 38, "out": 30,
}
## Seconds of the sudden death's deciding clip after the moment: the loser's lift goes
## under and the current takes them (SuddenDeathTuning.plunge_time and a beat).
const SUDDEN_DEATH_POST := {"correct": 2.4, "wrong": 2.4, "late": 2.4}

var game_state: QuizGameState
var capture: HighlightCapture
var online := false
var host := false

var _players: Array[Dictionary] = []
var _near: Array[float] = [INF, INF]
var _ended := false
var _end_state := ""
var _end_age := 0.0
var _committed := false
var _clips: Array[Dictionary] = []
var _match_id := HighlightStore.new_id()
static var _write_task := -1


func setup(state: QuizGameState, quality: String, is_online: bool, is_host: bool) -> void:
	name = "MatchReel"
	game_state = state
	online = is_online
	host = is_host
	for index in range(2):
		_players.append({"correct": 0, "attempted": 0, "streak": 0, "best_streak": 0})
	capture = HighlightCapture.new()
	add_child(capture)
	capture.configure(quality)
	capture.clip_ready.connect(_on_clip_ready)
	game_state.correct_answer.connect(_on_correct_answer)
	game_state.question_winner_decided.connect(_on_question_winner_decided)
	game_state.player_caught_by_saw.connect(_on_player_caught_by_saw)
	game_state.player_entered_ocean.connect(_on_player_entered_ocean)
	game_state.local_push_event.connect(_on_local_push_event)
	game_state.result_ceremony_phase_changed.connect(_on_result_ceremony_phase_changed)
	game_state.health_changed.connect(_on_health_changed)
	game_state.player_scrolled_out.connect(_on_player_scrolled_out)
	game_state.sudden_death_event.connect(_on_sudden_death_event)


## The ghost shark a knocked-out player rides at the survivor (created after the reel).
func watch_ghost_rides(controller: Node) -> void:
	if controller != null and controller.has_signal("charge_resolved"):
		controller.connect("charge_resolved", _on_ghost_charge_resolved)


## Called from GameWorld._on_state_changed.
func notify_state(new_state: String) -> void:
	if _ended:
		return
	if new_state == Constants.STATE_CLEAR or (
		new_state == Constants.STATE_GAME_OVER and not game_state.is_elimination_result_pending()
	):
		_ended = true
		_end_state = new_state
		_mark_ending()


func _process(delta: float) -> void:
	if game_state == null:
		return
	var state := game_state.game_state
	# The capture clock also runs underground, so the sudden death's deciding moment
	# finds its run-up in the ring buffer.
	capture.recording = capture.has_pending() or state in [
		Constants.STATE_PLAYING, Constants.STATE_GOAL_RACE, Constants.STATE_RESULT_CEREMONY,
		Constants.STATE_SUDDEN_DEATH,
	]
	if state == Constants.STATE_PLAYING and game_state.uses_saw_chase():
		_watch_saw()
	if _ended and not _committed:
		_end_age += delta
		if not capture.is_busy():
			_commit()
		elif _end_age > END_TIMEOUT:
			capture.finish_now()
			_commit()


func _exit_tree() -> void:
	if _ended and not _committed and capture != null:
		capture.finish_now()
		_commit()


# ---------------------------------------------------------------- moments

func _mark(kind: String, player: int, pre: float, post: float, extra: Dictionary = {}) -> void:
	var moment := {"kind": kind, "player": player, "priority": int(PRIORITY.get(kind, 40))}
	moment.merge(extra)
	capture.mark(moment, pre, post)


func _on_correct_answer() -> void:
	if game_state.num_players >= 2:
		return # Per player through question_winner_decided.
	var streak := game_state.current_streak
	if streak in STREAK_MARKS:
		_mark_streak(1, streak)


func _on_question_winner_decided(_index: int, winner_mask: int) -> void:
	if game_state.num_players < 2:
		return
	var faced := game_state.get_question_evaluated_mask() | winner_mask
	for player_index: int in [1, 2]:
		var bit := 1 << (player_index - 1)
		if faced & bit == 0:
			continue
		var stats: Dictionary = _players[player_index - 1]
		stats.attempted += 1
		if winner_mask & bit:
			stats.correct += 1
			stats.streak += 1
			stats.best_streak = maxi(stats.best_streak, stats.streak)
			if int(stats.streak) in STREAK_MARKS:
				_mark_streak(player_index, stats.streak)
		else:
			stats.streak = 0


static func priority_of(moment: Dictionary) -> int:
	if moment.get("kind") == "streak":
		return 40 + 4 * int(moment.get("streak", 3))
	return int(PRIORITY.get(moment.get("kind", ""), 40))


func _mark_streak(player_index: int, streak: int) -> void:
	# The clip opens on the run-up to the wall and ends on the landing.
	var moment := {"kind": "streak", "player": player_index, "priority": 40 + 4 * streak, "streak": streak}
	capture.mark(moment, 2.0, 1.0)


func _watch_saw() -> void:
	for player_index: int in [1, 2]:
		var clearance := game_state.get_saw_clearance(player_index)
		var closest := _near[player_index - 1]
		if clearance < closest:
			_near[player_index - 1] = clearance
		elif closest <= NEAR_MISS_CLEARANCE and clearance >= NEAR_MISS_ESCAPED and clearance < INF:
			_near[player_index - 1] = INF
			_mark("near_miss", player_index, 2.2, 0.6)
		elif clearance == INF or clearance >= NEAR_MISS_ESCAPED:
			_near[player_index - 1] = INF


func _on_player_caught_by_saw(player_index: int) -> void:
	_near[player_index - 1] = INF
	_mark("saw", player_index, 1.8, 1.4)


func _on_player_entered_ocean(player_index: int, _position: Vector3) -> void:
	# The clip keeps running while the shark comes: the bite extends it (_on_health_changed).
	_mark("ocean", player_index, 1.5, 3.0)
	_follow_wipe(player_index, HighlightCapture.MAX_CLIP_SECONDS)


## In 2P the match camera stays on the runner still racing; the death wipe shows the
## fallen player sinking and the shark, so the clip is shot from there.
func _follow_wipe(player_index: int, seconds: float) -> void:
	if game_state.num_players < 2 or not (game_state.p2_alive if player_index == 1 else game_state.p1_alive):
		return
	var wipe := get_parent().get_node_or_null("DeathWipeLayer/DeathWipe")
	var camera: Variant = wipe.get("wipe_camera") if wipe != null else null
	if camera is Camera3D:
		capture.follow(camera, seconds)


## Knocked out. The saw has its own signal; a player still waiting for the shark was
## bitten (the flag clears after this signal); otherwise a wall ended the run.
func _on_health_changed(player_index: int, previous_hp: int, hp: int) -> void:
	if hp > 0 or previous_hp <= 0 or game_state.is_replay:
		return
	if game_state.is_player_waiting_for_shark(player_index):
		_mark("shark", player_index, 1.2, 1.8)
		_follow_wipe(player_index, 1.8)
	elif not (game_state.p1_saw_killed if player_index == 1 else game_state.p2_saw_killed):
		_mark("out", player_index, 2.0, 1.2)


func _on_player_scrolled_out(player_index: int) -> void:
	_mark("out", player_index, 2.0, 1.0)


func _on_ghost_charge_resolved(player_index: int, hit: bool, _power: float) -> void:
	if hit:
		_mark("ghost_hit", player_index, 2.6, 1.8)


func _on_local_push_event(event: Dictionary) -> void:
	if str(event.get("kind", "")) == "hit":
		_mark("push", int(event.get("player", 0)), 1.2, 1.2)


func _on_result_ceremony_phase_changed(phase: int) -> void:
	if phase == QuizGameState.ResultCeremonyPhase.EFFECT:
		var winner := game_state.result_winner
		_mark("draw" if winner == 0 else "win", winner, 1.4, 2.6)


## The sudden death after a draw (docs/sudden_death_underground.md): the moment it is
## decided (the answer that sends the loser's lift under) is the strongest moment of the match.
func _on_sudden_death_event(event: Dictionary) -> void:
	if str(event.get("kind", "")) != "decided":
		return
	var by := str(event.get("by", ""))
	_mark("sudden_death", int(event.get("winner", 0)), 2.4, float(SUDDEN_DEATH_POST.get(by, 2.0)),
		{"by": by, "question": int(event.get("index", 0)) + 1})


func _mark_ending() -> void:
	if _end_state != Constants.STATE_CLEAR or game_state.uses_local_result_ceremony():
		return
	if game_state.num_players >= 2:
		if game_state.goal_winner > 0:
			_mark("goal", game_state.goal_winner, 2.2, 1.4)
	elif game_state.mode == Constants.MODE_TEN:
		_mark("perfect" if game_state.score >= game_state.target_count else "clear", 1, 2.2, 1.4,
			{"correct": game_state.score, "target": game_state.target_count})


func _on_clip_ready(clip: Dictionary) -> void:
	_clips.append(clip)


# ---------------------------------------------------------------- record

func build_record() -> Dictionary:
	var gs := game_state
	var ceremony := gs.uses_local_result_ceremony() and gs.result_presentation_active
	var players: Array[Dictionary] = []
	for player_index in range(1, gs.num_players + 1):
		var entry := {
			"correct": gs.score if player_index == 1 else gs.player2_score,
			"hp": gs.get_player_hp(player_index),
			"alive": gs.p1_alive if player_index == 1 else gs.p2_alive,
		}
		if ceremony:
			# The finale froze each finisher's values at the goal.
			entry["correct"] = gs.result_p1_correct_count if player_index == 1 else gs.result_p2_correct_count
			entry["hp"] = gs.result_p1_hp if player_index == 1 else gs.result_p2_hp
			entry["alive"] = not gs.is_result_ghost(player_index)
		if gs.num_players >= 2:
			var stats: Dictionary = _players[player_index - 1]
			entry["attempted"] = maxi(int(stats.attempted), int(entry.correct))
			entry["best_streak"] = stats.best_streak
		else:
			entry["attempted"] = maxi(gs.total_answered, int(entry.correct))
			entry["best_streak"] = gs.max_streak
		players.append(entry)
	var winner := -1
	var points: Array[int] = []
	if ceremony:
		points = [gs.result_p1_score, gs.result_p2_score]
		winner = gs.result_winner
	elif gs.num_players >= 2:
		if _end_state == Constants.STATE_CLEAR and gs.goal_winner > 0:
			winner = gs.goal_winner
		else:
			winner = 0 if gs.score == gs.player2_score else (1 if gs.score > gs.player2_score else 2)
	var record := {
		"id": _match_id,
		"ts": int(Time.get_unix_time_from_system()),
		"mode": gs.mode,
		"players": gs.num_players,
		"online": online,
		"host": host,
		"subject": gs.subject,
		"grade": gs.grade,
		"difficulty": gs.difficulty,
		"target": gs.target_count,
		"end": _end_state,
		"time": snappedf(gs.play_time, 0.1),
		"p": players,
		"points": points,
		"winner": winner,
		"highlights": [],
	}
	if gs.sudden_death_winner > 0:
		# The finale's draw was settled underground; the points stay level.
		record["sudden_death"] = {
			"questions": gs.sudden_death_question_count,
			"by": gs.sudden_death_decided_by,
			"winner": gs.sudden_death_winner,
		}
	return record


## Every clip of the match (the MAX_CLIPS highest priority ones when there are more),
## in match order, goes to HighlightStore, then the record to MatchHistory. File
## writing runs on a worker thread.
func _commit() -> void:
	_committed = true
	var record := build_record()
	var chosen := _clips.duplicate()
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.priority) > int(b.priority))
	chosen = chosen.slice(0, MAX_CLIPS)
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.at) < float(b.at))
	var stored: Array = []
	for order in range(chosen.size()):
		var clip: Dictionary = chosen[order]
		var events: Array = clip.events
		var lead: Dictionary = events[0]
		for event: Dictionary in events:
			if priority_of(event) > priority_of(lead):
				lead = event
		var entry := {
			"id": "%s_%02d" % [_match_id, order],
			"ts": float(record.ts) + order * 0.01,
			"match": _match_id,
			"order": order,
			"at": clip.at,
			"mode": record.mode,
			"players": record.players,
			"online": record.online,
			"times": clip.times,
			"events": events,
			"size": clip.size,
			# The strongest moment names the clip (older readers use these).
			"kind": lead.get("kind", ""),
			"player": lead.get("player", 0),
			"event": lead.get("t", 0.0),
		}
		if lead.has("streak"):
			entry["streak"] = lead.streak
		stored.append({"entry": entry, "jpegs": clip.jpegs})
		(record.highlights as Array).append(entry.id)
	wait_for_write()
	_write_task = WorkerThreadPool.add_task(MatchReel._write.bind(record, stored), false, "Match record")


## True once this match's record and clips are on disk, so the history can be read
## (MenuLedProgram.setup) without wait_for_write() blocking the frame.
func is_ready() -> bool:
	return _committed and not MatchReel.is_write_pending()


## A record is still being written on the worker thread.
static func is_write_pending() -> bool:
	return _write_task >= 0 and not WorkerThreadPool.is_task_completed(_write_task)


## The last match's files are on disk once this returns (the programme calls it before
## reading the history; it also releases the finished worker task).
static func wait_for_write() -> void:
	if _write_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_write_task)
		_write_task = -1


static func _write(record: Dictionary, clips: Array) -> void:
	HighlightStore.add_clips(clips)
	MatchHistory.append(record)
