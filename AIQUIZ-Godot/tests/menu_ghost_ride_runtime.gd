extends Node
## メニュー背景（2P）のゴーストライダーを、実際のメインメニューで最後まで通す。
## 1. 壁への激突で P2 が死ぬ → 本編と同じ演出（AIMING まで約 11 秒）→ 2〜3 回突進 → 帰って P2 が復活
## 2. P1 が死んで P2 を襲う（作り直した PlayerController でも動く）。PERFECT の命中で後ろの海へ落ちる
## 3. ライドの途中でカスタマイズ・1P への切り替え・出発（Start）が来たら、残らず畳む
const OUT := "res://artifacts/menu_ghost/"
const Phase = GhostSharkRideController.Phase
const AIState = preload("res://scripts/ui/menu_preview_actor_ai_state.gd")
var checks: Dictionary = {}
var report: Dictionary = {}
var preview: MenuWallBackgroundPreview
var shots: Dictionary = {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	Engine.max_fps = 60
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.llm_mode = "OFFLINE"
	QuizManager.game_state.num_players = 2
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	for i in 1200:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene and scene.get("_menu_wall_preview"):
			preview = scene._menu_wall_preview
			if preview._preview_saw and preview._preview_player and not SceneTransition.is_transitioning():
				break
	if preview == null:
		checks.menu_ready = false
		finish()
		return
	preview.sync_menu_player_count(2)
	for i in 120:
		await get_tree().process_frame
	var ghost := preview._ghost
	checks.director_exists = ghost != null
	checks.controller_ready = ghost.ensure_controller()
	ghost.chance = 1.0
	ghost.first_ride_after_sec = 0.0
	ghost.cooldown_sec = 0.0
	ghost.dodge_chance = 0.0
	ghost.brain.whiff_chance = 0.0
	checks.hud_hidden = not ghost.controller._hud_layer.visible
	checks.camera_sees_soul_layers = preview._preview_camera.get_cull_mask_value(20) and preview._preview_camera.get_cull_mask_value(19)
	await _ride_until_done(false, "ride1")
	await _ride_until_done(true, "ride2")
	await _lifecycle_cases()
	finish()


## 生き残る方の後ろにノコギリや壁がこないように場を整えて、dead_is_p1 側を壁への激突で殺す
func _prepare_and_kill(dead_is_p1: bool, survivor_z: float) -> void:
	var gs := preview._preview_gs
	preview._saw_next_trial = INF
	preview._saw_accident_cooldown = INF
	for wall in preview._preview_walls:
		if is_instance_valid(wall) and wall.position.z > -60.0:
			wall.position.z -= 200.0
	# 復活待ちなら終わるまで待つ
	for i in 600:
		if gs.p1_alive and gs.p2_alive and preview._p1_ai.ai_state == AIState.STATE_NORMAL and preview._p2_ai.ai_state == AIState.STATE_NORMAL and gs.player_y <= 0.01 and gs.player2_y <= 0.01:
			break
		await get_tree().process_frame
	var survivor_is_p1 := not dead_is_p1
	var survivor := preview._p1_ai if survivor_is_p1 else preview._p2_ai
	preview._set_actor_x(survivor_is_p1, -3.5 if survivor_is_p1 else 3.5)
	preview._set_actor_local_z(survivor_is_p1, survivor_z)
	survivor.vel_x = 0.0
	survivor.vel_z = 0.0
	survivor.lane_shift_active = false
	survivor.depth_shift_active = false
	survivor.next_action_t = INF
	preview._clear_learning_commit(survivor)
	var dead := preview._p1_ai if dead_is_p1 else preview._p2_ai
	preview._trigger_preview_death("crash", dead, dead_is_p1)


func _ride_until_done(dead_is_p1: bool, label: String) -> void:
	var ghost := preview._ghost
	var gs := preview._preview_gs
	var survivor_is_p1 := not dead_is_p1
	var survivor := preview._p1_ai if survivor_is_p1 else preview._p2_ai
	ghost.brain.forced_plan = MenuGhostRiderBrain.Plan.PERFECT if dead_is_p1 else -1
	var survivor_z := 1.6 if dead_is_p1 else -1.0
	var stats_before: Dictionary = ghost.stats.duplicate()
	await _prepare_and_kill(dead_is_p1, survivor_z)
	checks["%s_armed" % label] = ghost.is_armed()
	var phases: Dictionary = {}
	var start := preview._linger_time
	var knocked := false
	var knock_from := Vector2.ZERO
	var max_knock := 0.0
	var survivor_died := false
	var ended_at := -1.0
	var respawned_at := -1.0
	while preview._linger_time - start < 70.0:
		await get_tree().process_frame
		# 生き残る方は狙われやすいよう、ゴーストが来てからも自分では動き回らない（扉も来ない）
		if survivor.ai_state == AIState.STATE_NORMAL:
			survivor.next_action_t = INF
		var phase := ghost.ride_phase()
		var t := preview._linger_time - start
		if ghost.is_riding() and not phases.has(Phase.keys()[phase]):
			phases[Phase.keys()[phase]] = snappedf(t, 0.01)
			if phase in [Phase.SOUL_FLIGHT, Phase.BEAM_REVEAL, Phase.AIMING]:
				# 演出の途中を撮る（少し進めてから）
				for i in 40:
					await get_tree().process_frame
				await _shot("%s_%s" % [label, Phase.keys()[phase].to_lower()])
		if survivor.ai_state == AIState.STATE_KNOCKBACK and not knocked:
			knocked = true
			knock_from = Vector2(preview._actor_x(survivor_is_p1), preview._actor_local_z(survivor_is_p1))
			await _shot("%s_hit" % label)
		if knocked and survivor.ai_state in [AIState.STATE_KNOCKBACK, AIState.STATE_OCEAN_FALL]:
			max_knock = maxf(max_knock, Vector2(preview._actor_x(survivor_is_p1), preview._actor_local_z(survivor_is_p1)).distance_to(knock_from))
		if not preview._actor_alive(survivor_is_p1):
			survivor_died = true
		if ended_at < 0.0 and not ghost.is_riding() and phases.size() > 0:
			ended_at = t
		if ended_at >= 0.0 and preview._actor_alive(dead_is_p1):
			respawned_at = t
			break
	var dashes: int = ghost.stats.dashes - stats_before.dashes
	report[label] = {
		"phases": phases, "dashes": dashes, "hits": ghost.stats.hits - stats_before.hits,
		"knocked": knocked, "max_knock": snappedf(max_knock, 0.01), "survivor_died": survivor_died,
		"ended_at": snappedf(ended_at, 0.01), "respawned_at": snappedf(respawned_at, 0.01),
		"ocean_kills": ghost.stats.ocean_kills - stats_before.ocean_kills,
	}
	var aiming_at := float(phases.get("AIMING", -1.0))
	checks["%s_full_sequence" % label] = phases.has("SOUL_FLIGHT") and phases.has("MOUNTING") and phases.has("BEAM_REVEAL") and phases.has("ENTERING")
	checks["%s_aiming_after_full_intro" % label] = aiming_at >= 9.9 and aiming_at <= 12.5
	checks["%s_ended" % label] = ended_at > 0.0
	checks["%s_respawned_after_ride" % label] = respawned_at > 0.0 and respawned_at - ended_at <= 2.5
	checks["%s_controller_idle" % label] = ghost.ride_phase() == Phase.INACTIVE
	if survivor_died:
		# 吹き飛ばされて海へ落ちたか、扉の外へ飛ばされて壁に当たった：どちらでもライドはそこで終わる
		checks["%s_ends_on_survivor_death" % label] = ended_at > 0.0
		if dead_is_p1:
			# 後端寄り（z=1.6）を PERFECT で狙い続ける回は、後ろの海まで吹き飛ぶ
			checks["%s_ocean_kill" % label] = ghost.stats.ocean_kills > stats_before.ocean_kills
	else:
		checks["%s_dash_count" % label] = dashes >= MenuGhostRideDirector.DASHES_MIN and dashes <= MenuGhostRideDirector.DASHES_MAX
	if dead_is_p1:
		# PERFECT で狙い続ける：当たって後ろへ吹き飛ぶ（海まで届けば落ちる）
		checks["%s_knockback" % label] = knocked and max_knock >= 1.0
	var shark := ghost.controller.get_shark() if ghost.controller else null
	for i in 240:
		await get_tree().process_frame
	var sharks_ok := true
	for s in preview._stage_env.get_ocean_sharks():
		sharks_ok = sharks_ok and not bool(s.get("is_ghost_ridden"))
	checks["%s_shark_released" % label] = sharks_ok
	await _shot("%s_after" % label)


func _lifecycle_cases() -> void:
	var ghost := preview._ghost
	var gs := preview._preview_gs
	ghost.brain.forced_plan = -1
	# カスタマイズ画面に入ったら畳む
	await _prepare_and_kill(false, -1.0)
	for i in 300:
		await get_tree().process_frame
	checks.customize_ride_running = ghost.is_riding()
	preview.enter_customize_mode()
	checks.customize_aborts = not ghost.is_riding() and ghost.ride_phase() == Phase.INACTIVE and not preview._p2_ai.respawn_hold
	preview.exit_customize_mode()
	for i in 360:
		await get_tree().process_frame
	checks.customize_respawns = gs.p2_alive
	# 1P へ切り替えたら畳む
	await _prepare_and_kill(true, -1.0)
	for i in 300:
		await get_tree().process_frame
	checks.oneplayer_ride_running = ghost.is_riding()
	preview.sync_menu_player_count(1)
	await get_tree().process_frame
	checks.oneplayer_aborts = not ghost.is_riding() and ghost.ride_phase() == Phase.INACTIVE
	for i in 360:
		await get_tree().process_frame
	checks.oneplayer_p1_back = gs.p1_alive
	preview.sync_menu_player_count(2)
	for i in 240:
		await get_tree().process_frame
	# 出発（Start）が来たら畳む
	await _prepare_and_kill(false, -1.0)
	for i in 300:
		await get_tree().process_frame
	checks.departure_ride_running = ghost.is_riding()
	preview.begin_game_start_departure(2)
	checks.departure_aborts = not ghost.is_riding() and ghost.ride_phase() == Phase.INACTIVE and gs.p1_alive and gs.p2_alive
	preview.cancel_game_start_departure()
	for i in 120:
		await get_tree().process_frame
	var sharks_ok := true
	for s in preview._stage_env.get_ocean_sharks():
		sharks_ok = sharks_ok and not bool(s.get("is_ghost_ridden"))
	checks.lifecycle_sharks_released = sharks_ok


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	shots[name] = true


func finish() -> void:
	var errors: Array[String] = []
	for key in checks:
		if not checks[key]:
			errors.append(key)
	var result := {"passed": errors.is_empty(), "errors": errors, "checks": checks, "report": report, "stats": preview._ghost.stats if preview and preview._ghost else {}, "shots": shots.keys()}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("MENU_GHOST_RIDE ", JSON.stringify(result))
	get_tree().quit(0 if errors.is_empty() else 1)
