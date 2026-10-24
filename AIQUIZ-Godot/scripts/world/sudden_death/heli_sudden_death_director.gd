class_name HeliSuddenDeathDirector
extends Node3D

## 新サドンデスの演出の進行役（docs/sudden_death_v2/common.md）。DRAW の決着演出からの分岐、ヘリの迎えと
## 縄ばしごへの飛びつき、雲の覆い、空のセットでの移動、種目の舞台へ降りる、種目（見せ方は SuddenDeathPresenter）、
## 決着の後の帰還（勝者は縄ばしごでゴールへ、敗者は排水口から噴き出す）、判定からの決着演出の再生までを順に進める。
## 判定は持たない（ルールは QuizGameState.sudden_death_game）。演出の時計は実時間（止まったフレームは先へ進め、
## 一時停止の分は進めない）。テストは use_real_time = false でフレーム時間で進める。
##
## アバター：PlayerController の intro の状態（2人とも update_from_state が止まる）を使い、ヘリの縄ばしごの
## 関数（本編の登場と同じ）と StagingPuppet（UAL のクリップを当てて好きな位置に置く）で毎フレーム置く。

const Motion = preload("res://scripts/world/result_finale/result_finale_motion.gd")

enum Act { IDLE, BRANCH, REVEAL, PICKUP, CLIMB, SKY, DESCEND, VENUE, EXTRACT, HOME, ABORT, DONE, BOARD, DROP, REVIVE }

# ------------------------------------------------------------------ branch and pickup (ceremony seconds, common.md 4.2 / 5.2)
const CUT_IN_TIME := 8.6
const HELI_IN_TIME := 9.6
const HELI_APPROACH := 2.65
const HOLD_TIME := QuizGameState.SUDDEN_DEATH_HOLD_TIME
## The game reveal on the big screen (common.md 4.2): push in, the title lands (board 1.1 s), pull back.
const REVEAL_LENGTH := 3.4
const REVEAL_PUSH := 0.9
const REVEAL_PULL := 0.6
const WIDE_FOV := 54.0
## Pickup seconds (from the shout).
const RUN_START := [0.2, 0.35]
const GRAB_TIME := 0.62
const PICKUP_LIMIT := 4.6
## The rung waits beside the floor, over the sea (podium space).
const RUNG_X := 13.2
const RUNG_HEIGHT := 2.4
## Climb and cloud.
const CLIMB_CHARGE := 0.8
const CLIMB_LENGTH := 2.2
## Sky (common.md 第6章).
const SKY_ORIGIN := Vector3(0.0, 140.0, -1800.0)
const FORMATION_X := 6.0
const CRUISE_MIN := 3.0
const CRUISE_LONG := 8.0
const PREP_TIMEOUT := 25.0
## Descent onto the venue (6.1): the arrival's own beats.
const DESCEND_APPROACH := 2.6
const LOWER_TIME := 1.75
const SWING_TIME := 0.72
const SWING_DEG := 24.0
const JUMP_TIME := 1.70
const LANDED_HOLD := 0.55
const DROP_HOVER := 11.4
const P2_LAG := 0.3
## Between rounds: the landing fades to black (out, hold, in seconds) and the next shot is inside the floatplane.
const ROUND_BLACK := Vector3(0.6, 0.4, 0.6)
## The sky set's sun (the travel direction of the light): a clear late morning, 47.9° high.
const SKY_SUN_DIRECTION := Vector3(-0.533, -0.742, 0.407)
## Return (common.md 10.1).
const EXTRACT_APPROACH := 2.4
const HOME_APPROACH := 2.6
const HOME_DRAIN := 1.0
## The loser comes home as a ghost, flying in from off screen onto its sunk pad.
const GHOST_FLIGHT := 2.1
const GHOST_FROM := Vector3(16.0, 7.5, -6.0)
const HOP_TIME := 0.45
const REGROW_TIME := 1.6
const HOME_MATCH := 0.8
## Fallbacks for a stuck step.
const STEP_LIMIT := 9.0
## A ghost at the draw gets its body back before the reveal (docs/sudden_death_v2/ghost_revive.md): the second of two
## ghosts starts this much later. The lens stays on the held finale shot (no push in, no caption: user's request).
const REVIVE_LAG := 0.12
const REVIVE_HOLD := 0.12

const P1_COLOR := Color(0.95, 0.55, 0.20)
const P2_COLOR := Color(0.20, 0.65, 0.90)

var game_state: QuizGameState = null
var camera_controller: Node3D = null
var ceremony: ResultCeremonyDirector = null
var players: PlayerController = null
var stage_env: StageEnvironment = null
var _surface_toggle: Callable
## Tests can drive the clock by frame time instead of the wall clock.
var use_real_time := true
var debug_load_fail := false
var debug_load_delay := 0.0

var _act := Act.IDLE
var _act_time := 0.0
var _last_usec := 0
var _last_frame := 0
var _real_dt := 0.0
var _game_dt := 0.0
var _podium := Vector3.ZERO
var _cues := {}
var _rig: SuddenDeathHeliRig = null
var _sky: SuddenDeathSkySet = null
var _cover: SuddenDeathCloudCover = null
var _hud: SuddenDeathHud = null
var _drain: SurfaceDrain = null
var _presenter: SuddenDeathPresenter = null
var _puppets := {}
## Per player step state for the pickups, descents and the return.
var _steps := {1: {}, 2: {}}
var _winner := 0
var _loser := 0
var _prep_steps: Array[Callable] = []
var _prep_index := 0
var _prep_ready := false
var _prep_failed := false
var _prep_started_usec := 0
var _venue_env: Environment = null
var _pose := Transform3D.IDENTITY
var _pose_fov := 55.0
var _pose_ready := false
var _target_pose := Transform3D.IDENTITY
var _target_fov := 55.0
var _shot_name := ""
var _shot_log := {}
var _sky_flow := 0.0
var _events: Array[Dictionary] = []
var _emote_keys := [0, 0]
## The lens when the game reveal starts (the push to the big screen begins there).
var _reveal_from := Transform3D.IDENTITY
var _reveal_from_fov := WIDE_FOV
## The goal stand's LED face {"center", "width", "height"} for the reveal.
var _screen := {}
## The air games that ride the shared floatplane (descent_mode "floatplane", skygate_build_plan.md 4.7): boarding,
## the cabin, the drops, the pickups at the landing float and the flyby home live in FloatplaneStaging.
var _staging: FloatplaneStaging = null
var _floatplane := false
## The round the next drop starts (1 = the first drop, then the rule card).
var _round_next := 1
## After a drop hands over without a skip, the lens eases onto the game's top-down shot instead of cutting.
var _smooth_handover := false
## The live runners took over from the finale cast (once per sudden death: at the revival, otherwise at the pickup).
var _live_cast := false
## Player -> pelvis position standing on the sunk pad (taken from the cast at the handover).
var _pads := {}
## Player -> GhostRevival while a ghost's body comes back (docs/sudden_death_v2/ghost_revive.md).
var _revivals := {}
var _revive_ghosts: Array[int] = []
var _revive_from := Transform3D.IDENTITY
var _revive_from_fov := WIDE_FOV
var _revive_prewarm: Node3D = null


func setup(state: QuizGameState, camera_rig: Node3D, ceremony_director: ResultCeremonyDirector,
		player_controller: PlayerController, stage_environment: StageEnvironment, surface_toggle: Callable) -> void:
	game_state = state
	camera_controller = camera_rig
	ceremony = ceremony_director
	players = player_controller
	stage_env = stage_environment
	_surface_toggle = surface_toggle
	name = "HeliSuddenDeathDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_last_usec = Time.get_ticks_usec()


func _exit_tree() -> void:
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0


func is_active() -> bool:
	return _act != Act.IDLE and _act != Act.DONE


func act_name() -> String:
	return Act.keys()[_act]


func act_time() -> float:
	return _act_time


func shot_name() -> String:
	return _shot_name


func shot_log() -> Dictionary:
	return _shot_log


func presenter() -> SuddenDeathPresenter:
	return _presenter


func heli_rig() -> SuddenDeathHeliRig:
	return _rig


func floatplane_staging() -> FloatplaneStaging:
	return _staging


## The lens for FloatplaneStaging (the same easing as the director's own shots; cut = place it at once).
func stage_camera(pose: Transform3D, fov: float, shot: String, cut := false) -> void:
	_cut(pose, fov, shot, cut)


## Space during the boarding and the drops (c130_float.md 6, heli_drop.md 3.1).
func can_skip() -> bool:
	if _cover != null and _cover.is_playing():
		return false
	if _act == Act.VENUE:
		# The game's own shows (a round's landing, the winner's landing, a fall) say themselves when they can go.
		return _presenter != null and _presenter.has_method("can_skip") and bool(_presenter.call("can_skip"))
	if not _floatplane:
		return false
	match _act:
		Act.BOARD, Act.DROP:
			return true
		Act.SKY:
			# The cruise is also the wait for the game's preparation: it can only go once everything is ready.
			return _prep_ready and game_state.is_sudden_death_question_ready() and not _cues.has("cloud_in")
		Act.EXTRACT:
			return not _cues.has("home_cloud")
		Act.HOME:
			return _act_time > 0.5
	return false


