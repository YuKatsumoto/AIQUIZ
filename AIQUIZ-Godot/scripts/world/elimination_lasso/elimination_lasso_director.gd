class_name EliminationLassoDirector
extends Node3D

## 両者脱落のあと（2 人の 10 問。ローカルとオンライン）、結果発表へ移るまでの演出（docs/elimination_lasso.md）。
## 画面を暗くして切り替える代わりに、2 人の魂が死んだ所（体が砕けた所）から抜け出し（幽体離脱）、その場で浮かんで
## 動かずに待つ。雲に乗ったハテナが投げ縄で 2 人を捕まえて、コースの上を飛んでゴールの先のレーンへ降ろす。
## 魂はそのまま結果発表の幽霊として渡す（ResultCeremonyDirector.soul_source）。
##
## 捕まえ方は 2 人の間の距離で変わる（ONE_LOOP_MAX_SEP）：
##   近い → 縄 1 本。輪を 2 人の並ぶ向きへ広げて 2 人の頭の上から落とし、締めて 2 人をまとめる（魂は寄せない）。
##   遠い → 両手に 1 本ずつ縄を持って頭上で回し、それぞれの魂へ同時に投げて、1 人ずつ締める。
##
## 時間の流れ（秒。T_* の定数）：
##   0.0 魂が死んだ所からその場で起き上がって真上へ浮かぶ（横へは動かない）
##   → 0.05 雲がコースの先の空から一気に降りてきて、2 人の前の上に止まって 2 人（うしろのカメラ）の方を向く
##   → 1.2 ハテナが縄を頭上へ上げて回し始める（だんだん速く・大きく）→ 2.55 投げる → 3.05 輪が頭を越えて落ちる
##   → 3.2 引いて締める → 3.56 真上へ吊り上げる → 3.76〜7.7 壁より高く飛び、コース（ベルト・壁・左右の客席）を流して
##   ゴールの門を呼び寄せる → 6.75 門の手前へ低く降りる → 7.55 縄を引いて 2 人をうしろへ振り上げ → 8.1 前へ振り抜いて投げつける
##   → 2 人はラグドール（LassoSoulRagdoll）になって回りながら門の下をくぐり、ゴールラインの先に叩きつけられて転がる
##   → 止まったその場で自然に起き上がり、自分のレーン（スコアタワーへの行進の始まり）へ歩く
##   → 2 人とも着いたら結果発表（GameWorld が begin_elimination_result_ceremony）。そのままスコアタワーへ行進する。
##   ハテナは小さな輪を回しながら、門を越えて空へ帰る。
## カメラはカットを使わず、寄り（ズーム）や回り込みもしない。ゲームオーバーのカメラから一度だけ、2 人・止まったハテナ・
## 広げた輪が収まる画へ寄せて捕まえるまで動かさず、運ぶ間は斜めうしろから追い、投げつける所は門の手前の低い所から
## 門越しに見て、最後は結果発表の最初のカメラ（CameraController.result_ceremony_camera_pose）へ寄せて渡す。
## コースを流す（world_scroll_z を進める）間、GameWorld は左右の客席も同じだけ後ろへ流す（StageEnvironment.set_grandstand_shift）。
## 壁は雲の下をくぐって後ろへ流れる。
## 座標はすべて GameWorld のローカル（このノードは GameWorld の直下で、変換なし）。

const RIG_SCALE := 0.85
const ROPE_RADIUS := 0.03
## 2 人をまとめて縛った束で、魂の根が真ん中から離れる距離
const SOUL_SEP_BOUND := 0.6
## 締めた輪（胸の帯）の高さ（魂の根から）と、帯の輪郭の半分の幅・奥行き（束の空間）：2 人をまとめた帯・1 人の帯
const BAND_Y := 0.18
const BAND_HALF := Vector2(1.2, 0.19)
const SOLO_BAND_HALF := Vector2(0.34, 0.25)
## 飛ぶ輪の開いた半径（2 人をまとめる輪・1 人の輪）、頭の上を越える高さ（輪を落とす所の魂の根から）
const R_OPEN := 1.62
const R_OPEN_SOLO := 1.05
const OVER_HEADS := 1.7
## 2 人の間（水平）がこれ以下で、高さの差も ONE_LOOP_MAX_RISE 以下なら、縄 1 本の輪を広げて 2 人まとめて捕まえる。
## それより離れていれば、両手に 1 本ずつ縄を持って、それぞれに投げる。
const ONE_LOOP_MAX_SEP := 4.5
const ONE_LOOP_MAX_RISE := 1.0
## 広げた輪が、2 人の並ぶ向きに魂の真ん中から取るゆとり
const LOOP_MARGIN := 0.85
## 吊り上げて飛ぶときの縄の長さ・ゴールの手前で振り回すときの縄の長さ
const L_HAUL := 3.0
const L_FLING := 2.2
## 吊られた束が縄の向きへ傾く上限（度）
const MAX_BUNDLE_TILT_DEG := 34.0
## 両手の縄で吊った 2 人が、ぶつかって重ならない距離（結び目どうし）
const SOLO_BUNDLE_GAP := 0.85
## 雲の止まる所：魂の前（コースの先の側）か後ろへの距離と、いちばん高い魂の根からの高さ。雲は魂の方を向く。
## 前に止まりたいのに目の前の壁で場所がなければ、魂の横（コースの真ん中の側。x）の少し後ろ（z）
const CLOUD_AHEAD := 4.6
const CLOUD_RISE := 3.5
const CLOUD_SIDE := Vector2(6.3, -1.6)
## 体から抜け出して浮かぶ高さ（その場で真上へ。魂は捕まるまで横へ動かない）
const SOUL_RISE := 1.25
## 運ぶ高さ（壁とゴールの門の上を、ぶら下がった 2 人の足が越える）
const CRUISE_MIN_Y := 11.8
## 縄を回す中心（ハテナの空間。右肩の上）、手の回る半径、手から輪の結び目までの長さ
const TWIRL_PIVOT := Vector3(-0.56, 1.06, 0.08)
## 両手に縄を持つとき：手を左右へ広げて回す中心（右手。左手は x を反す）、結び目を手から外へずらす量・手からの高さ、
## 輪のいちばん大きい半径。2 つの輪は同じ向き・同じ角度で回るので、結び目の間（約 2 m）を保ったまま重ならない
const TWIN_PIVOT := Vector3(-0.8, 0.98, 0.1)
const TWIN_KNOT_OUT := 0.24
const TWIN_SPOKE := 1.0
const TWIN_RADIUS := 0.62
## 両手の縄で 1 人ずつ吊って運ぶあいだ、2 人をぶん回す速さ（1 秒の回転数。いちばん速いとき。回し方は _whirl_omega）
const WHIRL_REV := 0.8
## ぶん回し方：WHIRL_NONE はぶん回さず、ふつうに吊って運ぶ（いまの演出）。WHIRL_VERTICAL は両腕を風車のように回し、
## 2 人を左右それぞれ縦の円で振り回す（上を通って前へ振り下ろす）。WHIRL_HORIZONTAL は雲ごと回り、2 人を水平の円で振り回す。
enum WhirlStyle { WHIRL_NONE, WHIRL_VERTICAL, WHIRL_HORIZONTAL }
const WHIRL_STYLE := WhirlStyle.WHIRL_NONE
## 縦に振り回すとき、腕を回す中心（ハテナの空間。右手。左手は x を反す）と手の回る半径
const WINDMILL_PIVOT := Vector3(-0.8, 0.84, 0.05)
const WINDMILL_HAND_RADIUS := 0.2
const TWIRL_HAND_RADIUS := 0.05
const TWIRL_SPOKE := 0.95
## 輪の外側の上がり（度。負なら垂れる）
const TWIRL_DROOP_DEG := -5.0
## 投げつける前に雲が止まる所（ゴールラインの何 m 手前・高さ）。2 人は門の梁（床から 5 m）の下をくぐって飛ぶ。
const FLING_BACK := 5.6
const FLING_Y := 4.2
## 放してから床に着くまで（秒）、起き上がる長さ、立ってから歩く速さ（m/秒）
const FLING_FLIGHT := 0.95
const GET_UP_TIME := 0.85
const WALK_SPEED := 2.2
## 投げつけたラグドールが落ちる所（レーンの何 m 手前）。ゴールラインのすぐ先に落ちて少し転がり、結果発表の
## 最初のカメラに映る所（レーンの少し手前）で止まる
const FLING_SHORT := 0.1

## 一連の流れはテンポよく（魂が浮かぶのと同時に雲が飛んでくる）
const T_RISE := 0.7
const T_CLOUD_START := 0.05
const T_CLOUD_ARRIVE := 1.3
const T_WINDUP := 1.2
const T_TWIRL := 1.5
const T_RELEASE := 2.55
const T_OVER_HEADS := 3.05
const T_CINCH := 3.2
## 締め終わり（広げた輪なら、この間に 2 人が輪に引き寄せられてくっつく）
const T_CINCHED := 3.44
const T_YANK := 3.56
const T_CRUISE := 4.4
## コースを流す（ゴールまで飛ぶ）：吊り上げてすぐ流し始め、加速 → 一定の速さ → 減速して、門の前で止まる
## （SCROLL_ACCEL・SCROLL_DECEL）。観客席も一緒に流れる（StageEnvironment.set_grandstand_shift）。
const T_SCROLL_START := 3.76
const T_SCROLL_END := 7.7
const T_DESCEND := 6.75
const T_FLING_SET := 7.5
const T_WIND := 7.55
const T_FLING := 8.1
const T_EXIT := 8.4
## 2 人が起き上がるのを待つ上限（転がって止まらなくても、ここで起き上がらせる）と、結果発表の上限
const T_GET_UP_LATEST := 9.7
const T_CEREMONY_LATEST := 12.5
## 雲が飛び去って消える（_plan_exit の最後）
const T_END := 14.8
## コースを流す速さの、加速・減速にかける割合（流す時間のうち）
const SCROLL_ACCEL := 0.3
const SCROLL_DECEL := 0.4
## 回す速さ（1 秒の回転数）：回し始め → 投げる直前
const TWIRL_REV_START := 0.7
const TWIRL_REV_END := 2.0


## 縄 1 本の受け持ち。輪を広げて 2 人をまとめて捕まえるか、片手の縄で 1 人を捕まえる。締めたあとは、結び目から
## 吊られた束（巻きついた帯と、そこに縛られた魂）の振り子。座標は GameWorld のローカル。
class LassoCatch:
	var rope: LassoRope = null
	## 縄を持つ手（"R" / "L"）。左手の縄は右手の縄の鏡うつしで回して投げる
	var hand := "R"
	var players: Array[int] = []
	## 束の空間で、魂の根が並ぶ x（プレイヤー → x）
	var slots := {}
	## 輪を落とす所（魂の根の高さ）と、束の始まりの向き（ヨー。束の x が 2 人の並ぶ向き）・運ぶあいだに回る向き
	var target := Vector3.ZERO
	var yaw0 := 0.0
	var yaw_haul := 0.0
	## 開いた輪：束の x の向きの半径・その直角の半径、2 人の高さの差による傾き（束の x の 1 m あたりの上がり）
	var open_a := 1.0
	var open_b := 1.0
	var slope := 0.0
	## 締めた帯の輪郭の半分の幅・奥行きと、結び目の角度（束の空間。前の真ん中 = 0）
	var band_half := Vector2(0.3, 0.2)
	var honda_angle := 0.0
	## 運ぶあいだの束のよじれの位相
	var twist_phase := 0.0
	var release_center := Vector3.ZERO
	var release_u := Vector3.FORWARD
	var release_radius := 0.5
	var bundle := Transform3D.IDENTITY
	var bundle_up := Vector3.UP
	var honda_pos := Vector3.ZERO
	var honda_vel := Vector3.ZERO
	var rope_len := 3.0
	var pendulum_started := false
	var hand_prev := Vector3.ZERO
	## ぶん回すときの結び目の目標（前のフレーム。速さを求める）
	var whirl_prev := Vector3.INF


var game_state: QuizGameState = null
var player_controller: PlayerController = null
var camera_controller: Node3D = null
var world: Node3D = null

var _active := false
var _handed_over := false
var _t := 0.0
var _quality := GraphicsQuality.BALANCED
var _rider: LassoCloudRider = null
## 右手の縄（輪を広げて 2 人をまとめるときはこれだけ）と、両手に持つときの左手の縄
var _rope: LassoRope = null
var _rope_l: LassoRope = null
var _catches: Array[LassoCatch] = []
var _catch_of := {}
## 両手に 1 本ずつ縄を持つか（2 人が離れている）と、確かめ用の名前（one_loop / two_ropes）
var _two_ropes := false
var _mode_name := ""
## 縄が当たる床の高さ（魂が海の上にいれば海の高さ）
var _rope_floor_y := StageConstants.FLOOR_TOP_Y
var _souls := {}
var _released := {}
## 魂の根：死んだ所（抜け出す所）と、真上へ浮かんで止まる所
var _soul_start := {}
var _soul_rise := {}
## 雲の止まる所の x の側（+1 = +X。コースの真ん中の側）
var _cloud_side := -1.0
## 捕まえるまでの画（動かさない。2 人・止まったハテナ・広げた輪が収まる所）
var _stage_shot := {}
## コースを流す：始まりと終わりの world_scroll_z
var _scroll_from := 0.0
var _scroll_to := 0.0
var _cruise_y := CRUISE_MIN_Y
## 今出ている壁のいちばん高い所（GameWorld のローカルの y）
var _wall_top := 4.6
## 前のフレームの world_scroll_z（流れる速さを求める）
var _scroll_prev := 0.0
## 雲の向き（ヨー）の、ぶん回す分を足す前の値
var _base_yaw := 0.0
## ぶん回す速さに掛ける数（回し終わりでちょうど何周かして前を向くように）
var _whirl_scale := 1.0
## 去り方：下りながら前へ進み、スタンドの手前で横へ旋回して、海の上へ飛び去る道すじ（[時刻, 所]）と向かう側
var _exit_keys: Array = []
var _exit_side := 1.0
## 先に脱落してサメに乗っていた幽霊（GhostSharkRideController.hold_for_elimination_lasso で、乗ったまま待っている）：
## 乗り手のプレイヤー（0 = いない）、引き取る時刻（それまではサメに乗ったまま縄を掛ける。両手の縄なら引き上げる瞬間、
## 縄 1 本なら締めて 2 人を引き寄せる瞬間）、引き取ったときの大きさ（乗っているあいだは小さい。引き取ってから元へ戻す）
var _ride_controller: Node = null
var _shark_rider := 0
var _shark_take_at := INF
var _shark_taken_at := INF
var _shark_rider_scale := 1.0
var _lift_top := Vector3.ZERO
var _cruise_end := Vector3.ZERO
var _fling_pos := Vector3.ZERO
## ゴールへ投げつけたラグドール（プレイヤー → LassoSoulRagdoll）、起き上がり始めた時刻、立った印、
## 立ってから自分のレーンへ歩く（始まりの時刻・所・かかる時間）、レーンに着いた印
var _ragdolls := {}
var _get_up_at := {}
var _stood := {}
var _walk := {}
var _arrived := {}
var _ceremony_at := INF
var _cloud_hover := Vector3.ZERO
var _cloud_start := Vector3.ZERO
var _cloud_p1 := Vector3.ZERO
var _cloud_p2 := Vector3.ZERO
var _cloud_pos := Vector3.ZERO
var _cloud_prev := Vector3.ZERO
var _cloud_vel := Vector3.ZERO
var _cloud_yaw := 0.0
var _cloud_tilt := Vector2.ZERO
var _cloud_tilt_vel := Vector2.ZERO
var _goal_ready := false
var _lanes := {}
var _theta0 := 0.0
var _soul_pos := {}
var _soul_vel := {}
var _cam_eye := Vector3.ZERO
var _cam_target := Vector3.ZERO
var _cam_eye_vel := Vector3.ZERO
var _cam_target_vel := Vector3.ZERO
var _cam_fov := 50.0
var _final_cam := {}
var _cues := {}
var _whirl_count := 0
## 確かめ用（tests/elimination_lasso_runtime.gd の view=）：ハテナを横から寄りで見るカメラ。ふだんは空。
var debug_view := ""


func setup(state: QuizGameState, world_root: Node3D, players: PlayerController, camera_rig: Node3D) -> void:
	game_state = state
	world = world_root
	player_controller = players
	camera_controller = camera_rig
	name = "EliminationLasso"


## 演出を始められるか（素材があり、プレイヤーの体から魂を作れる）。できなければ GameWorld は今までの暗転を使う。
func can_play() -> bool:
	return (
		game_state != null
		and player_controller != null
		and camera_controller != null
		and camera_controller.has_method("set_director_pose")
		and ResourceLoader.exists(LassoCloudRider.CLOUD_GLB)
		and ResourceLoader.exists(LassoCloudRider.MASCOT_GLB)
	)


func is_active() -> bool:
	return _active


var _prewarm_root: Node3D = null


