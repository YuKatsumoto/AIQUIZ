class_name SkyGatePresenter
extends SuddenDeathPresenter

## サドンデス「つきやぶれ！スカイゲート」の見せ方（docs/sudden_death_v2/sky_gate.md 第3・5・6章、skygate_build_plan.md 4.5節）。
## ルールは持たない（SkyGateGame を読む。判定はルール）。受け持つのは本戦（図解ルールカードから決着まで）と、着地台への着地・ダンス。
## 乗り込み・離水・機内・降下・迎え・帰還は監督（W6）が受け持つ。descent_mode() は "floatplane"。
##
## 監督への口（W6 が SuddenDeathPresenter に足す）：round_cleared()（2人とも着地台に着いて「ROUND 2」を見せ終えた）、
## begin_round(round)（降下が終わって次のラウンドを始める）、sky_spawn(player)（降下が終わったときに2人が落ちている位置）。
## 監督なしでも動く（setup_solo。デバッグの入口 sky_gate_debug.gd とテスト）。
##
## 空中：2人は空のセットの下の「落ちる点」のまわりに留め（位置はルールのボードの座標）、雲を下から上へ流して落ちているように
## 見せる。ボードはドローンで吊られて真下に一列に並び（列。2026-10-25 から時間制限なし）、ルールの board_depth(k) のとおりに
## 一定の速さで上がってきて、今のボードが2人の高さに届いた瞬間に当たる。ラウンドの頭は斜め上からの引きの画（G4_Column）で
## 4 枚の列を見せてから、見下ろし（G2_TopDown）へ寄せる。ボードの x（右）はワールドの −X、y（前）は +Z。カメラは +Z を向くので
## P1（+X）は常に画面の左。まちがえた人がいても画は切り替えず、見下ろしのまま強いスローと色抜けで爆散を見せる（GTA 風）。
## 人物は、プレイヤーの見た目を写した人形（build_player_skeleton）。空中の腹ばいは DropMotion（SD_Box_Loop と傾き 4 つ）、
## パラシュート（ParachuteCanopy）・着地・勝ちの姿は関節の角度の表（ParachutePresenter と同じ作り）。
## ボードと効果は SkyGateBoard・SkyGateEffects（W5）。空の演出は W7 の SkyFallScenery（体積雲・島・海のサングリント・風切り）と
## マフラー SkyFallScarf（assets/sudden_death/sky_fx/README.md）。本戦の画の環境は SkyFallScenery.venue_environment。

const SKY_ORIGIN := HeliSuddenDeathDirector.SKY_ORIGIN
## 落ちる点（ボードが止まっているときの中心が、ゲートの時刻に来る点）。空のセットの中心から 40 m 下。
const FALL_DROP := 40.0
## ボードの座標の向き（ワールド）：x＝右は −X、y＝前は +Z。
const RIGHT := Vector3(-1.0, 0.0, 0.0)
const FORWARD := Vector3(0.0, 0.0, 1.0)
## ボードのノードの向き（ボードのローカルの +X が右、−Z が奥なので、Y まわりに半回転）。
const BOARD_TURN := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))

# ボードの列（深さはルールの board_depth。sky_gate.md 3.2）
## 列の 4 枚と、当たって消えていく 1 枚（延長は今のボードの下に 3 枚）。
const BOARD_POOL := 5
## 決着したとき・本戦が終わったとき、残りのボードが消えるまでの秒。
const BOARD_LEAVE_TIME := 0.5
## ラウンドの頭の海の深さ（SkyFallScenery.sea_depth の遠い側をこの倍に。最後のあたり（近い側 75 m）は同じ）。
const SEA_START_SCALE := 1.6
## 落ちる速さ（雲を流す速さ、m/秒。空の演出の雲海の高さは ROUND 1 の毎秒 40 m で作ってある）。
const FALL_SPEED := 40.0
## ボードは海よりこれだけ上にあるときだけ見せる（列の深いボードが海の中に見えないように）。
const BOARD_SEA_CLEAR := 30.0
## 海の高さを寄せる速さの上限（m/秒）。ラウンドの頭など行き先が変わっても、海と島は飛ばずに動く。
const SEA_RATE := 420.0

# カメラ（sky_gate.md 第6章）
## G2_TopDown：2人の上・少し後ろから見下ろす（sky_gate.md の案は 75°。体と真下のパネルが遠近でずれて見えないよう、
## ほぼ真上の 84° にした）。2人とボードが入るように高さを寄せる。注視点は2人の真ん中を、近づいたボードの真ん中へ半分寄せる。
## 高い所から狭い画角で見る（望遠ぎみ）：近い2人と下のボードの大きさの差が小さくなり、体がボードを隠しにくい。
const MAIN_FOV := 40.0
const PITCH := 84.0
const BOARD_AIM := 0.5
const CAM_NEAR := 16.0
const FRAME_TOP := 0.17
const FRAME_BOTTOM := 0.88
const FRAME_WIDTH := 0.84
const BODY_PAD := 1.0
const FIT_OUT_RATE := 4.0
const FIT_IN_RATE := 1.4
## ボードの四隅を画に入れ始める深さ（これより遠いとボードの中心だけ）。
const FIT_BOARD_FAR := 70.0
const FIT_BOARD_NEAR := 24.0
## ボードに近づいたら2人へ寄る（2026-10-20、ユーザーの指示「選択肢に近づいたらカメラも近づく」）：当たるまでが
## ゲートの長さの PUSH_SHARE（最大 PUSH_LEAD 秒）を切ったら、ボードと問題文の看板を画に収めるのをやめて、2人の体だけを
## 収める近さ（PUSH_NEAR m まで）へ寄せる。当たる PUSH_DONE 秒前に寄りきる。ボードは下から画いっぱいに迫ってくる。
## つき破ったあとは元の距離へ戻す。
const PUSH_SHARE := 0.3
const PUSH_LEAD := 2.4
const PUSH_DONE := 0.45
const PUSH_NEAR := 8.5
const PUSH_RATE := 3.2
## 通り抜けるとき（全員が正解）は見下ろし（G2）のまま。ボードは体の上を通りすぎながら消える（ユーザーの指示）。
## まちがえた人がいても画は切り替えない（2026-10-25、ユーザーの指示「今のカメラの切り替えから、そのままの降りるカメラで
## ぶつかったら GTA のように画面がスローモーションになって爆散」）：見下ろしのまま、色抜けの強さ（SkyGateImpact.wasted_amount）を
## WASTED_CAM_RATE（1/秒、実時間）でならした重さで、注視点をぶつかった人へ WASTED_AIM だけ寄せ、距離を WASTED_PULL 倍へゆっくり
## 引く（寄ったままだとボードが画いっぱいで、はね返りと爆散が見えない）。画面の色は彩度・明るさ・コントラストを WASTED_* へ、
## まわりは HUD が暗くする。はね返り・爆発の音は WASTED_PITCH まで音程を下げる。
const WASTED_AIM := 0.75
const WASTED_PULL := 1.35
const WASTED_CAM_RATE := 2.5
const WASTED_SATURATION := 0.1
const WASTED_BRIGHTNESS := 0.92
const WASTED_CONTRAST := 1.12
const WASTED_PITCH := 0.7
## G4_Column（2026-10-25、ユーザーの指示「4 枚が下へ続く列を最初に見せる」）：ラウンドの頭に、斜め上から下へ続く列を収める
## 引きの画。目は落ちる点から COLUMN_EYE（右は −X）、落ちる点の COLUMN_LOOK_DEPTH m 下を見る。ROUND 1 は降下のあと
## RULES_DELAY 秒この画を見せてからルールカードを出し、カウントダウンの「2」から GO までに見下ろしへ寄せる。
const COLUMN_FOV := 52.0
const COLUMN_EYE := Vector3(-34.0, 18.0, -58.0)
const COLUMN_LOOK_DEPTH := 120.0
const RULES_DELAY := 1.4
## 真下の印（ボードの紙の上の、自分の色の輪）。
const MARKER_RADIUS := 0.62
const MARKER_RANGE := 90.0
const MARKER_ALPHA := 0.42

# 海（ラウンドの進みで近づく。深さは SkyFallScenery.sea_depth：1150 m → 75 m、延長 520 m）と着地台
const LANDING_DROP := 20.0
## マフラーが受ける空気の流れ（体に対して、m/秒）：落ちている間・パラシュートの下・着地台の上。
const SCARF_AIR_FALL := Vector3(0.0, 30.0, 0.0)
const SCARF_AIR_CANOPY := Vector3(0.0, 6.0, 0.0)
const SCARF_AIR_GROUND := Vector3(0.0, 1.5, 0.0)
const LAND_SPREAD := 1.25
## 立った人形の腰の高さ（着地台の床から、m）。
const STAND_HIP := 1.32

# 導入
const RULE_HOLD := 0.6
const COUNT_STEP := 0.6
## ROUND 2 から：カウントダウンの前に「ROUND n」の見出しを見せる秒。
const ROUND_INTRO := 1.4

# 着地（ROUND のあと・決着。判定のあとから数える。skygate_impact.md 第4章）
## 空中から着地台までを切らずにつなぐ：海と着地台が下から上がってくる（体は落ちる点のまま）のと、体が最後の LANDING_DROP m を
## 実際に下りるのを合わせる。高い所からはまず頭を下にして急降下（DIVE）し、H_OPEN m でパラシュートを開く。
## 開いてから SNATCH 秒は落ちる速さのまま、そのあと V_CANOPY m/秒へ落ちつき、H_FLARE m で引いて着地する。
const H_OPEN := 60.0
const DIVE_AVG_MAX := 260.0
const DIVE_TIME_MAX := 2.4
const SNATCH := 0.35
const SNATCH_TAU := 0.35
const V_CANOPY := 12.0
const H_FLARE := 2.2
## 決着のあと、着地を始めるまで（判定の札を見せる間）。
const FINISH_BEAT := 0.25
## 着地からの秒：「ROUND n」の見出し・ROUND の終わり（監督が迎えを呼ぶ）・決着の終わり。
const L_BANNER_AFTER := 0.4
const L_ROUND_DONE_AFTER := 2.2
const L_FINISH_DONE_AFTER := 2.4
## 着地の画：空中の画から寄せる秒・追いかけの距離・着地台のまわりを回る画へ替わる高さ。
const LAND_CAM_BLEND := 1.2
const LAND_FOLLOW_DIST := 15.0
const LAND_ORBIT_FROM := 14.0
const LANDING_RADIUS := 9.6
const DANCE_RADIUS := 8.6
const DANCE_AUTO := 2.5
const EXTRACT_DELAY := 3.6
const ORBIT_SPEED := 12.0
## パラシュートのあと、布が落ちる床の点（着地した人の後ろ、m）。
const GROUND_BEHIND := 0.45
## 2人とも同じゲートでアウト：ブロックが体に戻り始める（復活の 1.0 秒のうち）。
const GATHER_AT := 0.5
const GATHER_TIME := 0.45
## 決着：アウトの人のブロックが集まって幽霊になる（スローのあとから）。
const GHOST_AT := 0.4

const AXES := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}
## 関節の角度の表（ParachutePresenter と同じ：関節・軸・度。+X＝r_ の腕の側、+Y＝頭、+Z＝胸）。
const POSE_BOX := [
	["spine", "x", -16.0], ["head_pivot", "x", -64.0],
	["l_shoulder", "z", -82.0], ["l_shoulder", "x", 14.0], ["l_elbow", "z", -78.0],
	["r_shoulder", "z", 82.0], ["r_shoulder", "x", 14.0], ["r_elbow", "z", 78.0],
	["l_hip", "z", -16.0], ["r_hip", "z", 16.0], ["l_hip", "x", 10.0], ["r_hip", "x", 10.0],
	["l_knee", "x", 58.0], ["r_knee", "x", 58.0],
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
const POSE_WIN := [
	["l_shoulder", "z", -160.0], ["r_shoulder", "z", 160.0], ["l_elbow", "z", -12.0], ["r_elbow", "z", 12.0],
	["l_hip", "z", -8.0], ["r_hip", "z", 8.0], ["head_pivot", "x", -10.0],
]
## 着地台で顔を見合わせる（ROUND の間）。
const POSE_STAND := [
	["l_shoulder", "z", -18.0], ["r_shoulder", "z", 18.0], ["l_elbow", "z", -10.0], ["r_elbow", "z", 10.0],
]
## 幽霊：ふわっと浮く（腕を少し前へ、脚をそろえる）。
const POSE_GHOST := [
	["l_shoulder", "z", -40.0], ["r_shoulder", "z", 40.0], ["l_shoulder", "x", -50.0], ["r_shoulder", "x", -50.0],
	["l_elbow", "x", -30.0], ["r_elbow", "x", -30.0], ["l_hip", "x", -12.0], ["r_hip", "x", -6.0], ["l_knee", "x", 24.0], ["r_knee", "x", 18.0],
]
const PLAYER_COLORS: Array[Color] = [Color(0.95, 0.55, 0.20), Color(0.18, 0.59, 0.90)]
## 落ちている間の風切り（ループ。効果音ラボ「風が吹く2」。docs/sound_effects.md「サドンデス」）：いっぱいの音量（dB）と、
## ルールカードの間・パラシュートが開いたあとの割合。スローの間は音程を下げる。
const WIND_LOOP := "res://assets/audio/sfx/se_lab/sd_freefall_loop.ogg"
const WIND_DB := -3.0
const WIND_RULES := 0.45
const WIND_CANOPY := 0.22

## ブロックが集まる効果（2人とも同じゲートでアウトの復活・幽霊になる）。色つきの小さな箱が、まわりから体の中心へ吸い込まれる。
class Gather extends Node3D:
	const COUNT := 22
	var _mm: MultiMesh = null
	var _from := PackedVector3Array()
	var _spin := PackedVector3Array()
	var _delay := PackedFloat32Array()
	var _t := -1.0
	var _length := 0.45

	func build(color: Color, seed_value: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_3D
		_mm.use_colors = true
		var box := BoxMesh.new()
		box.size = Vector3(0.2, 0.2, 0.2)
		_mm.mesh = box
		_mm.instance_count = COUNT
		var shades := [color, color.lightened(0.25), color.darkened(0.2), Color(0.98, 0.95, 0.9)]
		for i in range(COUNT):
			var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			_from.append(dir * rng.randf_range(1.6, 3.2))
			_spin.append(Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0)))
			_delay.append(rng.randf_range(0.0, 0.35))
			_mm.set_instance_color(i, shades[i % shades.size()])
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.6
		var node := MultiMeshInstance3D.new()
		node.multimesh = _mm
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		visible = false

	func play(length: float) -> void:
		_t = 0.0
		_length = maxf(length, 0.1)
		visible = true

	func is_playing() -> bool:
		return _t >= 0.0

	## target（ワールド）へ集める。終わったら隠れる。
	func advance(delta: float, target: Vector3) -> void:
		if _t < 0.0:
			return
		_t += delta
		global_position = target
		var span := _length * 0.65
		var done := true
		for i in range(COUNT):
			var u := clampf((_t - _delay[i] / 0.35 * (_length - span)) / span, 0.0, 1.0)
			if u < 1.0:
				done = false
			var k := u * u * u
			var at := _from[i] * (1.0 - k)
			var s := lerpf(1.0, 0.35, k)
			var rot := Basis.from_euler(_spin[i] * (1.0 - u))
			_mm.set_instance_transform(i, Transform3D(rot.scaled(Vector3(s, s, s)), at))
		if done:
			_t = -1.0
			visible = false


