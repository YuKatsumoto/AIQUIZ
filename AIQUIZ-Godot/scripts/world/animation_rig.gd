extends RefCounted
class_name AnimationRig

## P1/P2共通のアニメーションリグ管理クラス
## コア8スロット（走行・ジャンプ等）+ 追加エモートスロットでFBXを保持する

const SLOT_TAUNT := 0
const SLOT_RUN := 1
const SLOT_GANGNAM := 2
const SLOT_SLIDE := 3
const SLOT_TREADING_WATER := 4
const SLOT_DROWNING := 5
const SLOT_FLAIR := 6
const SLOT_JUMP := 7

const SLOT_EXTRA_EMOTE_FIRST := 8
## エモート一覧の全FBXを載せるための追加分（メモリと相談）
const SLOT_EXTRA_EMOTE_COUNT := 16
const SLOT_COUNT := 8 + SLOT_EXTRA_EMOTE_COUNT

const FBX_PATHS: Array[String] = [
	"res://assets/animations/Y Bot@Step Hip Hop Dance.fbx",
	"res://assets/animations/Run.fbx",
	"res://assets/animations/Y Bot@Gangnam Style.fbx",
	"res://assets/animations/Slide Hip Hop Dance.fbx",
	"res://assets/animations/Treading Water.fbx",
	"res://assets/animations/Drowning.fbx",
	"res://assets/animations/Flair.fbx",
	"res://assets/animations/Jumping.fbx",
	"", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "",
]

const SLOT_NAMES: Array[String] = [
	"Taunt", "Run", "Gangnam", "Slide",
	"TreadingWater", "Drowning", "Flair", "Jump",
	"Emote08", "Emote09", "Emote10", "Emote11", "Emote12", "Emote13", "Emote14",
	"Emote15", "Emote16", "Emote17", "Emote18", "Emote19", "Emote20", "Emote21",
	"Emote22", "Emote23",
]

## SLOT_MOONWALK はコア8枠のプレースホルダ（未使用）。エモート用は他スロットへ割当
const EMOTE_RIG_SLOTS: Array[int] = [
	SLOT_TAUNT, SLOT_GANGNAM, SLOT_SLIDE, SLOT_FLAIR,
	8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
]

# 各スロットのデータ (nullを許容するためVariant型の配列)
var scenes: Array = []
var skeletons: Array = []
var aps: Array = []
var bone_indices_list: Array = []
var anim_names: Array = []

var active_skeleton: Skeleton3D = null
var active_bone_indices: Dictionary = {}
var mirror_x: bool = false
var is_rigged: bool = false
var loaded_emotes: Array[int] = [1, 2, 3]
var thriller_part_slots: Array[int] = []
var thriller_part_idx: int = 0
var thriller_sequence_active: bool = false
var thriller_sequence_complete: bool = false

var _prefix: String = "P1"


func _init(prefix: String = "P1") -> void:
	_prefix = prefix
	for i in range(SLOT_COUNT):
		scenes.append(null)
		skeletons.append(null)
		aps.append(null)
		bone_indices_list.append({})
		anim_names.append("")


func load_all(parent: Node3D, loader: Callable, emote_slots: Array[int] = []) -> void:
	loaded_emotes.clear()
	for raw in emote_slots:
		var id := EmoteData.normalize_emote_id(int(raw))
		if id == EmoteData.EMOTE_NONE or loaded_emotes.has(id):
			continue
		loaded_emotes.append(id)
		if loaded_emotes.size() >= EMOTE_RIG_SLOTS.size():
			break
	if loaded_emotes.is_empty():
		loaded_emotes = [1, 2, 3]

	var emote_paths := FBX_PATHS.duplicate()
	while emote_paths.size() < SLOT_COUNT:
		emote_paths.append("")
	for i in range(mini(loaded_emotes.size(), EMOTE_RIG_SLOTS.size())):
		var slot_idx: int = EMOTE_RIG_SLOTS[i]
		if slot_idx < 0 or slot_idx >= emote_paths.size():
			continue
		var path := EmoteData.get_emote_fbx(loaded_emotes[i])
		if not path.is_empty():
			emote_paths[slot_idx] = path

	for i in range(SLOT_COUNT):
		var rig_name: String = _prefix + str(SLOT_NAMES[i]) + "Rig"
		var path: String = emote_paths[i] if i < emote_paths.size() else ""
		if path.is_empty():
			continue
		var data = loader.call(path, rig_name)
		if data:
			scenes[i] = data["node"]
			skeletons[i] = data["skeleton"]
			aps[i] = data["anim_player"]
			bone_indices_list[i] = data["bone_indices"]
			anim_names[i] = data["anim_name"]
			if i == SLOT_JUMP:
				var anim = aps[i].get_animation(anim_names[i])
				if anim:
					anim.loop_mode = Animation.LOOP_NONE
	_load_thriller_sequence_parts(loader)
	is_rigged = (skeletons[SLOT_TAUNT] != null) or (skeletons[SLOT_RUN] != null)