## 試合の読み込み中（覆いの下）に、雲・ハテナ・縄・魂を一度だけカメラの前に描いて、シェーダーを先に作っておく
## （両者脱落のとき、初めて雲が出たフレームで止まらないように）。2 人の 10 問だけ。
func begin_render_prewarm(prewarm_camera: Camera3D) -> void:
	end_render_prewarm()
	if prewarm_camera == null or not can_play() or not game_state.uses_local_result_ceremony():
		return
	_prewarm_root = Node3D.new()
	_prewarm_root.name = "EliminationLassoPrewarm"
	prewarm_camera.add_child(_prewarm_root)
	_prewarm_root.position = Vector3(0.0, -1.0, -6.0)
	var rider := LassoCloudRider.new()
	_prewarm_root.add_child(rider)
	if rider.setup(GraphicsQuality.normalize(GameManager.graphics_quality)):
		rider.scale = Vector3.ONE * RIG_SCALE
		rider.set_puffing(true)
	var rope := LassoRope.new()
	_prewarm_root.add_child(rope)
	rope.setup(ROPE_RADIUS, GraphicsQuality.normalize(GameManager.graphics_quality))
	rope.reset_hanging(Vector3(0.4, 1.0, 0.0), Vector3.RIGHT, 0.3, 0.4)
	rope.rebuild_mesh()
	var soul := player_controller.create_ghost_rider_visual(1) if player_controller != null else null
	if soul != null:
		_prewarm_root.add_child(soul)
		soul.position = Vector3(-1.2, 0.0, 0.0)
		player_controller.make_ghost_rider_translucent(soul)


func end_render_prewarm() -> void:
	if _prewarm_root != null and is_instance_valid(_prewarm_root):
		_prewarm_root.queue_free()
	_prewarm_root = null


## 結果発表を始めてよいか（魂がレーンに着地した）。GameWorld が begin_elimination_result_ceremony を呼ぶ。
func wants_ceremony() -> bool:
	return _active and not _handed_over and (_t >= _ceremony_at or _t >= T_CEREMONY_LATEST)


func elapsed() -> float:
	return _t


func begin() -> bool:
	if _active or not can_play():
		return false
	force_cleanup()
	_quality = GraphicsQuality.normalize(GameManager.graphics_quality)
	_rider = LassoCloudRider.new()
	_rider.name = "HatenaCloud"
	add_child(_rider)
	if not _rider.setup(_quality):
		_rider.queue_free()
		_rider = null
		return false
	_plan_stage()
	_scroll_prev = game_state.world_scroll_z
	_rope = _make_rope("Lasso")
	_rope_l = _make_rope("LassoLeft") if _two_ropes else null
	for c: LassoCatch in _catches:
		c.rope = _rope if c.hand == "R" else _rope_l
		# 両手に縄を持つときは、左手の束（コイル）は描かない
		c.rope.coil_visible = not _two_ropes
	for player_index: int in [1, 2]:
		if player_index == _shark_rider:
			# サメに乗った乗り手は、引き取るまでサメに乗ったまま（姿は乗り手の監督が付ける）
			_souls[player_index] = (_ride_controller.call("get_lasso_hold") as Dictionary).get("rider") as Node3D
			_soul_pos[player_index] = _soul_start[player_index]
			_soul_vel[player_index] = Vector3.ZERO
			_shark_take_at = T_YANK if _two_ropes else T_CINCH
			continue
		var soul := player_controller.create_ghost_rider_visual(player_index)
		if soul == null:
			continue
		soul.name = "LassoSoulP%d" % player_index
		add_child(soul)
		player_controller.make_ghost_rider_translucent(soul)
		player_controller.set_ghost_rider_shader_parameter(soul, &"body_alpha", 0.0)
		_souls[player_index] = soul
		_soul_pos[player_index] = _soul_start[player_index]
		_soul_vel[player_index] = Vector3.ZERO
	_active = true
	_handed_over = false
	_t = 0.0
	_cues.clear()
	_whirl_count = 0
	_goal_ready = true
	_ragdolls.clear()
	_get_up_at.clear()
	_stood.clear()
	_walk.clear()
	_arrived.clear()
	_ceremony_at = INF
	game_state.elimination_lasso_active = true
	# 雲は奥の空で待ち、垂らした小さな輪から始める
	_cloud_pos = _cloud_start
	_cloud_prev = _cloud_start
	_cloud_vel = Vector3.ZERO
	_cloud_yaw = _yaw_of(_cloud_hover - _cloud_start)
	_base_yaw = _cloud_yaw
	_place_rider(0.0)
	_rider.apply_pose(_hatena_pose(0.0))
	for c: LassoCatch in _catches:
		c.rope.reset_hanging(_rider.grip_point(c.hand), _rider.transform.basis.x, 0.3 * RIG_SCALE, 0.42 * RIG_SCALE)
		c.hand_prev = _rider.grip_point(c.hand)
	# カメラは今のゲームオーバーのカメラから始めて、捕まえるまでの画（動かさない）へ一度だけ寄せる
	var camera := camera_controller.get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		var local := _to_local_xform(camera.global_transform)
		_cam_eye = local.origin
		_cam_target = local.origin - local.basis.z * 8.0
		_cam_fov = camera.fov
	_cam_eye_vel = Vector3.ZERO
	_cam_target_vel = Vector3.ZERO
	_stage_shot = _fit(_stage_points(), _look_dir(atan2(0.25 * -_cloud_side, -0.97), deg_to_rad(20.0)), 50.0, 1.1, 6.5)
	_stage_shot["follow"] = 3.2
	_stage_shot["aim"] = 3.6
	AudioManager.play_sfx(&"ghost_soul_rise")
	update(0.0)
	return true


func _make_rope(rope_name: String) -> LassoRope:
	var rope := LassoRope.new()
	rope.name = rope_name
	add_child(rope)
	rope.setup(ROPE_RADIUS, _quality)
	rope.floor_y = _rope_floor_y
	return rope


## 魂・雲・縄の受け持ち・カメラの置き場所を、2 人の死んだ所と目の前の壁から決める。
func _plan_stage() -> void:
	var highest := -INF
	_rope_floor_y = StageConstants.FLOOR_TOP_Y
	# 先に脱落した人がサメに乗ったまま待っていれば、その人の魂はサメの上の乗り手（死んだ所からは出てこない）
	_ride_controller = world.get("_ghost_shark_ride_controller") as Node if world != null else null
	var hold: Dictionary = {}
	if _ride_controller != null and _ride_controller.has_method("get_lasso_hold"):
		hold = _ride_controller.call("get_lasso_hold")
	_shark_rider = int(hold.get("player", 0))
	_shark_take_at = INF
	_shark_taken_at = INF
	for player_index: int in [1, 2]:
		if player_index == _shark_rider:
			var seat := _to_local_point((hold.rider as Node3D).global_position)
			_soul_start[player_index] = seat
			_soul_rise[player_index] = seat
			highest = maxf(highest, seat.y)
			if seat.y - 1.2 < StageConstants.FLOOR_TOP_Y - 0.05:
				_rope_floor_y = StageConstants.OCEAN_SURFACE_Y
			continue
		var death := _death_local(player_index)
		# 体の真ん中より少し下に魂の根を置く（魂の体が倒れた体に重なって起き上がる）。海に落ちたなら水面から
		death.y = maxf(death.y - 0.25, StageConstants.OCEAN_SURFACE_Y + 0.2)
		_soul_start[player_index] = death
		_soul_rise[player_index] = death + Vector3.UP * SOUL_RISE
		highest = maxf(highest, death.y + SOUL_RISE)
		if death.y + SOUL_RISE - 1.2 < StageConstants.FLOOR_TOP_Y - 0.05:
			_rope_floor_y = StageConstants.OCEAN_SURFACE_Y
	var p1: Vector3 = _soul_rise[1]
	var p2: Vector3 = _soul_rise[2]
	var mid := (p1 + p2) * 0.5
	var across := Vector3(p1.x - p2.x, 0.0, p1.z - p2.z)
	_two_ropes = across.length() > ONE_LOOP_MAX_SEP or absf(p1.y - p2.y) > ONE_LOOP_MAX_RISE
	_mode_name = "two_ropes" if _two_ropes else "one_loop"
	# 雲の止まる所：2 人の前（コースの先の側）の上で、2 人の方（うしろのカメラの方）を向く
	_cloud_side = -1.0 if mid.x >= 0.0 else 1.0
	var room := CLOUD_AHEAD
	var wall_z := _wall_ahead_z(mid.z - 0.5)
	if is_finite(wall_z):
		room = minf(room, wall_z - 1.4 - mid.z)
	var cloud_y := highest + CLOUD_RISE
	if room >= 3.6:
		_cloud_hover = Vector3(mid.x + 1.2 * _cloud_side, cloud_y, mid.z + room)
	else:
		_cloud_hover = Vector3(mid.x + CLOUD_SIDE.x * _cloud_side, cloud_y, mid.z + CLOUD_SIDE.y)
	_cloud_hover.x = clampf(_cloud_hover.x, -11.0, 11.0)
	# 雲はコースの先の空から一気に降りてきて、少し回り込んで止まる
	_cloud_start = _cloud_hover + Vector3(3.0 * _cloud_side, 8.0, 16.0)
	_cloud_p1 = _cloud_hover + Vector3(-2.0 * _cloud_side, 4.5, 9.0)
	_cloud_p2 = _cloud_hover + Vector3(3.0 * _cloud_side, 2.0, 3.2)
	_plan_catches(p1, p2, mid, across)
	# 壁とゴールの門の上を、ぶら下がった 2 人の足が越える高さ
	_wall_top = _max_wall_top()
	_cruise_y = maxf(CRUISE_MIN_Y, _wall_top + 5.2)
	_scroll_from = game_state.world_scroll_z
	var goal := game_state.goal_z if game_state.goal_z > 0.0 else game_state.get_local_result_goal_z()
	_scroll_to = maxf(_scroll_from, goal - QuizGameState.RESULT_ELIMINATION_GOAL_AHEAD)
	_lanes.clear()
	_plan_goal()
	_lift_top = Vector3(lerpf(_cloud_hover.x, _fling_pos.x, 0.3), _cruise_y, _cloud_hover.z + 1.6)
	_cruise_end = Vector3(_fling_pos.x, _cruise_y, _fling_pos.z - 1.6)
	_plan_exit()
	# ぶん回す回数：回し終わりでちょうど何周かして前を向くよう、速さを少しだけ合わせる
	var turns := _whirl_turn_integral(T_YANK, _whirl_end()) / TAU
	_whirl_scale = maxf(1.0, roundf(turns)) / turns if turns > 0.01 else 1.0
	_final_cam = _finale_camera_pose()
	# 回す角度：投げる瞬間に、輪の向き（結び目から輪の真ん中）がハテナの前を向くように始まりを決める
	_theta0 = -_twirl_integral(T_RELEASE)


## 縄の受け持ち：近ければ右手の縄 1 本の輪を 2 人の並ぶ向きへ広げる。遠ければ、ハテナから見て右にいる方を右手、
## 左にいる方を左手の縄で捕まえる（2 本の縄が交差しない）。
func _plan_catches(p1: Vector3, p2: Vector3, mid: Vector3, across: Vector3) -> void:
	_catches.clear()
	_catch_of.clear()
	if _two_ropes:
		# ハテナの空間の x：右手は −x の側
		var facing := Basis(Vector3.UP, _yaw_of(mid - _cloud_hover)).inverse()
		var right_player := 1 if (facing * (p1 - _cloud_hover)).x < (facing * (p2 - _cloud_hover)).x else 2
		for player_index: int in [1, 2]:
			var solo := LassoCatch.new()
			solo.hand = "R" if player_index == right_player else "L"
			solo.players.append(player_index)
			solo.slots = {player_index: 0.0}
			solo.target = _soul_rise[player_index]
			if player_index == _shark_rider:
				# サメに乗った乗り手は、乗っている向きのまま縛る
				solo.yaw0 = _shark_rider_yaw()
			solo.open_a = R_OPEN_SOLO
			solo.open_b = R_OPEN_SOLO
			solo.band_half = SOLO_BAND_HALF
			solo.twist_phase = 0.0 if player_index == 1 else 2.1
			_catches.append(solo)
	else:
		var pair := LassoCatch.new()
		pair.players.assign([1, 2])
		pair.target = mid
		# 束の x は 2 人の並ぶ向き（+X の側を向く方）。P1 が −X の側なら、運ぶあいだに束が半回りして P1 を +X へ回す
		var line := across if across.length() > 0.05 else Vector3.RIGHT
		var half := across.length() * 0.5
		line = line.normalized()
		var p1_side := 1.0
		if line.x < 0.0:
			line = -line
			p1_side = -1.0
		pair.yaw0 = atan2(-line.z, line.x)
		pair.yaw_haul = 0.0 if p1_side > 0.0 else PI
		pair.slots = {1: SOUL_SEP_BOUND * p1_side, 2: -SOUL_SEP_BOUND * p1_side}
		pair.open_a = maxf(R_OPEN, half + LOOP_MARGIN)
		pair.open_b = R_OPEN
		pair.slope = clampf((p1.y - p2.y) * p1_side / maxf(2.0 * half, 0.5), -0.6, 0.6)
		pair.band_half = BAND_HALF
		_catches.append(pair)
	for c: LassoCatch in _catches:
		c.bundle = Transform3D(Basis(Vector3.UP, c.yaw0), c.target)
		# 結び目は輪のハテナの側。2 人をまとめた帯なら、前か後ろの真ん中（吊られても 2 人が横倒しにならない）
		var toward := Basis(Vector3.UP, c.yaw0).inverse() * (_cloud_hover - c.target)
		c.honda_angle = atan2(toward.x, toward.z)
		if c.players.size() > 1:
			c.honda_angle = 0.0 if toward.z >= 0.0 else PI
		for player_index: int in c.players:
			_catch_of[player_index] = c


func _to_local_point(global_point: Vector3) -> Vector3:
	return global_transform.affine_inverse() * global_point


## サメに乗った乗り手の向き（ヨー。乗り手の前 = サメの頭の向き）。
func _shark_rider_yaw() -> float:
	var rider := _souls.get(_shark_rider) as Node3D
	if rider == null and _ride_controller != null:
		rider = (_ride_controller.call("get_lasso_hold") as Dictionary).get("rider") as Node3D
	if rider == null or not is_instance_valid(rider):
		return 0.0
	var forward := global_transform.basis.inverse() * rider.global_basis.z
	return _yaw_of(forward) if Vector2(forward.x, forward.z).length() > 1e-3 else 0.0


## サメに乗った乗り手：引き取るまではサメが運ぶ（魂の所と、輪を落とす所は乗り手について動く）。引き取る時刻に
## サメから引きはがし、ここから先はほかの魂と同じに動かす（サメは海へ潜って帰る）。
func _update_shark_rider() -> void:
	if _shark_rider == 0 or not is_finite(_shark_take_at):
		return
	var player_index := _shark_rider
	var rider := _souls.get(player_index) as Node3D
	if rider == null or not is_instance_valid(rider):
		_shark_take_at = INF
		return
	if _t < _shark_take_at:
		var seat := _to_local_point(rider.global_position)
		_soul_start[player_index] = seat
		_soul_rise[player_index] = seat
		var c: LassoCatch = _catch_of.get(player_index)
		if c != null:
			c.target = seat if c.players.size() == 1 else (_soul_rise[1] + _soul_rise[2]) * 0.5
		return
	_shark_take_at = INF
	var taken: Node3D = _ride_controller.call("take_lasso_rider", self) if _ride_controller != null else null
	if taken == null:
		return
	taken.name = "LassoSoulP%d" % player_index
	player_controller.make_ghost_rider_translucent(taken)
	_shark_rider_scale = clampf(taken.transform.basis.get_scale().x, 0.2, 1.0)
	_shark_taken_at = _t
	_souls[player_index] = taken
	_soul_start[player_index] = taken.position
	_soul_rise[player_index] = taken.position
	AudioManager.play_sfx(&"lasso_cinch", -6.0, 1.3)


## サメに乗った乗り手の魂か（まだ引き取っていない）。
func _riding_shark(player_index: int) -> bool:
	return player_index == _shark_rider and not is_finite(_shark_taken_at)


## 魂の大きさ：サメから引き取った乗り手は、乗っていた大きさから元の大きさへなめらかに戻す。
func _soul_scale(player_index: int) -> float:
	if player_index != _shark_rider or not is_finite(_shark_taken_at):
		return 1.0
	return lerpf(_shark_rider_scale, 1.0, _ss(_t, _shark_taken_at, _shark_taken_at + 0.5))


## ゴールのレーン（結果発表の幽霊の始まりの所）と、投げつける前に雲が止まる所。コースを流し終えたあとの位置で求める。
func _plan_goal() -> void:
	var goal_local := game_state.get_local_result_goal_z() - _scroll_to
	for player_index: int in [1, 2]:
		var lane := Vector3(QuizGameState.RESULT_PLAYER_X if player_index == 1 else -QuizGameState.RESULT_PLAYER_X, 0.0,
			goal_local + QuizGameState.RESULT_GOAL_WAIT_OFFSET)
		_lanes[player_index] = lane
	_fling_pos = Vector3(0.0, FLING_Y, goal_local - FLING_BACK)


