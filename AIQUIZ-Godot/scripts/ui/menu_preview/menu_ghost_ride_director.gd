class_name MenuGhostRideDirector
extends Node3D

## メニュー背景（2P）で、死んだランナーがときどきゴーストシャークに乗って生き残った方を襲う。
## 演出は本編の GhostSharkRideController をそのまま使う（死亡 → 魂がサメへ → 光の柱 → 登場 → 照準・突進の繰り返し）。
## ここは、乗るかどうかの抽選、死んだ側の入力（MenuGhostRiderBrain）、体当たりをメニューの吹き飛びへ直すこと、
## 生き残った側の見物・警戒・回避、ライド中のノコギリの退避、画面の構図、途中で終わるときの後始末を受け持つ。

const Brain = preload("res://scripts/ui/menu_preview/menu_ghost_rider_brain.gd")
const AIState = preload("res://scripts/ui/menu_preview_actor_ai_state.gd")
const Phase = GhostSharkRideController.Phase

## テストと PV 撮影が止めるための全体のスイッチ
static var globally_enabled: bool = true

## 乗れる死亡のうち実際に乗る割合
const CHANCE: float = 0.34
## ライドの終わりから次のライドまで
const COOLDOWN_SEC: float = 50.0
## メニューを開いてから最初のライドまで（背景がいきなり物騒にならないように）
const FIRST_RIDE_AFTER_SEC: float = 15.0
## 本編の演出を読み込む時刻（最初のライドより前に、目立たないうちに済ませる）
const SETUP_AFTER_SEC: float = 3.0
## ノコギリでの死亡（専用の復活の流れがある）と、2P の取り外しは対象外
const ELIGIBLE_CAUSES: Array[String] = ["crash", "ocean"]
const DASHES_MIN: int = 2
const DASHES_MAX: int = 3
## これを過ぎたら次のクールダウンで帰る／これを過ぎたら何をしていても降りる
const SOFT_TIMEOUT_SEC: float = 36.0
const HARD_TIMEOUT_SEC: float = 48.0
## ライドが終わってから死んだ側が空から降ってくるまで
const RESPAWN_DELAY_SEC: float = 0.7
## 本編の吹き飛び（10.5〜18.5 m/s）はメニューのコンベアには強すぎるので弱める
const KNOCKBACK_SPEED_SCALE: float = 0.6
const DODGE_CHANCE: float = 0.35
const DODGE_ROLL_SHARE: float = 0.35
const DODGE_REACTION_MIN: float = 0.06
const DODGE_REACTION_MAX: float = 0.2
## 待つ場所はコンベアの右（メニューの UI は画面の左）。床の端（x=12）からこれだけ外、生き残った人より前（-z）。
const HOVER_SIDE: float = 1.0
const HOVER_OUTSIDE_OFFSET: float = 1.6
const HOVER_DEPTH_CANDIDATES: Array[float] = [-7.0, -8.5, -10.0, -11.5, -13.0, -14.5, -16.0]
## 海から上がる場所：待つ場所の外側・少し手前
const RENDEZVOUS_SIDE: float = 1.5
const RENDEZVOUS_DEPTH: float = 5.0
## サメと光の柱を収めたい画面の範囲（0〜1。左のメニュー UI にかからない右側）
const SCREEN_SAFE_RECT := Rect2(0.64, 0.12, 0.30, 0.76)
## 降りた乗り手が浮かんで消えるまで
const DISMOUNT_FLOAT_SECONDS: float = 0.7
const DISMOUNT_FLOAT_HEIGHT: float = 1.2

var host: MenuWallBackgroundPreview
var controller: GhostSharkRideController = null
var rng := RandomNumberGenerator.new()
var brain: MenuGhostRiderBrain
## テストが発動を確実にするときに書き換える
var chance: float = CHANCE
var cooldown_sec: float = COOLDOWN_SEC
var first_ride_after_sec: float = FIRST_RIDE_AFTER_SEC
var dodge_chance: float = DODGE_CHANCE
## 回数の記録（テストと確認用）
var stats := {"armed": 0, "rides": 0, "dashes": 0, "hits": 0, "dodges": 0, "ocean_kills": 0, "aborted": 0, "finished": 0}

