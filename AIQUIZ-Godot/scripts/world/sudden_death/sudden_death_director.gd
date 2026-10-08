class_name SuddenDeathDirector
extends Node3D

## 2Pサドンデス「早押し水没リフト」の演出の進行役（docs/sudden_death_underground.md 第2・5章）。
## DRAWの決着演出からの分岐（審判の笛・カットイン・両方のタワーが沈む・床のアイリス）、
## 黄色いランプの縦穴の降下（その間に地下神殿を別スレッドで準備）、着地と導入（2人がリフトのタワーへ
## 歩いて乗り、タワーがせり上がり、トンネルから鉄砲水）、本戦の表示（問題・早押し・判定・タワーの昇降・
## カメラ）、決着後の帰還（敗者のタワーが水に沈む、勝者を昇降台で地表へ、勝者のタワーの再上昇、
## 敗者が排水口から噴き出す）を順に進める。
## 準備が間に合わない・失敗したときは止まって引き返し、地表で従来の引き分けとして終える。
##
## 判定は持たない。QuizGameState と SuddenDeathState を読み、演出用の値（選手の持ち上げ量、
## 演出中の選手の位置と向き、ResultCeremonyDirector.stage_drop、帰還時のタワーの伸び）だけを書く。
## 演出の時計は実時間（メインスレッドが止まっても遅れず、止まった分だけ先へ進む）。
##
## 座標：縦穴（ShaftDescent）の原点は穴の軸。地表では口の中心（演出の台座）に置き、
## 巡航では地下神殿の着地点の真上 CRUISE_DECK_HEIGHT に付け替える（カットの瞬間なので見えない）。
## 減速の始めに、残りの降下で天井へ届く高さへもう一度付け替える。

const SHAFT_SCENE_PATH := "res://scenes/sudden_death/shaft_descent.tscn"
const Motion = preload("res://scripts/world/result_finale/result_finale_motion.gd")

enum Act { IDLE, BRANCH, DESCENT, INTRO, RUN, RETURN, ABORT, DONE }

# ------------------------------------------------------------------ branch (ceremony clock)
const CUT_IN_TIME := 8.6
## The finale lens hands over to the high podium shot while the towers sink.
const BRANCH_CAMERA := Vector2(9.2, 10.6)
## The letterbox bars slide in while the camera rises over the podium (ceremony seconds).
const LETTERBOX_IN := Vector2(10.0, 11.0)
## Descent seconds over which one continuous move takes the podium shot down the mouth after the
## deck and round to the cruise framing behind the runners (no cut: docs 5.4 shots A and B).
const PATH_START := 0.25
const PATH_END := 4.0
## Cruise framing, deck space: from just inside the wall behind the runners, over their heads.
const CRUISE_EYE := Vector3(1.5, 3.4, -5.9)
const CRUISE_AIM := Vector3(-0.5, -3.6, 6.0)
## Halfway (deck space): high behind the riders, so they stay whole in frame on the way in.
const PATH_MID_EYE := Vector3(0.8, 5.4, -5.2)
const PATH_MID_AIM := Vector3(0.0, -1.2, 2.2)
## The live runners and the deck's referee take over from the finale cast in this many seconds.
const CAST_HANDOFF := 0.7
## Descent seconds over which the sinking deck leaves the sun and the open sky behind, so only the
## shaft's own lamps light it by the swap (the shaft environment takes over then).
const DUSK := Vector2(1.0, 2.3)
## The surface environment's exposure at the swap: the shaft environment then starts at
## SHAFT_START_EXPOSURE, and the deck looks the same on both sides of it.
const ENTRY_END_EXPOSURE := 0.62
const SHAFT_START_EXPOSURE := 0.55
const IRIS_OPEN_TIME := 0.6
## From the cut-in the surface falls to night over NIGHT_FADE seconds (as far as NIGHT_AMOUNT of the
## descent's dusk), so the scoreboard's "SUDDEN DEATH!" and the beacons carry the moment on their own.
const NIGHT_AMOUNT := 0.8
const NIGHT_FADE := 0.9

# ------------------------------------------------------------------ landing / intro (real seconds after touchdown)
const INTRO_SHOUT := 0.2
## Both walk off the deck to their own lift tower (the score towers, downstream of the landing point)
## and step onto its platform, flush with the floor.
const INTRO_WALK := Vector2(0.9, 3.2)
## The towers lift them to the starting height over the floor, and the deck takes the referee back up.
const INTRO_RISE := 3.4
const INTRO_RISE_SPEED := 2.4
## While they walk, the inflow gate lifts and the flood bursts out of the tunnel: an insert shot (cut in and
## out). The towers have lifted them by the time it comes rushing under them.
const INTRO_GATE := 2.0
const INFLOW_SHOT := 1.35
const TUNNEL_SHOT_CUT_OUT := 0.1
## From the low shot of the rising towers to the duel shot.
const INTRO_DUEL := 5.6
## The rule card stays up until a player presses Enter (confirm_rules), so the rules can be read at leisure.
## Enter is ignored for this long after the card appears, so a held or mashed key does not skip it unread.
const INTRO_RULES := 6.2
const RULES_MIN_READ := 0.6
## The countdown waits until the flood has run this long (it has passed the towers and filled the view).
const FLOOD_LEAD := 11.0
const DECK_RISE_TIME := 1.9
## Lights come on row by row from 1.0 s into the arrival (docs 2.2).
const LIGHTS_START := 1.0
const LIGHTS_STEP := 0.12
const LIGHT_FLICKER := 0.09

# ------------------------------------------------------------------ duel camera (docs 7)
## From upstream (under the ceiling opening), looking down the hall: both lift towers with the players
## turned toward the lens (P1 left, P2 right), the flood running past the camera and on under them into
## the pillar forest.
const DUEL_EYE := Vector3(0.0, 5.0, -12.5)
const DUEL_AIM := Vector3(0.0, 3.2, 6.0)
const DUEL_FOV := 50.0
## How quickly the duel camera eases to a new framing (1/s).
const DUEL_FOLLOW := 2.6
## Seconds of a result that look at the sinking tower.
const SINK_LOOK := 1.5

# ------------------------------------------------------------------ return (real seconds after the decision)
const SLOWMO_TIME := 1.0
## The slow motion holds until the water has taken the loser (and this long after, real seconds),
## at most SLOWMO_MAX: the plunge takes SuddenDeathTuning.plunge_time game seconds.
const SLOWMO_AFTER_CATCH := 0.8
const SLOWMO_MAX := 3.2
const SLOWMO_SCALE := 0.5
const PICKUP_DECK := Vector2(1.0, 2.0)
const PICKUP_DECK_HEIGHT := 16.0
## The deck comes down downstream of the winner's tower, its edge just clear of the platform.
const PICKUP_CLEARANCE := 0.3
const PICKUP_RUN_SPEED := 3.6
const LIFT_OFF_TIME := 0.45
const LIFT_OFF_HEIGHT := 4.0
const ASCENT_TIME := 2.5
const ASCENT_SPEED := 22.0
## Surface (real seconds after the cut back up).
const SURFACE_RISE := 0.7
const SURFACE_IRIS_CLOSE := Vector2(0.62, 0.98)
## Starts once the iris has closed (the tower column grows up from inside the deck).
const SURFACE_REGROW := Vector2(1.0, 3.1)
const SURFACE_DRAIN := 1.15
const DRAIN_FLIGHT := 1.0
const SURFACE_CAMERA_MATCH := Vector2(2.3, 3.1)
const SURFACE_RELEASE := 3.1
const ABORT_REGROW := Vector2(0.2, 1.8)
const ABORT_RELEASE := 2.1

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
## Tests: forwarded to the loader when the descent starts.
var debug_load_delay := 0.0
var debug_load_fail := false

var _act := Act.IDLE
var _act_time := 0.0
var _last_usec := 0
var _real_dt := 0.0
var _shaft: ShaftDescent = null
var _shaft_packed: PackedScene = null
var _loader: SuddenDeathLoader = null
var _hud: SuddenDeathHud = null
var _audio: SuddenDeathAudio = null
var _drain: SurfaceDrain = null
var _descent := SuddenDeathDescent.new()
var _podium := Vector3.ZERO
var _cues := {}
var _shaft_env: Environment = null
var _hall_env: Environment = null
var _surface_env: Environment = null
var _env_ramp := Vector3(1.0, 1.0, 1.0)  # from, to, duration
var _env_ramp_time := 0.0
var _env_base_exposure := 1.0
var _camera_from := Transform3D.IDENTITY
var _camera_from_fov := 50.0
var _camera_pose := Transform3D.IDENTITY
var _camera_fov := 50.0
var _camera_shot := ""
var _deck_props: Node3D = null
var _deck_referee: Node3D = null
var _deck_referee_animation: AnimationPlayer = null
var _deck_towers := {}
var _deck_world := Vector3.ZERO
var _deck_local_y := 0.0
var _scroll := 0.0
var _cruise_anchor_deck_y := 0.0
var _swapped := false
## Podium space -> world: the shaft (and the camera path with it) jumps above the cistern at the swap.
var _space_offset := Vector3.ZERO
## The finale referee's bone poses at the swap, blended into the deck referee's idle.
var _referee_handoff := {}
var _referee_handoff_time := 0.0
## The surface sky's ambient and energy before the descent faded them (a copy of the surface environment).
var _surface_ambient := -1.0
var _surface_sky := 1.0
var _surface_fog := 1.0
## How far the branch has already taken the surface into night (0..NIGHT_AMOUNT).
var _branch_night := 0.0
var _arrival_anchored := false
var _arrival_started := false
var _abort_announced := false
var _arrival_start_distance := 0.0
var _game_dt := 0.0
var _last_frame := 0
var _deck_rise_elapsed := -1.0
var _lamp_index := 0
var _sign_depths: Array[float] = []
var _landed_time := -1.0
## Intro seconds the rule card appeared at (-1 before), whether Enter took it away, when the countdown
## may start (INF until then) and when the gate opened and the flood came out (INF before).
var _rules_shown_at := -1.0
var _rules_confirmed := false
var _countdown_at := INF
var _flood_at := INF
var _deck_rise_from := -1.0
## Return slow motion: when (stage seconds) the water took the loser.
var _caught_at := -1.0
## The duel camera's eased pose and lens, and the last countdown second ticked.
var _run_pose := Transform3D.IDENTITY
var _run_fov := DUEL_FOV
var _last_tick := -1
var _row_lights_on := 0
# Return
var _winner := 0
var _loser := 0
var _return_stage := ""
var _stage_time := 0.0
var _winner_from := Vector3.ZERO
var _pickup_center := Vector3.ZERO
var _pickup_height := 0.0
var _ascent_scroll := 0.0
var _flight_from := Vector3.ZERO
var _frame_log: Array[float] = []
var _ready_frame_log: Array[float] = []
## Shot name -> descent time it first appeared (tests and the report).
var _shot_log := {}
var _events: Array[Dictionary] = []


