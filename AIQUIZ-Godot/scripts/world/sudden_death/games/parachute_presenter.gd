class_name ParachutePresenter
extends SuddenDeathPresenter

## サドンデス「ひらけ！パラシュート」の見せ方（docs/sudden_death_v2/parachute.md 第4〜8章）。M1：仮のパラシュートで通す。
## 監督（HeliSuddenDeathDirector）は空のセットの巡航のあと、縄ばしごで降ろさずにここへ渡す（descent_mode "skydive"）。
## ここが受け持つもの：導入（ボタン→床のハッチ→落下→腹ばいに整える）、図解ルールカード、カウントダウン、本戦（段に応じた
## パラシュートと引き上げ、うなずき・ひもを引く・きりもみ、カメラ、最後の1問のスロー）、決着（全開・ハンカチ・
## ドボン・着地）、勝者のダンス（ResultWinnerDance、エモートのキー）。決着のあとの迎え（縄ばしご）と帰還は監督。
##
## 人物：落ちている間と着地台の上は、プレイヤーの見た目を写した人形（ダブル。決着演出の人形と同じ作り）を関節の角度で
## 動かす。本物のアバター（StagingPuppet）は機内の座席と、迎えの縄ばしごへ走るときだけ使う。
## 落下：2人は空のセットの下の「落ちる点」に留め、雲（FallClouds）を下から上へ流し、海と着地台を高度に合わせて上下させる。

const SKY_ORIGIN := HeliSuddenDeathDirector.SKY_ORIGIN
const FORMATION_X := HeliSuddenDeathDirector.FORMATION_X
## 落ちる点（2人の中心）。空のセットの中心から 26 m 下。
const FALL_DROP := 26.0
const SIDE_X := 1.7
const GRAVITY := 9.8
const TERMINAL := 45.0

# 導入の時刻（parachute.md 4.1）
const I_COCKPIT := 0.5
const I_HATCH := 1.2
const I_DROP := 1.6
const I_P2_LAG := 0.15
const I_CHASE := 3.2
const I_RULES := 5.0
const SETTLE_TIME := 1.2
const RULE_HOLD := 0.6
## カウントダウン「3・2・1」各 0.6 秒、そのあと GO!
const COUNT_STEP := 0.6

# 本戦
const RISE_PER_STAGE := 1.2
## 本戦の画の収め方（parachute.md 7.1節、M2）：2人の体と、パラシュートの一番上（パイロットシュートの頂点）が、
## 問題パネルの下と4択の上の間（画面の高さの FRAME_TOP〜FRAME_BOTTOM）に収まる距離と高さを毎フレーム求めて寄せる。
## 横は 2人と布の幅が FRAME_WIDTH に収まるように。距離は CAMERA_NEAR より近づかない。
const CAMERA_NEAR := 7.2
const FRAME_TOP := 0.17
const FRAME_BOTTOM := 0.83
const FRAME_WIDTH := 0.84
const MAIN_FOV := 50.0
## 体の上下の余白（腹ばいの体の厚み・手足）と、横の余白（腕）。
const BODY_PAD := 0.75
const ARM_PAD := 1.1
## 引くとき（パラシュートが開いた）は速く、寄るときはゆっくり。
const FIT_OUT_RATE := 5.0
const FIT_IN_RATE := 1.6
const NOD_TIME := 0.35
const PULL_TIME := 0.6
const SPIN_TIME := 0.8
const TAG_TIME := 1.3
const SLOW := 0.3
## 本戦の頭と最後の1問の手前の、カメラから海までの高さ（下がるにつれて海が近づく）。
const HIGH_SEA := 390.0
const LOW_SEA := 140.0
## 着地のあと、パラシュートが落ちる床の点（着地した人の後ろ、m）。
const GROUND_BEHIND := 0.45
## 最後の1問と着地：着地台の上面がこの高さだけ下。
const LANDING_DROP := 20.0

# 決着（4.4）
const F_RELEASE := 1.6
const F_SPLASH := 2.2
const F_DESCEND := 4.4
const F_LAND := 5.2
const F_COVER := 6.2
const F_DONE := 7.0
const WINNER_RISE := 14.0

# 勝者のダンス（6.6）
const DANCE_AUTO := 2.5
const EXTRACT_DELAY := 3.6
const ORBIT_SPEED := 12.0
## 着地（C9）とダンス（C10）の画の半径、最後の1問（C6）の画角（M2 で絵コンテに合わせた）。
const LANDING_RADIUS := 9.6
const DANCE_RADIUS := 8.6
const FINAL_FOV := 40.0

const AXES := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}
## 関節の角度の表（関節・軸・度）。軸は体の向きの軸（+X＝画面の右の腕「r_」の側、+Y＝頭、+Z＝胸）。
## x は − で前へ振る（頭は − でてっぺんが後ろへ倒れ、顔が前を向く）。
const POSE_BOX := [
	["spine", "x", -16.0], ["head_pivot", "x", -64.0],
	["l_shoulder", "z", -82.0], ["l_shoulder", "x", 14.0], ["l_elbow", "z", -78.0],
	["r_shoulder", "z", 82.0], ["r_shoulder", "x", 14.0], ["r_elbow", "z", 78.0],
	["l_hip", "z", -16.0], ["r_hip", "z", 16.0], ["l_hip", "x", 10.0], ["r_hip", "x", 10.0],
	["l_knee", "x", 58.0], ["r_knee", "x", 58.0],
]
const POSE_DROP := [
	["l_shoulder", "z", -150.0], ["r_shoulder", "z", 140.0], ["l_elbow", "z", -20.0], ["r_elbow", "z", 30.0],
	["l_hip", "x", -30.0], ["l_knee", "x", 50.0], ["r_hip", "x", 15.0], ["r_knee", "x", 20.0],
	["head_pivot", "x", 12.0],
]
const POSE_PULL := [
	["spine", "x", -10.0], ["head_pivot", "x", -50.0],
	["l_shoulder", "z", -82.0], ["l_shoulder", "x", 14.0], ["l_elbow", "z", -78.0],
	["r_shoulder", "z", 20.0], ["r_shoulder", "x", -70.0], ["r_elbow", "x", -60.0],
	["l_hip", "z", -16.0], ["r_hip", "z", 16.0], ["l_knee", "x", 58.0], ["r_knee", "x", 58.0],
]
const POSE_SPIN := [
	["spine", "x", -18.0], ["spine", "y", 20.0],
	["l_shoulder", "z", -160.0], ["l_shoulder", "x", -40.0], ["r_shoulder", "z", 35.0], ["r_shoulder", "x", 50.0],
	["r_elbow", "z", 60.0], ["l_hip", "x", -50.0], ["l_knee", "x", 30.0], ["r_hip", "z", 30.0], ["r_knee", "x", 70.0],
	["head_pivot", "z", 18.0],
]
const POSE_CANOPY := [
	["l_shoulder", "z", -150.0], ["r_shoulder", "z", 150.0], ["l_elbow", "z", 25.0], ["r_elbow", "z", -25.0],
	["l_hip", "x", -18.0], ["r_hip", "x", -12.0], ["l_knee", "x", 22.0], ["r_knee", "x", 14.0],
	["head_pivot", "x", -8.0],
]
const POSE_FLARE := [
	["l_shoulder", "z", -60.0], ["r_shoulder", "z", 60.0], ["l_elbow", "z", 40.0], ["r_elbow", "z", -40.0],
	["l_hip", "x", -40.0], ["r_hip", "x", -40.0], ["l_knee", "x", 30.0], ["r_knee", "x", 30.0],
]
const POSE_LAND := [
	["spine", "x", -20.0], ["l_shoulder", "z", -40.0], ["r_shoulder", "z", 40.0],
	["l_hip", "x", -50.0], ["r_hip", "x", -50.0], ["l_knee", "x", 70.0], ["r_knee", "x", 70.0],
]
const POSE_PANIC := [
	["l_shoulder", "z", -165.0], ["r_shoulder", "z", 120.0], ["r_elbow", "z", 50.0], ["l_elbow", "z", -35.0],
	["l_hip", "x", -45.0], ["l_knee", "x", 80.0], ["r_hip", "x", 25.0], ["r_hip", "z", 20.0],
	["head_pivot", "x", 20.0], ["spine", "x", -10.0],
]
const POSE_WIN := [
	["l_shoulder", "z", -160.0], ["r_shoulder", "z", 160.0], ["l_elbow", "z", -12.0], ["r_elbow", "z", 12.0],
	["l_hip", "z", -8.0], ["r_hip", "z", 8.0], ["head_pivot", "x", -10.0],
]