var _armed := false
var _armed_dead_is_p1 := false
var _riding := false
var _ride_dead_is_p1 := false
var _ride_started_at := 0.0
var _dashes := 0
var _max_dashes := DASHES_MIN
var _last_ride_end := -INF
var _last_phase: int = Phase.INACTIVE
var _retire_requested := false
var _dodge_at := -1.0
var _dodge_dir := Vector2.ZERO
var _dodge_roll := false
var _shards_scheduled := false
## 乗せ終えて海へ潜るまで隠しておくサメ
var _hidden_sharks: Array[Node3D] = []
## 降りて浮かびながら消える乗り手 {node, t, from, scale}
var _floating_riders: Array[Dictionary] = []


func _init(p_host: MenuWallBackgroundPreview) -> void:
	host = p_host
	name = "MenuGhostRideDirector"
	rng.randomize()
	brain = Brain.new(rng)


func is_riding() -> bool:
	return _riding


func is_armed() -> bool:
	return _armed


func ride_phase() -> int:
	return controller.phase if controller != null else Phase.INACTIVE


## ライドが始まっているあいだはノコギリを持ち場へ戻して止める（吹き飛んだ先がノコギリにならないように）。
func wants_saw_clear() -> bool:
	return _riding and controller != null and controller.phase != Phase.INACTIVE


## 本編の演出を作る。メニューの舞台ができてから呼ぶ（最初のライドより前に自分で呼ぶ）。
func ensure_controller() -> bool:
	if controller != null:
		return true
	var pc := host._preview_player as PlayerController
	if host._preview_gs == null or host._stage_env == null or pc == null:
		return false
	controller = GhostSharkRideController.new()
	controller.name = "MenuGhostSharkRide"
	controller.auto_detect_deaths = false
	add_child(controller)
	controller.setup(host._preview_gs, host._stage_env, pc, null, null)
	controller.set_hud_enabled(false)
	controller.view_camera = host._preview_camera
	controller.hover_side_override = HOVER_SIDE
	controller.hover_outside_offset = HOVER_OUTSIDE_OFFSET
	controller.rendezvous_side_distance = RENDEZVOUS_SIDE
	controller.rendezvous_depth_offset = RENDEZVOUS_DEPTH
	controller.heroic_follow_survivor = false
	controller.charge_resolved.connect(_on_charge_resolved)
	return true


## MenuWallBackgroundPreview._trigger_preview_death の最後に呼ばれる。
func on_actor_died(dead_is_p1: bool, reason: String) -> void:
	if _riding and dead_is_p1 != _ride_dead_is_p1:
		# 襲われていた側が死んだ（海へ落とされた・壁に当たった）：サメは帰る
		if reason == "ocean":
			stats.ocean_kills += 1
		abort(ride_phase() not in [Phase.CHARGING, Phase.COOLDOWN])
		return
	if _armed and dead_is_p1 != _armed_dead_is_p1:
		_disarm()
		return
	if not _can_arm(dead_is_p1, reason):
		return
	if rng.randf() >= chance:
		return
	_armed = true
	_armed_dead_is_p1 = dead_is_p1
	host._ai.bundle_for(dead_is_p1).respawn_hold = true
	stats.armed += 1


func _can_arm(dead_is_p1: bool, reason: String) -> bool:
	if not globally_enabled or _armed or _riding or controller == null:
		return false
	if reason not in ELIGIBLE_CAUSES or not host._is_local_2p_active():
		return false
	if host._customize_active or host._menu_start_departure_active or host._menu_departure_hold or host._menu_intro_active:
		return false
	if host._linger_time < first_ride_after_sec or host._linger_time - _last_ride_end < cooldown_sec:
		return false
	var survivor_is_p1 := not dead_is_p1
	if not host._actor_alive(survivor_is_p1):
		return false
	var survivor := host._ai.bundle_for(survivor_is_p1)
	if survivor.ai_state not in [AIState.STATE_NORMAL, AIState.STATE_ACROBATICS, AIState.STATE_TAUNT]:
		return false
	for shark: Node3D in host._stage_env.get_ocean_sharks():
		if is_instance_valid(shark) and shark.call("is_available_for_ocean_attack"):
			return true
	return false


