class_name MenuRunnerAnimator
extends RefCounted

## メニュー背景ランナー 1 人の見た目の仕上げ。PlayerController.update_from_state（本編と同じ描画：死亡・爆発・スキン・
## 押し合い・エモート）のあとに、ふつうに動いているあいだだけ姿勢を上書きする：
## 床に対する速さで足を運ぶ歩様（止まる・歩く・走る）、進む向きへの体の向き・前傾・傾き、ジャンプの踏み切り〜着地、
## 吹き飛び、海への落下、復活の落下、前転のよけ。切り替わりは前のフレームの姿から慣性でつなぐ。
## 本編の描画には手を入れない（PlayerController はメニューでも本編と同じ）。

const Gait = preload("res://scripts/ui/menu_preview/menu_runner_gait.gd")
const AIState = preload("res://scripts/ui/menu_preview_actor_ai_state.gd")

enum Mode { LEGACY, LOCOMOTION, JUMP, LANDING, KNOCKBACK, FALL, RESPAWN_FALL, DODGE_ROLL }

## テストと PV 撮影が止めるための全体のスイッチ（止めると本編と同じ描画のまま）
static var globally_enabled: bool = true

const BLEND_LEGACY: float = 0.25
const BLEND_BAND: float = 0.22
const BLEND_JUMP: float = 0.08
const BLEND_LAND: float = 0.05
const BLEND_LAND_TO_RUN: float = 0.2
const BLEND_KNOCKBACK: float = 0.06
const BLEND_FALL: float = 0.18
const YAW_RATE: float = 8.0
const TILT_RATE: float = 6.5
const ACCEL_RATE: float = 10.0
const LANDING_SECONDS: float = 0.32
## 上昇の速さがこれを下回ったら踏み切りの姿から空中の姿へ
const JUMP_LOOP_VY: float = 1.5
const JUMP_START_CLIP := "Jump_Start"
const JUMP_LOOP_CLIP := "Jump_Loop"
const JUMP_LAND_CLIP := "Jump_Land"
const NINJA_START_CLIP := "NinjaJump_Start"
const NINJA_LOOP_CLIP := "NinjaJump_Idle_Loop"
const NINJA_LAND_CLIP := "NinjaJump_Land"
const KNOCKBACK_CLIP := "Hit_Knockback"
const ROLL_CLIP := "Roll"
const WATCH_CLIP := "Idle_No_Loop"
const ROLL_SPEED: float = 1.6
## ゴーストを見ているあいだ、立ち止まっていればここまで振り向く
const WATCH_YAW_LIMIT: float = deg_to_rad(60.0)

var host: MenuWallBackgroundPreview
var is_p1: bool
var puppet: StagingPuppet = null
var mode: int = Mode.LEGACY
var band: int = Gait.IDLE
## 歩様の位相（左足の接地から何周目か）
var phase: float = 0.0
var yaw: float = Gait.FACING_YAW
var lean: float = 0.0
var bank: float = 0.0
## 計測（テスト用）：最後のフレームにかかった時間（マイクロ秒）と、いま当てているクリップ
var last_cost_usec: int = 0
var current_clip: String = ""

var _controller: PlayerController = null
var _mode_time: float = 0.0
var _clock: float = 0.0
var _landing_until: float = -1.0
var _landing_ninja: bool = false
var _prev_vel := Vector2.ZERO
var _accel := Vector2.ZERO
var _was_airborne: bool = false
var _airborne_ninja: bool = false
var _snapshot: Dictionary = {}
## 歩様の置き方に使う、直近の「床へ合わせるのに要る持ち上げ量」(時刻, 量)
var _plant_samples: Array[Vector2] = []


func _init(p_host: MenuWallBackgroundPreview, p_is_p1: bool) -> void:
	host = p_host
	is_p1 = p_is_p1


## 描画の PlayerController が作り直されたら付け替える（前の姿は捨てる）。
func bind(pc: PlayerController) -> void:
	if pc == _controller:
		return
	_controller = pc
	puppet = StagingPuppet.new(pc, 1 if is_p1 else 2) if pc != null else null
	_snapshot = {}
	mode = Mode.LEGACY


func _rig_ready() -> bool:
	if puppet == null or not is_instance_valid(_controller) or not puppet.is_ready():
		return false
	var rig := puppet.rig()
	return rig != null and rig.is_rigged and rig.aps.size() > AnimationRig.SLOT_UAL2 and rig.aps[AnimationRig.SLOT_UAL] != null


