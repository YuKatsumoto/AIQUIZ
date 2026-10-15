extends Node

## Online end-to-end runtime test (one side of a pair).
## tests/net/run_pair.py starts the real relay and two game processes:
##   host  : queues first, so the relay makes it the host
##   guest : queues second
## Both go through the real lobby scene (random match), the real game world and
## the real NetworkManager / NetGameState. Bots steer with injected key events.
## The guest deliberately takes the wrong door on WRONG_WALLS and the right door
## elsewhere, after running a little ahead of the host so it reaches each wall
## first. Each side writes a JSON report the runner compares.

const WRONG_WALLS := [1, 4]
const PLAY_TIMEOUT_MS := 240000
const KILL_ARG := "kill_at="

var role := "host"
var relay := "ws://127.0.0.1:18766"
var out_path := "user://net_match.json"
var gs: QuizGameState
var world: Node
var report := {"failures": []}
var _held: Dictionary = {}
var _corrections: Array[float] = []
var _far_corrections: Array[float] = []
var _guest_hits: Array = []
var _kill_at_wall := -1
var _killed := false
var _pause_seen := false
var _resume_seen := false
var _shots_dir := ""
var _quit_at_wall := -1
## scenario=push: both run at each other after the start; the guest keeps re-pressing to strike.
## scenario=staging: also records the matching presentation (states, cut-in names and poses, match -> reveal time).
## scenario=quit_at_cutin: the host (it matches first, so it reaches the cut-in first) vanishes as its cut-in starts;
##   the guest, still in the join or formation shot, must search again in the air (D12).
var _scenario := ""
var _staging := {"states": [], "cutin_names": [], "cutin_poses": []}
## 中央の線が開いたあとのヘリ登場（計画書 M9）：監督があるか、降ろし終えたか、着地してから始まったか。
var _arrival := {"present": false}
var _matched_ms := -1
var _push_counts := {}
var _push_contact_seen := false
var _push_shots := 0
var _match_over_message := ""
var _shot_walls: Dictionary = {}
## カウントダウンが終わって走り出した時刻（ms）。少しあとに「じぶん」の矢印が出ている画面を撮る。
var _go_ms := -1
## 対峙の演出のフレーム時間（ms）：JOIN・FORMATION・CUTIN_IN・CUTIN_HOLD・SWAP（メニュー）、COVER（覆いの静止画の下でゲーム画面を準備）、
## REVEAL（覆いが割れて開くあいだ）。カクつき（HITCH_MS をこえるフレーム）を数える
const HITCH_MS := 25.0
var _vs_frames: Dictionary = {}
var _vs_last_us := 0
## ホスト：REVEAL のあいだに問題生成が始まっていたか（始まっていてはいけない）
var _generation_in_reveal := false
## 25 ms をこえたフレーム：[区間, マッチからの秒, ms, メニューの読み込みの状態, そのフレームのパイプライン生成数]
var _vs_hitches: Array = []
var _menu_ref: Node = null
var _vs_compiles := 0
var _vs_skip_frame := false


func _ready() -> void:
	call_deferred("run")


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var phase := _vs_phase()
	var compiles := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		compiles += RenderingServer.get_rendering_info(info)
	var new_compiles := compiles - _vs_compiles
	_vs_compiles = compiles
	if _vs_skip_frame:
		_vs_skip_frame = false
		phase = ""
	if _vs_last_us > 0 and not phase.is_empty():
		if not _vs_frames.has(phase):
			_vs_frames[phase] = []
		var ms := float(now - _vs_last_us) / 1000.0
		(_vs_frames[phase] as Array).append(ms)
		if ms > HITCH_MS and (_vs_frames[phase] as Array).size() > 1:
			_vs_hitches.append([phase, snappedf(float(Time.get_ticks_msec() - _matched_ms) / 1000.0, 0.01), snappedf(ms, 0.1),
				int(_menu_ref.get("_load_state")) if is_instance_valid(_menu_ref) else -1, new_compiles])
		if phase == "REVEAL" and NetworkManager.is_host and gs != null and not gs.quiz_generation_deferred:
			_generation_in_reveal = true
	_vs_last_us = now


func _vs_phase() -> String:
	var scene := get_tree().current_scene
	if scene is OnlineMenu:
		var director := (scene as OnlineMenu).director
		if director != null and director.state_name() in ["JOIN", "FORMATION", "CUTIN_IN", "CUTIN_HOLD", "SWAP"]:
			return director.state_name()
		if director != null:
			return "MENU_" + director.state_name()
		return ""
	if scene != null and scene.scene_file_path == OnlineMenu.GAME_WORLD_PATH and SceneTransition.is_transitioning():
		return "REVEAL" if SceneTransition.versus_split_opening else "COVER"
	return ""


