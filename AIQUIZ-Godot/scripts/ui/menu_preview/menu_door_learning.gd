class_name MenuDoorLearning
extends MenuActorComponent

## 近づいてくる壁の扉へ向かう「学習コミット」。本物の問題が載った壁では正解の扉を狙い、
## 迷い・ミスのぶれは MenuPreviewDoorLearner が受け持つ。

const APPROACH_MIN_DIST: float = 0.4
const APPROACH_MAX_DIST: float = 18.0


func skill(bundle: MenuPreviewActorAIState) -> float:
	return bundle.door_learner.get_skill() if bundle.door_learner else 0.0


func is_commit_active(bundle: MenuPreviewActorAIState) -> bool:
	return (
		bundle.learn_intended_action >= 0
		and bundle.learn_approach_wall != null
		and is_instance_valid(bundle.learn_approach_wall)
		and not bundle.learn_episode_reported
	)


func clear_commit(bundle: MenuPreviewActorAIState, home: float = Geo.PLAYER_X) -> void:
	bundle.learn_approach_wall = null
	bundle.learn_intended_action = -1
	bundle.learn_target_x = home
	bundle.learn_episode_reported = false


func update_approach(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not gs() or not bundle.door_learner:
		return
	if not alive(is_p1) or bundle.ai_state != AIState.STATE_NORMAL:
		return
	# エモート中は立ち止まって踊る（壁が来る前に踊りを切り上げるので、そのあと扉へ向かう）
	if bundle.is_emoting or is_commit_active(bundle):
		return
	var candidate := pick_target_wall(local_z(is_p1))
	if not candidate:
		return
	bundle.learn_approach_wall = candidate
	var learner_action := int(bundle.door_learner.pick_door_action())
	var correct_door := int(candidate.get_meta("preview_correct_door", -1))
	# 本物の問題が載った壁では正解の扉を狙う (迷い・ミスの揺らぎは door_learner が担う)
	bundle.learn_intended_action = correct_door if correct_door >= 0 else learner_action
	bundle.learn_target_x = clampf(
		bundle.door_learner.target_x_for_action(bundle.learn_intended_action),
		MenuActorAI.PLAYER_X_MIN,
		MenuActorAI.PLAYER_X_MAX
	)
	bundle.learn_episode_reported = false
	bundle.target_x = bundle.learn_target_x
	if bundle.lane_shift_speed < MenuActorAI.LANE_SHIFT_SPEED_MIN:
		bundle.lane_shift_speed = MenuActorAI.LANE_SHIFT_SPEED_MIN
	bundle.lane_shift_active = true


func pick_target_wall(player_z: float) -> Node3D:
	var best_wall: Node3D = null
	var best_dist := INF
	for wall in host._preview_walls:
		if not is_instance_valid(wall) or not wall.visible:
			continue
		if not bool(wall.get_meta("preview_should_break_door", true)):
			continue
		if bool(wall.get_meta("preview_door_broken", false)):
			continue
		var door_leading_z := wall.position.z + Geo.DOOR_HALF_DEPTH_Z
		if Geo.wall_front_touches_player(door_leading_z, player_z):
			continue
		var dist := player_z - door_leading_z
		if dist < APPROACH_MIN_DIST or dist > APPROACH_MAX_DIST:
			continue
		if dist < best_dist:
			best_dist = dist
			best_wall = wall
	return best_wall


func record_outcome_for_wall(wall: Node3D, reward: float, bundle: MenuPreviewActorAIState) -> void:
	if not wall or wall != bundle.learn_approach_wall or bundle.learn_episode_reported:
		return
	if bundle.learn_intended_action < 0:
		clear_commit(bundle, home_x(bundle))
		return
	if bundle.door_learner:
		bundle.door_learner.record_outcome(bundle.learn_intended_action, reward)
	bundle.learn_episode_reported = true
	clear_commit(bundle, home_x(bundle))


func on_wall_removed(wall: Node3D) -> void:
	for bundle: MenuPreviewActorAIState in [host._p1_ai, host._p2_ai]:
		if wall != bundle.learn_approach_wall:
			continue
		if bundle.learn_episode_reported:
			clear_commit(bundle, home_x(bundle))
			continue
		record_outcome_for_wall(wall, 0.0, bundle)