## GameWorld forwards Space here (the "SPACE でスキップ" hint shows while can_skip(), FloatplaneStaging).
## The boarding skips to the cloud cover (both in their seats); the cruise or a drop skips to
## the game's top-down shot (a 0.3 s white flash); the winner's pickup skips to the flight home and the flight home to
## the ceremony; inside the game the presenter skips its own show.
func skip_presentation() -> bool:
	if not can_skip():
		return false
	match _act:
		Act.BOARD:
			if _cue("board_cloud", true):
				_cover.play(_enter_sky)
		Act.SKY:
			if _cue("cloud_in", true):
				game_state.sudden_death_preparing_panel = ""
				_round_next = 1
				_handover(true)
		Act.DROP:
			_handover(true)
		Act.EXTRACT:
			if _cue("home_cloud", true):
				_cover.play(_enter_home)
		Act.HOME:
			if _cue("home_skip", true):
				_cover.play(func() -> void:
					# The winner is already on its pad: the finale cast takes over from the live figures.
					for player in [1, 2]:
						(_puppets[player] as StagingPuppet).set_visible(false)
					game_state.sudden_death_live_players = false
					_release_ceremony())
		Act.VENUE:
			return bool(_presenter.call("skip_presentation")) if _presenter.has_method("skip_presentation") else false
	return true


func sky_set() -> SuddenDeathSkySet:
	return _sky


## GameWorld, every frame of the sudden death: which emote keys are held (GameWorld._emote_key_mask bits).
func set_emote_keys(p1_mask: int, p2_mask: int) -> void:
	_emote_keys = [p1_mask, p2_mask]


func emote_keys(player: int) -> int:
	return int(_emote_keys[clampi(player, 1, 2) - 1])


# ------------------------------------------------------------------ match start (under the loading cover)

## Built with the match when a draw could branch (the helicopters, the sky set, the drain column),
## so their shaders compile under the loading cover.
func prepare_for_match() -> void:
	if game_state == null or not game_state.uses_sudden_death():
		return
	# The game is drawn at the draw itself; the list decides which aircraft the match may need.
	if _rig == null and _needs_heli_rig():
		_rig = SuddenDeathHeliRig.new()
		add_child(_rig)
		_rig.build(GameManager.graphics_quality)
	if _staging == null and _needs_floatplane():
		_staging = FloatplaneStaging.new()
		add_child(_staging)
		_staging.setup(self)
		_staging.build(GameManager.graphics_quality)
	if _sky == null:
		_sky = SuddenDeathSkySet.new()
		_sky.name = "SuddenDeathSky"
		add_child(_sky)
		_sky.position = SKY_ORIGIN
		_sky.build(GameManager.graphics_quality, -SKY_SUN_DIRECTION.normalized())
		_sky.visible = false
	if _cover == null:
		_cover = SuddenDeathCloudCover.new()
		add_child(_cover)
	_ensure_drain()
	# サドンデスの効果音は試合の頭（読み込みの覆いの下）で読んでおく（演出の途中で読むとそのフレームが重くなる）
	AudioManager.preload_sfx(AudioManager.SUDDEN_DEATH_SFX_CUES)


func begin_render_prewarm(camera: Camera3D) -> Dictionary:
	prepare_for_match()
	if (_rig == null and _staging == null) or camera == null:
		return {"ready": true, "skipped": true}
	# Show the aircraft and the sky in front of the prewarm camera for a frame.
	var ahead := camera.global_position - camera.global_basis.z * 12.0
	if _rig != null:
		for player in [1, 2]:
			_rig.place(player, ahead + Vector3((player * 2 - 3) * 6.0, 0.0, 0.0), Vector3(0, 0, -1))
			(_rig.holder(player) as Node3D).visible = true
	if _staging != null and _staging.plane != null:
		_staging.plane.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), camera.global_position - camera.global_basis.z * 30.0)
		_staging.plane.visible = true
	if _sky != null:
		_sky.visible = true
	# The revival's glow (only a ghost at the draw shows it, docs/sudden_death_v2/ghost_revive.md).
	if not is_instance_valid(_revive_prewarm):
		_revive_prewarm = GhostRevival.build_prewarm(self, Transform3D(camera.global_basis, ahead))
	return {"ready": true}


func end_render_prewarm() -> void:
	if is_instance_valid(_revive_prewarm):
		_revive_prewarm.queue_free()
	_revive_prewarm = null
	if _rig != null:
		for player in [1, 2]:
			(_rig.holder(player) as Node3D).visible = false
	if _staging != null and _staging.plane != null:
		_staging.plane.visible = false
	if _sky != null:
		_sky.visible = false


## The helicopters only serve the games that still use them (not the floatplane games).
func _needs_heli_rig() -> bool:
	for kind: String in QuizGameState.SUDDEN_DEATH_GAMES:
		if kind != "sky_gate":
			return true
	return game_state != null and not game_state.sudden_death_kind.is_empty() and game_state.sudden_death_kind != "sky_gate"


func _needs_floatplane() -> bool:
	return QuizGameState.SUDDEN_DEATH_GAMES.has("sky_gate") or (game_state != null and game_state.sudden_death_kind == "sky_gate")


func _ensure_drain() -> void:
	if is_instance_valid(_drain):
		return
	_drain = SurfaceDrain.new()
	_drain.name = "SurfaceDrain"
	add_child(_drain)
	_drain.setup(GameManager.graphics_quality)


# ------------------------------------------------------------------ frame

## GameWorld calls this every frame, before the players, the finale stage and the camera.
func process_frame(delta: float) -> void:
	if game_state == null:
		return
	_game_dt = delta
	_real_dt = _real_delta(delta)
	if not use_real_time:
		# Frame-time tests: the HUD animations follow the same clock as the shots.
		if is_instance_valid(_hud):
			_hud.debug_manual_clock = true
			_hud.debug_step(_real_dt)
		if _presenter != null:
			_presenter.debug_step_clock(_real_dt)
	if _cover != null:
		_cover.advance(_real_dt)
	_act_time += _real_dt
	match _act:
		Act.IDLE:
			if game_state.sudden_death_pending and game_state.result_presentation_active:
				_begin_branch()
		Act.BRANCH:
			_update_branch()
		Act.REVEAL:
			_update_reveal()
		Act.REVIVE:
			_update_revive()
		Act.PICKUP:
			_update_pickup()
		Act.CLIMB:
			_update_climb()
		Act.SKY:
			_update_sky()
		Act.DESCEND:
			_update_descend()
		Act.VENUE:
			_update_venue()
		Act.EXTRACT:
			_update_extract()
		Act.HOME:
			_update_home()
		Act.ABORT:
			_update_abort()
		Act.BOARD:
			_update_board()
		Act.DROP:
			_update_sky_drop()
		Act.DONE:
			pass
	_step_preparation()
	_apply_camera()
	if _act == Act.DONE and not game_state.result_presentation_active and game_state.game_state != Constants.STATE_SUDDEN_DEATH:
		reset()
	if _act != Act.IDLE and game_state.game_state == Constants.STATE_MENU:
		reset()


func _real_delta(delta: float) -> float:
	var now := Time.get_ticks_usec()
	var frame := Engine.get_process_frames()
	var frame_dt := delta / maxf(Engine.time_scale, 0.01)
	var resumed := frame - _last_frame > 1
	_last_frame = frame
	if not use_real_time or _last_usec == 0 or resumed:
		_last_usec = now
		return frame_dt
	var real := float(now - _last_usec) / 1000000.0
	_last_usec = now
	return clampf(real, 0.0, 5.0)


func on_event(event: Dictionary) -> void:
	_events.append(event)
	if _presenter != null and _act == Act.VENUE:
		_presenter.on_event(event)


## sudden_death_transition_requested: true when the finale reaches the hold (11.0 s).
func on_transition_requested(entering: bool) -> void:
	if entering and _act == Act.BRANCH:
		if _ghosts_at_draw().is_empty():
			_begin_reveal()
		else:
			_begin_revive()


## Enter on the rule card (GameWorld forwards it).
func confirm_rules() -> bool:
	if _act == Act.VENUE and _presenter != null:
		return _presenter.confirm_rules()
	return false


## Pause / focus loss while the game runs: the game's rules decide what to redo (SuddenDeathGame.interrupt).
func on_interrupted() -> void:
	if game_state != null and _act == Act.VENUE:
		game_state.interrupt_sudden_death()


func reset() -> void:
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	if _presenter != null:
		_presenter.teardown()
		_presenter.queue_free()
		_presenter = null
	_clear_revivals()
	_live_cast = false
	_pads.clear()
	if _rig != null:
		_rig.hide_all()
	if _staging != null:
		_staging.hide_all()
	if _sky != null:
		_sky.visible = false
	if _hud != null:
		_hud.hide_all(true)
	_restore_environment()
	_floatplane = false
	_smooth_handover = false
	_round_next = 1
	if camera_controller != null and camera_controller.has_method("clear_director_pose"):
		camera_controller.clear_director_pose()
	if game_state != null:
		game_state.sudden_death_live_players = false
		game_state.sudden_death_preparing_panel = ""
	_act = Act.IDLE
	_act_time = 0.0
	_cues.clear()
	_steps = {1: {}, 2: {}}
	_pose_ready = false
	_prep_steps.clear()
	_prep_ready = false
	_prep_failed = false


# ------------------------------------------------------------------ branch (4.2)