func _vs_frame_report() -> Dictionary:
	var out := {}
	for phase: String in _vs_frames:
		var values: Array = (_vs_frames[phase] as Array).duplicate()
		# 区間に入った最初のフレーム（シーンの切り替え）は別に見る
		var first: float = values[0]
		values = values.slice(1)
		if values.is_empty():
			continue
		values.sort()
		var hitches := 0
		for v: float in values:
			if v > HITCH_MS:
				hitches += 1
		out[phase] = {"frames": values.size(), "median_ms": snappedf(values[values.size() / 2], 0.01),
			"p99_ms": snappedf(values[mini(values.size() - 1, int(ceil(values.size() * 0.99)) - 1)], 0.01),
			"max_ms": snappedf(values[-1], 0.01), "hitches": hitches, "first_ms": snappedf(first, 0.01)}
	return out


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("role="): role = arg.trim_prefix("role=")
		if arg.begins_with("relay="): relay = arg.trim_prefix("relay=")
		if arg.begins_with("out="): out_path = arg.trim_prefix("out=")
		if arg.begins_with(KILL_ARG): _kill_at_wall = int(arg.trim_prefix(KILL_ARG))
		if arg.begins_with("shots="): _shots_dir = arg.trim_prefix("shots=")
		if arg.begins_with("quit_at="): _quit_at_wall = int(arg.trim_prefix("quit_at="))
		if arg.begins_with("scenario="): _scenario = arg.trim_prefix("scenario=")
	report["role"] = role
	gs = QuizManager.game_state
	QuizManager.player_analytics = null
	gs.subject = "算数"
	gs.grade = 3
	gs.difficulty = "普通"
	QuizManager.provider.set_llm_mode("OFFLINE")
	# 2 つのプロセスは同じ設定ファイルを読むので、名前を役ごとに分ける（保存はしない）
	GameManager.online_name = "ホストの テスト" if role == "host" else "ゲストの テスト"
	NetworkManager.relay_url = relay
	NetworkManager.state_changed.connect(func(state: int) -> void:
		if state == NetworkManager.State.RECONNECTING:
			_pause_seen = true)
	NetworkManager.resumed.connect(func(_info: Dictionary) -> void: _resume_seen = true)
	NetworkManager.peer_resumed.connect(func(_who: String) -> void: _resume_seen = true)
	NetworkManager.peer_paused.connect(func(_who: String, _g: float) -> void: _pause_seen = true)

	get_tree().change_scene_to_file(OnlineMenu.SCENE_PATH)
	await _frames(5)
	var menu := get_tree().current_scene as OnlineMenu
	if menu == null:
		_finish("online menu did not open")
		return
	if not _shots_dir.is_empty() and role == "host":
		await _frames(10)
		await _shot("lobby_home")
		(menu.page(OnlineMenu.HOME) as OnlineHomePage).roll_name()
		await _frames(5)
		await _shot("lobby_dice")
		report["dice_name"] = GameManager.online_name
	_menu_ref = menu
	_watch_staging(menu)
	# VS 演出の効果音が鳴った時刻（マッチから）
	_staging["sfx"] = []
	AudioManager.sfx_played.connect(func(cue: StringName) -> void:
		if String(cue).begins_with("versus_") and _matched_ms >= 0:
			(_staging.sfx as Array).append([String(cue), snappedf(float(Time.get_ticks_msec() - _matched_ms) / 1000.0, 0.01)]))
	menu.find_match()
	if _scenario == "quit_at_cutin":
		await _quit_at_cutin(menu)
		return
	if not _shots_dir.is_empty():
		await _wait(func() -> bool: return NetworkManager.state == NetworkManager.State.IN_LOBBY, 60000)
		await _frames(20)
		await _shot("lobby_vs")
	if not await _wait(func() -> bool: return _in_game_world(), 60000):
		_finish("never reached the game world")
		return
	world = get_tree().current_scene
	_watch_arrival(world)
	# 中央の線が開き始めた時刻（マッチから。受け入れ基準 A6）
	if await _wait(func() -> bool: return SceneTransition.get_cover_factor() < 0.999, 20000) and _matched_ms >= 0:
		_staging["match_to_reveal_s"] = snappedf(float(Time.get_ticks_msec() - _matched_ms) / 1000.0, 0.01)
	report["is_host"] = NetworkManager.is_host
	report["local_slot"] = gs.local_slot
	if (role == "host") != NetworkManager.is_host:
		report.failures.append("role mismatch: expected %s" % role)

	if not await _wait(func() -> bool: return gs.game_state != Constants.STATE_PRELOADING and gs.game_state != Constants.STATE_MENU, 60000):
		_finish("stuck in preloading (quizzes never arrived)")
		return
	if NetworkManager.is_host:
		if not await _wait(func() -> bool:
			if gs.game_state == Constants.STATE_WAITING_START:
				_tap_key(KEY_ENTER)
			return gs.game_state not in [Constants.STATE_WAITING_START, Constants.STATE_PRELOADING], 60000):
			_finish("host could not start the round")
			return
	if not await _wait(func() -> bool: return gs.game_state == Constants.STATE_PLAYING, 30000):
		_finish("never reached PLAYING")
		return

	await _play()
	_record_state()
	await _check_return_to_menu()
	_finish("")


