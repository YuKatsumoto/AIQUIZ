extends Node
## メニュー背景ランナーの見た目（MenuRunnerAnimator）を実際のメインメニューで確かめる。
## 接地した足の流れが本編の描画より悪くない・体の向きの振れ幅・止まったら立ち止まる・
## ジャンプの姿・腕が T の字に上がっていない・上書きの処理時間。30fps と 60fps で回す。
const OUT := "res://artifacts/menu_locomotion/"
const AIState = preload("res://scripts/ui/menu_preview_actor_ai_state.gd")
var checks: Dictionary = {}
var report: Dictionary = {}
var preview: MenuWallBackgroundPreview


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	QuizManager.set_meta("saw_dock_menu_seen", true)
	QuizManager.provider.llm_mode = "OFFLINE"
	QuizManager.game_state.num_players = 2
	MenuGhostRideDirector.globally_enabled = false
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
	preview._saw_next_trial = INF
	preview._saw_accident_cooldown = INF
	for fps: int in [60, 30]:
		Engine.max_fps = fps
		await _sample_free_running(fps, 20.0)
	Engine.max_fps = 60
	# 比べるため、同じ測り方で本編の描画のまま（上書きなし）も測る
	MenuRunnerAnimator.globally_enabled = false
	await _sample_free_running(60, 20.0, "_legacy")
	MenuRunnerAnimator.globally_enabled = true
	checks.slip_not_worse_than_legacy = float(report.fps_60.stance_slip_median) <= float(report.fps_60_legacy.stance_slip_median) + 0.3
	await _paused_idle()
	await _jump_pose()
	finish()


func _foot_points(is_p1: bool) -> Array[Vector3]:
	var pc := preview._preview_player as PlayerController
	var parts: Dictionary = pc.p1_parts if is_p1 else pc.p2_parts
	var out: Array[Vector3] = []
	for key: String in ["l_ankle", "r_ankle"]:
		var node := parts.get(key) as Node3D
		out.append(node.global_position if node else Vector3.INF)
	return out