func _load_thriller_sequence_parts(loader: Callable) -> void:
	thriller_part_slots.clear()
	thriller_part_idx = 0
	thriller_sequence_active = false
	thriller_sequence_complete = false
	if not loaded_emotes.has(EmoteData.EMOTE_THRILLER):
		return
	var emote_idx := loaded_emotes.find(EmoteData.EMOTE_THRILLER)
	if emote_idx < 0 or emote_idx >= EMOTE_RIG_SLOTS.size():
		return
	var part1_slot: int = EMOTE_RIG_SLOTS[emote_idx]
	if anim_names[part1_slot] == "":
		return
	thriller_part_slots.append(part1_slot)
	var part1_ap := aps[part1_slot] as AnimationPlayer
	if part1_ap and anim_names[part1_slot] != "":
		var part1_anim = part1_ap.get_animation(anim_names[part1_slot])
		if part1_anim:
			part1_anim.loop_mode = Animation.LOOP_NONE
	for part_i in range(1, EmoteData.THRILLER_PART_PATHS.size()):
		var path: String = EmoteData.THRILLER_PART_PATHS[part_i]
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var slot := _find_free_emote_slot()
		if slot < 0:
			break
		var rig_name: String = _prefix + "Thriller" + str(part_i + 1) + "Rig"
		var data = loader.call(path, rig_name)
		if not data:
			continue
		scenes[slot] = data["node"]
		skeletons[slot] = data["skeleton"]
		aps[slot] = data["anim_player"]
		bone_indices_list[slot] = data["bone_indices"]
		anim_names[slot] = data["anim_name"]
		var ap := aps[slot] as AnimationPlayer
		if ap:
			var anim = ap.get_animation(anim_names[slot])
			if anim:
				anim.loop_mode = Animation.LOOP_NONE
		thriller_part_slots.append(slot)


func _find_free_emote_slot() -> int:
	for slot in range(SLOT_EXTRA_EMOTE_FIRST, SLOT_EXTRA_EMOTE_FIRST + SLOT_EXTRA_EMOTE_COUNT):
		if anim_names[slot] == "":
			return slot
	return -1


func reset_thriller_sequence() -> void:
	thriller_part_idx = 0
	thriller_sequence_active = false
	thriller_sequence_complete = false


func is_thriller_locked() -> bool:
	return thriller_sequence_active or thriller_sequence_complete


func start_thriller_sequence() -> void:
	if thriller_part_slots.is_empty():
		return
	if thriller_sequence_active or thriller_sequence_complete:
		return
	thriller_part_idx = 0
	thriller_sequence_active = true
	thriller_sequence_complete = false
	play_slot(thriller_part_slots[0], true)


func _on_thriller_part_finished(_anim_name: StringName = &"") -> void:
	if not thriller_sequence_active:
		return
	thriller_part_idx += 1
	if thriller_part_idx >= thriller_part_slots.size():
		thriller_sequence_active = false
		thriller_sequence_complete = true
		var last_slot: int = thriller_part_slots[thriller_part_slots.size() - 1]
		var last_ap := aps[last_slot] as AnimationPlayer
		if last_ap and anim_names[last_slot] != "":
			var anim = last_ap.get_animation(anim_names[last_slot])
			if anim:
				last_ap.play(anim_names[last_slot])
				last_ap.seek(anim.length, true)
				last_ap.pause()
		return
	play_slot(thriller_part_slots[thriller_part_idx], true)


