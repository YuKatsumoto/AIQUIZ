class_name MenuActorAI
extends MenuActorComponent

## メニュー背景ランナー 1 人ずつの AI：状態の切り替え、行動の実行、加減速つきの移動、ジャンプ、
## 吹き飛び（ゴーストの体当たり）、海への落下、死亡から復活まで。
## 書く先は持ち主の _preview_gs（PlayerController がそれを描く）。

const Picker = preload("res://scripts/ui/menu_preview/menu_actor_action_picker.gd")
const Motor = preload("res://scripts/ui/menu_preview/menu_runner_motor.gd")

const ACTION_INTERVAL_MIN: float = 1.1
const ACTION_INTERVAL_MAX: float = 2.6
## 2Pメニュープレビューでは行動の切り替え時刻をずらし、同時に同じ動きへ入るのを防ぐ。
const P1_2P_ACTION_INTERVAL_SCALE: float = 0.82
const P2_2P_ACTION_INTERVAL_SCALE: float = 1.18
## 目標位置と走行アニメの個体差。ゲーム本編には影響せず、メニュープレビューだけに適用する。
const TARGET_SEPARATION_X_2P: float = 1.45
const TARGET_SEPARATION_Z_2P: float = 1.10
const P1_RUN_ANIM_MULT_2P: float = 0.92
const P2_RUN_ANIM_MULT_2P: float = 1.08
## 本編の走りのアニメは 1 倍でこの速さ（m/s）の走りに見える
const RUN_ANIM_NATURAL_SPEED: float = 3.5
const DEPTH_STEP_MIN: float = 1.0
const DEPTH_STEP_MAX: float = 3.4
## 2P 中に左右ドア付近へ寄る確率
const EDGE_WANDER_CHANCE_2P: float = 0.12
const DOOR_VISIT_CHANCE: float = 0.55
## 左右ドア（±3.5）の両方へ行ける X 範囲
const PLAYER_X_MIN: float = Geo.DOOR_X_LEFT - 0.35
const PLAYER_X_MAX: float = Geo.DOOR_X_RIGHT + 0.35
const LANE_SHIFT_SPEED_MIN: float = 2.2
const LANE_SHIFT_SPEED_MAX: float = 3.6
const DEPTH_SHIFT_SPEED_MIN: float = 2.0
const DEPTH_SHIFT_SPEED_MAX: float = 4.0
const JUMP_SPEED_MIN: float = 6.4
const JUMP_SPEED_MAX: float = 7.4
## 踏み切る前に一瞬沈む
const JUMP_PREP_SECONDS: float = 0.1
const GRAVITY: float = 26.0
const DEAD_TO_RESPAWN_MIN: float = 3.2
const DEAD_TO_RESPAWN_MAX: float = 4.1
const RESPAWN_START_Y_MIN: float = 5.5
const RESPAWN_START_Y_MAX: float = 7.0
const RESPAWN_DOWN_SPEED_MIN: float = 5.1
const RESPAWN_DOWN_SPEED_MAX: float = 6.9
## 復活して着地してから、この秒数かけて走り出す
const RESPAWN_RAMP_SECONDS: float = 0.35
const ACRO_DURATION_MIN: float = 2.4
const ACRO_DURATION_MAX: float = 4.0
const ACRO_JUMP_SPEED_MIN: float = 8.2
const ACRO_JUMP_SPEED_MAX: float = 10.2
const ACRO_BURST_INTERVAL_MIN: float = 1.15
const ACRO_BURST_INTERVAL_MAX: float = 2.05
const ACRO_RETARGET_MIN: float = 0.25
const ACRO_RETARGET_MAX: float = 0.45
## アクロバット中に踊り出す割合（毎秒）と、その踊りの長さ
const ACRO_EMOTE_BURST_RATE: float = 0.35
const ACRO_EMOTE_BURST_DURATION_MIN: float = 2.8
const ACRO_EMOTE_BURST_DURATION_MAX: float = 4.5
## 吹き飛びから立ち直る速さ（これより遅く、着地していて、操作できない時間が過ぎたら走りに戻る）
const KNOCKBACK_RECOVER_SPEED: float = 0.8
const KNOCKBACK_X_LIMIT: float = StageConstants.FLOOR_HALF_WIDTH - 0.5
const KNOCKBACK_Z_BACK_PAD: float = 1.1
const DODGE_SPEED: float = 4.6
const DODGE_DISTANCE_MIN: float = 1.8
const DODGE_DISTANCE_MAX: float = 2.4
const DODGE_SECONDS: float = 0.75

## わざと起こす事故（壁への激突・海への転落）を選ぶか。PV 撮影は止める（以前は事故が選ばれなかったので、その見た目で撮る）
static var accidents_enabled: bool = true

var rng := RandomNumberGenerator.new()
var _picker_context := Picker.Context.new()


func _init(p_host: MenuWallBackgroundPreview) -> void:
	super(p_host)
	rng.randomize()