var _world: Node3D = null
var _hud: SkyGateHud = null
var _float: LandingFloat = null
## 着地台のまわりの観客船（座った観客・クラッカー・打ち上げ花火。sky_gate.md 第9章）
var _flotilla: SkyGateFlotilla = null
var _scenery: SkyFallScenery = null
var _venue_env: Environment = null
var _fx: SkyGateEffects = null
## player -> {"root", "parts", "rest"}
var _actors := {}
var _ghosts := {}
var _canopies := {}
var _gathers := {}
## player -> マフラー（SkyFallScarf）
var _scarves := {}
## player -> 真下の印（MeshInstance3D）
var _markers := {}
var _boards: Array[SkyGateBoard] = []
## 図解ルールカードの実演（ゲーム内の 3D をカードの絵にする）。
var _rule_demos: Array[SkyGateRuleDemo] = []
## ボードごと：{"role": "idle"/"column"（列の k 枚目。まだ当たっていない）/"hit"（当たって消えていく）/"leaving"（決着で消える）,
## "k", "d": 深さ, "offset": 横のずれ, "scale": Vector2, "q": 書いた問題文, "hit_at": 当たった見せ方の時計, "mode", "speed", "leave_at"}
var _board_state: Array[Dictionary] = []
var _built := false

## 監督なしで動かすとき（setup_solo）。
var _solo_state: QuizGameState = null
var _solo_game: SkyGateGame = null
var _solo_sky: SuddenDeathSkySet = null
var _solo_camera: Camera3D = null
var _solo_hud: SuddenDeathHud = null
var _solo_sun: DirectionalLight3D = null
var _solo_emotes := [0, 0]

## "idle", "rules", "countdown", "main", "round_land", "round_wait", "finish", "dance", "released"
var _phase := "idle"
var _t := 0.0
var _phase_t := 0.0
## 見せ方の時計の速さ（脱落のスロー。SkyGateImpact.wasted_scale）と、その速さで進む見せ方の時計（つき破る動きはこの時計で読む）。
var _slow := 1.0
var _scene_t := 0.0
## 脱落の色抜けの強さ（0〜1。SkyGateImpact.wasted_amount）と、色を戻すための本戦の環境のもとの値。
var _wasted := 0.0
var _wasted_cam := 0.0
var _env_base := {}
var _camera := {}
var _shot := ""
var _sea_y := 0.0
var _cues := {}
var _rules_at := INF
var _count_at := INF
## ROUND 2 からのカウントダウンの間：これから始めるラウンド（0 = なし。ルールはまだ着地のまま）。
var _pending_round := 0

# 本戦
var _round := 1
var _gate := 0
var _overtime := false
var _lean := [Vector2.ZERO, Vector2.ZERO]
var _lit := [-1, -1]
## 当たった（gate_impact）の中身と見せ方の時計の時刻、判定（gate_pass）の時刻。次に当たるまで残す。
var _impact := {}
var _impact_at := -INF
var _impact_sync := false
var _verdict_at := -INF
var _both_out_at := -INF
var _hidden := {1: false, 2: false}
## 体の中心の高さのずれ（落ちる点から、m）と、はね返って回る角度（SkyGateImpact）。爆散した人の分は判定のあとで 0 へ戻す。
var _lift := [0.0, 0.0]
var _tumble := [0.0, 0.0]
var _exploded := [false, false]
var _cam_dist := CAM_NEAR
var _cam_aim := Vector3.ZERO
var _cam_ready := false
## 見下ろしの画の寄り（0 = ボードと看板を収める、1 = 2人へ寄る。_push_weight）。
var _cam_push := 0.0
## ラグドール（player -> SkyGateLimp）。
var _limps := {}
var _banner := {}
var _banner_until := -INF
var _fall_distance := 0.0
## 空中の腹ばいの時計（スローで遅くなる）。
var _air_t := 0.0
var _shake_at := -INF
## 着地した布を置く床（着地台から見た置き場所）。
var _canopy_ground := {}

# 着地と決着
var _land_at := INF
## 着地の段取り（_plan_landing）：急降下・開く・引く・着地の時刻、初めの高さ、海の動かし方。
var _land_plan := {}
## 着地を始めたときの画（ここから寄せる）と、2人の体の中心。
var _land_from_cam := Transform3D.IDENTITY
var _land_from_fov := MAIN_FOV
var _land_start := {}
var _land_h := 0.0
var _landers: Array[int] = []
var _winner := 0
var _loser := 0
var _decided_by := ""
var _finish_at := INF
var _ghost_shown := false
var _landing := Vector3.ZERO
var _landed_canopy := {}
var _orbit := 0.0
var _next_round := 0

# ダンス
var _dances := {}
var _dance_slot := -1
var _dance_started := 0.0
var _dance_prev_mask := 0
var _dance_names: Array[String] = []
var _dance_t := 0.0
var _released := false
## 落ちている間の風切りの音（_update_wind_audio）
var _wind_audio: AudioStreamPlayer = null
var _wind_gain := 0.0


func title(english: bool) -> String:
	return "SKY GATE BREAK!" if english else "つきやぶれ！スカイゲート"


## 監督（W6）が水上機の乗り込み・降下を受け持つ。
func descent_mode() -> String:
	return "floatplane"


func extract_delay() -> float:
	return EXTRACT_DELAY


## 勝者は HUD の上に小さく出す（共通の大きな「P1 WIN!」はダンスを隠すので出さない）。
func shows_winner_banner() -> bool:
	return false


func preparation_steps() -> Array[Callable]:
	return [_build_world, _build_actors, _build_boards, _build_float, _build_flotilla, _build_rule_demos, _build_effects]


## 監督なしで動かす（デバッグの入口・テスト）。state は見た目（帽子・スキン・エモート・英語）だけに使う。
## ルールの出来事は呼ぶ側が on_event へ渡す（game.events）。カメラは venue_camera() を呼ぶ側が当てる。
## sun は海・雲・サングリントを照らす太陽（監督のときはステージの太陽 stage_env.directional_light）。
func setup_solo(state: QuizGameState, game: SkyGateGame, sky: SuddenDeathSkySet, camera: Camera3D, common_hud: SuddenDeathHud,
		sun: DirectionalLight3D = null) -> void:
	director = null
	_solo_state = state
	_solo_game = game
	_solo_sky = sky
	_solo_camera = camera
	_solo_hud = common_hud
	_solo_sun = sun


func set_solo_emote_keys(p1_mask: int, p2_mask: int) -> void:
	_solo_emotes = [p1_mask, p2_mask]


## 本戦の画の環境（監督がカメラに当てる）：ステージと同じ空・トーンマップで、霧だけ空撮向け（SkyFallScenery.venue_environment）。
func environment() -> Environment:
	if _venue_env == null:
		_venue_env = SkyFallScenery.venue_environment(_quality())
		_env_base = {"enabled": _venue_env.adjustment_enabled, "saturation": _venue_env.adjustment_saturation,
			"brightness": _venue_env.adjustment_brightness, "contrast": _venue_env.adjustment_contrast}
	return _venue_env


## 脱落の色抜け（w = 0〜1）を本戦の環境に当てる。0 ならもとの値へ戻す。
func _apply_wasted(w: float) -> void:
	_wasted = clampf(w, 0.0, 1.0)
	if _venue_env == null or _env_base.is_empty():
		return
	if _wasted <= 0.0001:
		_venue_env.adjustment_enabled = bool(_env_base.enabled)
		_venue_env.adjustment_saturation = float(_env_base.saturation)
		_venue_env.adjustment_brightness = float(_env_base.brightness)
		_venue_env.adjustment_contrast = float(_env_base.contrast)
		return
	_venue_env.adjustment_enabled = true
	_venue_env.adjustment_saturation = lerpf(float(_env_base.saturation), WASTED_SATURATION, _wasted)
	_venue_env.adjustment_brightness = lerpf(float(_env_base.brightness), float(_env_base.brightness) * WASTED_BRIGHTNESS, _wasted)
	_venue_env.adjustment_contrast = lerpf(float(_env_base.contrast), float(_env_base.contrast) * WASTED_CONTRAST, _wasted)


# ------------------------------------------------------------------ build (one step a frame)

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "SkyGateWorld"
	add_child(_world)
	_world.visible = false
	_hud = SkyGateHud.new()
	add_child(_hud)
	_hud.english = _english()


func _build_actors() -> void:
	var state := _state()
	for player: int in [1, 2]:
		_actors[player] = _make_doll(player, "P%dSkydiver" % player, state)
		var canopy := ParachuteCanopy.new()
		canopy.name = "P%dCanopy" % player
		_world.add_child(canopy)
		canopy.build(player == 1)
		canopy.visible = false
		_canopies[player] = canopy
		_mount_container(_actors[player].parts, canopy)
		_ghosts[player] = _make_doll(player, "P%dGhost" % player, state)
		_make_ghost_look(_ghosts[player].root as Node3D, player)
		var gather := Gather.new()
		gather.name = "P%dGather" % player
		_world.add_child(gather)
		gather.build(PLAYER_COLORS[player - 1], 4100 + player)
		_gathers[player] = gather
		_markers[player] = _make_marker(player)
		_limps[player] = SkyGateLimp.new(player)
		# 腹ばいの素材（drop_moves.glb）を先に読んでおく（本戦の頭で止まらないように）
		DropMotion.pose_box(_actors[player].parts, Vector2.ZERO, 0.0)


func _make_doll(player: int, node_name: String, state: QuizGameState) -> Dictionary:
	var root := Node3D.new()
	root.name = node_name
	_world.add_child(root)
	var hat := 0
	var skin := {}
	if state != null:
		hat = state.p1_hat if player == 1 else state.p2_hat
		skin = state.get_display_skin(player)
	var parts := EmoteBlockmanPreview.build_player_skeleton(player == 1, root, hat, 0, skin)
	parts["root"] = root
	var rest := {}
	for key: Variant in parts:
		if parts[key] is Node3D and key != "root":
			rest[key] = (parts[key] as Node3D).transform
	root.visible = false
	return {"root": root, "parts": parts, "rest": rest}


func _build_boards() -> void:
	for i in range(BOARD_POOL):
		var board := SkyGateBoard.new()
		board.name = "Gate_%d" % i
		_world.add_child(board)
		board.build(_quality())
		board.visible = false
		_boards.append(board)
		_board_state.append(_new_board_state())


func _build_float() -> void:
	_float = LandingFloat.new()
	_float.name = "LandingFloat"
	_world.add_child(_float)
	_float.build()


## 着地台のまわりの観客船（sky_gate.md 第9章）。着地すると観客がクラッカーを鳴らし、船から花火を上げる。
## 素材が読めなければ船なしで続ける（着地台とダンスはそのまま）。
func _build_flotilla() -> void:
	_flotilla = SkyGateFlotilla.new()
	_flotilla.name = "Flotilla"
	_world.add_child(_flotilla)
	if not _flotilla.build(_quality()):
		_flotilla.queue_free()
		_flotilla = null


## 図解ルールカードの 3 枚の絵：ゲームと同じボード・人形・効果・つき破る動きを、小さな別の世界で動かして映す（SkyGateRuleDemo）。
## 動いて選ぶ・破って抜ける（P1 の見た目）、はね返されて爆散（P2 の見た目）。
func _build_rule_demos() -> void:
	var textures: Array[Texture2D] = []
	var pixels := Vector2i(480, 360) if _quality() == GraphicsQuality.LOW else Vector2i(640, 480)
	for row: Array in [["steer", 1], ["burst", 1], ["bounce", 2]]:
		var demo := SkyGateRuleDemo.new()
		add_child(demo)
		demo.build(str(row[0]), int(row[1]), _state(), _quality(), pixels)
		_rule_demos.append(demo)
		textures.append(demo.get_texture())
	if _hud != null:
		_hud.set_rule_textures(textures)


## カードが出ている間（と、消えていく少しの間）だけ実演を描く。
func _set_rule_demos_playing(on: bool) -> void:
	for demo: SkyGateRuleDemo in _rule_demos:
		demo.set_playing(on)


func _build_effects() -> void:
	_build_scenery()
	_fx = SkyGateEffects.new()
	_fx.name = "SkyGateFx"
	_world.add_child(_fx)
	_fx.build(_quality())
	# 効果の座標はこのノードのローカルで、描くかどうかはノードのまわり ±60 m の箱で決まる：落ちる点に置く（世界の原点に置くと、
	# 見下ろしの画では箱が画の外になり、人形の爆散が描かれない）
	_fx.global_position = _fall_center()
	_built = true


## 背中のコンテナ（chute.glb の Container）を人形の背骨に付ける（ParachutePresenter と同じ）。
func _mount_container(parts: Dictionary, canopy: ParachuteCanopy) -> void:
	var spine := parts.get("spine") as Node3D
	var container := canopy.container_node()
	if spine == null or container == null:
		return
	spine.add_child(container)
	container.position = Vector3(0.0, 0.22, -0.12)


