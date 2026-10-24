class_name MenuActorAccidents
extends MenuActorComponent

## わざと起こす事故（不正解の扉や扉のあいだへ突っ込んで激突／コンベアの後端から海へ転落）。
## 事故は「潜伏型」：AI の状態は NORMAL のまま、pending_accident を立てて目標へ走らせ、壁や縁に着いたところで起きる。

const COOLDOWN_MIN: float = 7.5
const COOLDOWN_MAX: float = 12.0
## 事故のうち壁への激突を選ぶ割合（残りは海。ノコギリが後ろをふさいでいれば激突だけ）
const CRASH_RATIO: float = 0.45
## 事故に使う壁の範囲（ローカル z）
const WALL_PICK_Z_MIN: float = -26.0
const WALL_PICK_Z_MAX: float = 4.0
## 激突の狙い：不正解の扉へ走る割合（残りは扉のあいだの壁）
const WRONG_DOOR_SHARE: float = 0.65


func clear_pending(bundle: MenuPreviewActorAIState) -> void:
	var wall := bundle.pending_accident_wall
	if wall != null and is_instance_valid(wall):
		if wall.has_meta("preview_accident_owner") and wall.get_meta("preview_accident_owner") == bundle:
			wall.remove_meta("preview_accident_owner")
	bundle.pending_accident = AIState.PENDING_ACCIDENT_NONE
	bundle.pending_accident_wall = null


func on_cooldown(bundle: MenuPreviewActorAIState) -> bool:
	return now() < bundle.accident_cooldown_t


func reset_cooldown(bundle: MenuPreviewActorAIState) -> void:
	bundle.accident_cooldown_t = now() + randf_range(COOLDOWN_MIN, COOLDOWN_MAX)


## 後ろ（+z）にノコギリがいなければ、コンベアの後端まで走って海へ落ちられる
func ocean_run_up_clear() -> bool:
	return host._saw_safe_depth() > Geo.BELT_EDGE_FALL_Z + 0.3