func update_actor(dt: float, is_p1: bool) -> void:
	if not gs():
		return
	var bundle := bundle_for(is_p1)
	_detect_teleport(bundle, is_p1)
	_update_jump_trigger_ttl(dt, bundle, is_p1)
	match bundle.ai_state:
		AIState.STATE_NORMAL:
			_update_normal(dt, bundle, is_p1)
		AIState.STATE_KNOCKBACK:
			_update_knockback(dt, bundle, is_p1)
		AIState.STATE_OCEAN_FALL:
			_update_ocean_fall(dt, bundle, is_p1)
		AIState.STATE_DEAD:
			_update_dead(dt, bundle, is_p1)
		AIState.STATE_RESPAWN:
			host._ai_emotes.stop_emote(bundle, is_p1)
			set_moving_back(is_p1, false)
			_update_respawn_drop(dt, bundle, is_p1)
		AIState.STATE_ACROBATICS:
			_update_acrobatics(dt, bundle, is_p1)
		AIState.STATE_TAUNT:
			_update_taunt(dt, bundle, is_p1)
	if bundle.ai_state not in [AIState.STATE_DEAD, AIState.STATE_OCEAN_FALL]:
		enforce_floor_support(bundle, is_p1)
	_remember_written(bundle, is_p1)


func _update_normal(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	host._avoid_saw(bundle, is_p1)
	if bundle.pending_accident == AIState.PENDING_ACCIDENT_NONE:
		host._door_learning.update_approach(bundle, is_p1)
		_keep_door_commit_lane(bundle, is_p1)
	_update_jump_prep(bundle, is_p1)
	update_lane_shift(dt, bundle, is_p1)
	update_depth_shift(dt, bundle, is_p1)
	_update_moving_back(bundle, is_p1)
	update_ground_movement(dt, bundle, is_p1)
	host._accidents.update_pending_wall(bundle, is_p1)
	host._accidents.update_pending_ocean(bundle, is_p1)
	host._update_pending_saw_accident(bundle, is_p1)
	if bundle.ai_state != AIState.STATE_NORMAL:
		return
	host._ai_emotes.update_emote_timer(bundle, is_p1)
	if now() >= bundle.next_action_t:
		roll_next_action(bundle, is_p1)
		bundle.next_action_t = now() + next_action_delay(is_p1)


## 扉へ向かっているあいだは、ほかの行動が横の目標を書き換えても扉の位置へ戻す
## （踊っているとき・よけているときは除く。踊りは壁に間に合う長さで切り上げる）。
func _keep_door_commit_lane(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.is_emoting or bundle.is_dodging(now()) or not host._door_learning.is_commit_active(bundle):
		return
	if absf(bundle.target_x - bundle.learn_target_x) > 0.001 or (
		not bundle.lane_shift_active and absf(x(is_p1) - bundle.learn_target_x) > 0.05
	):
		bundle.target_x = bundle.learn_target_x
		bundle.lane_shift_speed = maxf(bundle.lane_shift_speed, LANE_SHIFT_SPEED_MIN)
		bundle.lane_shift_active = true


func next_action_delay(is_p1: bool) -> float:
	var delay := rng.randf_range(ACTION_INTERVAL_MIN, ACTION_INTERVAL_MAX)
	if not is_2p():
		return delay
	return delay * (P1_2P_ACTION_INTERVAL_SCALE if is_p1 else P2_2P_ACTION_INTERVAL_SCALE)


func roll_next_action(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not gs() or not alive(is_p1):
		return
	# 踊りは正解の扉をくぐった時だけ、事故は進行中のものを優先し、よけている最中は割り込まない
	if bundle.is_emoting or bundle.pending_accident != AIState.PENDING_ACCIDENT_NONE or bundle.is_dodging(now()):
		return
	# 相手のゴーストのサメが来るのを見ているあいだは、扉へ向かう以外は動かない
	if bundle.ghost_mode == AIState.GHOST_MODE_WATCH:
		return
	var ctx := _picker_context
	ctx.skill = host._door_learning.skill(bundle)
	ctx.is_2p = is_2p()
	ctx.grounded = grounded(is_p1) and bundle.jump_prep_until < 0.0
	ctx.ghost_alert = bundle.ghost_mode != AIState.GHOST_MODE_NONE
	ctx.accident_allowed = (
		accidents_enabled
		and not ctx.ghost_alert
		and not host._accidents.on_cooldown(bundle)
		and not host._door_learning.is_commit_active(bundle)
	)
	ctx.acro_allowed = not ctx.ghost_alert
	ctx.conveyor_paused = host._conveyor_paused
	match Picker.pick(ctx, rng):
		Picker.Action.HOLD:
			hold(bundle)
		Picker.Action.LANE_SHIFT:
			start_lane_shift(bundle, is_p1)
		Picker.Action.DASH:
			start_dash_move(false, bundle, is_p1)
		Picker.Action.STEP_FORWARD:
			if not start_depth_step(bundle, is_p1, true):
				start_lane_shift(bundle, is_p1)
		Picker.Action.STEP_BACK:
			if not start_depth_step(bundle, is_p1, false):
				start_lane_shift(bundle, is_p1)
		Picker.Action.JUMP:
			if not start_jump(bundle, is_p1):
				start_lane_shift(bundle, is_p1)
		Picker.Action.ACROBATICS:
			if not start_acrobatics(bundle, is_p1):
				start_dash_move(true, bundle, is_p1)
		Picker.Action.ACCIDENT:
			if not host._accidents.try_start(bundle, is_p1):
				start_dash_move(false, bundle, is_p1)


## その場でコンベアに合わせて走り続ける（横・前後の移動はブレーキで止める）。
func hold(bundle: MenuPreviewActorAIState) -> void:
	bundle.lane_shift_active = false
	bundle.depth_shift_active = false


## 横だけ動く。
func start_lane_shift(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	_set_lane_target(bundle, is_p1, false)


## 横と前後を同時に動く。
func start_dash_move(is_acro: bool, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not gs():
		return
	_set_lane_target(bundle, is_p1, is_acro)
	var depth_hint := 0
	if not is_acro and rng.randf() < 0.72:
		depth_hint = 1 if rng.randf() < 0.5 else -1
	var next_z := clamp_depth_target_z(pick_depth_target_z(is_p1, depth_hint), bundle)
	if should_separate_2p_target(bundle):
		var other := other_bundle(bundle)
		if absf(next_z - other.target_local_z) < TARGET_SEPARATION_Z_2P:
			next_z = clamp_depth_target_z(
				other.target_local_z + (-TARGET_SEPARATION_Z_2P if is_p1 else TARGET_SEPARATION_Z_2P),
				bundle
			)
	bundle.target_local_z = next_z
	bundle.depth_shift_speed = rng.randf_range(
		DEPTH_SHIFT_SPEED_MIN + (0.7 if is_acro else 0.0),
		DEPTH_SHIFT_SPEED_MAX + (1.3 if is_acro else 0.0)
	)
	bundle.depth_shift_active = true


func _set_lane_target(bundle: MenuPreviewActorAIState, is_p1: bool, is_acro: bool) -> void:
	var skill := host._door_learning.skill(bundle)
	var next_x := clampf(pick_dash_target_x(bundle), PLAYER_X_MIN, PLAYER_X_MAX)
	if absf(next_x - x(is_p1)) < 0.28:
		next_x = clampf(next_x + rng.randf_range(-0.85, 0.85), PLAYER_X_MIN, PLAYER_X_MAX)
	if should_separate_2p_target(bundle):
		var other := other_bundle(bundle)
		if absf(next_x - other.target_x) < TARGET_SEPARATION_X_2P:
			next_x = clampf(
				other.target_x + (-TARGET_SEPARATION_X_2P if is_p1 else TARGET_SEPARATION_X_2P),
				PLAYER_X_MIN,
				PLAYER_X_MAX
			)
	bundle.target_x = next_x
	bundle.lane_shift_speed = rng.randf_range(
		LANE_SHIFT_SPEED_MIN + (0.7 if is_acro else 0.0),
		lerpf(LANE_SHIFT_SPEED_MAX, 3.8, skill) + (1.1 if is_acro else 0.0)
	)
	bundle.lane_shift_active = true


func should_separate_2p_target(bundle: MenuPreviewActorAIState) -> bool:
	return (
		is_2p()
		and bundle.pending_accident == AIState.PENDING_ACCIDENT_NONE
		and not host._door_learning.is_commit_active(bundle)
	)


func pick_dash_target_x(bundle: MenuPreviewActorAIState) -> float:
	if host._door_learning.is_commit_active(bundle):
		return bundle.learn_target_x
	if is_2p() and rng.randf() < EDGE_WANDER_CHANCE_2P:
		var door_x := Geo.DOOR_X_LEFT if rng.randf() < 0.5 else Geo.DOOR_X_RIGHT
		return clampf(door_x + rng.randf_range(-0.35, 0.35), PLAYER_X_MIN, PLAYER_X_MAX)
	var learned_pick_chance := lerpf(0.25, 0.75, host._door_learning.skill(bundle))
	if bundle.door_learner and rng.randf() < learned_pick_chance:
		var action := int(bundle.door_learner.pick_door_action())
		return clampf(bundle.door_learner.target_x_for_action(action), PLAYER_X_MIN, PLAYER_X_MAX)
	if rng.randf() < DOOR_VISIT_CHANCE:
		var door_x := Geo.DOOR_X_LEFT if rng.randf() < 0.5 else Geo.DOOR_X_RIGHT
		return clampf(door_x + rng.randf_range(-0.45, 0.45), PLAYER_X_MIN, PLAYER_X_MAX)
	return rng.randf_range(PLAYER_X_MIN, PLAYER_X_MAX)


func pick_depth_target_z(is_p1: bool, forward_hint: int = 0) -> float:
	var cur := local_z(is_p1)
	var step := rng.randf_range(DEPTH_STEP_MIN, DEPTH_STEP_MAX)
	# 本編と同じ: 前進は -Z（壁方向）、後退は +Z
	if forward_hint > 0:
		return clamp_depth_target_z(cur - step)
	if forward_hint < 0:
		return clamp_depth_target_z(cur + step)
	return clamp_depth_target_z(rng.randf_range(Geo.BELT_Z_MIN, Geo.BELT_Z_MAX))


func start_depth_step(bundle: MenuPreviewActorAIState, is_p1: bool, forward: bool) -> bool:
	if not gs():
		return false
	var cur := local_z(is_p1)
	var target := clamp_depth_target_z(pick_depth_target_z(is_p1, 1 if forward else -1))
	if absf(target - cur) < 0.3:
		return false
	bundle.target_local_z = target
	bundle.depth_shift_speed = rng.randf_range(DEPTH_SHIFT_SPEED_MIN, DEPTH_SHIFT_SPEED_MAX)
	bundle.depth_shift_active = true
	return true


## 前後に動ける奥の上限（+z がカメラ側・コンベアの後端）。後ろのノコギリの手前で止まる。
func max_depth_z_for_bundle(bundle: MenuPreviewActorAIState = null) -> float:
	var belt_max := minf(Geo.BELT_Z_MAX, host._saw_safe_depth())
	if bundle == null:
		return belt_max
	if bundle.pending_accident == AIState.PENDING_ACCIDENT_OCEAN:
		# 縁を越えた落下は止めない。手前の助走はノコギリがふさいでいれば止まる。
		if host._is_past_belt_edge(bundle == host._p1_ai):
			return Geo.OCEAN_DEPTH_MAX
		return minf(Geo.OCEAN_DEPTH_MAX, host._saw_safe_depth())
	if bundle.pending_accident != AIState.PENDING_ACCIDENT_SAW or host._saw_near_miss:
		return belt_max
	return Geo.BELT_Z_MAX


func clamp_depth_target_z(z: float, bundle: MenuPreviewActorAIState = null) -> float:
	return clampf(z, Geo.BELT_Z_MIN, max_depth_z_for_bundle(bundle))


## 着地直後は少しずつ走り出す
func _cruise_scale(bundle: MenuPreviewActorAIState) -> float:
	return smoothstep(0.0, RESPAWN_RAMP_SECONDS, now() - bundle.landed_at_t)


func update_lane_shift(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not gs():
		return
	var pos := x(is_p1)
	if bundle.lane_shift_active:
		var accel := Motor.DODGE_ACCEL if bundle.is_dodging(now()) else Motor.LANE_ACCEL
		var step := Motor.steer_axis(
			pos, bundle.vel_x, bundle.target_x, bundle.lane_shift_speed * _cruise_scale(bundle),
			accel, Motor.LANE_DECEL, dt
		)
		set_x(is_p1, step.x)
		bundle.vel_x = step.y
		if step.z > 0.5:
			bundle.lane_shift_active = false
	else:
		var braked := Motor.brake_axis(pos, bundle.vel_x, Motor.LANE_DECEL, dt)
		var limited := clampf(braked.x, PLAYER_X_MIN - 1.0, PLAYER_X_MAX + 1.0)
		set_x(is_p1, limited)
		bundle.vel_x = braked.y if is_equal_approx(limited, braked.x) else 0.0


func update_depth_shift(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not gs():
		return
	bundle.target_local_z = clamp_depth_target_z(bundle.target_local_z, bundle)
	var before_z := local_z(is_p1)
	var next_z := before_z
	var next_vel := 0.0
	var reached := false
	if bundle.depth_shift_active:
		var accel := Motor.DODGE_ACCEL if bundle.is_dodging(now()) else Motor.DEPTH_ACCEL
		var step := Motor.steer_axis(
			before_z, bundle.vel_z, bundle.target_local_z, bundle.depth_shift_speed * _cruise_scale(bundle),
			accel, Motor.DEPTH_DECEL, dt
		)
		next_z = step.x
		next_vel = step.y
		reached = step.z > 0.5
	else:
		var braked := Motor.brake_axis(before_z, bundle.vel_z, Motor.DEPTH_DECEL, dt)
		next_z = braked.x
		next_vel = braked.y
	# 安全な範囲の外にいるランナーは、範囲へ戻る向きには歩ける（その場へ引き戻さない）
	var clamped := clampf(next_z, Geo.BELT_Z_MIN, maxf(before_z, max_depth_z_for_bundle(bundle)))
	if not is_equal_approx(clamped, next_z):
		# 端に押し付けている：その向きの速さを捨てる。目標がその端の向こうなら、着いたことにする
		# （止まりきれずに端へ当たっただけで、目標が反対側なら動きは続ける）
		next_vel = 0.0
		if (bundle.target_local_z - clamped) * (next_z - clamped) > 0.0:
			reached = bundle.depth_shift_active
	set_local_z(is_p1, clamped)
	bundle.vel_z = next_vel
	if reached:
		bundle.depth_shift_active = false


## 進む向き：カメラ側（+z）へ下がっているときだけ moving_back
func _update_moving_back(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	set_moving_back(is_p1, not bundle.is_emoting and bundle.vel_z > 0.2)


func start_jump(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not gs() or bundle.is_emoting or not grounded(is_p1) or bundle.jump_prep_until >= 0.0:
		return false
	bundle.jump_prep_until = now() + JUMP_PREP_SECONDS
	bundle.jump_prep_speed = rng.randf_range(JUMP_SPEED_MIN, JUMP_SPEED_MAX)
	return true


func _update_jump_prep(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.jump_prep_until < 0.0 or now() < bundle.jump_prep_until:
		return
	bundle.jump_prep_until = -1.0
	if bundle.is_emoting or not grounded(is_p1):
		return
	_launch(bundle, is_p1, bundle.jump_prep_speed, 0.09)


func _launch(bundle: MenuPreviewActorAIState, is_p1: bool, speed: float, trigger_ttl: float) -> void:
	set_vel_y(is_p1, speed)
	set_jump_trigger(is_p1, true)
	bundle.jump_trigger_ttl = trigger_ttl


func update_ground_movement(dt: float, _bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not gs():
		return
	var floor_y := Geo.FLOOR_Y
	set_vel_y(is_p1, vel_y(is_p1) - GRAVITY * dt)
	var next_y := y(is_p1) + vel_y(is_p1) * dt
	if next_y <= floor_y:
		set_y(is_p1, floor_y)
		if vel_y(is_p1) < 0.0:
			set_vel_y(is_p1, 0.0)
	else:
		set_y(is_p1, next_y)


func _update_jump_trigger_ttl(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if bundle.jump_trigger_ttl > 0.0:
		bundle.jump_trigger_ttl = maxf(0.0, bundle.jump_trigger_ttl - dt)
		if bundle.jump_trigger_ttl <= 0.0:
			set_jump_trigger(is_p1, false)


func allows_below_floor(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if bundle.ai_state == AIState.STATE_OCEAN_FALL:
		return true
	return bundle.pending_accident == AIState.PENDING_ACCIDENT_OCEAN and host._is_past_belt_edge(is_p1)


func enforce_floor_support(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not gs() or allows_below_floor(bundle, is_p1):
		return
	var floor_y := Geo.FLOOR_Y
	if y(is_p1) < floor_y:
		set_y(is_p1, floor_y)
	if y(is_p1) <= floor_y + 0.001 and vel_y(is_p1) < 0.0:
		set_vel_y(is_p1, 0.0)


## テストの位置固定・復活・2P の登場などで位置が飛んだら、それまでの速度を捨てる
func _detect_teleport(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if absf(x(is_p1) - bundle.last_written_x) > Motor.TELEPORT_DISTANCE:
		bundle.vel_x = 0.0
	if absf(local_z(is_p1) - bundle.last_written_z) > Motor.TELEPORT_DISTANCE:
		bundle.vel_z = 0.0


func _remember_written(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	bundle.last_written_x = x(is_p1)
	bundle.last_written_z = local_z(is_p1)


## 2P の押し合い・カプセルの重なり解消で押し戻された向きの速さは捨てる（押し返しと走りがぶつかって震えないように）
func absorb_external_correction(is_p1: bool, before: Vector2) -> void:
	var bundle := bundle_for(is_p1)
	var dx := x(is_p1) - before.x
	var dz := local_z(is_p1) - before.y
	if absf(dx) > 0.0005 and signf(dx) != signf(bundle.vel_x):
		bundle.vel_x = 0.0
	if absf(dz) > 0.0005 and signf(dz) != signf(bundle.vel_z):
		bundle.vel_z = 0.0
	bundle.last_written_x = x(is_p1)
	bundle.last_written_z = local_z(is_p1)


func start_acrobatics(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:
	if not gs() or not alive(is_p1) or bundle.is_emoting:
		return false
	bundle.ai_state = AIState.STATE_ACROBATICS
	bundle.state_end_t = now() + rng.randf_range(ACRO_DURATION_MIN, ACRO_DURATION_MAX)
	bundle.next_acro_jump_t = now() + rng.randf_range(0.08, 0.35)
	bundle.next_acro_retarget_t = now() + rng.randf_range(ACRO_RETARGET_MIN, ACRO_RETARGET_MAX)
	start_dash_move(true, bundle, is_p1)
	return true


func _update_acrobatics(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	update_lane_shift(dt, bundle, is_p1)
	update_depth_shift(dt, bundle, is_p1)
	_update_moving_back(bundle, is_p1)
	update_ground_movement(dt, bundle, is_p1)
	if not bundle.is_emoting:
		if not bundle.lane_shift_active or not bundle.depth_shift_active or now() >= bundle.next_acro_retarget_t:
			start_dash_move(true, bundle, is_p1)
			bundle.next_acro_retarget_t = now() + rng.randf_range(ACRO_RETARGET_MIN, ACRO_RETARGET_MAX)
		if grounded(is_p1) and now() >= bundle.next_acro_jump_t:
			_launch(bundle, is_p1, rng.randf_range(ACRO_JUMP_SPEED_MIN, ACRO_JUMP_SPEED_MAX), 0.11)
			bundle.next_acro_jump_t = now() + rng.randf_range(ACRO_BURST_INTERVAL_MIN, ACRO_BURST_INTERVAL_MAX)
		elif grounded(is_p1) and rng.randf() < Motor.chance_per_frame(ACRO_EMOTE_BURST_RATE, dt):
			host._ai_emotes.start_emote(
				bundle, is_p1, rng.randf_range(ACRO_EMOTE_BURST_DURATION_MIN, ACRO_EMOTE_BURST_DURATION_MAX)
			)
	host._ai_emotes.update_emote_timer(bundle, is_p1)
	if now() >= bundle.state_end_t:
		bundle.ai_state = AIState.STATE_NORMAL
		bundle.next_action_t = now() + rng.randf_range(0.55, 1.4)


## 相手が死んだ：着地してから立ち止まり、飛んでいく相手を見ながら煽る。壁が迫ったら切り上げて扉へ。
func _update_taunt(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	set_jump_trigger(is_p1, false)
	set_moving_back(is_p1, false)
	bundle.lane_shift_active = false
	bundle.depth_shift_active = false
	update_lane_shift(dt, bundle, is_p1)
	update_depth_shift(dt, bundle, is_p1)
	update_ground_movement(dt, bundle, is_p1)
	if host._ai_emotes.must_leave_for_wall(is_p1):
		host._ai_emotes.end_taunt(is_p1, 0.0)
		return
	# リグ読込直後などに初回開始が失敗しても、死亡演出中は必ず再試行する。
	if grounded(is_p1) and emote(is_p1) == EmoteData.EMOTE_NONE:
		host._ai_emotes.start_taunt_emote(bundle, is_p1)


## ゴーストの突進をよける：dir（ローカル x, z）へ一気に踏み出す。roll なら前転。
func start_dodge(bundle: MenuPreviewActorAIState, is_p1: bool, dir: Vector2, roll: bool) -> bool:
	if not gs() or not alive(is_p1) or bundle.ai_state != AIState.STATE_NORMAL or not grounded(is_p1):
		return false
	if dir.length_squared() < 0.0001:
		return false
	if bundle.is_emoting:
		host._ai_emotes.stop_emote(bundle, is_p1)
	var step := dir.normalized() * rng.randf_range(DODGE_DISTANCE_MIN, DODGE_DISTANCE_MAX)
	bundle.target_x = clampf(x(is_p1) + step.x, PLAYER_X_MIN - 0.6, PLAYER_X_MAX + 0.6)
	bundle.target_local_z = clamp_depth_target_z(local_z(is_p1) + step.y, bundle)
	bundle.lane_shift_speed = DODGE_SPEED
	bundle.depth_shift_speed = DODGE_SPEED
	bundle.lane_shift_active = true
	bundle.depth_shift_active = true
	bundle.jump_prep_until = -1.0
	bundle.dodge_until = now() + DODGE_SECONDS
	bundle.dodge_roll = roll
	bundle.next_action_t = maxf(bundle.next_action_t, bundle.dodge_until + 0.2)
	return true


## ゴーストの体当たり。horizontal はローカル (x, z) の速さ。自分では動けない時間 lock のあいだ吹き飛ぶ。
func start_knockback(bundle: MenuPreviewActorAIState, is_p1: bool, horizontal: Vector2, up_speed: float, lock: float) -> void:
	if not gs() or not alive(is_p1):
		return
	if bundle.ai_state == AIState.STATE_TAUNT:
		host._ai_emotes.end_taunt(is_p1)
	host._ai_emotes.stop_emote(bundle, is_p1)
	host._accidents.clear_pending(bundle)
	host._door_learning.clear_commit(bundle, home_x(bundle))
	if host._saw_accident_owner == (1 if is_p1 else 2):
		host._saw_accident_owner = 0
	bundle.ai_state = AIState.STATE_KNOCKBACK
	bundle.lane_shift_active = false
	bundle.depth_shift_active = false
	bundle.dodge_until = -1.0
	bundle.jump_prep_until = -1.0
	bundle.knockback_vel_x = horizontal.x
	bundle.knockback_vel_z = horizontal.y
	bundle.vel_x = horizontal.x
	bundle.vel_z = horizontal.y
	bundle.knockback_lock_until = now() + lock
	bundle.knockback_from = -horizontal.normalized() if horizontal.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	set_vel_y(is_p1, maxf(vel_y(is_p1), up_speed))
	set_jump_trigger(is_p1, false)
	set_moving_back(is_p1, false)


func _update_knockback(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	var step := Motor.knockback_step(
		Vector2(x(is_p1), local_z(is_p1)), Vector2(bundle.knockback_vel_x, bundle.knockback_vel_z), dt
	)
	var next_pos: Vector2 = step[0]
	var next_vel: Vector2 = step[1]
	var limited_x := clampf(next_pos.x, -KNOCKBACK_X_LIMIT, KNOCKBACK_X_LIMIT)
	if not is_equal_approx(limited_x, next_pos.x):
		next_vel.x = 0.0
	var limited_z := maxf(next_pos.y, Geo.BELT_Z_MIN - KNOCKBACK_Z_BACK_PAD)
	if not is_equal_approx(limited_z, next_pos.y):
		next_vel.y = 0.0
	set_x(is_p1, limited_x)
	set_local_z(is_p1, limited_z)
	bundle.knockback_vel_x = next_vel.x
	bundle.knockback_vel_z = next_vel.y
	bundle.vel_x = next_vel.x
	bundle.vel_z = next_vel.y
	set_vel_y(is_p1, vel_y(is_p1) - Motor.KNOCKBACK_GRAVITY * dt)
	var next_y := y(is_p1) + vel_y(is_p1) * dt
	if host._is_past_belt_edge(is_p1):
		# コンベアの後端を越えた：床がないので海へ落ちる
		set_y(is_p1, next_y)
		start_ocean_fall(bundle, is_p1)
		return
	if next_y <= Geo.FLOOR_Y:
		set_y(is_p1, Geo.FLOOR_Y)
		if vel_y(is_p1) < 0.0:
			set_vel_y(is_p1, 0.0)
	else:
		set_y(is_p1, next_y)
	if grounded(is_p1) and now() >= bundle.knockback_lock_until and next_vel.length() < KNOCKBACK_RECOVER_SPEED:
		bundle.ai_state = AIState.STATE_NORMAL
		bundle.target_x = x(is_p1)
		bundle.target_local_z = clamp_depth_target_z(local_z(is_p1), bundle)
		bundle.next_action_t = now() + rng.randf_range(0.35, 0.75)


## コンベアの後端から海へ落ちる（わざと走り込んだ事故も、ゴーストに吹き飛ばされたのも同じ落ち方）。
func start_ocean_fall(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	host._ai_emotes.stop_emote(bundle, is_p1)
	host._accidents.clear_pending(bundle)
	bundle.ai_state = AIState.STATE_OCEAN_FALL
	bundle.lane_shift_active = false
	bundle.depth_shift_active = false
	bundle.dodge_until = -1.0
	var carry := Vector2(bundle.vel_x, bundle.vel_z)
	if bundle.knockback_vel_x != 0.0 or bundle.knockback_vel_z != 0.0:
		carry = Vector2(bundle.knockback_vel_x, bundle.knockback_vel_z)
	# 縁から外へ出る勢いは残す
	carry.y = maxf(carry.y, 1.2)
	bundle.knockback_vel_x = carry.x
	bundle.knockback_vel_z = carry.y
	set_jump_trigger(is_p1, false)
	set_moving_back(is_p1, false)


func _update_ocean_fall(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	var horizontal := Motor.air_drag(Vector2(bundle.knockback_vel_x, bundle.knockback_vel_z), dt)
	bundle.knockback_vel_x = horizontal.x
	bundle.knockback_vel_z = horizontal.y
	bundle.vel_x = horizontal.x
	bundle.vel_z = horizontal.y
	set_x(is_p1, clampf(x(is_p1) + horizontal.x * dt, -KNOCKBACK_X_LIMIT, KNOCKBACK_X_LIMIT))
	set_local_z(is_p1, local_z(is_p1) + horizontal.y * dt)
	set_vel_y(is_p1, vel_y(is_p1) - GRAVITY * Motor.FALL_GRAVITY_SCALE * dt)
	set_y(is_p1, y(is_p1) + vel_y(is_p1) * dt)
	if y(is_p1) <= StageConstants.OCEAN_ENTRY_Y:
		set_y(is_p1, StageConstants.OCEAN_ENTRY_Y)
		host._trigger_preview_death("ocean", bundle, is_p1)


func _update_dead(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	set_moving_back(is_p1, false)
	host._add_actor_game_over_timer(is_p1, dt)
	if y(is_p1) <= StageConstants.OCEAN_ENTRY_Y:
		set_y(is_p1, move_toward(y(is_p1), StageConstants.OCEAN_SINK_Y, StageConstants.OCEAN_SINK_SPEED * dt))
		set_vel_y(is_p1, 0.0)
	if bundle.respawn_hold:
		return
	if now() >= bundle.dead_end_t and host._menu_saw.can_respawn(1 if is_p1 else 2):
		start_respawn(bundle, is_p1)


## 死んでから復活までの時間。壁への激突はラグドールと破片の演出が終わるまで待つ。
func death_duration(reason: String) -> float:
	var duration := rng.randf_range(DEAD_TO_RESPAWN_MIN, DEAD_TO_RESPAWN_MAX)
	if reason == "crash":
		duration = maxf(duration, QuizGameState.WALL_DEATH_SEQUENCE_DURATION)
	return duration


func start_respawn(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	if not gs():
		return
	host._ai_emotes.stop_survivor_taunt(is_p1)
	host._accidents.clear_pending(bundle)
	host._schedule_death_shard_cleanup(is_p1)
	host._rebuild_preview_player()
	bundle.ai_state = AIState.STATE_RESPAWN
	bundle.knockback_vel_x = 0.0
	bundle.knockback_vel_z = 0.0
	bundle.vel_x = 0.0
	bundle.vel_z = 0.0
	bundle.dodge_until = -1.0
	bundle.jump_prep_until = -1.0
	bundle.ghost_mode = AIState.GHOST_MODE_NONE
	bundle.respawn_hold = false
	host._set_actor_wall_impact(is_p1, false)
	if is_p1:
		gs().p1_saw_killed = false
	else:
		gs().p2_saw_killed = false
	host._set_actor_alive(is_p1, true)
	host._set_actor_game_over_timer(is_p1, 0.0)
	set_emote(is_p1, 0)
	set_jump_trigger(is_p1, false)
	set_moving_back(is_p1, false)
	set_x(is_p1, clampf(pick_dash_target_x(bundle), PLAYER_X_MIN, PLAYER_X_MAX))
	set_local_z(is_p1, pick_safe_respawn_local_z())
	host._push_walls_away_from_player(local_z(is_p1))
	set_y(is_p1, rng.randf_range(RESPAWN_START_Y_MIN, RESPAWN_START_Y_MAX))
	set_vel_y(is_p1, -rng.randf_range(RESPAWN_DOWN_SPEED_MIN, RESPAWN_DOWN_SPEED_MAX))
	bundle.target_x = x(is_p1)
	bundle.target_local_z = local_z(is_p1)
	bundle.lane_shift_active = false
	bundle.depth_shift_active = false
	host._accidents.reset_cooldown(bundle)


func _update_respawn_drop(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:
	set_vel_y(is_p1, vel_y(is_p1) - GRAVITY * dt)
	set_y(is_p1, y(is_p1) + vel_y(is_p1) * dt)
	if y(is_p1) <= Geo.FLOOR_Y:
		set_y(is_p1, Geo.FLOOR_Y)
		set_vel_y(is_p1, 0.0)
		set_moving_back(is_p1, false)
		bundle.ai_state = AIState.STATE_NORMAL
		bundle.landed_at_t = now()
		bundle.next_action_t = now() + rng.randf_range(0.45, 1.2)
		host._resume_preview_conveyor()


func pick_safe_respawn_local_z() -> float:
	var saw_limit: float = host._menu_saw.local_z - SawChaseState.BLADE_RADIUS - QuizGameState.PLAYER_BODY_RADIUS - 1.0
	var best_z := 0.0
	var best_clearance := -INF
	for _i in range(10):
		var trial_z := minf(
			rng.randf_range(Geo.BELT_Z_MIN * 0.35, Geo.BELT_Z_MAX * 0.55),
			saw_limit
		)
		var clearance := min_wall_front_gap(trial_z)
		if clearance > best_clearance:
			best_clearance = clearance
			best_z = trial_z
	if best_clearance < Geo.WALL_PLAYER_CLEAR_Z * 0.55:
		return minf(0.0, saw_limit)
	return best_z


func min_wall_front_gap(player_local_z: float) -> float:
	var min_gap := INF
	for wall in host._preview_walls:
		if not is_instance_valid(wall):
			continue
		var gap := wall.position.z + Geo.DOOR_HALF_DEPTH_Z - player_local_z
		min_gap = minf(min_gap, gap)
	return min_gap


## 位置と速度を初期化してすぐ走り出す（メニュー表示・出発の取りやめ・2P の登場）。
func reset_actor(bundle: MenuPreviewActorAIState, is_p1: bool, next_action_min: float, next_action_max: float) -> void:
	bundle.ai_state = AIState.STATE_NORMAL
	bundle.next_action_t = now() + rng.randf_range(next_action_min, next_action_max)
	bundle.emote_end_t = 0.0
	bundle.dead_end_t = 0.0
	bundle.state_end_t = 0.0
	bundle.target_x = x(is_p1) if gs() else home_x(bundle)
	bundle.lane_shift_speed = LANE_SHIFT_SPEED_MIN
	bundle.lane_shift_active = false
	bundle.target_local_z = 0.0
	bundle.depth_shift_speed = DEPTH_SHIFT_SPEED_MIN
	bundle.depth_shift_active = false
	bundle.vel_x = 0.0
	bundle.vel_z = 0.0
	bundle.last_written_x = INF
	bundle.last_written_z = INF
	bundle.jump_trigger_ttl = 0.0
	bundle.jump_prep_until = -1.0
	bundle.landed_at_t = -INF
	bundle.is_emoting = false
	host._accidents.clear_pending(bundle)
	bundle.blocking_wall = null
	host._accidents.reset_cooldown(bundle)
	bundle.next_acro_jump_t = 0.0
	bundle.next_acro_retarget_t = 0.0
	bundle.knockback_vel_x = 0.0
	bundle.knockback_vel_z = 0.0
	bundle.knockback_lock_until = 0.0
	bundle.dodge_until = -1.0
	bundle.ghost_mode = AIState.GHOST_MODE_NONE
	bundle.respawn_hold = false
	host._door_learning.clear_commit(bundle, home_x(bundle))
	bundle.last_emote = 0
	start_dash_move(false, bundle, is_p1)


## 本編の走りのアニメの速さ（PlayerController が pN_run_anim_speed_mult を掛ける）を、床に対する実際の速さに合わせる。
func update_run_anim_speed_multipliers(belt_speed: float) -> void:
	if not gs():
		return
	gs().p1_run_anim_speed_mult = _run_anim_speed_mult(host._p1_ai, true, belt_speed)
	gs().p2_run_anim_speed_mult = _run_anim_speed_mult(host._p2_ai, false, belt_speed)


func _run_anim_speed_mult(bundle: MenuPreviewActorAIState, is_p1: bool, belt_speed: float) -> float:
	if not gs() or not alive(is_p1):
		return 1.0
	var identity_mult := 1.0
	if is_2p():
		identity_mult = P1_RUN_ANIM_MULT_2P if is_p1 else P2_RUN_ANIM_MULT_2P
	if bundle.is_emoting or bundle.ai_state not in [AIState.STATE_NORMAL, AIState.STATE_ACROBATICS]:
		return identity_mult
	var gait_speed := Motor.belt_relative_velocity(bundle.vel_x, bundle.vel_z, belt_speed).length()
	# PlayerController 側は (wall_speed / 3.5) を下限 0.3 で掛けるので、その分を割り戻す
	var base_ratio := maxf(0.3, belt_speed / RUN_ANIM_NATURAL_SPEED)
	return clampf((gait_speed / RUN_ANIM_NATURAL_SPEED) / base_ratio, 0.2, 3.0) * identity_mult
