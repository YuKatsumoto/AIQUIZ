class_name MenuActorAccidents
extends MenuActorComponent

## 潜伏型の事故の後始末（AI の状態は NORMAL のまま pending_accident を立て、壁や縁に着いたところで起きる）。
## ノコギリのヒヤリ・事故（MenuWallBackgroundPreview._start_saw_accident）が使う。
## 壁への激突・海への転落を AI がわざと選ぶことはしない（以前からの動き）。


func clear_pending(bundle: MenuPreviewActorAIState) -> void:
	var wall := bundle.pending_accident_wall
	if wall != null and is_instance_valid(wall):
		if wall.has_meta("preview_accident_owner") and wall.get_meta("preview_accident_owner") == bundle:
			wall.remove_meta("preview_accident_owner")
	bundle.pending_accident = AIState.PENDING_ACCIDENT_NONE
	bundle.pending_accident_wall = null


func update_pending_wall(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.pending_accident != AIState.PENDING_ACCIDENT_WALL:
		return
	if not is_instance_valid(bundle.pending_accident_wall):
		clear_pending(bundle)
		return
	if absf(x(is_p1) - bundle.target_x) <= 0.05:
		return
	bundle.lane_shift_active = true


## 海への助走：後端を越えたら落下の状態へ渡す
func update_pending_ocean(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.pending_accident != AIState.PENDING_ACCIDENT_OCEAN:
		return
	if host._is_past_belt_edge(is_p1):
		clear_pending(bundle)
		host._ai.start_ocean_fall(bundle, is_p1)
		return
	var next_z := move_toward(local_z(is_p1), bundle.target_local_z, bundle.depth_shift_speed * dt)
	set_local_z(is_p1, host._ai.clamp_depth_target_z(next_z, bundle))


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