## update_from_state と煽り・エモートの向きを当てたあとに毎フレーム呼ぶ。
func update(dt: float, belt_speed: float) -> void:
	var started := Time.get_ticks_usec()
	_clock += dt
	if not _rig_ready():
		mode = Mode.LEGACY
		_snapshot = {}
		return
	var bundle := host._p1_ai if is_p1 else host._p2_ai
	var vel := Vector2(bundle.vel_x, bundle.vel_z)
	_accel = _accel.lerp((vel - _prev_vel) / maxf(dt, 0.0001), 1.0 - exp(-ACCEL_RATE * dt))
	_prev_vel = vel
	var next_mode := _choose_mode(bundle)
	if next_mode != mode:
		puppet.begin_blend_from(_snapshot, _blend_seconds(mode, next_mode))
		mode = next_mode
		_mode_time = 0.0
		_plant_samples.clear()
		if mode == Mode.LANDING:
			_landing_until = host._ai_time + LANDING_SECONDS
	else:
		_mode_time += dt
	match mode:
		Mode.LOCOMOTION:
			_pose_locomotion(dt, bundle, vel, belt_speed)
		Mode.JUMP:
			_pose_jump(dt, bundle)
		Mode.LANDING:
			_pose_landing(dt, bundle)
		Mode.KNOCKBACK:
			_pose_knockback(dt, bundle)
		Mode.FALL, Mode.RESPAWN_FALL:
			_pose_fall(dt, bundle)
		Mode.DODGE_ROLL:
			_pose_roll(dt, bundle, vel)
		_:
			current_clip = ""
			# 本編の描画のまま。歩様の向きは壁向きへ戻しておく（次に歩様へ戻るとき急に振れないように）
			yaw = lerp_angle(yaw, Gait.FACING_YAW, 1.0 - exp(-YAW_RATE * dt))
	puppet.apply_blend(dt)
	_snapshot = puppet.capture_display()
	last_cost_usec = Time.get_ticks_usec() - started


func _choose_mode(bundle: MenuPreviewActorAIState) -> int:
	var gs := host._preview_gs
	if not globally_enabled or not host._actor_alive(is_p1):
		_was_airborne = false
		return Mode.LEGACY
	match bundle.ai_state:
		AIState.STATE_DEAD, AIState.STATE_TAUNT:
			_was_airborne = false
			return Mode.LEGACY
		AIState.STATE_KNOCKBACK:
			return Mode.KNOCKBACK
		AIState.STATE_OCEAN_FALL:
			return Mode.FALL
		AIState.STATE_RESPAWN:
			_was_airborne = true
			_airborne_ninja = false
			return Mode.RESPAWN_FALL
	if bundle.is_emoting or host._actor_emote(is_p1) != EmoteData.EMOTE_NONE:
		return Mode.LEGACY
	# 体が触れて押し合っているあいだは、本編の押し合いの姿（構え・肩の当て合い・のけぞり）をそのまま見せる
	if gs.local_push.contact and bool(gs.get_local_push_pose(1 if is_p1 else 2).get("active", false)):
		return Mode.LEGACY
	var airborne := host._actor_y(is_p1) > 0.02 or host._actor_vel_y(is_p1) > 0.01 or bundle.jump_prep_until >= 0.0
	if airborne:
		if not _was_airborne:
			_airborne_ninja = bundle.ai_state == AIState.STATE_ACROBATICS
		_was_airborne = true
		return Mode.JUMP
	if _was_airborne:
		_was_airborne = false
		_landing_ninja = _airborne_ninja
		return Mode.LANDING
	if mode == Mode.LANDING and host._ai_time < _landing_until:
		return Mode.LANDING
	if bundle.is_dodging(host._ai_time) and bundle.dodge_roll:
		return Mode.DODGE_ROLL
	return Mode.LOCOMOTION


func _blend_seconds(from: int, to: int) -> float:
	if from == Mode.LEGACY or to == Mode.LEGACY:
		return BLEND_LEGACY
	match to:
		Mode.JUMP:
			return BLEND_JUMP
		Mode.LANDING:
			return BLEND_LAND
		Mode.KNOCKBACK:
			return BLEND_KNOCKBACK
		Mode.FALL, Mode.RESPAWN_FALL:
			return BLEND_FALL
	return BLEND_LAND_TO_RUN if from == Mode.LANDING else BLEND_BAND