func _sample_free_running(fps: int, seconds: float, label: String = "") -> void:
	var yaw_dev_max := 0.0
	var tpose_frames := 0
	var loco_frames := 0
	var cost_total := 0.0
	var cost_frames := 0
	var bands := {}
	var prev := {true: [], false: []}
	# 接地区間ごとの足首の流れ（区間の平均の速度）。接地している足は床と一緒に +z へ belt の速さで流れるはず
	var stance := {}
	var sole_history := {}
	var windows: Array[float] = []
	var start := Time.get_ticks_msec()
	var shot_taken := false
	var legacy := not MenuRunnerAnimator.globally_enabled
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await get_tree().process_frame
		# 測っているあいだは事故で死なないようにする（死亡・煽りの間は本編の描画なので測れない）
		for bundle: MenuPreviewActorAIState in [preview._p1_ai, preview._p2_ai]:
			bundle.accident_cooldown_t = INF
		var dt := get_process_delta_time()
		var belt := preview._get_effective_preview_speed()
		for is_p1: bool in [true, false]:
			var animator: MenuRunnerAnimator = preview._runner_animators[0 if is_p1 else 1]
			var bundle: MenuPreviewActorAIState = preview._p1_ai if is_p1 else preview._p2_ai
			cost_total += animator.last_cost_usec
			cost_frames += 1
			var feet := _foot_points(is_p1)
			var was: Array = prev[is_p1]
			prev[is_p1] = feet
			var running := animator.mode == MenuRunnerAnimator.Mode.LOCOMOTION and animator.band != MenuRunnerGait.IDLE
			if legacy:
				running = bundle.ai_state == AIState.STATE_NORMAL and not bundle.is_emoting and preview._actor_alive(is_p1) and preview._actor_y(is_p1) <= 0.01 and not bool(preview._preview_gs.get_local_push_pose(1 if is_p1 else 2).get("active", false))
			elif animator.mode == MenuRunnerAnimator.Mode.LOCOMOTION:
				loco_frames += 1
				bands[animator.band] = int(bands.get(animator.band, 0)) + 1
				if belt > 0.5:
					yaw_dev_max = maxf(yaw_dev_max, absf(wrapf(animator.yaw - PI, -PI, PI)))
				# 腕が肩より上で左右に大きく開いていたら T の字
				var pc := preview._preview_player as PlayerController
				var parts: Dictionary = pc.p1_parts if is_p1 else pc.p2_parts
				var lw := (parts.get("l_wrist") as Node3D).global_position
				var rw := (parts.get("r_wrist") as Node3D).global_position
				var ls := (parts.get("l_shoulder") as Node3D).global_position
				var rs := (parts.get("r_shoulder") as Node3D).global_position
				if (lw.y + rw.y) * 0.5 > (ls.y + rs.y) * 0.5 - 0.05 and lw.distance_to(rw) > ls.distance_to(rs) * 2.4:
					tpose_frames += 1
			# 接地している足：靴の底がこの 1 秒でいちばん低かった所から 3 cm 以内。その足首が床と一緒に流れているかを
			# 接地区間ごとの平均で見る（本編の描画のままでも同じ測り方になる）
			var pc2 := preview._preview_player as PlayerController
			var parts2: Dictionary = pc2.p1_parts if is_p1 else pc2.p2_parts
			var now := Time.get_ticks_msec() / 1000.0
			for k in 2:
				var foot_key := "%s%d" % ["p1" if is_p1 else "p2", k]
				var mesh_keys: Array[String] = ["l_foot", "l_toe_mesh"]
				if k == 1:
					mesh_keys = ["r_foot", "r_toe_mesh"]
				var bottom: float = pc2.call("_lowest_intro_mesh_y", parts2, mesh_keys)
				var hist: Array = sole_history.get(foot_key, [])
				hist.append(Vector2(now, bottom))
				while hist.size() > 1 and (hist[0] as Vector2).x < now - 1.0:
					hist.pop_front()
				sole_history[foot_key] = hist
				var floor_y := INF
				for h: Vector2 in hist:
					floor_y = minf(floor_y, h.y)
				var acc: Dictionary = stance.get(foot_key, {})
				var down := running and was.size() == 2 and dt > 0.0 and bottom < floor_y + 0.03
				if down:
					var a: Vector3 = was[k]
					var b: Vector3 = feet[k]
					acc["d"] = (acc.get("d", Vector2.ZERO) as Vector2) + Vector2(b.x - a.x, b.z - a.z)
					acc["t"] = float(acc.get("t", 0.0)) + dt
					acc["belt"] = float(acc.get("belt", 0.0)) + belt * dt
					stance[foot_key] = acc
				elif not acc.is_empty():
					var t := float(acc.t)
					if t >= 0.05:
						var mean_vel := (acc.d as Vector2) / t
						windows.append((mean_vel - Vector2(0.0, float(acc.belt) / t)).length())
					stance.erase(foot_key)
		if not shot_taken and Time.get_ticks_msec() - start > seconds * 500.0:
			shot_taken = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OUT + "running_%dfps%s.png" % [fps, label])
	windows.sort()
	var median := windows[windows.size() / 2] if not windows.is_empty() else INF
	var p90 := windows[int(windows.size() * 0.9)] if not windows.is_empty() else INF
	var cost := cost_total / maxf(1.0, cost_frames)
	report["fps_%d%s" % [fps, label]] = {"stance_slip_median": snappedf(median, 0.01), "stance_slip_p90": snappedf(p90, 0.01), "stance_windows": windows.size(), "yaw_dev_max_deg": snappedf(rad_to_deg(yaw_dev_max), 0.1), "loco_frames": loco_frames, "tpose_frames": tpose_frames, "cost_usec": snappedf(cost, 1), "bands": bands}
	if legacy:
		return
	# 走りは本編と同じクリップ・同じ速さなので、足の流れは本編の描画と同程度が上限（下の slip_not_worse_than_legacy で比べる）
	checks["stance_slip_sampled_%d" % fps] = windows.size() >= 10
	checks["yaw_limit_%d" % fps] = rad_to_deg(yaw_dev_max) <= 40.0
	checks["no_tpose_%d" % fps] = tpose_frames == 0
	checks["cost_%d" % fps] = cost < 800.0
	checks["locomotion_used_%d" % fps] = loco_frames > 60