func _begin_branch() -> void:
	_act = Act.BRANCH
	_act_time = 0.0
	_cues.clear()
	_events.clear()
	_shot_log.clear()
	_podium = ResultCeremonyDirector.podium_center(game_state)
	_winner = 0
	_loser = 0
	_clear_revivals()
	_live_cast = false
	_pads.clear()
	prepare_for_match()
	_ensure_hud()
	_puppets = {1: StagingPuppet.new(players, 1), 2: StagingPuppet.new(players, 2)}
	# The venue starts loading now (one build step a frame; heavy steps wait for dark shots).
	_presenter = _create_presenter(game_state.sudden_death_kind)
	add_child(_presenter)
	_presenter.setup(self)
	_floatplane = _presenter.descent_mode() == "floatplane"
	_round_next = 1
	_smooth_handover = false
	if _floatplane and _staging == null:
		prepare_for_match()
	_prep_steps = _presenter.preparation_steps()
	_prep_index = 0
	_prep_ready = false
	# Without a game for the kind, the preparation fails and the draw comes back (like a load failure).
	_prep_failed = debug_load_fail or not QuizGameState.has_sudden_death_game(game_state.sudden_death_kind)
	_prep_started_usec = Time.get_ticks_usec()


## The presenter of each game (QuizGameState.SUDDEN_DEATH_GAMES). An unknown kind gets the base one, which only fails the preparation.
func _create_presenter(kind: String) -> SuddenDeathPresenter:
	if kind == "sky_gate":
		return SkyGatePresenter.new()
	if kind == "parachute":
		return ParachutePresenter.new()
	push_warning("[SuddenDeath] No presenter for '%s'." % kind)
	return SuddenDeathPresenter.new()


func _update_branch() -> void:
	var elapsed := game_state.result_ceremony_elapsed
	if not game_state.sudden_death_pending:
		reset()
		return
	# 8.4 秒：審判の笛（両者が踊りをやめて振り向く）。8.6 秒：「SUDDEN DEATH!」と回転灯の警報。9.0 秒：両方のタワーが床まで沈む
	if _cue("whistle", elapsed >= QuizGameState.SUDDEN_DEATH_BRANCH_TIME):
		AudioManager.play_sfx(&"sd_whistle")
	if _cue("cut_in", elapsed >= CUT_IN_TIME):
		_hud_call("flash", [0.9, 0.22])
		AudioManager.play_sfx(&"sd_siren")
		# 判定（6.9 秒）からの結果の曲を、サドンデスの導入曲に替える（docs/bgm_renewal.md）。本戦の GO まで流れる
		AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_SUDDEN_DEATH)
		AudioManager.set_music_track(AudioManager.MUSIC_TRACK_SUDDEN_DEATH_INTRO)
	if _cue("towers_sink", elapsed >= QuizGameState.SUDDEN_DEATH_SINK_TIME):
		AudioManager.play_sfx(&"sd_tower_move", 0.0, 0.85)
	if _floatplane:
		# The stand beside the podium swaps to its sea-cropped copy while the camera is on the finale (looks the same).
		if elapsed >= HELI_IN_TIME and _staging != null and _cue("gate_ready", true):
			_staging.prepare_gate(stage_env, _podium)
	elif elapsed >= HELI_IN_TIME:
		_update_arriving_helis(elapsed - HELI_IN_TIME)
	# No wide shot of the helicopters before the big screen (2026-10-18, user's request): the finale camera
	# stays until 11.0 s and the reveal pushes in on the screen straight from it.


## The podium, both hovering aircraft with their ladders and the goal stand behind, in one frame.
func _wide_shot() -> Transform3D:
	return _look(_podium + Vector3(0.0, 8.5, -29.0), _podium + Vector3(0.0, 5.6, 4.0))


## Both aircraft come in from the near sky over the sea at the sides and hover beside the floor.
func _update_arriving_helis(t: float) -> void:
	for player in [1, 2]:
		var hover := _pickup_hover(player)
		var from := hover + Vector3(_side(player) * 6.0, 9.0, -34.0)
		var u := clampf(t / HELI_APPROACH, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - u, 3.0)
		var position := from.lerp(hover, eased) + Vector3(0.0, sin(t * 1.3 + player) * 0.12 * u, 0.0)
		if not (_rig.holder(player) as Node3D).visible:
			_rig.place(player, from, Vector3(-_side(player), 0.0, 0.0))
			_rig.set_shown(player, true)
		_rig.set_motion(player, position, Vector3(-_side(player), 0.0, 0.0), maxf(_real_dt, 0.0001))
		var ladder := _rig.ensure_ladder(player, "pickup")
		if ladder != null:
			ladder.set_winch_progress(0.0)
			ladder.set_deploy_progress(clampf((t - (HELI_APPROACH - 1.0)) / 1.2, 0.0, 1.0))


## Holder position over the sea beside the floor, so the bottom rung waits at jump height.
func _pickup_hover(player: int) -> Vector3:
	var rung := _podium + Vector3(_side(player) * RUNG_X, RUNG_HEIGHT, 0.0)
	return _rig.holder_for_rung(rung)


# ------------------------------------------------------------------ reveal (11.0-12.6)

## The game is announced on the goal stand's big screen, not over the picture: the camera pushes in on the
## screen, the board spins "???" and slams the title, then the camera pulls back for the pickup.
func _begin_reveal() -> void:
	_act = Act.REVEAL
	_act_time = 0.0
	game_state.sudden_death_title = _presenter.title(game_state.use_english_ui)
	_screen = _find_screen()
	# The push starts from the lens as it is now (the finale camera; there is no wide shot before the screen).
	# Starting from a computed shot instead made the camera jump back toward the helicopters for a frame.
	var camera := main_camera()
	if _pose_ready:
		_reveal_from = _pose
		_reveal_from_fov = _pose_fov
	elif camera != null:
		_reveal_from = camera.global_transform
		_reveal_from_fov = camera.fov
	else:
		var finale := _finale_camera(HOLD_TIME)
		_reveal_from = finale.transform
		_reveal_from_fov = float(finale.fov)
	AudioManager.play_sfx(&"score_drum_roll", -4.0)


func _update_reveal() -> void:
	var t := HOLD_TIME + _act_time
	if _live_cast:
		# Revived before the reveal: the live runners wait on their pads instead of the finale cast.
		for player in [1, 2]:
			_stand_idle(player, PI)
	var wide := _wide_shot()
	if _floatplane:
		# Pull back to the boarding's first shot (the stand beside the podium and the open sea).
		wide = _look(Vector3(-7.0, 7.0, _podium.z - 27.2), Vector3(26.0, 2.0, _podium.z + 4.8))
	else:
		_update_arriving_helis(t - HELI_IN_TIME)
	var close := _screen_shot()
	var push := smoothstep(0.0, REVEAL_PUSH, _act_time)
	var pull := smoothstep(REVEAL_LENGTH - REVEAL_PULL, REVEAL_LENGTH, _act_time)
	# Ease in a little steeper than the follow so the board fills the frame while the title lands.
	# In: from the lens as it was at 11.0 s. Out: back to the wide shot for the pickup.
	var shot := _blend(_reveal_from, close.transform, push)
	var fov := lerpf(_reveal_from_fov, float(close.fov), push)
	if pull > 0.0:
		shot = _blend(close.transform, wide, pull)
		fov = lerpf(float(close.fov), WIDE_FOV, pull)
	_cut(shot, fov, "reveal_screen", true)
	if _act_time >= GoalStandScoreboard.TITLE_SPIN and _cue("title_land", true):
		AudioManager.stop_sfx(&"score_drum_roll")
		AudioManager.play_sfx(&"score_drum_finish", -2.0)
		_hud_call("flash", [0.35, 0.18])
	if _act_time >= REVEAL_LENGTH:
		if _floatplane:
			_begin_board()
		else:
			_begin_pickup()


## The LED face filling most of the frame, straight on from the course side.
func _screen_shot() -> Dictionary:
	if _screen.is_empty():
		return {"transform": _wide_shot(), "fov": WIDE_FOV}
	var center: Vector3 = _screen.center
	var toward := Vector3(_podium.x - center.x, 0.0, _podium.z - center.z).normalized()
	var fov := 40.0
	var aspect := 16.0 / 9.0
	var half_width := tan(deg_to_rad(fov) * 0.5) * aspect
	var distance := float(_screen.width) / 0.86 / (2.0 * half_width)
	var eye := center + toward * distance + Vector3(0.0, -0.35, 0.0)
	return {"transform": _look(eye, center), "fov": fov}


func _find_screen() -> Dictionary:
	var parent := get_parent()
	if parent == null:
		return {}
	for child: Node in parent.get_children():
		if child is GoalStand:
			return (child as GoalStand).screen_frame()
	return {}


# ------------------------------------------------------------------ pickup (5.2)

func _begin_pickup() -> void:
	_act = Act.PICKUP
	_act_time = 0.0
	# The floatplane boarding shows no "乗りこめー！" caption (user's request, c130_float.md 12).
	if not _floatplane:
		_hud_call("show_shout", ["ALL ABOARD!" if game_state.use_english_ui else "乗りこめー！"])
	var already_live := _live_cast
	_take_over_cast(0.35)
	for player in [1, 2]:
		var puppet := _puppets[player] as StagingPuppet
		if already_live:
			# From the idle on the pad after a revival: ease into the boarding's own stand.
			puppet.begin_blend(0.35)
		var pelvis := puppet.parts().get("pelvis") as Node3D
		_steps[player] = {"phase": "turn", "t": 0.0, "pad": pelvis.global_position if pelvis != null else _podium,
			"ground_y": StageConstants.FLOOR_TOP_Y}


