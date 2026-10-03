class_name HighlightStore
extends RefCounted

## Highlight clips recorded during matches (HighlightCapture) for the LED programme
## on the goal stand scoreboard.
## A clip is a short run of small JPEG frames:
##   user://highlights/<id>/000.jpg, 001.jpg, ...   and   user://highlights/index.json
## Index entry: id, ts (unix seconds), match (MatchHistory id), order and at (the
##   clip's place and capture second in its match), mode, players, online, size [w, h],
##   times (seconds of each frame from the clip start), events (every moment in the
##   clip: kind, player (0 = both / nobody in particular), t (second in the clip),
##   streak for "streak"), and kind / player / event / streak of the strongest one.
## The clips of the newest MAX_MATCHES matches are kept (at most MAX_CLIPS); older
## clip folders are deleted. GameManager clear()s the whole store at every launch.

const DIR := "user://highlights"
const MAX_MATCHES := 3
const MAX_CLIPS := 48
const INDEX_VERSION := 1

## Tests point the store somewhere else.
static var dir_override := ""


static func root() -> String:
	return dir_override if not dir_override.is_empty() else DIR


static func index_path() -> String:
	return root().path_join("index.json")


static func new_id() -> String:
	return "%d_%04x" % [int(Time.get_unix_time_from_system()), randi() & 0xffff]


## Newest first.
static func list() -> Array[Dictionary]:
	var clips: Array[Dictionary] = []
	var parsed := MatchHistory.read_json(index_path())
	var items: Variant = parsed.get("clips")
	if items is Array:
		for item: Variant in items:
			if item is Dictionary and not (item.get("times", []) as Array).is_empty():
				clips.append(item)
	clips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("ts", 0)) > float(b.get("ts", 0)))
	return clips


static func frame_path(entry: Dictionary, index: int) -> String:
	return root().path_join(str(entry.get("id", ""))).path_join("%03d.jpg" % index)


## Stores clips (each {entry, jpegs}) and prunes the oldest. File IO only, so it
## may run on a worker thread; the index is written last.
static func add_clips(clips: Array) -> bool:
	if clips.is_empty():
		return true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root()))
	var index := list()
	for clip: Dictionary in clips:
		var entry: Dictionary = clip.entry
		var folder := root().path_join(str(entry.id))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var jpegs: Array = clip.jpegs
		for frame in range(jpegs.size()):
			var file := FileAccess.open(frame_path(entry, frame), FileAccess.WRITE)
			if file == null:
				push_warning("HighlightStore: cannot write %s" % frame_path(entry, frame))
				return false
			file.store_buffer(jpegs[frame])
			file.close()
		index.insert(0, entry)
	index.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("ts", 0)) > float(b.get("ts", 0)))
	var matches: Array[String] = []
	var kept: Array[Dictionary] = []
	for entry: Dictionary in index:
		var match_id := str(entry.get("match", entry.get("id", "")))
		if not match_id in matches:
			matches.append(match_id)
		if matches.find(match_id) < MAX_MATCHES and kept.size() < MAX_CLIPS:
			kept.append(entry)
		else:
			_remove_folder(root().path_join(str(entry.get("id", ""))))
	return MatchHistory.write_json(index_path(), {"version": INDEX_VERSION, "clips": kept})


## Deletes every clip folder and the index (at launch, see GameManager).
static func clear() -> void:
	var dir := DirAccess.open(root())
	if dir == null:
		return
	for folder: String in dir.get_directories():
		_remove_folder(root().path_join(folder))
	for file_name: String in dir.get_files():
		dir.remove(file_name)


## Clips grouped by match, newest match first, each match's clips in match order.
static func by_match(clips: Array[Dictionary]) -> Array[Array]:
	var groups: Array[Array] = []
	var index_of := {}
	var sorted := clips.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("ts", 0)) > float(b.get("ts", 0)))
	for clip: Dictionary in sorted:
		var match_id := str(clip.get("match", clip.get("id", "")))
		if not index_of.has(match_id):
			index_of[match_id] = groups.size()
			groups.append([])
		(groups[index_of[match_id]] as Array).append(clip)
	for group: Array in groups:
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("at", a.get("order", 0))) < float(b.get("at", b.get("order", 0))))
	return groups


## Decodes a clip's frames. No scene access, so it runs on a worker thread.
static func load_frames(entry: Dictionary) -> Array[Image]:
	var images: Array[Image] = []
	for frame in range((entry.get("times", []) as Array).size()):
		var bytes := FileAccess.get_file_as_bytes(frame_path(entry, frame))
		var image := Image.new()
		if bytes.is_empty() or image.load_jpg_from_buffer(bytes) != OK:
			break
		images.append(image)
	return images


static func _remove_folder(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null or folder.get_file().is_empty():
		return
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