## 真下の印：体の中心の真下の、ボードの紙の上の輪と点（自分の色）。遠近で体と真下のパネルがずれて見えても、どこへ落ちるかが分かる。
func _make_marker(player: int) -> MeshInstance3D:
	var color := PLAYER_COLORS[player - 1]
	var ring := TorusMesh.new()
	ring.inner_radius = MARKER_RADIUS * 0.72
	ring.outer_radius = MARKER_RADIUS
	ring.rings = 24
	ring.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 半透明（ユーザーの指示：選択肢の文字が見えにくくならないように）
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.lightened(0.15), MARKER_ALPHA)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = 3
	ring.material = material
	var node := MeshInstance3D.new()
	node.name = "P%dMarker" % player
	node.mesh = ring
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dot := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = MARKER_RADIUS * 0.28
	disc.bottom_radius = MARKER_RADIUS * 0.28
	disc.height = 0.02
	disc.radial_segments = 16
	disc.rings = 1
	disc.material = material
	dot.mesh = disc
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(dot)
	node.scale = Vector3(1.0, 0.15, 1.0)
	node.visible = false
	_world.add_child(node)
	return node


## 幽霊の姿（どの場面でも GOSTRIDER の魂と同じ：半透明・プレイヤー色の縁光り・昇る光の粒）。
func _make_ghost_look(root: Node3D, player: int) -> void:
	PlayerController.apply_ghost_soul_look(root, player)


# ------------------------------------------------------------------ the sky scenery (W7：SkyFallScenery とマフラー)

## 空の演出（assets/sudden_death/sky_fx/README.md の使い方どおり）：落ちる点に置き、画面の上の向き（前＝+Z）を渡す。
## 空のセットの海を空撮向けに合わせ（描く順・太陽）、太陽はステージの太陽。2 人にマフラーと手足の風の筋。
func _build_scenery() -> void:
	_scenery = SkyFallScenery.new()
	_scenery.name = "SkyFallScenery"
	_world.add_child(_scenery)
	_scenery.global_position = _fall_center()
	_scenery.build(_quality(), _sea_point(round_sea_depth(0.0)), FORWARD)
	var sky := _sky()
	var sun := _sun_light()
	if sky != null and sky.ocean != null:
		_scenery.configure_sea(sky.ocean, sun)
	if sun != null:
		_scenery.set_sun(sun)
	for player: int in [1, 2]:
		var parts: Dictionary = _actors[player].parts
		var scarf := SkyFallScarf.new()
		scarf.name = "P%dScarf" % player
		_world.add_child(scarf)
		# スローに合わせるので、見せ方の時計で進める
		scarf.auto_advance = false
		scarf.attach_doll(parts, player)
		_scarves[player] = scarf
		_scenery.track_body(player, parts)


## 海面の点（落ちる点の真下、深さ m）。
func _sea_point(depth: float) -> Vector3:
	return _fall_center() + Vector3.DOWN * depth


## 落ちた分だけ雲と景色を流す。progress はラウンドの落下の進み（0〜1）、wind は風切りの強さ（0〜1.4）。
## 海の高さ（_sea_y）を先に決めてから呼ぶ（島・薄い雲・影・海鳥が海と一緒に動く）。
func _scenery_advance(distance: float, delta: float, progress: float, wind: float) -> void:
	if _scenery == null:
		return
	_scenery.set_overtime(_overtime)
	_scenery.set_progress(progress)
	_scenery.set_wind(wind)
	_scenery.set_landing_point(Vector3(_fall_center().x, _sea_y, _fall_center().z))
	_scenery.advance(distance, delta)


## マフラーを進める（air は体に対する空気の流れ）。体が見えない人（ブロックにばらけた）のマフラーは隠す。
func _advance_scarves(delta: float, air: Vector3, wind: float) -> void:
	for player: int in [1, 2]:
		var scarf := _scarves.get(player) as SkyFallScarf
		if scarf == null:
			continue
		var shown: bool = (_actors[player].root as Node3D).visible and not _hidden[player]
		scarf.visible = shown
		if not shown:
			continue
		scarf.air_velocity = air
		scarf.wind = wind
		scarf.time_scale = _slow
		scarf.advance(delta)


## 体がブロックにばらけた（隠れた）／戻った。隠れている間は手足の風の筋とマフラーも出さない。
func _set_body_hidden(player: int, hidden: bool) -> void:
	_hidden[player] = hidden
	if _scenery == null:
		return
	if hidden:
		_scenery.untrack_body(player)
	else:
		_scenery.track_body(player, _actors[player].parts)


func _scenery_gate(board: Node3D) -> void:
	if _scenery != null:
		_scenery.gate_emerge(board)


## 速さの線はカメラの子に置かれる。本戦の間だけ付け、着地の画・片づけでは外す。
func _scenery_camera(on := true) -> void:
	if _scenery != null:
		_scenery.set_camera(_main_camera() if on else null)


## 空のセットの巡航の雲（StagingClouds）は本戦では隠す（雲は SkyFallScenery の体積雲だけ）。
func _show_cruise_clouds(on: bool) -> void:
	var sky := _sky()
	if sky != null and sky.clouds != null:
		sky.clouds.visible = on


# ------------------------------------------------------------------ the venue

func set_venue_active(active: bool) -> void:
	if _world != null:
		_world.visible = active
	if not active:
		_stop_wind_audio()
		_apply_wasted(0.0)
		_restore_sea()
		_scenery_camera(false)
		_show_cruise_clouds(true)
		if _hud != null:
			_hud.hide_all()
		if _float != null:
			_float.set_tally(false)
		if _flotilla != null:
			_flotilla.reset_show()


## 降下が終わった：4 枚の列の引きの画（RULES_DELAY 秒）から図解ルールカードへ（2人はその間も落ち続ける）。
func begin_venue() -> void:
	_phase = "rules"
	_t = 0.0
	_phase_t = 0.0
	_rules_at = 0.0
	_slow = 1.0
	_cues.clear()
	_pending_round = 0
	_world.visible = true
	_round = 1
	_gate = 0
	_overtime = false
	_winner = 0
	_loser = 0
	_decided_by = ""
	_released = false
	_dance_slot = -1
	_land_at = INF
	_finish_at = INF
	_ghost_shown = false
	_banner = {}
	_canopy_ground.clear()
	_landed_canopy.clear()
	if _flotilla != null:
		_flotilla.reset_show()
	_reset_sky(1)
	if _state() != null:
		_state().sudden_death_preparing_panel = ""


## 2人を空へ戻す（ラウンドの頭。降下から渡されたところ）：腹ばい・パラシュートをたたむ・ボードを片づける。
## 海は今の高さ（降下で水上機の場面が置いた高さ）から、ラウンドの頭の深さへ SEA_RATE で寄せる（飛ばない）。
func _reset_sky(round_number: int) -> void:
	_round = round_number
	var sky := _sky()
	if sky != null and sky.ocean != null:
		_sea_y = sky.ocean.global_position.y
	else:
		_sea_y = _fall_center().y - round_sea_depth(0.0)
	_scenery_camera(true)
	_show_cruise_clouds(false)
	if _scenery != null:
		_scenery.visible = true
		_scenery.set_progress(0.0)
	for player: int in [1, 2]:
		var actor: Dictionary = _actors[player]
		(actor.root as Node3D).visible = true
		var pelvis := actor.parts.get("pelvis") as Node3D
		if pelvis != null:
			pelvis.visible = true
		var canopy := _canopies[player] as ParachuteCanopy
		canopy.set_stage(0)
		canopy.collapse = 0.0
		# 着地で床へ落とした布を背中へ戻す（ParachuteCanopy に戻す口が無いので、床へ落とす印を消す）
		canopy.set("_to_ground", false)
		canopy.snap()
		canopy.visible = false
		(_ghosts[player].root as Node3D).visible = false
		_set_body_hidden(player, false)
		_lean[player - 1] = Vector2.ZERO
		_lit[player - 1] = -1
		_lift[player - 1] = 0.0
		_tumble[player - 1] = 0.0
		_exploded[player - 1] = false
	# ボードは _update_boards がルールの列（4 枚とも問題を書いて）から並べ直す
	for i in range(_boards.size()):
		_boards[i].reset()
		_boards[i].visible = false
		_board_state[i] = _new_board_state()
	_landers.clear()
	_land_plan = {}
	# 降下から渡された直後は、監督が 1.6 秒かけてこの画（列の引き）へ寄せる（ここで画を決め直してよい）
	_cam_ready = false
	for limp: Variant in _limps.values():
		(limp as SkyGateLimp).reset()
	_impact = {}
	_impact_at = -INF
	_verdict_at = -INF
	_apply_wasted(0.0)
	_wasted_cam = 0.0


func update_venue(delta: float) -> void:
	if not _built or _phase == "idle":
		return
	_t += delta
	_slow = _time_scale_now()
	var sd := delta * _slow
	_scene_t += sd
	_sync_impact_clock()
	_apply_wasted(_wasted_now())
	_air_t += sd
	_phase_t += delta
	match _phase:
		"rules", "countdown", "main":
			if _phase == "countdown":
				_update_countdown()
			_update_air(delta, sd)
		"round_land", "round_wait":
			_update_landing(delta, sd)
		"finish":
			_update_finish(delta, sd)
		"dance", "released":
			_update_sea(delta)
			_scenery_advance(0.0, delta, 1.0, 0.0)
			_advance_scarves(delta, SCARF_AIR_GROUND, 0.2)
	if _flotilla != null:
		_flotilla.camera = _main_camera()
		_flotilla.advance(sd)
	_update_hud()
	_update_wind_audio(delta)


func venue_camera() -> Dictionary:
	return _camera


## ルールカードが画面に出て、閉じるのを待っている（列の引きの画を RULES_DELAY 秒見せたあと、_update_hud と同じ条件）。
## スマホのタップの層（tap_to_confirm_overlay）と TouchControls の「OK」は、これが true の間だけ出る。
func rules_waiting() -> bool:
	return _phase == "rules" and _t - _rules_at >= RULES_DELAY


func confirm_rules() -> bool:
	if _phase != "rules" or _t - _rules_at < RULES_DELAY + RULE_HOLD:
		return false
	_phase = "countdown"
	_count_at = _t
	return true


## 監督の Space で飛ばす口：ROUND の着地・勝者の着地の演出の間だけ飛ばせる（ルールの時計で進む本戦と判定は飛ばさない）。
func can_skip() -> bool:
	if _phase == "round_land":
		return true
	return _phase == "finish" and _land_clock() >= 0.0 and not finale_done()


## 着地の演出を飛ばして、着地台に立った所（ROUND のあとは「ROUND n」を出し終えた所、決着は踊りの前）へ。白い閃光で隠す。
func skip_presentation() -> bool:
	if not can_skip():
		return false
	if _land_plan.is_empty():
		_plan_landing()
	var after := L_ROUND_DONE_AFTER if _phase == "round_land" else L_FINISH_DONE_AFTER
	_land_at = _t - (_land_time() + after)
	_land_h = 0.0
	var hud := _common_hud()
	if hud != null and hud.has_method("flash"):
		hud.call("flash", 0.8, 0.3)
	if _phase == "round_land" and _cue("round_banner_%d" % _next_round, true):
		var sub := "both reached the ground - next round" if _english() else "2人とも地上へ → 次のラウンド"
		_show_banner("ROUND %d" % _next_round, sub, PLAYER_COLORS[0].darkened(0.1), INF)
	return true


func finale_done() -> bool:
	return _phase == "finish" and _land_clock() >= _land_time() + L_FINISH_DONE_AFTER


func winner() -> int:
	return _winner


## 2人とも着地台に着いて「ROUND n」を見せ終えた（監督が迎えの水上機を呼ぶ）。
func round_cleared() -> bool:
	return _phase == "round_wait"


## 降下が終わって次のラウンドを始める（監督。監督なしではデバッグの入口が呼ぶ）。ROUND 1 と同じく、カウントダウン
## 「3・2・1・GO」のあとでルールの時計を始める（2026-10-20、ユーザーの指示）。カウントダウンの前に「ROUND n」の見出し
## （むずかしさ）を ROUND_INTRO 秒見せる。その間は次のラウンドの 4 枚の列の引きの画で、2人は次のラウンドの頭の位置で落ち続ける。
func begin_round(round_number: int) -> void:
	var game := _game()
	if game == null or game.phase != "landing":
		return
	if round_number != game.current_round + 1:
		push_warning("[SkyGate] begin_round(%d)：ルールの次のラウンドは %d" % [round_number, game.current_round + 1])
	var next := game.current_round + 1
	game.place_for_next_round()
	_reset_sky(next)
	_pending_round = next
	_phase = "countdown"
	_phase_t = 0.0
	_count_at = _t + ROUND_INTRO
	_slow = 1.0
	if _float != null:
		_float.set_tally(false)
	if _flotilla != null:
		_flotilla.reset_show()
	if _cue("round_intro_%d" % next, true):
		_show_round_banner(next, ROUND_INTRO - 0.3)


## 降下が終わったときに2人が落ちている位置（腹ばいの体の中心。basis の +Z が頭＝前、+Y が背中）。降下のカメラがここへつながる。
func sky_spawn(player: int) -> Transform3D:
	var game := _game()
	var next := 1
	if game != null:
		next = game.current_round + 1 if game.phase == "landing" else maxi(game.current_round, 1)
	var p := SkyGateGame.spawn_point(player, _round_scale(next))
	return Transform3D(Basis.IDENTITY, _air_point(p))


## W6（監督）：ラウンドのあとの迎えと勝者の迎えで、水上機を着地台に着けるための口。
func landing_float() -> LandingFloat:
	return _float


## 降りた人形の腰の位置（ワールド）。迎えで本物のアバターに替えるときの立ち位置。
func lander_point(player: int) -> Vector3:
	if not _actors.has(player):
		return _float.land_point() if _float != null else Vector3.ZERO
	var pelvis := _actors[player].parts.get("pelvis") as Node3D
	return pelvis.global_position if pelvis != null else (_actors[player].root as Node3D).global_position


## 着地台に立っている人形を隠す（監督が本物のアバターを出すとき）。
func set_landers_hidden(hidden: bool) -> void:
	for player: int in [1, 2]:
		if _actors.has(player):
			(_actors[player].root as Node3D).visible = not hidden


## 空中の落ちる点（2人の腹ばいのまわり）。監督の降下の行き先。
func fall_center() -> Vector3:
	return _fall_center()