func setup(state: QuizGameState, camera_rig: Node3D, ceremony_director: ResultCeremonyDirector,
		player_controller: PlayerController, stage_environment: StageEnvironment, surface_toggle: Callable) -> void:
	game_state = state
	camera_controller = camera_rig
	ceremony = ceremony_director
	players = player_controller
	stage_env = stage_environment
	_surface_toggle = surface_toggle
	name = "SuddenDeathDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		# A pause is not a stall: do not jump ahead by the paused time.
		_last_usec = Time.get_ticks_usec()


func _exit_tree() -> void:
	if Engine.time_scale != 1.0 and _act == Act.RETURN:
		Engine.time_scale = 1.0
	ResultCeremonyDirector.stage_drop = 0.0


func is_active() -> bool:
	return _act != Act.IDLE and _act != Act.DONE


func act_name() -> String:
	return Act.keys()[_act]


## Seconds into the current act (intro: since touchdown).
func act_time() -> float:
	return _act_time


## Seconds into the current return / abort stage.
func stage_time() -> float:
	return _stage_time


func shot_name() -> String:
	return _camera_shot


func shot_log() -> Dictionary:
	return _shot_log


func return_stage() -> String:
	return _return_stage


func descent() -> SuddenDeathDescent:
	return _descent


# ------------------------------------------------------------------ match start (under the loading cover)

## The shaft is small, so it is built with the match (docs 5.5) when a draw could branch.
func prepare_for_match() -> void:
	if game_state == null or not game_state.uses_sudden_death() or is_instance_valid(_shaft):
		return
	if _shaft_packed == null and ResourceLoader.exists(SHAFT_SCENE_PATH):
		_shaft_packed = load(SHAFT_SCENE_PATH) as PackedScene
	if _shaft_packed == null:
		push_warning("[SuddenDeath] Shaft scene missing; the descent will use the plain cut.")
		return
	_shaft = _shaft_packed.instantiate() as ShaftDescent
	_shaft.name = "ShaftDescent"
	add_child(_shaft)
	_shaft.setup(GameManager.graphics_quality)
	_shaft.visible = false
	_build_deck_props()
	_deck_props.visible = false
	# The drain column compiles its effect shaders on setup (~0.1-0.2 s): do it here.
	_ensure_drain()


func _ensure_drain() -> void:
	if is_instance_valid(_drain):
		return
	_drain = SurfaceDrain.new()
	_drain.name = "SurfaceDrain"
	add_child(_drain)
	_drain.setup(GameManager.graphics_quality)


func begin_render_prewarm(camera: Camera3D) -> Dictionary:
	prepare_for_match()
	if not is_instance_valid(_shaft) or camera == null:
		return {"ready": true, "skipped": true}
	_shaft.visible = true
	return _shaft.begin_render_prewarm(camera)


func end_render_prewarm() -> void:
	if is_instance_valid(_shaft):
		_shaft.end_render_prewarm()
		_shaft.visible = false


# ------------------------------------------------------------------ frame

## GameWorld calls this every frame, before the players, the finale stage and the camera.
func process_frame(delta: float) -> void:
	if game_state == null:
		return
	_game_dt = delta
	_real_dt = _real_delta(delta)
	if not use_real_time and is_instance_valid(_hud):
		# Frame-time tests: the HUD animations follow the same clock as the shots.
		_hud.debug_manual_clock = true
		_hud.debug_step(_real_dt)
	match _act:
		Act.IDLE:
			if game_state.sudden_death_pending and game_state.result_presentation_active:
				_begin_branch()
		Act.BRANCH:
			_update_branch()
		Act.DESCENT:
			_update_descent()
		Act.INTRO:
			_update_intro()
		Act.RUN:
			_update_run(delta)
		Act.RETURN:
			_update_return()
		Act.ABORT:
			_update_abort()
		Act.DONE:
			pass
	if _act in [Act.DESCENT, Act.INTRO, Act.RUN, Act.RETURN, Act.ABORT]:
		_update_env_ramp()
	if _act == Act.DONE and not game_state.result_presentation_active and game_state.game_state != Constants.STATE_SUDDEN_DEATH:
		reset()
	if _act != Act.IDLE and game_state.game_state == Constants.STATE_MENU:
		reset()


## Wall-clock seconds since the last frame. A stalled frame jumps ahead (docs 5.5);
## frames skipped by the pause menu (GameWorld stops calling us) do not.
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
	if _act not in [Act.RUN, Act.INTRO, Act.RETURN]:
		return
	var cistern := _cistern()
	if cistern != null:
		cistern.on_event(event)
	var kind := str(event.get("kind", ""))
	var player := int(event.get("player", 0))
	var english := game_state.use_english_ui
	match kind:
		"go":
			_hud_call("set_countdown", [""])
			_play(&"whistle", -4.0, 1.1)
		"buzz":
			_play(&"buzz", -1.0)
			_hud_call("flash", [0.18, 0.18])
			_hud_callout(("P%d BUZZ!" if english else "P%d 早押し！") % player, P1_COLOR if player == 1 else P2_COLOR, 1.0)
		"answer":
			if bool(event.get("correct", false)):
				_play(&"correct")
				_hud_callout(("P%d CORRECT!" if english else "P%d 正解！") % player, Color(0.45, 1.0, 0.55), 1.6)
			else:
				_play(&"wrong")
				var late := bool(event.get("late", false))
				_hud_callout(("P%d " + ("TOO LATE" if late else "WRONG!")) % player if english
					else ("P%d " + ("答えられず…" if late else "不正解！")) % player, Color(1.0, 0.4, 0.3), 1.6)
		"timeout":
			_play(&"time_up", -2.0)
			_hud_callout("TIME UP! BOTH LIFTS SINK" if english else "時間切れ！ 両方のリフトが沈む", Color(1.0, 0.72, 0.3), 1.6)
		"sink":
			var tower := cistern.tower_position(player) if cistern != null else Vector3.ZERO
			_audio_call("play_at", [&"deck_release", tower + Vector3(0.0, 2.0, 0.0), -5.0, 0.9])
		"caught":
			_hud_callout("P%d OUT!" % player, Color(1.0, 0.35, 0.3), 1.4)
			var at := _runner_world(player)
			_audio_call("play_at", [&"drain_burst", at, 0.0, 0.85])
		"decided":
			if _act == Act.RUN:
				_begin_return(int(event.get("winner", 0)))


## sudden_death_transition_requested: true when the draw finale reaches the descent.
## The finished rules (false) are handled by the return itself.
func on_transition_requested(entering: bool) -> void:
	if entering and _act == Act.BRANCH:
		_begin_descent()


# ------------------------------------------------------------------ branch (2.1)

func _begin_branch() -> void:
	_act = Act.BRANCH
	_act_time = 0.0
	_cues.clear()
	_events.clear()
	_frame_log.clear()
	_ready_frame_log.clear()
	_shot_log.clear()
	_podium = ResultCeremonyDirector.podium_center(game_state)
	_branch_night = 0.0
	prepare_for_match()
	_ensure_hud()
	_ensure_audio()
	# Compile the floor/ocean hole variants now, not on the cut-in frame.
	if stage_env != null and stage_env.has_method("prepare_shaft_hole"):
		stage_env.prepare_shaft_hole()
	_loader = SuddenDeathLoader.new()
	_loader.name = "SuddenDeathLoader"
	add_child(_loader)
	_loader.debug_extra_delay = debug_load_delay
	_loader.debug_force_fail = debug_load_fail
	_loader.begin(self, game_state)
	_loader.set_presentable(false)
	_loader.set_heavy_work_allowed(false)
	if is_instance_valid(_shaft):
		_shaft.global_position = _podium
		_shaft.set_view(0.0, 0.0)
		_shaft.set_clip(0.0, -INF)
		_shaft.set_mouth(true, 0.0, 0.0)
		_shaft.set_beacons(false)
		_shaft.set_daylight(1.0)
		_shaft.set_depth_signs([])
		_shaft.visible = false


func _update_branch() -> void:
	var elapsed := game_state.result_ceremony_elapsed
	if not game_state.sudden_death_pending:
		# The ceremony was cut short (menu, retry): nothing to do.
		reset()
		return
	if _cue("whistle", elapsed >= QuizGameState.SUDDEN_DEATH_BRANCH_TIME):
		_play(&"whistle")
	if _cue("cut_in", elapsed >= CUT_IN_TIME):
		# No 2D title: the scoreboard behind the podium carries "SUDDEN DEATH!".
		_hud_call("flash", [1.0, 0.22])
		_surface_env = _duplicate_surface_env()
		_surface_ambient = -1.0
		_set_env(_surface_env, 1.0, 1.0, 0.0)
		_play(&"siren", -2.0)
		# The floor under the podium becomes the steel hatch (hidden by the flash).
		if stage_env != null and stage_env.has_method("set_shaft_hole"):
			stage_env.set_shaft_hole(_podium, SuddenDeathLayout.SHAFT_RADIUS, true)
		if is_instance_valid(_shaft):
			_shaft.visible = true
			_shaft.set_beacons(true)
	if elapsed >= CUT_IN_TIME:
		_branch_night = NIGHT_AMOUNT * smoothstep(CUT_IN_TIME, CUT_IN_TIME + NIGHT_FADE, elapsed)
		_set_surface_dusk(_branch_night)
	if _cue("sink", elapsed >= QuizGameState.SUDDEN_DEATH_SINK_TIME):
		_play(&"deck_release", -9.0, 0.8)
	if _cue("iris", elapsed >= QuizGameState.SUDDEN_DEATH_IRIS_TIME):
		_play(&"iris_open")
	if elapsed >= LETTERBOX_IN.x:
		_hud_call("set_letterbox", [smoothstep(LETTERBOX_IN.x, LETTERBOX_IN.y, elapsed)])
	var iris := smoothstep(QuizGameState.SUDDEN_DEATH_IRIS_TIME, QuizGameState.SUDDEN_DEATH_IRIS_TIME + IRIS_OPEN_TIME, elapsed)
	if is_instance_valid(_shaft):
		_shaft.set_mouth(true, 0.0, iris)
	# Camera: the finale lens until the towers sink, then high over the podium.
	if elapsed >= BRANCH_CAMERA.x:
		if not _cues.has("camera_from"):
			_cues["camera_from"] = elapsed
			_capture_camera()
		var u := smoothstep(BRANCH_CAMERA.x, BRANCH_CAMERA.y, elapsed)
		var shot := _podium_shot()
		_set_camera(_blend(_camera_from, shot, u), lerpf(_camera_from_fov, 50.0, u), "podium")


# ------------------------------------------------------------------ descent (第5章)

func _begin_descent() -> void:
	_act = Act.DESCENT
	_act_time = 0.0
	_descent.reset()
	_scroll = 0.0
	_lamp_index = 0
	_swapped = false
	_space_offset = Vector3.ZERO
	_referee_handoff.clear()
	_arrival_anchored = false
	_arrival_started = false
	_abort_announced = false
	_deck_rise_elapsed = -1.0
	_landed_time = -1.0
	# The branch has usually put the night on already: keep it (no flash back to daylight).
	if _surface_env == null:
		_surface_env = _duplicate_surface_env()
		_surface_ambient = -1.0
	_set_env(_surface_env, 1.0, 1.0, 0.0)
	_play(&"deck_release")
	_audio_call("set_motor", [true, 0.0])
	_audio_call("set_depth_reverb", [0.0])
	_hud_call("set_letterbox", [1.0])