func _position() -> Vector3:
	return Vector3(host._actor_x(is_p1), host._actor_y(is_p1), host._actor_local_z(is_p1))


func _stand(yaw_value: float, tilt: Basis = Basis.IDENTITY) -> void:
	var p := _position()
	puppet.stand_at(p, yaw_value, PlayerController.BASE_Y + p.y, tilt)


## 歩様の置き方：クリップの腰の上下（走りの浮き沈み・空中期）は残し、直近 1 周期でいちばん深く接地した足が
## 床に着く高さに合わせる（毎フレーム低いほうの足を床へ押し付けると、空中で振り出す足が床をこする）。
func _stand_gait(yaw_value: float, tilt: Basis, window: float) -> void:
	var parts := puppet.parts()
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis == null:
		return
	var p := _position()
	var ground := PlayerController.BASE_Y + p.y
	var hips := pelvis.position.y - PlayerController.BASE_Y
	pelvis.global_transform = Transform3D(tilt * Basis(Vector3.UP, yaw_value) * pelvis.basis, Vector3(p.x, ground + hips, p.z))
	var lowest: float = _controller.call("_lowest_intro_foot_mesh_y", parts)
	if not is_finite(lowest):
		return
	var need := ground + StagingPuppet.FOOT_CLEARANCE - lowest
	_plant_samples.append(Vector2(_clock, need))
	while _plant_samples.size() > 1 and _plant_samples[0].x < _clock - window:
		_plant_samples.pop_front()
	var offset := -INF
	for sample: Vector2 in _plant_samples:
		offset = maxf(offset, sample.y)
	pelvis.global_position.y += offset


func _turn_toward(target: float, dt: float) -> void:
	yaw = lerp_angle(yaw, target, 1.0 - exp(-YAW_RATE * dt))


func _pose_locomotion(dt: float, bundle: MenuPreviewActorAIState, vel: Vector2, belt_speed: float) -> void:
	var rel := MenuRunnerMotor.belt_relative_velocity(vel.x, vel.y, belt_speed)
	var watching := bundle.ghost_mode == AIState.GHOST_MODE_WATCH and rel.length() < 0.5
	var target := Gait.target_yaw(rel, Gait.yaw_limit(belt_speed, bundle.is_dodging(host._ai_time)))
	if watching:
		var to_shark := Vector2(bundle.ghost_watch_target.x - host._actor_x(is_p1), bundle.ghost_watch_target.z - host._actor_local_z(is_p1))
		if to_shark.length() > 0.5:
			var deviation := wrapf(atan2(to_shark.x, to_shark.y) - Gait.FACING_YAW, -PI, PI)
			target = Gait.FACING_YAW + clampf(deviation, -WATCH_YAW_LIMIT, WATCH_YAW_LIMIT)
	_turn_toward(target, dt)
	# 向いている向きの速さで足を運ぶ（横に残る分はわずかに滑る）
	var forward_speed := rel.dot(Gait.facing_vector(yaw))
	var next_band := Gait.pick_band(absf(forward_speed), band)
	if next_band != band:
		puppet.begin_blend_from(_snapshot, BLEND_BAND)
		# 位相は「左足の接地から」でそろえているので、段が変わっても足の運びは続く
		band = next_band
	var entry: Dictionary = Gait.LOCOMOTION_CLIPS[band]
	var rig := puppet.rig()
	var length := maxf(Gait.cycle_length(rig, entry), 0.05)
	if band == Gait.IDLE:
		phase += dt / length
	else:
		phase += dt * Gait.playback_rate(band, forward_speed) / length
	var clip := Gait.clip_name(rig, entry)
	var slot := int(entry.slot)
	if band == Gait.IDLE and watching:
		clip = WATCH_CLIP
		slot = AnimationRig.SLOT_UAL2
	current_clip = clip
	if not puppet.pose(clip, fposmod(phase + float(entry.contact), 1.0), slot):
		return
	var tilt_target := Gait.lean_bank(_accel, yaw)
	lean = lerpf(lean, tilt_target.x, 1.0 - exp(-TILT_RATE * dt))
	bank = lerpf(bank, tilt_target.y, 1.0 - exp(-TILT_RATE * dt))
	# 1 周期ぶん（ゆっくり回すほど長く）の中で、いちばん深い接地を床に合わせる
	var rate := absf(Gait.playback_rate(band, forward_speed)) if band != Gait.IDLE else 1.0
	_stand_gait(yaw, Gait.tilt_basis(yaw, lean, bank), clampf(length / maxf(rate, 0.1) * 1.05, 0.4, 1.6))