func on_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	match kind:
		"round_start":
			_round = int(event.get("round", 1))
			# ふつうはカウントダウンの前（begin_round）に見せてある
			if _round > 1 and _cue("round_intro_%d" % _round, true):
				_show_round_banner(_round, 1.6)
		"gate":
			_on_gate(event)
		"gate_impact":
			_on_gate_impact(event)
		"gate_pass":
			_on_gate_pass(event)
		"both_out":
			_both_out_at = _t
		"revive":
			_revive()
		"round_clear":
			_begin_round_land()
		"overtime":
			_overtime = true
			var text := "OVERTIME!" if _english() else "延長戦！"
			var sub := "no landing - faster and faster (fastest wins at the end)" if _english() \
				else "着地せずに続く・だんだん速く（最後は早い者勝ち）"
			_show_banner(text, sub, Color(0.91, 0.28, 0.28), 2.2)
			AudioManager.play_sfx(&"sg_overtime")
		"decided":
			_begin_finish(int(event.get("winner", 1)), str(event.get("by", "out")))


## 次のボード（列の今のボード）。ボードは列のまま _update_boards が並べている。
func _on_gate(event: Dictionary) -> void:
	_gate = int(event.get("index", 0))
	_round = int(event.get("round", _round))
	_overtime = bool(event.get("overtime", false))
	for player: int in [1, 2]:
		_lit[player - 1] = -1
	var game := _game()
	if game != null:
		_update_boards(game, 0.0, 0.0)
	var cur := _current_board()
	if cur >= 0:
		_scenery_gate(_boards[cur])


## 当たった（skygate_impact.md）：位置はもう動かない。ここから SkyGateImpact の時刻（見せ方の時計）で、正解の人は紙を破って抜け、
## まちがいの人は破れない紙にはね返され、強いスローで爆散する（_update_impact）。判定（アウト・決着）はまだ出さない。
func _on_gate_impact(event: Dictionary) -> void:
	_impact = event
	_impact_at = _scene_t
	_impact_sync = true
	_verdict_at = -INF
	var results: Array = event.get("results", [])
	var mode := int(event.get("mode", SkyGateImpact.mode_of(results)))
	_impact["mode"] = mode
	var cur := _board_for(int(event.get("index", -1)))
	if cur < 0:
		return
	var st: Dictionary = _board_state[cur]
	st.role = "hit"
	st.hit_at = _scene_t
	st.mode = mode
	st.speed = float(event.get("speed", SkyGateGame.FALL_SPEEDS[0]))
	# まちがえた人は紙に当たった瞬間から力が抜ける（ラグドール）。画は見下ろしのまま（_air_camera）
	for player: int in [1, 2]:
		var limp := _limps.get(player) as SkyGateLimp
		if limp != null:
			if str(results[player - 1]) == "boom":
				limp.start()
			else:
				limp.reset()
	# ボードの高さを一気に通る
	AudioManager.play_sfx(&"sg_gate_rush")


## 当たった時刻をルールの時計に合わせる：知らせはフレームの途中の刻みで出るので、見せ方の時計の上の時刻を
## 「今 − ルールの impact の段階の秒（見せ方の時計の秒に直す）」にする（直さないと最初のフレームで最大 1 フレームぶん先へ飛ぶ）。
func _sync_impact_clock() -> void:
	if not _impact_sync:
		return
	var game := _game()
	if game != null and game.phase == "impact" and int(_impact.get("index", -1)) == game.gate_index:
		var at := _scene_t - SkyGateImpact.wasted_scene_time(game.phase_clock(), _impact_mode())
		_impact_at = at
		var hit := _hit_board(int(_impact.get("index", -1)))
		if hit >= 0:
			_board_state[hit].hit_at = at
	_impact_sync = false


## 当たってからの見せ方の時計の秒（当たっていなければ負）。
func _impact_clock() -> float:
	return _scene_t - _impact_at if not _impact.is_empty() else -INF


func _impact_mode() -> int:
	return int(_impact.get("mode", SkyGateImpact.mode_of(_impact.get("results", []))))


## 判定（つき破る動きを見せ終えた）：音。アウト・決着・2人ともアウトは続く出来事が知らせる。
func _on_gate_pass(event: Dictionary) -> void:
	if _impact.is_empty() or int(_impact.get("index", -1)) != int(event.get("index", -2)):
		# 当たった知らせが無かった（古い呼び方）：ここで動きを始める
		_on_gate_impact(event)
		_impact_at = _scene_t - SkyGateImpact.BOOM_JUDGE_AT
	_verdict_at = _t
	var hit := _hit_board(int(event.get("index", -1)))
	if hit >= 0:
		_lit_off(hit)
	var results: Array = event.get("results", [])
	if results.has("boom"):
		AudioManager.play_sfx(&"door_wrong", -6.0)
	else:
		AudioManager.play_sfx(&"sg_safe")


## 当たってからの「つき破る」動き：体の高さ・回転・ラグドール、紙のへこみと張りつめ、破れる・はね返る・爆散のきっかけ。
## 時刻は見せ方の時計（まちがいがいれば強いスローで遅くなる）。ボードの高さと消え方は _board_motion。
func _update_impact(delta := 0.0) -> void:
	if _impact.is_empty():
		return
	var it := _impact_clock()
	var results: Array = _impact.get("results", [])
	var panels: Array = _impact.get("panels", [])
	var locals: Array = _impact.get("local", [])
	var mode := _impact_mode()
	var speed := float(_impact.get("speed", SkyGateGame.FALL_SPEEDS[0]))
	var hit := _hit_board(int(_impact.get("index", -1)))
	var board: SkyGateBoard = _boards[hit] if hit >= 0 and float(_board_state[hit].hit_at) == _impact_at else null
	var key := "%d_%d" % [_round, _gate]
	var sd := delta * _slow
	for player: int in [1, 2]:
		var slot := player - 1
		var burst := str(results[slot]) == "burst"
		if not burst and SkyGateImpact.exploded(it):
			# 爆散したあと：ばらけたブロックの中心（2人ともアウトなら復活する所）を落ちる点の高さへ戻す
			var peak := SkyGateImpact.body_height(false, mode, SkyGateImpact.EXPLODE_AT)
			_lift[slot] = peak * (1.0 - smoothstep(0.15, 1.0, it - SkyGateImpact.EXPLODE_AT))
		else:
			_lift[slot] = SkyGateImpact.body_height(burst, mode, it)
		# ラグドール：体の上下の速さ（式の差分）で手足と首を振り回す
		var limp := _limps.get(player) as SkyGateLimp
		if limp != null and limp.is_active():
			if SkyGateImpact.limp(it):
				var h := 1.0 / 120.0
				var v := (SkyGateImpact.body_height(false, mode, it) - SkyGateImpact.body_height(false, mode, it - h)) / h
				limp.step(sd, v)
			elif SkyGateImpact.exploded(it):
				limp.reset()
		# 爆散したあとは体が見えないので、復活したときはまっすぐな腹ばいに戻っている
		_tumble[slot] = SkyGateImpact.tumble(it) if not burst and not SkyGateImpact.exploded(it) else 0.0
		var panel := int(panels[slot]) if slot < panels.size() else -1
		if board == null or panel < 0:
			continue
		var local: Vector2 = locals[slot] if slot < locals.size() else Vector2.ZERO
		var at := board.board_point(local)
		var through := mode == SkyGateImpact.ALL_BURST
		board.set_dent(panel, slot, at, SkyGateImpact.through_dent(it, speed) if through else SkyGateImpact.dent(burst, it))
		if burst:
			var torn := it >= SkyGateImpact.through_tear_time(speed) if through else SkyGateImpact.torn(it)
			if torn and _cue("tear_%s_%d" % [key, player], true):
				board.burst(panel, at)
				AudioManager.play_sfx(&"sg_tear", 0.0, _wasted_pitch())
				AudioManager.play_sfx(&"door_correct", -6.0)
		else:
			var tense := smoothstep(0.04, 0.26, it) * (1.0 - smoothstep(SkyGateImpact.EXPLODE_AT, SkyGateImpact.EXPLODE_AT + 0.4, it))
			board.set_strain(panel, tense)
			if it >= SkyGateImpact.STRETCH_END and _cue("bounce_%s_%d" % [key, player], true):
				board.bounce(panel, at)
				# 破れない紙にボヨンとはね返される（体が当たる鈍い音を少し重ねる。スローの間は音程を下げる）
				AudioManager.play_sfx(&"sg_bounce", 0.0, _wasted_pitch())
				AudioManager.play_sfx(&"wall_crash", -8.0, 0.8 * _wasted_pitch())
			if SkyGateImpact.exploded(it) and _cue("explode_%s_%d" % [key, player], true):
				_explode(player)


## まちがい：はね返された上で、体がブロックにばらけて爆散する（漫画の爆発。血や怖さはない）。スローの中で起きるので音程を下げる。
func _explode(player: int) -> void:
	var center := _body_center(player)
	_exploded[player - 1] = true
	if _fx != null:
		_fx.player_burst(_actors[player].parts, center)
		_fx.puffs(_fx.to_local(center), 1.25, 12, true, 0.6)
		_fx.stars(_fx.to_local(center), 8, 3.4)
	_set_body_hidden(player, true)
	AudioManager.play_sfx(&"barrier_explosion", -4.0, _wasted_pitch())
	AudioManager.play_sfx(&"body_burst", -6.0, _wasted_pitch())
	_shake()


## 脱落のスローの間の効果音の音程（色抜けの強さに合わせて WASTED_PITCH まで下げる）。
func _wasted_pitch() -> float:
	return lerpf(1.0, WASTED_PITCH, _wasted)


## 2人とも同じゲートでアウト → その場で復活（ばらけたブロックが体に戻る）。
func _revive() -> void:
	for player: int in [1, 2]:
		# はね上がった高さはもう落ちる点へ戻してある（_update_impact）
		_exploded[player - 1] = false
		_set_body_hidden(player, false)
		var pelvis := _actors[player].parts.get("pelvis") as Node3D
		if pelvis != null:
			pelvis.visible = true
		if _fx != null:
			_fx.flash(_fx.to_local(_body_center(player)), 1.4, 0.3, Color(1, 1, 1))
			_fx.stars(_fx.to_local(_body_center(player)), 6, 3.0)
	AudioManager.play_sfx(&"sg_revive")


# ------------------------------------------------------------------ air (rules, countdown, main)

func _update_countdown() -> void:
	var c := _t - _count_at
	var text := ""
	if c < 0.0:
		# ROUND 2 から：「ROUND n」の見出しを見せている間
		text = ""
	elif c < COUNT_STEP:
		text = "3"
	elif c < COUNT_STEP * 2.0:
		text = "2"
	elif c < COUNT_STEP * 3.0:
		text = "1"
	elif c < COUNT_STEP * 3.0 + 0.8:
		text = "GO!"
	var hud := _common_hud()
	if hud != null:
		hud.set_countdown(text)
	# きっかけはラウンドごと（ROUND 2 からもカウントダウンをするので）
	var round_key := maxi(_pending_round, 1)
	if text != "" and _cue("count_%d_%s" % [round_key, text], true):
		AudioManager.play_sfx(&"countdown_go" if text == "GO!" else &"countdown_beep", -4.0)
	if c >= COUNT_STEP * 3.0 and _cue("game_start_%d" % round_key, true):
		_start_rules()
		_phase = "main"
		_phase_t = 0.0
		# ROUND 1 の GO で本戦の曲を頭から（docs/bgm_renewal.md）。ROUND 2 からは流れたままなので何もしない
		AudioManager.set_music_track(AudioManager.MUSIC_TRACK_SUDDEN_DEATH_MAIN)


## 落ちている間の風切り（ループ）：ルールカードの間は弱く、本戦は _wind（ゲートが近いと弱く、つき破る瞬間に強く）、
## 着地でパラシュートが開いたら弱く、着地したら消す。スローの間は音程を下げる。ループは乱れた所から始める。
func _update_wind_audio(delta: float) -> void:
	var amount := 0.0
	match _phase:
		"rules":
			amount = WIND_RULES
		"countdown", "main":
			amount = _wind(_game())
		"round_land", "finish":
			var f := _land_clock()
			if f < 0.0 or _land_plan.is_empty():
				amount = _wind(_game())
			elif f < float(_land_plan.open):
				amount = 1.15
			elif f < float(_land_plan.land):
				amount = WIND_CANOPY
	if AudioManager.menu_sfx_muted or _world == null or not _world.visible:
		amount = 0.0
	_wind_gain = lerpf(_wind_gain, db_to_linear(WIND_DB) * amount, 1.0 - exp(-delta * 4.0))
	if _wind_gain < 0.002:
		if _wind_audio != null and _wind_audio.playing:
			_wind_audio.stop()
		return
	if _wind_audio == null:
		_wind_audio = AudioStreamPlayer.new()
		_wind_audio.name = "FreefallWind"
		_wind_audio.bus = "SFX"
		if ResourceLoader.exists(WIND_LOOP):
			var stream := (load(WIND_LOOP) as AudioStreamOggVorbis)
			if stream != null:
				stream = stream.duplicate() as AudioStreamOggVorbis
				stream.loop = true
				_wind_audio.stream = stream
		add_child(_wind_audio)
	if _wind_audio.stream == null:
		return
	_wind_audio.volume_db = linear_to_db(_wind_gain)
	_wind_audio.pitch_scale = lerpf(0.72, 1.0, clampf(_slow, 0.0, 1.0)) * lerpf(0.94, 1.05, clampf(amount, 0.0, 1.4) / 1.4)
	if not _wind_audio.playing:
		_wind_audio.play(randf() * _wind_audio.stream.get_length())


func _stop_wind_audio() -> void:
	_wind_gain = 0.0
	if _wind_audio != null:
		_wind_audio.stop()


## 落ちている間の風切りの今の音量（線形。テストの記録用）。
func wind_audio_gain() -> float:
	return _wind_gain if _wind_audio != null and _wind_audio.playing else 0.0


## カウントダウンが終わった：ルールの時計を始める（ROUND 1 の1枚目。ROUND 2 からは次のラウンドの1枚目）。
func _start_rules() -> void:
	if _pending_round > 0:
		_pending_round = 0
		var game := _game()
		if game != null:
			game.begin_round()
		return
	if director != null and _state() != null:
		_state().start_sudden_death_countdown()
	elif _solo_game != null and _solo_game.waiting_for_start:
		_solo_game.start()


func _update_air(delta: float, sd: float) -> void:
	var game := _game()
	_update_boards(game, delta, sd)
	_update_impact(delta)
	for player: int in [1, 2]:
		_pose_skydiver(player, game, delta)
	_update_gathers(game, sd)
	if _fx != null:
		_fx.global_position = _fall_center()
		_fx.advance(sd)
	_fall_distance += FALL_SPEED * sd
	_update_sea_air(game, delta)
	_scenery_advance(FALL_SPEED * sd, sd, _round_progress(game), _wind(game))
	_advance_scarves(delta, SCARF_AIR_FALL, _wind(game))
	_air_camera(game, delta)