func _update_descent() -> void:
	_act_time += _real_dt
	var loader_ready := _loader != null and _loader.is_ready()
	var loader_failed := _loader == null or _loader.has_failed()
	# Online quiz generation (docs 第4章): keep going down until the questions are in.
	var waiting_questions := not game_state.is_sudden_death_question_ready()
	var progress := minf(_loader.progress() if _loader != null else 0.0, game_state.sudden_death_question_progress())
	_descent.set_preparation(progress, loader_ready, loader_failed, waiting_questions)
	_update_preparing_panel(waiting_questions)
	var stage_before := _descent.stage
	_descent.advance(_real_dt)
	var stage := _descent.stage
	# One long frame may cross several stages: every handover still happens, in order.
	if not _swapped and stage >= SuddenDeathDescent.Stage.CRUISE:
		_swap_to_underground()
		if _act != Act.DESCENT:
			return
	if stage in [SuddenDeathDescent.Stage.DECEL, SuddenDeathDescent.Stage.ARRIVAL, SuddenDeathDescent.Stage.LANDED] and not _arrival_anchored:
		_anchor_for_arrival()
	if stage in [SuddenDeathDescent.Stage.ARRIVAL, SuddenDeathDescent.Stage.LANDED] and not _arrival_started:
		_begin_arrival()
	if _descent.is_aborting() and not _abort_announced:
		_abort_announced = true
		_hud_callout("準備が間に合わない… 引き返す" if not game_state.use_english_ui else "NOT READY - GOING BACK UP", Color(1.0, 0.8, 0.3), 2.0)
		_play(&"klaxon", -6.0)
	if stage in [SuddenDeathDescent.Stage.ABORT_SURFACE, SuddenDeathDescent.Stage.ABORTED]:
		_begin_abort_surface()
		return
	match stage:
		SuddenDeathDescent.Stage.ENTRY, SuddenDeathDescent.Stage.ACCEL:
			_update_entry()
		SuddenDeathDescent.Stage.CRUISE, SuddenDeathDescent.Stage.ABORT_STOP, SuddenDeathDescent.Stage.ABORT_HOLD, SuddenDeathDescent.Stage.ABORT_RISE:
			_update_cruise()
		SuddenDeathDescent.Stage.DECEL, SuddenDeathDescent.Stage.ARRIVAL:
			_update_arrival()
		SuddenDeathDescent.Stage.LANDED:
			_update_arrival()
			_begin_intro()
			return
	if stage_before == SuddenDeathDescent.Stage.DECEL and stage == SuddenDeathDescent.Stage.ARRIVAL:
		_play(&"deck_stop", -8.0, 1.2)
	_audio_call("set_motor", [not _descent.is_finished(), absf(_descent.speed)])
	if is_instance_valid(_shaft):
		_shaft.set_motion_speed(_descent.speed)
	if stage == SuddenDeathDescent.Stage.CRUISE:
		_frame_log.append(_real_dt * 1000.0)
		if _descent.can_land():
			_ready_frame_log.append(_real_dt * 1000.0)


## The descent waits for its questions (online generation) or, past the minimum cruise,
## for the cistern: GameplayHUD shows the match-start "問題を準備中..." panel (docs 5.3).
func _update_preparing_panel(waiting_questions: bool) -> void:
	var panel := ""
	var going_down := _descent.stage in [SuddenDeathDescent.Stage.ENTRY, SuddenDeathDescent.Stage.ACCEL, SuddenDeathDescent.Stage.CRUISE]
	if going_down and waiting_questions:
		panel = "questions"
	elif _descent.stage == SuddenDeathDescent.Stage.CRUISE and not _descent.ready \
			and _descent.cruise_time >= SuddenDeathDescent.MIN_CRUISE:
		panel = "stage"
	game_state.sudden_death_preparing_panel = panel


## Through the ceiling opening: the hall's big air and reverb (docs 5.6).
func _begin_arrival() -> void:
	_arrival_started = true
	_set_env(_hall_env_for_quality(), 0.72, 1.0, 1.4)
	# Dark hall: only the cool column through the opening until the rows come on.
	CisternStage.apply_hall_light(_hall_env, 0.0)
	_audio_call("set_ambience", [&"hall"])
	_audio_call("set_hall_reverb", [])
	var cistern := _cistern()
	if cistern != null:
		cistern.set_opening_light(1.0)


## Entry and acceleration: the deck really sinks into the mouth under the podium,
## carrying the finale stage (towers, cast, referee).
func _update_entry() -> void:
	var drop := _descent.entry_drop()
	ResultCeremonyDirector.stage_drop = drop
	_deck_local_y = -drop
	if is_instance_valid(_shaft):
		_shaft.global_position = _podium
		_shaft.set_view(_deck_local_y, 0.0)
		_shaft.set_clip(0.0, -INF)
		_shaft.set_mouth(true, 0.0, 1.0)
		_shaft.set_daylight(1.0 - smoothstep(1.2, 2.4, _descent.t))
	_deck_world = _podium + Vector3(0.0, _deck_local_y, 0.0)
	_set_surface_dusk(maxf(_branch_night, smoothstep(DUSK.x, DUSK.y, _descent.t)))
	# Daylight to darkness on a fixed curve (no auto exposure, docs 5.2).
	_env_base_exposure = lerpf(1.0, ENTRY_END_EXPOSURE, smoothstep(1.0, 2.4, _descent.t))
	if _surface_env != null:
		_surface_env.tonemap_exposure = _env_base_exposure
	_lamp_ticks(drop)
	_set_camera(_descent_path(_descent.t), _descent_path_fov(_descent.t), "A_entry")


## The end of the acceleration, in the middle of the one continuous move: the finale stage hands
## over to the live runners on the deck (pose for pose), the surface goes away and the shaft jumps
## above the cistern with the camera path, so nothing on screen moves.
func _swap_to_underground() -> void:
	_swapped = true
	# The cast as last drawn (the stage was lowered by stage_drop), in deck space.
	var cast_deck := _podium - Vector3(0.0, ResultCeremonyDirector.stage_drop, 0.0)
	var cast_pose := _capture_cast_pose()
	var finale_stage := ceremony.stage() if ceremony != null else null
	var finale_referee := finale_stage.referee_node() if finale_stage != null else null
	if not game_state.begin_sudden_death():
		_begin_abort_now()
		return
	if players != null:
		players.reset_result_presentation()
	ResultCeremonyDirector.stage_drop = 0.0
	if _surface_toggle.is_valid():
		_surface_toggle.call(false)
	_cruise_anchor_deck_y = -SuddenDeathDescent.entry_total()
	_deck_local_y = _cruise_anchor_deck_y
	var shaft_before := _shaft.global_position if is_instance_valid(_shaft) else _podium
	_anchor_for_cruise()
	if is_instance_valid(_shaft):
		_space_offset = _shaft.global_position - shaft_before
	_build_deck_props()
	_place_runners_on_deck()
	if players != null and players.has_method("begin_pose_handoff"):
		var shift := _deck_world - cast_deck
		for player_index: int in cast_pose:
			var pose := {}
			for key: Variant in cast_pose[player_index]:
				var part: Transform3D = cast_pose[player_index][key]
				pose[key] = Transform3D(part.basis, part.origin + shift)
			players.begin_pose_handoff(player_index, pose, CAST_HANDOFF)
	_capture_referee_pose(finale_referee)
	_set_env(_shaft_env_for_quality(), SHAFT_START_EXPOSURE, 1.0, 1.6)
	_audio_call("set_ambience", [&"shaft"])
	if _loader != null:
		_loader.set_presentable(true)
		_loader.set_heavy_work_allowed(true)


## Global transforms of the finale cast's parts (player_index -> {key -> Transform3D}).
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


func _capture_referee_pose(referee: Node3D) -> void:
	_referee_handoff.clear()
	_referee_handoff_time = 0.0
	var skeleton := _first_skeleton(referee)
	if skeleton == null:
		return
	for bone in range(skeleton.get_bone_count()):
		_referee_handoff[bone] = [skeleton.get_bone_pose_position(bone), skeleton.get_bone_pose_rotation(bone),
			skeleton.get_bone_pose_scale(bone)]


static func _first_skeleton(root: Node) -> Skeleton3D:
	if root == null or not is_instance_valid(root):
		return null
	var found := root.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null

func _anchor_for_cruise() -> void:
	if not is_instance_valid(_shaft):
		return
	_shaft.global_position = Vector3(SuddenDeathLayout.LANDING.x,
		SuddenDeathLayout.FLOOR_Y + SuddenDeathLayout.CRUISE_DECK_HEIGHT - _cruise_anchor_deck_y, SuddenDeathLayout.LANDING.z)
	_shaft.set_mouth(false, 0.0, 1.0)
	_shaft.set_daylight(0.0)
	_deck_world = _shaft.global_position + Vector3(0.0, _deck_local_y, 0.0)


func _update_cruise() -> void:
	# Deck and camera stay put; the wall pattern streams past (docs 5.5).
	_scroll = _descent.distance - SuddenDeathDescent.entry_total()
	_deck_local_y = _cruise_anchor_deck_y
	if is_instance_valid(_shaft):
		_shaft.set_view(_deck_local_y, _scroll)
		_shaft.set_clip(_scroll, -INF)
		_shaft.set_depth_signs(_depth_signs())
	_deck_world = _shaft.global_position + Vector3(0.0, _deck_local_y, 0.0) if is_instance_valid(_shaft) else SuddenDeathLayout.LANDING
	_place_runners_on_deck()
	_pose_deck_referee()
	_lamp_ticks(_scroll + 6.2)
	_audio_call("set_depth_reverb", [clampf(_descent.display_depth / SuddenDeathDescent.DISPLAY_FINAL, 0.0, 1.0)])
	var down := _descent.shot == SuddenDeathDescent.Shot.DOWN
	var shot := "C_down" if down else "B_cruise"
	if _descent.is_aborting():
		shot = "B_cruise"
	if not down and _descent.t < PATH_END:
		# Still settling behind the runners at the end of the move from the podium.
		_set_camera(_descent_path(_descent.t), _descent_path_fov(_descent.t), shot)
		return
	_set_camera(_down_shot() if down else _cruise_shot(), 64.0 if down else 60.0, shot)


## Decel and arrival move the deck for real: the shaft is placed so that the
## remaining descent ends exactly at the cistern ceiling, then the floor.
func _anchor_for_arrival() -> void:
	_arrival_anchored = true
	_arrival_start_distance = _descent.distance
	_row_lights_on = 0
	var cistern := _cistern()
	if cistern != null:
		cistern.visible = true
		cistern.set_all_rows(0.0)
	if not is_instance_valid(_shaft):
		return
	# Whatever is left of the deceleration ends exactly at the ceiling opening.
	_deck_local_y = _cruise_anchor_deck_y
	_shaft.global_position = Vector3(SuddenDeathLayout.LANDING.x,
		SuddenDeathLayout.ceiling_bottom_y() + _descent.remaining_decel() - _deck_local_y, SuddenDeathLayout.LANDING.z)