func update(dt: float) -> void:
	_update_hidden_sharks()
	_update_floating_riders(dt)
	if controller == null:
		if host._linger_time >= SETUP_AFTER_SEC and globally_enabled:
			ensure_controller()
		if controller == null:
			if _armed:
				_disarm()
			return
	if not globally_enabled:
		if _armed:
			_disarm()
		if _riding:
			abort(false)
		return
	if _armed and not _riding:
		_try_begin()
	if not _riding:
		return
	if not _validate_ride():
		return
	var survivor_is_p1 := not _ride_dead_is_p1
	var survivor := host._ai.bundle_for(survivor_is_p1)
	var survivor_position := Vector3(
		host._actor_x(survivor_is_p1), host._actor_y(survivor_is_p1), host._actor_local_z(survivor_is_p1)
	)
	var cmd := brain.update(
		dt, controller.phase, controller.get_aim_point(), survivor_position,
		Vector2(survivor.vel_x, survivor.vel_z), controller.get_charge_amount()
	)
	var axis: Vector2 = cmd.axis
	var fire: bool = cmd.fire
	var emote: int = cmd.emote
	var dead_p1 := _ride_dead_is_p1
	controller.update_ghost_ride(
		dt,
		axis if dead_p1 else Vector2.ZERO,
		Vector2.ZERO if dead_p1 else axis,
		fire and dead_p1,
		fire and not dead_p1,
		emote if dead_p1 else 0,
		0 if dead_p1 else emote,
		false,
		false
	)
	_consume_hit(survivor_is_p1)
	if controller.phase == Phase.INACTIVE:
		# 本編の制御が自分で畳んだ（続けられない状態になった）
		_finish_ride()
		return
	if controller.phase != _last_phase:
		_on_phase_changed(controller.phase)
		_last_phase = controller.phase
	if _retire_requested:
		_retire_requested = false
		_retire(true)
		return
	if host._linger_time - _ride_started_at >= HARD_TIMEOUT_SEC:
		abort(true)
		return
	_update_survivor(survivor, survivor_is_p1)


func _try_begin() -> void:
	var dead_is_p1 := _armed_dead_is_p1
	var survivor_is_p1 := not dead_is_p1
	_fit_composition(survivor_is_p1)
	brain.reset()
	brain.emotes = host._ai.bundle_for(dead_is_p1).available_emotes.duplicate()
	if not controller.begin_for_dead_player(1 if dead_is_p1 else 2):
		_disarm()
		return
	_armed = false
	_riding = true
	_ride_dead_is_p1 = dead_is_p1
	_ride_started_at = host._linger_time
	_dashes = 0
	_max_dashes = rng.randi_range(DASHES_MIN, DASHES_MAX)
	_last_phase = controller.phase
	_retire_requested = false
	_dodge_at = -1.0
	_shards_scheduled = false
	stats.rides += 1


func _disarm() -> void:
	if not _armed:
		return
	_armed = false
	var dead := host._ai.bundle_for(_armed_dead_is_p1)
	dead.respawn_hold = false


## 続けられないなら畳んで false。
func _validate_ride() -> bool:
	var survivor_is_p1 := not _ride_dead_is_p1
	if host._customize_active or host._menu_start_departure_active or host._menu_departure_hold:
		abort(false)
		return false
	if not host._is_local_2p_active():
		abort(true)
		return false
	if not host._actor_alive(survivor_is_p1) or host._actor_alive(_ride_dead_is_p1):
		abort(ride_phase() not in [Phase.CHARGING, Phase.COOLDOWN])
		return false
	return true


func _on_phase_changed(phase: int) -> void:
	var survivor_is_p1 := not _ride_dead_is_p1
	var survivor := host._ai.bundle_for(survivor_is_p1)
	match phase:
		Phase.SOUL_FLIGHT:
			if not _shards_scheduled:
				_shards_scheduled = true
				host._schedule_death_shard_cleanup(_ride_dead_is_p1)
		Phase.MOUNTING:
			# 煽りをやめて、サメに乗るのを見る
			host._ai_emotes.end_taunt(survivor_is_p1, 0.0)
			survivor.ghost_mode = AIState.GHOST_MODE_WATCH
		Phase.ENTERING:
			# 壁に当たって止まっていたコンベアを動かし、狙われる前に走り出す
			host._resume_preview_conveyor()
			host._ai_emotes.end_taunt(survivor_is_p1, 0.0)
			survivor.ghost_mode = AIState.GHOST_MODE_ALERT
			survivor.next_action_t = minf(survivor.next_action_t, host._ai_time + 0.3)
		Phase.WINDUP:
			_plan_dodge(survivor_is_p1)


func _on_charge_resolved(_player_index: int, hit: bool, _power: float) -> void:
	if not _riding:
		return
	_dashes += 1
	stats.dashes += 1
	if hit:
		stats.hits += 1
	# 本編の制御の更新の途中なので、終わらせるのは更新が済んでから
	if _dashes >= _max_dashes or host._linger_time - _ride_started_at >= SOFT_TIMEOUT_SEC:
		_retire_requested = true