## ボードを列のとおりに並べる（どのボードも消えたり飛んだりせずに動く）：
## まだ当たっていない列のボード（column）は、ルールの board_depth(k) の深さと board_offset() の横のずれ（列は1つとして揺れる）。
## 列の今のボードから board_count() までの k に空いたボードを当てて問題を書く（始まる前に問題が差し替わったら書き直す）。
## 当たったボード（hit）は SkyGateImpact の高さで動き、ゲーム中の問題の壁のようにだんだん透明になって消える（通り抜けたら
## 体の上を通りすぎながら）。決着したら・本戦が終わったら、残りのボードは BOARD_LEAVE_TIME 秒で消える（leaving）。
func _update_boards(game: SkyGateGame, delta: float, sd: float) -> void:
	var first := 0
	var last := 0
	var column_on := game != null and _phase in ["rules", "countdown", "main"] and not game.finished
	if column_on:
		if game.gate_index >= 0:
			first = game.gate_index if game.phase == "gate" else game.gate_index + 1
		last = game.board_count()
	var scale := Vector2.ONE
	if game != null:
		scale = _round_scale(SkyGateGame.SMALL_FROM_ROUND if game.overtime else game.column_round)
	# 列から外れたボードは消す（決着・本戦の終わり）。今のボードより前のもの（当たった知らせを待つ）は残す
	for i in range(_board_state.size()):
		var st: Dictionary = _board_state[i]
		if str(st.role) == "column" and (not column_on or int(st.k) >= last):
			st.role = "leaving"
			st.leave_at = _t
	for k in range(first, last):
		if _board_for(k) >= 0:
			continue
		var spare := _board_with("idle")
		if spare < 0:
			break
		_board_state[spare] = _new_board_state("column", k, scale)
		_boards[spare].reset()
		_write_question(spare, game.column_quiz(k))
	for i in range(_boards.size()):
		var st: Dictionary = _board_state[i]
		match str(st.role):
			"column":
				var quiz := game.column_quiz(int(st.k)) if game != null else null
				if quiz != null and quiz.q != str(st.q):
					_write_question(i, quiz)
				if game != null:
					st.d = game.board_depth(int(st.k))
					st.offset = game.board_offset()
				st.scale = scale
				_boards[i].visible = float(st.d) < _sea_depth_now() - BOARD_SEA_CLEAR
			"hit":
				_board_motion(i)
				if _boards[i].fade() <= 0.001:
					_retire_board(i)
			"leaving":
				var alpha := 1.0 - smoothstep(0.0, BOARD_LEAVE_TIME, _t - float(st.leave_at))
				_boards[i].set_fade(minf(alpha, _boards[i].fade()))
				if alpha <= 0.001:
					_retire_board(i)
		if str(_board_state[i].role) != "idle":
			_place_board(i)
			_boards[i].advance(sd)
	# 真下のパネルを自分の色の光る枠で
	var cur := _current_board()
	if cur >= 0 and game != null and game.phase == "gate":
		for player: int in [1, 2]:
			var panel := game.under[player - 1]
			if panel != int(_lit[player - 1]):
				if int(_lit[player - 1]) >= 0:
					_boards[cur].set_highlight(int(_lit[player - 1]), player, false)
				if panel >= 0:
					_boards[cur].set_highlight(panel, player, true)
				_lit[player - 1] = panel
	_update_markers(game, cur)


func _update_markers(game: SkyGateGame, cur: int) -> void:
	for player: int in [1, 2]:
		var marker := _markers.get(player) as MeshInstance3D
		if marker == null:
			continue
		var show: bool = cur >= 0 and game != null and game.phase == "gate" and float(_board_state[cur].d) < MARKER_RANGE and not _hidden[player]
		marker.visible = show
		if show:
			var board := _boards[cur]
			marker.global_position = board.board_point(game.local_point(player - 1)) + Vector3.UP * 0.07


## 当たったあとのボード：紙の面の高さと消え方（見せ方の時計で読む）。全員が正解なら列の速さのまま上へ抜けていく
## （減速せずに突破）。まちがいがいれば SkyGateImpact のたわみ・はね返し・運び去り（スローは時計の側で掛かっている）。
func _board_motion(i: int) -> void:
	var st: Dictionary = _board_state[i]
	var it := _scene_t - float(st.hit_at)
	var mode := int(st.mode)
	if mode == SkyGateImpact.ALL_BURST:
		st.d = SkyGateImpact.CONTACT - float(st.speed) * it
		_boards[i].set_fade(SkyGateImpact.through_alpha(it, float(st.speed)))
		return
	st.d = -SkyGateImpact.board_height(mode, it, false)
	_boards[i].set_fade(SkyGateImpact.board_alpha(mode, it))


func _new_board_state(role := "idle", k := -1, scale := Vector2.ONE) -> Dictionary:
	return {"role": role, "k": k, "d": SkyGateGame.FIRST_DEPTH, "offset": 0.0, "scale": scale, "side": 0.0, "bank": 0.0,
		"q": "", "hit_at": -INF, "mode": SkyGateImpact.ALL_BURST, "speed": SkyGateGame.FALL_SPEEDS[0], "leave_at": -INF}


func _write_question(i: int, quiz: QuizItem) -> void:
	var text := ""
	var choices: Array = []
	if quiz != null:
		text = quiz.q
		for choice: String in quiz.c:
			choices.append(choice)
	_boards[i].set_question(text, choices)
	_board_state[i].q = text


func _retire_board(i: int) -> void:
	_board_state[i].role = "idle"
	_board_state[i].k = -1
	_boards[i].visible = false


func _place_board(i: int) -> void:
	var st: Dictionary = _board_state[i]
	var s: Vector2 = st.scale
	var basis := Basis(FORWARD, float(st.bank)) * BOARD_TURN * Basis.from_scale(Vector3(s.x, (s.x + s.y) * 0.5, s.y))
	var origin := _fall_center() + RIGHT * (float(st.offset) + float(st.side)) + Vector3.DOWN * float(st.d)
	_boards[i].global_transform = Transform3D(basis, origin)


func _board_with(role: String) -> int:
	for i in range(_board_state.size()):
		if str(_board_state[i].role) == role:
			return i
	return -1


## 列の k 枚目を受け持つ、まだ当たっていないボード（無ければ -1）。
func _board_for(k: int) -> int:
	for i in range(_board_state.size()):
		if str(_board_state[i].role) == "column" and int(_board_state[i].k) == k:
			return i
	return -1


## 列の k 枚目の、当たって消えていくボード（無ければ -1）。
func _hit_board(k: int) -> int:
	for i in range(_board_state.size()):
		if str(_board_state[i].role) == "hit" and int(_board_state[i].k) == k:
			return i
	return -1


## 今のボード（ルールの今のゲートの、まだ当たっていないボード。始まる前は列の 0 枚目）。
func _current_board() -> int:
	var game := _game()
	if game == null:
		return -1
	return _board_for(maxi(game.gate_index, 0))


func _lit_off(i: int) -> void:
	for player: int in [1, 2]:
		for panel in range(SkyGateBoard.PANEL_COUNT):
			_boards[i].set_highlight(panel, player, false)


## 空中の腹ばい：ルールの位置に置き、動く速さの向きで傾ける（DropMotion：SD_Box_Loop と傾き 4 つ）。
func _pose_skydiver(player: int, game: SkyGateGame, delta: float) -> void:
	var actor: Dictionary = _actors[player]
	var root := actor.root as Node3D
	root.visible = true
	var target := Vector2.ZERO
	if game != null and game.phase == "gate":
		target = game.vel[player - 1] / SkyGateGame.MOVE_SPEED
	_lean[player - 1] = (_lean[player - 1] as Vector2).lerp(target.limit_length(1.0), 1.0 - exp(-delta * 6.0))
	var center := _body_center(player)
	# はね返されたときは体の横の軸まわりに回る（頭が起きてうしろへ）
	var spin := Basis(Vector3(1, 0, 0), float(_tumble[player - 1]))
	_place_box(player, center, _lean[player - 1], _air_t + float(player) * 0.37, spin)
	# まちがいのパネルに当たったら力が抜ける（ラグドール：腹ばいの姿の上に、手足と首のぐにゃぐにゃを重ねる）
	var limp := _limps.get(player) as SkyGateLimp
	if limp != null and limp.is_active():
		limp.apply(actor.parts)
		var pelvis := (actor.parts as Dictionary).get("pelvis") as Node3D
		if pelvis != null:
			root.global_position += center - pelvis.global_position


## 腹ばいの姿を当てて、腰を center に置く（頭が前＝+Z、背中が上）。spin は腰のまわりの回転。
func _place_box(player: int, center: Vector3, lean: Vector2, time: float, spin := Basis.IDENTITY) -> void:
	var actor: Dictionary = _actors[player]
	var root := actor.root as Node3D
	var parts: Dictionary = actor.parts
	root.global_transform = Transform3D(spin, center)
	if not DropMotion.pose_box(parts, lean, time):
		_pose_actor(player, spin * _frame(Vector3(0.0, 0.35, 1.0).normalized(), Vector3(0, -1, 0)), center, _with_wobble(POSE_BOX, player, 1.0))
		return
	var pelvis := parts.get("pelvis") as Node3D
	if pelvis != null:
		root.global_position += center - pelvis.global_position


## 2人の体の中心（ワールド）：ルールの位置＋風の小さなゆれ＋当たったあとの高さのずれ（はね返り）。
func _body_center(player: int) -> Vector3:
	var game := _game()
	var p := SkyGateGame.spawn_point(player)
	if game != null:
		p = game.pos[player - 1]
	return _air_point(p) + _drift(player) + Vector3.UP * float(_lift[player - 1])


func _air_point(p: Vector2) -> Vector3:
	return _fall_center() + RIGHT * p.x + FORWARD * p.y


func _fall_center() -> Vector3:
	return SKY_ORIGIN + Vector3(0.0, -FALL_DROP, 0.0)


func _drift(player: int) -> Vector3:
	var p := float(player)
	var t := _t
	return Vector3(sin(t * 0.9 + p) * 0.06, sin(t * 1.3 + p * 2.0) * 0.12, sin(t * 0.7 + p) * 0.05)


func _update_gathers(game: SkyGateGame, sd: float) -> void:
	# 2人とも同じゲートでアウト：復活の 1.0 秒のうち GATHER_AT からブロックが体へ戻る
	if game != null and game.phase == "both_out" and _t - _both_out_at >= GATHER_AT and _cue("gather_%d" % int(_both_out_at * 1000.0), true):
		for player: int in [1, 2]:
			(_gathers[player] as Gather).play(GATHER_TIME)
	for player: int in [1, 2]:
		(_gathers[player] as Gather).advance(sd, _body_center(player))


## ラウンドの落下の進み（0〜1）：ゲートの数と今のゲートの進み。
func _round_progress(game: SkyGateGame) -> float:
	if game == null or game.phase == "idle" or _pending_round > 0:
		return 0.0
	if game.overtime:
		return 0.5
	var within := game.gate_progress() if game.phase == "gate" else 1.0
	return clampf((float(maxi(game.gate_index, 0)) + within) / float(SkyGateGame.GATES_PER_ROUND), 0.0, 1.0)


## 風切りの強さ（sky_fx.md 2）：ふだん 1.0、ボードの半分まで近づいてから 0.5、つき破る瞬間に 1.4（すぐ 1.0 へ）。
## まちがいのスローの間は弱く（音程はスローで下がる）。
func _wind(game: SkyGateGame) -> float:
	var it := _impact_clock()
	if it >= 0.0 and it < 0.5:
		if _impact_mode() == SkyGateImpact.ALL_BURST:
			return lerpf(1.4, 1.0, smoothstep(0.1, 0.5, it))
		return lerpf(1.0, 0.6, _wasted)
	if game != null and game.phase == "gate" and game.gate_progress() > 0.5:
		return 0.5
	return lerpf(1.0, 0.6, _wasted)


## 見せ方の時計の速さ：まちがいの人がいたら、紙に触れた瞬間から強いスロー、爆散を見せたら戻す（SkyGateImpact.wasted_scale）。
func _time_scale_now() -> float:
	if _phase != "main" and _phase != "finish":
		return 1.0
	if not _impact.is_empty():
		return SkyGateImpact.wasted_scale(_impact_clock(), _impact_mode())
	return 1.0


## 脱落の色抜けの強さ（0〜1）。
func _wasted_now() -> float:
	if (_phase != "main" and _phase != "finish") or _impact.is_empty():
		return 0.0
	return SkyGateImpact.wasted_amount(_impact_clock(), _impact_mode())


## 今のまま当たったら全員が正解のパネルの上か（ユーザーの指示「くぐるときは減速せず・カメラの拡大を変えず突破」：
## その間は寄りを入れない。誰かがまちがえるなら、これまでどおり寄りで見せる）。
func _all_safe(game: SkyGateGame) -> bool:
	var answer := game.correct_choice()
	return answer >= 0 and game.under[0] == answer and game.under[1] == answer


## 全員が正解でつき破っている最中（当たってから判定まで）。画の距離は変えずに通りすぎる。
func _bursting_through(game: SkyGateGame) -> bool:
	if game == null or _impact.is_empty() or int(_impact.get("index", -1)) != game.gate_index:
		return false
	if game.phase != "impact":
		return false
	return _impact_mode() == SkyGateImpact.ALL_BURST


## 海の深さ：空の演出の帯に合わせたおすすめ（round_sea_depth。進み 0 で約 1840 m、1 で 75 m、延長は 520 m）。
## 行き先が変わっても（ラウンドの頭など）SEA_RATE より速くは動かさない。
func _update_sea_air(game: SkyGateGame, delta: float) -> void:
	var target := _fall_center().y - round_sea_depth(_round_progress(game), _overtime)
	_sea_y = move_toward(_sea_y, target, SEA_RATE * delta)
	_update_sea(delta)


## ラウンドの進み p（0〜1）の海の深さ（落ちる点から m）。SkyFallScenery.sea_depth の遠い側を SEA_START_SCALE 倍にした
## （最初の高度を上げた。最後の 75 m と延長の深さは同じ）。降下の側（水上機の場面）もこの深さに合わせると、渡したあと海が沈まない。
static func round_sea_depth(p: float, is_overtime := false) -> float:
	if is_overtime:
		return SkyFallScenery.sea_depth(p, true)
	var near := SkyFallScenery.sea_depth(1.0)
	return near + (SkyFallScenery.sea_depth(p) - near) * SEA_START_SCALE


