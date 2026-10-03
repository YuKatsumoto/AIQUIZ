class_name MatchHistory
extends RefCounted

## Finished matches of this game session (user://match_history.json, newest last).
## MatchReel appends one record when a match ends; the LED programme on the goal stand
## scoreboard (MenuLedProgram) reads them back for the last match, the history and the
## all-time tiles. GameManager clear()s the file at every launch, so the LED only shows
## matches played since the game was started.
##
## Record (VERSION 2):
##   id, ts (unix seconds), mode, players, online, host,
##   subject, grade, difficulty, target, end ("CLEAR" | "GAME_OVER"), time (seconds),
##   p: one {correct, attempted, best_streak, hp, alive} per player,
##   points: local 2P finale totals in half points ([p1, p2]) or [],
##   winner: 0 draw, 1 / 2 that player, -1 none (1P, or nobody won),
##   highlights: ids of this match's clips in HighlightStore,
##   sudden_death (VERSION 2, only when a local 2P draw was settled underground):
##     {rows: gate rows reached 1-6, 7 = the exit ladders; by: "gate" | "wave" | "ladder";
##     winner: 1 / 2}. The points stay level; winner is the sudden death's.
## VERSION 1 records (no sudden_death) read the same way.

const PATH := "user://match_history.json"
const MAX_RECORDS := 200
const VERSION := 2

## Tests point the history somewhere else.
static var path_override := ""


static func path() -> String:
	return path_override if not path_override.is_empty() else PATH


static func load_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var parsed := read_json(path())
	var list: Variant = parsed.get("matches")
	if list is Array:
		for item: Variant in list:
			if item is Dictionary:
				records.append(item)
	return records


static func append(record: Dictionary) -> bool:
	var records := load_records()
	records.append(record)
	if records.size() > MAX_RECORDS:
		records = records.slice(records.size() - MAX_RECORDS)
	return write_json(path(), {"version": VERSION, "matches": records})


## Forgets every record (at launch, see GameManager).
static func clear() -> void:
	for file_path: String in [path(), path() + ".tmp"]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))


## The newest record, or {} when nothing was played yet.
static func latest(records: Array[Dictionary]) -> Dictionary:
	return records[records.size() - 1] if not records.is_empty() else {}


## All-time figures for the LED tiles.
##   matches, best_correct (most correct answers by one player in one match),
##   correct / attempted (every player, every match), accuracy 0..1,
##   wins: [P1 wins, P2 wins] over local 2P matches.
static func summary(records: Array[Dictionary]) -> Dictionary:
	var best := 0
	var correct := 0
	var attempted := 0
	var wins := [0, 0]
	for record: Dictionary in records:
		for player: Variant in record.get("p", []):
			if player is Dictionary:
				best = maxi(best, int(player.get("correct", 0)))
				correct += int(player.get("correct", 0))
				attempted += int(player.get("attempted", 0))
		var winner := int(record.get("winner", -1))
		if winner == 1 or winner == 2:
			wins[winner - 1] += 1
	return {
		"matches": records.size(),
		"best_correct": best,
		"correct": correct,
		"attempted": attempted,
		"accuracy": float(correct) / float(attempted) if attempted > 0 else 0.0,
		"wins": wins,
	}


static func read_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	return parsed if parsed is Dictionary else {}


## Writes through a temporary file so a crash never leaves half a history.
static func write_json(file_path: String, data: Dictionary) -> bool:
	var temp_path := file_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("MatchHistory: cannot write %s" % temp_path)
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	var target := ProjectSettings.globalize_path(file_path)
	if FileAccess.file_exists(file_path) and DirAccess.remove_absolute(target) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), target) == OK