## The finale cast hands over to the live runners, pose for pose (common.md 5.2). Once per sudden death: before the
## reveal when a ghost gets its body back (docs/sudden_death_v2/ghost_revive.md), at the pickup otherwise.
func _take_over_cast(blend: float) -> void:
	if _live_cast:
		return
	_live_cast = true
	var cast := _capture_cast_pose()
	game_state.sudden_death_live_players = true
	var stage := ceremony.stage() if ceremony != null else null
	for player in [1, 2]:
		_lock_avatar(player)
		var puppet := _puppets[player] as StagingPuppet
		puppet.set_visible(true)
		var parts := puppet.parts()
		if cast.has(player):
			for key: Variant in cast[player]:
				var node := parts.get(key) as Node3D
				if node != null:
					node.global_transform = cast[player][key]
		puppet.begin_blend(blend)
		if stage != null:
			stage.set_actor_flight(player, Vector3.ZERO, -1.0)
		var pelvis := parts.get("pelvis") as Node3D
		_pads[player] = pelvis.global_position if pelvis != null else _podium + Vector3(_side(player) * QuizGameState.SUDDEN_DEATH_START_X, GhostRevival.HIPS, 0.0)


## A live runner idling on its sunk pad (the reveal after a revival).
func _stand_idle(player: int, yaw: float) -> void:
	var puppet := _puppets.get(player) as StagingPuppet
	if puppet == null or not puppet.is_ready():
		return
	var pad: Vector3 = _pads.get(player, _podium)
	var length := maxf(puppet.clip_length("Idle_Loop"), 0.1)
	puppet.pose("Idle_Loop", fposmod((HOLD_TIME + _act_time) / length + 0.31 * float(player), 1.0))
	puppet.stand_at(pad, yaw, pad.y - GhostRevival.HIPS)
	puppet.apply_blend(_real_dt)


# ------------------------------------------------------------------ revival (docs/sudden_death_v2/ghost_revive.md)

## Finalists who stand on the podium as ghosts when the draw branches.
func _ghosts_at_draw() -> Array[int]:
	var out: Array[int] = []
	if game_state == null:
		return out
	for player in [1, 2]:
		if game_state.is_result_ghost(player) and not game_state.is_sudden_death_revived(player):
			out.append(player)
	return out


## The held draw (11.0 s): the live runners take over from the cast, and each ghost floats up and calls its body back
## from off screen, part by part, then bursts into a hero landing. The lens holds the finale shot; the reveal pushes
## in from it as before.
func _begin_revive() -> void:
	_act = Act.REVIVE
	_act_time = 0.0
	_revive_ghosts = _ghosts_at_draw()
	var camera := main_camera()
	if _pose_ready:
		_revive_from = _pose
		_revive_from_fov = _pose_fov
	elif camera != null:
		_revive_from = camera.global_transform
		_revive_from_fov = camera.fov
	else:
		var finale := _finale_camera(HOLD_TIME)
		_revive_from = finale.transform
		_revive_from_fov = float(finale.fov)
	_take_over_cast(0.55)
	for index in range(_revive_ghosts.size()):
		var player: int = _revive_ghosts[index]
		var revival := GhostRevival.new()
		add_child(revival)
		revival.setup(players, _puppets[player] as StagingPuppet, player, _pads.get(player, _podium) as Vector3,
			REVIVE_LAG * float(index), _revive_from, _revive_from_fov, camera)
		_revivals[player] = revival
	_cut(_revive_from, _revive_from_fov, "revive", true)


func _update_revive() -> void:
	if not game_state.sudden_death_pending:
		reset()
		return
	var t := _act_time
	var done := true
	for player in [1, 2]:
		var revival := _revivals.get(player) as GhostRevival
		if revival == null:
			_pose_watcher(player, t)
			continue
		revival.advance(_real_dt)
		for beat: StringName in revival.take_beats():
			_on_revival_beat(player, beat)
		done = done and revival.is_done()
	_cut(_revive_from, _revive_from_fov, "revive", true)
	if done and t >= _revive_length() + REVIVE_HOLD:
		_clear_revivals()
		for player in [1, 2]:
			(_puppets[player] as StagingPuppet).begin_blend(0.3)
		_begin_reveal()


func _revive_length() -> float:
	return GhostRevival.LENGTH + REVIVE_LAG * float(maxi(_revive_ghosts.size() - 1, 0))


## The living finalist on the other pad turns to watch the body come back, then faces front again.
func _pose_watcher(player: int, t: float) -> void:
	var puppet := _puppets.get(player) as StagingPuppet
	if puppet == null or not puppet.is_ready():
		return
	var pad: Vector3 = _pads.get(player, _podium)
	var other: Vector3 = _pads.get(3 - player, _podium)
	var look := atan2(other.x - pad.x, other.z - pad.z)
	var watch := smoothstep(0.15, 0.7, t) * (1.0 - smoothstep(_revive_length() - 0.6, _revive_length(), t))
	var yaw := lerp_angle(PI, look, 0.62 * watch)
	var length := maxf(puppet.clip_length("Idle_Loop"), 0.1)
	puppet.pose("Idle_Loop", fposmod((HOLD_TIME + t) / length + 0.31 * float(player), 1.0))
	puppet.stand_at(pad, yaw, pad.y - GhostRevival.HIPS)
	puppet.apply_blend(_real_dt)


func _on_revival_beat(player: int, beat: StringName) -> void:
	match beat:
		&"burst":
			# The body is back: the finale cast stops wearing the ghost look (ResultFinaleStage.wants_ghost_look).
			# No caption on screen (user's request); the light, the sound and a small shake carry it.
			game_state.mark_sudden_death_revived(player)
			_hud_call("flash", [0.22, 0.14])
			game_state.camera_shake = maxf(game_state.camera_shake, 0.14)
		&"land":
			game_state.camera_shake = maxf(game_state.camera_shake, 0.18)


func _clear_revivals() -> void:
	for revival: Variant in _revivals.values():
		if is_instance_valid(revival):
			(revival as GhostRevival).teardown()
	_revivals.clear()


func revival(player := 0) -> GhostRevival:
	if player == 0:
		for value: Variant in _revivals.values():
			if is_instance_valid(value):
				return value as GhostRevival
		return null
	return _revivals.get(player) as GhostRevival


func _update_pickup() -> void:
	var t := _act_time
	_update_arriving_helis(HOLD_TIME + REVEAL_LENGTH + t - HELI_IN_TIME)
	var captured := 0
	for player in [1, 2]:
		if _update_pickup_runner(player, t, _podium + Vector3(_side(player) * RUNG_X, 0.0, 0.0), RUN_START[player - 1]):
			captured += 1
	# Low and back: both runs to the floor edge, the leaps and the aircraft with their ladders.
	_cut(_look(_podium + Vector3(0.0, 2.6, -22.0), _podium + Vector3(0.0, 4.6, 2.0)), 64.0, "pickup_run")
	if captured == 2 or t >= PICKUP_LIMIT:
		_begin_climb()


## One runner: turn out, step off the pad, run to the floor edge and jump onto the rung. True once hanging.
func _update_pickup_runner(player: int, t: float, rung_ground: Vector3, run_start: float) -> bool:
	var step: Dictionary = _steps[player]
	var puppet := _puppets[player] as StagingPuppet
	var ladder := _rig.ladder(player)
	match str(step.get("phase", "")):
		"turn":
			var outward := atan2(_side(player), 0.0)
			var pad: Vector3 = step.pad
			puppet.pose("Idle_Loop", fposmod(t / maxf(puppet.clip_length("Idle_Loop"), 0.1), 1.0))
			puppet.stand_at(pad, lerp_angle(PI, outward, smoothstep(0.0, run_start, t)), pad.y - 0.95)
			puppet.apply_blend(_real_dt)
			if t >= run_start and ladder != null and ladder.is_ready_for_ground_pickup():
				step.phase = "run"
				step.t = 0.0
		"run":
			step.t = float(step.t) + _real_dt
			# The sunk pad is only a few centimetres up: the run keeps that height.
			if players.update_intro_pickup_approach(player, rung_ground, _real_dt):
				players.begin_intro_ladder_grab(player, GRAB_TIME)
				step.phase = "grab"
				step.t = 0.0
		"grab":
			step.t = float(step.t) + _real_dt
			var progress := clampf(float(step.t) / GRAB_TIME, 0.0, 1.0)
			players.update_intro_ladder_grab(player, _rig.grip(player, Vector3(-_side(player), 0.0, 0.0), false), progress, _real_dt)
			if progress >= 1.0:
				if ladder != null:
					ladder.set_payload_active(true)
				step.phase = "hang"
				_audio_grip(player)
		"hang":
			players.update_intro_ladder_grab(player, _rig.grip(player, Vector3(-_side(player), 0.0, 0.0), false), 1.0, _real_dt)
			return true
	return false


# ------------------------------------------------------------------ floatplane boarding (c130_float.md 6)

## The finale cast hands over to the live runners as for the pickup; FloatplaneStaging plays the stand lifting,
## the floatplane backing into the channel and the run aboard, then the take-off into the cloud cover.
func _begin_board() -> void:
	_begin_pickup()
	_act = Act.BOARD
	_act_time = 0.0
	_staging.begin_board(_podium)


func _update_board() -> void:
	var state := _staging.update_board(_real_dt)
	# The floatplane climbs into a real cloud deck; once it is deep inside, a blackout covers the swap from the surface
	# to the sky set (c130_float.md 12: the climb would otherwise come out very high with no break). "cover" is only
	# the time-out fallback.
	if state == "swap" and _cue("board_cloud", true):
		_cover.play_black(_enter_sky)
	elif state == "cover" and _cue("board_cloud", true):
		_cover.play(_enter_sky)


# ------------------------------------------------------------------ floatplane drops and the pickup between rounds

