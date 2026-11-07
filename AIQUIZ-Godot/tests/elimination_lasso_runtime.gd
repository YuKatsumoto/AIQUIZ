extends Node

## 両者脱落の投げ縄の演出を本物の GameWorld で再生し、決まった間隔で画面を撮って確かめる
## （tests/elimination_lasso_bootstrap.gd から起動）。2 人を問題の壁で脱落させ（result_ceremony_runtime の
## elimination と同じ作り方）、演出の始まりから結果発表の最初の 1.5 秒までを撮る。
## 確かめること：暗転を使わない／魂が死んだ所から抜け出し、捕まるまで横へ動かない／近い 2 人は縄 1 本、離れた 2 人は
## 両手の縄で捕まえる／ハテナが到着から投げつけまで画面に入っている／カメラが一度も飛ばない（カットなし）／
## コースを流してゴールの手前まで寄せる／魂が結果発表の幽霊にそのまま渡る／渡すときに魂がレーンに立っている。

var OUT := "res://artifacts/elimination_lasso/runtime/"
var helper: Node
var gs: QuizGameState
var world: Node
var pc: PlayerController
var fps := 60
var quality := "high"
var every := 0.1
## 演出の前（脱落してから演出が始まるまで）を撮る間隔の秒。0 なら撮らない
var pre_every := 0.0
var death := "wall"
## 2 人が倒れる扉：same（同じ扉。2 択）、near（隣の扉。4 択）、far（離れた扉。4 択）。near_swap / far_swap は
## P1 と P2 の左右を入れかえる（P1 が −X の側）
var spread := "same"
## 先に脱落してサメに乗る人（rider=1|2）。0 なら 2 人同時に脱落する
var rider_first := 0
## もう 1 人が脱落するときのサメ：aiming（照準中）、charging（突進の途中）、cooldown（突進のあと戻りのポータルの途中）
var rider_phase := "aiming"
var view := ""
var from_t := 0.0
var to_t := 99.0
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("fps="): fps = int(arg.trim_prefix("fps="))
		if arg.begins_with("quality="): quality = arg.trim_prefix("quality=")
		if arg.begins_with("every="): every = float(arg.trim_prefix("every="))
		if arg.begins_with("pre="): pre_every = float(arg.trim_prefix("pre="))
		if arg.begins_with("death="): death = arg.trim_prefix("death=")
		if arg.begins_with("spread="): spread = arg.trim_prefix("spread=")
		if arg.begins_with("rider="): rider_first = int(arg.trim_prefix("rider="))
		if arg.begins_with("rider_phase="): rider_phase = arg.trim_prefix("rider_phase=")
		if arg.begins_with("view="): view = arg.trim_prefix("view=")
		if arg.begins_with("from="): from_t = float(arg.trim_prefix("from="))
		if arg.begins_with("to="): to_t = float(arg.trim_prefix("to="))
		if arg.begins_with("out="): OUT = "res://artifacts/elimination_lasso/runtime/" + arg.trim_prefix("out=") + "/"
	GameManager.graphics_quality = quality
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture()
	if spread != "same":
		# 4 択にして、2 人を別々の扉で脱落させる
		gs.difficulty = "難しい"
		gs.quiz_list.clear()
		for i in range(10):
			gs.quiz_list.append(QuizItem.create("HP検証 %d" % i, PackedStringArray(["正解", "不正解", "別の不正解", "その他"]), 0, "テスト問題です。", "OFFLINE"))
		gs.load_current_quiz()
	gs.sudden_death_enabled = false
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs.game_state = Constants.STATE_WAITING_START
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	pc = world.get_node("Player") as PlayerController
	pc.prepare_for_loading(gs)
	await frames(fps)
	world.call("_clear_preview_walls")
	gs.score = 5
	gs.player2_score = 3
	if rider_first in [1, 2]:
		await eliminate_with_shark_rider(rider_first)
	else:
		await eliminate_both_mid_quiz()
	var lasso: EliminationLassoDirector = world.get("_elimination_lasso")
	check(lasso != null, "GameWorld owns the elimination lasso director")
	if lasso != null:
		lasso.debug_view = view
	var director: Node3D = world.get("_result_ceremony_director")
	var camera_rig: Node = world.get("camera_controller")
	var next_shot := 0.0
	var lasso_seen := false
	var covered := false
	var handoff := {}
	var cut := {}
	var prev_eye := Vector3.INF
	var prev_forward := Vector3.ZERO
	var max_step := 0.0
	var max_turn := 0.0
	var emerge := {}
	var plan := {}
	var stay := {}
	var hatena_frames := 0
	var hatena_inside := 0
	var hatena_height_sum := 0.0
	var hatena_out: Array = []
	var wall_clear := INF
	var next_pre := 0.0
	var ceremony_frames := 0
	var last_lasso_eye := Vector3.ZERO
	var max_frame_ms := 0.0
	var hitches: Array = []
	var frame_started := Time.get_ticks_usec()
	for _frame in range(fps * 34):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - frame_started) / 1000.0
		frame_started = now
		if SceneTransition.is_fully_covered():
			covered = true
		var camera: Camera3D = get_viewport().get_camera_3d()
		if pre_every > 0.0 and not lasso_seen and float(_frame) / float(fps) >= next_pre:
			# 演出の前（脱落の瞬間から）も撮る
			next_pre += pre_every
			save_frame("frames/pre_%05.2f" % (float(_frame) / float(fps)))
		if lasso != null and lasso.is_active() and not gs.result_presentation_active:
			if lasso_seen and lasso.elapsed() > 0.3:
				max_frame_ms = maxf(max_frame_ms, frame_ms)
			if lasso_seen and frame_ms > 40.0:
				hitches.append([snappedf(lasso.elapsed(), 0.01), snappedf(frame_ms, 0.1)])
			lasso_seen = true
			var t := lasso.elapsed()
			if t >= next_shot and t >= from_t and t <= to_t:
				next_shot = t + every - 0.0005
				save_frame("frames/lasso_%05.2f" % t)
			if plan.is_empty() and t > 0.0:
				plan["mode"] = String(lasso.get("_mode_name")) if lasso.get("_mode_name") != null else ""
				for key in ["_soul_start", "_soul_rise"]:
					var points: Dictionary = lasso.get(key) if lasso.get(key) is Dictionary else {}
					for player_index in points:
						plan["%s_p%d" % [key.trim_prefix("_"), player_index]] = vec(points[player_index])
				plan["cloud_hover"] = vec(lasso.get("_cloud_hover"))
				plan["shark_rider"] = int(lasso.get("_shark_rider"))
				plan["wall_ahead_z"] = lasso.call("_wall_ahead_z", -INF)
			if emerge.is_empty() and t > 0.0:
				# 最初のフレーム：魂は倒れた体のところにいる
				for player_index in [1, 2]:
					# 演出の始まりに体のあった所（監督が覚えた所）から抜け出す。体は物理で動き続けるので、今の位置とは比べない。
					# サメに乗っていた人は、サメの上の乗り手のまま
					var planned: Vector3 = (lasso.get("_soul_start") as Dictionary).get(player_index, Vector3.INF)
					var at := soul_pos(lasso, player_index)
					emerge[player_index] = at.distance_to(planned) if at.is_finite() else INF
			if t >= EliminationLassoDirector.T_SCROLL_END + 0.3 and not cut.has("scroll_ahead"):
				cut["scroll_ahead"] = gs.get_local_result_goal_z() - gs.world_scroll_z
				cut["hidden_mask"] = pc.lasso_hidden_mask
				# 左右の客席もコースと一緒に流れた（流した距離と同じだけ後ろへ）
				var stage: Node = world.get("stage_env")
				cut["stand_shift"] = float(stage.call("get_grandstand_shift")) if stage != null else 0.0
				cut["scrolled"] = gs.world_scroll_z - float(lasso.get("_scroll_from"))
			# 運ぶあいだ、ぶら下がった魂の足が壁の上を越える
			var walls: Variant = world.get("_active_walls")
			if walls is Array and t >= EliminationLassoDirector.T_YANK and t < EliminationLassoDirector.T_FLING:
				for wall: Variant in walls:
					if not (wall is Node3D) or not is_instance_valid(wall) or not (wall as Node3D).visible:
						continue
					var wall_node := wall as Node3D
					for player_index in [1, 2]:
						var at := soul_pos(lasso, player_index)
						if at.is_finite() and absf(at.z - wall_node.position.z) < 0.6 and absf(at.x) < 12.0:
							var clearance: float = at.y - 1.2 - float(wall_node.get("wall_top_y"))
							wall_clear = minf(wall_clear, clearance)
			if camera != null and t > 0.0:
				var forward := -camera.global_basis.z
				if prev_eye != Vector3.INF:
					max_step = maxf(max_step, camera.global_position.distance_to(prev_eye))
					max_turn = maxf(max_turn, rad_to_deg(prev_forward.angle_to(forward)))
				prev_eye = camera.global_position
				prev_forward = forward
			if camera != null:
				last_lasso_eye = camera.global_position
			# サメに乗っていた人：サメに乗ったまま縄を掛けられ、引き上げるときにサメから引きはがされる
			if rider_first in [1, 2]:
				var rider_soul := (lasso.get("_souls") as Dictionary).get(rider_first) as Node3D
				if t >= EliminationLassoDirector.T_CINCH + 0.08 and not cut.has("rider_tied_on_shark"):
					cut["rider_tied_on_shark"] = rider_soul != null and rider_soul.get_parent() != lasso
				if t >= EliminationLassoDirector.T_YANK + 0.2 and not cut.has("rider_pulled_off"):
					cut["rider_pulled_off"] = rider_soul != null and rider_soul.get_parent() == lasso
			# 魂は捕まるまで死んだ所から横へ動かない
			if t < EliminationLassoDirector.T_CINCH:
				var starts: Dictionary = lasso.get("_soul_start")
				for player_index in [1, 2]:
					var at := soul_pos(lasso, player_index)
					if at.is_finite() and starts.has(player_index):
						var start: Vector3 = starts[player_index]
						var drift := Vector2(at.x - start.x, at.z - start.z).length()
						stay[player_index] = maxf(float(stay.get(player_index, 0.0)), drift)
			# 投げつける瞬間：P1 が +X の側（自分のレーンの側）にいて、2 人が交差して飛ばない
			if t >= EliminationLassoDirector.T_FLING - 0.02 and not cut.has("fling_p1_x"):
				var s1 := soul_pos(lasso, 1)
				var s2 := soul_pos(lasso, 2)
				if s1.is_finite() and s2.is_finite():
					cut["fling_p1_x"] = s1.x
					cut["fling_p2_x"] = s2.x
			# ハテナが画面に映っているか（体の真ん中が画面の中）と、画面の高さに占める割合
			var rider: Node3D = lasso.get_node_or_null("HatenaCloud")
			if camera != null and rider != null and t >= EliminationLassoDirector.T_CLOUD_ARRIVE and t <= EliminationLassoDirector.T_FLING + 0.3:
				var body := rider.global_transform * Vector3(0.0, 0.95, 0.0)
				var size := get_viewport().get_visible_rect().size
				var inside := false
				if camera.is_position_in_frustum(body):
					var px := camera.unproject_position(body)
					inside = px.x >= 0.0 and px.y >= 0.0 and px.x <= size.x and px.y <= size.y
				var top := camera.unproject_position(rider.global_transform * Vector3(0.0, 1.85, 0.0))
				var bottom := camera.unproject_position(rider.global_transform * Vector3(0.0, -0.3, 0.0))
				hatena_frames += 1
				if inside:
					hatena_inside += 1
					hatena_height_sum += absf(top.y - bottom.y) / size.y
				elif hatena_out.size() < 40:
					hatena_out.append(snappedf(t, 0.01))
		if gs.result_presentation_active:
			ceremony_frames += 1
			if ceremony_frames == 1:
				handoff["time"] = lasso.elapsed() if lasso != null else -1.0
				handoff["camera_jump"] = camera.global_position.distance_to(last_lasso_eye) if camera != null else INF
				handoff["result_camera_active"] = bool(camera_rig.get("_result_camera_active"))
				for player_index in [1, 2]:
					var ghost: Node3D = director.call("get_result_ghost", player_index)
					var landing: Vector3 = (world as Node3D).to_global(gs.get_result_ghost_landing_local_position(player_index))
					handoff["ghost%d_name" % player_index] = String(ghost.name) if ghost != null else ""
					handoff["ghost%d_from_lasso" % player_index] = ghost != null and bool(ghost.get_meta("result_release_scale", 0.0) == 1.0) and String(ghost.get_parent().name) == "ResultGhosts"
					handoff["ghost%d_error" % player_index] = ghost.global_position.distance_to(landing) if ghost != null else INF
				save_frame("ceremony_first")
			if ceremony_frames == int(fps * 0.5):
				save_frame("ceremony_0.5")
			if ceremony_frames == int(fps * 1.5):
				save_frame("ceremony_1.5")
				break
		await get_tree().process_frame
	check(lasso_seen, "lasso presentation plays when both are out")
	check(not covered, "no screen wipe before the finale")
	for player_index in [1, 2]:
		check(float(emerge.get(player_index, INF)) < 0.6, "P%d soul leaves its body where it fell (%.2f m)" % [player_index, float(emerge.get(player_index, INF))])
	for player_index in [1, 2]:
		cut["soul%d_drift" % player_index] = snappedf(float(stay.get(player_index, INF)), 0.001)
		check(float(stay.get(player_index, INF)) < 0.05, "P%d soul stays where it died until caught (%.3f m)" % [player_index, float(stay.get(player_index, INF))])
	if rider_first in [1, 2]:
		pass
	elif spread == "same":
		check(String(plan.get("mode", "")) == "one_loop", "close souls are caught with one widened loop")
	elif spread.begins_with("far"):
		check(String(plan.get("mode", "")) == "two_ropes", "far souls are caught with a rope in each hand")
	if String(plan.get("mode", "")) == "one_loop":
		# 2 人をまとめた束は、運ぶあいだに回って P1 を +X（自分のレーンの側）へ向ける
		check(float(cut.get("fling_p1_x", 0.0)) >= float(cut.get("fling_p2_x", 0.0)) - 0.1, "souls leave the rope on their own lane sides (no crossing)")
	cut["hatena_onscreen"] = snappedf(float(hatena_inside) / float(maxi(hatena_frames, 1)), 0.001)
	cut["hatena_height"] = snappedf(hatena_height_sum / float(maxi(hatena_inside, 1)), 0.001)
	cut["hatena_offscreen_times"] = hatena_out
	check(float(cut.hatena_onscreen) >= 0.97, "Hatena stays on screen from arrival to the fling (%.1f%%)" % (float(cut.hatena_onscreen) * 100.0))
	if rider_first in [1, 2]:
		check(int(plan.get("shark_rider", 0)) == rider_first, "the soul riding the shark is lassoed where it rides")
		if String(plan.get("mode", "")) == "two_ropes":
			check(bool(cut.get("rider_tied_on_shark", false)), "the rope is cinched while the soul still rides the shark")
		check(bool(cut.get("rider_pulled_off", false)), "the yank pulls the rider off the shark")
	cut["wall_clearance"] = snappedf(wall_clear, 0.01) if is_finite(wall_clear) else "no wall passed"
	check(not is_finite(wall_clear) or wall_clear > 0.0, "the dangling souls fly over the walls (%.2f m)" % wall_clear)
	check(float(cut.get("stand_shift", 0.0)) < -10.0 and absf(float(cut.get("stand_shift", 0.0)) + float(cut.get("scrolled", 0.0))) < 0.5,
		"the side stands stream back with the course (%.1f m for %.1f m)" % [float(cut.get("stand_shift", 0.0)), float(cut.get("scrolled", 0.0))])
	cut["max_camera_step"] = max_step
	cut["max_camera_turn"] = max_turn
	check(max_step < 1.2, "camera never jumps: no cut (largest step %.2f m)" % max_step)
	check(max_turn < 12.0, "camera never snaps round (largest turn %.1f deg)" % max_turn)
	check(int(cut.get("hidden_mask", 0)) == 3, "fallen bodies tidied away behind the flight")
	check(absf(float(cut.get("scroll_ahead", 0.0)) - QuizGameState.RESULT_ELIMINATION_GOAL_AHEAD) < 0.01 or float(cut.get("scroll_ahead", 99.0)) <= QuizGameState.RESULT_ELIMINATION_GOAL_AHEAD, "the course carried the goal in front of the souls")
	check(ceremony_frames > 0 and gs.result_from_elimination, "finale starts after the lasso")
	check(bool(handoff.get("result_camera_active", false)), "finale camera takes over")
	check(float(handoff.get("camera_jump", INF)) < 0.35, "finale camera continues from the lasso shot (%.2f m)" % float(handoff.get("camera_jump", INF)))
	for player_index in [1, 2]:
		check(bool(handoff.get("ghost%d_from_lasso" % player_index, false)), "P%d soul becomes the finale ghost" % player_index)
		check(float(handoff.get("ghost%d_error" % player_index, INF)) < 0.08, "P%d soul stands on its lane at the hand-over (%.3f m)" % [player_index, float(handoff.get("ghost%d_error" % player_index, INF))])
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "fps": fps, "quality": quality,
		"death": death, "spread": spread, "plan": plan, "handoff": handoff, "cut": cut, "max_frame_ms": max_frame_ms, "hitches": hitches,
		"renderer": RenderingServer.get_current_rendering_method(), "samples": samples}
	FileAccess.open(OUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ELIMINATION_LASSO_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"plan": plan, "handoff": handoff, "cut": cut, "max_frame_ms": max_frame_ms, "hitches": hitches}))
	world.queue_free()
	await frames(2)
	for provider in helper.providers: provider.free()
	helper.free()
	get_tree().quit(0 if failures.is_empty() else 1)


