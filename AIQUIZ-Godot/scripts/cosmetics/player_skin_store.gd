extends RefCounted
class_name PlayerSkinStore

## このPCの P1/P2 の見た目（体の塗りと帽子）を user://player_skins.json に保存する。
## ゲーム状態はリプレイやオンライン対戦で一時的に書き換わるので、保存はここからだけ行う。
## --fresh-profile 付きで起動したとき（テスト）は読み込みも書き込みもしない。

const DEFAULT_PATH := "user://player_skins.json"
const FILE_VERSION := 1
const SAVE_DELAY_SEC := 0.4
const FRESH_PROFILE_ARG := "--fresh-profile"

static var path: String = DEFAULT_PATH
## true の間は変更をファイルへ書かない（チュートリアルの紹介中など）。
static var suspended: bool = false
static var _skins: Dictionary = {1: {}, 2: {}}
static var _hats: Dictionary = {1: 0, 2: 0}
static var _dirty: bool = false
static var _save_generation: int = 0


static func is_fresh_profile() -> bool:
	return OS.get_cmdline_user_args().has(FRESH_PROFILE_ARG)


static func reset_memory() -> void:
	_skins = {1: {}, 2: {}}
	_hats = {1: 0, 2: 0}
	_dirty = false
	_save_generation += 1


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
		push_warning("[PlayerSkinStore] %s を読めなかったので標準の見た目にします。" % path)
		return
	var players: Variant = (parsed as Dictionary).get("players", {})
	if not players is Dictionary:
		return
	for slot: int in [1, 2]:
		var entry: Variant = (players as Dictionary).get(str(slot), {})
		if not entry is Dictionary:
			continue
		var code: Variant = (entry as Dictionary).get("skin", "")
		_skins[slot] = normalized(slot, PlayerSkin.from_code(code if code is String else ""))
		_hats[slot] = _sanitize_hat((entry as Dictionary).get("hat", 0))


static func load_into(gs: QuizGameState) -> void:
	load_from_disk()
	apply_to_state(gs)


static func apply_to_state(gs: QuizGameState) -> void:
	if gs == null:
		return
	for slot: int in [1, 2]:
		gs.set_player_skin(slot, _skins[slot])
	gs.p1_hat = int(_hats[1])
	gs.p2_hat = int(_hats[2])


static func get_skin(slot: int) -> Dictionary:
	return (_skins.get(_slot(slot), {}) as Dictionary).duplicate(true)


static func get_skin_code(slot: int) -> String:
	return PlayerSkin.to_code(_skins.get(_slot(slot), {}), _slot(slot))


static func get_hat(slot: int) -> int:
	return int(_hats.get(_slot(slot), 0))


static func set_skin(slot: int, skin: Dictionary) -> void:
	var key := _slot(slot)
	var normalized := normalized(key, skin)
	var stored := {} if PlayerSkin.is_slot_default(normalized, key) else PlayerSkin.canonicalize(normalized, key)
	if PlayerSkin.to_code(stored, key) == PlayerSkin.to_code(_skins[key], key):
		return
	_skins[key] = stored
	schedule_save()


static func set_hat(slot: int, hat_id: int) -> void:
	var key := _slot(slot)
	var hat := _sanitize_hat(hat_id)
	if hat == int(_hats[key]):
		return
	_hats[key] = hat
	schedule_save()


static func schedule_save() -> void:
	_dirty = true
	_save_generation += 1
	var generation := _save_generation
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		flush()
		return
	tree.create_timer(SAVE_DELAY_SEC, true, false, true).timeout.connect(
		func() -> void:
			if generation == _save_generation:
				flush()
	)


static func flush() -> void:
	if not _dirty or suspended or is_fresh_profile():
		return
	_dirty = false
	var players := {}
	for slot: int in [1, 2]:
		players[str(slot)] = {"skin": PlayerSkin.to_code(_skins[slot], slot), "hat": int(_hats[slot])}
	var text := JSON.stringify({"version": FILE_VERSION, "players": players}, "  ")
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("[PlayerSkinStore] %s に書けませんでした。" % temp_path)
		_dirty = true
		return
	file.store_string(text)
	file.close()
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_path := ProjectSettings.globalize_path(path)
	if DirAccess.rename_absolute(absolute_temp, absolute_path) != OK:
		DirAccess.remove_absolute(absolute_path)
		if DirAccess.rename_absolute(absolute_temp, absolute_path) != OK:
			push_warning("[PlayerSkinStore] %s を保存できませんでした。" % path)
			_dirty = true


static func has_unsaved_changes() -> bool:
	return _dirty


## プレイヤー2 はローカル2人対戦でしか使わず、そこでは あたまの色が固定なので、いつも標準色にしておく。
static func is_head_locked(slot: int) -> bool:
	return _slot(slot) == 2


## プレイヤー2 なら あたまを標準色にした見た目（それ以外はそのまま）。
static func normalized(slot: int, skin: Dictionary) -> Dictionary:
	if not is_head_locked(slot) or skin.is_empty():
		return skin
	return PlayerSkin.with_default_head(skin, slot)


static func _slot(slot: int) -> int:
	return 2 if slot == 2 else 1


static func _sanitize_hat(value: Variant) -> int:
	var hat := int(value) if (value is int or value is float) else 0
	return hat if HatData.is_selectable(hat) else HatData.HAT_NONE