## ヘリ登場の記録（両方の画面で、それぞれのヘリが 2 人を運んでくる）。
func _watch_arrival(game_world: Node) -> void:
	var director := game_world.get_node_or_null("HelicopterArrivalDirector") as HelicopterArrivalDirector
	if director == null:
		return
	_arrival["present"] = true
	_arrival["helicopters"] = director._helicopters.size()
	var t0 := Time.get_ticks_msec()
	director.presentation_finished.connect(func(success: bool) -> void:
		_arrival["finished"] = success
		_arrival["unlocked_s"] = snappedf(float(Time.get_ticks_msec() - t0) / 1000.0, 0.01))
	var shot_taken := false
	while is_instance_valid(director) and is_inside_tree():
		if director.has_started_arrival() and not _arrival.has("started_s"):
			_arrival["started_s"] = snappedf(float(Time.get_ticks_msec() - t0) / 1000.0, 0.01)
		if _arrival.has("started_s") and not shot_taken and float(Time.get_ticks_msec() - t0) / 1000.0 > float(_arrival.started_s) + 2.0:
			shot_taken = true
			await _shot("arrival")
		if gs.game_state not in [Constants.STATE_PRELOADING, Constants.STATE_WAITING_START] and not _arrival.has("landed_before_start"):
			_arrival["landed_before_start"] = director.have_players_touched_down() and bool(_arrival.get("finished", false))
			_arrival["start_s"] = snappedf(float(Time.get_ticks_msec() - t0) / 1000.0, 0.01)
			return
		await get_tree().process_frame


## マッチング演出の記録：状態の順、カットインの名前とポーズ、マッチの時刻。
func _watch_staging(menu: OnlineMenu) -> void:
	NetworkManager.matched.connect(func(_info: Dictionary) -> void: _matched_ms = Time.get_ticks_msec(), CONNECT_ONE_SHOT)
	if menu.director == null:
		_staging["no_director"] = true
		return
	menu.director.state_changed.connect(func(state: int) -> void:
		var name: String = OnlineStagingDirector.STATE_NAMES[state]
		_staging.states.append(name)
		if _matched_ms >= 0:
			_staging["t_" + name] = snappedf(float(Time.get_ticks_msec() - _matched_ms) / 1000.0, 0.01)
		_staging["load_state_at_" + name] = int(menu.get("_load_state"))
		if name == "CUTIN_IN" and menu.cutin != null:
			var names := menu.cutin.names()
			_staging["cutin_names"] = names
			_staging["cutin_poses"] = [OnlineStagingTimeline.cutin_pose_index(names[0]), OnlineStagingTimeline.cutin_pose_index(names[1])]
			if _scenario == "quit_at_cutin" and role == "host":
				OS.kill(OS.get_process_id()))


## ホストはカットインが始まったところで消える（_watch_staging）。ゲストは空のまま探し直すことを確かめる。
func _quit_at_cutin(menu: OnlineMenu) -> void:
	if role == "host":
		await _wait(func() -> bool: return false, 90000)
		_finish("host was expected to vanish at the cut-in")
		return
	var requeued := await _wait(func() -> bool: return menu.director != null and menu.director.state_name() == "REQUEUE", 90000)
	report["requeued"] = requeued
	if not requeued:
		_finish("guest did not search again after the host vanished at the cut-in")
		return
	var back := await _wait(func() -> bool: return menu.director.state_name() == "CRUISE" and menu.current_id() == OnlineMenu.SEARCH, 10000)
	report["back_to_search"] = back
	if not back:
		report.failures.append("guest did not return to the search band in the air")
	menu.cancel_search()
	_finish("")


