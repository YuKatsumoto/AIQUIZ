extends Node
## メニュー背景ランナーがゴーストの体当たりで吹き飛ぶ・海へ落ちる動き（MenuRunnerMotor と MenuActorAI）の単体テスト。
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
	_knockback_slide()
	_actor_cases()
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "report": report}
	print("MENU_RUNNER_MOTOR ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)


## 本編と同じ減速：速さ v で v²/(2a) 滑る
func _knockback_slide() -> void:
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