## The drop from the floatplane's ramp (heli_drop.md 3.1). The first one opens the game; a short one starts each later round.
func _begin_sky_drop(short: bool) -> void:
	_act = Act.DROP
	_act_time = 0.0
	game_state.sudden_death_preparing_panel = ""
	var spawns := {}
	for player in [1, 2]:
		spawns[player] = _presenter.sky_spawn(player)
	_staging.begin_drop(short, spawns)


func _update_sky_drop() -> void:
	_sky.advance(SuddenDeathSkySet.FLOW_SPEED * _real_dt)
	if _staging.update_drop(_real_dt) == "handover":
		_handover(false)


## The drop hands over to the game: the live runners hide and the game's figures take the same places in the air
## (presenter.sky_spawn). The first drop opens on the rule card; later ones start the next round. Space gets here
## at once with a white flash and a cut to the game's top-down shot.
func _handover(skipped: bool) -> void:
	_staging.end_drop(skipped)
	for player in [1, 2]:
		_steps[player] = {}
	_act = Act.VENUE
	_act_time = 0.0
	_presenter.set_venue_active(true)
	if _round_next <= 1:
		_presenter.begin_venue()
	else:
		_presenter.begin_round(_round_next)
	_presenter.update_venue(0.0)
	_smooth_handover = not skipped
	if skipped:
		_hud_call("flash", [0.8, 0.3])
		var camera := _presenter.venue_camera()
		if not camera.is_empty():
			_cut(camera.transform, float(camera.get("fov", 55.0)), str(camera.get("shot", "venue")), true)


## Both reached the landing float (presenter.round_cleared): no pickup by the floatplane between rounds (2026-10-20,
## the user's call). The landing fades to black and the next shot opens inside the floatplane for the short drop.
func _begin_round_blackout() -> void:
	var rules := game_state.sudden_death_game as SkyGateGame
	_round_next = (rules.current_round + 1) if rules != null else _round_next + 1
	_presenter.hide_banner(ROUND_BLACK.x)
	_cover.play_black(_enter_short_drop, ROUND_BLACK.x, ROUND_BLACK.y, ROUND_BLACK.z, false)


func _enter_short_drop() -> void:
	_presenter.set_venue_active(false)
	_staging.enter_short_drop(_presenter.fall_center())
	_begin_sky_drop(true)


# ------------------------------------------------------------------ climb and cloud

func _begin_climb() -> void:
	_act = Act.CLIMB
	_act_time = 0.0
	for player in [1, 2]:
		_steps[player]["climb_from"] = (_rig.holder(player) as Node3D).global_position


func _update_climb() -> void:
	var t := _act_time
	for player in [1, 2]:
		var from: Vector3 = _steps[player].get("climb_from", _pickup_hover(player))
		var charge := clampf(t / CLIMB_CHARGE, 0.0, 1.0)
		var aircraft := _rig.heli(player)
		if aircraft != null and aircraft.has_jets():
			aircraft.set_jet_charge(charge)
			if t >= CLIMB_CHARGE and _cue("ignite_%d" % player, true):
				aircraft.ignite_jets(false)
		var s := maxf(0.0, t - CLIMB_CHARGE * 0.5)
		var position := from + Vector3(_side(player) * 1.5 * s, 3.0 * s + 3.2 * s * s, 4.0 * s * s)
		_rig.set_motion(player, position, Vector3(0.0, 0.0, 1.0), maxf(_real_dt, 0.0001))
		# Still hanging below the aircraft.
		var step: Dictionary = _steps[player]
		if str(step.get("phase", "")) in ["hang", "grab"]:
			_update_pickup_runner(player, 0.0, Vector3.ZERO, 0.0)
	var mid := ((_rig.holder(1) as Node3D).global_position + (_rig.holder(2) as Node3D).global_position) * 0.5
	_cut(_look(_podium + Vector3(0.0, 0.9, -7.5), mid + Vector3(0.0, -4.0, 0.0)), 60.0, "climb_up")
	if t >= CLIMB_LENGTH and _cue("cloud_out", true):
		_cover.play(_enter_sky)


## Under the cloud cover: the surface goes away, the sky set comes in, both ride in their seats.
func _enter_sky() -> void:
	if not game_state.begin_sudden_death():
		_abort_to_surface()
		return
	players.cancel_intro_drops()
	if _surface_toggle.is_valid():
		_surface_toggle.call(false)
	_set_environment(_presenter.environment())
	_presenter.set_sun(true)
	_sky.visible = true
	_sky_flow = 0.0
	if _floatplane:
		# Both ride the floatplane's cabin; the channel by the podium closes under the cover.
		for player in [1, 2]:
			_lock_avatar(player)
		_staging.enter_cruise(_presenter.fall_center())
	else:
		for player in [1, 2]:
			_rig.remove_ladder(player)
			var aircraft := _rig.heli(player)
			if aircraft != null:
				aircraft.extinguish_jets(true)
				aircraft.stow_jets()
			_rig.place(player, _formation_position(player, 0.0), Vector3(0, 0, -1))
			_lock_avatar(player)
	_act = Act.SKY
	_act_time = 0.0
	game_state.sudden_death_preparing_panel = ""


func _formation_position(player: int, time: float) -> Vector3:
	var sway := StagingFlight.cruise_sway(time, 0.0 if player == 1 else 0.7)
	return SKY_ORIGIN + Vector3(FORMATION_X * _side(player), 0.0, 0.0) + sway.origin


func _update_sky() -> void:
	var t := _act_time
	_sky.advance(SuddenDeathSkySet.FLOW_SPEED * _real_dt)
	if _floatplane:
		_staging.update_cruise(_real_dt)
	else:
		for player in [1, 2]:
			_rig.set_motion(player, _formation_position(player, t), Vector3(0, 0, -1), maxf(_real_dt, 0.0001))
			var puppet := _puppets[player] as StagingPuppet
			var length := maxf(puppet.clip_length("Driving_Loop"), 0.1)
			puppet.pose("Driving_Loop", fposmod(t / length, 1.0))
			puppet.sit_at(_rig.seat_transform(player))
			var aircraft := _rig.heli(player)
			if aircraft != null:
				aircraft.set_door("L", 0.0)
				aircraft.set_belt("L", 1.0)
		_sky_camera(t)
	var questions_ready := game_state.is_sudden_death_question_ready()
	if not questions_ready:
		game_state.sudden_death_preparing_panel = "questions"
	elif not _prep_ready and t > CRUISE_MIN:
		game_state.sudden_death_preparing_panel = "stage"
	else:
		game_state.sudden_death_preparing_panel = ""
	var prep_seconds := float(Time.get_ticks_usec() - _prep_started_usec) / 1000000.0
	if _prep_failed or (not _prep_ready and prep_seconds > PREP_TIMEOUT + debug_load_delay and use_real_time):
		if _cue("abort_cloud", true):
			game_state.sudden_death_preparing_panel = ""
			_cover.play(_abort_to_surface)
		return
	# The floatplane's lens first flies in through the cockpit window (FloatplaneStaging.cruise_ready).
	var lens_ready := not _floatplane or _staging.cruise_ready()
	if t >= CRUISE_MIN and _prep_ready and questions_ready and lens_ready and _cue("cloud_in", true):
		game_state.sudden_death_preparing_panel = ""
		if _floatplane:
			_round_next = 1
			_begin_sky_drop(false)
		elif _presenter.descent_mode() == "skydive":
			_enter_skydive()
		else:
			_cover.play(_enter_venue)


## Formation from the front (P1 left), drifting; long waits look straight down past the skids.
func _sky_camera(t: float) -> void:
	var drift := Vector3(sin(t * 0.21) * 1.2, sin(t * 0.17) * 0.5, 0.0)
	var eye := SKY_ORIGIN + Vector3(0.0, 1.8, -27.0) + drift
	var aim := SKY_ORIGIN + Vector3(0.0, 0.9, 0.0)
	if t > CRUISE_LONG:
		var u := smoothstep(CRUISE_LONG, CRUISE_LONG + 2.0, t)
		eye = eye.lerp(SKY_ORIGIN + Vector3(10.0, 6.0, -8.0), u)
	_cut(_look(eye, aim), 34.0, "sky_formation")


## An air game (descent_mode "skydive", parachute.md 第10章): no cloud cover and no ladder. The sky set stays
## and the presenter takes over the aircraft, the seated runners and the lens from the cruise as it is.
func _enter_skydive() -> void:
	for player in [1, 2]:
		_steps[player] = {}
	_act = Act.VENUE
	_act_time = 0.0
	_presenter.begin_venue()


# ------------------------------------------------------------------ descend onto the venue (6.1)

func _enter_venue() -> void:
	_sky.visible = false
	_presenter.set_venue_active(true)
	_set_environment(_presenter.environment())
	for player in [1, 2]:
		var drop := _presenter.drop_point(player)
		var hover := drop + Vector3(0.0, DROP_HOVER, 0.0)
		var from := hover + _presenter.approach_offset(player)
		_rig.place(player, from, hover - from)
		_rig.set_shown(player, true)
		_steps[player] = {"phase": "approach", "t": -P2_LAG * float(player - 1), "drop": drop, "hover": hover, "from": from}
		var aircraft := _rig.heli(player)
		if aircraft != null:
			aircraft.set_belt("L", 0.0)
		players.begin_intro_cabin_ride(player, _rig.cabin_wait_transform(player))
	_act = Act.DESCEND
	_act_time = 0.0