var _world: Node3D = null
var _hud: ParachuteHud = null
var _float: LandingFloat = null
var _clouds: FallClouds = null
var _splash: WaterSplash = null
## player -> {"root", "parts", "rest"}
var _actors := {}
var _canopies := {}
var _built := false

## "idle", "intro", "rules", "countdown", "main", "finish", "dance", "released"
var _phase := "idle"
var _t := 0.0
var _phase_t := 0.0
var _slow := 1.0
var _slow_target := 1.0
var _camera := {}
var _cut_next := false
var _shot := ""
var _fall := Vector3.ZERO
var _sea_y := 0.0
var _landing := Vector3.ZERO
var _cues := {}

## 落下の高さ（落ちる点からの差）と速さ・つなぎ。
var _drop_start := {}
var _rise := {1: 0.0, 2: 0.0}
var _rise_v := {1: 0.0, 2: 0.0}
var _nod_at := {1: -INF, 2: -INF}
var _pull_at := {1: -INF, 2: -INF}
var _spin_at := {1: -INF, 2: -INF}
var _stage_at := {1: INF, 2: INF}
var _stage_to := {1: 0, 2: 0}
var _tags := {1: ["", -INF], 2: ["", -INF]}
var _cam_distance := 7.2
var _cam_aim := 0.4
var _cam_center_x := 0.0
var _punch_at := -INF
var _punch_side := 1.0
var _shake_at := -INF
var _final_at := -INF
var _landed_canopy := Transform3D.IDENTITY
var _rules_at := INF
var _count_at := INF
var _finish_at := INF
var _winner := 0
var _loser := 0
var _orbit := 0.0

# ダンス
var _dances := {}
var _dance_slot := -1
var _dance_started := 0.0
var _dance_prev_mask := 0
var _dance_names: Array[String] = []
var _dance_t := 0.0
var _released := false


func title(english: bool) -> String:
	return "OPEN THE CHUTE!" if english else "ひらけ！パラシュート"


func descent_mode() -> String:
	return "skydive"


func extract_delay() -> float:
	return EXTRACT_DELAY


## 勝者は HUD の上に小さく出す（共通の大きな「P1 WIN!」はダンスを隠すので出さない）。
func shows_winner_banner() -> bool:
	return false


func preparation_steps() -> Array[Callable]:
	return [_build_world, _build_actors, _build_float, _build_effects]


func approach_offset(_player: int) -> Vector3:
	return Vector3(-16.0, 7.0, 8.0)


# ------------------------------------------------------------------ build (one step a frame)

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "ParachuteWorld"
	add_child(_world)
	_world.visible = false
	_hud = ParachuteHud.new()
	add_child(_hud)
	_hud.english = director.game_state.use_english_ui if director != null and director.game_state != null else false


func _build_actors() -> void:
	var state := director.game_state
	for player in [1, 2]:
		var root := Node3D.new()
		root.name = "P%dSkydiver" % player
		_world.add_child(root)
		var hat := state.p1_hat if player == 1 else state.p2_hat
		var parts := EmoteBlockmanPreview.build_player_skeleton(player == 1, root, hat, 0, state.get_display_skin(player))
		parts["root"] = root
		var canopy := ParachuteCanopy.new()
		canopy.name = "P%dCanopy" % player
		_world.add_child(canopy)
		canopy.build(player == 1)
		_canopies[player] = canopy
		_mount_container(parts, canopy)
		var rest := {}
		for key: Variant in parts:
			if parts[key] is Node3D and key != "root":
				rest[key] = (parts[key] as Node3D).transform
		_actors[player] = {"root": root, "parts": parts, "rest": rest}
		root.visible = false


func _build_float() -> void:
	_float = LandingFloat.new()
	_float.name = "LandingFloat"
	_world.add_child(_float)
	_float.build()


func _build_effects() -> void:
	_clouds = FallClouds.new()
	_clouds.name = "FallClouds"
	_world.add_child(_clouds)
	_clouds.build(GameManager.graphics_quality)
	_splash = WaterSplash.new()
	_splash.name = "WaterSplash"
	_world.add_child(_splash)
	_splash.build()
	_built = true


## 背中のコンテナ（chute.glb の Container。原点＝背中に当たる面の中心）を人形の背骨に付ける。
func _mount_container(parts: Dictionary, canopy: ParachuteCanopy) -> void:
	var spine := parts.get("spine") as Node3D
	var container := canopy.container_node()
	if spine == null or container == null:
		return
	spine.add_child(container)
	container.position = Vector3(0.0, 0.22, -0.12)


# ------------------------------------------------------------------ the venue

func set_venue_active(active: bool) -> void:
	if _world != null:
		_world.visible = active
	if not active:
		_restore_sea()
		if _hud != null:
			_hud.hide_all()
		if _float != null:
			_float.set_tally(false)


func begin_venue() -> void:
	_phase = "intro"
	_t = 0.0
	_phase_t = 0.0
	_slow = 1.0
	_slow_target = 1.0
	_cues.clear()
	_fall = SKY_ORIGIN + Vector3(0.0, -FALL_DROP, 0.0)
	_sea_y = _fall.y - HIGH_SEA
	_world.visible = true
	for player in [1, 2]:
		(_canopies[player] as ParachuteCanopy).set_stage(0)
		_rise[player] = 0.0
		_rise_v[player] = 0.0
	_cam_distance = CAMERA_NEAR
	_cam_aim = 0.4
	_cam_center_x = 0.0
	_cut_next = true