func _update_arrival() -> void:
	var anchor := _shaft.global_position if is_instance_valid(_shaft) else Vector3(0.0, SuddenDeathLayout.ceiling_bottom_y(), 0.0)
	var deck_top: float
	if _descent.stage == SuddenDeathDescent.Stage.DECEL:
		_deck_local_y = _cruise_anchor_deck_y - (_descent.distance - _arrival_start_distance)
		deck_top = anchor.y + _deck_local_y
	else:
		deck_top = SuddenDeathLayout.ceiling_bottom_y() - _descent.arrival_drop()
		_deck_local_y = deck_top - anchor.y
	if is_instance_valid(_shaft):
		_shaft.set_view(_deck_local_y, _scroll)
		_shaft.set_clip(INF, SuddenDeathLayout.ceiling_top_y() - anchor.y)
		_shaft.set_depth_signs([])
	_deck_world = Vector3(anchor.x, deck_top, anchor.z)
	_place_runners_on_deck()
	_pose_deck_referee()
	if _descent.stage == SuddenDeathDescent.Stage.DECEL:
		_set_camera(_cruise_shot(), 60.0, "B_cruise")
		return
	var arrival_time := SuddenDeathDescent.ARRIVAL_TIME if _descent.is_landed() else _descent.stage_time
	var u := arrival_time / SuddenDeathDescent.ARRIVAL_TIME
	_update_row_lights(arrival_time)
	_set_camera(_arrival_shot(u), lerpf(60.0, 58.0, u), "D_arrival")


func _update_row_lights(arrival_time: float) -> void:
	var cistern := _cistern()
	if cistern == null:
		return
	var lit := 0.0
	for row in range(cistern.row_count()):
		var on_at := LIGHTS_START + LIGHTS_STEP * float(row)
		var local := arrival_time - on_at
		var amount := 0.0
		if local >= 0.0:
			# Contactor clunk, a brief flicker, then full.
			amount = 1.0 if local > LIGHT_FLICKER * 2.0 else (0.75 if fmod(local, LIGHT_FLICKER) < LIGHT_FLICKER * 0.5 else 0.25)
			if row >= _row_lights_on:
				_row_lights_on = row + 1
				var position_value := Vector3(0.0, SuddenDeathLayout.FLOOR_Y + 7.0, cistern.light_row_z(row))
				_audio_call("play_at", [&"light_on", position_value, -2.0 - 1.4 * float(row), 1.0 - 0.015 * float(row)])
		cistern.set_row_brightness(row, amount)
		lit += amount
	if _hall_env != null:
		CisternStage.apply_hall_light(_hall_env, lit / maxf(float(cistern.row_count()), 1.0))


# ------------------------------------------------------------------ landing and intro (2.2)

func _begin_intro() -> void:
	_act = Act.INTRO
	game_state.sudden_death_preparing_panel = ""
	_act_time = 0.0
	_landed_time = 0.0
	_update_row_lights(SuddenDeathDescent.ARRIVAL_TIME + 5.0)
	_rules_shown_at = -1.0
	_rules_confirmed = false
	_countdown_at = INF
	_flood_at = INF
	_deck_rise_from = -1.0
	_play(&"landing")
	_audio_call("set_motor", [false, 0.0])
	_capture_camera()
	if _loader != null:
		_loader.set_heavy_work_allowed(true)


func _update_intro() -> void:
	_act_time += _real_dt
	var t := _act_time
	var cistern := _cistern()
	if cistern != null:
		cistern.update_runtime(_real_dt, game_state.sudden_death)
	if _cue("shout", t >= INTRO_SHOUT):
		_hud_call("show_shout", ["SUDDEN DEATH!" if game_state.use_english_ui else "サドンデス！"])
		_play(&"shout_echo")
		_play(&"whistle", -3.0)
	# Both step off their pads and walk to their own lift tower, then the towers lift them.
	var walk := smoothstep(INTRO_WALK.x, INTRO_WALK.y, t)
	game_state.sudden_death_walk_mask = 3 if t >= INTRO_WALK.x and t < INTRO_WALK.y else 0
	for player_index in [1, 2]:
		var pad := Vector3(SuddenDeathLayout.PAD_X * (1.0 if player_index == 1 else -1.0), 0.0, 0.0)
		var tower := SuddenDeathLayout.lift_position(player_index)
		var at := pad.lerp(Vector3(tower.x, 0.0, tower.z), walk)
		game_state.place_sudden_death_runner(player_index, at.x, at.z)
	if _cue("rise", t >= INTRO_RISE) and cistern != null:
		var start := game_state.sudden_death.tuning.lift_height(game_state.sudden_death.tuning.start_margin)
		for player_index in [1, 2]:
			cistern.set_tower_target(player_index, start, INTRO_RISE_SPEED)
		_play(&"deck_release", -3.0, 1.1)
		_deck_rise_from = t
		_deck_rise_elapsed = 0.0
	_place_runners_on_towers(walk)
	_pose_deck_referee()
	if _cue("gate", t >= INTRO_GATE):
		_flood_at = t
		_play(&"whistle", -2.0, 0.95)
		if cistern != null:
			cistern.start_flood()
			var tunnel := Vector3(0.0, SuddenDeathLayout.TUNNEL_CENTER_Y, SuddenDeathLayout.HALL_START_Z)
			_audio_call("play_at", [&"gate_open", tunnel, 2.0])
			_audio_call("play_at", [&"flood_burst", tunnel, 3.0])
	if cistern != null and _flood_at < INF:
		cistern.set_inflow_gate(smoothstep(0.0, 1.2, t - _flood_at))
	if _cue("rules", t >= INTRO_RULES):
		_rules_shown_at = t
		_hud_call("show_rule_card", [INF])
	if _rules_confirmed and t >= _countdown_at and _cue("countdown", true):
		game_state.start_sudden_death_countdown()
		_hud_call("set_countdown", ["3"])
		if cistern != null:
			cistern.set_focus(true)
	_update_intro_deck()
	_update_countdown_hud()
	# Camera: settle from the arrival, follow the walk from behind, cut to the tunnel as the flood bursts out,
	# cut back low in front of the towers as they lift the players, then the duel shot (held through the
	# rules and the countdown) with the flood running in under them.
	var arrival := _blend(_camera_from, _arrival_shot(1.0), smoothstep(0.0, 0.6, t))
	if t < INTRO_WALK.x + 0.4:
		_set_camera(arrival, 58.0, "intro")
	elif t < INTRO_GATE:
		var walk_u := smoothstep(INTRO_WALK.x + 0.4, INTRO_GATE, t)
		_set_camera(_blend(arrival, _walk_shot(), walk_u), lerpf(58.0, 52.0, walk_u), "intro_walk")
	elif t < INTRO_GATE + INFLOW_SHOT - TUNNEL_SHOT_CUT_OUT:
		_set_camera(_tunnel_shot(t - INTRO_GATE), 50.0, "intro_tunnel")
	elif t < INTRO_DUEL:
		var duel_u := smoothstep(INTRO_DUEL - 1.0, INTRO_DUEL, t)
		_set_camera(_blend(_rise_shot(), duel_wide_shot(), duel_u), lerpf(52.0, DUEL_FOV, duel_u), "intro_rise")
	else:
		_set_camera(duel_wide_shot(), DUEL_FOV, "intro_duel")
	var sd := game_state.sudden_death
	if sd != null and sd.phase not in [SuddenDeathState.Phase.INTRO, SuddenDeathState.Phase.COUNTDOWN]:
		_begin_run()


## Enter on the rule card (GameWorld forwards the key): the card leaves and the countdown starts once the
## flood has reached the towers. Returns true when the key was taken.
func confirm_rules() -> bool:
	if _act != Act.INTRO or _rules_confirmed or _rules_shown_at < 0.0:
		return false
	if _act_time - _rules_shown_at < RULES_MIN_READ:
		return false
	_rules_confirmed = true
	_countdown_at = maxf(_act_time, _flood_at + FLOOD_LEAD) if _flood_at < INF else _act_time
	_hud_call("dismiss_rule_card", [])
	return true


## The players stand on their towers once they have walked onto them (walk 1): their avatars ride the
## platforms (presentation lift) and turn round to face the duel camera upstream.
func _place_runners_on_towers(walk: float) -> void:
	var cistern := _cistern()
	var lift := Vector2.ZERO
	if _act == Act.INTRO:
		game_state.sudden_death_facing = PI * smoothstep(0.0, 1.0, (_act_time - INTRO_WALK.y) / 0.5)
	else:
		game_state.sudden_death_facing = PI if walk >= 1.0 else 0.0
	if cistern != null and walk >= 1.0:
		lift = Vector2(cistern.tower_height(1), cistern.tower_height(2))
		for player_index in [1, 2]:
			if not game_state.is_flood_caught(player_index):
				var tower := cistern.tower_position(player_index)
				game_state.place_sudden_death_runner(player_index, tower.x, tower.z)
	game_state.sudden_death_lift = lift


## After the gate opens the deck takes the referee and both tower bases back up.
func _update_intro_deck() -> void:
	if not is_instance_valid(_shaft) or not _shaft.visible:
		return
	var rise := 0.0
	if _deck_rise_elapsed >= 0.0:
		_deck_rise_elapsed += _real_dt
		var u := clampf(_deck_rise_elapsed / DECK_RISE_TIME, 0.0, 1.0)
		rise = (u * u * (3.0 - 2.0 * u)) * (SuddenDeathLayout.HALL_HEIGHT + 2.5)
	var anchor := _shaft.global_position
	var deck_top := SuddenDeathLayout.FLOOR_Y + rise
	_deck_local_y = deck_top - anchor.y
	_deck_world = Vector3(anchor.x, deck_top, anchor.z)
	_shaft.set_view(_deck_local_y, _scroll)
	_shaft.set_clip(INF, SuddenDeathLayout.ceiling_top_y() - anchor.y)
	_shaft.set_motion_speed(-1.0 if rise > 0.0 and rise < SuddenDeathLayout.HALL_HEIGHT else 0.0)
	if rise >= SuddenDeathLayout.HALL_HEIGHT + 2.0:
		_shaft.visible = false


func _update_countdown_hud() -> void:
	var sd := game_state.sudden_death
	if sd == null or sd.phase != SuddenDeathState.Phase.COUNTDOWN:
		return
	var step := sd.tuning.countdown / 3.0
	_hud_call("set_countdown", [str(clampi(int(ceil(sd.countdown_remaining() / step)), 1, 3))])


# ------------------------------------------------------------------ run (the buzzer duel)

func _begin_run() -> void:
	_act = Act.RUN
	_act_time = 0.0
	_last_tick = -1
	_capture_camera()
	_run_pose = _camera_from
	_run_fov = _camera_from_fov
	_hud_call("set_letterbox", [0.0])
	if _loader != null:
		_loader.set_heavy_work_allowed(false)