func _update_descend() -> void:
	var landed := 0
	for player in [1, 2]:
		if _update_drop(player, _presenter.table_direction(player)):
			landed += 1
	_set_camera_from(_presenter.descent_camera(_act_time), "venue_descend")
	if landed == 2 or _act_time > 14.0:
		for player in [1, 2]:
			players.complete_intro_ladder_landing(player, game_state)
		players.cancel_intro_drops()
		for player in [1, 2]:
			_lock_avatar(player)
		_act = Act.VENUE
		_act_time = 0.0
		_presenter.begin_venue()


## The arrival's drop for one runner: approach (seated over the hatch), lowering, swing, jump, landing.
## Then the aircraft leaves. True once landed and settled.
func _update_drop(player: int, inward: Vector3) -> bool:
	var step: Dictionary = _steps[player]
	step.t = float(step.t) + _real_dt
	var t := float(step.t)
	var hover: Vector3 = step.hover
	var from: Vector3 = step.from
	var ladder := _rig.ladder(player)
	match str(step.phase):
		"approach":
			var u := clampf(t / DESCEND_APPROACH, 0.0, 1.0)
			_rig.set_motion(player, from.lerp(hover, 1.0 - pow(1.0 - u, 3.0)), hover - from, maxf(_real_dt, 0.0001))
			players.update_intro_cabin_ride(player, _rig.cabin_wait_transform(player), t > -0.2)
			if u >= 1.0:
				_rig.ensure_ladder(player, "drop")
				players.begin_intro_ladder_hang(player)
				step.phase = "lower"
				step.t = 0.0
		"lower":
			_rig.set_motion(player, hover + Vector3(0.0, sin(t * 1.4) * 0.08, 0.0), Vector3.ZERO, maxf(_real_dt, 0.0001))
			var reach := t / LOWER_TIME
			if ladder != null:
				ladder.set_deploy_progress(maxf(0.04, reach))
			players.update_intro_ladder_hang(player, _rig.grip(player, inward, true), reach, 0.0, _real_dt)
			if reach >= 1.0 and (ladder == null or ladder.is_fully_deployed() or t > LOWER_TIME + 1.0):
				if ladder != null:
					ladder.set_payload_active(true)
				step.phase = "swing"
				step.t = 0.0
		"swing":
			_rig.set_motion(player, hover, Vector3.ZERO, maxf(_real_dt, 0.0001))
			var angle := deg_to_rad(SWING_DEG) * smoothstep(0.0, 0.18, t) * sin(t * TAU * 0.125)
			players.update_intro_ladder_hang(player, _rig.grip(player, inward, true), 1.0, angle, _real_dt)
			if t >= SWING_TIME:
				var grab := players.get_intro_ladder_grab_state(player)
				var origin: Vector3 = grab.get("character_position", hover)
				var drop: Vector3 = step.drop
				var velocity := _solve_launch(origin, drop + Vector3.UP * 0.9, JUMP_TIME)
				players.begin_intro_ladder_jump(player, velocity, drop, JUMP_TIME, drop)
				if ladder != null:
					ladder.set_payload_active(false)
				step.phase = "jump"
				step.t = 0.0
		"jump":
			_rig.set_motion(player, hover + Vector3(0.0, t * 0.6, 0.0), Vector3.ZERO, maxf(_real_dt, 0.0001))
			var state := players.update_intro_ladder_jump(player, _real_dt)
			if bool(state.get("landed", false)) or t > JUMP_TIME + 1.5:
				step.phase = "landed"
				step.t = 0.0
		"landed":
			_leave(player, t, hover)
			return t >= LANDED_HOLD
		"left":
			return true
	return false


## The aircraft lifts off and leaves on its jets, then hides.
func _leave(player: int, t: float, from: Vector3) -> void:
	var aircraft := _rig.heli(player)
	if aircraft != null and aircraft.has_jets():
		aircraft.set_jet_charge(clampf(t / 0.8, 0.0, 1.0))
		if t >= 0.8 and _cue("leave_ignite_%d_%d" % [player, int(_act)], true):
			aircraft.ignite_jets(false)
	var s := maxf(0.0, t - 0.4)
	_rig.set_motion(player, from + Vector3(0.0, 2.0 * s + 3.0 * s * s, 0.0) + _presenter.approach_offset(player).normalized() * 6.0 * s * s,
		_presenter.approach_offset(player), maxf(_real_dt, 0.0001))
	if t > 5.0:
		_rig.set_shown(player, false)
		_rig.remove_ladder(player)


# ------------------------------------------------------------------ venue (the game)

func _update_venue() -> void:
	_presenter.update_venue(_real_dt)
	if _floatplane:
		_staging.advance_idle(_real_dt)
	else:
		for player in [1, 2]:
			var step: Dictionary = _steps[player]
			if str(step.get("phase", "")) == "landed":
				step.t = float(step.t) + _real_dt
				_leave(player, float(step.t), step.hover)
	var camera := _presenter.venue_camera()
	if not camera.is_empty():
		# Right after a drop the lens eases from the chase onto the game's top-down shot (heli_drop.md 3.1: no cut).
		if _smooth_handover and _act_time < 1.6:
			camera = camera.duplicate()
			camera["cut"] = false
		else:
			_smooth_handover = false
		_set_camera_from(camera, str(camera.get("shot", "venue")))
	if _floatplane and _presenter.round_cleared():
		var rules := game_state.sudden_death_game as SkyGateGame
		if _cue("round_black_%d" % (rules.current_round if rules != null else _round_next), true):
			_begin_round_blackout()
		return
	if _presenter.finale_done():
		_winner = _presenter.winner()
		_loser = 3 - _winner
		_begin_extract()


# ------------------------------------------------------------------ return (10.1)

func _begin_extract() -> void:
	_act = Act.EXTRACT
	_act_time = 0.0
	var player := _winner
	if _floatplane:
		# The winner dances on the float while the floatplane is held back, then it comes to the float as between rounds.
		var wait := maxf(_presenter.extract_delay(), 0.0)
		_steps[player] = {"phase": "dance", "t": -wait, "delay": wait}
		if _presenter.shows_winner_banner():
			_hud_call("show_winner", [player])
		return
	var ground := _presenter.extract_point(player)
	var rung := ground + Vector3(0.0, RUNG_HEIGHT, 0.0)
	var hover := _rig.holder_for_rung(rung)
	var from := hover + _presenter.approach_offset(player)
	_rig.remove_ladder(player)
	_rig.place(player, from, hover - from)
	_rig.set_shown(player, true)
	var aircraft := _rig.heli(player)
	if aircraft != null:
		aircraft.extinguish_jets(true)
		aircraft.stow_jets()
	# The presenter may hold the aircraft back a while (the winner's dance, parachute.md 6.6): the clock starts negative.
	var delay := maxf(_presenter.extract_delay(), 0.0)
	_rig.set_shown(player, delay <= 0.0)
	_steps[player] = {"phase": "approach", "t": -delay, "delay": delay, "hover": hover, "from": from, "ground": ground}
	if _presenter.shows_winner_banner():
		_hud_call("show_winner", [player])


func _update_extract() -> void:
	if _floatplane:
		_update_extract_floatplane()
		return
	var player := _winner
	var step: Dictionary = _steps[player]
	step.t = float(step.t) + _real_dt
	var t := float(step.t)
	var hover: Vector3 = step.hover
	var from: Vector3 = step.from
	_presenter.update_venue(_real_dt)
	match str(step.phase):
		"approach":
			var since := t + float(step.get("delay", 0.0))
			if t < 0.0:
				_presenter.pose_winner_waiting(player, since)
				_set_camera_from(_presenter.extract_camera(player, from), "extract_wait")
				return
			if not (_rig.holder(player) as Node3D).visible:
				_rig.place(player, from, hover - from)
				_rig.set_shown(player, true)
			var u := clampf(t / EXTRACT_APPROACH, 0.0, 1.0)
			_rig.set_motion(player, from.lerp(hover, 1.0 - pow(1.0 - u, 3.0)), hover - from, maxf(_real_dt, 0.0001))
			var ladder := _rig.ensure_ladder(player, "pickup")
			ladder.set_winch_progress(0.0)
			ladder.set_deploy_progress(clampf((t - EXTRACT_APPROACH + 1.0) / 1.2, 0.0, 1.0))
			_presenter.pose_winner_waiting(player, since)
			if u >= 1.0 and ladder.is_ready_for_ground_pickup():
				_presenter.release_avatar(player)
				step.phase = "run"
				step.t = 0.0
		"run":
			_rig.set_motion(player, hover, Vector3.ZERO, maxf(_real_dt, 0.0001))
			if players.update_intro_pickup_approach(player, step.ground, _real_dt) or t > 3.0:
				players.begin_intro_ladder_grab(player, GRAB_TIME)
				step.phase = "grab"
				step.t = 0.0
		"grab":
			_rig.set_motion(player, hover, Vector3.ZERO, maxf(_real_dt, 0.0001))
			var progress := clampf(t / GRAB_TIME, 0.0, 1.0)
			players.update_intro_ladder_grab(player, _rig.grip(player, Vector3.ZERO, false), progress, _real_dt)
			if progress >= 1.0:
				_rig.ladder(player).set_payload_active(true)
				_audio_grip(player)
				step.phase = "climb"
				step.t = 0.0
		"climb":
			players.update_intro_ladder_grab(player, _rig.grip(player, Vector3.ZERO, false), 1.0, _real_dt)
			var aircraft := _rig.heli(player)
			if aircraft != null and aircraft.has_jets():
				aircraft.set_jet_charge(clampf(t / CLIMB_CHARGE, 0.0, 1.0))
				if t >= CLIMB_CHARGE and _cue("extract_ignite", true):
					aircraft.ignite_jets(false)
			var s := maxf(0.0, t - CLIMB_CHARGE * 0.5)
			_rig.set_motion(player, hover + Vector3(0.0, 3.0 * s + 3.2 * s * s, 0.0) - _presenter.approach_offset(player).normalized() * 3.0 * s * s,
				-_presenter.approach_offset(player), maxf(_real_dt, 0.0001))
			if t >= CLIMB_LENGTH and _cue("cloud_home", true):
				_cover.play(_enter_home)
	var camera := _presenter.extract_camera(player, (_rig.holder(player) as Node3D).global_position)
	_set_camera_from(camera, "extract")