func update_venue(delta: float) -> void:
	if not _built or _phase == "idle":
		return
	_slow = move_toward(_slow, _slow_target, delta * 2.5)
	var sd := delta * _slow
	_t += delta
	_phase_t += delta
	match _phase:
		"intro":
			_update_intro(delta)
		"rules", "countdown", "main":
			_update_freefall(delta, sd)
		"finish":
			_update_finish(delta)
		"dance", "released":
			_update_float_only(delta)
	_update_hud()


func venue_camera() -> Dictionary:
	return _camera


## スマホのタップの層（監督が見る）：ルールカードが出て、閉じるのを待っている間。
func rules_waiting() -> bool:
	return _phase == "rules"


func confirm_rules() -> bool:
	if _phase != "rules" or _t - _rules_at < RULE_HOLD:
		return false
	_phase = "countdown"
	_count_at = _t
	return true


func finale_done() -> bool:
	return _phase == "finish" and _t - _finish_at >= F_DONE


func winner() -> int:
	return _winner


func on_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	match kind:
		"answered":
			_nod_at[int(event.player)] = _t
		"reveal":
			_on_reveal(event)
		"final_wrong":
			_tags[int(event.player)] = ["miss", _t]
			_shake_at = _t
		"final":
			_final_at = _t
			_slow_target = SLOW
			_sea_y = _fall.y - LANDING_DROP - _float_pad_top()
			_cut_next = true
			AudioManager.play_sfx(&"score_drum_roll", -8.0)
		"decided":
			_begin_finish(int(event.winner))


func _on_reveal(event: Dictionary) -> void:
	var results: Array = event.get("results", [])
	var stages: Array = event.get("stages", [0, 0])
	if bool(event.get("final", false)):
		return
	var order := [1, 2]
	var game := _game()
	if game != null and game.pick_time[1] >= 0.0 and (game.pick_time[0] < 0.0 or game.pick_time[1] < game.pick_time[0]):
		order = [2, 1]
	var lag := 0.0
	if results.has("correct"):
		AudioManager.play_sfx(&"door_correct", -6.0)
	if results.has("wrong"):
		AudioManager.play_sfx(&"door_wrong", -6.0)
	for player: int in order:
		var result := str(results[player - 1]) if player - 1 < results.size() else ""
		_stage_to[player] = int(stages[player - 1])
		if result == "correct":
			_pull_at[player] = _t + 0.2 + lag
			_stage_at[player] = _t + 0.35 + lag
			_tags[player] = ["opened", _t + 0.35 + lag]
			_punch_at = _t + 0.2 + lag
			_punch_side = 1.0 if player == 1 else -1.0
			lag += 0.15
		elif result == "wrong":
			_spin_at[player] = _t + 0.2
			_stage_at[player] = _t + 0.2
			_tags[player] = ["shrunk", _t + 0.2]
			_shake_at = _t + 0.2


func _begin_finish(player: int) -> void:
	_winner = player
	_loser = 3 - player
	_phase = "finish"
	_finish_at = _t
	_slow_target = 1.0
	_slow = 1.0
	_stage_at[_winner] = _t
	_stage_to[_winner] = 3
	AudioManager.stop_sfx(&"score_drum_roll")
	# 勝者の装備の 3 つの踊りを先に読んでおく（ダンスで止まらないように）。
	var state := director.game_state
	var slots: Array[int] = state.p1_emote_slots if player == 1 else state.p2_emote_slots
	_dance_names.clear()
	for index in range(3):
		var emote := int(slots[index]) if index < slots.size() else 0
		if emote <= 0:
			emote = state.get_result_winner_emote(player)
		var dance := ResultWinnerDance.new()
		dance.setup(_world, emote)
		_dances[index] = dance
		_dance_names.append(EmoteData.get_emote_name(emote))


# ------------------------------------------------------------------ intro (4.1)

func _update_intro(delta: float) -> void:
	var t := _phase_t
	var rig := director.heli_rig()
	var sky := director.sky_set()
	if t < I_DROP and sky != null:
		sky.advance(SuddenDeathSkySet.FLOW_SPEED * delta)
	for player in [1, 2]:
		var side := _side(player)
		var aircraft := rig.heli(player) if rig != null else null
		var sway := StagingFlight.cruise_sway(_t + 30.0, 0.0 if player == 1 else 0.7)
		var formation := SKY_ORIGIN + Vector3(FORMATION_X * side, 0.0, 0.0) + sway.origin
		var drop_t := t - I_DROP - (I_P2_LAG if player == 2 else 0.0)
		if drop_t > 0.4:
			# 2人が出たら、ヘリは上へ離れていく（落ちていく2人から見ると、ヘリが空へ遠ざかる）。
			var u := drop_t - 0.4
			formation += Vector3(0.0, 0.9 * u * u + 1.5 * u, -2.0 * u * u)
		if rig != null:
			rig.set_motion(player, formation, Vector3(0, 0, -1), maxf(delta, 0.0001))
		if aircraft != null:
			aircraft.set_hatch(clampf((t - I_HATCH) / 0.4, 0.0, 1.0))
			aircraft.set_belt("L", 0.0 if t >= I_HATCH else 1.0)
			if aircraft.pilot != null:
				if _cue("pilot_turn_%d" % player, t >= 0.0):
					aircraft.pilot.play(&"wave")
				if _cue("pilot_press_%d" % player, t >= I_COCKPIT):
					aircraft.pilot.play(&"point")
				if _cue("pilot_back_%d" % player, t >= I_DROP + 0.6):
					aircraft.pilot.play(&"steer")
		var puppet := director.puppet(player)
		if drop_t < 0.0:
			if puppet != null:
				var length := maxf(puppet.clip_length("Driving_Loop"), 0.1)
				puppet.pose("Driving_Loop", fposmod(_t / length, 1.0))
				puppet.sit_at(rig.seat_transform(player))
			continue
		if not _drop_start.has(player):
			# 座席の人形から、写した人形へ入れ替える（同じ位置から落ちる）。
			var start := SKY_ORIGIN + Vector3(FORMATION_X * side, 0.0, 0.0)
			if puppet != null:
				var pelvis := puppet.parts().get("pelvis") as Node3D
				if pelvis != null:
					start = pelvis.global_position + Vector3(0.0, 0.3, 0.0)
				puppet.set_visible(false)
			_drop_start[player] = start
			(_actors[player].root as Node3D).visible = true
			if _cue("hatch_sound_%d" % player, true) and aircraft != null and aircraft.sound != null and aircraft.sound.has_method("play_one_shot"):
				aircraft.sound.call("play_one_shot", "grip")
		var from: Vector3 = _drop_start[player]
		var end := _fall + Vector3(SIDE_X * side, 0.0, 0.0)
		var fallen := minf(0.5 * GRAVITY * drop_t * drop_t, from.y - end.y)
		var across := smoothstep(0.0, 2.2, drop_t)
		var center := Vector3(lerpf(from.x, end.x, across), from.y - fallen, lerpf(from.z, end.z, across))
		center += _drift(player)
		# ばたつき → 腹ばい（I_CHASE から SETTLE_TIME かけて）
		var settle := smoothstep(I_CHASE - I_DROP, I_CHASE - I_DROP + SETTLE_TIME, drop_t)
		var pose := _mix(POSE_DROP, POSE_BOX, settle)
		_pose_actor(player, _body_basis(_upright_basis(Vector3(0, 0, 1)), _box_basis(), settle, drop_t * 0.9), center,
			_with_wobble(pose, player, 1.0 + (1.0 - settle) * 3.0))
		_place_canopy(player, delta)
	var fall_speed := minf(GRAVITY * maxf(t - I_DROP, 0.0), TERMINAL) if t > I_DROP + 2.0 else 0.0
	_clouds.advance(fall_speed * delta)
	_update_sea(delta)
	# 追いかけの画は本戦の画へつなぐので、収め方を先に求めておく
	_fit_main(delta)
	_intro_camera(t)
	if t >= I_RULES:
		_phase = "rules"
		_rules_at = _t
		if rig != null:
			for player in [1, 2]:
				rig.set_shown(player, false)
		if director.game_state != null:
			director.game_state.sudden_death_preparing_panel = ""