func _update_run(delta: float) -> void:
	_act_time += _real_dt
	var sd := game_state.sudden_death
	if game_state.game_state != Constants.STATE_SUDDEN_DEATH or sd == null:
		return
	var cistern := _cistern()
	if cistern != null:
		for player_index in [1, 2]:
			cistern.set_tower_target(player_index, sd.lift_target(player_index))
			var lit: bool = sd.phase == SuddenDeathState.Phase.ANSWERING and sd.buzzer == player_index
			cistern.set_tower_glow(player_index, 1.0 if lit else 0.0)
		cistern.update_runtime(delta, sd)
	_update_intro_deck()
	_place_runners_on_towers(1.0)
	_hud_call("set_quiz", [_quiz_state(sd)])
	_update_countdown_hud()
	_timer_ticks(sd)
	_update_duel_camera(sd)
	if sd.phase == SuddenDeathState.Phase.DECIDED and _act == Act.RUN:
		_begin_return(sd.winner)


## What the HUD shows of the current question ({} between questions).
func _quiz_state(sd: SuddenDeathState) -> Dictionary:
	var quiz := sd.current_quiz()
	if quiz == null:
		return {}
	var phase := ""
	match sd.phase:
		SuddenDeathState.Phase.QUESTION:
			phase = "intro"
		SuddenDeathState.Phase.READING:
			phase = "reading"
		SuddenDeathState.Phase.ANSWERING:
			phase = "answering"
		_:
			phase = "result"
	var count := quiz.c.size()
	var keys: Array = []
	for index in range(count):
		keys.append(QuizGameState.sudden_death_key_for_choice(index, count))
	var timer := 1.0
	var mode := ""
	if sd.phase == SuddenDeathState.Phase.READING:
		mode = "think"
		timer = sd.think_fraction() if sd.is_fully_revealed() else 1.0
	elif sd.phase == SuddenDeathState.Phase.ANSWERING:
		mode = "answer"
		timer = sd.answer_fraction()
	var revealed := sd.revealed_count()
	return {
		"number": sd.question_index + 1, "text": quiz.q, "revealed": revealed, "choices": quiz.c, "keys": keys,
		"phase": phase, "timer": timer, "timer_mode": mode, "buzzer": sd.buzzer,
		"chosen": sd.answer if phase == "result" else -1, "answer": quiz.a if phase == "result" else -1,
		"result": sd.result if phase == "result" else "",
		"margins": [maxi(sd.margin[0], 0), maxi(sd.margin[1], 0)], "max_margin": sd.tuning.start_margin,
	}


## A tick for each of the last three seconds to think or to answer.
func _timer_ticks(sd: SuddenDeathState) -> void:
	var remaining := INF
	if sd.phase == SuddenDeathState.Phase.READING and sd.is_fully_revealed():
		remaining = sd.reading_remaining()
	elif sd.phase == SuddenDeathState.Phase.ANSWERING:
		remaining = sd.tuning.answer_time * sd.answer_fraction()
	if not is_finite(remaining) or remaining > 3.0:
		_last_tick = -1
		return
	var second := int(ceil(remaining))
	if second != _last_tick and second > 0:
		_last_tick = second
		_play(&"tick", -2.0, 1.0 + 0.08 * float(3 - second))


## The duel shot, leaning toward whoever buzzed, then toward a tower that sinks.
func _update_duel_camera(sd: SuddenDeathState) -> void:
	var cistern := _cistern()
	var target := duel_wide_shot()
	var fov := DUEL_FOV
	var shot := "duel"
	if cistern != null:
		if sd.phase == SuddenDeathState.Phase.ANSWERING and sd.buzzer > 0:
			target = _blend(target, _tower_shot(sd.buzzer, 1.4, 8.5), 0.38)
			fov = 46.0
			shot = "duel_buzz"
		elif sd.phase == SuddenDeathState.Phase.RESULT and sd.phase_time < SINK_LOOK:
			var sinking := _sinking_player(sd)
			if sinking > 0:
				target = _blend(target, _tower_shot(sinking, 0.2, 7.0), 0.28)
				fov = 48.0
				shot = "duel_sink"
	var follow := 1.0 - exp(-DUEL_FOLLOW * _real_dt)
	_run_pose = _blend(_run_pose, target, follow)
	_run_fov = lerpf(_run_fov, fov, follow)
	var clock := float(Time.get_ticks_msec()) / 1000.0
	var pose := _run_pose
	# A slow breath of the handheld lens.
	pose.basis = pose.basis * Basis(Vector3.FORWARD, deg_to_rad(0.25) * sin(clock * TAU * 0.13)) \
		* Basis(Vector3.RIGHT, deg_to_rad(0.18) * sin(clock * TAU * 0.09 + 1.3))
	_set_camera(pose, _run_fov, shot)


## The player whose tower this result sends down (one at most; 0 for none or both after a time-out).
func _sinking_player(sd: SuddenDeathState) -> int:
	if sd.result == "correct":
		return 3 - sd.buzzer
	if sd.result in ["wrong", "late"]:
		return sd.buzzer
	return 0


# ------------------------------------------------------------------ return (2.3)

func _begin_return(winner: int) -> void:
	if winner <= 0:
		return
	_act = Act.RETURN
	_act_time = 0.0
	_winner = winner
	_loser = 3 - winner
	_return_stage = "slowmo"
	_stage_time = 0.0
	_caught_at = -1.0
	Engine.time_scale = SLOWMO_SCALE
	_play(&"slowmo")
	_capture_camera()
	var cistern := _cistern()
	if cistern != null:
		# The loser's tower drops into the water.
		cistern.set_tower_target(_loser, game_state.sudden_death.tuning.sunk_height(), CisternStage.PLUNGE_SPEED)
		cistern.set_tower_glow(_loser, 0.0)
	_audio_call("play_at", [&"deck_stop", _runner_world(_loser), 2.0, 0.7])


func _update_return() -> void:
	_act_time += _real_dt
	_stage_time += _real_dt
	var cistern := _cistern()
	var sd := game_state.sudden_death
	if cistern != null and sd != null and cistern.visible:
		cistern.update_runtime(_game_dt, sd)
	match _return_stage:
		"slowmo":
			_update_slowmo()
		"pickup":
			_update_pickup()
		"ascent":
			_update_ascent()
		"surface":
			_update_surface()


func _update_slowmo() -> void:
	var sd := game_state.sudden_death
	var cistern := _cistern()
	if cistern != null:
		# The winner stays up there; the loser rides the tower down until the water takes them.
		var lift := Vector2(cistern.tower_height(1), cistern.tower_height(2))
		game_state.sudden_death_lift = lift
		var tower := cistern.tower_position(_winner)
		game_state.place_sudden_death_runner(_winner, tower.x, tower.z)
		if sd != null and not sd.caught[_loser - 1]:
			var sunk := cistern.tower_position(_loser)
			game_state.place_sudden_death_runner(_loser, sunk.x, sunk.z)
	if sd != null:
		_hud_call("set_quiz", [_quiz_state(sd)])
	# Low over the water by the loser's tower, the winner's tower standing beyond.
	_set_camera(_blend(_camera_from, _plunge_shot(), smoothstep(0.0, 0.4, _stage_time)), 52.0, "R_plunge")
	var swallowed := sd == null or _loser <= 0 or bool(sd.caught[_loser - 1])
	if swallowed and _caught_at < 0.0:
		_caught_at = _stage_time
	var done := _stage_time >= SLOWMO_TIME and swallowed and _stage_time - _caught_at >= SLOWMO_AFTER_CATCH
	if done or _stage_time >= SLOWMO_MAX:
		Engine.time_scale = 1.0
		_return_stage = "pickup"
		_stage_time = 0.0
		_begin_pickup()


## The deck comes down out of the dark ceiling beside the winner's tower, level with its platform.
func _begin_pickup() -> void:
	_hud_call("set_quiz", [{}])
	_hud_call("show_winner", [_winner])
	_play(&"win_sting")
	game_state.sudden_death_presentation_lock = true
	var cistern := _cistern()
	if not is_instance_valid(_shaft) or cistern == null:
		_build_deck_props()
		_begin_ascent()
		return
	var tower := cistern.tower_position(_winner)
	var pad_x := SuddenDeathLayout.PAD_X * (1.0 if _winner == 1 else -1.0)
	_pickup_height = cistern.tower_height(_winner)
	_winner_from = Vector3(tower.x, 0.0, tower.z)
	_pickup_center = Vector3(tower.x - pad_x, 0.0,
		tower.z + (SuddenDeathLayout.DECK_RADIUS + SuddenDeathLayout.LIFT_RADIUS + PICKUP_CLEARANCE))
	_capture_camera()
	_build_deck_props()
	_shaft.visible = true
	_shaft.global_position = Vector3(_pickup_center.x, SuddenDeathLayout.FLOOR_Y, _pickup_center.z)
	_shaft.set_clip(INF, INF)
	_shaft.set_mouth(false, 0.0, 1.0)
	_shaft.set_daylight(0.0)
	_shaft.set_depth_signs([])
	_audio_call("set_motor", [true, 6.0])


func _update_pickup() -> void:
	var t := _stage_time
	var pad_x := SuddenDeathLayout.PAD_X * (1.0 if _winner == 1 else -1.0)
	var pad := _pickup_center + Vector3(pad_x, 0.0, 0.0)
	# The deck comes down out of the dark to the platform's height.
	var down := smoothstep(PICKUP_DECK.x, PICKUP_DECK.y, t)
	var deck_height := lerpf(PICKUP_DECK_HEIGHT, _pickup_height, down)
	var lift_off := 0.0
	var run_start := PICKUP_DECK.y - 0.15
	var run_time := maxf(0.4, _winner_from.distance_to(pad) / PICKUP_RUN_SPEED)
	var lift_start := run_start + run_time + 0.15
	if t >= lift_start:
		var u := clampf((t - lift_start) / LIFT_OFF_TIME, 0.0, 1.0)
		lift_off = u * u * LIFT_OFF_HEIGHT
	if _cue("pickup_land", t >= PICKUP_DECK.y):
		_play(&"deck_stop", -2.0)
		_audio_call("set_motor", [false, 0.0])
	if _cue("pickup_lift", t >= lift_start):
		_play(&"deck_release", -3.0)
		_audio_call("set_motor", [true, 8.0])
	var deck_top := SuddenDeathLayout.FLOOR_Y + deck_height + lift_off
	_deck_world = Vector3(_pickup_center.x, deck_top, _pickup_center.z)
	if is_instance_valid(_shaft):
		_shaft.global_position = Vector3(_pickup_center.x, SuddenDeathLayout.FLOOR_Y, _pickup_center.z)
		_deck_local_y = deck_top - SuddenDeathLayout.FLOOR_Y
		_shaft.set_view(_deck_local_y, 0.0)
		_shaft.set_clip(INF, INF)
		_shaft.set_motion_speed(-3.0 if lift_off > 0.0 else (2.0 if down < 1.0 else 0.0))
	_pose_deck_referee()
	# The winner turns from the camera and walks off the platform onto their own pad of the deck (downstream).
	var run := clampf((t - run_start) / run_time, 0.0, 1.0)
	var position_value := _winner_from.lerp(pad, run * run * (3.0 - 2.0 * run)) if t >= run_start else _winner_from
	game_state.place_sudden_death_runner(_winner, position_value.x, position_value.z)
	game_state.sudden_death_walk_mask = (1 if _winner == 1 else 2) if t >= run_start and run < 1.0 else 0
	game_state.sudden_death_facing = 0.0 if t >= run_start else PI
	var on_deck := smoothstep(0.75, 1.0, run)
	var lift := lerpf(_pickup_height, deck_height + lift_off + SuddenDeathLayout.PAD_TOP, on_deck)
	if _winner == 1:
		game_state.sudden_death_lift.x = lift
	else:
		game_state.sudden_death_lift.y = lift
	# Camera: upstream of the tower, looking down the hall at the winner stepping onto the deck.
	var tower_top := SuddenDeathLayout.FLOOR_Y + _pickup_height
	var eye := Vector3(_winner_from.x * 0.4, tower_top + 2.6 + lift_off * 0.5, _winner_from.z - 8.0)
	var look_height := tower_top + 1.2 + lift_off + clampf(deck_height - _pickup_height, 0.0, 8.0) * 0.35
	var target := Vector3(lerpf(_winner_from.x, pad.x, 0.5), look_height, lerpf(_winner_from.z, _pickup_center.z, 0.55))
	_set_camera(_blend(_camera_from, _look(eye, target), smoothstep(0.0, 0.6, t)), 54.0, "R_pickup")
	if t >= lift_start + LIFT_OFF_TIME:
		_begin_ascent()