## 突進の向きと直角に、コンベアの中央寄り（または広いほう）へよける
func _plan_dodge(survivor_is_p1: bool) -> void:
	if rng.randf() >= dodge_chance:
		return
	var locked := controller.get_locked_direction()
	var along := Vector2(locked.x, locked.z)
	if along.length_squared() < 0.0001:
		return
	along = along.normalized()
	var side := Vector2(-along.y, along.x)
	var here := Vector2(host._actor_x(survivor_is_p1), host._actor_local_z(survivor_is_p1))
	var a := here + side * 2.0
	var b := here - side * 2.0
	_dodge_dir = side if _room_score(a) >= _room_score(b) else -side
	_dodge_roll = rng.randf() < DODGE_ROLL_SHARE
	_dodge_at = host._ai_time + rng.randf_range(DODGE_REACTION_MIN, DODGE_REACTION_MAX)


func _room_score(point: Vector2) -> float:
	var x_room := MenuActorAI.PLAYER_X_MAX + 0.6 - absf(point.x)
	var z_room := minf(point.y - MenuPreviewGeometry.BELT_Z_MIN, MenuPreviewGeometry.BELT_EDGE_FALL_Z - point.y)
	return minf(x_room, z_room)


func _update_survivor(survivor: MenuPreviewActorAIState, survivor_is_p1: bool) -> void:
	var shark := controller.get_shark()
	if shark != null and is_instance_valid(shark):
		survivor.ghost_watch_target = shark.global_position
	if _dodge_at >= 0.0 and host._ai_time >= _dodge_at:
		_dodge_at = -1.0
		if host._ai.start_dodge(survivor, survivor_is_p1, _dodge_dir, _dodge_roll):
			stats.dodges += 1


## 本編の体当たりは game_state の外力として入る（メニューは game_state.update() を回さない）ので、
## 取り出してメニューの吹き飛びへ直す。
func _consume_hit(survivor_is_p1: bool) -> void:
	var gs := host._preview_gs
	var impulse := gs.p1_external_velocity if survivor_is_p1 else gs.p2_external_velocity
	if impulse.length_squared() < 0.0001:
		return
	var lock := gs.p1_external_control_lock if survivor_is_p1 else gs.p2_external_control_lock
	if survivor_is_p1:
		gs.p1_external_velocity = Vector2.ZERO
		gs.p1_external_control_lock = 0.0
	else:
		gs.p2_external_velocity = Vector2.ZERO
		gs.p2_external_control_lock = 0.0
	host._ai.start_knockback(
		host._ai.bundle_for(survivor_is_p1), survivor_is_p1, impulse * KNOCKBACK_SPEED_SCALE,
		host._actor_vel_y(survivor_is_p1), lock
	)


## ライドを途中でやめる。dismount なら乗り手を降ろして浮かべて消し、そうでなければ静かに消す。
func abort(dismount: bool) -> void:
	if _armed:
		_disarm()
	if not _riding:
		return
	stats.aborted += 1
	_retire(not dismount)


## 何をしていても今すぐ畳む（カスタマイズ・出発・画面を離れるとき）。
func abort_all() -> void:
	abort(false)


func _retire(quiet: bool) -> void:
	if controller != null and controller.phase != Phase.INACTIVE:
		var shark := controller.get_shark()
		var was_hidden := shark != null and is_instance_valid(shark) and not shark.visible
		var rider := controller.retire_ride(null if quiet else self)
		if rider != null:
			_floating_riders.append({"node": rider, "t": 0.0, "from": rider.global_position, "scale": rider.scale})
		if shark != null and is_instance_valid(shark) and (quiet or was_hidden):
			# 潜りきるまで見せない（宙で急に現れないように）
			shark.visible = false
			if not _hidden_sharks.has(shark):
				_hidden_sharks.append(shark)
	_finish_ride()


func _finish_ride() -> void:
	if not _riding:
		return
	_riding = false
	stats.finished += 1
	var dead := host._ai.bundle_for(_ride_dead_is_p1)
	dead.respawn_hold = false
	dead.dead_end_t = maxf(dead.dead_end_t, host._ai_time + RESPAWN_DELAY_SEC)
	var survivor := host._ai.bundle_for(not _ride_dead_is_p1)
	survivor.ghost_mode = AIState.GHOST_MODE_NONE
	survivor.dodge_until = -1.0
	_last_ride_end = host._linger_time
	_last_phase = Phase.INACTIVE
	_dodge_at = -1.0
	_retire_requested = false
	brain.reset()