## 去り方の道すじ：投げつけた所から下りながら前へ進み（2 人の頭の上を越えて）、ゴール観客席の手前で横へ旋回し、
## 横のスタンドの上を越えるように上りながら、海の上へ飛び去る。
func _plan_exit() -> void:
	_exit_side = -_cloud_side
	var g := _fling_pos.z + FLING_BACK
	var s := _exit_side
	_exit_keys = [
		[T_EXIT - 0.3, _fling_rest(T_EXIT - 0.3)],
		[T_EXIT, _fling_rest(T_EXIT)],
		[T_EXIT + 0.8, Vector3(0.5 * s, FLING_Y - 1.3, g + 2.5)],
		[T_EXIT + 1.6, Vector3(1.8 * s, 2.5, g + 9.0)],
		[T_EXIT + 2.4, Vector3(5.5 * s, 3.4, g + 12.5)],
		[T_EXIT + 3.2, Vector3(10.5 * s, 7.5, g + 13.0)],
		[T_EXIT + 4.2, Vector3(17.0 * s, 15.0, g + 11.5)],
		[T_EXIT + 5.4, Vector3(38.0 * s, 22.0, g + 9.0)],
		[T_EXIT + 6.4, Vector3(70.0 * s, 30.0, g + 12.0)],
	]


## 投げつける間の雲の所（振り上げで少しうしろへ引かれ、振り抜きで前へつんのめる）。
func _fling_rest(t: float) -> Vector3:
	return _fling_pos + Vector3(0.0, 0.0, -0.3) * _bump(t, T_WIND, T_FLING - 0.05) + Vector3(0.0, -0.1, 0.5) * _bump(t, T_FLING - 0.08, T_FLING + 0.5)


## ぶん回し（両手の縄で 1 人ずつ吊ったとき）：吊り上げてすぐ雲ごと回り始め、門の手前へ降りながら止めて、回し終わりで
## ちょうど前を向く（2 人は自分の側の手の下にぶら下がり、振り上げ・振り抜きにつながる）。
func _whirl_end() -> float:
	return T_WIND - 0.2


## 回る速さ（rad/秒。_whirl_scale を掛ける前）。
func _whirl_omega(t: float) -> float:
	if not _two_ropes or WHIRL_STYLE == WhirlStyle.WHIRL_NONE:
		return 0.0
	return TAU * WHIRL_REV * _ss(t, T_YANK + 0.15, T_CRUISE) * (1.0 - _ss(t, T_DESCEND - 0.2, _whirl_end()))


func _whirl_turn_integral(a: float, b: float) -> float:
	if b <= a:
		return 0.0
	var steps := 48
	var h := (b - a) / float(steps)
	var total := 0.0
	for i in range(steps):
		total += _whirl_omega(a + (float(i) + 0.5) * h) * h
	return total


## ぶん回した角度（吊り上げた時から。回し終わりでちょうど何周か）。
func _whirl_phase(t: float) -> float:
	if not _two_ropes:
		return 0.0
	return _whirl_turn_integral(T_YANK, minf(t, _whirl_end())) * _whirl_scale


## 雲ごと回す分の向き（水平にぶん回すときだけ）。
func _whirl_spin(t: float) -> float:
	return _whirl_phase(t) if WHIRL_STYLE == WhirlStyle.WHIRL_HORIZONTAL else 0.0


## 縦に振り回すときの、手から結び目への向き（ハテナの空間。0 = 真下、π/2 = うしろ、π = 真上、3π/2 = 前）。
static func _windmill_dir(angle: float) -> Vector3:
	return Vector3(0.0, -cos(angle), -sin(angle))


## 結び目をぶん回しの形（円すい振り子）へ寄せる重み。
func _whirl_weight(t: float) -> float:
	if not _two_ropes or WHIRL_STYLE == WhirlStyle.WHIRL_NONE:
		return 0.0
	return _ss(t, T_YANK + 0.1, T_YANK + 0.6) * (1.0 - _ss(t, _whirl_end() - 0.3, _whirl_end()))


## 今出ている壁のいちばん高い所（GameWorld のローカルの y）。
func _max_wall_top() -> float:
	var top := 4.6
	if world == null:
		return top
	var walls: Variant = world.get("_active_walls")
	if walls is Array:
		for wall: Variant in walls:
			if wall is Node3D and is_instance_valid(wall):
				var value: Variant = (wall as Node3D).get("wall_top_y")
				if value != null:
					top = maxf(top, float(value))
	return top


## 死んだ所（体が砕けた所。PlayerController.get_death_origin_position）を GameWorld のローカルで。
func _death_local(player_index: int) -> Vector3:
	var fallback := Vector3(game_state.player_x, game_state.player_y, game_state.player_local_z) if player_index == 1 \
		else Vector3(game_state.player2_x, game_state.player2_y, game_state.player2_local_z)
	if player_controller == null:
		return fallback
	var world_point := player_controller.get_death_origin_position(player_index == 1)
	var local := world.to_local(world_point) if world != null else world_point
	if not local.is_finite() or local.length() > 400.0:
		return fallback
	return local


func _wall_ahead_z(from_z: float) -> float:
	var best := INF
	if world == null:
		return best
	var walls: Variant = world.get("_active_walls")
	if not (walls is Array):
		return best
	for wall: Variant in walls:
		if wall is Node3D and is_instance_valid(wall):
			var z := (wall as Node3D).position.z
			if z > from_z and z < best:
				best = z
	return best


# ------------------------------------------------------------------ per frame

func update(delta: float) -> void:
	if not _active:
		return
	var dt := clampf(delta, 0.0, 0.05)
	_t += dt
	_update_scroll()
	_update_cloud(dt)
	_rider.apply_pose(_hatena_pose(_t))
	_update_shark_rider()
	_update_souls(dt)
	_update_rope(dt)
	_update_camera(dt)
	_update_sound()
	for c: LassoCatch in _catches:
		c.hand_prev = _rider.grip_point(c.hand)
	if _handed_over and _t >= T_END:
		_finish()


## 雲が壁より高く上がったら、コース（ベルト・壁・ゴール）を流してゴールの門を呼び寄せる。
## 壁は雲の下をくぐって後ろへ流れ、後ろの端で砕かずに消える。流し終えたら、後ろに残った倒れた体を片付ける
## （カメラはもう前を向いていて映らない）。
func _update_scroll() -> void:
	if _t < T_SCROLL_START or _scroll_to <= _scroll_from:
		return
	if not _cues.has("flyover") and world != null and world.has_method("set_elimination_flyover"):
		_cues["flyover"] = _t
		world.call("set_elimination_flyover", true)
	var eased := _cruise_curve(_seg(_t, T_SCROLL_START, T_SCROLL_END), SCROLL_ACCEL, SCROLL_DECEL)
	game_state.set_elimination_scroll(lerpf(_scroll_from, _scroll_to, eased))
	if _t >= T_SCROLL_END + 0.2 and player_controller != null and player_controller.lasso_hidden_mask != 3:
		player_controller.lasso_hidden_mask = 3


