extends Node

## 一番最初の autoload。ダウンロード済みのパッチPCKを、ほかのスクリプトが読まれる前に読み込む。
##
## autoload は project.godot に書いた順に「スクリプトを読む → _init を呼ぶ」を 1 つずつ進めるので、
## ここの _init で読み込んだパッチは、後ろの autoload（GameManager など）のスクリプトにも効く。
## そのため、このスクリプトは project.godot の [autoload] の先頭に置く。
##
## 決まりごと:
##   - このスクリプト自身はパッチで差し替えられない（読まれた後にパッチが入るため）。
##   - ほかのスクリプトを preload したり、class_name や autoload の名前を直接書いたりしない。
##     書くと、そのスクリプトがパッチより先に読まれてしまい、差し替えが効かなくなる。
##   - パッチのダウンロードと画面は scripts/core/game_updater.gd と scripts/ui/update_prompt.gd。
##     そちらはパッチで差し替えられる。

const DIR := "user://updates"
const STATE_PATH := DIR + "/state.json"
## パッチを当てた起動がこの回数続けてメニューまで届かなかったら、そのパッチを捨てる。
const MAX_FAILED_BOOTS := 2
## 捨てたパッチ（sha256）を覚えておく数。同じパッチを何度も勧めないため。
const MAX_REJECTED := 8

## いま入っているフル版のバージョン（パッチを当てる前の application/config/version）。
var base_version := ""
## 実際に動いているバージョン。パッチを読み込めたらパッチのバージョンになる。
var version := ""
var patch_loaded := false
## state.json の中身。{"patch": {version, base, file, size, sha256, failed_boots}, "rejected": [sha256...]}
var state: Dictionary = {}


func _init() -> void:
	base_version = str(ProjectSettings.get_setting("application/config/version", ""))
	version = base_version
	if not is_supported():
		return
	state = _read_state()
	_load_patch()
	_remove_stale_files()


func _ready() -> void:
	if patch_loaded:
		_watch_startup.call_deferred()


## パッチを使うのは Windows の書き出し版だけ。エディターの実行では res:// がそのまま最新。
static func is_supported() -> bool:
	return OS.has_feature("windows") and not OS.has_feature("editor")


func rejected_hashes() -> Array:
	var rejected: Variant = state.get("rejected", [])
	return rejected if rejected is Array else []


## 一時ファイルに書いてから置き換える。書いている途中で終了しても、前の state.json が残る。
func write_state() -> bool:
	if DirAccess.make_dir_recursive_absolute(DIR) != OK:
		return false
	var tmp_path := STATE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	return DirAccess.rename_absolute(tmp_path, STATE_PATH) == OK


func _read_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	return parsed if parsed is Dictionary else {}


func _load_patch() -> void:
	var patch: Variant = state.get("patch")
	if not patch is Dictionary:
		return
	# フル版を入れ直した後は、前のフル版向けのパッチは合わない。
	if str(patch.get("base", "")) != base_version:
		_drop_patch("base mismatch", false)
		return
	var failed := int(patch.get("failed_boots", 0))
	if failed >= MAX_FAILED_BOOTS:
		_drop_patch("%d boots did not reach the menu" % failed, true)
		return
	var path := DIR.path_join(str(patch.get("file", "")))
	if not _file_matches(path, int(patch.get("size", -1))):
		_drop_patch("file missing or wrong size", false)
		return
	# 先に「起動中」として数えておく。メニューまで届いたら _confirm_boot で 0 に戻す。
	patch["failed_boots"] = failed + 1
	write_state()
	if not ProjectSettings.load_resource_pack(path):
		_drop_patch("load_resource_pack failed", true)
		return
	patch_loaded = true
	version = str(patch.get("version", base_version))
	# project.godot の中身はもう読み込み済みなので、バージョンだけ手で合わせる。
	ProjectSettings.set_setting("application/config/version", version)
	print("[PatchBoot] patch %s loaded on base %s" % [version, base_version])


func _file_matches(path: String, size: int) -> bool:
	if size <= 0 or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and file.get_length() == size


func _drop_patch(reason: String, reject: bool) -> void:
	var patch: Dictionary = state.get("patch", {})
	push_warning("[PatchBoot] patch %s dropped: %s" % [str(patch.get("version", "?")), reason])
	if reject:
		var rejected := rejected_hashes()
		var sha := str(patch.get("sha256", ""))
		if not sha.is_empty() and not rejected.has(sha):
			rejected.append(sha)
		state["rejected"] = rejected.slice(-MAX_REJECTED)
	state.erase("patch")
	write_state()


## 使っていないパッチ（前の版、途中で止まったダウンロード）を消す。
func _remove_stale_files() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var keep := ""
	var patch: Variant = state.get("patch")
	if patch is Dictionary:
		keep = str(patch.get("file", ""))
	for file_name: String in dir.get_files():
		if file_name == keep or file_name == STATE_PATH.get_file():
			continue
		if file_name.ends_with(".pck") or file_name.ends_with(".part") or file_name.ends_with(".tmp"):
			dir.remove(file_name)


func _watch_startup() -> void:
	# GameManager の名前を直接書かない（このスクリプトの決まりごと）。
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager != null and game_manager.has_signal("startup_finished"):
		game_manager.connect("startup_finished", _confirm_boot, CONNECT_ONE_SHOT)


func _confirm_boot() -> void:
	var patch: Variant = state.get("patch")
	if patch is Dictionary:
		patch["failed_boots"] = 0
		write_state()