func _intro_camera(t: float) -> void:
	var rig := director.heli_rig()
	if t < I_COCKPIT:
		_set_camera(_look(SKY_ORIGIN + Vector3(0.0, 1.0, -13.0), SKY_ORIGIN + Vector3(0.0, -0.6, 0.0)), 50.0, "c1_formation")
	elif t < I_HATCH:
		var holder := rig.holder(1) if rig != null else null
		var h := holder.global_transform if holder != null else Transform3D(Basis.IDENTITY, SKY_ORIGIN)
		if _cue("cut_cockpit", true):
			_cut_next = true
		_set_camera(_look(h * Vector3(1.9, 1.2, -3.6), h * Vector3(0.1, 0.7, -0.4)), 40.0, "c1b_cockpit")
	elif t < I_CHASE:
		if _cue("cut_under", true):
			_cut_next = true
		_set_camera(_look(SKY_ORIGIN + Vector3(0.0, -16.0, -11.0), SKY_ORIGIN + Vector3(0.0, -3.0, 0.0)), 62.0, "c2_under")
	else:
		var u := smoothstep(I_CHASE, I_CHASE + 1.8, t)
		var chase := _look(_fall + Vector3(0.0, -6.0, -8.0), _fall + Vector3(0.0, 4.0, 0.0))
		var main := _main_shot()
		_set_camera(chase.interpolate_with(main.transform, u), lerpf(64.0, float(main.fov), u), "c3_chase")


# ------------------------------------------------------------------ freefall (rules, countdown, main)

func _update_freefall(delta: float, sd: float) -> void:
	var game := _game()
	if _phase == "countdown":
		_update_countdown()
	for player in [1, 2]:
		var side := _side(player)
		# 段が上がると落ちる速さが下がり、2人の中で上へ引かれる（ばね）。
		if _t >= float(_stage_at[player]):
			(_canopies[player] as ParachuteCanopy).set_stage(int(_stage_to[player]))
			_stage_at[player] = INF
		var target := RISE_PER_STAGE * float((_canopies[player] as ParachuteCanopy).stage)
		var k := 16.0
		var c := 2.0 * 0.6 * sqrt(k)
		_rise_v[player] = float(_rise_v[player]) + ((target - float(_rise[player])) * k - c * float(_rise_v[player])) * delta
		_rise[player] = float(_rise[player]) + float(_rise_v[player]) * delta
		var center := _fall + Vector3(SIDE_X * side, float(_rise[player]), 0.0) + _drift(player)
		var pose: Array = POSE_BOX
		var body := _box_basis()
		var nod := clampf((_t - float(_nod_at[player])) / NOD_TIME, 0.0, 1.0)
		if nod > 0.0 and nod < 1.0:
			pose = _add(pose, [["head_pivot", "x", 14.0 * sin(PI * nod)], ["spine", "x", 6.0 * sin(PI * nod)]])
		var pull := clampf((_t - float(_pull_at[player])) / PULL_TIME, 0.0, 1.0)
		if pull > 0.0 and pull < 1.0:
			pose = _mix(pose, POSE_PULL, sin(PI * pull))
		var spin := clampf((_t - float(_spin_at[player])) / SPIN_TIME, 0.0, 1.0)
		if spin > 0.0 and spin < 1.0:
			var e := spin * spin * (3.0 - 2.0 * spin)
			pose = _mix(pose, POSE_SPIN, sin(PI * spin))
			body = Basis(Vector3.UP, TAU * e) * body
		_pose_actor(player, body, center, _with_wobble(pose, player, 1.0))
		_place_canopy(player, sd)
	_clouds.advance(ParachuteGame.FALL_SPEED * sd)
	if game != null and not game.final:
		var progress := clampf((ParachuteGame.ALTITUDE_START - game.altitude) / (ParachuteGame.ALTITUDE_START - ParachuteGame.FINAL_ALTITUDE), 0.0, 1.0)
		_sea_y = _fall.y - lerpf(HIGH_SEA, LOW_SEA, progress)
	_update_sea(delta)
	_freefall_camera(delta)


func _update_countdown() -> void:
	var c := _t - _count_at
	var hud := director.hud()
	var text := ""
	if c < COUNT_STEP:
		text = "3"
	elif c < COUNT_STEP * 2.0:
		text = "2"
	elif c < COUNT_STEP * 3.0:
		text = "1"
	elif c < COUNT_STEP * 3.0 + 0.8:
		text = "GO!"
	if hud != null:
		hud.set_countdown(text)
	if text != "" and _cue("count_" + text, true):
		AudioManager.play_sfx(&"countdown_go" if text == "GO!" else &"countdown_beep", -4.0)
	if c >= COUNT_STEP * 3.0 and _cue("game_start", true):
		director.game_state.start_sudden_death_countdown()
	if c >= COUNT_STEP * 3.0 + 0.8:
		_phase = "main"
		_phase_t = 0.0


func _freefall_camera(delta: float) -> void:
	var game := _game()
	_fit_main(delta)
	if game != null and game.final:
		var land := Vector3(_fall.x, _sea_y + _float_pad_top(), _fall.z)
		# 着地台の手前（-Z の側）から見上げる。P1（+X）が画面の左に来る向き。
		_set_camera(_look(land + Vector3(0.0, 1.6, -4.2), _fall + Vector3(0.0, 0.3, 1.0)), FINAL_FOV, "c6_final")
		return
	if _shot == "c6_final":
		_cut_next = true
	var shot := _main_shot()
	# 本戦の画はここで寄せ方（_fit_main）を持つので、監督の追いかけを重ねない（重ねると開いた直後に遅れて上がはみ出す）
	_cut_next = true
	_set_camera(shot.transform, float(shot.fov), "c4_main")