func _pose_jump(dt: float, bundle: MenuPreviewActorAIState) -> void:
	var start_clip := NINJA_START_CLIP if _airborne_ninja else JUMP_START_CLIP
	var loop_clip := NINJA_LOOP_CLIP if _airborne_ninja else JUMP_LOOP_CLIP
	var slot := AnimationRig.SLOT_UAL2 if _airborne_ninja else AnimationRig.SLOT_UAL
	var clip := loop_clip
	var ratio := 0.0
	if bundle.jump_prep_until >= 0.0:
		# 踏み切りの溜め：しゃがみ込む
		clip = start_clip
		ratio = lerpf(0.1, 0.35, clampf(_mode_time / MenuActorAI.JUMP_PREP_SECONDS, 0.0, 1.0))
	elif host._actor_vel_y(is_p1) > JUMP_LOOP_VY:
		clip = start_clip
		ratio = clampf(0.35 + _mode_time * 0.5, 0.35, 0.65)
	else:
		var length := maxf(puppet.clip_length(loop_clip, slot), 0.1)
		ratio = fposmod(_clock / length, 1.0)
	current_clip = clip
	if puppet.pose(clip, ratio, slot):
		lean = lerpf(lean, 0.0, 1.0 - exp(-TILT_RATE * dt))
		bank = lerpf(bank, 0.0, 1.0 - exp(-TILT_RATE * dt))
		_stand(yaw)


func _pose_landing(dt: float, _bundle: MenuPreviewActorAIState) -> void:
	var clip := NINJA_LAND_CLIP if _landing_ninja else JUMP_LAND_CLIP
	var slot := AnimationRig.SLOT_UAL2 if _landing_ninja else AnimationRig.SLOT_UAL
	var ratio := lerpf(0.12, 0.5, clampf(_mode_time / LANDING_SECONDS, 0.0, 1.0))
	current_clip = clip
	if puppet.pose(clip, ratio, slot):
		_turn_toward(Gait.FACING_YAW, dt)
		_stand(yaw)


## 体当たりを受けた向き（ゴーストの来た方）を向いて吹き飛ぶ
func _pose_knockback(dt: float, bundle: MenuPreviewActorAIState) -> void:
	var length := maxf(puppet.clip_length(KNOCKBACK_CLIP, AnimationRig.SLOT_UAL2), 0.1)
	var from := bundle.knockback_from
	if from.length_squared() > 0.0001:
		yaw = lerp_angle(yaw, atan2(from.x, from.y), 1.0 - exp(-YAW_RATE * 2.0 * dt))
	current_clip = KNOCKBACK_CLIP
	if puppet.pose(KNOCKBACK_CLIP, clampf(_mode_time / length, 0.0, 1.0), AnimationRig.SLOT_UAL2):
		_stand(yaw)


func _pose_fall(dt: float, _bundle: MenuPreviewActorAIState) -> void:
	var rig := puppet.rig()
	if rig == null or not rig.seek_falling_idle(_mode_time):
		return
	current_clip = "FallingIdle"
	_controller.call("_apply_skeleton_pose", puppet.parts(), rig.active_skeleton, rig.active_bone_indices, rig.mirror_x)
	_turn_toward(Gait.FACING_YAW, dt)
	_stand(yaw)


func _pose_roll(dt: float, _bundle: MenuPreviewActorAIState, vel: Vector2) -> void:
	var length := maxf(puppet.clip_length(ROLL_CLIP), 0.1)
	if vel.length() > 0.5:
		var deviation := wrapf(atan2(vel.x, vel.y) - Gait.FACING_YAW, -PI, PI)
		if absf(deviation) > PI * 0.5:
			deviation = wrapf(deviation + PI, -PI, PI)
		_turn_toward(Gait.FACING_YAW + clampf(deviation, -PI * 0.5, PI * 0.5), dt)
	current_clip = ROLL_CLIP
	if puppet.pose(ROLL_CLIP, clampf(_mode_time * ROLL_SPEED / length, 0.0, 1.0)):
		_stand(yaw)
