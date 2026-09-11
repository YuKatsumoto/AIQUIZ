class_name MenuPreviewController
extends RefCounted

## メインメニューのライブプレビュー(menu_wall_background_preview)を
## カスタマイズ操作の唯一の3Dステージとして共有制御するブリッジ。
## main_menu のカスタマイズUIからのイベントを受け、状態を game_state に保存しつつ
## プレビューへ反映する。

const SECTION_WALL := 0
const SECTION_SKIN := 1
const SECTION_EMOTE := 2

var _preview: Node = null
var section: int = SECTION_WALL
var editing_player: int = 1


func setup(preview: Node) -> void:
	_preview = preview


func _can(method: String) -> bool:
	return _preview != null and is_instance_valid(_preview) and _preview.has_method(method)


## カスタマイズ開始: プレビューを共有制御モードへ
func begin() -> void:
	if _can("enter_customize_control"):
		_preview.enter_customize_control()
	set_section(section)
	set_editing_player(editing_player)


## カスタマイズ終了: プレビューを通常のメニュー挙動へ戻す
func end() -> void:
	if _can("exit_customize_control"):
		_preview.exit_customize_control()


func set_section(s: int) -> void:
	section = s
	if _can("set_customize_section"):
		_preview.set_customize_section(s)


func set_editing_player(pid: int) -> void:
	editing_player = 2 if pid == 2 else 1
	if _can("set_customize_editing_player"):
		_preview.set_customize_editing_player(editing_player)


# --- 壁速度 ---

func set_wall_speed(value: float) -> void:
	QuizManager.game_state.tuning.wall_speed_override = value
	if _can("set_preview_speed_override"):
		_preview.set_preview_speed_override(value)


func reset_wall_speed() -> void:
	QuizManager.game_state.tuning.wall_speed_override = 0.0
	if _can("reset_preview_speed_override"):
		_preview.reset_preview_speed_override()


func get_wall_speed() -> float:
	if _can("get_preview_speed"):
		return _preview.get_preview_speed()
	return 0.0


func is_wall_speed_manual() -> bool:
	return QuizManager.game_state.tuning.wall_speed_override > 0.0


# --- スキン(帽子) ---

func current_hat() -> int:
	var gs := QuizManager.game_state
	return gs.p1_hat if editing_player == 1 else gs.p2_hat


func set_hat(hat_id: int) -> void:
	var gs := QuizManager.game_state
	if editing_player == 1:
		gs.p1_hat = hat_id
	else:
		gs.p2_hat = hat_id
	if _can("apply_actor_hat"):
		_preview.apply_actor_hat(editing_player, hat_id)


# --- エモート ---

func emote_slots() -> Array[int]:
	var gs := QuizManager.game_state
	return gs.p1_emote_slots if editing_player == 1 else gs.p2_emote_slots


func assign_emote(slot_idx: int, emote_id: int) -> void:
	if slot_idx < 0:
		return
	var gs := QuizManager.game_state
	var slots: Array[int] = (gs.p1_emote_slots if editing_player == 1 else gs.p2_emote_slots).duplicate()
	while slots.size() <= slot_idx:
		slots.append(EmoteData.EMOTE_NONE)
	slots[slot_idx] = EmoteData.normalize_emote_id(emote_id)
	if editing_player == 1:
		gs.p1_emote_slots = slots
	else:
		gs.p2_emote_slots = slots
	if _can("apply_actor_emote_slots"):
		_preview.apply_actor_emote_slots()
	if _can("play_actor_emote"):
		_preview.play_actor_emote(editing_player, EmoteData.normalize_emote_id(emote_id))