## 本戦の画の距離と高さを、いま見えているもの（2人の体・パラシュート）に合わせて寄せる。
## 点を実際のカメラの向きで画面に投影し、上下が FRAME_TOP〜FRAME_BOTTOM、左右が FRAME_WIDTH に収まるまで、
## 距離と注視点の高さを数回直す（パラシュートは体の向きでカメラ側へ傾くので、同じ奥行きとみなす近似では足りない）。
func _fit_main(delta: float) -> void:
	var fit := framing()
	var points: Array = fit.points.values()
	if points.is_empty():
		# まだ誰も見えていない（導入の前半）：今の値のまま
		return
	var aspect := 16.0 / 9.0
	var viewport := get_viewport()
	if viewport != null:
		var size := viewport.get_visible_rect().size
		if size.y > 0.0:
			aspect = size.x / size.y
	var tan_v := tan(deg_to_rad(MAIN_FOV) * 0.5)
	var tan_h := tan_v * aspect
	var center_x := float(fit.cx) - _fall.x
	var d := maxf(_cam_distance, CAMERA_NEAR)
	var aim := (float(fit.y_max) + float(fit.y_min)) * 0.5 - _fall.y
	var band := FRAME_BOTTOM - FRAME_TOP
	var band_mid := (FRAME_TOP + FRAME_BOTTOM) * 0.5
	for _i in range(8):
		var xf := _main_pose(d, aim, center_x)
		var f_min := INF
		var f_max := -INF
		var w_max := 0.0
		var depth := 0.0
		for p: Vector3 in points:
			var local: Vector3 = xf.affine_inverse() * p
			var z := maxf(-local.z, 0.5)
			depth += z
			# 画面の縦の位置（0＝上、1＝下）と横の広がり（真ん中から、0〜1＝端）
			var fy := 0.5 - local.y / z / (2.0 * tan_v)
			f_min = minf(f_min, fy)
			f_max = maxf(f_max, fy)
			w_max = maxf(w_max, absf(local.x / z / tan_h))
		depth /= maxf(float(points.size()), 1.0)
		var scale := maxf((f_max - f_min) / band, w_max / FRAME_WIDTH)
		var mid := (f_min + f_max) * 0.5
		# 中身の真ん中を帯の真ん中へ：画面の割合の差を、奥行きでの高さに直して注視点を動かす（中身が下なら注視点を下げる）
		aim += (band_mid - mid) * 2.0 * tan_v * depth
		d = maxf(CAMERA_NEAR, d * lerpf(1.0, scale, 0.85))
	var rate := FIT_OUT_RATE if d > _cam_distance else FIT_IN_RATE
	_cam_distance = lerpf(_cam_distance, d, 1.0 - exp(-delta * rate))
	_cam_aim = lerpf(_cam_aim, aim, 1.0 - exp(-delta * maxf(rate, 3.0)))
	_cam_center_x = lerpf(_cam_center_x, center_x, 1.0 - exp(-delta * 2.0))


## 本戦の画のカメラの置き場所（ゆれ・寄りを入れない、収め方の計算用）。
func _main_pose(d: float, aim: float, center_x: float) -> Transform3D:
	var eye := _fall + Vector3(center_x, aim + d * 0.08, -d)
	return _look(eye, _fall + Vector3(center_x, aim, 0.6))


## カメラに収めたいもの（ワールド）：2人の体の上下、パラシュートの一番上、横の広がり。テストも読む。
func framing() -> Dictionary:
	var y_min := INF
	var y_max := -INF
	var x_min := INF
	var x_max := -INF
	var points := {}
	for player in [1, 2]:
		if not _actors.has(player):
			continue
		var root := _actors[player].root as Node3D
		if not root.visible:
			continue
		var at := root.global_position
		y_min = minf(y_min, at.y - BODY_PAD)
		y_max = maxf(y_max, at.y + BODY_PAD)
		x_min = minf(x_min, at.x - ARM_PAD)
		x_max = maxf(x_max, at.x + ARM_PAD)
		points["P%d_body_low" % player] = at - Vector3(0.0, BODY_PAD, 0.0)
		points["P%d_body_high" % player] = at + Vector3(0.0, BODY_PAD, 0.0)
		var canopy := _canopies.get(player) as ParachuteCanopy
		if canopy != null and canopy.stage > 0:
			var top := canopy.top_point()
			y_max = maxf(y_max, top.y + 0.15)
			var span := canopy.half_span()
			x_min = minf(x_min, canopy.global_position.x - span)
			x_max = maxf(x_max, canopy.global_position.x + span)
			points["P%d_chute_top" % player] = top
			if span > 0.5:
				var side := canopy.global_basis.x.normalized()
				points["P%d_chute_left" % player] = top - side * span - Vector3(0.0, 0.9, 0.0)
				points["P%d_chute_right" % player] = top + side * span - Vector3(0.0, 0.9, 0.0)
	if not is_finite(y_min):
		y_min = _fall.y - 1.0
		y_max = _fall.y + 1.0
		x_min = _fall.x - 3.0
		x_max = _fall.x + 3.0
	return {"y_min": y_min, "y_max": y_max, "x_half": maxf(x_max - x_min, 1.0) * 0.5, "cx": (x_min + x_max) * 0.5, "points": points}


## 本戦の画：2人の頭の前、少し上から。背景は下の海と水平線。中身に合わせて引く（_fit_main）。
func _main_shot() -> Dictionary:
	var d := _cam_distance
	var drift := Vector3(sin(_t * 0.2 * TAU) * 0.1 + sin(_t * 0.33 * TAU) * 0.05, sin(_t * 0.27 * TAU) * 0.08, 0.0)
	# 少しだけ上から（距離の 8%）。真横から見ると腹ばいの体が薄く見えるため。
	var lift := _cam_aim + d * 0.08
	var eye := _fall + Vector3(_cam_center_x, lift, -d) + drift
	var target := _fall + Vector3(_cam_center_x, _cam_aim, 0.6) + drift
	var punch := clampf((_t - _punch_at) / 0.3, 0.0, 1.0)
	if punch > 0.0 and punch < 1.0:
		var amount := sin(PI * punch) * 0.6
		eye += (Vector3(SIDE_X * _punch_side, 0.4, 0.0) - Vector3(0.0, lift, -d)).normalized() * amount
	var shake := clampf((_t - _shake_at) / 0.25, 0.0, 1.0)
	if shake > 0.0 and shake < 1.0:
		eye += Vector3(sin(_t * 90.0), cos(_t * 77.0), 0.0) * 0.08 * (1.0 - shake)
	return {"transform": _look(eye, target), "fov": MAIN_FOV}


# ------------------------------------------------------------------ finish (4.4)

