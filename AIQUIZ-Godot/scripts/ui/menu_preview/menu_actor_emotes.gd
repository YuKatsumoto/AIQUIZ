class_name MenuActorEmotes
extends MenuActorComponent

## エモート（正解の扉を3回くぐるごとに踊る）と、2P で相手が死んだときの煽り。
## 踊っているあいだは立ち止まる。次の壁に間に合わなくなる前に踊りを切り上げる。

const EMOTE_DURATION_MIN: float = 4.8
const EMOTE_DURATION_MAX: float = 8.0
## これより短くしか踊れないなら踊らない
const EMOTE_MIN_WINDOW: float = 2.0
## 踊り終わってから扉へ移るまでの余裕
const WALL_SAFETY_MARGIN: float = 1.0
const TAUNT_EMOTE_LOCK: float = 99999.0
const FALLBACK_EMOTES: Array[int] = [EmoteData.EMOTE_STEP_HIP_HOP, EmoteData.EMOTE_GANGNAM, EmoteData.EMOTE_MOONWALK]


func fill_pool(bundle: MenuPreviewActorAIState, rig_ids: Array[int]) -> void:
	bundle.available_emotes = rig_ids.duplicate()
	if bundle.available_emotes.is_empty():
		bundle.available_emotes = FALLBACK_EMOTES.duplicate()


## 次にくぐる壁と、その壁がランナーに届くまでの秒数（コンベアが止まっていれば INF）。
func next_wall_contact(is_p1: bool) -> Dictionary:
	var player_z := local_z(is_p1)
	var speed := host._get_effective_preview_speed()
	var best: Node3D = null
	var best_gap := INF
	for wall in host._preview_walls:
		if not is_instance_valid(wall) or not wall.visible:
			continue
		if bool(wall.get_meta("preview_door_broken", false)):
			continue
		if wall.get_meta("preview_hit_p1" if is_p1 else "preview_hit_p2", false):
			continue
		var door_leading_z := wall.position.z + Geo.DOOR_HALF_DEPTH_Z
		var gap := (player_z - Geo.WALL_CONTACT_Z) - door_leading_z
		if gap < 0.0 or gap >= best_gap:
			continue
		best_gap = gap
		best = wall
	var eta := INF
	if best != null and speed > 0.01:
		eta = best_gap / speed
	return {"wall": best, "eta": eta}


## その壁の正解の扉（わからなければ近いほうの扉）まで横に移るのにかかる時間の目安。
func reach_time_for_wall(wall: Node3D, is_p1: bool) -> float:
	var door_x := Geo.DOOR_X_LEFT
	var correct_door := int(wall.get_meta("preview_correct_door", -1)) if wall else -1
	if correct_door == Geo.RED_DOOR_INDEX:
		door_x = Geo.DOOR_X_RIGHT
	elif correct_door < 0 and x(is_p1) > 0.0:
		door_x = Geo.DOOR_X_RIGHT
	return absf(door_x - x(is_p1)) / MenuActorAI.LANE_SHIFT_SPEED_MIN + 0.45


## いま踊り始めたら、次の壁に間に合うために何秒以内に踊りやめる必要があるか。
func emote_window(is_p1: bool) -> float:
	var contact := next_wall_contact(is_p1)
	var wall := contact["wall"] as Node3D
	if wall == null:
		return INF
	return float(contact["eta"]) - reach_time_for_wall(wall, is_p1) - WALL_SAFETY_MARGIN


## いまの位置のまま壁が来たら死んでしまうか（煽りをやめて扉へ向かうべきか）。
func must_leave_for_wall(is_p1: bool) -> bool:
	var contact := next_wall_contact(is_p1)
	var wall := contact["wall"] as Node3D
	if wall == null:
		return false
	var door_idx := Geo.door_index_at(x(is_p1))
	var correct_door := int(wall.get_meta("preview_correct_door", -1))
	if door_idx >= 0 and (correct_door < 0 or door_idx == correct_door):
		return false
	return float(contact["eta"]) < reach_time_for_wall(wall, is_p1) + WALL_SAFETY_MARGIN


func start_emote(bundle: MenuPreviewActorAIState, is_p1: bool, max_duration: float = INF) -> bool:
	if not gs() or bundle.available_emotes.is_empty():
		return false
	if y(is_p1) > 0.01 or vel_y(is_p1) != 0.0:
		return false
	var window := minf(max_duration, emote_window(is_p1))
	if window < EMOTE_MIN_WINDOW:
		return false
	var emote_pool := bundle.available_emotes.duplicate()
	if emote_pool.size() > 1 and bundle.last_emote > 0:
		emote_pool.erase(bundle.last_emote)
	if emote_pool.is_empty():
		emote_pool = bundle.available_emotes.duplicate()
	set_emote(is_p1, int(emote_pool[randi() % emote_pool.size()]))
	bundle.last_emote = emote(is_p1)
	bundle.emote_end_t = now() + minf(randf_range(EMOTE_DURATION_MIN, EMOTE_DURATION_MAX), window)
	bundle.is_emoting = true
	bundle.next_action_t = maxf(bundle.next_action_t, bundle.emote_end_t + 0.25)
	# 踊るときは立ち止まる（動いていた分は MenuActorAI のブレーキで止まる）
	bundle.lane_shift_active = false
	bundle.depth_shift_active = false
	set_moving_back(is_p1, false)
	return true