func _begin_ascent() -> void:
	_return_stage = "ascent"
	_stage_time = 0.0
	_cruise_anchor_deck_y = -SuddenDeathDescent.SURFACE_DROP
	_deck_local_y = _cruise_anchor_deck_y
	_ascent_scroll = 0.0
	if is_instance_valid(_shaft):
		_shaft.global_position = Vector3(SuddenDeathLayout.LANDING.x,
			SuddenDeathLayout.FLOOR_Y + SuddenDeathLayout.CRUISE_DECK_HEIGHT - _deck_local_y, SuddenDeathLayout.LANDING.z)
	var cistern := _cistern()
	if cistern != null:
		cistern.visible = false
	game_state.sudden_death_walk_mask = 0
	_set_env(_shaft_env_for_quality(), 0.7, 1.0, 0.8)
	_audio_call("set_ambience", [&"shaft"])
	_audio_call("set_depth_reverb", [1.0])
	_hud_call("set_letterbox", [1.0])
	_camera_shot = ""


func _update_ascent() -> void:
	var t := _stage_time
	var speed := ASCENT_SPEED * smoothstep(0.0, 0.5, t) * (1.0 - 0.6 * smoothstep(ASCENT_TIME - 0.6, ASCENT_TIME, t))
	_ascent_scroll -= speed * _real_dt
	if is_instance_valid(_shaft):
		_shaft.set_view(_deck_local_y, _ascent_scroll)
		_shaft.set_clip(INF, -INF)
		_shaft.set_motion_speed(-speed)
		_deck_world = _shaft.global_position + Vector3(0.0, _deck_local_y, 0.0)
	_place_winner_on_deck()
	_pose_deck_referee()
	var display := SuddenDeathDescent.DISPLAY_FINAL * (1.0 - smoothstep(0.0, ASCENT_TIME, t))
	_lamp_ticks(-_ascent_scroll)
	_audio_call("set_motor", [true, speed * 0.45])
	_audio_call("set_depth_reverb", [display / SuddenDeathDescent.DISPLAY_FINAL])
	_set_camera(_ascent_shot(), 60.0, "R_ascent")
	if t >= ASCENT_TIME:
		_begin_surface_return()


## The cut back to daylight: the ceremony resumes (held at the verdict) with the
## winner, and the deck rises the last metres out of the mouth.
func _begin_surface_return() -> void:
	_return_stage = "surface"
	_stage_time = 0.0
	if players != null:
		players.reset_result_presentation()
	game_state.end_sudden_death(true)
	_finish_underground()
	_after_surface_cut()
	_hud_call("hide_all", [false])
	if ceremony != null:
		ceremony.allow_egg_target = false
	_ensure_drain()
	_drain.place(_podium, 1 if _loser == 1 else -1)
	_flight_from = _drain.mouth_position()
	_update_surface_deck(0.0)
	_surface_camera(0.0, SURFACE_CAMERA_MATCH, QuizGameState.RESULT_VERDICT_TIME)


func _update_surface() -> void:
	var t := _stage_time
	_update_surface_deck(t)
	game_state.result_return_regrow = smoothstep(SURFACE_REGROW.x, SURFACE_REGROW.y, t)
	if _cue("regrow", t >= SURFACE_REGROW.x):
		AudioManager.play_result_cue(&"climb")
	var stage := ceremony.stage() if ceremony != null else null
	if stage != null:
		var flight := -1.0
		if t >= SURFACE_DRAIN:
			flight = clampf((t - SURFACE_DRAIN) / DRAIN_FLIGHT, 0.0, 1.0)
		stage.set_actor_flight(_loser, _flight_from, flight)
	if _cue("drain", t >= SURFACE_DRAIN):
		if _drain != null:
			_drain.erupt()
		_play(&"drain_burst")
		game_state.camera_shake = maxf(game_state.camera_shake, 0.25)
	if _cue("loser_land", t >= SURFACE_DRAIN + DRAIN_FLIGHT):
		_play(&"landing", -4.0, 1.3)
		AudioManager.play_result_cue(&"sad", 1.0, -3.0)
		# The stand roars at the soaked loser (docs 2.3: 観客が笑って卵を投げる).
		AudioManager.play_crowd_cue(&"cheer", -5.0, 1.12)
		if ceremony != null:
			ceremony.allow_egg_target = true
	_surface_camera(t, SURFACE_CAMERA_MATCH, QuizGameState.RESULT_VERDICT_TIME)
	if t >= SURFACE_RELEASE:
		_release_ceremony()


func _update_surface_deck(t: float) -> void:
	var rise := smoothstep(0.0, SURFACE_RISE, t)
	var drop := SuddenDeathDescent.SURFACE_DROP * (1.0 - (1.0 - pow(1.0 - rise, 2.0)))
	ResultCeremonyDirector.stage_drop = drop
	if is_instance_valid(_shaft):
		_shaft.global_position = _podium
		_shaft.set_view(-drop, 0.0)
		_shaft.set_clip(0.0, -INF)
		_shaft.set_mouth(true, 0.0, 1.0 - smoothstep(SURFACE_IRIS_CLOSE.x, SURFACE_IRIS_CLOSE.y, t))
		_shaft.set_daylight(1.0)
		_shaft.set_motion_speed(-8.0 * (1.0 - rise))
	if _cue("surface_stop", t >= SURFACE_RISE):
		_play(&"deck_stop", -2.0)
		_audio_call("set_motor", [false, 0.0])
	if _cue("iris_close", t >= SURFACE_IRIS_CLOSE.x):
		_play(&"iris_close")


## Daylight: a high shot over the mouth, then match the finale lens before handing back.
func _surface_camera(t: float, match_window: Vector2, ceremony_time: float) -> void:
	var shot := _look(_podium + Vector3(0.0, 6.2, -10.8), _podium + Vector3(0.0, 1.1, 0.6))
	var fov := 52.0
	if _act == Act.RETURN and _loser > 0:
		# Swing toward the loser's side for the drain column, then back.
		var side := 1.0 if _loser == 1 else -1.0
		var drain := smoothstep(SURFACE_DRAIN - 0.45, SURFACE_DRAIN - 0.05, t) * (1.0 - smoothstep(SURFACE_DRAIN + DRAIN_FLIGHT + 0.3, SURFACE_DRAIN + DRAIN_FLIGHT + 0.9, t))
		var wide := _look(_podium + Vector3(side * 1.5, 5.4, -13.5), _podium + Vector3(side * 4.2, 3.0, 0.4))
		shot = _blend(shot, wide, drain)
		fov = lerpf(fov, 60.0, drain)
	if camera_controller != null and camera_controller.has_method("result_ceremony_camera_pose"):
		var finale: Dictionary = camera_controller.result_ceremony_camera_pose(game_state, ceremony_time)
		var u := smoothstep(match_window.x, match_window.y, t)
		shot = _blend(shot, finale.transform, u)
		fov = lerpf(fov, float(finale.fov), u)
	_set_camera(shot, fov, "R_surface")


func _release_ceremony() -> void:
	game_state.release_result_return_hold()
	if ceremony != null:
		ceremony.allow_egg_target = true
		var stage := ceremony.stage()
		if stage != null:
			stage.clear_actor_flights()
	ResultCeremonyDirector.stage_drop = 0.0
	if camera_controller != null:
		camera_controller.clear_director_pose()
	_restore_surface_env()
	_hud_call("hide_all", [false])
	_audio_call("stop_all", [])
	if is_instance_valid(_shaft):
		_shaft.set_beacons(false)
		_shaft.set_mouth(true, 0.0, 0.0)
	_act = Act.DONE


# ------------------------------------------------------------------ abort (5.2)

func _begin_abort_now() -> void:
	# begin_sudden_death() refused: go straight back to the draw.
	game_state.abort_sudden_death(false)
	_finish_underground()
	if _surface_toggle.is_valid():
		_surface_toggle.call(true)
	_release_abort()


func _begin_abort_surface() -> void:
	game_state.sudden_death_preparing_panel = ""
	if players != null:
		players.reset_result_presentation()
	game_state.abort_sudden_death(true)
	_finish_underground()
	_after_surface_cut()
	_act = Act.ABORT
	_act_time = 0.0
	_stage_time = 0.0


## Back on the surface after a failed descent: the deck rises out of the mouth
## (the descent's own ABORT_SURFACE curve), both towers grow back, the draw ends.
func _update_abort_surface() -> void:
	pass


func _update_abort() -> void:
	_stage_time += _real_dt
	var t := _stage_time
	if _descent.stage == SuddenDeathDescent.Stage.ABORT_SURFACE:
		_descent.advance(_real_dt)
	var drop := _descent.entry_drop()
	ResultCeremonyDirector.stage_drop = drop
	if is_instance_valid(_shaft):
		_shaft.global_position = _podium
		_shaft.set_view(-drop, 0.0)
		_shaft.set_clip(0.0, -INF)
		_shaft.set_mouth(true, 0.0, 1.0 - smoothstep(SuddenDeathDescent.SURFACE_TIME, SuddenDeathDescent.SURFACE_TIME + 0.4, t))
		_shaft.set_daylight(1.0)
	var regrow_from := SuddenDeathDescent.SURFACE_TIME
	game_state.result_return_regrow = smoothstep(regrow_from + ABORT_REGROW.x, regrow_from + ABORT_REGROW.y, t)
	if _cue("abort_stop", drop <= 0.001):
		_play(&"deck_stop", -2.0)
		_audio_call("set_motor", [false, 0.0])
	if _cue("abort_regrow", t >= regrow_from + ABORT_REGROW.x):
		AudioManager.play_result_cue(&"climb")
	_surface_camera(t, Vector2(regrow_from + ABORT_RELEASE - 0.8, regrow_from + ABORT_RELEASE),
		QuizGameState.SUDDEN_DEATH_ABORT_RESUME_TIME)
	if t >= regrow_from + ABORT_RELEASE:
		_release_abort()