func _update_finish(delta: float) -> void:
	var f := _t - _finish_at
	var w := _winner
	var l := _loser
	if f < F_RELEASE:
		# 勝者は全開で上へ抜け、敗者は落ち続ける（カメラは敗者と同じ速さ）。
		if _t >= float(_stage_at[w]):
			(_canopies[w] as ParachuteCanopy).set_stage(3)
			_stage_at[w] = INF
		var snatch := clampf(f / 0.35, 0.0, 1.0)
		var up := WINNER_RISE * (1.0 - pow(1.0 - clampf(f / F_RELEASE, 0.0, 1.0), 2.0))
		var wc := _fall + Vector3(SIDE_X * _side(w), float(_rise[w]) + up, 0.0)
		_pose_actor(w, _box_basis().slerp(_upright_basis(Vector3(0, 0, -1)), snatch), wc, _mix(POSE_BOX, POSE_CANOPY, snatch))
		_place_canopy(w, delta, snatch)
		var panic := smoothstep(0.6, 0.9, f)
		var lc := _fall + Vector3(SIDE_X * _side(l), float(_rise[l]), 0.0) + _drift(l) * 2.0
		var loser_body := _box_basis().slerp(_upright_basis(Vector3(0, 0.3, -1).normalized()).rotated(Vector3.RIGHT, 0.5), panic)
		_pose_actor(l, loser_body, lc, _with_wobble(_mix(POSE_BOX, POSE_PANIC, panic), l, 1.0 + 4.0 * panic))
		if f >= 0.6 and _cue("hanky", true):
			(_canopies[l] as ParachuteCanopy).show_hanky(true)
			(_canopies[l] as ParachuteCanopy).set_stage(0)
		_place_canopy(l, delta)
		_clouds.advance(ParachuteGame.FALL_SPEED * delta)
		_update_sea(delta)
		_set_camera(_look(_fall + Vector3(-1.0, -5.0, -10.0), _fall + Vector3(0.0, 3.6, 0.0)), 62.0, "c7_release")
		return
	# 海面の高さの着地のセット（ここでカット）。
	if _cue("landing_cut", true):
		_cut_next = true
		_clouds.visible = false
		_sea_y = _fall.y - LANDING_DROP - _float_pad_top()
		_landing = Vector3(_fall.x, _sea_y, _fall.z)
	_update_sea(delta)
	var top := _float.land_point() if _float != null else _landing + Vector3(0.0, 0.7, 0.0)
	# 敗者：頭から海へ（2.2 秒で水柱）。
	var fall_t := f - F_RELEASE
	var loser_start := _landing + Vector3(-9.0, 9.0, 3.0)
	var lc := loser_start + Vector3(0.0, -15.0 * fall_t, 0.0)
	if f < F_SPLASH:
		_pose_actor(l, _upright_basis(Vector3(0, 0, 1)).rotated(Vector3.RIGHT, PI * 0.85), lc, _with_wobble(POSE_PANIC, l, 4.0))
		_place_canopy(l, delta)
	else:
		(_actors[l].root as Node3D).visible = false
		(_canopies[l] as ParachuteCanopy).visible = false
		if _cue("splash", true):
			_splash.global_position = Vector3(loser_start.x, _sea_y, loser_start.z)
			_splash.play()
			AudioManager.play_sfx(&"body_burst", -6.0)
		else:
			_splash.advance(delta)
	# 勝者：ゆっくり降りてきて、フレアで止まり、着地面の中心に着地。
	var winner_start := _landing + Vector3(2.0, 14.0, 1.0)
	var wc := Vector3.ZERO
	var body := _upright_basis(Vector3(0, 0, 1))
	var pose: Array = POSE_CANOPY
	var canopy := _canopies[w] as ParachuteCanopy
	if f < F_DESCEND:
		var u := (f - F_RELEASE) / (F_DESCEND - F_RELEASE)
		wc = winner_start.lerp(top + Vector3(0.0, 1.0 + 1.32, 0.0), 1.0 - pow(1.0 - u, 2.0))
		wc += Vector3(sin(f * 2.1) * 0.25, 0.0, 0.0)
		_place_canopy(w, delta, 1.0)
	elif f < F_LAND:
		var u := (f - F_DESCEND) / (F_LAND - F_DESCEND)
		wc = (top + Vector3(0.0, 1.0 + 1.32, 0.0)).lerp(top + Vector3(0.0, 1.32, 0.0), u * u)
		pose = _mix(POSE_CANOPY, POSE_FLARE, smoothstep(0.0, 0.6, u))
		if u > 0.8:
			pose = _mix(POSE_FLARE, POSE_LAND, smoothstep(0.8, 1.0, u))
		_place_canopy(w, delta, 1.0)
	else:
		if _cue("land", true):
			_float.dip()
			AudioManager.play_sfx(&"jump_land", -4.0)
			# パラシュートは肩から外れて、人の後ろの床へ落ちる（ライザーのつけ根が体にめり込まないように）
			_landed_canopy = canopy.global_transform
		wc = top + Vector3(0.0, 1.32, 0.0)
		var g := f - F_LAND
		pose = _mix(POSE_LAND, POSE_WIN, smoothstep(F_COVER - F_LAND, F_DONE - F_LAND, g))
		canopy.collapse = smoothstep(0.1, F_COVER - F_LAND + 0.2, g)
		_lay_canopy(w, delta)
	_pose_actor(w, body, wc, _with_wobble(pose, w, 0.5))
	if f < F_DESCEND:
		var look := _landing + Vector3(-6.0, 2.0, 0.0)
		if f > F_SPLASH:
			look = look.lerp(wc, smoothstep(F_SPLASH, F_SPLASH + 1.2, f))
		_set_camera(_look(_landing + Vector3(-2.0, 3.0, 24.0), look), 55.0, "c8_sea")
	else:
		if _cue("cut_landing", true):
			_cut_next = true
		var a := deg_to_rad(lerpf(20.0, 90.0, smoothstep(F_DESCEND, F_DONE, f)))
		_orbit = a
		var eye := top + Vector3(sin(a) * LANDING_RADIUS, 1.9, cos(a) * LANDING_RADIUS)
		_set_camera(_look(eye, top + Vector3(0.0, 1.3, 0.0)), 46.0, "c9_landing")


## 着地台だけを浮かべ続ける（ダンスと迎えの間）。
func _update_float_only(delta: float) -> void:
	_update_sea(delta)


# ------------------------------------------------------------------ the winner's dance (6.6)