func update_emote_timer(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.is_emoting and now() >= bundle.emote_end_t:
		stop_emote(bundle, is_p1)


func stop_emote(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not gs():
		return
	bundle.is_emoting = false
	set_emote(is_p1, 0)
	if bundle.ai_state != AIState.STATE_TAUNT:
		clear_taunt_lock(is_p1)
	if not bundle.depth_shift_active:
		set_moving_back(is_p1, false)


func set_taunt_lock(is_p1: bool, locked: bool) -> void:
	if not gs():
		return
	if is_p1:
		gs().p1_emote_lock_timer = TAUNT_EMOTE_LOCK if locked else 0.0
	else:
		gs().p2_emote_lock_timer = TAUNT_EMOTE_LOCK if locked else 0.0


func clear_taunt_lock(is_p1: bool) -> void:
	set_taunt_lock(is_p1, false)
	var pc := host._preview_player as PlayerController
	if pc:
		pc.reset_thriller_sequence(not is_p1)


func rig_emote_ids(is_p1: bool) -> Array[int]:
	var pc := host._preview_player as PlayerController
	if not pc:
		return []
	return pc.get_loaded_emote_ids(not is_p1)


func filter_for_rig(candidates: Array[int], is_p1: bool) -> Array[int]:
	var rig_ids := rig_emote_ids(is_p1)
	if rig_ids.is_empty():
		return candidates.duplicate()
	var filtered: Array[int] = []
	for raw in candidates:
		var id := EmoteData.normalize_emote_id(int(raw))
		if rig_ids.has(id):
			filtered.append(id)
	return filtered


func start_taunt_emote(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not gs() or not alive(is_p1) or bundle.available_emotes.is_empty():
		return false
	if y(is_p1) > 0.01 or vel_y(is_p1) != 0.0:
		return false
	var emote_pool := filter_for_rig(bundle.available_emotes, is_p1)
	if emote_pool.is_empty():
		emote_pool = rig_emote_ids(is_p1)
	if emote_pool.is_empty():
		emote_pool = bundle.available_emotes.duplicate()
	if emote_pool.size() > 1 and bundle.last_emote > 0:
		emote_pool.erase(bundle.last_emote)
	if emote_pool.is_empty():
		emote_pool = filter_for_rig(bundle.available_emotes, is_p1)
	if emote_pool.is_empty():
		return false
	var emote_id := int(emote_pool[randi() % emote_pool.size()])
	set_emote(is_p1, emote_id)
	bundle.last_emote = emote_id
	set_moving_back(is_p1, false)
	set_taunt_lock(is_p1, true)
	var pc := host._preview_player as PlayerController
	if pc:
		pc.reset_thriller_sequence(not is_p1)
		if EmoteData.is_thriller_emote(emote_id):
			pc.start_thriller_sequence(not is_p1)
		pc.ensure_emote_playback(not is_p1, emote_id)
	return true


## 2P で片方が死んだら、生き残った方が立ち止まって飛んでいく相手を見ながら煽る。
func begin_survivor_taunt(dead_is_p1: bool) -> void:
	if not is_2p():
		return
	var survivor_is_p1 := not dead_is_p1
	if not alive(survivor_is_p1):
		return
	var survivor := bundle_for(survivor_is_p1)
	if survivor.ai_state not in [AIState.STATE_NORMAL, AIState.STATE_ACROBATICS]:
		return
	survivor.taunt_target_x = x(dead_is_p1)
	survivor.taunt_target_z = local_z(dead_is_p1)
	survivor.ai_state = AIState.STATE_TAUNT
	survivor.lane_shift_active = false
	survivor.depth_shift_active = false
	survivor.dodge_until = -1.0
	survivor.blocking_wall = null
	host._accidents.clear_pending(survivor)
	host._door_learning.clear_commit(survivor, home_x(survivor))
	stop_emote(survivor, survivor_is_p1)
	set_moving_back(survivor_is_p1, false)
	start_taunt_emote(survivor, survivor_is_p1)


## 煽りをやめて走りに戻る（相手が復活した・ゴーストのサメが来た・壁が迫った）。
func end_taunt(survivor_is_p1: bool, next_action_delay: float = -1.0) -> void:
	var survivor := bundle_for(survivor_is_p1)
	if survivor.ai_state != AIState.STATE_TAUNT:
		return
	survivor.ai_state = AIState.STATE_NORMAL
	stop_emote(survivor, survivor_is_p1)
	clear_taunt_lock(survivor_is_p1)
	survivor.next_action_t = now() + (next_action_delay if next_action_delay >= 0.0 else randf_range(0.35, 0.9))


func stop_survivor_taunt(respawned_is_p1: bool) -> void:
	if not is_2p():
		return
	end_taunt(not respawned_is_p1)


static func facing_y_toward(from_x: float, from_z: float, to_x: float, to_z: float) -> float:
	var dx := to_x - from_x
	var dz := to_z - from_z
	if dx * dx + dz * dz < 0.04:
		return PI
	return atan2(dx, dz)


## 煽り・エモートのときの向き（update_from_state のあとに pelvis へ当てる）。
## 煽りは実際に飛んでいるラグドール／破片を追い続け、エモートは FBX の回転を残して壁向き(+PI)だけ合わせる。
func apply_legacy_facing(parts: Dictionary, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	var pelvis := parts.get("pelvis") as Node3D
	if not pelvis:
		return
	if bundle.ai_state == AIState.STATE_TAUNT:
		var pc := host._preview_player as PlayerController
		if pc:
			var target_position := pc.get_death_presentation_position(not is_p1)
			bundle.taunt_target_x = target_position.x
			bundle.taunt_target_z = target_position.z
		pelvis.rotation.y = facing_y_toward(x(is_p1), local_z(is_p1), bundle.taunt_target_x, bundle.taunt_target_z)
	elif bundle.is_emoting or emote(is_p1) != EmoteData.EMOTE_NONE:
		pelvis.rotate_y(PI)
	else:
		pelvis.rotation.y = PI
