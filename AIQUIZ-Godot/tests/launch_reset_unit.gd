extends SceneTree

## The main menu LED history (MatchHistory) and its replay clips (HighlightStore) start
## empty at every launch: GameManager clears them when it is created.
## Unit: clear() on a scratch store. Process check: `seed` leaves a record and a clip in
## the real store, and the next launch (`verify`) must find neither.
## Run: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/launch_reset_unit.gd -- seed
##      Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/launch_reset_unit.gd -- verify
##      (no option: the unit checks only)

const SCRATCH := "user://test_launch_reset"
const CLIP_ID := "launch_reset_clip"

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)


func _run() -> void:
	var mode := "unit"
	for arg: String in OS.get_cmdline_user_args():
		if arg in ["seed", "verify"]:
			mode = arg
	match mode:
		"seed":
			_seed_real_store()
		"verify":
			_verify_real_store_is_empty()
		_:
			_unit_clear()
	print("LAUNCH_RESET_UNIT " + JSON.stringify({"mode": mode, "passed": _failures.is_empty(), "checks": _checks, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)


func _record() -> Dictionary:
	return {"id": "m1", "ts": 1, "mode": "TEN", "players": 1, "p": [{"correct": 3, "attempted": 4}]}


func _clip() -> Dictionary:
	return {
		"entry": {"id": CLIP_ID, "ts": 1, "match": "m1", "at": 0.0, "times": [0.0, 0.1]},
		"jpegs": [PackedByteArray([1, 2, 3]), PackedByteArray([4, 5, 6])],
	}


func _unit_clear() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH))
	MatchHistory.path_override = SCRATCH + "/match_history.json"
	HighlightStore.dir_override = SCRATCH + "/highlights"
	MatchHistory.clear()
	HighlightStore.clear()
	check(MatchHistory.load_records().is_empty() and HighlightStore.list().is_empty(), "scratch store starts empty")
	check(MatchHistory.append(_record()) and HighlightStore.add_clips([_clip()]), "scratch store written")
	check(MatchHistory.load_records().size() == 1 and HighlightStore.list().size() == 1, "scratch store holds a record and a clip")
	check(FileAccess.file_exists(HighlightStore.frame_path(_clip().entry, 1)), "clip frames written")
	MatchHistory.clear()
	HighlightStore.clear()
	check(MatchHistory.load_records().is_empty(), "clear() forgets the records")
	check(not FileAccess.file_exists(MatchHistory.path()), "clear() removes the history file")
	check(HighlightStore.list().is_empty(), "clear() forgets the clips")
	check(not FileAccess.file_exists(HighlightStore.frame_path(_clip().entry, 0)), "clear() removes the clip frames")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(HighlightStore.root().path_join(CLIP_ID))), "clear() removes the clip folder")
	MatchHistory.clear()
	HighlightStore.clear()
	check(true, "clear() on an empty store is harmless")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HighlightStore.root()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	MatchHistory.path_override = ""
	HighlightStore.dir_override = ""


func _seed_real_store() -> void:
	check(MatchHistory.path_override.is_empty() and HighlightStore.dir_override.is_empty(), "real store, not a scratch one")
	check(MatchHistory.append(_record()), "record seeded")
	check(HighlightStore.add_clips([_clip()]), "clip seeded")
	check(MatchHistory.load_records().size() == 1 and HighlightStore.list().size() == 1, "seeded store is readable")


func _verify_real_store_is_empty() -> void:
	check(not FileAccess.file_exists(MatchHistory.path()), "history file gone after launch")
	check(MatchHistory.load_records().is_empty(), "no records after launch")
	check(HighlightStore.list().is_empty(), "no clips after launch")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(HighlightStore.root().path_join(CLIP_ID))), "no clip folder after launch")