func pose_winner_waiting(player: int, time: float) -> void:
	if _released or not _actors.has(player):
		return
	if _phase == "finish":
		_phase = "dance"
		_phase_t = 0.0
		_dance_t = 0.0
		_dance_slot = -1
		_dance_prev_mask = director.emote_keys(player) if director != null else 0
		_float.set_tally(true)
	_dance_t = time
	var mask := director.emote_keys(player) if director != null else 0
	var pressed := mask & ~_dance_prev_mask
	_dance_prev_mask = mask
	for slot in range(3):
		if pressed & (1 << slot):
			_start_dance(slot)
			break
	if _dance_slot < 0 and time >= DANCE_AUTO:
		_start_dance(0)
	var top := _float.land_point()
	var root := _actors[player].root as Node3D
	var camera := director.main_camera()
	_pose_actor(player, _upright_basis(Vector3(0, 0, 1)), top + Vector3(0.0, 1.32, 0.0), POSE_WIN)
	_lay_canopy(player, 0.0)
	if _dance_slot >= 0 and _dances.has(_dance_slot) and camera != null:
		var dance := _dances[_dance_slot] as ResultWinnerDance
		dance.apply(root, _actors[player].parts, camera, ResultWinnerDance.START + (time - _dance_started), top.y)


func _start_dance(slot: int) -> void:
	_dance_slot = slot
	_dance_started = _dance_t
	AudioManager.play_sfx(&"ui_click", -6.0)


func release_avatar(player: int) -> void:
	_released = true
	_phase = "released"
	if not _actors.has(player):
		return
	var root := _actors[player].root as Node3D
	var pelvis := _actors[player].parts.get("pelvis") as Node3D
	var at := pelvis.global_position if pelvis != null else root.global_position
	root.visible = false
	(_canopies[player] as ParachuteCanopy).visible = false
	var puppet := director.puppet(player)
	if puppet != null:
		var to_rung := extract_point(player) - at
		puppet.pose("Idle_Loop", 0.0)
		puppet.stand_at(at, atan2(to_rung.x, to_rung.z), _float.land_point().y)
		puppet.set_visible(true)
	_float.set_tally(false)


func extract_point(_player: int) -> Vector3:
	if _float == null:
		return _landing
	return _float.land_point() + Vector3(-2.3, -0.05, 0.4)


func extract_camera(player: int, heli_position: Vector3) -> Dictionary:
	var top := _float.land_point() if _float != null else _landing
	if not _released:
		# 着地台のまわりをゆっくり回る。最後は少し引いてヘリと縄ばしごを入れる。
		var a := _orbit + deg_to_rad(ORBIT_SPEED) * _dance_t
		var pull := smoothstep(EXTRACT_DELAY + 1.0, EXTRACT_DELAY + 2.4, _dance_t)
		var radius := lerpf(DANCE_RADIUS, 11.0, pull)
		var eye := top + Vector3(sin(a) * radius, lerpf(2.1, 2.8, pull), cos(a) * radius)
		var target := top + Vector3(0.0, lerpf(1.3, 2.6, pull), 0.0)
		return {"transform": _look(eye, target), "fov": 44.0 + 8.0 * pull}
	var winner_at := director.puppet(player).center() if director.puppet(player) != null else top
	return {"transform": _look(top + Vector3(3.5, 2.6, 10.5), (winner_at + heli_position) * 0.5), "fov": 55.0}


# ------------------------------------------------------------------ HUD

func _update_hud() -> void:
	if _hud == null:
		return
	var game := _game()
	var state := {}
	var english := director.game_state.use_english_ui if director.game_state != null else false
	_hud.english = english
	if _phase == "rules":
		state["rules"] = true
		state["rules_prompt"] = _t - _rules_at >= RULE_HOLD
	var in_game := _phase in ["countdown", "main"] or (_phase == "finish" and _t - _finish_at < F_RELEASE)
	if in_game and game != null:
		var quiz := game.current_quiz()
		var showing := game.phase in ["question", "reveal"] and quiz != null
		if showing:
			var keys: Array = []
			var count := quiz.c.size()
			for i in range(count):
				var key := QuizGameState.sudden_death_key_for_choice(i, count)
				keys.append([SuddenDeathHud.KEY_LABELS[0][key] if key >= 0 else "", SuddenDeathHud.KEY_LABELS[1][key] if key >= 0 else ""])
			state["quiz"] = {"visible": true, "number": game.question_index + 1, "text": quiz.q, "choices": quiz.c, "keys": keys,
				"timer": game.time_left_ratio(), "reveal": game.phase == "reveal" or game.finished, "correct": game.correct_choice(),
				"picks": game.picks.duplicate() if (game.phase == "reveal" or game.finished) else [-1, -1],
				"final": game.final, "locked": game.final_locked.duplicate()}
		var tags := ["", ""]
		for player in [1, 2]:
			var tag: Array = _tags[player]
			if _t - float(tag[1]) < TAG_TIME and _t >= float(tag[1]):
				tags[player - 1] = _hud._t(str(tag[0]))
			elif game.phase == "question" and game.picks[player - 1] >= 0 and not game.final:
				tags[player - 1] = _hud._t("answered")
		state["status"] = {"visible": true, "stage": [(_canopies[1] as ParachuteCanopy).stage, (_canopies[2] as ParachuteCanopy).stage], "tags": tags}
		state["altimeter"] = {"visible": true, "altitude": game.altitude, "rel": [float(_rise[1]), float(_rise[2])]}
		state["final_alert"] = game.final and game.phase in ["question", "final_intro"]
	if _winner > 0 and ((_phase == "finish" and _t - _finish_at >= F_LAND) or _phase == "dance"):
		state["winner"] = _winner
	if _phase == "dance" and not _released:
		var left := int(ceil(maxf(EXTRACT_DELAY + 2.4 - _dance_t, 0.0)))
		state["emote"] = {"visible": true, "player": _winner, "names": _dance_names, "playing": _dance_slot, "seconds": left}
	_hud.set_state(state)


# ------------------------------------------------------------------ pieces

func _game() -> ParachuteGame:
	if director == null or director.game_state == null:
		return null
	return director.game_state.sudden_death_game as ParachuteGame


func _float_pad_top() -> float:
	return _float.pad_top if _float != null else 0.7


## 海と着地台を今の高さへ。空のセットの海（ocean）を上下させる。
func _update_sea(delta: float) -> void:
	var sky := director.sky_set()
	if sky != null and sky.ocean != null:
		sky.ocean.position.y = _sea_y - sky.global_position.y
	if _float != null:
		_float.float_at(Vector3(_fall.x, 0.0, _fall.z), _sea_y, delta)


func _restore_sea() -> void:
	var sky := director.sky_set() if director != null else null
	if sky != null and sky.ocean != null:
		sky.ocean.position.y = -SuddenDeathSkySet.FLY_HEIGHT


func _place_canopy(player: int, delta: float, upright := 0.0) -> void:
	var canopy := _canopies[player] as ParachuteCanopy
	var parts: Dictionary = _actors[player].parts
	var spine := parts.get("spine") as Node3D
	if spine == null:
		return
	canopy.visible = (_actors[player].root as Node3D).visible
	var shoulder := spine.global_transform * Vector3(0.0, 0.45, -0.1)
	var body := (_actors[player].root as Node3D).global_basis
	var head := body.y.normalized()
	var up := (Vector3.UP + head * 0.25).normalized().lerp(head, upright).normalized()
	var side := body.x.slide(up).normalized()
	# 布の前（+Z）を体の前へ（右手系のまま。以前は −Z で裏返り、着地でつぶれた布が人の前へ落ちていた）
	var fwd := side.cross(up).normalized()
	canopy.place(Transform3D(Basis(side, up, fwd), shoulder), delta)


