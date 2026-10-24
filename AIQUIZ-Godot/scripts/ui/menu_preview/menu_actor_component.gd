class_name MenuActorComponent
extends RefCounted

## メニュー背景ランナーの AI を受け持つ部品の土台。持ち主（MenuWallBackgroundPreview）の状態を読み書きする近道をまとめる。
## 部品は持ち主の _init で作られる（_ready を呼ばずに new() するテストでも使えるように）。
## _preview_gs や _p1_ai は後から差し替えられるので、部品の中に覚えず毎回持ち主から読む。

const AIState = preload("res://scripts/ui/menu_preview_actor_ai_state.gd")
const Geo = preload("res://scripts/ui/menu_preview/menu_preview_geometry.gd")

var host: MenuWallBackgroundPreview


func _init(p_host: MenuWallBackgroundPreview) -> void:
	host = p_host


func gs() -> QuizGameState:
	return host._preview_gs


func now() -> float:
	return host._ai_time


func bundle_for(is_p1: bool) -> MenuPreviewActorAIState:
	return host._p1_ai if is_p1 else host._p2_ai


func other_bundle(bundle: MenuPreviewActorAIState) -> MenuPreviewActorAIState:
	return host._p2_ai if bundle == host._p1_ai else host._p1_ai


func is_2p() -> bool:
	return host._is_local_2p_active()


func alive(is_p1: bool) -> bool:
	return host._actor_alive(is_p1)


func x(is_p1: bool) -> float:
	return host._actor_x(is_p1)


func set_x(is_p1: bool, value: float) -> void:
	host._set_actor_x(is_p1, value)


func y(is_p1: bool) -> float:
	return host._actor_y(is_p1)


func set_y(is_p1: bool, value: float) -> void:
	host._set_actor_y(is_p1, value)


func vel_y(is_p1: bool) -> float:
	return host._actor_vel_y(is_p1)


func set_vel_y(is_p1: bool, value: float) -> void:
	host._set_actor_vel_y(is_p1, value)


func local_z(is_p1: bool) -> float:
	return host._actor_local_z(is_p1)


func set_local_z(is_p1: bool, value: float) -> void:
	host._set_actor_local_z(is_p1, value)


func emote(is_p1: bool) -> int:
	return host._actor_emote(is_p1)


func set_emote(is_p1: bool, value: int) -> void:
	host._set_actor_emote(is_p1, value)


func set_jump_trigger(is_p1: bool, value: bool) -> void:
	host._set_actor_jump_trigger(is_p1, value)


func set_moving_back(is_p1: bool, value: bool) -> void:
	host._set_actor_moving_back(is_p1, value)


func grounded(is_p1: bool) -> bool:
	return y(is_p1) <= Geo.FLOOR_Y + 0.01 and vel_y(is_p1) <= 0.0


func home_x(bundle: MenuPreviewActorAIState) -> float:
	return (
		Geo.PLAYER_X if bundle == host._p1_ai
		else Geo.PLAYER2_X
	)