func try_start(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	var crash_first := randf() < CRASH_RATIO or not ocean_run_up_clear()
	var started := false
	if crash_first:
		started = start_collision(bundle, is_p1) or (ocean_run_up_clear() and start_ocean(bundle, is_p1))
	else:
		started = start_ocean(bundle, is_p1) or start_collision(bundle, is_p1)
	return started


func start_collision(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not gs() or not alive(is_p1):
		return false
	if host._door_learning.is_commit_active(bundle):
		return false
	if bundle.pending_accident != AIState.PENDING_ACCIDENT_NONE:
		return false
	var wall := pick_upcoming_wall(bundle)
	if not wall:
		return false
	bundle.pending_accident = AIState.PENDING_ACCIDENT_WALL
	bundle.pending_accident_wall = wall
	wall.set_meta("preview_accident_owner", bundle)
	set_moving_back(is_p1, false)
	bundle.target_x = pick_crash_x(wall)
	bundle.lane_shift_speed = randf_range(MenuActorAI.LANE_SHIFT_SPEED_MIN, MenuActorAI.LANE_SHIFT_SPEED_MAX)
	bundle.lane_shift_active = true
	bundle.target_local_z = host._ai.clamp_depth_target_z(local_z(is_p1) + randf_range(-0.8, 0.8))
	bundle.depth_shift_speed = randf_range(MenuActorAI.DEPTH_SHIFT_SPEED_MIN, MenuActorAI.DEPTH_SHIFT_SPEED_MAX)
	bundle.depth_shift_active = true
	reset_cooldown(bundle)
	return true


func start_ocean(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not gs() or not alive(is_p1):
		return false
	if bundle.pending_accident != AIState.PENDING_ACCIDENT_NONE or not ocean_run_up_clear():
		return false
	bundle.pending_accident = AIState.PENDING_ACCIDENT_OCEAN
	bundle.pending_accident_wall = null
	bundle.lane_shift_active = false
	bundle.target_local_z = Geo.BELT_EDGE_FALL_Z + randf_range(0.35, 0.65)
	bundle.depth_shift_speed = randf_range(MenuActorAI.DEPTH_SHIFT_SPEED_MIN, MenuActorAI.DEPTH_SHIFT_SPEED_MAX)
	bundle.depth_shift_active = true
	reset_cooldown(bundle)
	return true


## 不正解の扉か、扉と扉のあいだの壁。正解の扉を選んで「くぐれるのに死ぬ」ことはしない。
func pick_crash_x(wall: Node3D) -> float:
	var correct_door := int(wall.get_meta("preview_correct_door", -1)) if wall else -1
	var target_x := randf_range(-1.1, 1.1)
	if randf() < WRONG_DOOR_SHARE:
		if correct_door == 0:
			target_x = Geo.DOOR_X_RIGHT
		elif correct_door == Geo.RED_DOOR_INDEX:
			target_x = Geo.DOOR_X_LEFT
		target_x += randf_range(-0.35, 0.35)
	return clampf(target_x, MenuActorAI.PLAYER_X_MIN, MenuActorAI.PLAYER_X_MAX)


func pick_upcoming_wall(for_bundle: MenuPreviewActorAIState = null) -> Node3D:
	var candidate: Node3D = null
	var best_z := INF
	for wall in host._preview_walls:
		if not wall_available(wall, for_bundle):
			continue
		var z := wall.position.z
		if z < WALL_PICK_Z_MIN or z > WALL_PICK_Z_MAX:
			continue
		if z < best_z:
			best_z = z
			candidate = wall
	return candidate


func wall_available(wall: Node3D, for_bundle: MenuPreviewActorAIState) -> bool:
	if not is_instance_valid(wall):
		return false
	if bool(wall.get_meta("preview_door_broken", false)):
		return false
	if wall.has_meta("preview_accident_owner"):
		var accident_owner = wall.get_meta("preview_accident_owner")
		if accident_owner != null and accident_owner != for_bundle:
			return false
	for bundle: MenuPreviewActorAIState in [host._p1_ai, host._p2_ai]:
		if bundle != for_bundle and bundle.pending_accident == AIState.PENDING_ACCIDENT_WALL and bundle.pending_accident_wall == wall:
			return false
	return true


func update_pending_wall(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.pending_accident != AIState.PENDING_ACCIDENT_WALL:
		return
	if not is_instance_valid(bundle.pending_accident_wall):
		clear_pending(bundle)
		return
	if absf(x(is_p1) - bundle.target_x) <= 0.05:
		return
	bundle.lane_shift_active = true
	if bundle.lane_shift_speed <= 0.01:
		bundle.lane_shift_speed = randf_range(MenuActorAI.LANE_SHIFT_SPEED_MIN, MenuActorAI.LANE_SHIFT_SPEED_MAX)


## 海への助走：後端を越えたら落下の状態へ渡す（ノコギリに道をふさがれたら MenuWallBackgroundPreview._avoid_saw が取りやめる）
func update_pending_ocean(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.pending_accident != AIState.PENDING_ACCIDENT_OCEAN:
		return
	if host._is_past_belt_edge(is_p1):
		clear_pending(bundle)
		host._ai.start_ocean_fall(bundle, is_p1)
		return
	if not bundle.depth_shift_active:
		bundle.depth_shift_active = true


func should_force_wall_crash(bundle: MenuPreviewActorAIState, wall: Node3D) -> bool:
	return (
		bundle.pending_accident == AIState.PENDING_ACCIDENT_WALL
		and bundle.pending_accident_wall == wall
		and is_instance_valid(wall)
	)


func release_wall_claim(wall: Node3D) -> void:
	if is_instance_valid(wall) and wall.has_meta("preview_accident_owner"):
		wall.remove_meta("preview_accident_owner")


func wall_reserved_for_crash(wall: Node3D) -> bool:
	for bundle: MenuPreviewActorAIState in [host._p1_ai, host._p2_ai]:
		if bundle.pending_accident == AIState.PENDING_ACCIDENT_WALL and bundle.pending_accident_wall == wall:
			return true
	return false