func _sea_depth_now() -> float:
	return _fall_center().y - _sea_y


# ------------------------------------------------------------------ camera (air)

## 空中の画：ふだんも、全員が通り抜けるときも、まちがえた人がいるときも見下ろし（G2_TopDown。画は切り替えない）。
## まちがいの脱落のスローの間は、色抜けの強さに合わせて注視点をぶつかった人へ寄せ、少し近づく（決着したときは着地の画が
## この画から寄せる）。ラウンドの頭は 4 枚の列の引き（G4_Column）から見下ろしへ寄せる。
func _air_camera(game: SkyGateGame, delta: float) -> void:
	_cam_push = _push_weight(game)
	_fit_topdown(delta)
	var aim := _cam_aim
	var dist := _cam_dist
	_wasted_cam = move_toward(_wasted_cam, _wasted, delta * WASTED_CAM_RATE)
	if _wasted_cam > 0.0:
		var w := smoothstep(0.0, 1.0, _wasted_cam)
		aim = aim.lerp(_dead_center(), WASTED_AIM * w)
		dist *= lerpf(1.0, WASTED_PULL, w)
	var top := _orbit_pose(aim, PITCH, dist)
	var col := _column_weight()
	if col <= 0.0:
		_set_camera(top, MAIN_FOV, "g2_topdown")
		return
	var column := _column_pose()
	if col >= 1.0:
		_set_camera(column, COLUMN_FOV, "g4_column")
		return
	_set_camera(top.interpolate_with(column, col), lerpf(MAIN_FOV, COLUMN_FOV, col), "g4_column" if col > 0.5 else "g2_topdown")


## 見下ろしの画の寄り（0〜1）：当たるまでがゲートの長さの PUSH_SHARE（最大 PUSH_LEAD 秒）を切ってから、当たる PUSH_DONE 秒前
## までに 1。まちがいのつき破る間と決着は 1 のまま、全員が正解なら寄らない。復活は REVIVE_TIME で 0 へ戻す。
func _push_weight(game: SkyGateGame) -> float:
	if game == null or (_phase != "main" and _phase != "finish"):
		return 0.0
	match game.phase:
		"gate":
			if _all_safe(game):
				return 0.0
			var left := game.time_to_contact()
			var lead := minf(PUSH_LEAD, (game.gate_clock() + left) * PUSH_SHARE)
			return 1.0 - smoothstep(PUSH_DONE, maxf(lead, PUSH_DONE + 0.1), left)
		"impact":
			return 0.0 if _bursting_through(game) else 1.0
		"decided":
			return 1.0
		"both_out":
			return 1.0 - smoothstep(0.0, SkyGateGame.REVIVE_TIME, game.phase_clock())
	return 0.0


## ぶつかった人（2 人ともなら 2 人の真ん中）の体の中心（はね上がり・爆散したブロックの中心）。
func _dead_center() -> Vector3:
	var results: Array = _impact.get("results", [])
	var sum := Vector3.ZERO
	var count := 0
	for player: int in [1, 2]:
		if player - 1 < results.size() and str(results[player - 1]) == "boom":
			sum += _body_center(player)
			count += 1
	return sum / float(count) if count > 0 else _players_mid()


## G4_Column の重さ：列の引きを見せる間（ルールカードの間、ROUND 2 からの「ROUND n」の見出しの間）は 1、
## カウントダウンの「2」から GO までに 0 へ（見下ろしへ寄せる）。
func _column_weight() -> float:
	match _phase:
		"rules":
			return 1.0
		"countdown":
			return 1.0 - smoothstep(COUNT_STEP, COUNT_STEP * 3.0, _t - _count_at)
	return 0.0


## G4_Column：斜め上から、2人の下へ真下に続くボードの列（ルールの列の 0〜3 枚目）を収める引きの画。
func _column_pose() -> Transform3D:
	var center := _fall_center()
	return _look(center + COLUMN_EYE, center + Vector3.DOWN * COLUMN_LOOK_DEPTH, Vector3.UP)


## 注視点のまわりの画（前＝+Z へ向き、pitch 度で見下ろす。P1 は画面の左）。爆発のゆれを足す。
func _orbit_pose(aim: Vector3, pitch_deg: float, dist: float) -> Transform3D:
	var pitch := deg_to_rad(pitch_deg)
	var forward := Vector3(0.0, -sin(pitch), cos(pitch))
	var eye := aim - forward * dist
	var shake := clampf((_t - _shake_at) / 0.3, 0.0, 1.0)
	if shake > 0.0 and shake < 1.0:
		eye += Vector3(sin(_t * 90.0), sin(_t * 71.0) * 0.5, cos(_t * 77.0)) * 0.12 * (1.0 - shake)
	return Transform3D(Basis.looking_at(forward, Vector3.UP), eye)


func _players_mid() -> Vector3:
	return (_body_center(1) + _body_center(2)) * 0.5


func _topdown_basis() -> Basis:
	var pitch := deg_to_rad(PITCH)
	return Basis.looking_at(Vector3(0.0, -sin(pitch), cos(pitch)), Vector3.UP)


## 見下ろしの画に入れたい点（ワールド）：2人の体（手足の余白つき）と、近づいたボードの四隅。
func framing_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for player: int in [1, 2]:
		var c := _body_center(player)
		for dx: float in [-BODY_PAD, BODY_PAD]:
			for dz: float in [-BODY_PAD, BODY_PAD]:
				points.append(c + RIGHT * dx + FORWARD * dz)
	var cur := _current_board()
	# ボードに近づいたら2人へ寄る（_push_weight）：ボードと看板は画に収めない。当たったあとのボード（上へ抜けて消えていく）も
	# 収めない（寄った画のまま判定を見せ、次のボードへ向けて2人だけの画へ戻る）。
	var keep := 1.0 - _cam_push
	if cur >= 0 and _boards[cur].visible and not is_finite(float(_board_state[cur].hit_at)) and keep > 0.001:
		var st: Dictionary = _board_state[cur]
		var center := _boards[cur].global_position
		var w := (1.0 - smoothstep(FIT_BOARD_NEAR, FIT_BOARD_FAR, float(st.d))) * keep
		var half := SkyGateBoard.BOARD_SIZE * (st.scale as Vector2) * 0.5
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				var corner := center + RIGHT * (half.x * sx) + FORWARD * (half.y * sy)
				points.append(center.lerp(corner, w))
		var sign := _question_sign_point(cur)
		points.append(center.lerp(sign, w))
		# 問題文の看板（ボードと同じ幅で奥へはみ出す）の 4 隅も画に入れる
		for corner: Vector3 in _boards[cur].sign_corners():
			points.append(center.lerp(corner, w))
	return points


## 問題文の看板（ボードの奥の辺）のワールドの位置。W5 が帯（QuestionStrip）を大きな看板（QuestionSign）に替えても、
## 名前の違いはここだけで吸収する（看板のノードがあればその位置、無ければ帯の寸法 STRIP_CENTER）。
func _question_sign_point(i: int) -> Vector3:
	var board := _boards[i]
	for node_name: String in ["QuestionSign", "QuestionStrip"]:
		var node := board.find_child(node_name, true, false) as Node3D
		if node != null:
			if node is VisualInstance3D:
				var aabb := (node as VisualInstance3D).get_aabb()
				return node.global_transform * aabb.get_center()
			return node.global_position
	return board.board_point(SkyGateBoard.STRIP_CENTER)


## G2 の距離と注視点を、画に入れたい点に合わせて寄せる（ParachutePresenter._fit_main と同じ考え：画面に投影して数回直す）。
func _fit_topdown(delta: float) -> void:
	if _cam_ready and _bursting_through(_game()):
		return
	var points := framing_points()
	if points.is_empty():
		return
	var basis := _topdown_basis()
	var tan_v := tan(deg_to_rad(MAIN_FOV) * 0.5)
	var tan_h := tan_v * _aspect()
	var mid := _players_mid()
	var aim := mid
	var cur := _current_board()
	if cur >= 0 and _boards[cur].visible and not is_finite(float(_board_state[cur].hit_at)):
		var w := (1.0 - smoothstep(FIT_BOARD_NEAR, FIT_BOARD_FAR, float(_board_state[cur].d))) * (1.0 - _cam_push)
		var board_center := _boards[cur].board_point(SkyGateGame.panels_rect().get_center())
		aim = mid.lerp(Vector3(board_center.x, mid.y, board_center.z), BOARD_AIM * w)
	var near := lerpf(CAM_NEAR, PUSH_NEAR, _cam_push)
	var d := maxf(_cam_dist, near)
	for _i in range(8):
		var inv := Transform3D(basis, aim + basis.z * d).affine_inverse()
		var f_min := INF
		var f_max := -INF
		var x_min := INF
		var x_max := -INF
		for k in range(points.size()):
			var local: Vector3 = inv * points[k]
			var z := maxf(-local.z, 0.5)
			var fy := 0.5 - local.y / z / (2.0 * tan_v)
			var fx := local.x / z / tan_h
			f_min = minf(f_min, fy)
			f_max = maxf(f_max, fy)
			x_min = minf(x_min, fx)
			x_max = maxf(x_max, fx)
		# 注視点は動かさず、いちばんはみ出す点が枠に入る距離へ（画の真ん中 0.5 からの広がりで測る）
		var scale := maxf(maxf(absf(x_min), absf(x_max)) / FRAME_WIDTH,
			maxf((0.5 - f_min) / (0.5 - FRAME_TOP), (f_max - 0.5) / (FRAME_BOTTOM - 0.5)))
		d = maxf(near, d * lerpf(1.0, scale, 0.8))
	if not _cam_ready:
		_cam_dist = d
		_cam_aim = aim
		_cam_ready = true
		return
	var rate := FIT_OUT_RATE if d > _cam_dist else lerpf(FIT_IN_RATE, PUSH_RATE, _cam_push)
	_cam_dist = lerpf(_cam_dist, d, 1.0 - exp(-delta * rate))
	_cam_aim = _cam_aim.lerp(aim, 1.0 - exp(-delta * 3.0))


func _shake() -> void:
	_shake_at = _t


func _aspect() -> float:
	var viewport := get_viewport()
	if viewport != null:
		var size := viewport.get_visible_rect().size
		if size.y > 0.0:
			return size.x / size.y
	return 16.0 / 9.0


# ------------------------------------------------------------------ landing (round clear) and the finish

## 2人ともラウンドを突破：パラシュートを開いて着地台へ（ROUND の見出し）。判定のあとすぐ、今の画と高さから続ける。
func _begin_round_land() -> void:
	_phase = "round_land"
	_phase_t = 0.0
	_land_at = _t
	_land_plan = {}
	_landers = [1, 2]
	_next_round = _round + 1


## 決着：勝者だけが着地台へ。列の残りのボードは消える（_update_boards）。
func _begin_finish(player: int, by: String) -> void:
	_winner = player
	_loser = 3 - player
	_decided_by = by
	_phase = "finish"
	_phase_t = 0.0
	_finish_at = _t
	_land_at = _t + FINISH_BEAT
	_land_plan = {}
	_landers = [player]
	_ghost_shown = false
	AudioManager.play_sfx(&"score_drum_finish", -6.0)
	# 勝者の装備の 3 つの踊りを先に読んでおく（ダンスで止まらないように）。
	var state := _state()
	_dance_names.clear()
	for index in range(3):
		var emote := 0
		if state != null:
			var slots: Array[int] = state.p1_emote_slots if player == 1 else state.p2_emote_slots
			emote = int(slots[index]) if index < slots.size() else 0
			if emote <= 0:
				emote = state.get_result_winner_emote(player)
		if emote <= 0:
			emote = [18, 19, 13][index]
		var dance := ResultWinnerDance.new()
		dance.setup(_world, emote)
		_dances[index] = dance
		_dance_names.append(EmoteData.get_emote_name(emote))


## 着地の時計（着地を始めたときから）。
func _land_clock() -> float:
	return _t - _land_at


## 着地の時刻（_plan_landing の "land"）。まだ決めていなければ INF。
func _land_time() -> float:
	return float(_land_plan.get("land", INF))


func _update_finish(delta: float, sd: float) -> void:
	var f := _land_clock()
	if f < 0.0:
		# 判定の札を見せる間：本戦の画のまま（はね返り・運び去りの続き）
		_update_air(delta, sd)
		return
	if _decided_by == "speed" and _cue("speed_poof", true):
		# 早い者勝ちで負けた方も、ブロックにばらけて幽霊になる
		_fx.player_burst(_actors[_loser].parts, _body_center(_loser))
		_set_body_hidden(_loser, true)
		AudioManager.play_sfx(&"body_burst", -8.0)
	_update_landing(delta, sd)


## 着地の段取り（skygate_impact.md 第4章）：今の体の高さから着地台の上に立つまでの、相対の高さ h（体の腰が立つ高さより
## どれだけ上か）の道すじ。高ければ頭を下にして急降下（エルミート：落ちる速さで入って落ちる速さで出る）→ H_OPEN で開く →
## SNATCH 秒は落ちる速さのまま → V_CANOPY へ → H_FLARE から引いて着地。体そのものは最後の LANDING_DROP m を実際に下り、
## 残りは海と着地台が上がってくる（海の高さ = 体の高さ − h − 着地台の高さ）。
func _plan_landing() -> void:
	var pad := _float_pad_top()
	var body_y := 0.0
	_land_start.clear()
	for player: int in _landers:
		var c := _body_center(player)
		_land_start[player] = c
		body_y += c.y
	body_y /= maxf(float(_landers.size()), 1.0)
	var stand_y := _fall_center().y - LANDING_DROP + STAND_HIP
	var h0 := maxf(body_y - (_sea_y + pad + STAND_HIP), 3.0)
	var dive := maxf(0.0, h0 - H_OPEN)
	var t_dive := 0.0
	if dive > 0.0:
		var avg := lerpf(FALL_SPEED, DIVE_AVG_MAX, smoothstep(0.0, 600.0, dive))
		t_dive = minf(dive / avg, DIVE_TIME_MAX)
	var h_open := minf(h0, H_OPEN)
	var x_flare := 0.0
	if h_open > H_FLARE:
		var lo := 0.0
		var hi := 40.0
		for _i in range(40):
			var mid := (lo + hi) * 0.5
			if _canopy_drop(mid) < h_open - H_FLARE:
				lo = mid
			else:
				hi = mid
		x_flare = (lo + hi) * 0.5
	var v_flare := maxf(_canopy_speed(x_flare), 1.0)
	var flare := 2.0 * minf(h_open, H_FLARE) / v_flare
	_land_plan = {"h0": h0, "dive": dive, "t_dive": t_dive, "h_open": h_open, "open": t_dive, "flare": t_dive + x_flare,
		"flare_len": flare, "land": t_dive + x_flare + flare, "body_y0": body_y, "stand_y": stand_y}
	_land_h = h0
	_land_from_cam = _camera.get("transform", Transform3D.IDENTITY)
	_land_from_fov = float(_camera.get("fov", MAIN_FOV))
	# 着地の画の決まった位置：海が上がりきったときの着地台
	_landing = Vector3(_fall_center().x, _fall_center().y - LANDING_DROP - pad, _fall_center().z)