## 0 → 1 の進み方：はじめの accel の間になめらかに加速し、一定の速さで進んで、終わりの decel の間になめらかに止まる
## （速さはスムーズステップの山。いちばん速いときも平均の 1/(1 − (accel + decel)/2) 倍まで）。
static func _cruise_curve(u: float, accel: float, decel: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	var top := 1.0 / (1.0 - 0.5 * (accel + decel))
	if x <= accel:
		var a := x / maxf(accel, 1e-5)
		return top * accel * (a * a * a - 0.5 * a * a * a * a)
	if x <= 1.0 - decel:
		return top * (0.5 * accel + x - accel)
	var d := (1.0 - x) / maxf(decel, 1e-5)
	return 1.0 - top * decel * (d * d * d - 0.5 * d * d * d * d)


## 結果発表の最初のカメラ（コースを流し終えたあとの位置。流す前に、流し終えた値で一度だけ求める）。
func _finale_camera_pose() -> Dictionary:
	if camera_controller != null and camera_controller.has_method("result_ceremony_camera_pose"):
		var scroll := game_state.world_scroll_z
		game_state.world_scroll_z = _scroll_to
		var pose: Dictionary = camera_controller.call("result_ceremony_camera_pose", game_state, 0.0)
		game_state.world_scroll_z = scroll
		var local := _to_local_xform(pose.transform)
		return {"eye": local.origin, "forward": -local.basis.z, "fov": float(pose.fov)}
	var mid: Vector3 = (_lanes[1] + _lanes[2]) * 0.5
	return {"eye": mid + Vector3(0.0, 2.0, -7.4), "forward": Vector3(0.0, -0.17, 0.98).normalized(), "fov": 40.0}


## 結果発表が始まった（GameWorld）：カメラを返し、魂は結果発表の監督が受け取る。雲はそのまま空へ帰る。
func on_ceremony_started() -> void:
	if not _active or _handed_over:
		return
	_handed_over = true
	game_state.elimination_lasso_active = false
	if camera_controller != null and camera_controller.has_method("clear_director_pose"):
		camera_controller.call("clear_director_pose")


## 結果発表の監督（ResultCeremonyDirector._release_ghost）が、運ばれてきた魂をそのまま幽霊として受け取る。
func release_result_soul(player_index: int, new_parent: Node3D) -> Node3D:
	var soul := _souls.get(player_index) as Node3D
	if soul == null or not is_instance_valid(soul) or _released.get(player_index, false):
		return null
	_released[player_index] = true
	player_controller.set_ghost_rider_shader_parameter(soul, &"body_alpha", 0.5)
	player_controller.set_ghost_rider_shader_parameter(soul, &"flash", 0.0)
	soul.reparent(new_parent, true)
	soul.set_meta("result_release_scale", 1.0)
	return soul


func _finish() -> void:
	_active = false
	for player_index: int in _souls:
		# サメに乗ったまま引き取れなかった乗り手は、乗り手の監督のもの（ここでは消さない）
		if not _released.get(player_index, false) and not _riding_shark(player_index):
			var soul := _souls[player_index] as Node3D
			if soul != null and is_instance_valid(soul):
				soul.queue_free()
	_souls.clear()
	_ragdolls.clear()
	_free_rig()


func force_cleanup() -> void:
	if _active and not _handed_over and camera_controller != null and camera_controller.has_method("clear_director_pose"):
		camera_controller.call("clear_director_pose")
	_active = false
	_handed_over = false
	if game_state != null:
		game_state.elimination_lasso_active = false
	for player_index: int in _souls:
		var soul := _souls[player_index] as Node3D
		if soul != null and is_instance_valid(soul) and not _released.get(player_index, false) and not _riding_shark(player_index):
			soul.queue_free()
	_souls.clear()
	_released.clear()
	_ragdolls.clear()
	_shark_rider = 0
	_shark_take_at = INF
	_shark_taken_at = INF
	_free_rig()


func _free_rig() -> void:
	for node: Variant in [_rider, _rope, _rope_l]:
		if node != null and is_instance_valid(node):
			(node as Node).queue_free()
	_rider = null
	_rope = null
	_rope_l = null
	_catches.clear()
	_catch_of.clear()


# ------------------------------------------------------------------ cloud

func _update_cloud(dt: float) -> void:
	_cloud_prev = _cloud_pos
	_cloud_pos = _cloud_path(_t)
	var velocity := (_cloud_pos - _cloud_prev) / maxf(dt, 1e-4)
	var accel := (velocity - _cloud_vel) / maxf(dt, 1e-4)
	_cloud_vel = _cloud_vel.lerp(velocity, 1.0 - exp(-20.0 * dt))
	# 向き：飛んでくる間は進む向き、止まったら魂の方、運ぶ間とゴールでは前（＋Z）、去るときはまた進む向き。
	# 両手の縄なら、運ぶあいだ雲ごと回って 2 人をぶん回す（_whirl_spin。回し終わりでちょうど前を向く）
	var want_yaw := _base_yaw
	var flat := Vector3(_cloud_vel.x, 0.0, _cloud_vel.z)
	var leaving := _t >= T_EXIT + 0.15
	var rate := 5.0 if _t < T_YANK else 2.6
	if _t < T_CLOUD_ARRIVE - 0.55 and flat.length() > 1.5:
		want_yaw = _yaw_of(flat)
	elif _t < T_YANK:
		want_yaw = _yaw_of(_soul_mid() - _cloud_pos)
	elif leaving and flat.length() > 1.0:
		want_yaw = _yaw_of(flat)
		rate = 3.4
	else:
		want_yaw = 0.0
	_base_yaw = lerp_angle(_base_yaw, want_yaw, 1.0 - exp(-rate * dt))
	_cloud_yaw = _base_yaw + _whirl_spin(_t)
	# 傾き：横向きの加速で傾き、前向きの加速で前へのめる（ばねでゆれる）。旋回して去るときは大きく傾ける。
	# ぶん回しているあいだは、向きと一緒に回る加速でゆれすぎないように抑える
	var basis_yaw := Basis(Vector3.UP, _base_yaw)
	var local_accel := basis_yaw.inverse() * accel
	var bank_gain := 0.06 if leaving else 0.022
	var want_tilt := Vector2(clampf(local_accel.z * 0.018, -0.3, 0.3), clampf(-local_accel.x * bank_gain, -0.5, 0.5))
	want_tilt *= 1.0 - 0.75 * _whirl_weight(_t)
	if _t < T_CLOUD_START:
		want_tilt = Vector2.ZERO
	var stiffness := 38.0
	var damping := 9.0
	# 投げた反動で雲がうしろへのけぞり、締めて引いたときは前へつんのめる
	if _t >= T_RELEASE and not _cues.has("kick_release"):
		_cues["kick_release"] = _t
		_cloud_tilt_vel += Vector2(-1.6, 0.4 if not _two_ropes else 0.0)
	if _t >= T_CINCH and not _cues.has("kick_cinch"):
		_cues["kick_cinch"] = _t
		_cloud_tilt_vel += Vector2(1.3, 0.0)
	_cloud_tilt_vel += ((want_tilt - _cloud_tilt) * stiffness - _cloud_tilt_vel * damping) * dt
	_cloud_tilt += _cloud_tilt_vel * dt
	_place_rider(dt)
	# コースを流しているあいだは、景色が後ろへ流れる分だけ速く飛んでいる（雲のなびきとかけらに入れる）
	var flow := (game_state.world_scroll_z - _scroll_prev) / maxf(dt, 1e-4) if dt > 0.0 else 0.0
	_scroll_prev = game_state.world_scroll_z
	var air_vel := _cloud_vel + Vector3(0.0, 0.0, flow)
	var speed := air_vel.length()
	var local_vel := (Basis(Vector3.UP, _cloud_yaw).inverse() * air_vel) / RIG_SCALE
	_rider.trail = (-local_vel * 0.012).limit_length(0.14)
	_rider.set_flow(Vector3(0.0, 0.0, -flow))
	_rider.set_puffing(speed > 4.5 and _t > T_CLOUD_START)
	_rider.visible = _t >= T_CLOUD_START - 0.05


func _place_rider(_dt: float) -> void:
	var bob := Vector3(0.0, sin(_t * TAU * 0.55) * 0.06 + sin(_t * TAU * 1.3) * 0.015, 0.0)
	var tilt := Basis.from_euler(Vector3(_cloud_tilt.x + sin(_t * TAU * 0.4) * 0.02, 0.0, _cloud_tilt.y + sin(_t * TAU * 0.47 + 1.0) * 0.025))
	var basis := Basis(Vector3.UP, _cloud_yaw) * tilt
	# 飛び去って遠くへ行ったら、最後はすっと小さくなって消える
	var size := RIG_SCALE * maxf(1.0 - _ss(_t, T_END - 0.6, T_END - 0.05), 0.001)
	_rider.transform = Transform3D(basis.scaled_local(Vector3.ONE * size), _cloud_pos + bob)


func _cloud_path(t: float) -> Vector3:
	if t <= T_CLOUD_START:
		return _cloud_start
	if t < T_CLOUD_ARRIVE:
		# コースの先の空から降りてきて、少し回り込んで止まる（終わりで少し行き過ぎて戻る）
		var s := _seg(t, T_CLOUD_START, T_CLOUD_ARRIVE)
		var u := 1.0 - pow(1.0 - s, 2.4)
		return _bezier(_cloud_start, _cloud_p1, _cloud_p2, _cloud_hover, u)
	if t < T_YANK:
		var settle := t - T_CLOUD_ARRIVE
		var arrive_dir := (_cloud_hover - _cloud_p2).normalized()
		var overshoot := arrive_dir * 0.32 * exp(-4.5 * settle) * sin(settle * 8.0)
		# 投げた反動で少し下がり、締めたときに引かれて前へ出る
		var toward := _flat_toward_souls()
		var recoil := -toward * 0.22 * _bump(t, T_RELEASE - 0.05, T_RELEASE + 0.5)
		var tug := toward * 0.18 * _bump(t, T_CINCH, T_YANK + 0.2) - toward * 0.25 * _seg(t, T_CINCHED, T_YANK)
		return _cloud_hover + overshoot + recoil + tug
	# 真上へ吊り上げて壁より高く上がり、流れてくるコースの上をゴールの門の先まで飛んで、門を越えたら降りる
	var hover_end := _cloud_hover - _flat_toward_souls() * 0.25
	var lift_vel := Vector3(0.0, 1.6, 4.5)
	var cruise_vel := Vector3(0.0, -0.4, 2.2)
	if t < T_CRUISE:
		return _hermite(hover_end, Vector3(0.0, 3.0, 0.0), _lift_top, lift_vel, T_CRUISE - T_YANK, _seg(t, T_YANK, T_CRUISE))
	if t < T_DESCEND:
		return _hermite(_lift_top, lift_vel, _cruise_end, cruise_vel, T_DESCEND - T_CRUISE, _seg(t, T_CRUISE, T_DESCEND))
	if t < T_FLING_SET:
		return _hermite(_cruise_end, cruise_vel, _fling_pos, Vector3.ZERO, T_FLING_SET - T_DESCEND, _seg(t, T_DESCEND, T_FLING_SET))
	if t < T_EXIT:
		return _fling_rest(t)
	# 小さな輪を回しながら、下りながら前へ進み、スタンドの手前で旋回して飛び去る（_plan_exit）
	return _track(t, _exit_keys)


func _flat_toward_souls() -> Vector3:
	var toward := _soul_mid() - _cloud_hover
	toward.y = 0.0
	return toward.normalized() if toward.length_squared() > 1e-4 else Vector3.RIGHT


# ------------------------------------------------------------------ Hatena

## ハテナの空間での姿勢（LassoCloudRider.apply_pose）。両手に縄を持つときは、左手が右手の鏡うつしで同時に回して投げる。
func _hatena_pose(t: float) -> Dictionary:
	var pose := {}
	var two := _two_ropes
	var bob := sin(t * TAU * 1.1) * 0.018
	var pitch := 0.0
	var yaw := 0.0
	var roll := 0.0
	var squash := 1.0
	var r_hand := Vector3(-0.66, 0.68, 0.2)
	var l_hand := Vector3(0.62, 0.66, 0.26) if not two else Vector3(0.66, 0.68, 0.2)
	var r_pole := Vector3(-0.7, -0.6, -0.4)
	var l_pole := Vector3(0.7, -0.6, -0.4)
	var r_dir := Vector3.ZERO
	var l_dir := Vector3.ZERO
	var hat_lift := 0.0
	var offset := Vector3.ZERO
	var catch_r := _hand_catch("R")
	var catch_l := _hand_catch("L")
	var shoulder := Vector3(-0.52, 0.82, 0.0)
	var l_shoulder := _mirror(shoulder)
	var target_dir := (_to_hatena(_catch_target(catch_r) + Vector3.UP * 0.6) - shoulder).normalized()
	var l_target_dir := (_to_hatena(_catch_target(catch_l) + Vector3.UP * 0.6) - l_shoulder).normalized()

	if t < T_CLOUD_ARRIVE:
		# 飛んでくる間：前へのめって、帽子を少し浮かせる
		var speed_lean := clampf(_cloud_vel.length() / 18.0, 0.0, 1.0)
		pitch = deg_to_rad(10.0) * speed_lean
		hat_lift = 0.035 * speed_lean * (0.5 + 0.5 * sin(t * 31.0))
		if not two:
			l_hand = Vector3(0.55, 0.78, 0.3)
	if t >= T_CLOUD_ARRIVE - 0.2 and t < T_WINDUP + 0.1:
		# 止まって魂を見下ろす（腕の輪を少しゆらす）
		pitch = lerpf(pitch, deg_to_rad(9.0), _ss(t, T_CLOUD_ARRIVE - 0.2, T_CLOUD_ARRIVE + 0.2))

	if t >= T_WINDUP and t < T_RELEASE + 0.7:
		var r := T_RELEASE
		var theta := _theta0 + _twirl_integral(t)
		var lift := _ss(t, T_WINDUP, T_TWIRL)
		# 回す：手首で小さな円を描き、1 周ごとに体が弾む。最後の 1 周は腕ごと大きく回す
		var big := _ss(t, r - 0.55, r - 0.25)
		var hand_radius := lerpf(TWIRL_HAND_RADIUS, 0.085, big)
		var circling := _twirl_hand("R", theta, hand_radius)
		r_hand = r_hand.lerp(circling, lift)
		r_pole = Vector3(-1.0, -0.2, 0.3)
		r_dir = Vector3(-0.15, 1.0, 0.1) if not two else Vector3(-0.35, 1.0, 0.1)
		var sway := lift * (1.0 - _ss(t, r - 0.55, r - 0.3))
		pitch = lerpf(pitch, deg_to_rad(7.0), lift) + cos(theta) * deg_to_rad(4.0) * sway
		roll = 0.0 if two else sin(theta) * deg_to_rad(5.0) * sway
		bob += absf(sin(theta)) * 0.02 * sway - 0.01 * sway
		squash = 1.0 + 0.03 * sin(theta * 2.0 + 0.6) * sway
		hat_lift = 0.012 * absf(sin(theta)) * sway
		if two:
			# 左手も左へ広げ、右手と同じ向き・同じ角度で回す（2 つの輪がぶつからない）
			l_hand = l_hand.lerp(_twirl_hand("L", theta, hand_radius), lift)
			l_pole = _mirror(r_pole)
			l_dir = _mirror(r_dir)
		else:
			l_hand = Vector3(0.6, 0.72, 0.28)
			l_pole = Vector3(0.8, -0.5, -0.3)
		# 投げ：溜め（体を沈め、手を肩のうしろへ）→ 前へ伸び上がって腕を振り抜く → 前のめりで止まる。
		# 縄 1 本なら体を右うしろへひねって投げる。両手なら、ひねらずに両腕を同時に振り抜く
		var reach := shoulder + target_dir * 0.31
		var cocked := shoulder + Vector3(-0.09, 0.2, -0.17)
		var throw_hand: Vector3 = _throw_track(t, cocked, reach)
		var into_throw := _ss(t, r - 0.4, r - 0.26)
		var cock_dir := Vector3(0.0, 0.5, -1.0).normalized()
		var cock_weight := into_throw * (1.0 - _ss(t, r - 0.12, r))
		var aim := _ss(t, r - 0.1, r + 0.02)
		r_hand = r_hand.lerp(throw_hand, into_throw)
		r_dir = r_dir.lerp(cock_dir, cock_weight).lerp(target_dir, aim)
		r_pole = r_pole.lerp(Vector3(-0.9, -0.5, 0.1), _ss(t, r - 0.12, r + 0.05))
		pitch += deg_to_rad(float(_track(t, [[r - 0.55, 0.0], [r - 0.26, -17.0], [r - 0.12, -19.0], [r - 0.02, 30.0], [r + 0.14, 25.0], [r + 0.45, 12.0], [r + 0.7, 9.0]])))
		if not two:
			yaw = float(_track(t, [[r - 0.55, 0.0], [r - 0.26, 0.4], [r - 0.12, 0.46], [r - 0.01, -0.3], [r + 0.25, -0.12], [r + 0.7, 0.0]]))
			roll += float(_track(t, [[r - 0.55, 0.0], [r - 0.26, -0.13], [r, 0.1], [r + 0.4, 0.02], [r + 0.7, 0.0]]))
		var lunge: Vector3 = _track(t, [[r - 0.55, Vector3.ZERO], [r - 0.26, Vector3(0.0, -0.06, -0.08)], [r - 0.12, Vector3(0.0, -0.07, -0.09)],
			[r - 0.01, Vector3(0.0, 0.07, 0.12)], [r + 0.2, Vector3(0.0, 0.0, 0.09)], [r + 0.7, Vector3(0.0, 0.0, 0.03)]])
		offset += lunge
		squash *= float(_track(t, [[r - 0.55, 1.0], [r - 0.26, 0.9], [r - 0.12, 0.89], [r - 0.03, 1.13], [r + 0.1, 0.95], [r + 0.3, 1.03], [r + 0.55, 1.0]]))
		if two:
			var l_throw: Vector3 = _throw_track(t, _mirror(cocked), l_shoulder + l_target_dir * 0.31)
			l_hand = l_hand.lerp(l_throw, into_throw)
			l_dir = l_dir.lerp(cock_dir, cock_weight).lerp(l_target_dir, aim)
			l_pole = l_pole.lerp(Vector3(0.9, -0.5, 0.1), _ss(t, r - 0.12, r + 0.05))
		else:
			# 左手は振り子の重り：溜めで前へ、投げで後ろへ振ってつり合いを取る
			l_hand = l_hand.lerp(Vector3(0.62, 0.76, 0.36), _bump(t, r - 0.4, r - 0.05) * 0.8)
			l_hand = l_hand.lerp(Vector3(0.68, 0.8, -0.08), _bump(t, r - 0.08, r + 0.45))
		hat_lift = maxf(hat_lift, 0.07 * _bump(t, r - 0.04, r + 0.3))

	if t >= T_RELEASE + 0.05 and t < T_CINCH:
		# 飛ぶ輪を目で追い、腕を伸ばしたまま。縄 1 本なら左手で縄を送り出す（体の横で小さくたぐる）
		var follow := _ss(t, T_RELEASE + 0.05, T_RELEASE + 0.5)
		var loop_dir := (_to_hatena(catch_r.rope.get_loop_center()) - shoulder).normalized()
		r_hand = r_hand.lerp(shoulder + loop_dir * 0.3, follow)
		r_dir = r_dir.lerp(loop_dir, follow)
		if two:
			var l_loop_dir := (_to_hatena(catch_l.rope.get_loop_center()) - l_shoulder).normalized()
			l_hand = l_hand.lerp(l_shoulder + l_loop_dir * 0.3, follow)
			l_dir = l_dir.lerp(l_loop_dir, follow)
		else:
			var feed := sin(_seg(t, T_RELEASE, T_CINCH) * PI * 4.0)
			l_hand = l_hand.lerp(Vector3(0.58, 0.72, 0.3).lerp(Vector3(0.5, 0.76, 0.42), 0.5 + 0.5 * feed), follow)
		pitch = lerpf(pitch, deg_to_rad(15.0), follow)

	if t >= T_CINCH and t < T_WIND + 0.1:
		# 締める：強く引き、体を後ろへ反らす。吊り上げて運ぶ間は踏んばる。縄 1 本なら左手も同じ縄に掛け、
		# 両手なら左右それぞれの縄を引く
		var rope_dir := _rope_dir(catch_r)
		var yank := float(_track(t, [[T_CINCH - 0.02, 0.0], [T_CINCH + 0.1, 1.0], [T_CINCH + 0.32, 0.55], [T_YANK, 0.6], [T_YANK + 0.18, 1.0], [T_YANK + 0.6, 0.55]]))
		r_hand = Vector3(-0.5, 0.7, 0.12).lerp(Vector3(-0.56, 0.7, -0.12), yank)
		r_pole = Vector3(-0.7, -0.6, -0.3)
		r_dir = rope_dir
		if two:
			l_hand = _mirror(r_hand)
			l_pole = _mirror(r_pole)
			l_dir = _rope_dir(catch_l)
		else:
			l_hand = r_hand + rope_dir * 0.28 + Vector3(0.18, 0.04, 0.05)
			l_pole = Vector3(0.6, -0.7, -0.2)
			l_dir = rope_dir
		pitch = deg_to_rad(-6.0) - deg_to_rad(18.0) * yank
		squash = float(_track(t, [[T_CINCH - 0.02, 1.0], [T_CINCH + 0.06, 0.9], [T_CINCH + 0.2, 1.07], [T_CINCH + 0.4, 1.0], [T_YANK, 1.0], [T_YANK + 0.08, 0.92], [T_YANK + 0.3, 1.05], [T_YANK + 0.55, 1.0]]))
		hat_lift = 0.06 * _bump(t, T_CINCH + 0.02, T_CINCH + 0.3) + 0.05 * _bump(t, T_YANK + 0.05, T_YANK + 0.35)
		if two:
			# ぶん回す：両腕を左右へ広げて 2 本の縄を張り、体を少し反らして踏んばる（雲ごと回る）
			var spread := _whirl_weight(t)
			if spread > 0.0 and WHIRL_STYLE == WhirlStyle.WHIRL_VERTICAL:
				# 縦に振り回す：両腕を風車のように同じ角度で回し、縄の先の 2 人を上を越えて前へ振り下ろす。
				# 振り下ろすたびに体が前へのめり、振り上げで反る
				var angle := _whirl_phase(t)
				var swing_dir := _windmill_dir(angle)
				r_hand = r_hand.lerp(WINDMILL_PIVOT + swing_dir * WINDMILL_HAND_RADIUS, spread)
				l_hand = l_hand.lerp(_mirror(WINDMILL_PIVOT) + swing_dir * WINDMILL_HAND_RADIUS, spread)
				r_pole = r_pole.lerp(Vector3(-1.0, -0.2, -0.1), spread)
				l_pole = l_pole.lerp(Vector3(1.0, -0.2, -0.1), spread)
				r_dir = r_dir.lerp(swing_dir, spread)
				l_dir = l_dir.lerp(swing_dir, spread)
				pitch = lerpf(pitch, deg_to_rad(-4.0 - 10.0 * sin(angle)), spread)
				squash = lerpf(squash, 1.0 + 0.05 * cos(angle), spread)
				hat_lift = maxf(hat_lift, 0.04 * spread * maxf(0.0, -sin(angle)))
			elif spread > 0.0:
				r_hand = r_hand.lerp(Vector3(-0.9, 0.86, 0.02), spread)
				l_hand = l_hand.lerp(Vector3(0.9, 0.86, 0.02), spread)
				r_pole = r_pole.lerp(Vector3(-0.3, -1.0, -0.2), spread)
				l_pole = l_pole.lerp(Vector3(0.3, -1.0, -0.2), spread)
				pitch = lerpf(pitch, deg_to_rad(-12.0), spread)
				hat_lift = maxf(hat_lift, 0.03 * spread * (0.5 + 0.5 * sin(t * 29.0)))
		# 運ぶ間の踏んばり（小さく震える）
		if t > T_YANK + 0.6:
			pitch += sin(t * 23.0) * deg_to_rad(1.2)
			bob += sin(t * 17.0) * 0.004

	if t >= T_WIND - 0.1 and t < T_EXIT + 0.1:
		# 投げつける：縄を胸まで引き上げて 2 人をうしろへ振り上げ（体をのけぞらせて溜め）、前へ振り抜いて放す
		var r := T_FLING
		var rope_dir := _rope_dir(catch_r)
		var wind := _ss(t, T_WIND - 0.1, T_WIND + 0.25)
		var whip := _ss(t, r - 0.17, r + 0.02)
		var swing_hand := Vector3(-0.56, 0.7, -0.12).lerp(Vector3(-0.42, 0.98, -0.2), wind).lerp(Vector3(-0.4, 0.68, 0.34), whip)
		# 放したあとは、たぐり寄せる（両手を交互に）
		var reel := _ss(t, r + 0.25, r + 0.35) * (1.0 - _ss(t, T_EXIT - 0.05, T_EXIT + 0.1))
		var cycle := sin((t - r) * TAU * 3.2)
		r_hand = swing_hand + Vector3(0.0, 0.04 * cycle, -0.16 * cycle) * reel
		r_pole = Vector3(-0.8, -0.5, -0.2)
		r_dir = rope_dir
		if two:
			l_hand = _mirror(swing_hand) + Vector3(0.0, -0.04 * cycle, 0.16 * cycle) * reel
			l_pole = Vector3(0.8, -0.5, -0.2)
			l_dir = _rope_dir(catch_l)
		else:
			l_hand = r_hand + rope_dir * 0.24 + Vector3(0.2, 0.02, 0.05) + Vector3(0.0, -0.04 * cycle, 0.16 * cycle) * reel
			l_pole = Vector3(0.7, -0.6, -0.2)
			l_dir = rope_dir
		pitch = deg_to_rad(float(_track(t, [[T_WIND - 0.1, -6.0], [T_WIND + 0.25, -26.0], [r - 0.17, -29.0], [r + 0.02, 30.0], [r + 0.2, 22.0], [r + 0.5, 6.0]])))
		yaw = 0.0 if two else float(_track(t, [[T_WIND - 0.1, 0.0], [T_WIND + 0.25, 0.26], [r - 0.17, 0.3], [r + 0.02, -0.3], [r + 0.4, -0.05], [r + 0.6, 0.0]]))
		squash = float(_track(t, [[T_WIND - 0.1, 1.0], [T_WIND + 0.25, 0.92], [r - 0.15, 0.9], [r + 0.01, 1.13], [r + 0.15, 0.96], [r + 0.4, 1.0]]))
		offset += _track(t, [[T_WIND - 0.1, Vector3.ZERO], [T_WIND + 0.25, Vector3(0.0, -0.05, -0.08)], [r - 0.15, Vector3(0.0, -0.06, -0.1)],
			[r + 0.02, Vector3(0.0, 0.06, 0.13)], [r + 0.4, Vector3(0.0, 0.0, 0.04)], [r + 0.6, Vector3.ZERO]])
		hat_lift = 0.08 * _bump(t, r - 0.03, r + 0.35)

	if t >= T_EXIT:
		# 小さな輪を頭の上で回して、空へ帰る（縄 1 本なら左手を振る。両手ならどちらの手でも回す）
		var twirl := _exit_twirl(t)
		var w := _ss(t, T_EXIT, T_EXIT + 0.35)
		r_hand = r_hand.lerp(twirl.hand, w)
		r_dir = r_dir.lerp(Vector3.UP, w)
		r_pole = r_pole.lerp(Vector3(-1.0, -0.2, 0.3), w)
		if two:
			l_hand = l_hand.lerp(twirl.hand_l, w)
			l_dir = l_dir.lerp(Vector3.UP, w)
			l_pole = l_pole.lerp(Vector3(1.0, -0.2, 0.3), w)
		else:
			var wave := sin((t - T_EXIT) * TAU * 2.4)
			l_hand = l_hand.lerp(Vector3(0.66, 1.0 + 0.04 * wave, 0.16 + 0.08 * wave), w)
			l_pole = l_pole.lerp(Vector3(1.0, -0.3, -0.2), w)
		pitch = lerpf(pitch, deg_to_rad(-4.0), w)
		bob += 0.03 * absf(sin((t - T_EXIT) * TAU * 1.6)) * w
		squash = lerpf(squash, 1.0 + 0.03 * sin((t - T_EXIT) * TAU * 3.2), w)

	pose["body_offset"] = offset + Vector3(0.0, bob, 0.0)
	pose["body_rot"] = Quaternion.from_euler(Vector3(pitch, yaw, roll))
	pose["squash"] = squash
	pose["r_hand"] = r_hand
	pose["l_hand"] = l_hand
	pose["r_pole"] = r_pole
	pose["l_pole"] = l_pole
	pose["r_hand_dir"] = r_dir
	pose["l_hand_dir"] = l_dir
	pose["hat_lift"] = hat_lift
	return pose


## 投げる手の道すじ（溜め → 振り抜き → 伸ばしたまま）。
func _throw_track(t: float, cocked: Vector3, reach: Vector3) -> Vector3:
	var r := T_RELEASE
	return _track(t, [[r - 0.26, cocked], [r - 0.12, cocked + Vector3(0.0, 0.03, 0.03)],
		[r - 0.02, reach + Vector3(0.0, 0.07, 0.0)], [r + 0.1, reach - Vector3(0.0, 0.1, 0.0)],
		[r + 0.32, reach + Vector3(0.0, 0.02, 0.0)], [r + 0.7, reach]])


## 手から縄の幹の 3 分の 1 の所への向き（ハテナの空間）。
func _rope_dir(c: LassoCatch) -> Vector3:
	if c == null or c.rope == null:
		return Vector3.DOWN
	return (_to_hatena(c.rope.get_stem_point(LassoRope.STEM_COUNT / 3)) - _rider.grip_local(c.hand)).normalized()


func _hand_catch(hand: String) -> LassoCatch:
	for c: LassoCatch in _catches:
		if c.hand == hand:
			return c
	return null


func _catch_target(c: LassoCatch) -> Vector3:
	return c.target if c != null else _soul_mid()


## 回す角度（投げる瞬間に 0 = ハテナの前）。回す速さは TWIRL_REV_START から TWIRL_REV_END へなめらかに上がる。
func _twirl_integral(t: float) -> float:
	var t0 := T_WINDUP
	var t1 := T_RELEASE - 0.35
	var span := t1 - t0
	var x := clampf((t - t0) / span, 0.0, 1.0)
	var smooth_area := x * x * x - 0.5 * x * x * x * x
	var a := TWIRL_REV_START
	var b := TWIRL_REV_END
	return TAU * (a * maxf(0.0, t - t0) + (b - a) * (span * smooth_area + maxf(0.0, t - t1)))


## 空へ帰るときに回す小さな輪の角度と、手の回る所（ハテナの空間。hand は右手、hand_l は左手）。
func _exit_twirl(t: float) -> Dictionary:
	var theta := (t - T_EXIT) * TAU * 1.7
	var circle := Vector3(sin(theta + 1.9), 0.0, cos(theta + 1.9)) * TWIRL_HAND_RADIUS
	var pivot := TWIN_PIVOT if _two_ropes else TWIRL_PIVOT
	var lift := Vector3(0.0, 0.04, 0.0)
	return {"theta": theta, "hand": pivot + lift + circle, "hand_l": _mirror(pivot) + lift + circle}


## 縄を回すときに手が回る所（ハテナの空間）。両手に縄を持つときは、両手を左右へ広げ、2 本とも同じ向き・同じ角度で回す。
func _twirl_hand(hand: String, theta: float, radius: float) -> Vector3:
	var circle := Vector3(sin(theta + 1.9), 0.0, cos(theta + 1.9)) * radius
	if not _two_ropes:
		return TWIRL_PIVOT + circle
	return (TWIN_PIVOT if hand == "R" else _mirror(TWIN_PIVOT)) + circle


## 頭上で回る輪（ハテナの空間）：結び目は手の上（knot_out だけ横へずらす）、輪の真ん中は結び目から u の向き。外側が
## わずかに垂れる。両手の縄は 2 本とも同じ u で回し、結び目を外へずらすので、2 つの輪はいつも同じだけ離れて重ならない。
func _twirl_ring(theta: float, radius: float, spoke: float, hand_local: Vector3, knot_out := -0.1) -> Dictionary:
	var u := Vector3(sin(theta), 0.0, cos(theta))
	var tilt := deg_to_rad(TWIRL_DROOP_DEG)
	var u_t := (u * cos(tilt) - Vector3.UP * sin(tilt)).normalized()
	var w := Vector3.UP.cross(u).normalized()
	# 結び目は手の真上から少し外（帽子のつばに縄が掛からない）
	var honda := hand_local + Vector3(knot_out, spoke, 0.0) + u * 0.13
	return {"honda": honda, "center": honda + u_t * radius, "u": u_t, "w": w}


## 結び目を手から横へずらす量（ハテナの空間の x）。両手の縄は外へ大きく、縄 1 本なら少しだけ。
func _knot_out(hand: String, scale_out: float) -> float:
	if not _two_ropes:
		return -0.1
	return (-1.0 if hand == "R" else 1.0) * scale_out


# ------------------------------------------------------------------ souls

func _soul_mid() -> Vector3:
	if _soul_pos.is_empty():
		return (_soul_rise.get(1, Vector3.ZERO) + _soul_rise.get(2, Vector3.ZERO)) * 0.5
	var sum := Vector3.ZERO
	var count := 0
	for player_index: int in _soul_pos:
		sum += _soul_pos[player_index]
		count += 1
	return sum / float(maxi(count, 1))


func _side(player_index: int) -> float:
	return 1.0 if player_index == 1 else -1.0


## 捕まるまでの魂の根：死んだ所から真上へ抜け出して浮かび、その場で小さく上下するだけ（横へは動かない）。
func _hover_point(player_index: int, t: float) -> Vector3:
	var start: Vector3 = _soul_start[player_index]
	var risen: Vector3 = _soul_rise[player_index]
	if player_index == _shark_rider:
		# サメに乗っていた乗り手は、サメの上（引き取ったらその場）
		return risen
	var rise := 1.0 - pow(1.0 - _seg(t, 0.0, T_RISE), 2.2)
	var phase := 0.0 if player_index == 1 else 1.7
	var bob := sin(t * TAU * 0.8 + phase) * 0.06 * _ss(t, 0.5, T_RISE + 0.4)
	return start.lerp(risen, rise) + Vector3.UP * bob


func _update_souls(dt: float) -> void:
	if _t < T_FLING:
		if _t >= T_CINCH:
			for c: LassoCatch in _catches:
				_step_catch(c, dt)
			_keep_bundles_apart()
			for c: LassoCatch in _catches:
				_orient_catch(c, dt)
		# 締めるまでは浮かんだその場。締めると輪に引き寄せられて束の所へ
		var pull := _ss(_t, T_CINCH + 0.02, T_CINCHED)
		for player_index: int in _souls:
			var pos := _hover_point(player_index, _t)
			if pull > 0.0:
				var c: LassoCatch = _catch_of[player_index]
				pos = pos.lerp(c.bundle * Vector3(float(c.slots[player_index]), 0.0, 0.0), pull)
			_soul_vel[player_index] = (pos - _soul_pos[player_index]) / maxf(dt, 1e-4)
			_soul_pos[player_index] = pos
	else:
		if _ragdolls.is_empty():
			_fling_souls()
		_update_ragdolls(dt)
	for player_index: int in _souls:
		_pose_soul(player_index)


## 投げつける瞬間：2 人を、今の（縛られた）姿勢のままラグドールにして、それぞれのレーンの少し手前へ放る。
## 前転するように回し、P1 と P2 で回り方と飛ぶ時間を少し変える。
func _fling_souls() -> void:
	var to_space := global_transform.affine_inverse()
	# 両手の縄で、P1 が −X の側にぶら下がっていたら（ハテナの右手で捕まえた P1 は、前を向くと左へ来る）、2 人は
	# 交差して自分のレーンへ飛ぶ。ぶつからないよう、P1 は高い弧・P2 は低い弧で投げる
	var crossing := _soul_pos.has(1) and _soul_pos.has(2) and (_soul_pos[1] as Vector3).x < (_soul_pos[2] as Vector3).x
	for player_index: int in _souls:
		var soul := _souls[player_index] as Node3D
		var parts: Dictionary = soul.get_meta("ghost_mount_parts", {}) if soul != null else {}
		if parts.is_empty():
			continue
		var ragdoll := LassoSoulRagdoll.new()
		ragdoll.floor_y = StageConstants.FLOOR_TOP_Y
		ragdoll.start(parts, to_space)
		var lane: Vector3 = _lanes[player_index]
		var side := _side(player_index)
		# 転がって外へ流れる分だけ、内側をねらう
		var land := Vector3(lane.x * 0.75, StageConstants.FLOOR_TOP_Y + 0.17, lane.z - FLING_SHORT)
		var flight := FLING_FLIGHT + (0.0 if player_index == 1 else 0.06)
		if crossing:
			flight = FLING_FLIGHT + (0.2 if player_index == 1 else -0.1)
		# 前まわり（横へ転がっていかないよう、ひねりは少しだけ）
		var spin_axis := Vector3(1.0, 0.12 * side, -0.05 * side)
		ragdoll.launch(land, flight, spin_axis, 8.0 if player_index == 1 else 7.0, 1.0 / 60.0)
		_ragdolls[player_index] = ragdoll


## ラグドールを進め、止まったらその場で起き上がらせ、立ったら自分のレーンへ歩かせる。2 人とも着いたら結果発表を始めてよい。
func _update_ragdolls(dt: float) -> void:
	var all_arrived := not _ragdolls.is_empty()
	for player_index: int in _ragdolls:
		var ragdoll: LassoSoulRagdoll = _ragdolls[player_index]
		if not _get_up_at.has(player_index):
			var was_landed := ragdoll.landed
			ragdoll.step(dt)
			if ragdoll.landed and not was_landed:
				# 叩きつけられた音
				AudioManager.play_sfx(&"wall_land", -6.0, 1.15 if player_index == 1 else 1.0)
				AudioManager.play_sfx(&"bonk", -4.0, 0.9)
			if ragdoll.is_resting() or _t >= T_GET_UP_LATEST:
				_get_up_at[player_index] = _t
				var soul := _souls[player_index] as Node3D
				ragdoll.begin_get_up(soul, soul.get_meta("ghost_mount_parts", {}))
		elif not _stood.get(player_index, false) and _t - float(_get_up_at[player_index]) >= GET_UP_TIME:
			_stood[player_index] = true
			var soul := _souls[player_index] as Node3D
			var start := Vector3(soul.position.x, 0.0, soul.position.z)
			var lane: Vector3 = _lanes[player_index]
			_walk[player_index] = {"from": start, "at": _t, "time": start.distance_to(lane) / WALK_SPEED + 0.3}
		if _walk.has(player_index):
			var walk: Dictionary = _walk[player_index]
			if _t - float(walk.at) >= float(walk.time):
				_arrived[player_index] = true
		_soul_pos[player_index] = (_souls[player_index] as Node3D).position
		if not _arrived.get(player_index, false):
			all_arrived = false
	if all_arrived and not is_finite(_ceremony_at):
		_ceremony_at = _t + 0.1


## 立ち上がったら向く向き：レーンが少し離れていればそちらへ（歩き出す向き）、近ければスコアタワーの方（＋Z）。
func _face_yaw(player_index: int, from: Vector3) -> float:
	var lane: Vector3 = _lanes[player_index]
	var to := lane - from
	to.y = 0.0
	return atan2(to.x, to.z) if to.length() > 0.35 else 0.0


## 投げつけたあとの魂：飛んで転がる間はラグドールの形のまま、止まったらその場で起き上がり、自分のレーンへ歩いて
## スコアタワーの方を向く（結果発表の立ち姿）。
func _pose_ragdoll_soul(player_index: int, soul: Node3D, parts: Dictionary) -> void:
	var ragdoll: LassoSoulRagdoll = _ragdolls[player_index]
	var lane: Vector3 = _lanes[player_index]
	if _walk.has(player_index):
		# 歩く：レーンへ向かって歩き、着く前にスコアタワーの方へ向き直る
		var walk: Dictionary = _walk[player_index]
		var from: Vector3 = walk.from
		var span := float(walk.time)
		var w := clampf((_t - float(walk.at)) / span, 0.0, 1.0)
		var e := w * w * (3.0 - 2.0 * w)
		var position := from.lerp(lane, e)
		var travel_yaw := _face_yaw(player_index, from)
		var yaw := lerp_angle(travel_yaw, 0.0, smoothstep(0.55, 1.0, w))
		soul.transform = Transform3D(Basis(Vector3.UP, yaw), position)
		var moving := w < 0.92 and from.distance_to(lane) > 0.35
		player_controller.apply_ghost_rider_result_pose(soul, player_index, moving, _t - float(walk.at))
	elif _get_up_at.has(player_index):
		player_controller.apply_ghost_rider_result_pose(soul, player_index, false, _t)
		var standing := {}
		for key: Variant in parts:
			if parts[key] is Node3D:
				standing[key] = (parts[key] as Node3D).quaternion
		var progress := (_t - float(_get_up_at[player_index])) / GET_UP_TIME
		var lying_at := Vector3(soul.position.x, 0.0, soul.position.z)
		ragdoll.apply_get_up(soul, parts, standing, progress, _face_yaw(player_index, lying_at))
	else:
		ragdoll.apply_pose(soul, parts)
	# 床に叩きつけられた瞬間に光る
	var impact := _bump(ragdoll.age, ragdoll.land_time - 0.02, ragdoll.land_time + 0.25) if ragdoll.landed else 0.0
	player_controller.set_ghost_rider_shader_parameter(soul, &"body_alpha", 0.5)
	player_controller.set_ghost_rider_shader_parameter(soul, &"flash", clampf(0.2 * impact, 0.0, 1.0))


## 締めたあと：束は結び目から縄で吊られた振り子。結び目を進める（縄の長さは引けば縮み、雲は前へ飛ぶ）。
func _step_catch(c: LassoCatch, dt: float) -> void:
	var hand := _rider.grip_point(c.hand)
	var hand_vel := (hand - c.hand_prev) / maxf(dt, 1e-4)
	if _t < T_YANK:
		# 締めた直後：その場で浮いたまま、締まった反動で小さくはねる
		var origin := c.target + Vector3.UP * 0.05 * _bump(_t, T_CINCHED - 0.08, T_YANK)
		c.bundle = Transform3D(Basis(Vector3.UP, c.yaw0), origin)
		c.honda_pos = c.bundle * _honda_local(c)
		c.honda_vel = Vector3.ZERO
		return
	if not c.pendulum_started:
		c.pendulum_started = true
		c.rope_len = hand.distance_to(c.honda_pos)
		# 引いた勢い：結び目が手の方へはね上がる
		c.honda_vel = (hand - c.honda_pos).normalized() * 3.2 + Vector3.UP * 1.5
	var target_len := L_HAUL
	if _t >= T_DESCEND - 0.2:
		target_len = lerpf(L_HAUL, L_FLING, _ss(_t, T_DESCEND - 0.2, T_FLING_SET))
	if _t < T_YANK + 0.5:
		target_len = lerpf(c.rope_len, L_HAUL, _ss(_t, T_YANK, T_YANK + 0.5))
	c.rope_len = target_len
	var steps := 4
	var h := dt / float(steps)
	var floor_honda := StageConstants.FLOOR_TOP_Y + 1.2 + BAND_Y + 0.05
	var support := c.target.y + BAND_Y
	# ゴールの手前へ降りる間に揺れを収める（空気の抵抗を強める）
	var calm := _ss(_t, T_DESCEND - 0.4, T_FLING_SET) if _goal_ready else 0.0
	for _step in range(steps):
		c.honda_vel += Vector3(0.0, -9.8, 0.0) * h
		c.honda_vel *= exp(-(0.9 + 5.5 * calm) * h)
		c.honda_pos += c.honda_vel * h
		var d := c.honda_pos - hand
		var dist := d.length()
		if dist > c.rope_len and dist > 1e-5:
			var n := d / dist
			c.honda_pos = hand + n * c.rope_len
			var radial := (c.honda_vel - hand_vel).dot(n)
			if radial > 0.0:
				c.honda_vel -= n * radial
		if _t < T_YANK + 0.3 and c.honda_pos.y < support:
			c.honda_pos.y = support
			c.honda_vel.y = maxf(c.honda_vel.y, 0.0)
		# 床の上なら床より下へ行かない（海の上の魂は水面から吊り上げる）
		if c.honda_pos.y < floor_honda and _over_floor(c.honda_pos):
			c.honda_pos.y = floor_honda
			c.honda_vel.y = maxf(c.honda_vel.y, 0.0)
		# 雲が急に下がっても、束が雲より上へ振り上がらない（縄の長さの 0.45 は必ず手の下）
		var ceiling := hand.y - c.rope_len * 0.45
		if c.honda_pos.y > ceiling:
			c.honda_pos.y = ceiling
			c.honda_vel.y = minf(c.honda_vel.y, hand_vel.y)
	# 両手の縄なら、雲ごと回って 2 人をぶん回す。円すい振り子：速く回るほど縄が水平に近づき、2 人はそれぞれの手の
	# 外へ（反対の側に）振り出される。回すのをやめると、自分の手の下へぶら下がる
	var whirl := _whirl_weight(_t)
	if whirl <= 0.0:
		c.whirl_prev = Vector3.INF
		return
	var target := hand
	if WHIRL_STYLE == WhirlStyle.WHIRL_VERTICAL:
		# 縦：手のまわりの縦の円（真下 → うしろ → 真上 → 前へ振り下ろす）。2 人とも同じ角度
		target = hand + Basis(Vector3.UP, _cloud_yaw) * _windmill_dir(_whirl_phase(_t)) * c.rope_len
	else:
		var spin := _whirl_omega(_t) * _whirl_scale
		var out_dir := _rider.transform.basis.orthonormalized() * Vector3(-1.0 if c.hand == "R" else 1.0, 0.0, 0.0)
		out_dir.y = 0.0
		out_dir = out_dir.normalized() if out_dir.length_squared() > 1e-6 else Vector3.RIGHT
		var cos_a := clampf(9.8 / maxf(spin * spin * c.rope_len, 1e-3), 0.0, 1.0)
		var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
		target = hand + out_dir * (c.rope_len * sin_a) - Vector3.UP * (c.rope_len * cos_a)
	var target_vel := (target - c.whirl_prev) / maxf(dt, 1e-4) if c.whirl_prev.is_finite() else Vector3.ZERO
	c.whirl_prev = target
	c.honda_pos = c.honda_pos.lerp(target, whirl)
	c.honda_vel = c.honda_vel.lerp(target_vel, whirl)


## 両手の縄で吊った 2 人が、ぶつかって重ならないように（結び目どうしを離す）。振り抜くあいだは手の動きに任せる。
func _keep_bundles_apart() -> void:
	if _catches.size() < 2 or _t < T_YANK or _t >= T_WIND - 0.15 or _whirl_weight(_t) > 0.3:
		return
	var a := _catches[0]
	var b := _catches[1]
	var d := a.honda_pos - b.honda_pos
	d.y = 0.0
	var dist := d.length()
	if dist >= SOLO_BUNDLE_GAP:
		return
	var n := d / dist if dist > 1e-4 else _rider.transform.basis.x.normalized()
	var push := (SOLO_BUNDLE_GAP - dist) * 0.5
	a.honda_pos += n * push
	b.honda_pos -= n * push
	var closing := (a.honda_vel - b.honda_vel).dot(n)
	if closing < 0.0:
		a.honda_vel -= n * (closing * 0.5)
		b.honda_vel += n * (closing * 0.5)


## 束の向きと置き場所：振り抜くときは縄を手のまわりの円の弧で振る。上の向きは縄の向きへ遅れて傾き、前の向きは
## 始まりの向き（2 人の並んでいた向き）から、運ぶあいだに前（結果発表の向き）へ回って、ゆっくりよじれる。
func _orient_catch(c: LassoCatch, dt: float) -> void:
	if _t < T_YANK:
		return
	var hand := _rider.grip_point(c.hand)
	var hung := c.honda_pos
	var swinging := _t >= T_WIND - 0.15
	if swinging:
		# 縄を引いて 2 人をうしろへ振り上げ、前へ振り抜く（手のまわりの円の弧。前へ 36 度で放す）
		var phi := deg_to_rad(float(_track(_t, [[T_WIND - 0.15, 0.0], [T_WIND + 0.28, -52.0], [T_FLING - 0.12, -30.0], [T_FLING, 36.0]])))
		var swing := hand + (Basis(Vector3.UP, _cloud_yaw) * Vector3(0.0, -cos(phi), sin(phi))) * c.rope_len
		hung = c.honda_pos.lerp(swing, _ss(_t, T_WIND - 0.15, T_WIND + 0.05))
		c.honda_vel = (hung - c.honda_pos) / maxf(dt, 1e-4)
		c.honda_pos = hung
	# ぶん回されているあいだは、頭を手の方へ向けて体ごと縄の向きに伸び、進む向きを向く
	var whirl := _whirl_weight(_t)
	var vertical := WHIRL_STYLE == WhirlStyle.WHIRL_VERTICAL
	var want_up := (hand - hung).normalized()
	var tilt := want_up.angle_to(Vector3.UP)
	var max_tilt := deg_to_rad(76.0 if swinging else lerpf(MAX_BUNDLE_TILT_DEG, 88.0 if not vertical else MAX_BUNDLE_TILT_DEG, whirl))
	if tilt > max_tilt:
		want_up = Vector3.UP.slerp(want_up, max_tilt / tilt)
	c.bundle_up = c.bundle_up.slerp(want_up.normalized(), 1.0 - exp(-lerpf(7.0, 30.0, whirl) * dt)).normalized()
	var twist := sin(_t * TAU * 0.42 + c.twist_phase) * 0.3 * _ss(_t, T_YANK, T_YANK + 0.6)
	var heading := lerp_angle(c.yaw0, c.yaw_haul, _ss(_t, T_YANK, T_CRUISE + 0.4)) + twist
	var flat_vel := Vector2(c.honda_vel.x, c.honda_vel.z)
	if whirl > 0.0 and not vertical and flat_vel.length() > 1.0:
		heading = lerp_angle(heading, atan2(flat_vel.x, flat_vel.y), whirl)
	var forward := Vector3(sin(heading), 0.0, cos(heading))
	var z_axis := (forward - c.bundle_up * forward.dot(c.bundle_up)).normalized()
	var x_axis := c.bundle_up.cross(z_axis).normalized()
	var basis := Basis(x_axis, c.bundle_up, z_axis)
	if whirl > 0.0 and vertical:
		# 縦に振り回すとき：体は縄の向き（頭が手の方）に伸び、横の軸は雲の横、前は回る向き（上を越えて前へ）
		var radial := (hand - hung).normalized()
		var side := Basis(Vector3.UP, _cloud_yaw) * Vector3.RIGHT
		side = (side - radial * side.dot(radial)).normalized()
		var swung := Basis(side, radial, side.cross(radial))
		basis = Basis(basis.get_rotation_quaternion().slerp(swung.get_rotation_quaternion(), whirl))
		c.bundle_up = basis.y
	c.bundle = Transform3D(basis, hung - basis * _honda_local(c))


func _over_floor(p: Vector3) -> bool:
	return absf(p.x) <= StageConstants.FLOOR_HALF_WIDTH and p.z >= StageConstants.FLOOR_BACK_Z


## 結び目の位置（束の空間）。帯の輪郭の上で、角度 honda_angle の向きの所（前の真ん中 = 0）。
func _honda_local(c: LassoCatch) -> Vector3:
	var p := _band_point_at_angle(c.honda_angle, c.band_half)
	return Vector3(p.x, BAND_Y, p.y)


func _band_point_at_angle(angle: float, half: Vector2) -> Vector2:
	var dir := Vector2(sin(angle), cos(angle))
	# 角の丸い長方形（スタジアム形）の、真ん中から dir の向きの線が当たる所
	var r := half.y
	var straight := half.x - r
	var lo := 0.0
	var hi := half.x + 0.5
	for _i in range(18):
		var mid := (lo + hi) * 0.5
		if _stadium_sdf(dir * mid, straight, r) < 0.0:
			lo = mid
		else:
			hi = mid
	return dir * lo


static func _stadium_sdf(p: Vector2, straight: float, r: float) -> float:
	var q := Vector2(maxf(absf(p.x) - straight, 0.0), p.y)
	return q.length() - r


## 帯の輪郭の上の点を、結び目から始めて等間隔に count 個（束の空間の xz）。回る向きは飛ぶ輪とそろえる（角度が減る向き）。
func _band_contour(count: int, start_angle: float, half: Vector2) -> PackedVector2Array:
	var r := half.y
	var straight := half.x - r
	var samples := PackedVector2Array()
	var lengths := PackedFloat32Array()
	var steps := 240
	var total := 0.0
	var prev := Vector2.ZERO
	for i in range(steps + 1):
		var a := start_angle - TAU * float(i) / float(steps)
		var dir := Vector2(sin(a), cos(a))
		var lo := 0.0
		var hi := half.x + 0.5
		for _k in range(14):
			var mid := (lo + hi) * 0.5
			if _stadium_sdf(dir * mid, straight, r) < 0.0:
				lo = mid
			else:
				hi = mid
		var p := dir * lo
		if i > 0:
			total += p.distance_to(prev)
		samples.append(p)
		lengths.append(total)
		prev = p
	var out := PackedVector2Array()
	var j := 0
	for i in range(count):
		var target := total * float(i) / float(count)
		while j < steps - 1 and lengths[j + 1] < target:
			j += 1
		var span := maxf(lengths[j + 1] - lengths[j], 1e-6)
		out.append(samples[j].lerp(samples[j + 1], clampf((target - lengths[j]) / span, 0.0, 1.0)))
	return out


static func _band_length(half: Vector2) -> float:
	var r := half.y
	return 4.0 * maxf(half.x - r, 0.0) + TAU * r


static func _ellipse_perimeter(a: float, b: float) -> float:
	var h := pow(a - b, 2.0) / maxf(pow(a + b, 2.0), 1e-6)
	return PI * (a + b) * (1.0 + 3.0 * h / (10.0 + sqrt(4.0 - 3.0 * h)))


## 開いた輪の i 番目の点（i = 0 が結び目。束の空間で角度 honda_angle の向きから、角度が減る向きへ回る）：
## 束の x の向きに半径 a、直角に b の楕円で、2 人の高さの差だけ傾く。
func _open_loop_point(c: LassoCatch, center: Vector3, i: int, a: float, b: float, slope: float) -> Vector3:
	var phi := c.honda_angle - TAU * float(i) / float(LassoRope.LOOP_COUNT)
	var dir := Vector2(sin(phi), cos(phi))
	var r := 1.0 / sqrt(dir.x * dir.x / (a * a) + dir.y * dir.y / (b * b))
	var local := Vector3(dir.x * r, dir.x * r * slope, dir.y * r)
	return center + Basis(Vector3.UP, c.yaw0) * local


## 魂の部品の向き（度）。左右の「l_」は体の −X 側（ブロックマンの名前のまま）。
func _pose_soul(player_index: int) -> void:
	var soul := _souls.get(player_index) as Node3D
	if soul == null or not is_instance_valid(soul) or _released.get(player_index, false):
		return
	if _riding_shark(player_index):
		# サメに乗っているあいだは、乗った姿のまま（サメと乗り手の監督が動かす）
		return
	var t := _t
	var side := _side(player_index)
	var pos: Vector3 = _soul_pos[player_index]
	var basis := Basis.IDENTITY
	if t < T_RISE + 0.35:
		# 倒れた体から、あお向けに寝た姿勢で抜け出し、起き上がりながら浮かぶ
		var sit_up := _ss(t, 0.08, T_RISE + 0.3)
		basis = Basis(Vector3.RIGHT, deg_to_rad(-82.0) * (1.0 - sit_up))
	elif t >= T_CINCH:
		# 締められると束の向きへ（縛られた 2 人は並ぶ向きに向き直る）
		var c: LassoCatch = _catch_of[player_index]
		var bound := c.bundle.basis.orthonormalized().get_rotation_quaternion()
		basis = Basis(Quaternion.IDENTITY.slerp(bound, _ss(t, T_CINCH + 0.02, T_CINCHED)))
	var parts: Dictionary = soul.get_meta("ghost_mount_parts", {})
	if _ragdolls.has(player_index) and not parts.is_empty():
		_pose_ragdoll_soul(player_index, soul, parts)
		return
	soul.transform = Transform3D(basis.scaled(Vector3.ONE * _soul_scale(player_index)), pos)
	# 姿勢の土台は結果発表の立ち姿
	player_controller.apply_ghost_rider_result_pose(soul, player_index, false, t)
	if parts.is_empty():
		return
	var pose := _soul_pose_targets(player_index, side, t)
	for part_name: String in pose:
		var part := parts.get(part_name) as Node3D
		if part == null:
			continue
		var deg: Vector3 = pose[part_name]
		part.quaternion = Quaternion.from_euler(deg * (PI / 180.0))
	# 浮かび上がる間に透けた体が現れ、締めた瞬間に光る
	var alpha := 0.5 * _ss(t, 0.05, 0.45)
	var flash := 0.6 * (1.0 - _ss(t, 0.0, 0.4)) + 0.16 * _bump(t, T_CINCH + 0.04, T_CINCH + 0.24)
	player_controller.set_ghost_rider_shader_parameter(soul, &"body_alpha", alpha)
	player_controller.set_ghost_rider_shader_parameter(soul, &"flash", clampf(flash, 0.0, 1.0))


func _soul_pose_targets(player_index: int, side: float, t: float) -> Dictionary:
	var phase := 0.0 if player_index == 1 else 0.9
	# 雲を見る向き（体の空間の向きと上下）。輪が飛んでくる間は、自分に来る輪を見る
	var pos: Vector3 = _soul_pos[player_index]
	var look := _cloud_pos + Vector3.UP * 1.2 - (pos + Vector3.UP * 0.7)
	var own: LassoCatch = _catch_of.get(player_index)
	if t >= T_RELEASE and t < T_CINCH and own != null and own.rope != null:
		look = own.rope.get_loop_center() - (pos + Vector3.UP * 0.7)
	var look_yaw := clampf(atan2(look.x, look.z), deg_to_rad(-100.0), deg_to_rad(100.0))
	var look_pitch := clampf(atan2(look.y, Vector2(look.x, look.z).length()), deg_to_rad(-40.0), deg_to_rad(65.0))
	var attention := _ss(t, T_RISE - 0.15, T_RISE + 0.25)
	var head_yaw := rad_to_deg(look_yaw) * attention
	var head_pitch := -rad_to_deg(look_pitch) * attention
	# 浮かぶ（両腕を少し広げ、脚は軽く曲げる）
	var arm_out := 26.0 + 6.0 * sin(t * 2.4 + phase)
	var pose := {
		"spine": Vector3(6.0, head_yaw * 0.3, 0.0),
		"neck": Vector3(head_pitch * 0.3, head_yaw * 0.25, 0.0),
		"head_pivot": Vector3(head_pitch * 0.7, head_yaw * 0.45, 0.0),
		"l_shoulder": Vector3(10.0, 0.0, -arm_out),
		"r_shoulder": Vector3(10.0, 0.0, arm_out),
		"l_elbow": Vector3(-28.0, 0.0, 0.0),
		"r_elbow": Vector3(-28.0, 0.0, 0.0),
		"l_hip": Vector3(-14.0, 0.0, -3.0),
		"r_hip": Vector3(-8.0, 0.0, 3.0),
		"l_knee": Vector3(30.0, 0.0, 0.0),
		"r_knee": Vector3(22.0, 0.0, 0.0),
		"l_ankle": Vector3(26.0, 0.0, 0.0),
		"r_ankle": Vector3(26.0, 0.0, 0.0),
		"pelvis": Vector3(0.0, 0.0, 0.0),
	}
	# 驚く（雲が来て、その場で身をすくめる）→ 縮こまって震える（両手を口もとへ、膝を寄せる）
	var startle := _bump(t, T_CLOUD_ARRIVE - 0.45, T_CLOUD_ARRIVE + 0.1)
	var huddle := _ss(t, T_CLOUD_ARRIVE + 0.05, T_CLOUD_ARRIVE + 0.45) * (1.0 - _ss(t, T_OVER_HEADS - 0.15, T_OVER_HEADS))
	var shiver := sin(t * 47.0 + phase * 3.0) * 2.2 * huddle
	_blend_pose(pose, {
		"l_shoulder": Vector3(-150.0, 0.0, -30.0), "r_shoulder": Vector3(-150.0, 0.0, 30.0),
		"l_elbow": Vector3(-20.0, 0.0, 0.0), "r_elbow": Vector3(-20.0, 0.0, 0.0),
		"spine": Vector3(-10.0, head_yaw * 0.3, 0.0),
		"l_hip": Vector3(-30.0, 0.0, -8.0), "r_hip": Vector3(-30.0, 0.0, 8.0),
		"l_knee": Vector3(60.0, 0.0, 0.0), "r_knee": Vector3(60.0, 0.0, 0.0),
	}, startle)
	_blend_pose(pose, {
		"l_shoulder": Vector3(-62.0 + shiver, 0.0, 16.0), "r_shoulder": Vector3(-62.0 - shiver, 0.0, -16.0),
		"l_elbow": Vector3(-118.0, 0.0, 0.0), "r_elbow": Vector3(-118.0, 0.0, 0.0),
		"spine": Vector3(14.0 + shiver * 0.5, head_yaw * 0.32, shiver * 0.4),
		"l_hip": Vector3(-34.0, 0.0, 6.0), "r_hip": Vector3(-34.0, 0.0, -6.0),
		"l_knee": Vector3(62.0, 0.0, 0.0), "r_knee": Vector3(62.0, 0.0, 0.0),
		"l_ankle": Vector3(30.0, 0.0, 0.0), "r_ankle": Vector3(30.0, 0.0, 0.0),
	}, huddle)
	# 輪が頭の上を越えて落ちる：両手を上げてびっくり
	var hands_up := _ss(t, T_OVER_HEADS - 0.15, T_OVER_HEADS) * (1.0 - _ss(t, T_CINCH + 0.02, T_CINCH + 0.1))
	_blend_pose(pose, {
		"l_shoulder": Vector3(-168.0, 0.0, -14.0), "r_shoulder": Vector3(-168.0, 0.0, 14.0),
		"l_elbow": Vector3(-10.0, 0.0, 0.0), "r_elbow": Vector3(-10.0, 0.0, 0.0),
		"spine": Vector3(-8.0, 0.0, 0.0),
		"l_hip": Vector3(-6.0, 0.0, -4.0), "r_hip": Vector3(-6.0, 0.0, 4.0),
		"l_knee": Vector3(16.0, 0.0, 0.0), "r_knee": Vector3(16.0, 0.0, 0.0),
	}, hands_up)
	# 締められた：腕は体の横にぴたり。2 人まとめてなら相手の方へ少し寄りかかる。吊られると脚をばたつかせる
	var bound := _ss(t, T_CINCH + 0.02, T_CINCH + 0.1)
	var dangle := _ss(t, T_YANK, T_YANK + 0.35)
	var kick_speed := TAU * (2.6 if player_index == 1 else 2.25)
	var kick := sin(t * kick_speed + phase * 2.0)
	var lean := 0.0
	if own != null and own.players.size() > 1:
		lean = -signf(float(own.slots.get(player_index, side))) * 7.0
	_blend_pose(pose, {
		"l_shoulder": Vector3(2.0, 0.0, 4.0), "r_shoulder": Vector3(2.0, 0.0, -4.0),
		"l_elbow": Vector3(-6.0, 0.0, 0.0), "r_elbow": Vector3(-6.0, 0.0, 0.0),
		"spine": Vector3(2.0, head_yaw * 0.15, lean),
		"neck": Vector3(head_pitch * 0.3, head_yaw * 0.3, -lean * 0.5),
		"l_hip": Vector3(-6.0 - 34.0 * dangle * (0.5 + 0.5 * kick), 0.0, -2.0),
		"r_hip": Vector3(-6.0 - 34.0 * dangle * (0.5 - 0.5 * kick), 0.0, 2.0),
		"l_knee": Vector3(12.0 + 52.0 * dangle * (0.5 + 0.5 * sin(t * kick_speed + phase * 2.0 + 1.2)), 0.0, 0.0),
		"r_knee": Vector3(12.0 + 52.0 * dangle * (0.5 - 0.5 * sin(t * kick_speed + phase * 2.0 + 1.2)), 0.0, 0.0),
		"l_ankle": Vector3(34.0, 0.0, 0.0), "r_ankle": Vector3(34.0, 0.0, 0.0),
		"l_wrist": Vector3(0.0, 0.0, 22.0 * sin(t * 19.0 + phase) * dangle),
		"r_wrist": Vector3(0.0, 0.0, -22.0 * sin(t * 19.0 + phase) * dangle),
	}, bound)
	return pose


static func _blend_pose(pose: Dictionary, layer: Dictionary, weight: float) -> void:
	if weight <= 0.0:
		return
	for key: String in layer:
		var base: Vector3 = pose.get(key, Vector3.ZERO)
		pose[key] = base.lerp(layer[key], clampf(weight, 0.0, 1.0))


# ------------------------------------------------------------------ rope

func _update_rope(dt: float) -> void:
	# 当たり：魂の体（締めて巻きついている間は輪郭が形を決めるので外す）
	var souls: Array = _soul_capsules() if (_t < T_CINCHED or _t >= T_FLING) else []
	for c: LassoCatch in _catches:
		_update_catch_rope(c, dt, souls)


func _update_catch_rope(c: LassoCatch, dt: float, soul_colliders: Array) -> void:
	var rope := c.rope
	var hand := _rider.grip_point(c.hand)
	rope.hand = hand
	var rider_basis := _rider.transform.basis.orthonormalized()
	if rope.coil_visible:
		rope.coil_transform = Transform3D(rider_basis * Basis(Vector3.UP, PI * 0.5), _rider.grip_point("L"))
		rope.coil_radius = 0.15 * RIG_SCALE
		rope.slack_bulge = rider_basis.z * 0.42 * RIG_SCALE
	# 放す瞬間は、輪がハテナの体と帽子をすり抜けない
	var colliders: Array = soul_colliders.duplicate()
	if _t > T_RELEASE - 0.3 and _t < T_RELEASE + 0.45:
		colliders.append_array(_rider.colliders())
	rope.capsules = colliders
	rope.floor_y = _rope_floor_y if _t < T_FLING else StageConstants.FLOOR_TOP_Y
	rope.honda_pinned = false
	rope.stem_drag = 0.8
	rope.loop_drag = 1.2
	var k := RIG_SCALE
	if _t < T_WINDUP:
		# 雲が飛ぶ間は、手から垂らした小さな輪がなびく
		rope.loop_mode = LassoRope.LoopMode.FREE
		rope.loop_stiffness = 0.0
		rope.stem_length = 0.42 * k
		rope.loop_length = TAU * 0.3 * k
	elif _t < T_RELEASE:
		var theta := _theta0 + _twirl_integral(_t)
		var grip_local := _rider.grip_local(c.hand)
		var lift := _ss(_t, T_WINDUP, T_TWIRL)
		var radius := lerpf(0.3, 0.46, lift) + 0.36 * _ss(_t, T_TWIRL, T_RELEASE - 0.3)
		var spoke := lerpf(0.42, TWIRL_SPOKE, lift)
		if _two_ropes:
			radius = lerpf(0.3, 0.42, lift) + (TWIN_RADIUS - 0.42) * _ss(_t, T_TWIRL, T_RELEASE - 0.3)
			spoke = lerpf(0.42, TWIN_SPOKE, lift)
		var ring := _twirl_ring(theta, radius, spoke, grip_local, _knot_out(c.hand, TWIN_KNOT_OUT * lift))
		_set_ring_targets(rope, ring.center, ring.u, ring.w, radius, true)
		rope.loop_mode = LassoRope.LoopMode.SHAPED
		rope.loop_stiffness = 0.24 * _ss(_t, T_WINDUP, T_WINDUP + 0.3)
		rope.loop_length = TAU * radius * k
		rope.stem_length = hand.distance_to(_rider.transform * ring.honda)
		c.release_center = _rider.transform * ring.center
		c.release_u = (rider_basis * ring.u).normalized()
		c.release_radius = radius * k
	elif _t < T_OVER_HEADS:
		# 飛ぶ：輪は開きながら弧を描いて魂の頭の上へ。先が少し持ち上がり、着く前に水平へ戻って、
		# 2 人をまとめる輪なら 2 人の並ぶ向きへ大きく広がる
		var s := _seg(_t, T_RELEASE, T_OVER_HEADS)
		var e := 1.0 - pow(1.0 - s, 1.55)
		var over := c.target + Vector3.UP * OVER_HEADS
		var control := (c.release_center + over) * 0.5 + Vector3.UP * 1.6
		var center := _quad_bezier(c.release_center, control, over, e)
		var u := _flat(over - c.release_center)
		var tilt := deg_to_rad(lerpf(-TWIRL_DROOP_DEG, 0.0, s) + 26.0 * sin(PI * minf(s * 1.15, 1.0)))
		var w := Vector3.UP.cross(u).normalized()
		var u_t := (u * cos(tilt) + Vector3.UP * sin(tilt)).normalized()
		var radius := lerpf(c.release_radius, c.open_b, _ss(s, 0.0, 0.62))
		var widen := _ss(s, 0.3, 1.0)
		for i in range(LassoRope.LOOP_COUNT):
			var phi := TAU * float(i) / float(LassoRope.LOOP_COUNT)
			var round_point := center + (-u_t * cos(phi) + w * sin(phi)) * radius
			rope.loop_targets[i] = round_point.lerp(_open_loop_point(c, center, i, c.open_a, c.open_b, 0.0), widen)
		rope.loop_mode = LassoRope.LoopMode.SHAPED
		rope.loop_stiffness = lerpf(0.14, 0.3, _ss(s, 0.55, 1.0))
		rope.loop_length = lerpf(TAU * radius, _ellipse_perimeter(c.open_a, c.open_b), widen)
		rope.stem_length = hand.distance_to(rope.loop_targets[0]) * 1.03 + 0.35
		rope.stem_drag = 1.9
	elif _t < T_CINCH:
		# 落ちる：広げた輪が魂のまわりをすり抜けて胸の高さへ（2 人の高さが違えば、そのぶん傾く）
		var s := _seg(_t, T_OVER_HEADS, T_CINCH)
		var top := c.target + Vector3.UP * OVER_HEADS
		var band := c.target + Vector3.UP * BAND_Y
		var center := top.lerp(band, s * s)
		for i in range(LassoRope.LOOP_COUNT):
			rope.loop_targets[i] = _open_loop_point(c, center, i, c.open_a, c.open_b, c.slope * s)
		rope.loop_mode = LassoRope.LoopMode.SHAPED
		rope.loop_stiffness = 0.32
		rope.loop_length = _ellipse_perimeter(c.open_a, c.open_b)
		rope.stem_length = hand.distance_to(rope.loop_targets[0]) * 1.06 + 0.3
		rope.stem_drag = 1.5
	elif _t < T_FLING:
		# 締める：輪が縮んで魂を引き寄せ、帯になって巻きついたまま（結び目は束に付いて動く）
		var pull := _ss(_t, T_CINCH + 0.02, T_CINCHED)
		var half := Vector2(c.open_a, c.open_b).lerp(c.band_half, pull)
		var band_targets := _band_targets(c, half, c.slope * (1.0 - pull))
		for i in range(LassoRope.LOOP_COUNT):
			rope.loop_targets[i] = band_targets[i]
		rope.loop_mode = LassoRope.LoopMode.BOUND if pull >= 1.0 else LassoRope.LoopMode.SHAPED
		rope.loop_stiffness = lerpf(0.42, 0.9, pull)
		# 締めている間は輪郭より少し短くして張らせる（長いと縄がたわんで波打つ）
		rope.loop_length = _band_length(half) * lerpf(0.95, 1.0, pull)
		var honda := c.bundle * _honda_local(c)
		if _t >= T_CINCHED:
			rope.honda_pinned = true
			rope.honda_target = honda
		if c.pendulum_started:
			rope.stem_length = c.rope_len
		else:
			# 締めた直後は縄がたるみ、引いた瞬間にぴんと張る
			rope.stem_length = hand.distance_to(honda) * lerpf(1.1, 1.02, _seg(_t, T_CINCH, T_YANK)) + 0.12
	else:
		var s_open := _seg(_t, T_FLING, T_FLING + 0.3)
		if s_open < 1.0:
			# 放す：輪が開いて魂から外れ、勢いのまま前へ流れる
			var center := c.bundle * Vector3(0.0, BAND_Y, 0.0) + (Basis(Vector3.UP, _cloud_yaw) * Vector3(0.0, 0.4, 1.6)) * s_open
			var u := _flat(c.bundle * _honda_local(c) - center)
			var w := Vector3.UP.cross(u).normalized()
			var radius := lerpf(maxf(c.band_half.x, 0.4), 1.5 if c.players.size() > 1 else 0.9, _ss(s_open, 0.0, 0.5))
			_set_ring_targets(rope, center, u, w, radius, false)
			rope.loop_mode = LassoRope.LoopMode.SHAPED
			rope.loop_stiffness = 0.2 * (1.0 - s_open)
			rope.loop_length = TAU * radius
			rope.stem_length = hand.distance_to(center + u * radius) * 1.05 + 0.2
			rope.stem_drag = 1.4
		elif _t < T_EXIT + 0.2:
			# たぐり寄せる：縄が縮み、輪は床をこすって手元へはね上がる
			rope.loop_mode = LassoRope.LoopMode.FREE
			rope.loop_stiffness = 0.0
			rope.stem_length = maxf(0.42 * k, rope.stem_length - dt * 7.5)
			rope.loop_length = maxf(TAU * 0.3 * k, rope.loop_length - dt * 9.0)
			rope.stem_drag = 2.2
			rope.loop_drag = 2.4
		else:
			# 空へ帰る：小さな輪を頭の上で回す
			var twirl := _exit_twirl(_t)
			var grip_local := _rider.grip_local(c.hand)
			var radius := 0.34
			var ring := _twirl_ring(float(twirl.theta), radius, 0.55, grip_local, _knot_out(c.hand, 0.16))
			_set_ring_targets(rope, ring.center, ring.u, ring.w, radius, true)
			rope.loop_mode = LassoRope.LoopMode.SHAPED
			rope.loop_stiffness = 0.2 * _ss(_t, T_EXIT + 0.2, T_EXIT + 0.6)
			rope.loop_length = TAU * radius * k
			rope.stem_length = lerpf(rope.stem_length, hand.distance_to(_rider.transform * ring.honda), 1.0 - exp(-8.0 * dt))
	rope.simulate(dt)
	rope.rebuild_mesh()


## 輪の目標：結び目（i = 0）が center − u·r、i が増えると w の側へ回る円。local なら ハテナの空間から変える。
func _set_ring_targets(rope: LassoRope, center: Vector3, u: Vector3, w: Vector3, radius: float, local: bool) -> void:
	var xform := _rider.transform
	for i in range(LassoRope.LOOP_COUNT):
		var phi := TAU * float(i) / float(LassoRope.LOOP_COUNT)
		var p := center + (-u * cos(phi) + w * sin(phi)) * radius
		rope.loop_targets[i] = xform * p if local else p


## 締めていく帯の輪郭（束の空間から GameWorld のローカルへ）。結び目から等間隔。half は今の帯の大きさ、
## slope は 2 人の高さの差の残り（締め終わると 0）。
func _band_targets(c: LassoCatch, half: Vector2, slope: float) -> PackedVector3Array:
	var contour := _band_contour(LassoRope.LOOP_COUNT, c.honda_angle, half)
	var out := PackedVector3Array()
	out.resize(LassoRope.LOOP_COUNT)
	for i in range(LassoRope.LOOP_COUNT):
		var p := contour[i]
		out[i] = c.bundle * Vector3(p.x, BAND_Y + p.x * slope, p.y)
	return out


func _soul_capsules() -> Array:
	var out: Array = []
	for player_index: int in _souls:
		var soul := _souls[player_index] as Node3D
		if soul == null or not is_instance_valid(soul) or _released.get(player_index, false):
			continue
		# サメに乗った乗り手はサメの子なので、ワールドから直す
		var xform := global_transform.affine_inverse() * soul.global_transform
		var k := xform.basis.get_scale().x
		out.append([xform * Vector3(0.0, -0.35, 0.0), xform * Vector3(0.0, 0.42, 0.0), 0.27 * k])
		out.append([xform * Vector3(0.0, 0.62, 0.0), xform * Vector3(0.0, 0.74, 0.0), 0.16 * k])
	return out


# ------------------------------------------------------------------ camera

func _update_camera(dt: float) -> void:
	var shot := _shot(_t)
	var follow := float(shot.get("follow", 3.0))
	var aim := float(shot.get("aim", 3.0))
	var want_eye: Vector3 = shot.eye
	want_eye.y = maxf(want_eye.y, _lowest_eye_y(want_eye))
	# 流れてくる壁の中へカメラが入らない（壁の近くでは壁の上を通す）
	if _t >= T_SCROLL_START and _t < T_SCROLL_END and _wall_near(_cam_eye.z, 6.0):
		want_eye.y = maxf(want_eye.y, _wall_top + 1.2)
	var eye_step := _smooth_damp(_cam_eye, want_eye, _cam_eye_vel, follow, dt)
	_cam_eye = eye_step[0]
	_cam_eye_vel = eye_step[1]
	var target_step := _smooth_damp(_cam_target, shot.target, _cam_target_vel, aim, dt)
	_cam_target = target_step[0]
	_cam_target_vel = target_step[1]
	_cam_fov = lerpf(_cam_fov, float(shot.fov), 1.0 - exp(-follow * dt))
	var forward := _cam_target - _cam_eye
	if forward.length_squared() < 1e-6:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.985:
		up = Vector3.BACK
	var local := Transform3D(Basis.looking_at(forward, up), _cam_eye)
	var global := world.global_transform * local if world != null else local
	if not _handed_over:
		camera_controller.call("set_director_pose", global, _cam_fov)


## z の前後 reach m に、今出ている壁があるか。
func _wall_near(z: float, reach: float) -> bool:
	var walls: Variant = world.get("_active_walls") if world != null else null
	if not (walls is Array):
		return false
	for wall: Variant in walls:
		if wall is Node3D and is_instance_valid(wall) and (wall as Node3D).visible and absf((wall as Node3D).position.z - z) < reach:
			return true
	return false


## カメラが下がってよい高さ（床の上なら床から、外なら海から少し上）。
func _lowest_eye_y(eye: Vector3) -> float:
	if _over_floor(eye):
		return StageConstants.FLOOR_TOP_Y + 0.9
	return StageConstants.OCEAN_SURFACE_Y + 1.4


## カメラの狙い（カットなし。ばねで追うので、狙いが変わってもなめらかにつながる）。寄り（ズーム）や回り込みはしない：
##   捕まえるまで → ゲームオーバーのカメラから一度だけ、2 人・止まったハテナ・広げた輪が収まる画（_stage_shot）へ寄せて
##   そのまま動かさない（雲はその画の中へ飛んでくる）→ 吊り上げて運ぶ：斜めうしろから、ハテナと吊られた 2 人を追う
##   → 投げつける：門の手前の斜めうしろの低い所から、門越しに → 結果発表の最初のカメラへ寄せる。
func _shot(t: float) -> Dictionary:
	var k := RIG_SCALE
	var cloud_basis := Basis(Vector3.UP, _cloud_yaw)
	if not debug_view.is_empty() and t >= T_CLOUD_ARRIVE - 0.3 and t < T_YANK + 0.6:
		var side_sign := 1.0 if debug_view == "hatena_left" else -1.0
		var debug_eye := _cloud_pos + cloud_basis * (Vector3(3.6 * side_sign, 1.3, 1.2) * k)
		var debug_target := _cloud_pos + cloud_basis * (Vector3(0.0, 1.35, 0.9) * k)
		return {"eye": debug_eye, "target": debug_target, "fov": 46.0, "follow": 30.0, "aim": 30.0}
	var away := -_cloud_side
	var souls := _soul_points()
	var shot := _stage_shot.duplicate()
	# 吊り上げて運ぶ：雲が速く動くので、ばねの遅れの分だけ先回りする（_lead）
	var w := _ss(t, T_YANK - 0.15, T_YANK + 0.25)
	if w > 0.0:
		# 吊り上げた直後は上へ速く動くので、余白を広めに
		var margin := lerpf(1.65, 1.3, _ss(t, T_YANK + 0.4, T_CRUISE + 0.2))
		var points := souls + _hatena_points()
		# ぶん回しているあいだは、2 人が回る円を丸ごと入れる（2 人の今の所に合わせてカメラが揺れない）
		var spin := _whirl_weight(t)
		if spin > 0.0:
			var hub := _cloud_pos + Vector3.UP * 0.7
			var reach := (L_HAUL + 2.2) * spin
			if WHIRL_STYLE == WhirlStyle.WHIRL_VERTICAL:
				# 縦の円（左右の手のまわり。上・下・前・うしろ）
				var frame := Basis(Vector3.UP, _cloud_yaw)
				for side: float in [-1.0, 1.0]:
					var pivot := hub + frame * Vector3(1.0 * side, 0.0, 0.0)
					for dir: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
						points.append(pivot + frame * dir * reach)
			else:
				for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
					points.append(hub + dir * reach + Vector3.DOWN * 0.9)
					points.append(hub + dir * reach + Vector3.UP * 0.6)
		var chase := _fit(points, _look_dir(atan2(0.8 * away, -0.6), deg_to_rad(14.0)), 50.0, margin, 6.0)
		chase["follow"] = 4.6
		chase["aim"] = 5.6
		shot = _blend_shot(shot, _lead(chase, 1.0), w)
	# 投げつける：門の手前へ降りる雲の斜めうしろの低い所から、門越しにゴールラインの先が見える画にする
	w = _ss(t, T_DESCEND - 0.1, T_FLING_SET + 0.1)
	if w > 0.0:
		var goal_mid: Vector3 = (_lanes[1] + _lanes[2]) * 0.5
		var landing := [goal_mid + Vector3(-2.6, -1.2, -1.2), goal_mid + Vector3(2.6, 0.9, 0.6)]
		var goal_dir := _look_dir(atan2(9.4 * away, -9.6), deg_to_rad(10.0))
		var goal_shot := _fit(landing + souls + _hatena_points(), goal_dir, 52.0, 1.1, 7.0)
		# 放したあとは、空へ帰るハテナを追わずにゴールへ
		var gone := _ss(t, T_FLING + 0.2, T_FLING + 0.7)
		if gone > 0.0:
			goal_shot = _blend_shot(goal_shot, _fit(landing + souls, goal_dir, 52.0, 1.1, 7.0), gone)
		goal_shot["follow"] = 3.8
		goal_shot["aim"] = 4.2
		shot = _blend_shot(shot, goal_shot, w)
	# 2 人が投げつけられて転がり、起き上がるのを見ながら、結果発表の最初のカメラへ寄せていく
	w = _ss(t, T_FLING + 0.6, T_FLING + 1.6)
	if w > 0.0:
		var final_eye: Vector3 = _final_cam.get("eye", Vector3.ZERO)
		var final_forward: Vector3 = _final_cam.get("forward", Vector3.BACK)
		var finale := {"eye": final_eye, "target": final_eye + final_forward * 10.0, "fov": float(_final_cam.get("fov", 40.0)),
			"follow": 6.0, "aim": 7.0}
		shot = _blend_shot(shot, finale, w)
	return shot


## 捕まえるまでの画に入れるもの（決まった所。動かない）：浮かんだ魂（頭と足）、止まったハテナ（回す輪まで）、広げた輪。
func _stage_points() -> Array:
	var out: Array = []
	for player_index: int in _soul_rise:
		var p: Vector3 = _soul_rise[player_index]
		out.append(p + Vector3.UP * 0.85)
		out.append(p + Vector3.DOWN * 1.2)
	var mid: Vector3 = (_soul_rise[1] + _soul_rise[2]) * 0.5
	var hatena := Transform3D(Basis(Vector3.UP, _yaw_of(mid - _cloud_hover)).scaled(Vector3.ONE * RIG_SCALE), _cloud_hover)
	# 両手の縄は左右へ広げて回すので、そのぶん横に広く
	var half_x := 2.4 if _two_ropes else 1.6
	for x: float in [-half_x, half_x]:
		for y: float in [-0.35, 2.5]:
			for z: float in [-0.9, 0.9]:
				out.append(hatena * Vector3(x, y, z))
	for c: LassoCatch in _catches:
		var basis := Basis(Vector3.UP, c.yaw0)
		for x: float in [-c.open_a, c.open_a]:
			out.append(c.target + basis * Vector3(x, OVER_HEADS, 0.0))
	return out


## 魂の見える所（頭と足。GameWorld のローカル）。
func _soul_points() -> Array:
	var out: Array = []
	for player_index: int in _soul_pos:
		var p: Vector3 = _soul_pos[player_index]
		out.append(p + Vector3.UP * 0.85)
		out.append(p + Vector3.DOWN * 1.2)
	return out


## ハテナの見える箱の角（雲・体・帽子）。
func _hatena_points() -> Array:
	var out: Array = []
	if _rider == null:
		return out
	var xform := _rider.transform
	for x: float in [-1.25, 1.25]:
		for y: float in [-0.35, 1.85]:
			for z: float in [-0.9, 0.9]:
				out.append(xform * Vector3(x, y, z))
	return out


## 点がすべて画面に収まる、いちばん近いカメラ（forward の向きから見る）。{eye, target, fov}
func _fit(points: Array, forward: Vector3, fov: float, margin: float, min_dist: float) -> Dictionary:
	var f := forward.normalized()
	var right := f.cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
	var up := right.cross(f).normalized()
	var mean := Vector3.ZERO
	for p: Vector3 in points:
		mean += p
	mean /= float(maxi(points.size(), 1))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector3 in points:
		var q := Vector2((p - mean).dot(right), (p - mean).dot(up))
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var center := mean
	if not points.is_empty():
		center += right * ((lo.x + hi.x) * 0.5) + up * ((lo.y + hi.y) * 0.5)
	var tan_v := tan(deg_to_rad(fov) * 0.5) / margin
	var tan_h := tan_v * _aspect()
	var dist := min_dist
	for p: Vector3 in points:
		var r := p - center
		var depth := r.dot(f)
		dist = maxf(dist, absf(r.dot(right)) / tan_h - depth)
		dist = maxf(dist, absf(r.dot(up)) / tan_v - depth)
	return {"eye": center - f * dist, "target": center, "fov": fov}


## 雲について動く画の先回り：ばね（_smooth_damp）は一定の速さで動くものに 2/ω 秒ぶん遅れるので、その分だけ前へ置く。
func _lead(shot: Dictionary, weight: float) -> Dictionary:
	if weight <= 0.0:
		return shot
	var velocity := _cloud_vel.limit_length(16.0) * weight
	shot["eye"] = (shot.eye as Vector3) + velocity * (2.0 / maxf(float(shot.get("follow", 3.0)), 0.5))
	shot["target"] = (shot.target as Vector3) + velocity * (2.0 / maxf(float(shot.get("aim", 3.0)), 0.5))
	return shot


static func _blend_shot(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var w := clampf(weight, 0.0, 1.0)
	return {
		"eye": (a.eye as Vector3).lerp(b.eye, w),
		"target": (a.target as Vector3).lerp(b.target, w),
		"fov": lerpf(float(a.fov), float(b.fov), w),
		"follow": lerpf(float(a.get("follow", 3.0)), float(b.get("follow", 3.0)), w),
		"aim": lerpf(float(a.get("aim", 3.0)), float(b.get("aim", 3.0)), w),
	}


## カメラの向き：被写体から見てカメラのいる水平の向き yaw（atan2(x, z)）から、pitch だけ見下ろす（負なら見上げる）。
static func _look_dir(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))


func _aspect() -> float:
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16.0, 9.0)
	return size.x / maxf(size.y, 1.0)