func _release_abort() -> void:
	game_state.release_result_return_hold()
	ResultCeremonyDirector.stage_drop = 0.0
	if camera_controller != null:
		camera_controller.clear_director_pose()
	_restore_surface_env()
	_hud_call("hide_all", [false])
	_audio_call("stop_all", [])
	if is_instance_valid(_shaft):
		_shaft.set_beacons(false)
		_shaft.set_mouth(true, 0.0, 0.0)
	_act = Act.DONE


## Shared by the return and the abort at the cut back to daylight.
func _after_surface_cut() -> void:
	if _surface_toggle.is_valid():
		_surface_toggle.call(true)
	if stage_env != null and stage_env.has_method("set_shaft_hole"):
		stage_env.set_shaft_hole(_podium, SuddenDeathLayout.SHAFT_RADIUS, true)
	_free_deck_props()
	_surface_env = _duplicate_surface_env()
	_set_env(_surface_env, 2.0, 1.0, 1.3)
	_audio_call("set_ambience", [&"none"])
	_audio_call("set_depth_reverb", [0.0])
	_audio_call("set_motor", [true, 5.0])
	_hud_call("set_letterbox", [0.0])
	if is_instance_valid(_shaft):
		_shaft.visible = true
		_shaft.global_position = _podium
		_shaft.set_beacons(true)
		_shaft.set_depth_signs([])
	_capture_camera()


func _finish_underground() -> void:
	Engine.time_scale = 1.0
	game_state.sudden_death_walk_mask = 0
	if _loader != null:
		_loader.cancel()
		_loader.queue_free()
		_loader = null


# ------------------------------------------------------------------ deck riders

## Built once with the match (hidden) so the cut into the shaft does not instantiate
## the towers and the referee; shown only while they ride the deck.
func _build_deck_props() -> void:
	if not is_instance_valid(_shaft):
		return
	if is_instance_valid(_deck_props):
		_deck_props.visible = true
		return
	var deck := _shaft.get_deck()
	if deck == null:
		return
	_deck_props = Node3D.new()
	_deck_props.name = "DeckRiders"
	deck.add_child(_deck_props)
	_deck_towers.clear()
	for player_index in [1, 2]:
		var built := ResultFinaleStage.create_tower(player_index, _deck_props)
		var root := built.root as Node3D
		root.position = Vector3(SuddenDeathLayout.PAD_X * (1.0 if player_index == 1 else -1.0), 0.0, 0.0)
		var lift := built.lift as Node3D
		lift.position.y = SuddenDeathLayout.PAD_TOP
		# Sunk into the deck: the tier column would hang below it.
		var column := lift.find_child("TierColumn", true, false) as Node3D
		if column != null:
			column.visible = false
		_deck_towers[player_index] = built
	# A weak neutral fill so the riders keep their own colours under the sodium lamps
	# (docs 6.5: 人物の見やすさのための弱い補助光).
	var fill := OmniLight3D.new()
	fill.name = "RiderFill"
	fill.light_color = Color(0.86, 0.92, 1.0)
	fill.light_energy = 1.8
	fill.light_specular = 0.2
	fill.omni_range = 9.0
	fill.omni_attenuation = 1.1
	fill.shadow_enabled = false
	fill.position = Vector3(0.0, 4.2, -3.2)
	_deck_props.add_child(fill)
	var referee := ResultFinaleReferee.create(_deck_props, "DeckReferee")
	_deck_referee = referee.root
	_deck_referee_animation = referee.animation
	# Same relation to the runners as on the podium (the rig carries the 1 m offset).
	_deck_referee.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)


## Back on the surface the finale stage's own towers and referee take over.
func _free_deck_props() -> void:
	if is_instance_valid(_deck_props):
		_deck_props.visible = false


func _pose_deck_referee() -> void:
	if is_instance_valid(_deck_referee_animation):
		ResultFinaleReferee.pose_idle(_deck_referee_animation, _act_time + _stage_time)
	if _referee_handoff.is_empty():
		return
	# From the finale referee's last pose into the idle sway (same rig, bone for bone).
	var weight := smoothstep(0.0, 1.0, _referee_handoff_time / CAST_HANDOFF)
	_referee_handoff_time += _real_dt
	var skeleton := _first_skeleton(_deck_referee)
	if skeleton != null:
		for bone: int in _referee_handoff:
			if bone >= skeleton.get_bone_count():
				continue
			var from: Array = _referee_handoff[bone]
			skeleton.set_bone_pose_position(bone, (from[0] as Vector3).lerp(skeleton.get_bone_pose_position(bone), weight))
			skeleton.set_bone_pose_rotation(bone, (from[1] as Quaternion).slerp(skeleton.get_bone_pose_rotation(bone), weight))
			skeleton.set_bone_pose_scale(bone, (from[2] as Vector3).lerp(skeleton.get_bone_pose_scale(bone), weight))
	if weight >= 1.0:
		_referee_handoff.clear()


## Both runners stand on their own pads of the deck (lift = deck height above the floor).
func _place_runners_on_deck() -> void:
	var lift := SuddenDeathLayout.lift_for_deck_top(_deck_world.y)
	game_state.sudden_death_lift = Vector2(lift, lift)
	for player_index in [1, 2]:
		var x := _deck_world.x + SuddenDeathLayout.PAD_X * (1.0 if player_index == 1 else -1.0)
		game_state.place_sudden_death_runner(player_index, x, _deck_world.z)


func _place_winner_on_deck() -> void:
	var pad_x := SuddenDeathLayout.PAD_X * (1.0 if _winner == 1 else -1.0)
	var lift := SuddenDeathLayout.lift_for_deck_top(_deck_world.y)
	game_state.place_sudden_death_runner(_winner, _deck_world.x + pad_x, _deck_world.z)
	if _winner == 1:
		game_state.sudden_death_lift.x = lift
	else:
		game_state.sudden_death_lift.y = lift


func _runner_world(player_index: int) -> Vector3:
	if player_index == 1:
		return Vector3(game_state.player_x, SuddenDeathLayout.FLOOR_Y + game_state.player_y, game_state.player_z)
	return Vector3(game_state.player2_x, SuddenDeathLayout.FLOOR_Y + game_state.player2_y, game_state.player2_z)


func _winner_x() -> float:
	return game_state.player_x if _winner == 1 else game_state.player2_x


func _winner_z() -> float:
	return game_state.player_z if _winner == 1 else game_state.player2_z


# ------------------------------------------------------------------ shots (5.4)

## High over the podium, looking into the mouth.
func _podium_shot() -> Transform3D:
	return _look(_podium + Vector3(0.0, 7.4, -11.5), _podium + Vector3(0.0, 0.2, 0.9))


## A into B as one move: from the podium shot (podium space, which jumps with the shaft at the
## swap) down the mouth after the deck (deck space) and round to the cruise framing. A quadratic
## Bezier through PATH_MID; it passes the mouth's rim at least ~1.3 m inside.
func _descent_path(t: float) -> Transform3D:
	var s := smoothstep(PATH_START, PATH_END, t)
	var podium := _podium + _space_offset
	var eye := _through(podium + Vector3(0.0, 7.4, -11.5), _deck_world + PATH_MID_EYE, _deck_world + CRUISE_EYE, s)
	var aim := _through(podium + Vector3(0.0, 0.2, 0.9), _deck_world + PATH_MID_AIM, _deck_world + CRUISE_AIM, s)
	var pose := _look(eye, aim)
	# The cruise shot's sway and judder come in as the move lands.
	var settle := smoothstep(0.8, 1.0, s)
	if settle > 0.0:
		pose = _blend(pose, _cruise_shot(), settle)
	return pose


func _descent_path_fov(t: float) -> float:
	return lerpf(50.0, 60.0, smoothstep(0.4, PATH_END, t))


## Quadratic Bezier from [param a] to [param b] that passes through [param mid] at s = 0.5.
static func _through(a: Vector3, mid: Vector3, b: Vector3, s: float) -> Vector3:
	var control := mid * 2.0 - (a + b) * 0.5
	var u := 1.0 - s
	return a * (u * u) + control * (2.0 * s * u) + b * (s * s)


## B: from just inside the wall behind the runners, over their heads and down past the far edge.
func _cruise_shot() -> Transform3D:
	var eye := _deck_world + CRUISE_EYE
	var target := _deck_world + CRUISE_AIM
	var pose := _look(eye, target)
	# Gentle sway (0.3 deg, 0.5 Hz) and a fine lift judder with speed.
	var clock := float(Time.get_ticks_msec()) / 1000.0
	var judder := clampf(absf(_descent.speed) / 10.0, 0.0, 1.0)
	var sway := Basis(Vector3.FORWARD, deg_to_rad(0.3) * sin(clock * TAU * 0.5))
	sway = sway * Basis(Vector3.RIGHT, deg_to_rad(0.08) * judder * sin(clock * 47.0) + deg_to_rad(0.05) * judder * sin(clock * 71.0))
	pose.basis = pose.basis * sway
	return pose


## C: straight down from above both heads; the lamp rings run to the vanishing point.
func _down_shot() -> Transform3D:
	var eye := _deck_world + Vector3(0.0, 12.5, -0.4)
	return Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), eye)


## D: riding the deck through the ceiling, the lens tilts up to the pillar forest.
func _arrival_shot(u: float) -> Transform3D:
	var eye := _deck_world + Vector3(0.6, 2.9, -6.2)
	var pitch := deg_to_rad(lerpf(-38.0, -7.0, smoothstep(0.15, 0.85, u)))
	var forward := Vector3(0.0, sin(pitch), cos(pitch))
	return _look(eye, eye + forward * 10.0)


## The intro's insert at the inflow tunnel (seconds into it): 24 m out from the end wall, a little off
## axis, as the gate lifts and the flood bursts out and pours toward the lens; a slow push in.
func _tunnel_shot(t: float) -> Transform3D:
	var push := smoothstep(0.0, INFLOW_SHOT, t)
	var eye := Vector3(lerpf(7.5, 6.6, push), SuddenDeathLayout.FLOOR_Y + 3.1, lerpf(-5.5, -7.5, push))
	return _look(eye, Vector3(-1.0, SuddenDeathLayout.FLOOR_Y + 2.6, SuddenDeathLayout.HALL_START_Z))


## The duel (docs 7): from upstream over the water, both lift towers (P1 on the left) with the players
## facing the lens, the flood running on under them into the pillar forest. World transform.
static func duel_wide_shot() -> Transform3D:
	var base := Vector3(0.0, SuddenDeathLayout.FLOOR_Y, SuddenDeathLayout.LIFT_Z)
	var eye := base + DUEL_EYE
	return Transform3D(Basis.looking_at(base + DUEL_AIM - eye, Vector3.UP), eye)