func _update_hidden_sharks() -> void:
	for i in range(_hidden_sharks.size() - 1, -1, -1):
		var shark := _hidden_sharks[i]
		if not is_instance_valid(shark):
			_hidden_sharks.remove_at(i)
			continue
		# 潜りきったか、次のライドでまた乗られた（そのときは本編の演出が見え方を決める）
		if shark.global_position.y < StageConstants.OCEAN_SURFACE_Y - 0.5 or bool(shark.get("is_ghost_ridden")):
			shark.visible = true
			_hidden_sharks.remove_at(i)


func _update_floating_riders(dt: float) -> void:
	for i in range(_floating_riders.size() - 1, -1, -1):
		var entry := _floating_riders[i]
		var rider := entry.node as Node3D
		if rider == null or not is_instance_valid(rider):
			_floating_riders.remove_at(i)
			continue
		entry.t = float(entry.t) + dt
		var k := clampf(float(entry.t) / DISMOUNT_FLOAT_SECONDS, 0.0, 1.0)
		rider.global_position = (entry.from as Vector3) + Vector3.UP * DISMOUNT_FLOAT_HEIGHT * smoothstep(0.0, 1.0, k)
		rider.scale = (entry.scale as Vector3) * maxf(0.01, 1.0 - k * k)
		if k >= 1.0:
			rider.queue_free()
			_floating_riders.remove_at(i)


## サメが待つ場所と光の柱が、メニューの UI にかからない画面右に収まる奥行きを、実際のカメラで投影して選ぶ。
func _fit_composition(survivor_is_p1: bool) -> void:
	var camera := host._preview_camera
	if camera == null or controller == null:
		return
	var size := camera.get_viewport().get_visible_rect().size
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var survivor_z := host._actor_local_z(survivor_is_p1)
	var hover_x := HOVER_SIDE * (StageConstants.FLOOR_HALF_WIDTH + HOVER_OUTSIDE_OFFSET)
	var best_depth := HOVER_DEPTH_CANDIDATES[0]
	var best_score := INF
	for depth: float in HOVER_DEPTH_CANDIDATES:
		var hover := Vector3(hover_x, StageConstants.FLOOR_TOP_Y + 3.8, survivor_z + depth)
		var beam := Vector3(hover.x + HOVER_SIDE * RENDEZVOUS_SIDE, StageConstants.FLOOR_TOP_Y + 4.0, hover.z + RENDEZVOUS_DEPTH)
		var score := _screen_miss(camera, size, hover) + _screen_miss(camera, size, beam)
		if score < best_score - 0.0001:
			best_score = score
			best_depth = depth
		if score <= 0.0:
			break
	controller.hover_depth_offset = best_depth


## 点が SCREEN_SAFE_RECT の外にはみ出している量（画面の幅・高さを 1 とする）。カメラの後ろなら大きな値。
func _screen_miss(camera: Camera3D, size: Vector2, point: Vector3) -> float:
	if camera.is_position_behind(point):
		return 10.0
	var p := camera.unproject_position(point) / size
	var rect := SCREEN_SAFE_RECT
	var dx := maxf(0.0, rect.position.x - p.x) + maxf(0.0, p.x - rect.end.x)
	var dy := maxf(0.0, rect.position.y - p.y) + maxf(0.0, p.y - rect.end.y)
	return dx + dy


## 本編のサメの透過判定（GhostSharkRideController._update_problem_wall_occlusion）が親に聞く：カメラとサメのあいだに壁の枠があるか。
func is_problem_wall_occluding_segment(segment_start: Vector3, segment_end: Vector3) -> bool:
	for wall: Node3D in host._preview_walls:
		if not is_instance_valid(wall) or not wall.is_visible_in_tree():
			continue
		if wall.has_method("is_solid_frame_occluding_segment") and bool(
			wall.call("is_solid_frame_occluding_segment", segment_start, segment_end)
		):
			return true
	return false


## 復活でメニューの PlayerController が作り直されたら、本編の制御が持つ参照を差し替える。
func on_player_controller_rebuilt(pc: PlayerController) -> void:
	if controller != null and pc != null:
		controller.rebind_player_controller(pc)


func shutdown() -> void:
	abort_all()
	if controller != null:
		controller.force_cleanup()
	for shark: Node3D in _hidden_sharks:
		if is_instance_valid(shark):
			shark.visible = true
	_hidden_sharks.clear()