## パラシュートを開いてから x 秒で落ちる長さ（m）と速さ。
static func _canopy_drop(x: float) -> float:
	if x < SNATCH:
		return FALL_SPEED * x
	var s := x - SNATCH
	return FALL_SPEED * SNATCH + V_CANOPY * s + (FALL_SPEED - V_CANOPY) * SNATCH_TAU * (1.0 - exp(-s / SNATCH_TAU))


static func _canopy_speed(x: float) -> float:
	if x < SNATCH:
		return FALL_SPEED
	return V_CANOPY + (FALL_SPEED - V_CANOPY) * exp(-(x - SNATCH) / SNATCH_TAU)


## 着地の時計 f のときの相対の高さ h（m）。
func _land_height(f: float) -> float:
	var p := _land_plan
	var t_open := float(p.open)
	if f < t_open:
		var t_dive := float(p.t_dive)
		var dive := float(p.dive)
		var u := clampf(f / maxf(t_dive, 0.0001), 0.0, 1.0)
		var m := FALL_SPEED * t_dive / maxf(dive, 0.0001)
		var u2 := u * u
		var u3 := u2 * u
		var hermite := (-2.0 * u3 + 3.0 * u2) + (u3 - 2.0 * u2 + u) * m + (u3 - u2) * m
		return float(p.h0) - dive * hermite
	var t_flare := float(p.flare)
	if f < t_flare:
		return float(p.h_open) - _canopy_drop(f - t_open)
	var u := clampf((f - t_flare) / maxf(float(p.flare_len), 0.0001), 0.0, 1.0)
	return minf(float(p.h_open), H_FLARE) * (1.0 - u) * (1.0 - u)


## パラシュートを開いて着地台へ降りる（ROUND のあとは2人、決着は勝者だけ）。切らずに：急降下・開く・降りる・引く・着地。
func _update_landing(delta: float, sd: float) -> void:
	var f := _land_clock()
	var game := _game()
	if _land_plan.is_empty():
		_plan_landing()
	var p := _land_plan
	var t_open := float(p.open)
	var t_land := float(p.land)
	var h := _land_height(f)
	var flowed := maxf(_land_h - h, 0.0)
	var speed := flowed / maxf(delta, 0.0001)
	_land_h = h
	# 体は最後の LANDING_DROP m を実際に下りる（開いてから着地まで）。海と着地台はその下に上がってくる
	var down := smoothstep(t_open, t_land, f)
	var body_y := lerpf(float(p.body_y0), float(p.stand_y), down)
	_sea_y = body_y - h - _float_pad_top() - STAND_HIP
	_update_sea(delta)
	var top := _float.land_point() if _float != null else _landing + Vector3(0.0, 0.7, 0.0)
	var wind := clampf(speed / FALL_SPEED, 0.0, 1.4) if f < t_land else 0.0
	_scenery_advance(flowed, sd, 1.0, wind)
	if f > t_open + 0.9 and _cue("land_lines_%d" % int(_land_at * 1000.0), true):
		# 落ちる速さが落ちついたら、カメラの速さの線を外す（風が弱いので見えない）
		_scenery_camera(false)
	var canopy_air := smoothstep(t_open, t_open + 0.6, f)
	_advance_scarves(delta, SCARF_AIR_FALL.lerp(SCARF_AIR_CANOPY, canopy_air) if f < t_land else SCARF_AIR_GROUND,
		lerpf(1.0, 0.3, canopy_air) if f < t_land else 0.15)
	_update_boards(game, delta, sd)
	_update_impact(delta)
	if _fx != null:
		_fx.global_position = _fall_center()
		_fx.advance(sd)
	for player: int in [1, 2]:
		if not _landers.has(player) and not _hidden[player]:
			_pose_skydiver(player, game, delta)
	for player: int in _landers:
		_pose_lander(player, f, h, body_y, top, delta)
	_update_ghost(f, top, sd)
	_update_landing_camera(f, h, top)
	if _flotilla != null:
		# 観客船：降りてくる人に身を乗り出し、着地したら歓声とクラッカーと花火（決着はダンスの間ずっと）
		if f >= t_land - 2.4 and _cue("crowd_lean_%d" % int(_land_at * 1000.0), true):
			_flotilla.anticipate()
		if f >= t_land and _cue("crowd_party_%d" % int(_land_at * 1000.0), true):
			_flotilla.celebrate(_winner, _phase == "finish")
	if _phase == "round_land" and f >= t_land + L_BANNER_AFTER and _cue("round_banner_%d" % _next_round, true):
		var sub := "both reached the ground - next round" if _english() else "2人とも地上へ → 次のラウンド"
		_show_banner("ROUND %d" % _next_round, sub, PLAYER_COLORS[0].darkened(0.1), INF)
		AudioManager.play_sfx(&"sg_round_clear")
	if _phase == "round_land" and f >= t_land + L_ROUND_DONE_AFTER:
		_phase = "round_wait"
		_float.set_tally(true)


func _lander_mid() -> Vector3:
	var sum := Vector3.ZERO
	for player: int in _landers:
		sum += (_actors[player].root as Node3D).global_position
	return sum / maxf(float(_landers.size()), 1.0)


## 着地台の上の立つ点（ROUND のあとは左右に並ぶ。決着は真ん中）。P1 は画面の左（+X）。
func _stand_point(player: int, top: Vector3) -> Vector3:
	if _landers.size() < 2:
		return top
	return top - RIGHT * (LAND_SPREAD * (1.0 if player == 1 else -1.0))


## 1人の着地：開くまでは腹ばい（高い所からは頭を下に急降下）→ 開いて引かれ、立つ点の上へ寄りながら降りる → 引いて着地 →
## 顔を見合わせる（ROUND のあと）・勝ちの姿（決着）。
func _pose_lander(player: int, f: float, h: float, body_y: float, top: Vector3, delta: float) -> void:
	var p := _land_plan
	var t_open := float(p.open)
	var t_flare := float(p.flare)
	var t_land := float(p.land)
	var canopy := _canopies[player] as ParachuteCanopy
	var root := _actors[player].root as Node3D
	var stand := _stand_point(player, top)
	var start: Vector3 = _land_start.get(player, _body_center(player))
	# 横は開いてから立つ点の上へ寄る（縦は相対の高さ h）
	var glide := smoothstep(t_open, t_flare, f)
	var xz := Vector2(start.x, start.z).lerp(Vector2(stand.x, stand.z), glide)
	var center := Vector3(xz.x, body_y, xz.y)
	if f < t_land:
		center.y = stand.y + STAND_HIP + h
	root.visible = true
	if f < t_open:
		# 開く前：腹ばい。急降下なら頭を下へ傾ける
		var dive_k := clampf(float(p.dive) / 120.0, 0.0, 1.0) * smoothstep(0.0, 0.4, f) * (1.0 - smoothstep(t_open - 0.35, t_open, f))
		_place_box(player, center, Vector2(0.0, dive_k), _air_t + float(player) * 0.37, Basis(Vector3(1, 0, 0), 1.05 * dive_k))
		return
	if canopy.stage < 3:
		canopy.visible = true
		canopy.set_stage(3)
		# パラシュートがバサッと開く（2 人なら少しずらした音程）
		AudioManager.play_sfx(&"sg_chute_open", 0.0, 0.78 + 0.06 * float(player - 1))
	var snatch := smoothstep(t_open, t_open + SNATCH + 0.15, f)
	var box := _frame(Vector3(0.0, 0.35, 1.0).normalized(), Vector3(0, -1, 0))
	var body := box.slerp(_upright_basis(Vector3(0, 0, -1)), snatch)
	var pose: Array = _mix(POSE_BOX, POSE_CANOPY, snatch)
	if f < t_flare:
		center.x += sin(f * 2.1 + float(player)) * 0.25 * snatch
		_place_canopy(player, delta, snatch)
	elif f < t_land:
		var u := (f - t_flare) / maxf(t_land - t_flare, 0.0001)
		pose = _mix(POSE_CANOPY, POSE_FLARE, smoothstep(0.0, 0.6, u))
		if u > 0.8:
			pose = _mix(POSE_FLARE, POSE_LAND, smoothstep(0.8, 1.0, u))
		_place_canopy(player, delta, 1.0)
	else:
		if _cue("land_%d_%d" % [player, int(_land_at * 1000.0)], true):
			_float.dip()
			AudioManager.play_sfx(&"jump_land", -4.0)
			AudioManager.play_sfx(&"sg_float_splash")
			if _phase == "finish":
				AudioManager.play_sfx(&"sg_winner")
				# 勝者が着地台に降りたら結果の曲へ。ダンス・迎え・帰還から、やり直す判定までそのまま流れる
				AudioManager.set_music_track(AudioManager.MUSIC_TRACK_RESULT)
			_landed_canopy[player] = canopy.global_transform
			# 布を落とす床：人の後ろ（着地したときの向き。着地台は波でゆれるので、着地台から見た置き場所で持つ）
			var front := body.z.slide(Vector3.UP).normalized()
			var spot := stand - front * GROUND_BEHIND
			spot.y = _float.land_point().y
			_canopy_ground[player] = _float.global_transform.affine_inverse() * Transform3D(Basis.looking_at(-front, Vector3.UP), spot)
		center = stand + Vector3(0.0, STAND_HIP, 0.0)
		var g := f - t_land
		if _phase == "finish":
			pose = _mix(POSE_LAND, POSE_WIN, smoothstep(0.6, 1.8, g))
		else:
			# 2人：着地 → 顔を見合わせる
			pose = _mix(POSE_LAND, POSE_STAND, smoothstep(0.3, 1.0, g))
			var face := Vector3(-1.0 if player == 1 else 1.0, 0.0, -0.6).normalized()
			body = _upright_basis(Vector3(0, 0, -1)).slerp(_upright_basis(face), smoothstep(0.6, 1.4, g))
		canopy.collapse = smoothstep(0.1, 1.8, g)
		_lay_canopy(player, delta)
	_pose_actor(player, body, center, _with_wobble(pose, player, 0.5))


## 着地の画（切らない）：空中の画から LAND_CAM_BLEND 秒で、降りていく人をうしろの少し上から追う画へ寄り、
## 着地台が近づく（h < LAND_ORBIT_FROM）と着地台のまわりを回る画へ移る。
func _update_landing_camera(f: float, h: float, top: Vector3) -> void:
	var mid := _lander_mid()
	# 開いたパラシュート（体の 4〜5 m 上）も入るように、体より少し上を見る。高いうちは少し下（上がってくる海）も入れる
	var look := mid + Vector3(0.0, 2.2 - 0.06 * minf(h, 40.0), 0.0)
	var follow := _look(mid + Vector3(1.5, 1.4, 0.0) - FORWARD * LAND_FOLLOW_DIST, look, Vector3.UP)
	var t_land := _land_time()
	var a := deg_to_rad(lerpf(200.0, 160.0, smoothstep(t_land - 0.8, t_land + 4.2, f)))
	_orbit = a
	var radius := LANDING_RADIUS + (1.6 if _landers.size() > 1 else 0.0)
	var eye := top + Vector3(sin(a) * radius, 1.9, cos(a) * radius)
	var orbit := _look(eye, top + Vector3(0.0, 1.3, 0.0), Vector3.UP)
	var to_orbit := 1.0 - smoothstep(1.0, LAND_ORBIT_FROM, h) if f < t_land else 1.0
	var target := follow.interpolate_with(orbit, to_orbit)
	var fov := lerpf(55.0, 46.0, to_orbit)
	var w := smoothstep(0.0, LAND_CAM_BLEND, f)
	var shot := "g5_landing" if to_orbit > 0.5 else "g5_follow"
	_set_camera(_land_from_cam.interpolate_with(target, w), lerpf(_land_from_fov, fov, w), shot)


## 幽霊：アウトの人のブロックが集まって幽霊になり、勝者の横をふわふわついていく。着地したら着地台の横の宙で待つ。
func _update_ghost(f: float, top: Vector3, sd: float) -> void:
	if _phase != "finish" or _loser <= 0:
		return
	var ghost: Dictionary = _ghosts[_loser]
	var root := ghost.root as Node3D
	var at := _ghost_point(f)
	if f >= GHOST_AT and _cue("ghost_gather", true):
		(_gathers[_loser] as Gather).play(GATHER_TIME)
		AudioManager.play_sfx(&"ghost_soul_rise", -4.0)
	var t_land := _land_time()
	at = at.lerp(_ghost_rest_point(top), smoothstep(t_land - 0.4, t_land + 0.8, f))
	(_gathers[_loser] as Gather).advance(sd, at)
	if f >= GHOST_AT + GATHER_TIME * 0.9 and not _ghost_shown:
		_ghost_shown = true
		if _fx != null:
			_fx.flash(_fx.to_local(at), 1.2, 0.3, Color(0.8, 0.9, 1.0))
	root.visible = _ghost_shown
	if _ghost_shown:
		_pose_doll(ghost, _upright_basis(Vector3(0, 0, -1)), at, _with_wobble(POSE_GHOST, _loser, 1.5))


func _ghost_point(f: float) -> Vector3:
	var winner_at := (_actors[_winner].root as Node3D).global_position
	var side := 1.0 if _loser == 1 else -1.0
	var bob := Vector3(sin(_t * 1.7) * 0.15, sin(_t * 2.3) * 0.25, 0.0)
	return winner_at - RIGHT * (1.9 * side) + Vector3(0.0, 0.9, 0.4) + bob + Vector3.UP * (1.0 - smoothstep(GHOST_AT, GHOST_AT + 1.0, f)) * 2.0