## なめらかに追う（臨界減衰のばね）。[新しい位置, 新しい速さ]
static func _smooth_damp(current: Vector3, target: Vector3, velocity: Vector3, omega: float, dt: float) -> Array:
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (velocity + change * omega) * dt
	var new_velocity := (velocity - temp * omega) * e
	var result := target + (change + temp) * e
	return [result, new_velocity]


# ------------------------------------------------------------------ sound

func _update_sound() -> void:
	_cue_at("cloud", T_CLOUD_START + 0.1, func() -> void: AudioManager.play_sfx(&"sd_cloud_whoosh", -3.0))
	# 回すたびに ヒュン（1 周ごと、だんだん高く）
	if _t >= T_TWIRL - 0.1 and _t < T_RELEASE:
		var turns := int(floor((_theta0 + _twirl_integral(_t)) / TAU + 0.25))
		if turns > _whirl_count:
			_whirl_count = turns
			var speed := _seg(_t, T_TWIRL, T_RELEASE)
			AudioManager.play_sfx(&"lasso_whirl", lerpf(-6.0, -1.0, speed), lerpf(0.86, 1.18, speed))
	elif _t < T_TWIRL - 0.1:
		_whirl_count = int(floor((_theta0 + _twirl_integral(_t)) / TAU + 0.25))
	_cue_at("throw", T_RELEASE - 0.03, func() -> void:
		AudioManager.play_sfx(&"lasso_throw")
		if _two_ropes:
			AudioManager.play_sfx(&"lasso_throw", -3.0, 1.12))
	_cue_at("cinch", T_CINCH + 0.02, func() -> void:
		AudioManager.play_sfx(&"lasso_cinch")
		AudioManager.play_sfx(&"bonk", -2.0, 1.25))
	_cue_at("yank", T_YANK + 0.02, func() -> void:
		AudioManager.play_sfx(&"sg_bounce", -2.0, 1.05)
		AudioManager.play_sfx(&"lasso_cinch", -4.0, 0.85))
	_cue_at("haul", T_YANK + 0.3, func() -> void: AudioManager.play_sfx(&"sd_cloud_whoosh", -5.0, 1.12))
	_cue_at("rush", T_SCROLL_START + 0.55, func() -> void: AudioManager.play_sfx(&"sg_gate_rush", -4.0, 0.92))
	_cue_at("descend", T_DESCEND, func() -> void: AudioManager.play_sfx(&"sd_cloud_whoosh", -5.0, 0.94))
	_cue_at("wind", T_WIND + 0.05, func() -> void: AudioManager.play_sfx(&"lasso_whirl", -4.0, 0.8))
	_cue_at("fling", T_FLING - 0.04, func() -> void:
		AudioManager.play_sfx(&"lasso_throw", -2.0, 0.9)
		AudioManager.play_sfx(&"ghost_dash", -6.0, 1.1))
	_cue_at("reel", T_FLING + 0.32, func() -> void: AudioManager.play_sfx(&"lasso_whirl", -8.0, 1.3))
	_cue_at("stand", _ceremony_at - 0.15, func() -> void: AudioManager.play_sfx(&"ghost_mount_land", -8.0))