## Closer on [param player_index]'s tower: [param lift] m over its platform, [param back] m upstream of it
## (the duel camera's side).
func _tower_shot(player_index: int, lift: float, back: float) -> Transform3D:
	var cistern := _cistern()
	var tower := cistern.tower_position(player_index) if cistern != null else SuddenDeathLayout.lift_position(player_index)
	var top := cistern.tower_height(player_index) if cistern != null else 4.0
	return _look(Vector3(tower.x * 0.55, tower.y + top + lift, tower.z - back), Vector3(tower.x, tower.y + top + 0.9, tower.z))


## High behind the players as they walk off the deck to their towers (P1 stays on the left).
func _walk_shot() -> Transform3D:
	var base := Vector3(0.0, SuddenDeathLayout.FLOOR_Y, SuddenDeathLayout.LIFT_Z)
	return _look(base + Vector3(0.0, 7.5, -15.5), base + Vector3(0.0, 0.8, 1.0))


## Low in front of the towers (upstream), looking up as they lift the players.
func _rise_shot() -> Transform3D:
	var base := Vector3(0.0, SuddenDeathLayout.FLOOR_Y, SuddenDeathLayout.LIFT_Z)
	return _look(base + Vector3(0.0, 2.3, -11.5), base + Vector3(0.0, 3.3, 1.0))


## Low over the water by the loser's tower as it goes under, the winner's tower standing beyond.
func _plunge_shot() -> Transform3D:
	var cistern := _cistern()
	var level := game_state.sudden_death.tuning.water_level if game_state.sudden_death != null else 1.2
	var tower := cistern.tower_position(_loser) if cistern != null else SuddenDeathLayout.lift_position(_loser)
	return _look(Vector3(tower.x * 0.3, tower.y + level + 1.4, tower.z - 6.5), Vector3(tower.x * 0.8, tower.y + level + 1.1, tower.z + 0.5))


func _ascent_shot() -> Transform3D:
	var eye := _deck_world + Vector3(1.3, 3.4, -5.8)
	var target := _deck_world + Vector3(-0.2, 0.2, 2.4)
	return _look(eye, target)


func _look(eye: Vector3, target: Vector3) -> Transform3D:
	var direction := target - eye
	if direction.length_squared() < 0.000001:
		direction = Vector3.FORWARD
	var up := Vector3.UP if absf(direction.normalized().y) < 0.995 else Vector3.FORWARD
	return Transform3D(Basis.looking_at(direction, up), eye)


func _blend(a: Transform3D, b: Transform3D, u: float) -> Transform3D:
	var weight := clampf(u, 0.0, 1.0)
	return Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), weight)),
		a.origin.lerp(b.origin, weight))


func _capture_camera() -> void:
	var camera := _camera()
	if camera != null:
		_camera_from = camera.global_transform
		_camera_from_fov = camera.fov


func _set_camera(pose: Transform3D, fov: float, shot: String) -> void:
	_camera_pose = pose
	_camera_fov = fov
	if shot != _camera_shot:
		_camera_shot = shot
		if not _shot_log.has(shot):
			_shot_log[shot] = snappedf(_descent.t, 0.01)
	if camera_controller != null and camera_controller.has_method("set_director_pose"):
		camera_controller.set_director_pose(pose, fov)


func _camera() -> Camera3D:
	return camera_controller.get_node_or_null("Camera3D") as Camera3D if camera_controller != null else null


# ------------------------------------------------------------------ environment

func _shaft_env_for_quality() -> Environment:
	if _shaft_env == null:
		_shaft_env = ShaftDescent.make_environment(GameManager.graphics_quality)
	return _shaft_env


## The loader prewarmed the hall with its own environment: reuse it so the prepared
## pipelines match what the camera draws.
func _hall_env_for_quality() -> Environment:
	if _hall_env == null:
		_hall_env = _loader.environment() if _loader != null and _loader.environment() != null else CisternStage.make_environment(GameManager.graphics_quality)
	return _hall_env


func _duplicate_surface_env() -> Environment:
	var world_env := stage_env.get_node_or_null("WorldEnvironment") as WorldEnvironment if stage_env != null else null
	if world_env == null or world_env.environment == null:
		return null
	return world_env.environment.duplicate() as Environment


## Put `environment` on the camera with an exposure ramp (from, to over `duration`).
func _set_env(environment: Environment, from: float, to: float, duration: float) -> void:
	var camera := _camera()
	if camera == null or environment == null:
		return
	camera.environment = environment
	_env_ramp = Vector3(from, to, maxf(duration, 0.0))
	_env_ramp_time = 0.0
	_env_base_exposure = to
	environment.tonemap_exposure = from if duration > 0.0 else to


func _update_env_ramp() -> void:
	var camera := _camera()
	if camera == null or camera.environment == null or _env_ramp.z <= 0.0:
		return
	if camera.environment == _surface_env and _act == Act.DESCENT:
		return
	_env_ramp_time += _real_dt
	var u := smoothstep(0.0, 1.0, _env_ramp_time / _env_ramp.z)
	camera.environment.tonemap_exposure = lerpf(_env_ramp.x, _env_ramp.y, u)


## 0..1: fade the surface sun and the sky's ambient light (the deck sinks into the mouth).
func _set_surface_dusk(amount: float) -> void:
	ResultCeremonyDirector.stage_light = 1.0 - amount
	WeatherCycle.light_scale = 1.0 - amount
	if _surface_env != null:
		if _surface_ambient < 0.0:
			_surface_ambient = _surface_env.ambient_light_energy
			_surface_sky = _surface_env.background_energy_multiplier
			_surface_fog = _surface_env.fog_light_energy
		# The stage's aerial fog is lit by the sky too: it goes out with the daylight.
		_surface_env.fog_light_energy = lerpf(_surface_fog, 0.0, amount)
		_surface_env.ambient_light_energy = lerpf(_surface_ambient, _surface_ambient * 0.08, amount)
		# The sky also lights the grating through its reflections (it is out of frame by then).
		_surface_env.background_energy_multiplier = lerpf(_surface_sky, _surface_sky * 0.04, amount)


func _restore_surface_env() -> void:
	ResultCeremonyDirector.stage_light = 1.0
	WeatherCycle.light_scale = 1.0
	_surface_ambient = -1.0
	_branch_night = 0.0
	var camera := _camera()
	if camera != null and camera.environment in [_surface_env, _shaft_env, _hall_env]:
		camera.environment = null
	_surface_env = null


# ------------------------------------------------------------------ helpers

func _cistern() -> CisternStage:
	return _loader.cistern() if _loader != null else null


func _depth_signs() -> Array:
	# A board every 10 m while the shown depth runs with the wall (cruise speed).
	if absf(_descent.speed - SuddenDeathDescent.CRUISE_SPEED) > 0.5 or _descent.display_depth >= SuddenDeathDescent.DISPLAY_SOFT - 2.0:
		return []
	var signs: Array = []
	var depth := _descent.display_depth
	for board in range(1, 7):
		var board_depth := float(board) * 10.0
		var y := _deck_local_y + 1.6 + (depth - board_depth)
		if y > _deck_local_y - 40.0 and y < _deck_local_y + 20.0:
			signs.append({"y": y, "text": "−%dm" % int(board_depth)})
	return signs


## A short tick each time a lamp ring passes the deck.
func _lamp_ticks(travel: float) -> void:
	var index := int(floor(travel / SuddenDeathLayout.SHAFT_TILE_HEIGHT))
	if index != _lamp_index:
		_lamp_index = index
		_play(&"lamp_pass", -13.0, randf_range(0.92, 1.08))


func _cue(cue_name: String, due: bool) -> bool:
	if due and not _cues.has(cue_name):
		_cues[cue_name] = true
		return true
	return false


func _ensure_hud() -> void:
	if is_instance_valid(_hud):
		return
	_hud = SuddenDeathHud.new()
	_hud.name = "SuddenDeathHud"
	add_child(_hud)
	_hud.setup(game_state.use_english_ui)


func _ensure_audio() -> void:
	if is_instance_valid(_audio):
		return
	_audio = SuddenDeathAudio.new()
	_audio.name = "SuddenDeathAudio"
	add_child(_audio)
	_audio.setup()


func _hud_call(method: StringName, args: Array) -> void:
	if is_instance_valid(_hud) and _hud.has_method(method):
		_hud.callv(method, args)


func _hud_callout(text: String, color: Color, duration := 1.2) -> void:
	_hud_call("callout", [text, color, duration])


func _audio_call(method: StringName, args: Array) -> void:
	if is_instance_valid(_audio) and _audio.has_method(method):
		_audio.callv(method, args)


func _play(cue: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	_audio_call("play", [cue, volume_db, pitch])


## Back to idle: free everything the sudden death created (menu, retry, next round).
func reset() -> void:
	game_state.sudden_death_preparing_panel = ""
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	_finish_underground()
	_free_deck_props()
	ResultCeremonyDirector.stage_drop = 0.0
	if ceremony != null:
		ceremony.allow_egg_target = true
	if camera_controller != null and camera_controller.has_method("clear_director_pose"):
		camera_controller.clear_director_pose()
	_restore_surface_env()
	_hud_call("hide_all", [true])
	_audio_call("stop_all", [])
	if is_instance_valid(_shaft):
		_shaft.visible = false
		_shaft.set_beacons(false)
	if is_instance_valid(_drain):
		_drain.clear()
	if stage_env != null and stage_env.has_method("set_shaft_hole"):
		stage_env.set_shaft_hole(_podium, SuddenDeathLayout.SHAFT_RADIUS, false)
	_act = Act.IDLE
	_act_time = 0.0
	_hall_env = null
	_return_stage = ""
	_cues.clear()


func get_debug_snapshot() -> Dictionary:
	var cistern := _cistern()
	var frames := _frame_log.duplicate()
	frames.sort()
	return {
		"act": act_name(), "act_time": snappedf(_act_time, 0.001), "return_stage": _return_stage,
		"shot": _camera_shot, "camera": _camera_pose.origin, "fov": _camera_fov,
		"descent": _descent.get_debug_snapshot(),
		"loader": _loader.get_debug_snapshot() if _loader != null else {},
		"shaft": _shaft.get_debug_snapshot() if is_instance_valid(_shaft) else {},
		"cistern": cistern.get_debug_snapshot() if cistern != null else {},
		"hud": _hud.get_debug_snapshot() if is_instance_valid(_hud) else {},
		"audio": _audio.get_debug_snapshot() if is_instance_valid(_audio) else {},
		"deck": _deck_world, "stage_drop": ResultCeremonyDirector.stage_drop,
		"lift": game_state.sudden_death_lift if game_state != null else Vector2.ZERO,
		"cruise_frames": frames.size(),
		"cruise_frame_max_ms": frames.back() if not frames.is_empty() else 0.0,
		"cruise_frame_p95_ms": frames[int(frames.size() * 0.95)] if not frames.is_empty() else 0.0,
		"cruise_ready_frames": _ready_frame_log.size(),
		"cruise_ready_frame_max_ms": _ready_frame_log.max() if not _ready_frame_log.is_empty() else 0.0,
		"exposure": _camera().environment.tonemap_exposure if _camera() != null and _camera().environment != null else -1.0,
		"rows_lit": _row_lights_on, "events": _events.size(), "shots": _shot_log.duplicate(),
	}