## コンベアを止めて誰も動かなければ、0.6 秒以内に立ち止まる（Idle）
func _paused_idle() -> void:
	for wall in preview._preview_walls:
		if is_instance_valid(wall) and wall.position.z > -40.0:
			wall.position.z -= 120.0
	for i in 120:
		await get_tree().process_frame
	# 2 人とも生きて走っている状態から止める
	for i in 900:
		if preview._preview_gs.p1_alive and preview._preview_gs.p2_alive and preview._p1_ai.ai_state == AIState.STATE_NORMAL and preview._p2_ai.ai_state == AIState.STATE_NORMAL and not preview._p1_ai.is_emoting and not preview._p2_ai.is_emoting:
			break
		await get_tree().process_frame
	# 押し合っていると本編の押し合いの姿になるので、離してから止める
	preview._set_actor_x(true, -3.5)
	preview._set_actor_x(false, 3.5)
	preview._reset_menu_push()
	preview._pause_preview_conveyor()
	for bundle: MenuPreviewActorAIState in [preview._p1_ai, preview._p2_ai]:
		bundle.next_action_t = INF
		bundle.lane_shift_active = false
		bundle.depth_shift_active = false
	var idle_at := -1.0
	var t := 0.0
	while t < 1.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		for bundle: MenuPreviewActorAIState in [preview._p1_ai, preview._p2_ai]:
			bundle.next_action_t = INF
		var a: MenuRunnerAnimator = preview._runner_animators[0]
		var b: MenuRunnerAnimator = preview._runner_animators[1]
		if idle_at < 0.0 and a.current_clip == "Idle_Loop" and b.current_clip == "Idle_Loop":
			idle_at = t
	report["paused_idle_at"] = snappedf(idle_at, 0.01)
	var diag := []
	for i in 2:
		var an: MenuRunnerAnimator = preview._runner_animators[i]
		var bu: MenuPreviewActorAIState = preview._p1_ai if i == 0 else preview._p2_ai
		diag.append({"mode": an.mode, "clip": an.current_clip, "band": an.band, "vel": Vector2(bu.vel_x, bu.vel_z), "state": bu.ai_state, "emoting": bu.is_emoting, "alive": preview._actor_alive(i == 0), "push": preview._preview_gs.get_local_push_pose(i + 1).get("active", false)})
	report["paused_diag"] = str(diag)
	checks.paused_goes_idle = idle_at >= 0.0 and idle_at <= 0.6
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "paused_idle.png")
	preview._resume_preview_conveyor()


## ジャンプの溜め〜空中はジャンプのクリップ、着地は Jump_Land
func _jump_pose() -> void:
	var bundle := preview._p1_ai
	bundle.next_action_t = INF
	var started := preview._ai.start_jump(bundle, true)
	var clips := {}
	var shot := false
	for i in 90:
		await get_tree().process_frame
		var animator: MenuRunnerAnimator = preview._runner_animators[0]
		# process_frame の直後なので、animator は前のフレームの結果。モードと当てたクリップの組で見る
		if animator.mode in [MenuRunnerAnimator.Mode.JUMP, MenuRunnerAnimator.Mode.LANDING]:
			clips[animator.current_clip] = true
			if not shot and preview._actor_y(true) > 0.5:
				shot = true
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OUT + "jump.png")
	report["jump_clips"] = clips.keys()
	var only_jump := not clips.is_empty()
	for clip: String in clips:
		only_jump = only_jump and (clip.begins_with("Jump_") or clip.begins_with("NinjaJump_"))
	checks.jump_started = started
	checks.jump_uses_jump_clips = only_jump and clips.has("Jump_Land")


func finish() -> void:
	var errors: Array[String] = []
	for key in checks:
		if not checks[key]:
			errors.append(key)
	var result := {"passed": errors.is_empty(), "errors": errors, "checks": checks, "report": report}
	FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("MENU_LOCOMOTION ", JSON.stringify(result))
	get_tree().quit(0 if errors.is_empty() else 1)