func _cue_at(cue: String, time: float, callback: Callable) -> void:
	if _t >= time and not _cues.has(cue):
		_cues[cue] = _t
		if time > _t - 0.25:
			callback.call()


# ------------------------------------------------------------------ helpers

func _to_hatena(local_point: Vector3) -> Vector3:
	return _rider.transform.affine_inverse() * local_point


func _to_local_xform(global: Transform3D) -> Transform3D:
	return world.global_transform.affine_inverse() * global if world != null else global


static func _mirror(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


static func _yaw_of(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)


static func _flat(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 1e-8 else Vector3.BACK


static func _seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / maxf(b - a, 1e-5), 0.0, 1.0)


static func _ss(t: float, a: float, b: float) -> float:
	return smoothstep(a, b, t)


## a から b の間で 0 → 1 → 0（なめらかな山）。
static func _bump(t: float, a: float, b: float) -> float:
	var s := _seg(t, a, b)
	return sin(s * PI) if s > 0.0 and s < 1.0 else 0.0


static func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var v := 1.0 - u
	return p0 * (v * v * v) + p1 * (3.0 * v * v * u) + p2 * (3.0 * v * u * u) + p3 * (u * u * u)


static func _quad_bezier(p0: Vector3, p1: Vector3, p2: Vector3, u: float) -> Vector3:
	var v := 1.0 - u
	return p0 * (v * v) + p1 * (2.0 * v * u) + p2 * (u * u)


static func _hermite(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, duration: float, s: float) -> Vector3:
	var s2 := s * s
	var s3 := s2 * s
	return p0 * (2.0 * s3 - 3.0 * s2 + 1.0) + v0 * duration * (s3 - 2.0 * s2 + s) + p1 * (-2.0 * s3 + 3.0 * s2) + v1 * duration * (s3 - s2)


## キー [[時刻, 値], ...] を Catmull-Rom でなめらかにつなぐ（値は float か Vector3）。
static func _track(t: float, keys: Array) -> Variant:
	var n := keys.size()
	if t <= float(keys[0][0]):
		return keys[0][1]
	if t >= float(keys[n - 1][0]):
		return keys[n - 1][1]
	var k := 0
	while k < n - 2 and t > float(keys[k + 1][0]):
		k += 1
	var t0 := float(keys[k][0])
	var t1 := float(keys[k + 1][0])
	var v0: Variant = keys[k][1]
	var v1: Variant = keys[k + 1][1]
	var h := t1 - t0
	var m0: Variant = v0 * 0.0
	var m1: Variant = v1 * 0.0
	if k > 0:
		m0 = (v1 - keys[k - 1][1]) / (t1 - float(keys[k - 1][0])) * h
	if k + 2 < n:
		m1 = (keys[k + 2][1] - v0) / (float(keys[k + 2][0]) - t0) * h
	var s := (t - t0) / h
	var s2 := s * s
	var s3 := s2 * s
	return v0 * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (s3 - 2.0 * s2 + s) + v1 * (-2.0 * s3 + 3.0 * s2) + m1 * (s3 - s2)
