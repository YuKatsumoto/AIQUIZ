extends RefCounted
class_name UnlockStore

## このPCで解放したシークレット（かくし要素）を user://unlocks.json に保存する。
## 解放は取り消さない。条件に届いた瞬間に書くので、試合を途中でやめても消えない。
## --fresh-profile 付きで起動したとき（テスト）は読み込みも書き込みもしない（メモリの中だけで動く）。

const DEFAULT_PATH := "user://unlocks.json"
const FILE_VERSION := 1
const FRESH_PROFILE_ARG := "--fresh-profile"

## ママチャリ：エンドレスで、難易度「普通」以上、1回のプレイで 50問 正解。
const MAMACHARI: StringName = &"mamachari"
const MAMACHARI_CORRECT_COUNT := 50
const MAMACHARI_DIFFICULTIES: Array[String] = ["普通", "難しい"]

const IDS: Array[StringName] = [MAMACHARI]
const LABELS := {
	&"mamachari": "ママチャリ",
}
const HINTS := {
	&"mamachari": "エンドレスモード（難易度「普通」以上）で、1回のプレイで50問正解する",
}

static var path: String = DEFAULT_PATH
## true の間は変更をファイルへ書かない（撮影・テストの間など）。
static var suspended: bool = false
## {id(String): {"at": 解放した時刻（UNIX 秒）, "seen": カスタマイズ画面で見たか}}
static var _entries: Dictionary = {}
static var _loaded: bool = false


static func is_fresh_profile() -> bool:
	return OS.get_cmdline_user_args().has(FRESH_PROFILE_ARG)


static func is_known(id: StringName) -> bool:
	return IDS.has(id)


static func label(id: StringName) -> String:
	return str(LABELS.get(id, str(id)))


## 解放の条件（解放前に「？？？」を選んだときに見せる）。
static func hint(id: StringName) -> String:
	return str(HINTS.get(id, ""))


static func reset_memory() -> void:
	_entries = {}
	_loaded = true


static func load_from_disk() -> void:
	reset_memory()
	if is_fresh_profile() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("[UnlockStore] %s を読めなかったので、解放なしとして扱います。" % path)
		return
	var unlocked: Variant = (parsed as Dictionary).get("unlocked", {})
	if not unlocked is Dictionary:
		return
	for key: Variant in unlocked:
		var id := StringName(str(key))
		if not is_known(id):
			continue
		var entry: Variant = (unlocked as Dictionary)[key]
		var source: Dictionary = entry if entry is Dictionary else {}
		var at: Variant = source.get("at", 0)
		_entries[str(id)] = {
			"at": int(at) if (at is int or at is float) else 0,
			"seen": bool(source.get("seen", false)),
		}


static func is_unlocked(id: StringName) -> bool:
	_ensure_loaded()
	return _entries.has(str(id))


## 解放する。今回はじめて解放したら true（もう解放済み・知らない ID なら false）。
static func unlock(id: StringName) -> bool:
	_ensure_loaded()
	if not is_known(id) or _entries.has(str(id)):
		return false
	_entries[str(id)] = {"at": int(Time.get_unix_time_from_system()), "seen": false}
	flush()
	return true


## 解放したあと、まだカスタマイズ画面で見ていない（「NEW」を出す）。
static func is_unseen(id: StringName) -> bool:
	_ensure_loaded()
	var entry: Variant = _entries.get(str(id))
	return entry is Dictionary and not bool((entry as Dictionary).get("seen", false))


static func mark_seen(id: StringName) -> void:
	if not is_unseen(id):
		return
	(_entries[str(id)] as Dictionary)["seen"] = true
	flush()


## エンドレスの1回のプレイが、ママチャリの条件に届いているか。
static func endless_run_qualifies(mode: String, difficulty: String, correct_count: int) -> bool:
	return (
		mode == Constants.MODE_ENDLESS
		and MAMACHARI_DIFFICULTIES.has(difficulty)
		and correct_count >= MAMACHARI_CORRECT_COUNT
	)


## 正解のたびに呼ぶ。今回はじめて解放したものの ID を返す（なければ空）。
## correct_count は、その試合でいちばん多く正解している人の数。
static func report_endless_progress(mode: String, difficulty: String, correct_count: int) -> Array[StringName]:
	var newly: Array[StringName] = []
	if endless_run_qualifies(mode, difficulty, correct_count) and unlock(MAMACHARI):
		newly.append(MAMACHARI)
	return newly


static func flush() -> void:
	if suspended or is_fresh_profile():
		return
	var text := JSON.stringify({"version": FILE_VERSION, "unlocked": _entries}, "  ")
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("[UnlockStore] %s に書けませんでした。" % temp_path)
		return
	file.store_string(text)
	file.close()
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_path := ProjectSettings.globalize_path(path)
	if DirAccess.rename_absolute(absolute_temp, absolute_path) != OK:
		DirAccess.remove_absolute(absolute_path)
		if DirAccess.rename_absolute(absolute_temp, absolute_path) != OK:
			push_warning("[UnlockStore] %s を保存できませんでした。" % path)


static func _ensure_loaded() -> void:
	if not _loaded:
		load_from_disk()