## 着地台の横の宙（幽霊が待つ所）。
func _ghost_rest_point(top: Vector3) -> Vector3:
	var side := 1.0 if _loser == 1 else -1.0
	return top - RIGHT * (2.6 * side) + Vector3(0.0, 2.9 + sin(_t * 2.0) * 0.2, 0.8)


# ------------------------------------------------------------------ the winner's dance

func pose_winner_waiting(player: int, time: float) -> void:
	if _released or not _actors.has(player):
		return
	if _phase == "finish":
		_phase = "dance"
		_phase_t = 0.0
		_dance_t = 0.0
		_dance_slot = -1
		_dance_prev_mask = _emote_mask(player)
		_float.set_tally(true)
	_dance_t = time
	var mask := _emote_mask(player)
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
	var camera := _main_camera()
	_pose_actor(player, _upright_basis(Vector3(0, 0, -1)), top + Vector3(0.0, 1.32, 0.0), POSE_WIN)
	_lay_canopy(player, 0.0)
	if _loser > 0:
		var ghost: Dictionary = _ghosts[_loser]
		(ghost.root as Node3D).visible = true
		_pose_doll(ghost, _upright_basis(Vector3(0, 0, -1)), _ghost_rest_point(top), _with_wobble(POSE_GHOST, _loser, 1.5))
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
	if _flotilla != null:
		_flotilla.stop_show()
	if not _actors.has(player):
		return
	var root := _actors[player].root as Node3D
	var pelvis := _actors[player].parts.get("pelvis") as Node3D
	var at := pelvis.global_position if pelvis != null else root.global_position
	root.visible = false
	(_canopies[player] as ParachuteCanopy).visible = false
	var puppet := director.puppet(player) if director != null else null
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
		# 着地の画（着地台のまわりを回る）からそのまま続ける：同じ向きに回り、半径・高さ・画角を踊りの画へ寄せる
		var a := _orbit - deg_to_rad(ORBIT_SPEED) * _dance_t
		var settle := smoothstep(0.0, 1.5, _dance_t)
		var pull := smoothstep(EXTRACT_DELAY + 1.0, EXTRACT_DELAY + 2.4, _dance_t)
		var radius := lerpf(lerpf(LANDING_RADIUS, DANCE_RADIUS, settle), 11.0, pull)
		var eye := top + Vector3(sin(a) * radius, lerpf(lerpf(1.9, 2.1, settle), 2.8, pull), cos(a) * radius)
		var target := top + Vector3(0.0, lerpf(1.3, 2.6, pull), 0.0)
		return {"transform": _look(eye, target, Vector3.UP), "fov": lerpf(46.0, 44.0, settle) + 8.0 * pull}
	var puppet := director.puppet(player) if director != null else null
	var winner_at := puppet.center() if puppet != null else top
	return {"transform": _look(top + Vector3(3.5, 2.6, -10.5), (winner_at + heli_position) * 0.5, Vector3.UP), "fov": 55.0}


# ------------------------------------------------------------------ HUD

## HUD は削ぎ落とす（2026-10-25、ユーザーの指示「無駄な UI を削ぎ落とす。端の選んでる選択肢やセーフは要らない」）：
## 本戦は上の真ん中の小さな「ROUND n」とゲートの丸、ROUND 1 の 1 枚目の間だけ下の操作キー。2人の札・残り時間の帯・
## 小さな知らせは出さない。ほかはルールカード（列の引きを RULES_DELAY 秒見せてから）、見出し、勝者の札、ダンスのキー、脱落の暗がり。
func _update_hud() -> void:
	if _hud == null:
		return
	var game := _game()
	var english := _english()
	_hud.english = english
	var hud_state := {}
	var card := _phase == "rules" and _t - _rules_at >= RULES_DELAY
	_set_rule_demos_playing(card or (_phase == "countdown" and _pending_round == 0 and _t - _count_at < 0.6))
	if card:
		hud_state["rules"] = true
		hud_state["rules_prompt"] = _t - _rules_at >= RULES_DELAY + RULE_HOLD
	var in_game := _phase in ["countdown", "main"] or (_phase == "finish" and _land_clock() < 0.0)
	if in_game and game != null:
		var pending := _pending_round > 0
		var round_number := _pending_round if pending else maxi(game.current_round, 1)
		hud_state["round"] = {"visible": true, "round": round_number, "gate": 0 if pending else maxi(game.gate_index, 0),
			"gates": SkyGateGame.GATES_PER_ROUND, "overtime": game.overtime}
		# 動かし方のキーは ROUND 1 の 1 枚目に当たるまで
		hud_state["keys"] = _phase != "finish" and round_number == 1 and not pending and game.gate_index <= 0 \
			and (game.waiting_for_start or game.phase == "gate")
	if _t < _banner_until and not _banner.is_empty():
		hud_state["banner"] = _banner
	if _winner > 0 and ((_phase == "finish" and _land_clock() >= _land_time()) or _phase == "dance"):
		hud_state["winner"] = _winner
	if _phase == "dance" and not _released:
		var left := int(ceil(maxf(EXTRACT_DELAY + 2.4 - _dance_t, 0.0)))
		hud_state["emote"] = {"visible": true, "player": _winner, "names": _dance_names, "playing": _dance_slot, "seconds": left}
	if _wasted > 0.0001:
		hud_state["wasted"] = _wasted
	_hud.set_state(hud_state)


## 監督（W6）：ラウンドの間の迎えが始まったら「ROUND n」の見出しを after 秒で下げる（水上機が見えるように）。
func hide_banner(after := 0.0) -> void:
	_banner_until = minf(_banner_until, _t + after)


## 「ROUND n」の見出し（ROUND 2 から。むずかしさ）と銅鑼。
func _show_round_banner(round_number: int, seconds: float) -> void:
	var small := round_number >= SkyGateGame.SMALL_FROM_ROUND
	var sub := "ボードが小さく・もっと速く" if small else "落ちるのが速く・ボードが動く"
	if _english():
		sub = "smaller boards, even faster" if small else "faster fall - the boards move"
	_show_banner("ROUND %d" % round_number, sub, PLAYER_COLORS[0].darkened(0.1), seconds)
	AudioManager.play_sfx(&"sg_round_gong")


func _show_banner(text: String, sub: String, color: Color, seconds: float) -> void:
	_banner = {"text": text, "sub": sub, "color": color}
	_banner_until = _t + seconds


# ------------------------------------------------------------------ pieces

func _state() -> QuizGameState:
	if director != null:
		return director.game_state
	return _solo_state


func _game() -> SkyGateGame:
	if _solo_game != null:
		return _solo_game
	var state := _state()
	return state.sudden_death_game as SkyGateGame if state != null else null


func _sky() -> SuddenDeathSkySet:
	return director.sky_set() if director != null else _solo_sky


func _common_hud() -> SuddenDeathHud:
	return director.hud() if director != null else _solo_hud


func _main_camera() -> Camera3D:
	return director.main_camera() if director != null else _solo_camera


## 海・雲・サングリントを照らす太陽（ステージの太陽）。
func _sun_light() -> DirectionalLight3D:
	if director != null:
		return director.stage_env.directional_light if director.stage_env != null else null
	return _solo_sun


func _emote_mask(player: int) -> int:
	if director != null:
		return director.emote_keys(player)
	return int(_solo_emotes[clampi(player, 1, 2) - 1])


func _english() -> bool:
	var state := _state()
	return state.use_english_ui if state != null else false


func _quality() -> String:
	return String(GameManager.graphics_quality)


static func _round_scale(round_number: int) -> Vector2:
	var size := SkyGateGame.SMALL_BOARD_SIZE if round_number >= SkyGateGame.SMALL_FROM_ROUND else SkyGateGame.BOARD_SIZE
	return size / SkyGateGame.BOARD_SIZE


func _float_pad_top() -> float:
	return _float.pad_top if _float != null else 0.7


## 海と着地台を今の高さへ（空のセットの海を上下させる）。
func _update_sea(delta: float) -> void:
	var sky := _sky()
	if sky != null and sky.ocean != null:
		sky.ocean.position.y = _sea_y - sky.global_position.y
	if _float != null:
		_float.float_at(Vector3(_fall_center().x, 0.0, _fall_center().z), _sea_y, delta)
	if _flotilla != null:
		_flotilla.float_at(Vector3(_fall_center().x, 0.0, _fall_center().z), _sea_y, delta)


func _restore_sea() -> void:
	var sky := _sky()
	if sky != null and sky.ocean != null:
		sky.ocean.position.y = -SuddenDeathSkySet.FLY_HEIGHT


func _place_canopy(player: int, delta: float, upright := 0.0) -> void:
	var canopy := _canopies[player] as ParachuteCanopy
	var parts: Dictionary = _actors[player].parts
	var spine := parts.get("spine") as Node3D
	if spine == null:
		return
	canopy.visible = (_actors[player].root as Node3D).visible and canopy.stage > 0
	var shoulder := spine.global_transform * Vector3(0.0, 0.45, -0.1)
	var body := (_actors[player].root as Node3D).global_basis
	var head := body.y.normalized()
	var up := (Vector3.UP + head * 0.25).normalized().lerp(head, upright).normalized()
	var side := body.x.slide(up).normalized()
	var fwd := side.cross(up).normalized()
	canopy.place(Transform3D(Basis(side, up, fwd), shoulder), delta)


## 着地のあと：パラシュートを着地台の床（人の後ろ）へ落とす。
func _lay_canopy(player: int, delta: float) -> void:
	var canopy := _canopies[player] as ParachuteCanopy
	if _float == null:
		return
	var local: Transform3D = _canopy_ground.get(player, Transform3D(Basis.IDENTITY, Vector3(0.0, _float.pad_top, -GROUND_BEHIND)))
	canopy.drop_to(_float.global_transform * local)
	canopy.place(_landed_canopy.get(player, canopy.global_transform) as Transform3D, delta)


## 立った向き（胸を front へ）。
func _upright_basis(front: Vector3) -> Basis:
	return _frame(Vector3.UP, front)


func _frame(head: Vector3, front: Vector3) -> Basis:
	var y := head.normalized()
	var z := front.slide(y).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## 人形を置き、関節の角度の表を当てる（休めの姿から）。
func _pose_actor(player: int, body: Basis, center: Vector3, pose: Array) -> void:
	_pose_doll(_actors[player], body, center, pose)


func _pose_doll(actor: Dictionary, body: Basis, center: Vector3, pose: Array) -> void:
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


## 風で手足が小さく揺れる。
func _with_wobble(pose: Array, player: int, amount: float) -> Array:
	var p := float(player) * 1.7
	var t := _t
	var out := pose.duplicate()
	out.append_array([
		["l_shoulder", "z", sin(t * TAU / 0.7 + p) * 4.0 * amount],
		["r_shoulder", "z", sin(t * TAU / 0.7 + p + 1.1) * 4.0 * amount],
		["l_knee", "x", sin(t * TAU / 1.1 + p) * 5.0 * amount],
		["r_knee", "x", sin(t * TAU / 1.1 + p + 0.8) * 5.0 * amount],
		["spine", "z", sin(t * TAU / 1.9 + p) * 2.0 * amount],
	])
	return out


func _set_camera(xf: Transform3D, fov: float, shot: String) -> void:
	# 寄せ方はここで持つので、監督の追いかけ（なめらかに寄せる）を重ねない
	_shot = shot
	_camera = {"transform": xf, "fov": fov, "cut": true, "shot": shot}


func _look(eye: Vector3, target: Vector3, up: Vector3) -> Transform3D:
	var dir := target - eye
	if absf(dir.normalized().dot(up.normalized())) > 0.995:
		up = FORWARD
	return Transform3D(Basis.looking_at(dir, up), eye)


func _cue(cue_name: String, when: bool) -> bool:
	if not when or _cues.has(cue_name):
		return false
	_cues[cue_name] = _t
	return true


# ------------------------------------------------------------------ teardown and debug

func teardown() -> void:
	_set_rule_demos_playing(false)
	_stop_wind_audio()
	_apply_wasted(0.0)
	_restore_sea()
	# 速さの線の板はカメラの子なので、見せ方を消す前にかならず外す
	_scenery_camera(false)
	_show_cruise_clouds(true)
	for dance: Variant in _dances.values():
		(dance as ResultWinnerDance).clear()
	_dances.clear()
	if _flotilla != null:
		_flotilla.reset_show()
	if _hud != null:
		_hud.hide_all()
	if _world != null:
		_world.visible = false
	_phase = "idle"


func debug_step_clock(seconds: float) -> void:
	if _hud != null:
		_hud.debug_manual_clock = true
		_hud.debug_step(seconds)


func phase_name() -> String:
	return _phase


func hud() -> SkyGateHud:
	return _hud


func flotilla() -> SkyGateFlotilla:
	return _flotilla


func boards() -> Array[SkyGateBoard]:
	return _boards


func current_board() -> SkyGateBoard:
	var cur := _current_board()
	return _boards[cur] if cur >= 0 else null


func rule_demos() -> Array[SkyGateRuleDemo]:
	return _rule_demos


func get_debug_snapshot() -> Dictionary:
	var centers := []
	for player: int in [1, 2]:
		if _actors.has(player):
			var root := _actors[player].root as Node3D
			centers.append([snappedf(root.global_position.x, 0.01), snappedf(root.global_position.y, 0.01), snappedf(root.global_position.z, 0.01)])
	var board_list := []
	for i in range(_board_state.size()):
		board_list.append({"role": _board_state[i].role, "k": int(_board_state[i].k), "d": snappedf(float(_board_state[i].d), 0.01),
			"visible": _boards[i].visible, "q": str(_board_state[i].q)})
	return {"phase": _phase, "t": snappedf(_t, 0.01), "shot": _shot, "slow": snappedf(_slow, 0.01), "round": _round, "gate": _gate,
		"wasted": snappedf(_wasted, 0.01), "scene_t": snappedf(_scene_t, 0.01),
		"centers": centers, "boards": board_list, "sea_y": snappedf(_sea_y, 0.01), "winner": _winner, "loser": _loser, "by": _decided_by,
		"cam_dist": snappedf(_cam_dist, 0.01), "hidden": _hidden.duplicate(), "ghost": _ghost_shown, "dance_slot": _dance_slot,
		"released": _released, "built": _built, "scenery": _scenery.name if _scenery != null else "",
		"flotilla": _flotilla.get_debug_snapshot() if _flotilla != null else {},
		"hud": _hud.get_debug_snapshot() if _hud != null else {}}