## The floatplane comes for the winner at the landing float (the same approach as between rounds); the winner keeps
## dancing until the ramp is down, then runs aboard, and the cloud cover takes everyone home.
func _update_extract_floatplane() -> void:
	var player := _winner
	var step: Dictionary = _steps[player]
	step.t = float(step.t) + _real_dt
	var since := float(step.t) + float(step.get("delay", 0.0))
	_presenter.update_venue(_real_dt)
	match str(step.phase):
		"dance":
			# On the first frame the game still shows its landing orbit (this frame's pose).
			var landing_view := _presenter.venue_camera()
			_presenter.pose_winner_waiting(player, since)
			# The dance orbit continues the landing orbit (same direction and turning speed), so it is placed as is (no
			# easing on top). Its first frame is one turning step ahead: that small offset fades out over 0.8 s.
			var orbit := _presenter.extract_camera(player, Vector3.ZERO)
			if not step.has("orbit_fix") and landing_view.has("transform"):
				step["orbit_fix"] = (orbit.transform as Transform3D).affine_inverse() * (landing_view.transform as Transform3D)
			var fix: Transform3D = step.get("orbit_fix", Transform3D.IDENTITY)
			orbit.transform = (orbit.transform as Transform3D) * Transform3D.IDENTITY.interpolate_with(fix, 1.0 - smoothstep(0.0, 0.8, since))
			orbit["cut"] = true
			_set_camera_from(orbit, "extract_wait")
			if float(step.t) >= 0.0:
				var only: Array[int] = [player]
				_staging.begin_pickup(only, _presenter.landing_float(), func() -> void: _presenter.release_avatar(player),
					func() -> Dictionary: return _presenter.extract_camera(player, Vector3.ZERO))
				step.phase = "pickup"
		"pickup":
			if not _staging.released():
				_presenter.pose_winner_waiting(player, since)
			var state := _staging.update_pickup(_real_dt)
			# Deep inside the cloud deck after the take-off the venue swaps for the sky over the stage (no cover, no cut).
			if state == "swap" and _cue("home_cloud", true):
				_cover.play_black(_enter_home)
			elif state == "cover" and _cue("home_cloud", true):
				_cover.play(_enter_home)


## Under the cloud: back to the surface; the ceremony waits at the verdict with the winner.
func _enter_home() -> void:
	_presenter.set_venue_active(false)
	_presenter.set_sun(false)
	# An air game stays in the sky set until here.
	_sky.visible = false
	_restore_environment()
	if _surface_toggle.is_valid():
		_surface_toggle.call(true)
	if _rig != null:
		_rig.set_shown(_loser, false)
		_rig.remove_ladder(_loser)
		_rig.remove_ladder(_winner)
	players.cancel_intro_drops()
	players.reset_result_presentation()
	game_state.end_sudden_death(true)
	game_state.sudden_death_live_players = true
	var stage := ceremony.stage() if ceremony != null else null
	if ceremony != null:
		ceremony.allow_egg_target = false
	if stage != null:
		stage.set_actor_flight(_winner, Vector3.ZERO, -1.0)
		stage.set_actor_flight(_loser, Vector3.ZERO, -1.0)
	if _floatplane:
		# The floatplane passes low over the podium; the winner jumps off its ramp onto the floor (heli_drop.md 2.3).
		_lock_avatar(_winner)
		_staging.begin_home(_winner, _podium)
		_steps[_winner] = {"phase": "plane", "t": 0.0}
	else:
		var ground := _home_ground(_winner)
		var hover := ground + Vector3(0.0, DROP_HOVER, 0.0)
		var from := hover + Vector3(_side(_winner) * 10.0, 10.0, -40.0)
		_rig.place(_winner, from, hover - from)
		_rig.set_shown(_winner, true)
		var aircraft := _rig.heli(_winner)
		if aircraft != null:
			aircraft.extinguish_jets(true)
			aircraft.stow_jets()
		_steps[_winner] = {"phase": "approach", "t": 0.0, "drop": ground, "hover": hover, "from": from}
		players.begin_intro_cabin_ride(_winner, _rig.cabin_wait_transform(_winner))
	_steps[_loser] = {"phase": "", "t": 0.0}
	(_puppets[_loser] as StagingPuppet).set_visible(false)
	_hud_call("hide_all", [false])
	_act = Act.HOME
	_act_time = 0.0


## In front of the winner's sunk pad (the camera side), on the floor.
func _home_ground(player: int) -> Vector3:
	return _podium + Vector3(_side(player) * QuizGameState.RESULT_PLAYER_X, 0.0, -1.6)


func _update_home() -> void:
	var t := _act_time
	var stage := ceremony.stage() if ceremony != null else null
	var step: Dictionary = _steps[_winner]
	if _floatplane:
		if _staging.update_home(_real_dt) == "landed" and not step.has("hop"):
			# From where the landing clip ended (the goal side of the pad), turning round to the camera.
			step["hop"] = 0.0
			step["hop_from"] = _staging.home_feet()
			step["hop_yaw"] = 0.0
	match str(step.phase):
		"approach", "lower", "swing", "jump":
			_update_drop(_winner, Vector3(0.0, 0.0, 1.0))
		"landed":
			_update_drop(_winner, Vector3(0.0, 0.0, 1.0))
			if float(step.t) >= LANDED_HOLD and not _steps[_winner].has("hop"):
				players.complete_intro_ladder_landing(_winner, game_state)
				players.cancel_intro_drops()
				_lock_avatar(_winner)
				(_puppets[_loser] as StagingPuppet).set_visible(false)
				_steps[_winner]["hop"] = 0.0
		"left":
			pass
	if _steps[_winner].has("hop"):
		_update_winner_hop(stage)
	# The loser flies in as a ghost from off screen onto its sunk pad. Until then neither
	# finale figure shows: the ceremony stage rebuilds itself with the winner after end_sudden_death, which
	# clears what was hidden, so this is set again every frame.
	var drain_t := t - (HOME_APPROACH + LOWER_TIME * 0.5)
	if stage != null:
		var flight := -1.0
		if drain_t >= HOME_DRAIN:
			flight = clampf((drain_t - HOME_DRAIN) / GHOST_FLIGHT, 0.0, 1.0)
		if flight < 1.0 or not _cues.has("loser_landed_once"):
			var from := _podium + Vector3(_side(_loser) * GHOST_FROM.x, GHOST_FROM.y, GHOST_FROM.z)
			stage.set_actor_flight(_loser, from, flight, "ghost")
			if flight >= 1.0:
				_cues["loser_landed_once"] = _act_time
		if not _steps[_winner].has("swapped_at"):
			stage.set_actor_flight(_winner, Vector3.ZERO, -1.0)
	if drain_t >= HOME_DRAIN and _cue("ghost", true):
		AudioManager.play_sfx(&"ghost_soul_rise", -4.0)
	if drain_t >= HOME_DRAIN + GHOST_FLIGHT and _cue("loser_land", true):
		if ceremony != null:
			ceremony.allow_egg_target = true
	# The floatplane's flyby has its own lens until the winner is down (FloatplaneStaging), then a cut to the home shot.
	if not _floatplane or _steps[_winner].has("hop"):
		_home_camera(t)
	var swapped_at := float(_steps[_winner].get("swapped_at", -1.0))
	if swapped_at >= 0.0:
		game_state.result_return_regrow = smoothstep(0.0, REGROW_TIME, t - swapped_at)
		if t - swapped_at >= REGROW_TIME + 0.2 and drain_t >= HOME_DRAIN + GHOST_FLIGHT + 0.3:
			_release_ceremony()
	elif t > 16.0:
		_release_ceremony()


## The winner hops up onto the sunk pad, then the finale cast takes over (the tower grows back).
func _update_winner_hop(stage: ResultFinaleStage) -> void:
	var step: Dictionary = _steps[_winner]
	var h := float(step.hop) + _real_dt
	step.hop = h
	var puppet := _puppets[_winner] as StagingPuppet
	var from: Vector3 = step.get("hop_from", _home_ground(_winner))
	var pad := _podium + Vector3(_side(_winner) * QuizGameState.RESULT_PLAYER_X, 0.0, 0.0)
	# A longer hop when the floatplane's landing ended farther from the pad (the roll).
	var hop_time := clampf(Vector2(pad.x - from.x, pad.z - from.z).length() / 3.6, HOP_TIME, 1.0)
	var u := clampf(h / hop_time, 0.0, 1.0)
	var at := from.lerp(pad, u)
	var lift := 4.0 * u * (1.0 - u) * 0.45
	if u < 1.0:
		puppet.pose("Jump_Loop", fposmod(h * 1.4, 1.0))
	else:
		puppet.pose("Idle_Loop", fposmod(h / 2.0, 1.0))
	var yaw := lerp_angle(float(step.get("hop_yaw", PI)), PI, smoothstep(0.0, 0.7, u))
	puppet.stand_at(at, yaw, StageConstants.FLOOR_TOP_Y + 0.07 * u + lift)
	if not _floatplane:
		_leave(_winner, h + 0.6, step.hover)
	if u >= 1.0 and not step.has("swapped_at"):
		step["swapped_at"] = _act_time
		# 勝者のタワーが伸び直す（REGROW_TIME）
		AudioManager.play_sfx(&"sd_tower_move", -3.0, 1.0)
		puppet.set_visible(false)
		game_state.sudden_death_live_players = false
		if stage != null:
			stage.set_actor_flight(_winner, Vector3.ZERO, 1.0)