## 着地のあと：パラシュートを着地台の床（人の後ろ）へ落とす。着地台は波で上下・傾くので、毎フレーム床の置き場所を渡し直す。
func _lay_canopy(player: int, delta: float) -> void:
	var canopy := _canopies[player] as ParachuteCanopy
	if _float == null:
		return
	canopy.drop_to(_float.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, _float.pad_top, -GROUND_BEHIND)))
	canopy.place(_landed_canopy, delta)


func _drift(player: int) -> Vector3:
	var p := float(player)
	var t := _t * _slow
	return Vector3(sin(t * 0.9 + p) * 0.12, sin(t * 1.3 + p * 2.0) * 0.08, sin(t * 0.7 + p) * 0.1)


## 腹ばい（頭は -Z、胸は下）。
func _box_basis() -> Basis:
	return _frame(Vector3(0.0, 0.35, -1.0).normalized(), Vector3(0, -1, 0))


## 立った向き（胸を front へ）。
func _upright_basis(front: Vector3) -> Basis:
	return _frame(Vector3.UP, front)


func _frame(head: Vector3, front: Vector3) -> Basis:
	var y := head.normalized()
	var z := front.slide(y).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## ばたつきから腹ばいへ：体の向きをまぜ、ばたつきの間は少し回る。
func _body_basis(a: Basis, b: Basis, w: float, tumble: float) -> Basis:
	var q := a.get_rotation_quaternion().slerp(b.get_rotation_quaternion(), clampf(w, 0.0, 1.0))
	var wobble := Basis(Vector3.UP, sin(tumble * 2.3) * 0.5 * (1.0 - w)) * Basis(Vector3.RIGHT, sin(tumble * 3.1) * 0.3 * (1.0 - w))
	return wobble * Basis(q)


## 人形を置き、関節の角度の表を当てる（休めの姿から）。
func _pose_actor(player: int, body: Basis, center: Vector3, pose: Array) -> void:
	var actor: Dictionary = _actors[player]
	var root := actor.root as Node3D
	root.global_transform = Transform3D(body.orthonormalized(), center)
	var parts: Dictionary = actor.parts
	var rest: Dictionary = actor.rest
	for key: Variant in rest:
		(parts[key] as Node3D).transform = rest[key]
	for row: Array in pose:
		var node := parts.get(row[0]) as Node3D
		if node == null:
			continue
		var axis := (root.global_basis * (AXES[row[1]] as Vector3)).normalized()
		node.global_basis = Basis(axis, deg_to_rad(float(row[2]))) * node.global_basis


## 2つの表を w でまぜる（片方にない角度は 0 とみなす）。
func _mix(a: Array, b: Array, w: float) -> Array:
	var order: Array[String] = []
	var va := {}
	var vb := {}
	for row: Array in a:
		var key := "%s|%s" % [row[0], row[1]]
		if not va.has(key):
			order.append(key)
		va[key] = float(va.get(key, 0.0)) + float(row[2])
	for row: Array in b:
		var key := "%s|%s" % [row[0], row[1]]
		if not va.has(key) and not vb.has(key):
			order.append(key)
		vb[key] = float(vb.get(key, 0.0)) + float(row[2])
	var out: Array = []
	for key: String in order:
		var parts := key.split("|")
		out.append([parts[0], parts[1], lerpf(float(va.get(key, 0.0)), float(vb.get(key, 0.0)), clampf(w, 0.0, 1.0))])
	return out


func _add(a: Array, extra: Array) -> Array:
	var out := a.duplicate()
	out.append_array(extra)
	return out


## 風で手足が小さく揺れる（周期の違う揺れを重ねる。2人で位相をずらす）。
func _with_wobble(pose: Array, player: int, amount: float) -> Array:
	var p := float(player) * 1.7
	var t := _t * _slow
	return _add(pose, [
		["l_shoulder", "z", sin(t * TAU / 0.7 + p) * 4.0 * amount],
		["r_shoulder", "z", sin(t * TAU / 0.7 + p + 1.1) * 4.0 * amount],
		["l_knee", "x", sin(t * TAU / 1.1 + p) * 5.0 * amount],
		["r_knee", "x", sin(t * TAU / 1.1 + p + 0.8) * 5.0 * amount],
		["spine", "z", sin(t * TAU / 1.9 + p) * 2.0 * amount],
	])


func _set_camera(xf: Transform3D, fov: float, shot: String) -> void:
	_shot = shot
	_camera = {"transform": xf, "fov": fov, "cut": _cut_next, "shot": shot}
	_cut_next = false


func _look(eye: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


func _side(player: int) -> float:
	return 1.0 if player == 1 else -1.0


func _cue(name: String, when: bool) -> bool:
	if not when or _cues.has(name):
		return false
	_cues[name] = _t
	return true


# ------------------------------------------------------------------ teardown and debug

func teardown() -> void:
	_restore_sea()
	for dance: Variant in _dances.values():
		(dance as ResultWinnerDance).clear()
	_dances.clear()
	if _hud != null:
		_hud.hide_all()
	if _world != null:
		_world.visible = false
	_phase = "idle"


func debug_step_clock(seconds: float) -> void:
	if _hud != null:
		_hud.debug_manual_clock = true
		_hud.debug_step(seconds)


func get_debug_snapshot() -> Dictionary:
	var stages := []
	var centers := []
	for player in [1, 2]:
		if _canopies.has(player):
			stages.append((_canopies[player] as ParachuteCanopy).stage)
		if _actors.has(player):
			var root := _actors[player].root as Node3D
			centers.append([snappedf(root.global_position.x, 0.01), snappedf(root.global_position.y, 0.01), snappedf(root.global_position.z, 0.01)])
	var predicted := {}
	if _built and _phase in ["main", "countdown", "rules"]:
		var xf := _main_pose(_cam_distance, _cam_aim, _cam_center_x)
		var tan_v := tan(deg_to_rad(MAIN_FOV) * 0.5)
		for key: String in framing().points:
			var local: Vector3 = xf.affine_inverse() * (framing().points[key] as Vector3)
			predicted[key] = snappedf((0.5 - local.y / maxf(-local.z, 0.5) / (2.0 * tan_v)) * 720.0, 1.0)
		predicted["d"] = snappedf(_cam_distance, 0.01)
		predicted["aim"] = snappedf(_cam_aim, 0.01)
	return {"fit": predicted, "phase": _phase, "t": snappedf(_t, 0.01), "shot": _shot, "slow": snappedf(_slow, 0.01), "stages": stages,
		"centers": centers, "sea_y": snappedf(_sea_y, 0.01), "winner": _winner, "dance_slot": _dance_slot,
		"dance_names": _dance_names, "released": _released, "built": _built,
		"hud": _hud.get_debug_snapshot() if _hud != null else {}}