func _play() -> void:
	var started := Time.get_ticks_msec()
	var mine := gs.local_slot
	var net: NetGameState = world.get("_net_state")
	net.match_over.connect(func(message: String) -> void: _match_over_message = message)
	gs.local_push_event.connect(func(event: Dictionary) -> void:
		var key := str(event.kind)
		if key == "hit":
			key = "hit_p%d" % int(event.player)
		_push_counts[key] = int(_push_counts.get(key, 0)) + 1)
	while Time.get_ticks_msec() - started < PLAY_TIMEOUT_MS:
		await get_tree().process_frame
		if gs.game_state in [Constants.STATE_GOAL_RACE, Constants.STATE_CLEAR, Constants.STATE_GAME_OVER, Constants.STATE_RESULT_CEREMONY]:
			break
		if net.finished:
			break
		var alive := gs.p1_alive if mine == 1 else gs.p2_alive
		if not alive:
			_release_all()
			continue
		if _quit_at_wall >= 0 and gs.current_wall_index >= _quit_at_wall:
			# Vanish without a goodbye (closed laptop): the relay must forfeit us after the grace window.
			OS.kill(OS.get_process_id())
		if _kill_at_wall >= 0 and not _killed and gs.current_wall_index >= _kill_at_wall:
			_killed = true
			report["killed_at_wall"] = gs.current_wall_index
			# Simulate a dropped link: close the socket without a goodbye.
			NetworkManager._ws.close()
		var playing := gs.game_state == Constants.STATE_PLAYING and not net.paused
		await _steer(mine, playing, started)
		if not _shots_dir.is_empty() and playing and _go_ms != -2:
			if _go_ms < 0:
				_go_ms = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - _go_ms > 1200:
				_go_ms = -2
				await _shot("go")
		if not _shots_dir.is_empty() and playing and gs.current_wall_index in [2, 5] and not _shot_walls.has(gs.current_wall_index):
			var to_wall := gs.wall_z - gs.player2_z
			if to_wall < 4.0:
				_shot_walls[gs.current_wall_index] = true
				await _shot("wall%d" % gs.current_wall_index)
		if mine == 2 and net.predictor != null and net.predictor.is_active():
			_corrections.append(net.predictor.last_correction)
			# Body contact with the other player is resolved on the host only.
			if absf(gs.player_x - gs.player2_x) > 1.5 and gs.p2_damage_time <= 0.0:
				_far_corrections.append(net.predictor.last_correction)
	_release_all()
	# Let the last snapshots and events land.
	await _wait(func() -> bool: return false, 1500)


func _steer(mine: int, playing: bool, started: int) -> void:
	if not playing or gs.current_quiz == null:
		_release_all()
		return
	if _scenario == "push" and Time.get_ticks_msec() - started < 4000:
		await _steer_push(mine, started)
		return
	var x := gs.player_x if mine == 1 else gs.player2_x
	var answer := gs.current_quiz.a
	var target_door := answer
	if mine == 2 and gs.current_wall_index in WRONG_WALLS:
		target_door = (answer + 1) % gs.num_choices
	var target_x := _door_x(target_door)
	# Guest runs a little ahead early on so it reaches each wall first.
	_hold(KEY_W, mine == 2 and _scenario != "push" and Time.get_ticks_msec() - started < 900)
	# KEY_A raises x, KEY_D lowers it (see game_world input mapping).
	_hold(KEY_A, x < target_x - 0.25)
	_hold(KEY_D, x > target_x + 0.25)
	if mine == 2:
		var lz := gs.player2_z - gs.world_scroll_z
		var wall_ahead := gs.wall_z - gs.world_scroll_z - lz
		if wall_ahead < 0.6 and wall_ahead > -1.5 and _guest_hits.size() <= gs.current_wall_index:
			_guest_hits.append({"wall": gs.current_wall_index, "x": snappedf(x, 0.01), "door": gs._check_player_door(x), "answer": answer})