func _home_camera(t: float) -> void:
	var shot := _look(_podium + Vector3(0.0, 4.6, -15.5), _podium + Vector3(0.0, 3.6, 0.0))
	var fov := 56.0
	var swapped_at := float(_steps[_winner].get("swapped_at", -1.0))
	if swapped_at >= 0.0:
		var finale := _finale_camera(QuizGameState.RESULT_VERDICT_TIME)
		var u := smoothstep(0.0, HOME_MATCH + REGROW_TIME * 0.5, t - swapped_at)
		shot = _blend(shot, finale.transform, u)
		fov = lerpf(fov, float(finale.fov), u)
	# The floatplane's lens is already on this shot when the winner lands (no cut, c130_float.md 10).
	_cut(shot, fov, "home")


func _release_ceremony() -> void:
	game_state.release_result_return_hold()
	game_state.sudden_death_live_players = false
	if ceremony != null:
		ceremony.allow_egg_target = true
		var stage := ceremony.stage()
		if stage != null:
			stage.clear_actor_flights()
	players.cancel_intro_drops()
	if _rig != null:
		_rig.hide_all()
	if _staging != null:
		_staging.hide_all()
	if camera_controller != null:
		camera_controller.clear_director_pose()
	_pose_ready = false
	_hud_call("hide_all", [false])
	if _presenter != null:
		_presenter.teardown()
	_act = Act.DONE
	_act_time = 0.0


# ------------------------------------------------------------------ abort

## Preparation failed or ran out of time: back to the surface, the draw ends as before.
func _abort_to_surface() -> void:
	_sky.visible = false
	if _presenter != null:
		_presenter.set_venue_active(false)
		_presenter.set_sun(false)
	_restore_environment()
	if _surface_toggle.is_valid():
		_surface_toggle.call(true)
	players.cancel_intro_drops()
	players.reset_result_presentation()
	if _rig != null:
		_rig.hide_all()
	if _staging != null:
		_staging.hide_all()
	game_state.sudden_death_live_players = false
	game_state.sudden_death_preparing_panel = ""
	game_state.abort_sudden_death(true)
	_hud_call("hide_all", [false])
	_act = Act.ABORT
	_act_time = 0.0


func _update_abort() -> void:
	game_state.result_return_regrow = smoothstep(0.2, 1.8, _act_time)
	var finale := _finale_camera(QuizGameState.SUDDEN_DEATH_ABORT_RESUME_TIME)
	_cut(finale.transform, float(finale.fov), "abort")
	if _act_time >= 2.1:
		game_state.release_result_return_hold()
		if camera_controller != null:
			camera_controller.clear_director_pose()
		_pose_ready = false
		if _presenter != null:
			_presenter.teardown()
		_act = Act.DONE


# ------------------------------------------------------------------ preparation

## One venue build step a frame (from the branch on), then the render prewarm.
func _step_preparation() -> void:
	if _prep_ready or _prep_failed or _presenter == null or _act in [Act.IDLE, Act.DONE, Act.ABORT]:
		return
	if debug_load_delay > 0.0 and float(Time.get_ticks_usec() - _prep_started_usec) / 1000000.0 < debug_load_delay:
		return
	if _prep_index < _prep_steps.size():
		_prep_steps[_prep_index].call()
		_prep_index += 1
		return
	_prep_ready = _presenter.prewarm_tick()


func preparation_ready() -> bool:
	return _prep_ready


# ------------------------------------------------------------------ avatars

## Keep the avatars out of update_from_state (both stop together), with nothing auto-posing them.
func _lock_avatar(player: int) -> void:
	var pelvis := (_puppets[player] as StagingPuppet).parts().get("pelvis") as Node3D
	var xf := pelvis.global_transform if pelvis != null else Transform3D.IDENTITY
	players.begin_intro_cabin_ride(player, xf)


func puppet(player: int) -> StagingPuppet:
	return _puppets.get(player) as StagingPuppet


func lock_avatar(player: int) -> void:
	_lock_avatar(player)


# ------------------------------------------------------------------ camera

func _look(eye: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


func _blend(a: Transform3D, b: Transform3D, u: float) -> Transform3D:
	return a.interpolate_with(b, clampf(u, 0.0, 1.0))


## A shot the lens eases toward (cut = place it at once).
func _cut(pose: Transform3D, fov: float, shot: String, cut := false) -> void:
	_target_pose = pose
	_target_fov = fov
	if cut or not _pose_ready:
		_pose = pose
		_pose_fov = fov
		_pose_ready = true
	if shot != _shot_name:
		_shot_name = shot
		if not _shot_log.has(shot):
			_shot_log[shot] = Time.get_ticks_msec()


## {"transform", "fov", "cut"} from the presenter.
func _set_camera_from(camera: Dictionary, shot: String) -> void:
	if camera.is_empty():
		return
	_cut(camera.transform, float(camera.get("fov", 55.0)), shot, bool(camera.get("cut", false)))


func _apply_camera() -> void:
	if not _pose_ready or camera_controller == null or _act in [Act.IDLE, Act.DONE]:
		return
	var follow := 1.0 - exp(-2.6 * maxf(_real_dt, 0.0))
	if _cover != null and _cover.is_playing():
		follow = 1.0
	_pose = _pose.interpolate_with(_target_pose, follow)
	_pose_fov = lerpf(_pose_fov, _target_fov, follow)
	if game_state.camera_shake > 0.0:
		var shake := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * game_state.camera_shake * 0.4
		camera_controller.set_director_pose(Transform3D(_pose.basis, _pose.origin + shake), _pose_fov)
	else:
		camera_controller.set_director_pose(_pose, _pose_fov)


func _finale_camera(ceremony_time: float) -> Dictionary:
	if camera_controller != null and camera_controller.has_method("result_ceremony_camera_pose"):
		return camera_controller.result_ceremony_camera_pose(game_state, ceremony_time)
	return {"transform": _look(_podium + Vector3(0.0, 4.0, -10.0), _podium + Vector3(0.0, 2.0, 0.0)), "fov": 42.0}


func main_camera() -> Camera3D:
	if camera_controller == null:
		return null
	return camera_controller.get("camera") as Camera3D


func _set_environment(environment: Environment) -> void:
	_venue_env = environment
	var camera := main_camera()
	if camera != null:
		camera.environment = environment


func _restore_environment() -> void:
	var camera := main_camera()
	if camera != null and _venue_env != null and camera.environment == _venue_env:
		camera.environment = null
	_venue_env = null


# ------------------------------------------------------------------ HUD and sound

func hud() -> SuddenDeathHud:
	_ensure_hud()
	return _hud


func _ensure_hud() -> void:
	if is_instance_valid(_hud):
		return
	_hud = SuddenDeathHud.new()
	add_child(_hud)
	_hud.setup(game_state.use_english_ui if game_state != null else false)


func _hud_call(method: String, args: Array) -> void:
	_ensure_hud()
	if _hud.has_method(method):
		_hud.callv(method, args)


func _audio_grip(player: int) -> void:
	var aircraft := _rig.heli(player)
	if aircraft != null and aircraft.sound != null and aircraft.sound.has_method("play_one_shot"):
		aircraft.sound.call("play_one_shot", "grip")


# ------------------------------------------------------------------ helpers

func _side(player: int) -> float:
	return 1.0 if player == 1 else -1.0


func _cue(cue_name: String, when: bool) -> bool:
	if not when or _cues.has(cue_name):
		return false
	_cues[cue_name] = _act_time
	return true


static func _solve_launch(origin: Vector3, landing: Vector3, duration: float) -> Vector3:
	var flight_time := maxf(duration, 0.08)
	var gravity := Vector3(0.0, -9.8, 0.0)
	return (landing - origin - gravity * (0.5 * flight_time * flight_time)) / flight_time


func _capture_cast_pose() -> Dictionary:
	var result := {}
	var stage := ceremony.stage() if ceremony != null else null
	if stage == null or not stage.is_built():
		return result
	for player_index in [1, 2]:
		var parts := stage.actor_parts(player_index)
		var pose := {}
		for key: Variant in parts:
			if parts[key] is Node3D and (parts[key] as Node3D).is_inside_tree():
				pose[key] = (parts[key] as Node3D).global_transform
		if not pose.is_empty():
			result[player_index] = pose
	return result


func get_debug_snapshot() -> Dictionary:
	return {"act": act_name(), "act_time": _act_time, "shot": _shot_name, "prep_ready": _prep_ready,
		"prep_index": _prep_index, "prep_steps": _prep_steps.size(), "winner": _winner,
		"floatplane": _floatplane, "round_next": _round_next,
		"staging": _staging.get_debug_snapshot() if _staging != null else {},
		"steps": {1: str(_steps[1].get("phase", "")), 2: str(_steps[2].get("phase", ""))},
		"live_cast": _live_cast, "revive_ghosts": _revive_ghosts.duplicate(),
		"presenter": _presenter.get_debug_snapshot() if _presenter != null else {}}
