extends Node
## メニュー背景ランナーの移動（MenuRunnerMotor と MenuActorAI の吹き飛び・海への落下・踊りの停止）の単体テスト。
const Motor = preload("res://scripts/ui/menu_preview/menu_runner_motor.gd")
const AIState = preload("res://scripts/ui/menu_preview_actor_ai_state.gd")
var failures: Array[String] = []
var checks := 0
var report := {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _ready() -> void:
	_arrival_cases()
	_brake_and_knockback_cases()
	_actor_cases()
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "report": report}
	print("MENU_RUNNER_MOTOR ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)


## 30〜240fps で、着く時間がほぼ同じで、目標を飛び越えない
func _arrival_cases() -> void:
	var reference := _arrive_time(240, 2.0, 3.0)
	for fps: int in [30, 60, 144, 240]:
		var t := _arrive_time(fps, 2.0, 3.0)
		report["arrive_%d" % fps] = t
		var tolerance := maxf(reference * 0.03, 1.5 / fps)
		check(absf(t - reference) <= tolerance, "arrival %.3f vs %.3f at %d fps" % [t, reference, fps])
	# 144fps の最初のフレームで「詰まった」とみなさない（少しでも進む）
	var first := Motor.steer_axis(0.0, 0.0, 0.5, 3.0, Motor.LANE_ACCEL, Motor.LANE_DECEL, 1.0 / 144.0)
	check(first.x > 0.0 and first.z < 0.5, "first 144fps frame moves without arriving")
	# 逆向きに走っている最中に目標を変えても、止まってから折り返す
	var pos := 0.0
	var vel := 3.0
	var turned := false
	for i in 240:
		var step := Motor.steer_axis(pos, vel, -2.0, 3.0, Motor.LANE_ACCEL, Motor.LANE_DECEL, 1.0 / 60.0)
		if step.z > 0.5:
			pos = step.x
			break
		check(absf(step.y - vel) <= Motor.LANE_DECEL / 60.0 + 0.001, "velocity change limited")
		pos = step.x
		vel = step.y
		turned = turned or vel < 0.0
	check(turned and is_equal_approx(pos, -2.0), "reverses and arrives")


func _arrive_time(fps: int, distance: float, cruise: float) -> float:
	var pos := 0.0
	var vel := 0.0
	var dt := 1.0 / fps
	var t := 0.0
	for i in fps * 10:
		var step := Motor.steer_axis(pos, vel, distance, cruise, Motor.LANE_ACCEL, Motor.LANE_DECEL, dt)
		check(step.x <= distance + 0.000001, "no overshoot at %d fps" % fps)
		pos = step.x
		vel = step.y
		t += dt
		if step.z > 0.5:
			return t
	return INF


func _brake_and_knockback_cases() -> void:
	var pos := 0.0
	var vel := 3.0
	var t := 0.0
	while not is_zero_approx(vel) and t < 2.0:
		var b := Motor.brake_axis(pos, vel, Motor.LANE_DECEL, 1.0 / 60.0)
		pos = b.x
		vel = b.y
		t += 1.0 / 60.0
	check(t <= 3.0 / Motor.LANE_DECEL + 0.05, "brake stops in time")
	check(absf(pos - 9.0 / (2.0 * Motor.LANE_DECEL)) < 0.06, "brake distance")
	# 本編と同じ減速：速さ v で v²/(2a) 滑る
	var kp := Vector2.ZERO
	var kv := Vector2(6.0, 8.0)
	for i in 600:
		var step := Motor.knockback_step(kp, kv, 1.0 / 60.0)
		kp = step[0]
		kv = step[1]
	var expected := 100.0 / (2.0 * Motor.KNOCKBACK_DECEL)
	report["knockback_slide"] = kp.length()
	check(absf(kp.length() - expected) < 0.15, "knockback slide %.2f vs %.2f" % [kp.length(), expected])


func _fixture() -> MenuWallBackgroundPreview:
	var p := MenuWallBackgroundPreview.new()
	p._preview_gs = QuizGameState.new()
	p._preview_gs.num_players = 1
	p._menu_synced_player_count = 1
	p._preview_gs.game_state = Constants.STATE_PLAYING
	p._preview_gs.p1_alive = true
	p._p1_ai = MenuPreviewActorAIState.new()
	p._p2_ai = MenuPreviewActorAIState.new()
	p._p1_ai.next_action_t = INF
	p._p1_ai.available_emotes = [EmoteData.EMOTE_STEP_HIP_HOP]
	return p


func _step(p: MenuWallBackgroundPreview, dt: float) -> void:
	p._ai_time += dt
	p._ai.update_actor(dt, true)


func _actor_cases() -> void:
	# 後端の近くで後ろへ吹き飛ばされたら、海へ落ちて死ぬ
	var p := _fixture()
	var gs := p._preview_gs
	gs.player_x = 0.0
	gs.player_z = 3.8
	p._ai.start_knockback(p._p1_ai, true, Vector2(-1.0, 7.0), 5.0, 0.4)
	check(p._p1_ai.ai_state == AIState.STATE_KNOCKBACK, "knockback starts")
	var fell := false
	for i in 240:
		_step(p, 1.0 / 60.0)
		fell = fell or p._p1_ai.ai_state == AIState.STATE_OCEAN_FALL
		if not gs.p1_alive:
			break
	check(fell and not gs.p1_alive and p._p1_ai.ai_state == AIState.STATE_DEAD, "knockback past the edge falls into the sea")
	p.free()
	# 弱い吹き飛びはベルトの上で止まって走りに戻る
	p = _fixture()
	gs = p._preview_gs
	gs.player_x = 0.0
	gs.player_z = -2.0
	p._ai.start_knockback(p._p1_ai, true, Vector2(3.0, 2.0), 4.0, 0.3)
	var recovered_at := -1.0
	var displacement := 0.0
	for i in 180:
		_step(p, 1.0 / 60.0)
		if recovered_at < 0.0 and p._p1_ai.ai_state == AIState.STATE_NORMAL:
			recovered_at = p._ai_time
			displacement = Vector2(gs.player_x, gs.player_local_z + 2.0).length()
	report["recover_time"] = recovered_at
	report["recover_displacement"] = displacement
	check(gs.p1_alive and recovered_at > 0.3 and recovered_at < 1.5, "small knockback recovers on the belt")
	check(displacement > 0.5, "knockback moves the runner")
	p.free()
	# 踊り始めたら 0.5 秒以内に止まる
	p = _fixture()
	gs = p._preview_gs
	gs.player_x = -3.0
	gs.player_z = 0.0
	p._p1_ai.target_x = 3.0
	p._p1_ai.lane_shift_speed = 3.0
	p._p1_ai.lane_shift_active = true
	for i in 30:
		_step(p, 1.0 / 60.0)
	check(p._p1_ai.vel_x > 1.0, "running before the emote")
	check(p._ai_emotes.start_emote(p._p1_ai, true), "emote starts")
	for i in 30:
		_step(p, 1.0 / 60.0)
	check(absf(p._p1_ai.vel_x) < 0.01 and p._p1_ai.is_emoting, "emote holds still within 0.5 s")
	p.free()
	# 外から位置を書き換えられたら速度を捨てる
	p = _fixture()
	gs = p._preview_gs
	gs.player_x = 0.0
	p._p1_ai.vel_x = 3.0
	p._p1_ai.last_written_x = -1.0
	_step(p, 1.0 / 60.0)
	check(is_zero_approx(p._p1_ai.vel_x) and is_zero_approx(gs.player_x), "teleport drops velocity")
	p.free()