func _apply_thriller_slot_pose(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	var skel: Skeleton3D = skeletons[slot]
	if not skel:
		return false
	active_skeleton = skel
	active_bone_indices = bone_indices_list[slot]
	mirror_x = true
	return true


func _select_thriller_emote(player_y: float, emote_lock: bool) -> bool:
	if player_y > 0.01 and not emote_lock:
		stop_all()
		reset_thriller_sequence()
		return false
	if thriller_sequence_complete:
		return _apply_thriller_slot_pose(thriller_part_slots[thriller_part_slots.size() - 1])
	if not thriller_sequence_active:
		start_thriller_sequence()
		if not thriller_sequence_active:
			return false
	var slot: int = thriller_part_slots[thriller_part_idx]
	var target_ap := aps[slot] as AnimationPlayer
	if target_ap and not target_ap.is_playing() and anim_names[slot] != "":
		play_slot(slot, true)
	return _apply_thriller_slot_pose(slot)


func _play_locked_emote_slot(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	var target_ap := aps[slot] as AnimationPlayer
	if not target_ap or anim_names[slot] == "":
		return false
	if not target_ap.is_playing():
		play_slot(slot, true)
	else:
		active_skeleton = skeletons[slot]
		active_bone_indices = bone_indices_list[slot]
		mirror_x = true
	return active_skeleton != null


func play_slot(slot: int, force_restart: bool = false) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	if is_thriller_locked() and slot not in thriller_part_slots:
		return false
	var target_ap = aps[slot] as AnimationPlayer
	var target_anim: String = anim_names[slot]
	if not target_ap or target_anim == "":
		return false
	for i in range(SLOT_COUNT):
		var ap = aps[i] as AnimationPlayer
		if ap and ap != target_ap and ap.is_playing():
			ap.stop()
	if not target_ap.is_playing() or force_restart:
		if slot == SLOT_JUMP:
			target_ap.play(target_anim, -1, 1.0)
		else:
			target_ap.play(target_anim)
	if slot in thriller_part_slots and thriller_sequence_active:
		if target_ap.animation_finished.is_connected(_on_thriller_part_finished):
			target_ap.animation_finished.disconnect(_on_thriller_part_finished)
		target_ap.animation_finished.connect(_on_thriller_part_finished, CONNECT_ONE_SHOT)
	active_skeleton = skeletons[slot]
	active_bone_indices = bone_indices_list[slot]
	mirror_x = true
	return true


func stop_all() -> void:
	if is_thriller_locked():
		return
	for i in range(SLOT_COUNT):
		var ap = aps[i] as AnimationPlayer
		if ap and ap.is_playing():
			ap.stop()


func select_animation(player_y: float, jump_trigger: bool, emote: int,
		moving_back: bool, is_active_state: bool,
		jump_ap_playing: bool, emote_lock: bool = false) -> bool:
	if emote <= 0 and is_thriller_locked() and not emote_lock:
		reset_thriller_sequence()

	if emote_lock:
		var lock_norm := EmoteData.normalize_emote_id(emote) if emote > 0 else EmoteData.EMOTE_NONE
		if is_thriller_locked() and not thriller_part_slots.is_empty():
			return _select_thriller_emote(player_y, true)
		if EmoteData.is_thriller_emote(lock_norm) and not thriller_part_slots.is_empty():
			return _select_thriller_emote(player_y, true)
		if emote > 0:
			var lock_idx := loaded_emotes.find(lock_norm)
			if lock_idx >= 0 and lock_idx < EMOTE_RIG_SLOTS.size():
				return _play_locked_emote_slot(EMOTE_RIG_SLOTS[lock_idx])
		return is_emote_playing() or is_thriller_locked()

	if player_y < -1.0:
		return play_slot(SLOT_DROWNING)

	if emote > 0:
		var norm := EmoteData.normalize_emote_id(emote)
		if EmoteData.is_thriller_emote(norm) and not thriller_part_slots.is_empty():
			return _select_thriller_emote(player_y, emote_lock)
		if player_y > 0.01 and not emote_lock:
			stop_all()
			return false
		var idx := loaded_emotes.find(norm)
		if idx >= 0 and idx < EMOTE_RIG_SLOTS.size():
			return play_slot(EMOTE_RIG_SLOTS[idx])
		return false

	if player_y > 0.01:
		stop_all()
		return false

	if is_active_state:
		return play_slot(SLOT_RUN)

	stop_all()
	return false


func is_jump_playing() -> bool:
	var ap = aps[SLOT_JUMP] as AnimationPlayer
	return ap != null and ap.is_playing()


func is_emote_playing() -> bool:
	for slot in EMOTE_RIG_SLOTS:
		var ap = aps[slot] as AnimationPlayer
		if ap and ap.is_playing():
			return true
	return false