func _steer_push(mine: int, started: int) -> void:
	var my_x := gs.player_x if mine == 1 else gs.player2_x
	var their_x := gs.player2_x if mine == 1 else gs.player_x
	var toward := KEY_A if their_x > my_x else KEY_D
	var away := KEY_D if toward == KEY_A else KEY_A
	_hold(KEY_W, false)
	_hold(away, false)
	if gs.local_push.contact:
		_push_contact_seen = true
	if mine == 1:
		_hold(toward, true)
	else:
		# Hold to brace, then release and press again to strike.
		var phase := (Time.get_ticks_msec() - started) % 330
		_hold(toward, phase < 250)
	if not _shots_dir.is_empty() and mine == 2 and _push_shots < 3 and gs.local_push.contact and (gs.local_push.is_shoving(1, 0.0) or gs.local_push.is_shoving(2, 0.0)):
		_push_shots += 1
		await _shot("push%d" % _push_shots)


func _shot(name: String) -> void:
	if _shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	image.save_png("%s/%s_%s.png" % [_shots_dir, role, name])
	# PNG の保存で止まったフレームは、演出の重さに数えない
	_vs_skip_frame = true


func _door_x(door: int) -> float:
	if gs.num_choices == 4:
		return gs.tuning.door4_xs[clampi(door, 0, 3)]
	return gs.tuning.left_door_x if door == 0 else gs.tuning.right_door_x


func _hold(key: Key, down: bool) -> void:
	if bool(_held.get(key, false)) == down:
		return
	_held[key] = down
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = down
	Input.parse_input_event(event)


func _release_all() -> void:
	for key in _held.keys():
		_hold(key, false)


func _tap_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	var up := event.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _in_game_world() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == "res://scenes/game_world.tscn"


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


## 試合の結果を書き留める（オンラインメニューへ戻ると状態が消えるので、その前に）。
func _record_state() -> void:
	if gs == null or report.has("state"):
		return
	report["state"] = gs.game_state
	report["wall"] = gs.current_wall_index
	report["winners"] = Array(gs.question_winners)
	report["hp"] = [gs.p1_hp, gs.p2_hp]
	report["scores"] = [gs.score, gs.player2_score]
	report["alive"] = [gs.p1_alive, gs.p2_alive]
	report["p2"] = [snappedf(gs.player2_x, 0.01), snappedf(gs.player2_z - gs.world_scroll_z, 0.01)]


## 試合のあとはオンラインメニューへ戻る（結果画面の「オンラインメニューへ」と同じ経路）。
func _check_return_to_menu() -> void:
	OnlineMenu.return_from_match(get_tree())
	var back := await _wait(func() -> bool:
		var scene := get_tree().current_scene
		return scene is OnlineMenu and (scene as OnlineMenu).current_id() == OnlineMenu.HOME, 10000)
	report["returned_to_online_menu"] = back
	if not back:
		report.failures.append("did not return to the online menu after the match")
	elif not _shots_dir.is_empty() and role == "host":
		await _frames(10)
		await _shot("menu_after_match")


func _finish(error: String) -> void:
	if not error.is_empty():
		report.failures.append(error)
	_record_state()
	report["guest_hits"] = _guest_hits
	if not _vs_frames.is_empty():
		_staging["vs_frames"] = _vs_frame_report()
		_staging["generation_in_reveal"] = _generation_in_reveal
		_staging["vs_hitches"] = _vs_hitches
	report["pause_seen"] = _pause_seen
	report["resume_seen"] = _resume_seen
	if not _corrections.is_empty():
		var total := 0.0
		var worst := 0.0
		var big := 0
		for c in _corrections:
			total += c
			worst = maxf(worst, c)
			if c > 0.3:
				big += 1
		report["corrections"] = {"samples": _corrections.size(), "mean": snappedf(total / _corrections.size(), 0.0001), "max": snappedf(worst, 0.001), "over_0_3": big}
	if not _far_corrections.is_empty():
		var far_total := 0.0
		var far_worst := 0.0
		for c in _far_corrections:
			far_total += c
			far_worst = maxf(far_worst, c)
		report["far_corrections"] = {"samples": _far_corrections.size(), "mean": snappedf(far_total / _far_corrections.size(), 0.0001), "max": snappedf(far_worst, 0.001)}
	report["rtt_ms"] = NetworkManager.rtt_ms
	report["match_over"] = _match_over_message
	report["push_events"] = _push_counts
	report["push_contact_seen"] = _push_contact_seen
	report["staging"] = _staging
	report["arrival"] = _arrival
	report["passed"] = (report.failures as Array).is_empty()
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("NET_MATCH " + JSON.stringify(report))
	NetworkManager.leave_match()
	get_tree().quit(0 if report.passed else 1)
