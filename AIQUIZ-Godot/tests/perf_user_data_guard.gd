extends RefCounted

## Keeps the player's own user:// data out of the harness: every file a match can write
## (analytics, quiz history, ratings, the Firebase outbox, settings...) is copied before the
## autoloads start and written back when the harness ends (and again from _finalize, after
## the scene tree has exited). Files that did not exist are removed again.
## A copy also lands in user://perf_harness_backup/ while the harness runs; if a run crashes,
## the next run moves that folder aside (perf_harness_backup_leftover_<time>) instead of
## restoring it blindly, so newer real data is never overwritten.

const BACKUP_DIR := "user://perf_harness_backup"
const MANIFEST := "user://perf_harness_backup/manifest.json"
const FILES: Array[String] = [
	"user://settings.json",
	"user://audio_settings.cfg",
	"user://player_analytics.json",
	"user://recent_quiz_history.json",
	"user://quiz_ratings.json",
	"user://firebase_quiz_cache_v1.json",
	"user://firebase_quiz_cache_v1.tmp",
	"user://firebase_quiz_cache_v1.bak",
	"user://firebase_quiz_outbox_v1.json",
	"user://firebase_quiz_outbox_v1.tmp",
	"user://firebase_quiz_outbox_v1.bak",
	"user://generated_bank.json",
	"user://device_session.json",
	"user://match_history.json",
	"user://recent_unit_usage.json",
	"user://player_skins.json",
	"user://menu_preview_camera.json",
	"user://customize_wall_speed_camera.json",
	"user://lecture_visits.json",
	"user://lecture_board.json",
	"user://online_quiz_usage.jsonl",
	"user://online_quiz_cost_canary.json",
	"user://question_history.json",
	"user://highscores.json",
	"user://tutorial_state.json",
	"user://hat_config.json",
]

var _saved: Dictionary = {}
var _active := false
var leftover_moved_to := ""


func begin() -> void:
	if FileAccess.file_exists(MANIFEST):
		leftover_moved_to = "%s_leftover_%d" % [BACKUP_DIR, int(Time.get_unix_time_from_system())]
		var err := DirAccess.rename_absolute(BACKUP_DIR, leftover_moved_to)
		push_warning("[perf] A previous harness run did not finish; its backup was moved to %s (err %d). Check it if user data looks wrong." % [leftover_moved_to, err])
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	var manifest := {}
	for path: String in FILES:
		if FileAccess.file_exists(path):
			var bytes := FileAccess.get_file_as_bytes(path)
			_saved[path] = bytes
			var copy := BACKUP_DIR + "/" + path.get_file()
			var f := FileAccess.open(copy, FileAccess.WRITE)
			if f != null:
				f.store_buffer(bytes)
				f.close()
			manifest[path] = copy
		else:
			_saved[path] = null
			manifest[path] = ""
	var mf := FileAccess.open(MANIFEST, FileAccess.WRITE)
	if mf != null:
		mf.store_string(JSON.stringify(manifest, "  "))
		mf.close()
	_active = true


## Writes the saved files back. Returns {"restored": [...], "removed": [...]}.
func restore(final: bool) -> Dictionary:
	var report := {"restored": [], "removed": []}
	if not _active:
		return report
	for path: String in _saved.keys():
		var original: Variant = _saved[path]
		if original == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
				(report["removed"] as Array).append(path)
			continue
		var current := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
		if current != (original as PackedByteArray):
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(original as PackedByteArray)
				f.close()
				(report["restored"] as Array).append(path)
	if final:
		for path: String in FILES:
			var copy := BACKUP_DIR + "/" + path.get_file()
			if FileAccess.file_exists(copy):
				DirAccess.remove_absolute(copy)
		if FileAccess.file_exists(MANIFEST):
			DirAccess.remove_absolute(MANIFEST)
		DirAccess.remove_absolute(BACKUP_DIR)
		_active = false
	return report