## 魂の所（投げ縄の監督の空間）。サメに乗った乗り手はサメの子なので、ワールドから直す。
static func soul_pos(lasso: Node3D, player_index: int) -> Vector3:
	var souls: Variant = lasso.get("_souls")
	var soul := (souls as Dictionary).get(player_index) as Node3D if souls is Dictionary else null
	if soul == null or not is_instance_valid(soul):
		return Vector3.INF
	return lasso.to_local(soul.global_position)


static func vec(value: Variant) -> Array:
	if value is Vector3:
		var v: Vector3 = value
		return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
	return []


func save_frame(tag: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_jpg(OUT + tag + ".jpg", 0.88)
	samples.append({"tag": tag, "state": gs.game_state})


## 2 人とも問題の壁で脱落させる（result_ceremony_runtime の eliminate_both_mid_quiz と同じ）。death=ocean なら 1 人は海へ落とす。
func eliminate_both_mid_quiz() -> void:
	gs.current_index = 3
	gs.current_wall_index = 3
	gs.game_state = Constants.STATE_PLAYING
	gs.load_current_quiz()
	var wall_z := gs.tuning.wall_start_z + 3 * gs.tuning.wall_spacing
	gs.world_scroll_z = wall_z - 7.0
	gs.player_z = gs.world_scroll_z + 0.5
	gs.player2_z = gs.world_scroll_z + 0.5
	await frames(3)
	gs._set_player_hp(1, 1)
	gs._set_player_hp(2, 1)
	var wrong_a := (gs.current_quiz.a + 1) % gs.num_choices
	var wrong_b := wrong_a
	if gs.num_choices == 4 and spread != "same":
		# near はいちばん近い 2 つの不正解の扉、far はいちばん離れた 2 つ
		var best := INF if spread == "near" else -INF
		for i in range(4):
			for j in range(i + 1, 4):
				if i == gs.current_quiz.a or j == gs.current_quiz.a:
					continue
				var gap := absf(gs.tuning.door4_xs[i] - gs.tuning.door4_xs[j])
				if (spread.begins_with("near") and gap < best) or (not spread.begins_with("near") and gap > best):
					best = gap
					wrong_a = j
					wrong_b = i
		if spread.ends_with("_swap"):
			# P1 を −X の側（P2 の左右を入れかえる）
			var keep := wrong_a
			wrong_a = wrong_b
			wrong_b = keep
	gs.player_x = gs.tuning.door4_xs[wrong_a] if gs.num_choices == 4 else (gs.tuning.left_door_x if wrong_a == 0 else gs.tuning.right_door_x)
	gs.player2_x = gs.tuning.door4_xs[wrong_b] if gs.num_choices == 4 else (gs.tuning.left_door_x if wrong_b == 0 else gs.tuning.right_door_x)
	gs.resolve_collision(true, true)
	check(gs.game_state == Constants.STATE_GAME_OVER and gs.is_elimination_result_pending(), "both out mid-quiz hold for the finale")


## 先に 1 人（rider_index）だけ脱落させてゴーストのサメに乗せ（脱落〜光の柱の演出は飛ばす）、照準を合わせているところで
## もう 1 人も脱落させる。サメに乗った幽霊は、乗ったまま投げ縄を待つ。
func eliminate_with_shark_rider(rider_index: int) -> void:
	var survivor := 3 - rider_index
	var ride: Node = world.get("_ghost_shark_ride_controller")
	gs.current_index = 3
	gs.current_wall_index = 3
	gs.game_state = Constants.STATE_PLAYING
	gs.load_current_quiz()
	var wall_z := gs.tuning.wall_start_z + 3 * gs.tuning.wall_spacing
	gs.world_scroll_z = wall_z - 7.0
	gs.player_z = gs.world_scroll_z + 0.5
	gs.player2_z = gs.world_scroll_z + 0.5
	await frames(3)
	gs._set_player_hp(rider_index, 1)
	gs._set_player_hp(survivor, 3)
	var right_x: float = helper.door(gs, true)
	var wrong_x: float = helper.door(gs, false)
	gs.player_x = wrong_x if rider_index == 1 else right_x
	gs.player2_x = wrong_x if rider_index == 2 else right_x
	gs.resolve_collision(true, true)
	var rider_out := not (gs.p1_alive if rider_index == 1 else gs.p2_alive)
	var survivor_on := gs.p1_alive if survivor == 1 else gs.p2_alive
	check(rider_out and survivor_on, "P%d is out first, P%d plays on" % [rider_index, survivor])
	# サメに乗って照準を合わせるまで待つ
	var aiming := false
	for _i in range(fps * 30):
		await get_tree().process_frame
		if ride == null:
			break
		ride.call("practice_skip_intro")
		if int(ride.get("phase")) == GhostSharkRideController.Phase.AIMING:
			aiming = true
			break
	check(aiming, "P%d rides the ghost shark" % rider_index)
	await frames(fps / 2)
	if ride != null and rider_phase in ["charging", "cooldown"]:
		# サメに突進させ、突進の途中（charging）か戻りのポータルの途中（cooldown）でもう 1 人を脱落させる
		ride.set("_last_charge_power", 0.6)
		ride.set("_perfect_charge", false)
		ride.call("_start_charge")
		var want := GhostSharkRideController.Phase.CHARGING if rider_phase == "charging" else GhostSharkRideController.Phase.COOLDOWN
		var reached := false
		for _i in range(fps * 5):
			if int(ride.get("phase")) == want:
				reached = true
				break
			await get_tree().process_frame
		check(reached, "the shark is %s when the survivor goes out" % rider_phase)
		if rider_phase == "cooldown":
			await frames(fps / 4)
		if rider_phase == "cooldown":
			# 突進で吹き飛ばした生き残りが海に落ちるまで少し待つ
			for _i in range(fps * 2):
				if gs.is_player_waiting_for_shark(survivor) or gs.game_state == Constants.STATE_GAME_OVER:
					break
				await get_tree().process_frame
		if gs.is_player_waiting_for_shark(survivor):
			# 突進で海へ落とされた：サメに食べられて両者脱落になるまで、乗り手はサメに乗ったまま待つ
			var held_while_sinking := true
			for _i in range(fps * 20):
				if gs.game_state == Constants.STATE_GAME_OVER:
					break
				held_while_sinking = held_while_sinking and bool(ride.call("is_holding_for_lasso"))
				await get_tree().process_frame
			check(held_while_sinking, "the shark rider stays on the shark while the survivor sinks")
			check(gs.game_state == Constants.STATE_GAME_OVER and gs.is_elimination_result_pending(), "both out hold for the finale")
			check(bool(ride.call("is_holding_for_lasso")), "the shark rider waits on the shark for the lasso")
			return
	# もう 1 人も次の壁で脱落させる
	gs.current_index = 4
	gs.current_wall_index = 4
	gs.load_current_quiz()
	gs.choice_locked = false
	gs._set_player_hp(survivor, 1)
	var wrong_next: float = helper.door(gs, false)
	if survivor == 1:
		gs.player_x = wrong_next
	else:
		gs.player2_x = wrong_next
	gs.resolve_collision(survivor == 1, survivor == 2)
	check(gs.game_state == Constants.STATE_GAME_OVER and gs.is_elimination_result_pending(), "both out hold for the finale")
	check(ride != null and bool(ride.call("is_holding_for_lasso")), "the shark rider waits on the shark for the lasso")
