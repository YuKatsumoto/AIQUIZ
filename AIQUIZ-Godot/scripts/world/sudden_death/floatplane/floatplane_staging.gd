class_name FloatplaneStaging
extends Node3D

## サドンデス「つきやぶれ！スカイゲート」の水上機の場面（docs/sudden_death_v2/skygate_build_plan.md 4.7、c130_float.md 第6・8章、
## heli_drop.md 第3章）。監督（HeliSuddenDeathDirector）が場面ごとに呼ぶ：
##   乗り込み     begin_board / update_board → "cover"（雲の覆いへ）
##   機内の巡航   enter_cruise / update_cruise
##   降下         begin_drop / update_drop → "handover"（2人が腹ばいに落ち着いた。本戦の見下ろしへ渡す）
##   着地台の迎え begin_pickup / update_pickup → "cover"（ROUND の間は2人、決着のあとは勝者だけ）
##   帰還         begin_home / update_home → "landed"（勝者が床に着いた）
## 部品：水上機 SuddenDeathFloatplane（W1）、水路 StandGate・昇降台 FloorEdgeLift（W2）、人の動き DropMotion（W3）。
## 離着水の動きは FloatplaneFlight（進入・着水・後ろ向きに寄せる・動き出し・離水を前もって積む）、航跡は FloatplaneWake
## （c130_float.md 第9章）。
## 人物は監督の StagingPuppet（本物のアバター）。時計は監督の演出の時計（update_* の delta）。カメラは監督の stage_camera へ渡す。
## 座標：水上機の原点＝喫水線 × 胴体の中心線 × 主翼の翼弦の中央、機首 −Z（モデルのまま）。P1 は機体の右の壁（ローカル +X）。

const SEA_Y := StageConstants.OCEAN_SURFACE_Y
const FLOOR_Y := StageConstants.FLOOR_TOP_Y
## 貨物室の床（機体のローカルの y）と、スロープの付け根・端（ローカルの z、スロープが水平のとき）。
const CABIN_FLOOR := 1.9
const HINGE_Z := 4.6
const EDGE_Z := 7.8
## 機内の2人の通り道（機体のローカルの x の大きさ）。
const LANE_X := 0.75
## 走るクリップの速さ（drop_moves.json の speed と同じ。足がすべらない速さ）。
const RUN_OUT_SPEED := 7.12
const RUN_UP_SPEED := 5.9

# ------------------------------------------------------------------ 乗り込み（c130_float.md 第6・9・10章。秒は「乗りこめー！」から）
const Walker := preload("res://scripts/world/sudden_death/floatplane/fp_walker.gd")
const Lens := preload("res://scripts/world/sudden_death/floatplane/fp_lens.gd")
const CloudPass := preload("res://scripts/world/sudden_death/floatplane/fp_cloud_pass.gd")
const SkipHint := preload("res://scripts/world/sudden_death/floatplane/fp_skip_hint.gd")
const B_TOWERS := Vector2(0.0, 0.7)
const B_LIFT := Vector2(0.25, 1.55)
## 進入（FloatplaneFlight.landing。s は台座の中心からの x）：0 秒に x＝−50。向こう（−X）のスタンドの上を 22.5 m で越え、
## 15.5° の急な進入（輸送機の戦術進入）で台座の上を床から約 6 m で通り、持ち上げたスタンドの下をくぐりながら機首を起こして
## 外の海に着水する（約 x＝79、32 m/秒）。少し右から寄せて、向こうのスタンドの手前で向きを合わせる。着水したら逆推力いっぱい。
const B_APPROACH := {"start_s": -50.0, "anchor_s": -27.2, "anchor_h": 22.5, "glide_deg": 15.5, "flare_s": 5.0, "touch_deg": 3.0,
	"v_app": 38.0, "v_td": 32.0, "slow_from": 0.0, "turn_deg": 3.0, "turn_from": -95.0, "turn_to": -12.0, "alpha_deg": 6.5,
	"turb": 1.0, "duration": 14.0, "reverse_decel": 8.5}
## 02（床から見上げる）の始まり。
const B_FLYOVER := 0.75
## 着水して止まったら、そのまま逆推力で後ろ向きに加速して水路まで戻る（時間を飛ばさない）。
## 後ろ向きの速さ（m/秒）・加速の秒・最後になめらかに止める秒。
const B_BACK_SPEED := 15.0
const B_BACK_ACCEL := 3.0
const B_BACK_BRAKE := 4.2
## 昇降台（c130_float.md 第10章）。床の高さのデッキは尾翼に当たるので、機体が寄ってくる前にデッキを起こし、2 人を乗せて
## 貨物室の床の高さまで下ろしておく。2 人はそこで待ち、尾が頭の上をくぐってくる。秒は機体が止まる何秒前か。
const B_LIFT_DEPLOY := 10.4
const B_RUN_LEAD := [8.4, 8.2]
## 上のふたを開け、スロープを途中まで下ろす（尾が 2 人の頭の上を通る前に）。止まってからスロープを下ろしきり、先をデッキの受けに載せる。
const B_DOOR := Vector2(7.4, 5.0)
const B_RAMP_HALF := 0.72
const B_RAMP_SET := Vector2(0.05, 0.85)
## 止まってから駆け込む（P1 が先）
const B_BOARD_GO := [1.45, 1.62]
## デッキの上の立ち位置（壁から外への割合・中心線からの横。P1 は +Z）：下りる間は手すりの近く、待つのは尾の通り道の真ん中
const DECK_RIDE := Vector2(0.5, 1.38)
const DECK_WAIT := Vector2(0.68, 0.62)
## 走る速さ（台座から床の端・スロープから機内）
const B_RUN_SPEED := 5.2
const B_IN_SPEED := 4.4
## 機内：2 人が座ってベルトを締め始めたら、スロープと上のふたを閉める（秒）。閉め始めてから推力を上げるまで。
const B_CLOSE := 2.3
const B_SPOOL_AT := 0.6
## 動き出しから離水・上昇（FloatplaneFlight.departure）。浮いたら 13° で上がり、雲の層（海面から 32〜58 m）の中で場所を替える。
const B_DEPART := {"go": 0.0, "spool": 1.6, "a_max": 5.4, "v_rotate": 30.0, "rotate_time": 0.8, "pitch_lof": 8.5, "v_lof": 33.0,
	"climb_deg": 13.0, "alpha_deg": 7.0, "v_cruise": 46.0, "duration": 40.0}
const CLOUD_BOTTOM := 32.0
const CLOUD_TOP := 58.0
const B_LIMIT := 75.0
## 持ち上げたスタンドを下ろすのは、尾が持ち上げたスタンドの外へ出てから（x）。
const STAND_CLEAR_X := 46.0
## 床の上の 2 人の昇降台の上の位置（古い約束。使わない）
const DECK_SPOT_X := 1.7
const DECK_SPOT_Z := 0.8
## 昇降台のデッキの上面を、貨物室の床（スロープの上面）よりこれだけ低く（スロープの先がデッキの受けに載る。2 cm の段）
const LIFT_TOE := 0.02
## 座る：ベンチの前に立つ所（座った腰から通路へ）と、腰を下ろす動き（UAL の Sitting_Enter）の速さ
const SIT_REACH := 0.46
const SIT_DOWN_CLIP := "Sitting_Enter"
const SIT_DOWN_SPEED := 1.15
## 操縦席の窓（前の右の外側の窓 |x| 0.66〜1.16 の真ん中の高さ、ガラスは v 約 4.18〜4.65。そのすぐ内と外。機体のローカル。
## カメラが通り抜ける）と、機内で通る点（ハテナの頭とヘッドセット |x| 0.65 以内から 0.4 m 右の外 → 操縦席の段の右うしろ）。
## 第 11 章で窓を下へ広げたのに合わせた（前は窓の上の外板を通り抜けていた）。右の窓にしたのは、巡航で入るときハテナが
## 手を振る腕（機体の左）の横を通らないため。
const WINDSHIELD_IN := Vector3(0.95, 4.45, -5.45)
const WINDSHIELD_OUT := Vector3(0.95, 4.45, -6.6)
const COCKPIT_PASS := Vector3(1.05, 4.5, -4.95)
const COCKPIT_BACK := Vector3(0.5, 4.55, -3.85)
## 乗り込みのカメラが 2 人を待つ所（スロープの先の左の横。浮き舟の上、デッキの手すりの外）と、離水を追い始める所（機体の向きの枠）
const LEAD_SIDE := Vector3(-2.6, 2.55, 7.2)
## 乗り込みの中ほどのカメラ（c130_float.md 第13章。秒は機体が止まる何秒前か、位置は水路の中心 z からのずれ）：
##   沖で止まった機体を望遠で追ったあと、床の上の後ろの高い所へ引いて全体を見せる（REVEAL。後ろ向きに戻ってくる機体・起きる昇降台・
##   台座の 2 人が一つの画に入る）→ 駆け出した 2 人を後ろから追って床の端へ（RUN）→ 床の端を越えて、2 人を乗せて下りる昇降台の横を
##   一緒に下りる（RIDE。寄ってくる尾が 2 人の頭の上に来る）
const B_REVEAL_AT := 12.6
const B_REVEAL_LEN := 3.0
const REVEAL_EYE := Vector3(-13.0, 4.2, -4.5)
const B_RUN_CAM := 8.7
const RUN_CAM_BACK := 8.5
const RUN_CAM_MAX_X := 6.0
## 駆け出した 2 人を追うカメラの横（水路の中心から −Z へ。2 人のほぼ真後ろ：2 人と寄ってくる機体が奥へ一直線に並ぶ）
const RUN_CAM_Z := -3.0
## 昇降台と一緒に下りるカメラ：デッキの上面からの高さ・横（水路の中心から −Z へ）
const RIDE_EYE := Vector3(13.0, 2.4, -7.0)
## 出発：操縦席へ向き直ってから（1.8 秒）水路を出るのを操縦席から見て、EXIT_PUSH 秒から EXIT_LEN 秒かけて窓から前へ抜け、
## 振り返りながら左の横へ回る。そこから滑走・離水を並んで追い（CHASE_RUN）、浮いたら左うしろの下から上がっていく機体を見上げる
## （CHASE_CLIMB。どちらも機体の向きの枠）。
const EXIT_PUSH := 3.0
const EXIT_LEN := 3.4
## 翼幅 24 m の機体が画に収まる距離（翼の高さより少し上から、浮き舟と横へ広がるしぶきが見える）
const CHASE_RUN := Vector3(-32.0, 4.5, -10.0)
const CHASE_CLIMB := Vector3(-26.0, -4.5, 33.0)
## スロープの上で 2 人を待つ所と、駆け込む 2 人の前を保つ距離
const LEAD_IN := Vector3(0.0, 3.3, 6.25)
const LEAD_GAP := 2.7
## 操縦席から前を見るカメラ（右の席の目の高さ。ハテナの右の肩越しに、前の窓から外を見る。窓を下げたので目も下げた）
const COCKPIT_EYE := Vector3(0.9, 4.55, -4.55)
const COCKPIT_AIM := Vector3(0.2, 4.2, -14.0)
## 機内（MK_CamAft）と操縦席（COCKPIT_EYE）のあいだを向き直るとき、途中で通る所。先に右へ寄ってから回るので、横を向いたときに
## ハテナの座席の背もたれが目の前に来ない（視線の先のいちばん近い物は 0.46 m 以上、背もたれは 0.62 m。まっすぐ動かすと 0.16 m）。
const TURN_MID := Vector3(0.75, 4.66, -3.75)
## 向き直りの途中で広げる画角（度）
const TURN_WIDEN := 9.0
## 迎えの機内で離水を操縦席から見る間、窓の方へゆっくり寄る（割合は COCKPIT_EYE → WINDSHIELD_IN、秒・画角を狭める度）
const RIDE_PUSH := 0.35
const RIDE_PUSH_TIME := 9.0
const RIDE_PUSH_FOV := 10.0
const CHASE_START := Vector3(-16.0, 5.0, 4.0)
## 巡航：雲の層から上へ抜けて降下の位置で水平になるまで（秒）と、そのとき雲の層の上からの高さ（m）
const CRUISE_SETTLE := 4.0
const CRUISE_ABOVE_CLOUD := 3.5

# ------------------------------------------------------------------ 降下（heli_drop.md 3.1。秒は降下の始まりから）
const D_THUMB := 1.0
## スロープと上のふたが開く（2.2 秒。油圧）・ベルトを外して立つ・緑のランプ・先の人が駆け出す
const D_RAMP := Vector2(1.4, 3.6)
const D_UNBUCKLE := 2.1
const UNBUCKLE_SPEED := 1.25
const D_GREEN := 3.6
const D_GO := 4.05
## 短い版（ROUND 2 から）：迎えのあと機内でベルトを締めて座っている所から。雲の層から上へ抜けると、スロープが開いて、
## ベルトを外して立ち、緑で駆け出す。
const D_SHORT_RAMP := Vector2(2.0, 3.8)
const D_SHORT_UNBUCKLE := 2.3
const D_SHORT_GREEN := 3.8
## 短い降下（雲の中で入れ替えた直後）：赤いジャンプ灯をつける時刻（入れ替えたフレームには何も変えない）
const D_SHORT_RED := 1.0
const D_SHORT_GO := 4.2
## 腹ばいで落ちながら、本戦の位置（presenter.sky_spawn）へ寄る長さの下限（約 20 m を落ちる）。
const BOX_MIN := 1.0
## 落ちる点（presenter.fall_center）から見た、降下の機体の原点。空のセットの下の雲の層（落ちる点の 10 m 上）の少し上を飛び、
## スロープの端は落ちる点の 26 m 上・8 m 後ろ。2 人は雲の層をつき抜けて本戦の位置まで落ちていく。
const DROP_OFFSET := Vector3(0.0, 24.0, -16.0)
## 空のセットの海の深さ（落ちる点から）。巡航は 200 m 下（海の板のふちが地平線の近くに隠れる）、降下で 2 人が腹ばいに
## なってカメラが下を向くあいだに、本戦の初めの深さ（900 m）まで下げる。
const CRUISE_SEA_DEPTH := 200.0
const DROP_SEA_DEPTH := 900.0

# ------------------------------------------------------------------ 着地台の迎え（c130_float.md 8.3・第9章。秒は迎えの始まりから）
## 進入（FloatplaneFlight.landing。s は着地台の中心から進む向きへの距離）：0 秒に s＝−58。9° で下りて着地台の上を 8.5 m で越え、
## 機首を起こして先（約 s＝78）に着水する。
const P_APPROACH := {"start_s": -200.0, "anchor_s": 0.0, "anchor_h": 6.0, "glide_deg": 8.0, "flare_s": -10.0, "touch_deg": 2.5,
	"v_app": 40.0, "v_td": 32.5, "slow_from": -40.0, "turn_deg": 4.0, "turn_from": -260.0, "turn_to": -40.0, "alpha_deg": 6.5,
	"turb": 0.8, "duration": 20.0, "reverse_decel": 8.5}
## 着水して止まったら、そのまま逆推力で後ろ向きに加速して着地台まで戻る（時間を飛ばさない）。戻ってくる機体が s ＝ P_CRANE_S まで
## 来たら、カメラは着地台の斜めうしろの低い所へ動きながら追う。
const P_BACK_SPEED := 2.6
const P_BACK_ACCEL := 1.4
const P_BACK_BRAKE := 2.4
## 待つ所（スロープの端が浮き輪に載る所からさらに先、m）と、迎えが始まってから下がり始めるまで（秒）
const P_WAIT := 8.0
const P_BACK_DELAY := 0.6
const P_CRANE_S := 60.0
const P_CRANE := 1.6
## スロープを下ろし始める（止まる何秒前）・2 人が駆け出す（止まってから。P1 が先）。
const P_RAMP_LEAD := 1.8
const P_RUN := [2.85, 3.03]
## 止まってから着地台の人形を本物のアバターに替える（カメラが機内へ入る前に。駆け出すのは P_RUN）
const P_RELEASE := 0.15
const P_LIMIT := 75.0
## 迎えで機内へ入るカメラが、駆け込む人を待つ所（スロープの付け根の後ろの上。機体のローカル）
const PICKUP_LEAD_IN := Vector3(0.0, 3.0, 5.6)
## 着地台の中心から見た、機体の進む向き（+X から +Z へ 80°。ハシゴ（±X）とテレビカメラ（−Z）をよける）。着水して止まるまで
## 約 150 m 進むので、島（SkyFallIslands。25° の向きは約 110 m 先が島）のない開けた海の向きにする。
const P_DOCK_ANGLE := 1.3963
## 着地台の浮き輪の真ん中の半径（スロープの端を載せる。浮き輪の上面は海から 0.8 m）。
const TUBE_R := 3.6

# ------------------------------------------------------------------ 帰還（heli_drop.md 2.3。秒は雲の覆いのあとから）
## 勝者がスロープの端を離れる時刻、そのときの速さ、それまでに下りてくる高さと長さ。
const H_LEAVE := 3.4
const H_SPEED := 9.0
const H_HIGH := 15.0
const H_DESCENT := 2.6
const H_CLIMB_AFTER := 0.8
## 勝者が離れたあとの加速と、旋回の横の加速度（m/秒²）。
const H_ACCEL := 6.0
const H_TURN_ACCEL := 1.6
## 着地する点：自分の台のゴールの側（機体はゴールの側から台の上を通り、コースの側へ抜ける。スロープはゴールの側を向く）。
const H_LAND_Z := 1.6
## 雲の層の中から台座までの道のり（m）と、離れる何秒前にスロープを開けるか
const H_FROM := 150.0
const H_RAMP_LEAD := 6.5
## 離れる何秒前にベルトを外して立つか（立って、スロープの端の手前まで歩いて待つ）
const H_UNBUCKLE_LEAD := 6.8
## 機内にカメラがあるとき、雲の白さをかけ始める距離（閉じたスロープまでの機内には霧をかけない）
const CABIN_FOG_START := 13.5
## 雲の中の入れ替えで、画の環境（空の明るさ・まわりの光・霧）と雲の明暗の太陽を寄せる長さ（秒）
const ENV_BLEND := 2.0
## 帰還（入れ替えた直後）：赤いジャンプ灯をつける時刻
const H_RED_AT := 1.5
## 雲の中の入れ替えのあと、運んだ前の画から新しい場面の画へ寄せる長さ（秒）
const CARRY_BLEND := 1.2
## 雲の中の入れ替えのあと、機体の傾き（離水のあとの旋回のバンクなど）を新しい場面の姿勢へ戻す長さ（秒）
const ATTITUDE_BLEND := 1.6
## 雲の中では日の光が届かない：カメラの層の中の深さがこの範囲で、舞台の太陽を弱めて消す（入れ替えで機体の向きと
## 太陽の向きの関係が変わっても、いちばん深い所では日の光がないので機内の明暗が飛ばない）
const SUN_IN_CLOUD := Vector2(0.3, 0.86)
## 通過の録音（fp_flyby）の頭から、いちばん近づいた（大きい）所まで（秒）。機体が真上を通る時刻にここが来るように鳴らす
## （乗り込みでは台座の真上を通るのが約 1.3 秒）。
const FLYBY_PEAK := 1.2
## 推力の音（FloatplaneSound.thrust）：巡航・降下（一定で飛ぶ）と帰還（台座の上を低く通ってから上がる）
const CRUISE_THRUST := 0.55
const HOME_THRUST := 0.75

var director: HeliSuddenDeathDirector = null
var plane: SuddenDeathFloatplane = null
## 機体のエンジンの音（乗り込みから帰還まで有効。hide_all で止める）
var sound: FloatplaneSound = null
var gate: StandGate = null
var lift: FloorEdgeLift = null

var _scene := ""
var _t := 0.0
var _cues := {}
var _runners := {}
var _rng := RandomNumberGenerator.new()
var _jump_memory := {}
var _podium := Vector3.ZERO
var _gap_z := 0.0
var _dock := Transform3D.IDENTITY
var _edge_ground_local := Vector3(0.0, 0.81, 7.61)
var _ramp_slope := tan(deg_to_rad(20.0))
var _drop_base := Transform3D.IDENTITY
var _handover_at := 0.0
var _first := 1
var _short := false
## 短い降下を暗転のあとから始める（ラウンドの間の迎えをやめた。2026-10-20）：機内の画から切って入る。
var _short_cut := false
var _float: LandingFloat = null
var _pickup_players: Array[int] = []
var _on_release := Callable()
var _released := false
var _home := {}
var _after := -1.0
## 降下の追いかけのカメラ（自分でなめらかに寄せて、監督にはそのまま渡す）。
var _chase := Transform3D.IDENTITY
var _chase_ready := false
var _last_delta := 0.0
var _fall_center := Vector3.ZERO
## 離着水の動き（今の道すじ）と、その場面の枠・止める所の s。
var _flight: FloatplaneFlight = null
var _frame := Transform3D.IDENTITY
var _dock_s := 0.0
## 乗り込み・迎えの段："approach"（進入〜着水〜減速）→ "back"（後ろ向きに寄せる）→ "cabin"（機内・動き出し）→ "takeoff"。
var _step := ""
## 戻ってくる機体を追ってカメラが動き始める時刻（後ろ向きの道すじを作ったときに決まる）。
var _crane_at := INF
var _stop_at := INF
## プロペラの風が水面を打つ強さ（0〜1）と、その向き（逆推力）。
var _thrust := 0.0
var _reverse := false
var _wake: FloatplaneWake = null
## カメラを持つ人：狙う点をばねで追う（急に振らない）。
var _op_aim := Vector3.ZERO
var _op_vel := Vector3.ZERO
var _op_ready := false
## カメラ（カットなし）・雲の層・後ろの扉の光
var _lens: RefCounted = null
var _cloud: Node3D = null
## 名前ごとの狙う点のばね・機体を追うカメラ（機体の向きの枠の中の位置）
var _aims := {}
var _chase_local := Vector3(-16.0, 5.0, 4.0)
## 巡航：雲から上へ抜ける間の機体の動き・カメラが機内に入ったか・降下を始めてよいか
var _cruise := {}
var _cruise_cam_inside := false
var _cruise_ready := false
var _lead_vel := 0.0
## 空の揺れの時計（巡航から降下へ続ける）
var _sway_t := 0.0
var _sway_base := 0.0
var _expo_value := 1.0
var _scene_was := ""
## カメラの体へ渡す揺れの元（_feel）：水の上か・水の上の速さ（_place_flight が決める）、被写体の機体の中心の前のフレームの位置と速さ
var _wet := false
var _water_v := 0.0
var _feel_prev := Vector3.INF
var _feel_vel := Vector3.ZERO
## 雲の中の入れ替えのあと、画の環境を寄せている間の環境（_blend_environment）
var _env_blend: Environment = null
## 「SPACE でスキップ」の表示（fp_skip_hint.gd）
var _skip_hint: CanvasLayer = null
var _env_keys: Array = []
var _env_final: Environment = null
var _env_t := 0.0
var _env_len := 0.0
## 雲の中の入れ替えの前の機体の姿（短い降下は enter_short_drop で覚えて begin_drop で使う）
var _swap_from := Transform3D.IDENTITY
var _swap_pending := false
## 入れ替えで運んだ機体の傾き（新しい場面の姿勢から見た回転）と、それが消える時刻（場面の _t。−1＝なし）
var _att_offset := Basis.IDENTITY
var _att_until := -1.0
## 雲の中で弱めているもの（_apply_cloud_light）：名前 → {"target", "prop", "param", "base", "applied"}
var _dims := {}
## 舞台の地面の照り返しの光（StageAtmosphere の GroundBounce）と画面のふちの暗さ（ビネットの材質）
var _bounce_light: DirectionalLight3D = null
var _vignette_material: ShaderMaterial = null
var _atmosphere_looked := false
## 環境を寄せている間の空（入れ替えの前の空の数値から寄せる）
var _sky_blend: ShaderMaterial = null
var _sky_keys: Array = []


func setup(owner_director: HeliSuddenDeathDirector) -> void:
	director = owner_director
	# 雲の中の太陽の弱め（_process）は、舞台の天気（太陽を毎フレーム決める）のあとに当てる
	process_priority = 100
	name = "FloatplaneStaging"
	_rng.randomize()
	# 「SPACE でスキップ」：監督が飛ばせる間だけ右下に出す（c130_float.md 12 章）
	if _skip_hint == null:
		_skip_hint = SkipHint.new()
		add_child(_skip_hint)


## 試合の頭（読み込みの覆いの下）。機体を作って隠しておく。水路の素材も読んでおく。
func build(quality: String) -> void:
	if plane == null:
		plane = SuddenDeathFloatplane.new()
		plane.name = "SkyGateFloatplane"
		add_child(plane)
		plane.build(quality)
		# スロープを着地台に下ろしたときの端（ローカル）
		plane.set_ramp(SuddenDeathFloatplane.RAMP_GROUND)
		_edge_ground_local = plane.global_transform.affine_inverse() * plane.ramp_edge_now()
		_ramp_slope = maxf(0.05, (CABIN_FLOOR - _edge_ground_local.y) / maxf(_edge_ground_local.z - HINGE_Z, 0.1))
		plane.set_ramp(0.0)
		plane.visible = false
	if sound == null and plane != null:
		sound = FloatplaneSound.new()
		plane.add_child(sound)
		sound.setup(plane)
	if _wake == null:
		_wake = FloatplaneWake.new()
		add_child(_wake)
	if _lens == null:
		_lens = Lens.new(director)
	_lens.set("quality", quality)
	_lens.set("subject", plane)
	if _cloud == null:
		_cloud = CloudPass.new()
		add_child(_cloud)
	_cloud.call("build", quality)
	StandGate.glb_mesh("SG_Tower")
	StandGate.glb_mesh("SG_LiftDeck")


func is_built() -> bool:
	return plane != null and plane.is_built()


func scene() -> String:
	return _scene


func hide_all() -> void:
	_scene = ""
	_end_environment_blend()
	_swap_pending = false
	_restore_cloud_light()
	_restore_sky_sea()
	if plane != null:
		plane.visible = false
		plane.set_props(0.0)
		plane.set_pontoon_spray(0.0)
	if sound != null:
		sound.set_enabled(false)
	if _wake != null:
		_wake.clear()
	if _cloud != null:
		_cloud.call("clear_deck")
	_set_exposure(1.0, false)
	_flight = null
	_feel_prev = Vector3.INF
	_feel_vel = Vector3.ZERO
	restore_gate()


func restore_gate() -> void:
	if gate != null:
		gate.restore()
		gate.queue_free()
		gate = null
	if lift != null:
		lift.restore()
		lift = null


# ================================================================== 乗り込み（BOARD）

## 決着演出の間（分岐の 9.6 秒ごろ）：台座の横のスタンドを持ち上げる準備（海面より下を切った写しに替える）と、床の横の壁の
## 昇降台（しまった姿。壁の設備に見える）。どちらもこのときのカメラ（床の上から台座を見る）からは見えない。
func prepare_gate(stage_env: Node, podium: Vector3) -> void:
	_podium = podium
	if gate == null:
		# 結果発表アリーナ（ResultArena）ではコースの客席を隠しているので、客席の水門は作らない（水上機は沖からそのまま入る）。
		var stands_shown: bool = stage_env == null or not stage_env.has_method("is_course_visible") or bool(stage_env.call("is_course_visible"))
		if stands_shown:
			gate = StandGate.new()
			add_child(gate)
		if gate == null or not gate.setup(stage_env, podium, 1.0):
			if gate != null:
				gate.queue_free()
			gate = null
			_gap_z = podium.z
		else:
			gate.activate()
			_gap_z = gate.gap_center_z()
	if lift == null:
		lift = FloorEdgeLift.new()
		add_child(lift)
		lift.setup(_gap_z, 1.0)
		lift.set_target_y(SEA_Y + CABIN_FLOOR - LIFT_TOE)
	# 離水して上がっていく先（+X の沖）の低い雲の層。決着演出と種目発表の画（+X の空は映らない）のあいだにゆっくり現れる。
	if _cloud != null and not _cloud.call("has_deck"):
		var dock_x := StageConstants.FLOOR_HALF_WIDTH + 0.5 + 11.45
		_cloud.call("place_deck", Vector3(dock_x + 600.0, 0.0, _gap_z), SEA_Y + CLOUD_BOTTOM, SEA_Y + CLOUD_TOP, Vector2(900.0, 760.0),
			Vector3(1.0, 0.0, 0.0), _stage_sun(), 3, 4.0)


## 審判の「乗りこめー！」。runners の 2 人は監督が決着演出の姿から受け取った人形（立っている）。カメラは今の画（種目発表の引き）から寄せる。
func begin_board(podium: Vector3) -> void:
	_podium = podium
	prepare_gate(director.stage_env, podium)
	_scene = "board"
	_t = 0.0
	_cues.clear()
	_aims.clear()
	# 止める位置：尾の端を床の壁から 0.5 m に。道すじの枠は台座の中心の海面、機首は +X（s ＝ ワールドの x）。
	var tail := plane.marker_local("MK_TailEnd").origin.z
	_dock = Transform3D(_nose_out(), Vector3(StageConstants.FLOOR_HALF_WIDTH + 0.5 + tail, SEA_Y, _gap_z))
	_frame = Transform3D(_nose_out(), Vector3(0.0, SEA_Y, _gap_z))
	_dock_s = _dock.origin.x
	var edge := _dock * Vector3(0.0, CABIN_FLOOR, EDGE_Z)
	lift.set_reach(edge.x)
	lift.set_target_y(edge.y - LIFT_TOE)
	plane.visible = true
	plane.set_ramp(0.0)
	plane.set_upper_door(0.0)
	plane.set_flaps(1.0)
	plane.set_jump_light("off")
	plane.set_cabin_lighting("day")
	plane.snap_props(1.0)
	plane.set_pontoon_spray(0.0)
	if plane.pilot != null:
		plane.pilot.play(&"steer")
	for player: int in [1, 2]:
		plane.set_belt(player, false)
	_flight = FloatplaneFlight.landing(_frame, 0.0, B_APPROACH)
	_step = "approach"
	_crane_at = INF
	_stop_at = INF
	_op_ready = false
	_reset_wake(_stage_ocean())
	plane.clear_water_fx()
	_place_flight(0.0, 0.0)
	for player: int in [1, 2]:
		var puppet := director.puppet(player)
		var pelvis := puppet.parts().get("pelvis") as Node3D
		var pad := pelvis.global_position if pelvis != null else podium + Vector3(2.2 * _side(player), 0.0, 0.0)
		var walker := Walker.new(puppet)
		var pad_y := pad.y - 0.95
		walker.feet = Vector3(pad.x, pad_y, pad.z)
		walker.yaw = PI
		walker.ground = func(_feet: Vector3) -> float: return pad_y
		_runners[player] = {"phase": "wait", "t": 0.0, "walker": walker, "pad_y": pad_y}
	_lens.seed(0.9)
	_chase_ready = false
	if sound != null:
		sound.thrust = 0.0
		sound.set_enabled(true)
	# 01：サイレンとともに、台座の横のスタンドが塔で持ち上がる
	AudioManager.play_sfx(&"sd_siren", -8.0)
	AudioManager.play_sfx(&"sd_stand_lift")


func update_board(delta: float) -> String:
	_t += delta
	_lens.advance(delta)
	var t := _t
	# 機体：進入〜着水〜減速 → 後ろ向きに寄せる → 止まる →（2 人が座ったら）動き出して離水・上昇
	if _step == "approach" and t >= _flight.stop_at:
		_begin_back(B_BACK_SPEED, B_BACK_ACCEL, B_BACK_BRAKE, INF)
	_place_flight(t, delta)
	_board_sounds(t)
	_update_stand(delta)
	var stop_known := is_finite(_stop_at)
	# 昇降台：止まる B_LIFT_DEPLOY 秒前に起こす。2 人が乗ったら下ろす。機体が離れたら（尾翼がデッキの上から抜けたら）しまう。
	if lift != null:
		if stop_known and t >= _stop_at - B_LIFT_DEPLOY and _cue("lift_deploy"):
			lift.deploy()
			# デッキが起きる（FloorEdgeLift.SWING_TIME 2.0 秒）モーター
			AudioManager.play_sfx(&"sd_tower_move", -4.0, 1.1)
		var riders := 0
		for player: int in [1, 2]:
			if str((_runners[player] as Dictionary).phase) in ["ride", "to_wait", "watch", "board", "turn", "sit", "belt", "seated"]:
				riders += 1
		if riders == 2 and lift.is_deployed() and _cue("lift_lower"):
			lift.start_lower()
			# 2 人を乗せて 6.1 m 下りる（LOWER_TIME 3.2 秒）
			AudioManager.play_sfx(&"sd_stand_lower", -4.0, 1.1)
		if _step in ["depart", "takeoff"] and plane.global_position.x - _dock_s > 7.0 and _cue("lift_return"):
			lift.start_return()
		lift.advance(delta)
	# スロープと上のふた：寄せている間に上のふたを開け、スロープを途中まで（デッキの上を越えられる角度）。止まったら下ろしきる。
	if stop_known and not _cues.has("close"):
		var half := smoothstep(_stop_at - B_DOOR.x, _stop_at - B_DOOR.y, t)
		var set := smoothstep(_stop_at + B_RAMP_SET.x, _stop_at + B_RAMP_SET.y, t)
		plane.set_upper_door(half)
		plane.set_ramp(half * B_RAMP_HALF + set * (1.0 - B_RAMP_HALF))
		if half > 0.0 and _cue("door_open"):
			AudioManager.play_sfx(&"sd_servo", -2.0, 0.75)
			AudioManager.play_sfx(&"fp_ramp", -3.0, 0.9)
		if set > 0.0 and _cue("ramp_down"):
			AudioManager.play_sfx(&"fp_ramp")
	# 2 人
	var seated := 0
	for player: int in [1, 2]:
		var state := _update_board_runner(player, delta)
		if state in ["belt", "seated"]:
			seated += 1
	# 機内：2 人がベルトを締め始めたらスロープを閉め、推力を上げて動き出す
	if seated == 2 and _cue("close"):
		plane.set_jump_light("red")
		AudioManager.play_sfx(&"fp_ramp", 0.0, 0.88)
	if _cues.has("close"):
		var c := t - float(_cues.close)
		var u := 1.0 - FloatplaneFlight._ss5(c / B_CLOSE)
		plane.set_ramp(u)
		plane.set_upper_door(u)
		if c >= B_SPOOL_AT and _cue("depart"):
			_begin_departure()
		if c >= B_CLOSE - 0.12 and _cue("ramp_latch"):
			AudioManager.play_sfx(&"fp_ramp_latch")
			# スロープが閉まりきる「ガコン」（機内のカメラに一瞬の揺れ）
			_lens.kick(0.32)
	_update_exposure(delta)
	_feel(delta)
	_board_camera(t, delta)
	_cloud.update(_lens.eye, delta)
	# 雲の層のいちばん深い所で、空のセットへ入れ替える（監督が _enter_sky を呼ぶ）
	if _step == "takeoff" and _cloud.depth >= 0.93 and plane.global_position.y >= SEA_Y + CLOUD_BOTTOM and _cue("swap"):
		return "swap"
	if t >= B_LIMIT and _cue("limit"):
		return "cover"
	return ""


## 着水して止まった所から、逆推力で後ろ向きに加速して戻り、止める所でなめらかに止める（FloatplaneFlight.dock）。
## 姿勢（機首・沈み）は止まった瞬間から引き継ぐ。crane_s は戻ってくる機体を追ってカメラが動き始める s。
func _begin_back(speed: float, accel_time: float, brake: float, crane_s: float) -> void:
	var now := _flight.sample(_t)
	var state := {"pitch": float(now.pitch), "d": float(now.d), "pitch_rate": 0.0, "d_rate": 0.0}
	_flight = FloatplaneFlight.dock(_frame, _t, {"from_s": float(now.s), "to_s": _dock_s, "speed": speed, "brake": brake,
		"accel_time": accel_time, "duration": 60.0, "wander": 0.8, "state": state})
	_stop_at = _flight.stop_at
	_crane_at = _flight.time_at_s(crane_s) if is_finite(crane_s) else INF
	_step = "back"
	# 止まる時刻はここで初めて決まる（カメラの動き出しはこれより前にしない。途中から始まって画がとばない）
	_cues["back_at"] = _t


## 推力を上げて止まった所から動き出し、水路を出て加速し、離水して上がる（時間を飛ばさない）。
func _begin_departure() -> void:
	var state := {}
	if _flight != null:
		var now := _flight.sample(_t)
		state = {"pitch": float(now.pitch), "d": float(now.d)}
	var spec := B_DEPART.duplicate()
	spec["from_s"] = _dock_s
	spec["state"] = state
	_flight = FloatplaneFlight.departure(_frame, _t, spec)
	_step = "depart"
	if plane.pilot != null:
		plane.pilot.play(&"steer")


## 持ち上げたスタンド：「乗りこめー！」で上がり、機体の尾が外へ出たら下りて、塔が海へしずむ。
func _update_stand(delta: float) -> void:
	if gate == null:
		return
	var t := _t
	gate.set_towers(smoothstep(B_TOWERS.x, B_TOWERS.y, t))
	var up := smoothstep(B_LIFT.x, B_LIFT.y, t)
	if _step in ["depart", "takeoff"] and plane.global_position.x - plane.marker_local("MK_TailEnd").origin.z > STAND_CLEAR_X and _cue("stand_down"):
		AudioManager.play_sfx(&"sd_stand_lower", -2.0, 0.9)
	if _cues.has("stand_down"):
		var since := t - float(_cues.stand_down)
		up = 1.0 - FloatplaneFlight._ss5(since / 3.4)
		gate.set_towers(1.0 - smoothstep(3.6, 7.5, since))
	gate.set_lift(up)
	if delta < 0.0:
		pass


## 今の道すじで機体を置き、プロペラ・フラップ・しぶき・航跡を合わせる。
func _place_flight(t: float, delta: float) -> void:
	if _flight == null:
		return
	# スロープを床や浮き輪に載せている間は、波の揺れを小さく（なめらかに切り替える）
	var bob := 1.0
	if _step == "back":
		bob = lerpf(1.0, 0.35, smoothstep(_stop_at - 0.9, _stop_at + 0.4, t))
	elif _step == "depart":
		bob = lerpf(0.35, 1.0, smoothstep(_flight.t0, _flight.t0 + 1.5, t))
	var sample := _flight.sample(t, bob)
	plane.global_transform = sample.xf
	_flight_controls(t, sample)
	if sound != null:
		# 空中（進入・上昇）は水を打つ風がないので _thrust は 0：音はプロペラの回転いっぱいの推力で鳴らす
		sound.thrust = _thrust if bool(sample.wet) else (0.85 if _step == "takeoff" else 0.6)
	var wet := bool(sample.wet)
	var v := float(sample.v)
	_wet = wet
	_water_v = v if wet else 0.0
	var since_td := t - _flight.touchdown_at
	var burst := 0.0
	if since_td >= 0.0 and since_td < 0.7:
		burst = pow(1.0 - since_td / 0.7, 2.0) * clampf(_flight.touchdown_sink / 1.4, 0.6, 1.3)
	var drip := 0.0
	var since_lof := t - _flight.liftoff_at
	if since_lof >= 0.0:
		drip = 1.0 - smoothstep(0.0, 1.8, since_lof)
		if _step == "depart":
			_step = "takeoff"
	# 水面の近く（段が水から 1.5 m まで）でだけ、プロペラの風が水を舞い上げる
	var near := 1.0 if wet else clampf(1.0 + (float(sample.d) + 0.5) / 1.5, 0.0, 1.0)
	plane.set_water_fx(v if wet else 0.0, _thrust * near, _reverse, burst, drip)
	if _wake != null:
		_wake.advance(delta, sample.xf, v, wet, burst)


## 段ごとのプロペラ（回転と逆推力）・フラップ・水を打つ風の強さ。
func _flight_controls(t: float, sample: Dictionary) -> void:
	var v := float(sample.v)
	match _step:
		"approach":
			var since_td := t - _flight.touchdown_at
			if since_td < 0.25:
				# 進入：回転は一定（羽根の角度で力を変える）、フラップは下げきり
				plane.set_props(1.0, false)
				_thrust = 0.0
				_reverse = false
			else:
				# 着水したら逆推力いっぱい（前へ水しぶきの霧）
				plane.set_props(1.0, true)
				_thrust = 0.9 * smoothstep(0.25, 0.7, since_td)
				_reverse = true
			plane.set_flaps(1.0)
		"back":
			if v < -0.4:
				# 後ろ向きに速く下がるあいだは逆推力いっぱい（前へ霧）
				var hard := smoothstep(2.0, 8.0, -v) if float(sample.a) <= 0.05 else 0.3
				plane.set_props(lerpf(0.72, 1.0, hard), true)
				_thrust = lerpf(0.45, 0.9, hard)
				_reverse = true
			elif t < _stop_at + 0.6:
				# 止める：羽根を戻して少し前へ押す
				plane.set_props(0.5, false)
				_thrust = 0.25
				_reverse = false
			else:
				plane.set_props(0.32, false)
				_thrust = 0.0
				_reverse = false
		"depart":
			var power := smoothstep(_flight.t0, _flight.t0 + 1.8, t)
			plane.set_props(lerpf(0.32, 1.0, power), false)
			_thrust = power
			_reverse = false
			plane.set_flaps(0.5)
		"takeoff":
			plane.set_props(1.0, false)
			_thrust = 1.0 if bool(sample.wet) else 0.0
			_reverse = false
			var since_lof := t - _flight.liftoff_at
			plane.set_flaps(lerpf(0.5, 0.15, smoothstep(0.8, 4.0, since_lof)) if since_lof > 0.0 else 0.5)


## 乗り込みの単発の音。エンジン・逆推力・離水の加速はエンジンの音（FloatplaneSound）が回転と推力で鳴らす。
func _board_sounds(t: float) -> void:
	# 02：台座と 2 人の真上を低く越える（通過の録音のいちばん大きい所を、真上を通る時刻に合わせる）
	if _step == "approach" and _flight != null and _cue("flyby_at"):
		_cues["flyby_time"] = maxf(0.0, _flight.time_at_s(_podium.x) - FLYBY_PEAK)
	if _cues.has("flyby_time") and t >= float(_cues.flyby_time) and _cue("flyby"):
		AudioManager.play_sfx(&"fp_flyby")
		if sound != null:
			sound.duck_for(FLYBY_PEAK + 1.6)
	if t >= _flight_touchdown() and _cue("splash"):
		AudioManager.play_sfx(&"fp_touchdown", 0.0, 0.78)
		# 着水の打ちつけ：望遠で見ている撮る人が一瞬びくっとする（遠いほど小さく）
		_lens.kick(0.42 * (1.0 - smoothstep(20.0, 160.0, (_lens.get("eye") as Vector3).distance_to(plane.global_position))) + 0.12)


## 進入の道すじの着水の時刻（後ろ向きの道すじへ替えたあとは、もう鳴らした）。
func _flight_touchdown() -> float:
	return _flight.touchdown_at if _flight != null and _step == "approach" else INF


## 1 人の乗り込み：台座 → 床の端の手すりをまたいで昇降台へ → 手すりの近くで一緒に下りる → 尾の通り道の真ん中で待つ
## → スロープを駆け上がって機内へ（減速して止まる）→ 通路へ向き直る → ベンチに腰を下ろす → ベルト。返り値は今の段。
func _update_board_runner(player: int, delta: float) -> String:
	var r: Dictionary = _runners[player]
	var walker: RefCounted = r.walker
	var puppet := director.puppet(player)
	r.t = float(r.t) + delta
	var side := _side(player)
	match str(r.phase):
		"wait":
			walker.call("stand", delta)
			if is_finite(_stop_at) and _t >= _stop_at - float(B_RUN_LEAD[player - 1]):
				var wall := StageConstants.FLOOR_HALF_WIDTH
				var edge_pt := Vector3(wall - 0.7, FLOOR_Y, _gap_z + 1.15 * side)
				var ride := lift.deck_spot(DECK_RIDE.x, DECK_RIDE.y * side)
				walker.set("ground", _board_ground)
				walker.call("set_path", [edge_pt, Vector3(ride.x, FLOOR_Y, ride.z)], B_RUN_SPEED, Walker.RUN)
				r.phase = "run"
		"run":
			if walker.call("step", delta):
				r.phase = "ride"
				walker.set("idle_clip", "Idle_Rail_Loop")
				walker.set("idle_slot", AnimationRig.SLOT_UAL2)
				walker.set("ground", _lift_ground)
		"ride":
			# 手すりの方を向いてつかまる（P1 は +Z の手すり）。デッキが下りる・止まるとき、体が少し沈む。
			var face := 0.0 if side > 0.0 else PI
			walker.call("turn_to", face, delta, 2.6)
			var dip := clampf(lift.vertical_accel() * 0.07, -0.25, 0.3)
			walker.set("extra_lean", -absf(dip) * 0.25)
			if lift.is_lowered() and not lift.busy():
				walker.set("idle_clip", "Idle_Loop")
				walker.set("idle_slot", AnimationRig.SLOT_UAL)
				walker.set("extra_lean", 0.0)
				var wait := lift.deck_spot(DECK_WAIT.x, DECK_WAIT.y * side)
				walker.call("set_path", [wait], 1.25, Walker.RUN)
				r.phase = "to_wait"
		"to_wait":
			if walker.call("step", delta):
				r.phase = "watch"
		"watch":
			# 寄ってくる機体の方（+X）を向いて待つ。尾が頭の上を通るときは少し身をかがめる。
			walker.call("turn_to", PI * 0.5, delta, 2.0)
			var tail_x := plane.global_position.x - plane.marker_local("MK_TailEnd").origin.z
			var over := smoothstep(17.0, 15.5, tail_x) * (1.0 - smoothstep(13.6, 12.8, tail_x)) if _step == "back" else 0.0
			walker.set("idle_clip", "Crouch_Idle_Loop" if over > 0.5 else "Idle_Loop")
			if is_finite(_stop_at) and _t >= _stop_at + float(B_BOARD_GO[player - 1]):
				walker.set("idle_clip", "Idle_Loop")
				var xf := plane.global_transform
				var lane := LANE_X * side
				var seat := plane.marker_local("MK_SeatP1" if player == 1 else "MK_SeatP2")
				var front := Vector3(seat.origin.x - SIT_REACH * side, CABIN_FLOOR, seat.origin.z)
				walker.set("ground", _cabin_ground)
				walker.call("set_path", [xf * Vector3(lane, CABIN_FLOOR, EDGE_Z - 0.4), xf * Vector3(lane, CABIN_FLOOR, HINGE_Z - 0.8),
					xf * Vector3(lane + 0.25 * side, CABIN_FLOOR, front.z + 0.9), xf * front], B_IN_SPEED, Walker.RUN)
				r.phase = "board"
		"board", "turn", "sit", "belt", "seated":
			return _update_seat_runner(player, delta)
	return str(r.phase)


## 乗り込みの足もと：床 → 床の端の手すり（高さ 0.26 m）をまたいで跳ぶ → 昇降台のデッキ。
func _board_ground(feet: Vector3) -> float:
	var wall := StageConstants.FLOOR_HALF_WIDTH
	var x := feet.x
	var y := FLOOR_Y
	if x > wall - 0.62 and x < wall + 0.32:
		y += 0.36 * sin(PI * (x - (wall - 0.62)) / 0.94)
	if x >= wall and lift != null:
		y = maxf(y, lift.top_point().y)
	return y


## 昇降台の上の足もと（デッキが下りるとき一緒に）。
func _lift_ground(_feet: Vector3) -> float:
	return lift.top_point().y if lift != null else FLOOR_Y


## スロープから機内の足もと：デッキの上 → スロープ（水平）→ 貨物室の床。
func _cabin_ground(feet: Vector3) -> float:
	var xf := plane.global_transform
	var local := xf.affine_inverse() * feet
	var cabin := (xf * Vector3(local.x, CABIN_FLOOR, local.z)).y
	if local.z > EDGE_Z - 0.05 and lift != null:
		return lerpf(cabin, lift.top_point().y, smoothstep(EDGE_Z - 0.05, EDGE_Z + 0.2, local.z))
	return cabin


## 乗り込みのカメラ（カットなし。c130_float.md 第10章）：
##   台座の左うしろの高め（01）→ 床へ下りながら頭の上を越える機体を見上げる（02）→ 床の端へ動いて、沖に着水して止まる機体を追う
##   → 水路の上（床の端の外の高め）へ動き、起きる昇降台・駆けてくる 2 人・下りる昇降台・後ろ向きに寄ってくる機体を一つの画に
##   → 尾の横を下りて 2 人の前（スロープの付け根）へ回り、駆け込む 2 人の前を後ろ向きに機内へ入って、操縦席の段の上で止まる（07）
##   → 動き出したら、そのまま前へ下がって操縦席の窓から外へ抜け、横へ回って離水・上昇を追い、雲の層へ入る。
func _board_camera(t: float, delta: float) -> void:
	var z := _gap_z
	var lift_eye := Vector3(-7.0, 7.0, z - 27.0)
	var lift_aim := Vector3(26.0, 2.0, z + 5.0)
	var shot := {"eye": lift_eye, "aim": lift_aim, "fov": 58.0}
	var name := "board_lift"
	if t >= B_FLYOVER:
		# 02：床へ下りながら、頭の上を越えていく機体を見上げて追う（カメラを持つ人は機体を追い続ける）
		if not _op_ready:
			_operator(lift_aim, delta, true)
		var aim := _operator(_lead_point(t, Vector3(0.0, 3.0, 0.0), 4.5), delta, false, 4.5)
		var k := smoothstep(B_FLYOVER, B_FLYOVER + 0.7, t)
		var fly := {"eye": lift_eye.lerp(Vector3(-6.0, 1.6, z - 26.0), k), "aim": aim, "fov": lerpf(58.0, 64.0, k)}
		# 床の端へ動いて、沖に着水して止まる機体を望遠で追う（遠いほど寄る）。床の端に沿ってゆっくり横へ動き、持ち上げた
		# スタンドの塔の足が手前を流れる（奥行き）。目が水路の中心に寄るので、塔の足が画面のふちにかからない。
		var edge_eye := Vector3(9.2, 1.5, z - 9.5).lerp(Vector3(10.4, 1.2, z - 4.6), smoothstep(1.7, 7.6, t))
		var far := edge_eye.distance_to(plane.global_position)
		var edge := {"eye": edge_eye, "aim": aim, "fov": lerpf(58.0, 15.0, smoothstep(30.0, 150.0, far))}
		shot = Lens.mix(fly, edge, FloatplaneFlight._ss5((t - 1.7) / 2.6))
		name = "board_flyover" if t < 2.6 else "board_splash"
		if t >= 2.6:
			# 望遠の間はピントを機体に（狙う点は余白のぶんずれる）
			_lens.focus_on(plane.global_transform * Vector3(0.0, 2.0, 0.0))
		var stop_known := is_finite(_stop_at)
		if stop_known:
			var mid := _board_backin_camera(t, shot, delta)
			if not mid.is_empty():
				shot = mid
				name = String(mid.get("name", name))
			# 昇降台の横から、尾の横を下りてスロープの先の横へ（2 人より先に機内へ）
			var lead_from := _stop_at - 2.4
			if t >= lead_from:
				shot = _board_lead_camera(t, lead_from, shot, delta)
				name = "board_lead" if t < _stop_at + 3.4 else "board_cabin"
	if _cues.has("depart"):
		var dep := float(_cues.depart)
		shot = _board_exit_camera(t, dep, shot, delta)
		var since_dep := t - dep
		if since_dep < 1.1:
			name = "board_cabin"
		elif since_dep < EXIT_PUSH:
			name = "board_cockpit"
		elif since_dep < EXIT_PUSH + EXIT_LEN * 0.85:
			name = "board_exit"
		else:
			name = "board_chase"
	_lens.shoot(shot.eye, shot.aim, float(shot.fov), name)


## 乗り込みの中ほど（機体が沖で止まってから、昇降台が下りきるまで。c130_float.md 第13章）。before は床の端の望遠の画。
##   REVEAL：床の端から後ろの高い所へ引きながら広げる（望遠 → 広角）。後ろ向きに戻ってくる機体・起きる昇降台・台座の 2 人
##   RUN：駆け出した 2 人を後ろから追って床の端へ（2 人は画の下、寄ってくる機体はその奥）
##   RIDE：床の端を越え、2 人を乗せて下りる昇降台の横（水路の上）を一緒に下りる。寄ってくる尾が 2 人の頭の上に来る
## 返り値は {eye, aim, fov, name}（まだ始まっていなければ空）。
func _board_backin_camera(t: float, before: Dictionary, delta: float) -> Dictionary:
	var s := _stop_at
	var reveal_at := maxf(s - B_REVEAL_AT, float(_cues.get("back_at", 0.0)) + 0.2)
	var u_reveal := FloatplaneFlight._ss5((t - reveal_at) / B_REVEAL_LEN)
	if u_reveal <= 0.0:
		return {}
	var z := _gap_z
	var xf := plane.global_transform
	var body := xf * Vector3(0.0, 2.4, 2.0)
	var deck := lift.deck_spot(0.55, 0.0) if lift != null else Vector3(14.0, FLOOR_Y, z)
	var people := (director.puppet(1).center() + director.puppet(2).center()) * 0.5
	# REVEAL：台座の 2 人の後ろの高い所。床の端の昇降台と水路と寄ってくる機体が一直線に並ぶ（奥へ重なる画）
	var reveal_eye := Vector3(REVEAL_EYE.x, REVEAL_EYE.y, z + REVEAL_EYE.z)
	var reveal_target := deck.lerp(body, 0.5).lerp(people, 0.12)
	var reveal := {"eye": reveal_eye, "aim": _smooth_aim("reveal", reveal_target, delta, 2.2), "fov": 42.0}
	# 引きながら広げる：初めは床の端の望遠の画のまま後ろへ下がり、画角は後半で広げる
	var pull := {"eye": Lens.path([before.eye as Vector3, Vector3(2.0, 3.4, z - 7.5), reveal_eye], u_reveal),
		"aim": (before.aim as Vector3).lerp(reveal.aim, FloatplaneFlight._ss5((t - reveal_at) / (B_REVEAL_LEN * 0.8))),
		"fov": lerpf(float(before.fov), 42.0, FloatplaneFlight._ss5((t - (reveal_at + 0.6)) / (B_REVEAL_LEN - 0.6)))}
	var out := pull if u_reveal < 1.0 else reveal
	out["name"] = "board_reveal"
	# RUN：2 人の後ろについて床の端へ（2 人を画の下 1/3 に、寄ってくる機体をその奥に）
	var u_run := FloatplaneFlight._ss5((t - (s - B_RUN_CAM)) / 2.4)
	if u_run > 0.0:
		var run_eye := Vector3(minf(people.x - RUN_CAM_BACK, RUN_CAM_MAX_X), FLOOR_Y + 4.2 - 1.2 * u_run, z + RUN_CAM_Z)
		run_eye.x = maxf(run_eye.x, reveal_eye.x)
		var run_target := people.lerp(body, 0.42) + Vector3(0.0, -0.4, 0.0)
		var run := {"eye": _smooth_point("run_eye", run_eye, delta, 2.6), "aim": _smooth_aim("run", run_target, delta, 3.0), "fov": 46.0}
		out = Lens.mix(out, run, u_run)
		out["name"] = "board_runners"
	# RIDE：昇降台が下り始めたら、床の端を越えてデッキの横を一緒に下りる（デッキの上面から一定の高さ）
	if _cues.has("lift_lower") and lift != null:
		var since := t - float(_cues.lift_lower)
		var u_ride := FloatplaneFlight._ss5(since / 1.6)
		var top := lift.top_point()
		var ride_eye := Vector3(RIDE_EYE.x, top.y + RIDE_EYE.y, z + RIDE_EYE.z)
		var tail := xf * Vector3(0.0, 5.0, 8.6)
		var over := smoothstep(30.0, 16.0, tail.x)
		var ride_target := (people + Vector3(0.0, 0.3, 0.0)).lerp(tail, 0.25 + 0.3 * over)
		var ride := {"eye": ride_eye, "aim": _smooth_aim("ride", ride_target, delta, 3.2), "fov": lerpf(50.0, 58.0, over)}
		# 床の端の上を越える（床の縁と手すりに当たらないよう、いったん上へ）
		var cross := {"eye": Lens.path([out.eye as Vector3, Vector3(11.4, FLOOR_Y + 3.3, z - 5.6), ride_eye], u_ride), "aim": ride.aim,
			"fov": lerpf(float(out.fov), float(ride.fov), u_ride)}
		out = Lens.mix(out, cross, minf(1.0, u_ride * 3.0))
		if u_ride >= 1.0:
			out = ride
		out["name"] = "board_backin"
		_lens.focus_on(people)
	return out


## 点をなめらかに寄せる（名前ごとに別のばね。_smooth_aim と同じ）。
func _smooth_point(key: String, target: Vector3, delta: float, rate: float) -> Vector3:
	return _smooth_aim(key, target, delta, rate)


## 尾の横からスロープの前へ回り、駆け込む 2 人の前を後ろ向きに機内へ入って、操縦席の段の上（MK_CamAft）で止まる。
##   外：昇降台の横（水路の上）→ 尾の横（水平尾翼より外・下）→ スロープの先の左の横（浮き舟の上、デッキの手すりの外）
##   2 人がまだ待っているうちに、胴体の下の縁の下をくぐってスロープの上（通り道の真ん中）へ入り、待つ 2 人を前から見る
##   駆け出したら、先の人から LEAD_GAP m 前を保って後ろ向きに下がり（付け根 → 貨物室）、2 人が座ると操縦席の段の上で止まる
func _board_lead_camera(t: float, from: float, before: Dictionary, delta: float) -> Dictionary:
	var xf := plane.global_transform
	var s := _stop_at
	var side := xf * LEAD_SIDE
	var start := before.eye as Vector3
	var points := [start, start.lerp(side, 0.5) + Vector3(0.0, 0.25, 0.0), side]
	if start.x < StageConstants.FLOOR_HALF_WIDTH + 0.5:
		# まだ床の上（昇降台が遅れた）：床の縁の外へ出てから下りる（壁を通り抜けない）
		points = [start, Vector3(StageConstants.FLOOR_HALF_WIDTH + 0.9, FLOOR_Y + 2.0, start.z), side]
	var u := FloatplaneFlight._ss5((t - from) / 2.0)
	var people := (director.puppet(1).center() + director.puppet(2).center()) * 0.5
	var aim := (before.aim as Vector3).lerp(people + Vector3(0.0, 0.2, 0.0), FloatplaneFlight._ss5((t - from) / 1.4))
	var out := {"eye": Lens.path(points, u), "aim": aim, "fov": lerpf(float(before.fov), 62.0, u)}
	_lens.focus_on(people)
	# くぐってスロープの上へ（待っている 2 人の 2.7 m 前）。2 人はスロープが下りきってから駆け出す。
	var into := s - 0.4
	if t >= into:
		var v := FloatplaneFlight._ss5((t - into) / 1.3)
		var under := [xf * LEAD_SIDE, xf * Vector3(-1.2, 2.5, 7.15), xf * Vector3(-0.4, 2.85, 6.7), xf * LEAD_IN]
		out = {"eye": Lens.path(under, v), "aim": people + Vector3(0.0, 0.1, 0.0), "fov": 62.0}
		if not _cues.has("lead_z"):
			_cues["lead_z"] = LEAD_IN.z
			_lead_vel = 0.0
		# 駆け出したら、先の人から LEAD_GAP m 前を保って下がる（ばねで追う。2 人が座ったら操縦席の段の上まで）
		if v >= 1.0:
			var cam_aft := plane.marker_local("MK_CamAft")
			var lead := INF
			var lead_speed := 0.0
			var settled := 0
			for player: int in [1, 2]:
				var r: Dictionary = _runners[player]
				var local := xf.affine_inverse() * director.puppet(player).center()
				if local.z < lead:
					lead = local.z
					lead_speed = float((r.walker as RefCounted).get("speed")) if str(r.phase) == "board" else 0.0
				if str(r.phase) in ["turn", "sit", "belt", "seated"]:
					settled += 1
			# 先の人の速さの分だけ先を読む（ばねの遅れで近づきすぎない）
			var want := minf(LEAD_IN.z, lead - LEAD_GAP - lead_speed * 0.32)
			if settled == 2:
				want = cam_aft.origin.z
			want = maxf(want, cam_aft.origin.z)
			var zc := float(_cues.lead_z)
			var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
			var h := delta / float(steps)
			for _i in range(steps):
				_lead_vel += ((want - zc) * 90.0 - _lead_vel * 2.0 * sqrt(90.0)) * h
				zc += _lead_vel * h
			zc = minf(zc, LEAD_IN.z)
			_cues["lead_z"] = zc
			# 通り道の真ん中：付け根の手前は頭より少し低く、前へ行くほど高く（操縦席の段の上の目の高さへ）
			var k := clampf((LEAD_IN.z - zc) / (LEAD_IN.z - cam_aft.origin.z), 0.0, 1.0)
			var eye_local := Vector3(0.0, lerpf(LEAD_IN.y, cam_aft.origin.y, FloatplaneFlight._ss5(k)), zc)
			var look_rest := xf * (cam_aft.origin + cam_aft.basis * Vector3(0.0, -0.55, -6.0))
			var look := (people + Vector3(0.0, 0.05, 0.0)).lerp(look_rest, smoothstep(0.6, 1.0, k))
			out = {"eye": xf * eye_local, "aim": look, "fov": 62.0}
	return out


## 07：操縦席の段の上から後ろを見る（P1 が左）。手持ちで少し揺れる。
func _cabin_view(t: float) -> Dictionary:
	var xf := plane.global_transform
	var cam := plane.marker_local("MK_CamAft")
	var drift := Vector3(sin(t * 0.37) * 0.05, sin(t * 0.53 + 1.0) * 0.03, sin(t * 0.29) * 0.04)
	# 狙う点は座った 2 人の少し先（ピントの距離。向きは前と同じ (0, −0.55, −6)）
	return {"eye": xf * (cam.origin + drift), "aim": xf * (cam.origin + cam.basis * Vector3(0.0, -0.41, -4.5)), "fov": 62.0}


## 動き出したら（c130_float.md 第13章）：
##   1) 操縦席の段の上で前へ向き直り（1.8 秒）、ハテナの右の肩越しに、水路を出て持ち上げたスタンドの下を抜けていく前を見る
##   2) EXIT_PUSH 秒から、窓を前へ抜けて機首の前の左へ出る（前を見たまま）→ 右へ振り返りながら左の横へ回り、加速して
##      滑走する機体と並ぶ（CHASE_RUN）。そこから離水・上昇を追う（機体の向きだけの枠。縦の揺れには付いていかない）
## 機体の中を後ろ向きに抜けない（操縦席の出入り口の壁や、ハテナの頭が画面をふさがない）。
func _board_exit_camera(t: float, dep: float, before: Dictionary, delta: float) -> Dictionary:
	var since := t - dep
	if since < 0.2:
		return before
	var view := Lens.mix(before, _ride_shake(_turn_view(t, (since - 0.2) / 1.8)), smoothstep(0.2, 0.7, since))
	_lens.focus_on(view.aim)
	if since < EXIT_PUSH:
		return view
	var u := FloatplaneFlight._ss5((since - EXIT_PUSH) / EXIT_LEN)
	var xf := plane.global_transform
	var heading := _heading_xf()
	var inv := heading.affine_inverse()
	var start := view.eye as Vector3
	var points := [start, xf * WINDSHIELD_IN, xf * WINDSHIELD_OUT, xf * Vector3(0.6, 4.7, -9.6), heading * Vector3(-4.0, 5.0, -17.0),
		heading * Vector3(-17.0, 4.8, -19.0), heading * CHASE_RUN]
	var eye := Lens.path(points, u)
	# 向き：前（操縦席から見ていた先）→ 右回りに振り返って機体の真ん中へ（向きの枠の中で、横をまわって回す）
	var d_front := inv.basis * ((view.aim as Vector3) - start).normalized()
	var d_plane := inv.basis * (heading * Vector3(0.0, 2.4, -1.5) - eye).normalized()
	var yaw_a := atan2(d_front.x, d_front.z)
	var yaw_b := atan2(d_plane.x, d_plane.z)
	while yaw_a < yaw_b:
		yaw_a += TAU
	while yaw_a - yaw_b > TAU:
		yaw_a -= TAU
	var k := FloatplaneFlight._ss5((u - 0.3) / 0.4)
	var yaw := lerpf(yaw_a, yaw_b, k)
	var pitch := lerpf(asin(clampf(d_front.y, -1.0, 1.0)), asin(clampf(d_plane.y, -1.0, 1.0)), k)
	var dir := heading.basis * Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var out := {"eye": eye, "aim": eye + dir * 20.0, "fov": lerpf(float(view.fov), 36.0, smoothstep(0.3, 0.9, u))}
	# ピント：前を見ている間は遠く、振り返ったら機体へ送る
	_lens.focus_on(heading * Vector3(0.0, 2.4, -1.5) if k > 0.5 else eye + dir * 40.0)
	if u >= 1.0:
		out = _chase_view(t, delta)
	elif u > 0.85:
		_chase_ready = false
		out = Lens.mix(out, _chase_view(t, delta), smoothstep(0.85, 1.0, u))
	return out


## 機体を追うカメラ（機体の向きだけの枠）：滑走のあいだは左の横の低い所から並んで（浮き舟と横へ広がるしぶき、少し望遠）、
## 浮いたら左うしろの下へ下がって、雲の層へ上がっていく機体を見上げる。カメラは海面より下へ入らない。
func _chase_view(t: float, delta: float) -> Dictionary:
	var heading := _heading_xf()
	var since_lof := t - _flight.liftoff_at if _flight != null and is_finite(_flight.liftoff_at) else -1.0
	var back := smoothstep(0.0, 3.0, since_lof)
	var want := CHASE_RUN.lerp(CHASE_CLIMB, back)
	if not _chase_ready:
		_chase_local = want
		_chase_ready = true
	_chase_local = _chase_local.lerp(want, 1.0 - exp(-1.6 * delta))
	var eye := heading * _chase_local
	eye.y = maxf(eye.y, SEA_Y + 1.6)
	var center := heading * Vector3(0.0, lerpf(2.4, 2.0, back), lerpf(-1.5, -2.5, back))
	_lens.focus_on(center)
	# 浮いて機首を上げ、カメラが後ろへ下がる間は少し広げる（尾が見切れない）
	var widen := smoothstep(0.0, 0.8, since_lof) * (1.0 - smoothstep(2.4, 4.0, since_lof))
	return {"eye": eye, "aim": center, "fov": lerpf(36.0, 42.0, back) + 6.0 * widen}


## 機体の向き（水平）だけの枠。
func _heading_xf() -> Transform3D:
	var f := plane.global_transform.basis.z
	var yaw := atan2(f.x, f.z)
	return Transform3D(Basis(Vector3.UP, yaw), plane.global_position)


## 狙う点をなめらかに寄せる（名前ごとに別のばね）。
func _smooth_aim(key: String, target: Vector3, delta: float, rate: float) -> Vector3:
	var prev: Variant = _aims.get(key)
	if prev == null:
		_aims[key] = target
		return target
	var p := (prev as Vector3).lerp(target, 1.0 - exp(-rate * delta))
	_aims[key] = p
	return p


## 雲の覆いの下（Space で飛ばしたとき）・雲の層の中で入れ替えたあと：水路と昇降台を元に戻す。
func end_board() -> void:
	restore_gate()


# ================================================================== 機内の巡航（空のセット）

## 雲の層の中で、地上から空のセットへ入れ替えた（または雲の覆いの下）。機体を空のセットの降下の位置の近くへ。
## 雲の層をつき抜けている途中なら、層の中の深さ・機体から見たカメラ・上昇の勢いをそのままにして、同じ高さの層を空のセットに
## 置き直す（上へ抜けて巡航へ）。Space で飛ばしたときは、機内の座席でベルトを締めた姿から。
func enter_cruise(fall_center: Vector3) -> void:
	var through := _scene == "board" and _cues.has("swap")
	var before := plane.global_transform
	_att_until = -1.0
	var climb_v := 0.0
	var depth_frac := 0.5
	var air_v := 46.0
	var pitch := 0.0
	if through and _flight != null:
		var now := _flight.sample(_t)
		var vel := (_flight.position_at(_t + 0.05) - _flight.position_at(_t - 0.05)) / 0.1
		climb_v = vel.y
		air_v = float(now.v)
		pitch = float(now.pitch)
		depth_frac = clampf((plane.global_position.y - _cloud.deck_bottom) / maxf(_cloud.deck_top - _cloud.deck_bottom, 1.0), 0.0, 1.0)
	_scene = "cruise"
	_t = 0.0
	_cues.clear()
	if sound != null:
		sound.thrust = CRUISE_THRUST
	restore_gate()
	_clear_water()
	_drop_base = Transform3D(Basis.IDENTITY, fall_center + DROP_OFFSET)
	_fall_center = fall_center
	_lower_sky_sea(fall_center, CRUISE_SEA_DEPTH)
	plane.visible = true
	plane.set_ramp(0.0)
	plane.set_upper_door(0.0)
	plane.snap_props(1.0)
	plane.set_pontoon_spray(0.0)
	plane.set_jump_light("off")
	plane.set_cabin_lighting("day")
	if plane.pilot != null:
		plane.pilot.play(&"steer")
	var top := _drop_base.origin.y - CRUISE_ABOVE_CLOUD
	var bottom := top - (CLOUD_TOP - CLOUD_BOTTOM)
	_cruise = {"through": through, "from_y": bottom + depth_frac * (top - bottom), "climb_v": climb_v, "air_v": air_v,
		"pitch": pitch, "lead": 0.0}
	if through:
		# 機体はまだ雲の中：降下の位置の下・少しうしろ。前へ進む分は空のセットの流れ（毎秒 FLOW_SPEED）が受け持つので、
		# 残りの速さで降下の位置へ寄りながら止まる。
		var excess := maxf(air_v - SuddenDeathSkySet.FLOW_SPEED, 0.0)
		_cruise.lead = excess * CRUISE_SETTLE * 0.5
		# 監督が当てた本戦の環境へ、舞台の環境から少しずつ寄せる（機内の明るさ・色がパッと変わらない）
		var venue_env := director.presenter().environment() if director.presenter() != null else null
		_blend_environment(_world_environment(), venue_env, venue_env, ENV_BLEND)
	else:
		_cloud.clear_deck()
	_place_cruise_plane(0.0)
	if through:
		_carry_swap(before, -HeliSuddenDeathDirector.SKY_SUN_DIRECTION.normalized())
	for player: int in [1, 2]:
		plane.set_belt(player, true)
		var puppet := director.puppet(player)
		puppet.set_visible(true)
		if not through:
			puppet.cancel_blend()
		_runners[player] = {"phase": "seated", "t": 0.0}
		_pose_seated(player, 3.0, -1.0)
	if not through:
		_cruise_cam_inside = true
		_lens.seed(0.0)
	else:
		_cruise_cam_inside = false
	_cruise_ready = not through
	# 入れ替えたフレームのうちにカメラも入れ替えた先へ（機体から見た位置はそのまま）
	_cruise_camera(0.0, 0.0)
	_cloud.update(_lens.eye, 0.0)


func update_cruise(delta: float) -> void:
	_t += delta
	_lens.advance(delta)
	var t := _t
	_place_cruise_plane(t)
	for player: int in [1, 2]:
		_pose_seated(player, 3.0 + t, -1.0)
	_update_exposure(delta)
	_feel(delta)
	_cruise_camera(t, delta)
	_cloud.update(_lens.eye, delta, Vector3(0.0, 0.0, SuddenDeathSkySet.FLOW_SPEED * delta))
	if bool(_cruise.get("through", false)) and t > CRUISE_SETTLE + 1.0 and _cloud.has_deck() and _cue("deck_away"):
		_cloud.clear_deck(4.0)


## 巡航の機体：雲の中から上がって降下の位置で水平になり（CRUISE_SETTLE 秒）、そのあとは空の揺れだけ。
func _place_cruise_plane(t: float) -> void:
	_sway_t = t
	plane.global_transform = _climb_out_xf(t, t)
	_apply_attitude_carry()


## 雲の中で入れ替えたあと、上へ抜けて降下の位置で水平になる機体（t は入れ替えてからの秒、sway_t は空の揺れの時計）。
func _climb_out_xf(t: float, sway_t: float) -> Transform3D:
	var sway := StagingFlight.cruise_sway(sway_t, 0.3)
	var base := _drop_base * Transform3D(sway.basis, sway.origin * 0.6)
	if not bool(_cruise.get("through", false)):
		return base
	var u := clampf(t / CRUISE_SETTLE, 0.0, 1.0)
	var e := FloatplaneFlight._ss5(u)
	# 高さ：上昇の勢いを保ったまま、降下の位置の高さへなめらかに（3 次のエルミート）
	var y0 := float(_cruise.from_y) - _drop_base.origin.y
	var v0 := float(_cruise.climb_v) * CRUISE_SETTLE
	var h00 := 2.0 * u * u * u - 3.0 * u * u + 1.0
	var h10 := u * u * u - 2.0 * u * u + u
	var dy := h00 * y0 + h10 * v0
	# 前：残りの速さで寄って止まる
	var lead := float(_cruise.lead)
	var dz := lead * (1.0 - (2.0 * u - u * u)) if u < 1.0 else 0.0
	var pitch := float(_cruise.pitch) * (1.0 - e)
	return base * Transform3D(Basis(Vector3.RIGHT, pitch), Vector3(0.0, dy, dz))


## 巡航のカメラ：雲から上へ抜ける機体を左うしろから追い → 前へ回って操縦席を見る → 操縦席の窓から入って
## 操縦席の段の上（MK_CamAft）で後ろを向く。入ったら降下を始めてよい（cruise_ready）。
func _cruise_camera(t: float, delta: float) -> void:
	var xf := plane.global_transform
	var cam := plane.marker_local("MK_CamAft")
	if _cruise_cam_inside:
		var view := _cabin_view(t)
		_lens.shoot(view.eye, view.aim, float(view.fov), "cruise_cabin")
		_cruise_ready = true
		return
	var heading := _heading_xf()
	var chase := {"eye": heading * _chase_local, "aim": heading * Vector3(0.0, 3.2, -2.0), "fov": 54.0}
	var t_front := CRUISE_SETTLE + 0.6
	var orbit := [_chase_local, Vector3(-22.0, 6.0, 2.0), Vector3(-17.0, 5.5, -15.0), Vector3(-2.2, 5.0, -21.0)]
	var u := FloatplaneFlight._ss5((t - t_front) / 3.2)
	var eye_local := Lens.path(orbit, u)
	var front := {"eye": heading * eye_local, "aim": xf * Vector3(0.0, 4.3, -4.6).lerp(Vector3(0.0, 3.2, -2.0), 1.0 - u), "fov": lerpf(54.0, 48.0, u)}
	var shot := chase if t < t_front else front
	var name := "cruise_outside"
	var t_in := t_front + 3.2
	if t >= t_in:
		if _cue("wave") and plane.pilot != null:
			plane.pilot.play(&"wave")
		var v := FloatplaneFlight._ss5((t - t_in) / 3.0)
		var points := [Vector3(-2.2, 5.0, -21.0), Vector3(1.0, 4.7, -10.0), WINDSHIELD_OUT, WINDSHIELD_IN, COCKPIT_PASS, COCKPIT_BACK, cam.origin]
		var eye_in := xf * Lens.path(points, v)
		var aim_in := xf * Vector3(0.0, 4.3, -4.6).lerp(cam.origin + cam.basis * Vector3(0.0, -0.55, -6.0), smoothstep(0.35, 0.95, v))
		shot = {"eye": eye_in, "aim": aim_in, "fov": lerpf(48.0, 60.0, v)}
		name = "cruise_enter"
		if v >= 1.0:
			_cruise_cam_inside = true
			shot = _cabin_view(t)
			name = "cruise_cabin"
	_lens.shoot(shot.eye, shot.aim, float(shot.fov), name)


## 降下を始めてよいか（カメラが機内に入った）。
func cruise_ready() -> bool:
	return _cruise_ready


## ベンチに座る（ベルトの動きは c 秒から）。belt_at が負ならベルトはもう締めている。
func _pose_seated(player: int, c: float, belt_at: float) -> void:
	var puppet := director.puppet(player)
	var frame := _seat_frame(player)
	var belt_len := 1.3
	if belt_at >= 0.0 and c >= belt_at and c < belt_at + belt_len:
		DropMotion.place_puppet(puppet, DropMotion.BENCH_BELT, c - belt_at, frame)
		if c - belt_at >= 0.78 and _cue("belt_%d" % player):
			plane.set_belt(player, true)
			AudioManager.play_sfx(&"fp_belt")
	else:
		DropMotion.place_puppet(puppet, DropMotion.BENCH_SIT, c + float(player) * 0.7, frame)


## 座る動きのクリップの原点（座った腰の真下の床、+Z が通路の向き）。
func _seat_frame(player: int) -> Transform3D:
	var seat := plane.marker_local("MK_SeatP1" if player == 1 else "MK_SeatP2")
	return plane.global_transform * Transform3D(seat.basis.orthonormalized(), Vector3(seat.origin.x, CABIN_FLOOR, seat.origin.z))


## 空のセットの海を、本戦の初めと同じ深さへ下げる（雲の層の間を飛ぶ機体の下がすぐ海にならないように）。
func _lower_sky_sea(fall_center: Vector3, depth: float) -> void:
	var sky := director.sky_set() if director != null else null
	if sky != null and sky.ocean != null:
		sky.ocean.position.y = fall_center.y - depth - sky.global_position.y


func _restore_sky_sea() -> void:
	var sky := director.sky_set() if director != null else null
	if sky != null and sky.ocean != null:
		sky.ocean.position.y = -SuddenDeathSkySet.FLY_HEIGHT


# ================================================================== 降下（DROP）

## 降下の始まり（巡航の機内の画から切らずに。heli_drop.md 3.1、c130_float.md 第10章）。short は ROUND 2 からの短い版：
## 迎えのあと機内で立って待っている 2 人（スロープはこれから開く）。spawns は本戦の初めの 2 人の位置（presenter.sky_spawn）。
func begin_drop(short: bool, spawns: Dictionary) -> void:
	_scene = "drop"
	_t = 0.0
	_att_until = -1.0
	_cues.clear()
	_short = short
	_sway_base = _sway_t
	plane.visible = true
	if sound != null:
		sound.thrust = CRUISE_THRUST
	_place_drop_plane(0.0)
	if _swap_pending:
		_swap_pending = false
		_carry_swap(_swap_from, -HeliSuddenDeathDirector.SKY_SUN_DIRECTION.normalized())
	plane.snap_props(1.0)
	plane.set_flaps(0.0)
	# 機内灯は 1.2 秒かけて赤へ。短い降下（雲の中で入れ替えた直後）は赤いジャンプ灯も D_SHORT_RED 秒で
	plane.set_cabin_lighting("red", 1.2)
	plane.set_jump_light("off" if short else "red")
	plane.set_ramp(0.0)
	plane.set_upper_door(0.0)
	_chase_ready = false
	_first = 1 + _rng.randi_range(0, 1)
	var pair := DropMotion.choose_pair(_rng, _jump_memory, _first)
	var xf := plane.global_transform
	for player: int in [1, 2]:
		plane.set_belt(player, true)
		var jump := String(pair.get(player, DropMotion.BASIC_JUMPS[0]))
		var info := DropMotion.clip_info(jump)
		var lane := LANE_X * _side(player)
		var jump_origin := xf * Vector3(lane, CABIN_FLOOR, EDGE_Z - float(info.edge))
		var puppet := director.puppet(player)
		puppet.set_visible(true)
		var prev: Dictionary = _runners.get(player, {})
		var walker: RefCounted = prev.get("walker") if short and prev.has("walker") else Walker.new(puppet)
		_walker_on_plane(walker)
		walker.set("idle_clip", "Idle_Loop")
		walker.set("idle_slot", AnimationRig.SLOT_UAL)
		_runners[player] = {
			"phase": "seated", "jump": jump, "info": info, "walker": walker,
			"jump_frame": Transform3D(xf.basis, jump_origin), "jump_local": xf.affine_inverse() * jump_origin,
			"spawn": spawns.get(player, Transform3D.IDENTITY), "t_jump": INF, "t_end": INF, "box_from": jump_origin,
			"last_pelvis": jump_origin, "clip": "",
		}
		if not short or _short_cut:
			puppet.cancel_blend()
	_handover_at = INF
	_update_drop_people(0.0)
	# 入れ替えたフレームのうちにカメラも機体の今の位置へ（短い版は雲の中で入れ替えた直後）
	_drop_camera(0.0)
	_cloud.call("update", _lens.get("eye"), 0.0)


func update_drop(delta: float) -> String:
	_t += delta
	_lens.advance(delta)
	_last_delta = delta
	var t := _t
	_place_drop_plane(t)
	var ramp := D_SHORT_RAMP if _short else D_RAMP
	var green := D_SHORT_GREEN if _short else D_GREEN
	if not _short and t >= D_THUMB and _cue("thumb"):
		if plane.pilot != null:
			plane.pilot.play(&"point")
	# スロープと上のふたが開く（油圧：ゆっくり動き出し、そっと止まる）。開くと外の光が差し込み、目が慣れていく。
	var u := FloatplaneFlight._ss5((t - ramp.x) / (ramp.y - ramp.x))
	plane.set_ramp(u)
	plane.set_upper_door(minf(u * 1.15, 1.0))
	if t >= ramp.x and _cue("ramp"):
		# 油圧のスロープ（2.2 秒）と、開いた後ろから吹き込む風
		AudioManager.play_sfx(&"fp_ramp", 0.0, 0.9)
		AudioManager.play_sfx(&"fp_ramp_wind")
	if _short and t >= D_SHORT_RED and t < green and _cue("red_light"):
		plane.set_jump_light("red")
	if t >= green and _cue("green"):
		plane.set_jump_light("green")
		AudioManager.play_sfx(&"fp_green_light")
	_update_drop_people(delta)
	_update_exposure(delta)
	_feel(delta)
	_drop_camera(t)
	# 短い版：機内のカメラで雲の層を上へ抜ける（窓の外の白さ）。抜けたら層を消す。
	_cloud.set("interior_start", CABIN_FOG_START if t < (D_SHORT_GO if _short else D_GO) else 0.0)
	_cloud.call("update", _lens.get("eye"), delta, Vector3(0.0, 0.0, SuddenDeathSkySet.FLOW_SPEED * delta))
	if _short and t > CRUISE_SETTLE + 0.5 and _cloud.call("has_deck") and _cue("deck_away"):
		_cloud.call("clear_deck", 3.0)
	# 2 人が飛び出して腹ばいになるあいだに、海を本戦の初めの深さへ下げる（本戦の見下ろしへつなぐ）
	var first: Dictionary = _runners[_first]
	var leave1 := float(first.t_jump) + float(first.info.leave)
	if is_finite(leave1):
		_lower_sky_sea(_fall_center, lerpf(CRUISE_SEA_DEPTH, _drop_sea_depth(), smoothstep(leave1 + 0.3, _handover_at, t)))
	if is_finite(_handover_at) and t >= _handover_at:
		return "handover"
	return ""


## 降下の機体：巡航の位置で、空の揺れを巡航から続ける（短い版は、雲の層から上へ抜けて水平になるところから）。
func _place_drop_plane(t: float) -> void:
	if _short:
		plane.global_transform = _climb_out_xf(t, _sway_base + t)
		_apply_attitude_carry()
		return
	var sway := StagingFlight.cruise_sway(_sway_base + t, 0.3)
	plane.global_transform = _drop_base * Transform3D(sway.basis, sway.origin * 0.6)


## 歩きの部品を機体の床の上（機体のローカル）で使う。
func _walker_on_plane(walker: RefCounted) -> void:
	walker.set("space", plane.global_transform)
	walker.set("ground", func(_feet: Vector3) -> float: return CABIN_FLOOR)
	walker.set("idle_clip", "Idle_Loop")
	walker.set("idle_slot", AnimationRig.SLOT_UAL)


## 座席の向き（機体のローカルの yaw。+Z が通路の向き）。
func _seat_local_yaw(player: int) -> float:
	var seat := plane.marker_local("MK_SeatP1" if player == 1 else "MK_SeatP2")
	var f := seat.basis.z
	return atan2(f.x, f.z)


## 機内の床（揺れる機体に合わせて）。
func _cabin_floor_ground(feet: Vector3) -> float:
	var xf := plane.global_transform
	var local := xf.affine_inverse() * feet
	return (xf * Vector3(local.x, CABIN_FLOOR, local.z)).y


## 1 人の降下：座って待つ → ベルトを外して立つ → 後ろ（スロープ）へ向き直って通り道へ一歩 → 緑で駆け出し（加速して前へ倒れる）
## → スロープの端で踏み切る（降り方のクリップ）→ 腹ばいで本戦の位置へ寄る。短い版は立って待つところから。
func _update_drop_people(delta: float) -> void:
	var t := _t
	var xf := plane.global_transform
	var go := (D_SHORT_GO if _short else D_GO)
	for player: int in [1, 2]:
		var r: Dictionary = _runners[player]
		var puppet := director.puppet(player)
		var walker: RefCounted = r.walker
		walker.set("space", xf)
		var lane := LANE_X * _side(player)
		var start := go + (0.0 if player == _first else DropMotion.JUMP_STAGGER)
		match str(r.phase):
			"seated":
				DropMotion.place_puppet(puppet, DropMotion.BENCH_SIT, t + float(player) * 0.7 + 3.0, _seat_frame(player))
				puppet.apply_blend(delta)
				if t >= (D_SHORT_UNBUCKLE if _short else D_UNBUCKLE) + 0.12 * float(player - 1):
					r.phase = "unbuckle"
					r.u_t = 0.0
			"unbuckle":
				r.u_t = float(r.u_t) + delta * UNBUCKLE_SPEED
				var local_t := float(r.u_t)
				DropMotion.place_puppet(puppet, DropMotion.BENCH_UNBUCKLE, local_t, _seat_frame(player))
				puppet.apply_blend(delta)
				if local_t >= 0.3 and _cue("unbelt_%d" % player):
					plane.set_belt(player, false)
					AudioManager.play_sfx(&"fp_belt", -2.0, 0.85)
				var length := float(DropMotion.clip_info(DropMotion.BENCH_UNBUCKLE).length)
				if local_t >= length - 0.02:
					var stood := xf.affine_inverse() * (_seat_frame(player) * DropMotion.root_offset(DropMotion.BENCH_UNBUCKLE, length))
					walker.set("feet", stood)
					walker.set("yaw", _seat_local_yaw(player))
					walker.set("speed", 0.0)
					puppet.begin_blend(0.25)
					walker.call("set_path", [Vector3(lane, CABIN_FLOOR, stood.z + 0.3)], 1.1, Walker.RUN)
					r.phase = "step"
			"step":
				if walker.call("step", delta):
					r.phase = "stand"
			"stand":
				walker.call("turn_to", 0.0, delta, 3.0)
				if t >= start:
					var jl: Vector3 = r.jump_local
					walker.set("a_up", 6.0)
					walker.call("set_path", [Vector3(lane, CABIN_FLOOR, jl.z - 1.2), jl], RUN_OUT_SPEED, Walker.SPRINT, false)
					r.phase = "run"
			"run":
				walker.call("step", delta)
				if walker.call("passed_end"):
					r.phase = "jump"
					r.t_jump = t
					r.t_end = t + float(r.info.length)
					var jl2: Vector3 = r.jump_local
					r.jump_frame = Transform3D(xf.basis, xf * jl2)
					puppet.begin_blend(0.12)
					var latest := 0.0
					for p: int in [1, 2]:
						var q: Dictionary = _runners[p]
						if not is_finite(float(q.t_jump)):
							latest = INF
							break
						latest = maxf(latest, maxf(float(q.t_end) + BOX_MIN, float(q.t_jump) + float(q.info.settle) + 0.45))
					_handover_at = latest
			"jump":
				var local := t - float(r.t_jump)
				DropMotion.place_puppet(puppet, String(r.jump), local, r.jump_frame)
				puppet.apply_blend(delta)
				var jumper := puppet.parts().get("pelvis") as Node3D
				if jumper != null:
					r.last_pelvis = jumper.global_position
				if local >= float(r.info.leave) and _cue("leave_%d" % player):
					# 2 人がほぼ同時に飛び出すので、あとの人は小さく（重なって大きくならない）
					AudioManager.play_sfx(&"fp_jump", -5.0 if _cues.has("leave_%d" % (3 - player)) else 0.0, 0.94 + 0.08 * float(player - 1))
				if t >= float(r.t_end):
					r.phase = "box"
					r.box_from = r.last_pelvis
			"box":
				var info: Dictionary = r.info
				var local_box := float(info.length) - float(info.settle) + (t - float(r.t_end))
				DropMotion.pose_puppet(puppet, DropMotion.BOX_LOOP, local_box)
				var pelvis := puppet.parts().get("pelvis") as Node3D
				if pelvis != null:
					var spawn: Transform3D = r.spawn
					var end := _handover_at if is_finite(_handover_at) else float(r.t_end) + BOX_MIN
					var w := smoothstep(float(r.t_end), end, t)
					var at := (r.box_from as Vector3).lerp(spawn.origin, w)
					var basis := (r.jump_frame as Transform3D).basis.orthonormalized()
					pelvis.global_transform = Transform3D(basis * pelvis.basis, at)
				puppet.apply_blend(delta)


## 降下のカメラ：機内（操縦席の段の上から後ろを見る、P1 が左）→ 駆け出した 2 人の背中を追ってスロープへ → 機外へ出て下を向く
## （本戦の見下ろしへは監督がつなぐ）。機内にいる間は貨物室の中に収める。
func _drop_camera(t: float) -> void:
	var first: Dictionary = _runners[_first]
	var second: Dictionary = _runners[3 - _first]
	var go := (D_SHORT_GO if _short else D_GO)
	if t < go:
		var view := _cabin_view(t)
		view["fov"] = lerpf(62.0, 56.0, smoothstep(D_THUMB, D_THUMB + 0.8, t))
		if _short and not _short_cut:
			# 迎えのあとは操縦席の窓の外（雲を上へ抜ける）を見ていた：スロープが開く前に後ろへ向き直る
			view = _turn_view(t, 1.0 - (t - 0.4) / 1.5)
		_lens.shoot(view.eye, view.aim, float(view.fov), "drop_cabin")
		_chase = _lens.get("last")
		_chase_ready = true
		return
	var a := director.puppet(1).center()
	var b := director.puppet(2).center()
	var mid := (a + b) * 0.5
	var leave1 := float(first.t_jump) + float(first.info.leave)
	var settle2 := float(second.t_jump) + float(second.info.settle)
	var k := 0.0
	if is_finite(leave1):
		k = smoothstep(0.0, 1.0, clampf((t - leave1) / maxf((settle2 - leave1 + 0.6) if is_finite(settle2) else 1.6, 0.1), 0.0, 1.0))
	var spread := clampf(a.distance_to(b) / 2.2, 1.0, 3.0)
	var eye := mid + Vector3(0.0, 1.5, -4.6).lerp(Vector3(0.0, 6.5, -2.0), k) * spread
	# 機内にいる間は、カメラを貨物室の中に収める（操縦席の段の壁や天井に入らない）。スロープの先から外では、胴体と尾の下に
	# 収める（尾翼や胴体の中に入らない。尾の端より後ろへ出たら上へ上がってよい）。
	var xf := plane.global_transform
	var local := xf.affine_inverse() * eye
	if local.z < EDGE_Z - 0.3:
		local = Vector3(clampf(local.x, -1.5, 1.5), clampf(local.y, CABIN_FLOOR + 0.9, CABIN_FLOOR + 3.3), maxf(local.z, -3.4))
	elif local.z < 13.5:
		var ceiling := lerpf(CABIN_FLOOR + 2.9, -1.2, smoothstep(EDGE_Z - 0.3, EDGE_Z + 1.6, local.z))
		ceiling = lerpf(ceiling, 30.0, smoothstep(11.8, 13.5, local.z))
		local.y = minf(local.y, ceiling)
		local.x = clampf(local.x, -1.4, 1.4) if local.y > -0.8 else local.x
	eye = xf * local
	var target := Lens.look(eye, mid + Vector3(0.0, -0.3, 2.5).lerp(Vector3(0.0, -1.0, 0.6), k))
	if not _chase_ready:
		_chase = _lens.get("last")
		_chase_ready = true
	# 機内のカメラからなめらかにつなぎ、飛び出したあとはぴったり追う（落ちる速さに遅れない）
	var rate := lerpf(2.6, 14.0, smoothstep(leave1 - 0.3, leave1 + 0.3, t)) if is_finite(leave1) else 2.6
	_chase = _chase.interpolate_with(target, 1.0 - exp(-rate * maxf(_last_delta, 0.0)))
	_lens.focus_on(mid)
	_lens.shoot_xf(_chase, 60.0, "drop_chase")


## 本戦へ渡した：2人の人形を隠し、機体は前へ飛び去る。Space で飛ばしたときは機体もすぐ隠す（迎えの途中なら着地台の横にいるため）。
func end_drop(skipped := false) -> void:
	_scene = "away"
	_after = 0.0
	for player: int in [1, 2]:
		director.puppet(player).set_visible(false)
		director.puppet(player).cancel_blend()
	plane.set_jump_light("off")
	plane.set_pontoon_spray(0.0)
	# ぼけは本戦の画へ寄せる間に消していく（advance_idle）。飛ばしたときは白い光の下ですぐ外す
	if skipped:
		_set_exposure(1.0, false)
		_clear_water()
		plane.visible = false
		# 着地台の先で待つ機体は、本戦の間に（映っていないときに）置く
		_scene = "away_hidden"


## 迎えで、2人（勝者）が駆け出した（着地台の人形と入れ替わった）。
func released() -> bool:
	return _released


## 本戦の間：飛び去る機体を少し動かしてから隠し、そのあと着地台の約 20 m 先の海で、尾を着地台へ向けて浮いて待たせる
## （2026-10-19 ユーザーの指示：迎えでは飛んでくる・着水する動きをなくし、もう着いていて、乗るときにハッチが開く）。
## 待つ所はカメラに映っていないときに置く（遠い海の上の小さな点のうちに）。海と着地台が上がってくるときも一緒に上がる。
func advance_idle(delta: float) -> void:
	if plane == null:
		return
	if _lens != null:
		_lens.settle(delta)
	if _scene == "away":
		_after += delta
		var xf := plane.global_transform
		plane.global_transform = Transform3D(xf.basis, xf.origin + Vector3(0.0, 4.0, -55.0) * delta)
		plane.set_ramp(1.0 - smoothstep(0.3, 1.5, _after))
		plane.set_upper_door(1.0 - smoothstep(0.3, 1.5, _after))
		if _after > 2.5:
			plane.visible = false
			_scene = "away_hidden"
	if _scene == "away_hidden":
		var landing := director.presenter().landing_float() if director.presenter() != null else null
		if landing != null and is_instance_valid(landing) and landing.is_inside_tree():
			_float = landing
			var pose := _wait_pose(0.0)
			var cam := director.main_camera()
			var far := cam == null or cam.global_position.distance_to(pose.origin) > 300.0 or not cam.is_position_in_frustum(pose.origin + Vector3(0.0, 3.0, 0.0))
			if far:
				_begin_wait()
	if _scene == "wait_float":
		_t += delta
		_place_wait(delta)


## 着地台の約 20 m 先で待つ機体を置き始める。
func _begin_wait() -> void:
	_scene = "wait_float"
	_t = 0.0
	if sound != null:
		sound.thrust = 0.0
	_clear_water()
	plane.visible = true
	plane.set_ramp(0.0)
	plane.set_upper_door(0.0)
	plane.set_flaps(0.3)
	plane.snap_props(0.3)
	plane.set_jump_light("off")
	plane.set_cabin_lighting("day")
	if plane.pilot != null:
		plane.pilot.play(&"steer")
	for player: int in [1, 2]:
		plane.set_belt(player, false)
	_dock_s = TUBE_R + _edge_ground_local.z
	_flight = null
	_step = "wait"
	_place_wait(0.0)


## 待つ機体：着地台の今の海の高さに合わせて、波にゆっくり揺れる。
func _place_wait(_delta: float) -> void:
	plane.global_transform = _wait_pose(_t)
	plane.set_props(0.3)


## 待つ所の機体の姿（FloatplaneFlight.sample の止まっているときと同じ波の揺れ。迎えで下がり始めてもつながる）。
func _wait_pose(t: float) -> Transform3D:
	var base := Transform3D(_pickup_basis(), _float_sea_center()) * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -(_dock_s + P_WAIT)))
	var heave := 0.055 * sin(TAU * t / 3.7 + 0.4) + 0.03 * sin(TAU * t / 5.3 + 2.2)
	var pitch := deg_to_rad(0.45) * sin(TAU * t / 4.4 + 1.1) + deg_to_rad(0.25)
	var roll := deg_to_rad(0.6) * sin(TAU * t / 5.9 + 0.7)
	return base * Transform3D(Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, roll), Vector3(0.0, heave + 0.01, 0.0))


## 着地台の中心の海面（今の高さ）。
func _float_sea_center() -> Vector3:
	if _float == null or not is_instance_valid(_float):
		return Vector3.ZERO
	var c := _float.global_position
	return Vector3(c.x, _float.sea_y, c.z)


# ================================================================== 着地台の迎え（REBOARD・EXTRACT）

## 水上機が遠くから飛んできて着地台の上を越え、先に着水し、後ろ向きに戻ってスロープを着地台に下ろす。2 人（決着のあとは勝者）が
## スロープを駆け上がって座りベルトを締めると、スロープを閉めて動き出し、離水して雲の層へ上がる。雲の層のいちばん深い所で
## 監督が場所を入れ替える（ROUND の間：降下の位置へ／決着のあと：舞台の上空へ）。カメラは本戦の最後の画から切らずに寄せる。
## release は駆け出す瞬間に呼ぶ（ROUND の間：着地台の人形を隠す／決着のあと：presenter.release_avatar）。
## camera_source は本戦の今の画を返す Callable（{"transform", "fov"}。寄せ始めの間その動きを続ける）。
func begin_pickup(players: Array[int], landing: LandingFloat, release: Callable, camera_source := Callable()) -> void:
	_scene_was = _scene
	_scene = "pickup"
	# 待っていた機体の時計（波の揺れ）はそのまま続ける
	if _scene_was != "wait_float":
		_t = 0.0
	_cues.clear()
	_aims.clear()
	_float = landing
	_pickup_players = players.duplicate()
	_on_release = release
	_released = false
	# 前の場面（降下）の 2 人の段は使わない（迎えの人だけを数える）
	_runners.clear()
	plane.visible = true
	plane.set_ramp(0.0)
	plane.set_upper_door(0.0)
	plane.set_flaps(0.3)
	if _scene_was != "wait_float":
		plane.snap_props(0.3)
	plane.set_jump_light("off")
	plane.set_cabin_lighting("day")
	if plane.pilot != null:
		plane.pilot.play(&"wave")
	for player: int in [1, 2]:
		plane.set_belt(player, false)
	# 道すじの枠：着地台の中心の海面、機首は進む向き（_pickup_dir）。止める所はスロープの端が浮き輪に載る s。
	# 機体はもう着地台の約 20 m 先で待っている：ゆっくり下がりながらハッチ（スロープと上のふた）を開け、端を浮き輪に載せる。
	var center := _float.global_position
	_frame = Transform3D(_pickup_basis(), Vector3(center.x, _float.sea_y, center.z))
	_dock_s = TUBE_R + _edge_ground_local.z
	_flight = FloatplaneFlight.dock(_frame, _t + P_BACK_DELAY, {"from_s": _dock_s + P_WAIT, "to_s": _dock_s, "speed": P_BACK_SPEED,
		"brake": P_BACK_BRAKE, "accel_time": P_BACK_ACCEL, "duration": 30.0, "wander": 0.25})
	_step = "back"
	_crane_at = INF
	_stop_at = _flight.stop_at
	_op_ready = false
	_chase_ready = false
	var sky := director.sky_set() if director != null else null
	_reset_wake(sky.ocean if sky != null else null)
	plane.clear_water_fx()
	_place_flight(0.0, 0.0)
	# 離水して上がっていく先（進む向きの沖）に、低い雲の層
	var dir := _pickup_dir()
	_cloud.call("place_deck", center + dir * 520.0, _float.sea_y + CLOUD_BOTTOM, _float.sea_y + CLOUD_TOP, Vector2(900.0, 760.0), dir,
		-HeliSuddenDeathDirector.SKY_SUN_DIRECTION.normalized(), 5, 5.0)
	# 本戦の最後の画（着地台のまわりを回る画）は動いたまま渡ってくる：その動きを続けながら寄せる
	_lens.seed(1.4, camera_source)


func update_pickup(delta: float) -> String:
	_t += delta
	_lens.advance(delta)
	var t := _t
	# 待っていた所からゆっくり下がり、スロープの端を浮き輪に載せる → 乗ったら動き出して離水・上昇（海の高さは着地台に合わせる）
	if _step == "back" and _float != null:
		_frame = Transform3D(_pickup_basis(), _float_sea_center())
		_flight.frame = _frame
	_place_flight(t, delta)
	var stop_known := is_finite(_stop_at)
	if stop_known and t >= _stop_at - P_RAMP_LEAD and not _cues.has("close"):
		var u := smoothstep(_stop_at - P_RAMP_LEAD, _stop_at, t)
		plane.set_ramp(u * SuddenDeathFloatplane.RAMP_GROUND)
		plane.set_upper_door(u)
		if _cue("ramp"):
			# スロープを浮き輪へ下ろす（P_RAMP_LEAD 1.8 秒）
			AudioManager.play_sfx(&"sd_servo", -2.0, 0.75)
			AudioManager.play_sfx(&"fp_ramp", 0.0, 1.1)
	if stop_known and t >= _stop_at + P_RELEASE and not _released:
		_released = true
		for player: int in _pickup_players:
			var puppet := director.puppet(player)
			var at := director.presenter().lander_point(player) if director.presenter() != null else _float.land_point()
			var pad_y := _float.land_point().y
			_adopt_lander_pose(player)
			var walker := Walker.new(puppet)
			walker.feet = Vector3(at.x, pad_y, at.z)
			walker.yaw = atan2(plane.global_position.x - at.x, plane.global_position.z - at.z)
			walker.ground = _pickup_ground
			_runners[player] = {"phase": "wait", "t": 0.0, "walker": walker}
			puppet.set_visible(true)
			puppet.begin_blend(0.4)
		if _on_release.is_valid():
			_on_release.call()
	var seated := 0
	if _released:
		for player: int in _pickup_players:
			if _update_pickup_runner(player, delta) in ["belt", "seated"]:
				seated += 1
	if _released and seated == _pickup_players.size() and _cue("close"):
		plane.set_jump_light("off")
		AudioManager.play_sfx(&"fp_ramp", 0.0, 0.88)
	if _cues.has("close"):
		var c := t - float(_cues.close)
		if c >= B_CLOSE - 0.12 and _cue("ramp_latch"):
			AudioManager.play_sfx(&"fp_ramp_latch")
			_lens.kick(0.32)
		var u2 := 1.0 - FloatplaneFlight._ss5(c / B_CLOSE)
		plane.set_ramp(u2 * SuddenDeathFloatplane.RAMP_GROUND)
		plane.set_upper_door(u2)
		if c >= B_SPOOL_AT and _cue("depart"):
			_begin_departure()
	_update_exposure(delta)
	_feel(delta)
	_pickup_camera(t, delta)
	# 機内のカメラ：機内の物には霧をかけない（窓の外だけ白くなる）
	_cloud.set("interior_start", CABIN_FOG_START if _cues.has("depart") else 0.0)
	_cloud.call("update", _lens.get("eye"), delta)
	if _step == "takeoff" and float(_cloud.get("depth")) >= 0.93 and _cue("swap"):
		return "swap"
	if t >= P_LIMIT and _cue("limit"):
		return "cover"
	return ""


func _pickup_dir() -> Vector3:
	return Vector3(cos(P_DOCK_ANGLE), 0.0, sin(P_DOCK_ANGLE))


func _pickup_basis() -> Basis:
	return Basis.looking_at(_pickup_dir(), Vector3.UP)


## 着地台の上から、スロープを駆け上がって機内へ（座ってベルト）。返り値は今の段。
func _update_pickup_runner(player: int, delta: float) -> String:
	var r: Dictionary = _runners[player]
	var walker: RefCounted = r.walker
	r.t = float(r.t) + delta
	var order := _pickup_players.find(player)
	var xf := plane.global_transform
	if str(r.phase) == "wait":
		walker.call("stand", delta)
		if _t >= _stop_at + float(P_RUN[mini(order, 1)]):
			var lane := LANE_X * _side(player)
			var seat := plane.marker_local("MK_SeatP1" if player == 1 else "MK_SeatP2")
			var front := Vector3(seat.origin.x - SIT_REACH * _side(player), CABIN_FLOOR, seat.origin.z)
			walker.call("set_path", [xf * Vector3(lane, _edge_ground_local.y, _edge_ground_local.z + 0.5),
				xf * Vector3(lane, CABIN_FLOOR, HINGE_Z - 0.6), xf * Vector3(lane + 0.25 * _side(player), CABIN_FLOOR, front.z + 0.9), xf * front],
				B_IN_SPEED, Walker.RUN)
			r.phase = "board"
		return str(r.phase)
	return _update_seat_runner(player, delta)


## 機内へ駆け込んだあとの共通の段：止まる → 通路へ向き直る → 腰を下ろす → ベルト → 座っている。返り値は今の段。
func _update_seat_runner(player: int, delta: float) -> String:
	var r: Dictionary = _runners[player]
	var walker: RefCounted = r.walker
	var puppet := director.puppet(player)
	match str(r.phase):
		"board":
			var done: bool = walker.call("step", delta)
			# スロープの金属の上を踏む音（スロープの先を越えたとき）
			var local := plane.global_transform.affine_inverse() * director.puppet(player).center()
			if local.z < EDGE_Z and _cue("ramp_step_%d" % player):
				AudioManager.play_sfx(&"step_metal", -8.0)
			if done:
				r.phase = "turn"
		"turn":
			if walker.call("turn_to", _seat_yaw(player), delta, 3.4):
				r.phase = "sit"
				r.sit_t = 0.0
				r.plant = walker.get("feet")
				puppet.begin_blend(0.2)
		"sit":
			r.sit_t = float(r.sit_t) + delta
			var length := maxf(puppet.clip_length(SIT_DOWN_CLIP), 0.5)
			var u := clampf(float(r.sit_t) * SIT_DOWN_SPEED / length, 0.0, 0.999)
			var plant: Vector3 = r.plant
			puppet.pose(SIT_DOWN_CLIP, u)
			var floor_y := (plane.global_transform * Vector3(0.0, CABIN_FLOOR, 0.0)).y
			puppet.stand_at(plant, _seat_yaw(player), floor_y)
			Walker.plant_feet(puppet, plant)
			puppet.apply_blend(delta)
			if u >= 0.97:
				r.phase = "belt"
				r.belt_t = 0.0
				puppet.begin_blend(0.35)
		"belt":
			r.belt_t = float(r.belt_t) + delta
			_pose_seated(player, float(r.belt_t), 0.0)
			puppet.apply_blend(delta)
			if float(r.belt_t) >= 1.35:
				r.phase = "seated"
		"seated":
			_pose_seated(player, 3.0 + _t, -1.0)
			puppet.apply_blend(delta)
	return str(r.phase)


## 着地台に立っている人形の姿を、本物のアバターに写す（入れ替わる瞬間に姿がとばないように。そのあと begin_blend でつなぐ）。
func _adopt_lander_pose(player: int) -> void:
	var presenter := director.presenter()
	if presenter == null:
		return
	var actors: Variant = presenter.get("_actors")
	if not (actors is Dictionary) or not (actors as Dictionary).has(player):
		return
	var src: Dictionary = (actors as Dictionary)[player].get("parts", {})
	var dst := director.puppet(player).parts()
	for key: Variant in src:
		var a: Variant = src[key]
		var b: Variant = dst.get(key)
		if a is Node3D and b is Node3D and (a as Node3D).is_inside_tree() and (b as Node3D).is_inside_tree():
			(b as Node3D).global_transform = (a as Node3D).global_transform


## 足もとの高さ：着地台の上 → スロープ（約 20° 上り）→ 貨物室の床。
func _pickup_ground(feet: Vector3) -> float:
	var xf := plane.global_transform
	var local := xf.affine_inverse() * feet
	if local.z > _edge_ground_local.z - 0.05:
		return _float.land_point().y
	var y := CABIN_FLOOR
	if local.z > HINGE_Z:
		y = CABIN_FLOOR - (local.z - HINGE_Z) * _ramp_slope
	return (xf * Vector3(local.x, y, local.z)).y


## 迎えのカメラ（カットなし）：本戦の最後の画から寄せて、着地台の横から、飛んできて着地台の上を越え先に着水する機体を追う
## （遠いほど寄る）→ 後ろ向きに戻ってくる機体を、着地台の斜めうしろへ動きながら追う → スロープが浮き輪に下りたら、スロープの先の
## 横から胴体の下の縁の下をくぐって機内へ入り、駆け込む 2 人の前を後ろ向きに下がって操縦席の段の上で止まる → そのまま機内で
## 離水・上昇（窓の外が雲で白くなる）。
func _pickup_camera(t: float, delta: float) -> void:
	var center := _float.global_position
	var dir := _pickup_dir()
	var side := Vector3(dir.z, 0.0, -dir.x)
	var dock := center + dir * 6.0 + Vector3(0.0, 2.0, 0.0)
	var arrive_eye := center + side * 30.0 + dir * 10.0 + Vector3(0.0, 4.5, 0.0)
	var aim := _operator(_lead_point(t, Vector3(0.0, 2.5, 0.0), 3.5), delta, not _op_ready, 3.5)
	var far := arrive_eye.distance_to(plane.global_position)
	var shot := {"eye": arrive_eye, "aim": aim, "fov": lerpf(52.0, 18.0, smoothstep(45.0, 160.0, far))}
	var name := "pickup_arrive"
	if is_finite(_stop_at):
		# 後ろ向きに寄ってくる機体と、着地台の 2 人（着地台の斜めうしろの低い所）
		var back_eye := center + side * 11.0 - dir * 8.5 + Vector3(0.0, 3.2, 0.0)
		var back_aim := _smooth_aim("pickup_back", dock.lerp(plane.global_position + Vector3(0.0, 2.0, 0.0), 0.4), delta, 3.0)
		var w := FloatplaneFlight._ss5((t - (_stop_at - 7.0)) / 3.2)
		shot = Lens.mix(shot, {"eye": back_eye, "aim": back_aim, "fov": 54.0}, w)
		if w > 0.5:
			name = "pickup_back"
		if _released:
			shot = _pickup_lead_camera(t, shot, delta)
			name = "pickup_lead"
	if _cues.has("close") and float(_cues.get("lead_z", 0.0)) <= plane.marker_local("MK_CamAft").origin.z + 0.05:
		var view := _cabin_view(t)
		name = "pickup_cabin"
		if _cues.has("depart"):
			# 動き出したら前へ向き直り、操縦席の窓から滑走と上昇と雲の層を見る。向き直ったら窓の方へゆっくり寄る（長い画に張りを）
			var since_dep := t - float(_cues.depart)
			view = _turn_view(t, (since_dep - 0.2) / 1.8)
			var push := FloatplaneFlight._ss5((since_dep - 2.0) / RIDE_PUSH_TIME)
			if push > 0.0:
				view.eye = (view.eye as Vector3) + plane.global_transform.basis * (WINDSHIELD_IN - COCKPIT_EYE) * (RIDE_PUSH * push)
				view.fov = float(view.fov) - RIDE_PUSH_FOV * push
			view = _ride_shake(view)
			name = "pickup_ride"
		shot = view
	_lens.shoot(shot.eye, shot.aim, float(shot.fov), name)


## スロープの先の横から機内へ（BOARD の _board_lead_camera と同じ考え。スロープは浮き輪へ下りている）。
func _pickup_lead_camera(t: float, before: Dictionary, delta: float) -> Dictionary:
	var xf := plane.global_transform
	var since := t - (_stop_at + P_RELEASE)
	var people := Vector3.ZERO
	for player: int in _pickup_players:
		people += director.puppet(player).center()
	people /= float(_pickup_players.size())
	var side_pt := xf * Vector3(-2.5, 2.25, 6.7)
	# 着地台の 2 人をよけて、着地台の左の外を回ってスロープの先の横へ
	var around := [before.eye as Vector3, xf * Vector3(-6.8, 3.8, 12.0), xf * Vector3(-4.6, 2.9, 7.6), side_pt]
	var u := FloatplaneFlight._ss5(since / 1.7)
	var aim := (before.aim as Vector3).lerp(people, FloatplaneFlight._ss5(since / 1.0))
	var out := {"eye": Lens.path(around, u), "aim": aim, "fov": lerpf(float(before.fov), 62.0, u)}
	if since >= 1.6:
		var v := FloatplaneFlight._ss5((since - 1.6) / 1.0)
		var under := [side_pt, xf * Vector3(-1.1, 2.2, 6.4), xf * Vector3(-0.3, 2.65, 5.95), xf * PICKUP_LEAD_IN]
		out = {"eye": Lens.path(under, v), "aim": people + Vector3(0.0, 0.1, 0.0), "fov": 62.0}
		if not _cues.has("lead_z"):
			_cues["lead_z"] = PICKUP_LEAD_IN.z
			_lead_vel = 0.0
		if v >= 1.0:
			out = _lead_follow(PICKUP_LEAD_IN, people, delta)
	return out


## 駆け込む人の LEAD_GAP m（坂のスロープから上がってくるときは少し多め）前を保って、通り道の真ん中を後ろ向きに下がる
## （全員が座りに入ったら操縦席の段の上まで）。
func _lead_follow(start: Vector3, people: Vector3, delta: float, gap := LEAD_GAP + 0.6) -> Dictionary:
	var xf := plane.global_transform
	var cam_aft := plane.marker_local("MK_CamAft")
	var lead := INF
	var lead_speed := 0.0
	var settled := 0
	var count := 0
	for player: int in _runners:
		var r: Dictionary = _runners[player]
		if not r.has("walker"):
			continue
		count += 1
		var local := xf.affine_inverse() * director.puppet(player).center()
		if local.z < lead:
			lead = local.z
			lead_speed = float((r.walker as RefCounted).get("speed")) if str(r.phase) == "board" else 0.0
		if str(r.phase) in ["turn", "sit", "belt", "seated"]:
			settled += 1
	var want := minf(start.z, lead - gap - lead_speed * 0.32)
	if count > 0 and settled == count:
		want = cam_aft.origin.z
	want = maxf(want, cam_aft.origin.z)
	var zc := float(_cues.get("lead_z", start.z))
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var h := delta / float(steps)
	for _i in range(steps):
		_lead_vel += ((want - zc) * 90.0 - _lead_vel * 2.0 * sqrt(90.0)) * h
		zc += _lead_vel * h
	zc = minf(zc, start.z)
	_cues["lead_z"] = zc
	var k := clampf((start.z - zc) / (start.z - cam_aft.origin.z), 0.0, 1.0)
	var eye_local := Vector3(0.0, lerpf(start.y, cam_aft.origin.y, FloatplaneFlight._ss5(k)), zc)
	var look_rest := xf * (cam_aft.origin + cam_aft.basis * Vector3(0.0, -0.55, -6.0))
	var look := (people + Vector3(0.0, 0.05, 0.0)).lerp(look_rest, smoothstep(0.6, 1.0, k))
	return {"eye": xf * eye_local, "aim": look, "fov": 62.0}


## 操縦席の出入り口から前を見る（ハテナの肩越しに、操縦席の窓の外）。
func _cockpit_view(t: float) -> Dictionary:
	var xf := plane.global_transform
	var drift := Vector3(sin(t * 0.41) * 0.03, sin(t * 0.57 + 0.7) * 0.02, 0.0)
	# 狙う点は同じ向きの遠く（ピントを窓の外に。ハテナの肩と計器盤は手前でぼける）
	return {"eye": xf * (COCKPIT_EYE + drift), "aim": xf * (COCKPIT_EYE + (COCKPIT_AIM - COCKPIT_EYE) * 4.0), "fov": 70.0}


## 機内のカメラが、後ろ（操縦席の段の上から貨物室）と前（操縦席の窓の外）のあいだを向き直る（u：0 後ろ、1 前）。
## 向きは機体の上を軸に右回りに回す（途中で狙う点が目に重ならない）。
func _turn_view(t: float, u: float) -> Dictionary:
	var k := FloatplaneFlight._ss5(u)
	if k <= 0.0:
		return _cabin_view(t)
	if k >= 1.0:
		return _cockpit_view(t)
	var xf := plane.global_transform
	var inv := xf.affine_inverse()
	var a := _cabin_view(t)
	var b := _cockpit_view(t)
	var eye := xf * Lens.path([inv * (a.eye as Vector3), TURN_MID, inv * (b.eye as Vector3)], k)
	var da := inv.basis * ((a.aim as Vector3) - (a.eye as Vector3)).normalized()
	var db := inv.basis * ((b.aim as Vector3) - (b.eye as Vector3)).normalized()
	var yaw_a := atan2(da.x, da.z)
	var yaw_b := atan2(db.x, db.z)
	# 左（−X）回り：目は右の席の側（TURN_MID）を通り、操縦席の真ん中（ハテナ）の方を向いて回る（右の壁や柱を向かない）
	if yaw_b > yaw_a:
		yaw_b -= TAU
	var pitch := lerpf(asin(clampf(da.y, -1.0, 1.0)), asin(clampf(db.y, -1.0, 1.0)), k)
	var yaw := lerpf(yaw_a, yaw_b, k)
	var dir := xf.basis * Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	# 回る途中はハテナの頭と座席の背が近い：その間だけ少し広げる（近い物が画面をふさがない）
	return {"eye": eye, "aim": eye + dir * 6.0, "fov": lerpf(float(a.fov), float(b.fov), k) + TURN_WIDEN * sin(PI * k)}


## 機内で離水・上昇を見る：加速でカメラが少し遅れ、推力で細かく震える。
func _ride_shake(view: Dictionary) -> Dictionary:
	if _flight == null:
		return view
	var sample := _flight.sample(_t)
	var accel := float(sample.a)
	var xf := plane.global_transform
	var lag := clampf(accel * 0.03, 0.0, 0.12)
	var buzz := 0.01 * smoothstep(0.0, 1.0, absf(float(sample.v)) / 30.0)
	var t := _t
	var jitter := Vector3(sin(t * 31.0) * 0.6 + sin(t * 47.0) * 0.4, sin(t * 37.0 + 1.0), sin(t * 29.0 + 2.0) * 0.5) * buzz
	var out := view.duplicate()
	out.eye = (view.eye as Vector3) + xf.basis.z * lag + xf.basis * jitter
	out.aim = (view.aim as Vector3) + xf.basis * jitter * 2.0
	return out


## 雲の層の中で（ROUND の間）、本戦から降下の位置へ入れ替えた。機体とカメラ（機内）と座った 2 人はそのまま、空のセットの
## 降下の位置の下の雲の層の中へ（上へ抜けて、短い降下へ）。
func enter_short_drop(fall_center: Vector3) -> void:
	var through := _scene == "pickup" and _cues.has("swap")
	# 迎えなし（暗転のあと）：機内の画から切って入る
	_short_cut = _scene != "pickup"
	# 雲の層・霧・カメラは、begin_drop で機体を降下の位置へ置いたときに一緒に運ぶ
	_swap_from = plane.global_transform
	_swap_pending = through
	_begin_climb_out(fall_center, through)
	for player: int in [1, 2]:
		director.puppet(player).set_visible(_runners.has(player))


## 雲の中で入れ替えたあとの上昇（巡航と短い降下）：層の中の深さ・上昇の勢いを引き継ぎ、空のセットに同じ高さの層を置き直す。
func _begin_climb_out(fall_center: Vector3, through: bool) -> void:
	var climb_v := 0.0
	var depth_frac := 0.5
	var air_v := 46.0
	var pitch := 0.0
	if through and _flight != null:
		var now := _flight.sample(_t)
		var vel := (_flight.position_at(_t + 0.05) - _flight.position_at(_t - 0.05)) / 0.1
		climb_v = vel.y
		air_v = float(now.v)
		pitch = float(now.pitch)
		depth_frac = clampf((plane.global_position.y - float(_cloud.get("deck_bottom"))) / maxf(float(_cloud.get("deck_top")) - float(_cloud.get("deck_bottom")), 1.0), 0.0, 1.0)
	_clear_water()
	_drop_base = Transform3D(Basis.IDENTITY, fall_center + DROP_OFFSET)
	_fall_center = fall_center
	_lower_sky_sea(fall_center, CRUISE_SEA_DEPTH)
	var top := _drop_base.origin.y - CRUISE_ABOVE_CLOUD
	var bottom := top - (CLOUD_TOP - CLOUD_BOTTOM)
	_cruise = {"through": through, "from_y": bottom + depth_frac * (top - bottom), "climb_v": climb_v, "air_v": air_v,
		"pitch": pitch, "lead": maxf(air_v - SuddenDeathSkySet.FLOW_SPEED, 0.0) * CRUISE_SETTLE * 0.5, "t0": 0.0}
	if not through:
		_cloud.call("clear_deck")
	plane.set_flaps(0.0)
	plane.set_pontoon_spray(0.0)


# ================================================================== 帰還（HOME）

## 雲の層の中で、本戦から舞台の上空へ入れ替えた（勝者の迎えのあと）。機体はゴールの側の上空の雲の層の中から下りてきて、
## 台座の上を低く通る。機内では勝者がベンチに座っている。台座の近くでスロープが開き（外の日の光が差し込む）、勝者がベルトを
## 外して立ち、スロープの端へ歩いて、端から飛び降りて自分の台のゴールの側に着地する（SD_Land_* の 3 通りからランダム）。
## カメラは機内（操縦席の段の上から後ろ）から勝者を追ってスロープへ、飛び降りた勝者を追って外へ出て、台座の前（今までの帰還の画）へ下がる。
func begin_home(winner: int, podium: Vector3) -> void:
	var through := _scene == "pickup" and _cues.has("swap")
	var before := plane.global_transform
	_att_until = -1.0
	var pitch_from := 0.0
	if through and _flight != null:
		pitch_from = float(_flight.sample(_t).pitch)
	_scene = "home"
	_t = 0.0
	_cues.clear()
	_clear_water()
	_podium = podium
	if sound != null:
		sound.thrust = HOME_THRUST
	var clip := DropMotion.LANDINGS[_rng.randi_range(0, DropMotion.LANDINGS.size() - 1)]
	var info := DropMotion.clip_info(clip)
	var land := podium + Vector3(QuizGameState.RESULT_PLAYER_X * _side(winner), 0.0, H_LAND_Z)
	land.y = FLOOR_Y
	var origin_local := Vector3(0.0, CABIN_FLOOR, EDGE_Z - float(info.get("edge", 1.53)))
	var land_time := float(info.get("land", 1.5))
	_home = {"winner": winner, "clip": clip, "info": info, "land": land, "origin_local": origin_local,
		"plane_at_leave": Vector3.ZERO, "t_start": H_LEAVE - float(info.get("leave", 0.433)), "frame": Transform3D.IDENTITY,
		"landed": false, "feet": land, "turn_sign": signf(land.x) if absf(land.x) > 0.01 else 1.0, "phase": "seated",
		"pitch_from": pitch_from, "through": through}
	# 離れる瞬間の機体の姿勢（機首を少し上げた低速の姿勢）で、スロープの立ち位置が着地点へ届くように機体の位置を決める
	_build_home_path()
	var leave_basis := _plane_home_xf(float(_home.leave_h)).basis
	_home.plane_at_leave = land - leave_basis * origin_local - DropMotion.root_offset(clip, land_time)
	plane.visible = true
	plane.set_ramp(0.0)
	plane.set_upper_door(0.0)
	plane.set_flaps(1.0)
	plane.snap_props(1.0)
	plane.set_pontoon_spray(0.0)
	# 入れ替えたフレームには灯を変えない（赤いジャンプ灯は H_RED_AT 秒）
	plane.set_jump_light("off" if through else "red")
	plane.set_cabin_lighting("day")
	if plane.pilot != null:
		plane.pilot.play(&"steer")
	for player: int in [1, 2]:
		plane.set_belt(player, player == winner)
	_place_plane_home(0.0)
	# 舞台の上空の雲の層：機体が今いる層の中の深さが同じになるように置く（下へ抜けて台座へ）
	# 舞台の上空の雲の層：入れ替えの前の層を機体と同じだけ運ぶ（機体の層の中の深さも、まわりの雲の並びも同じ。下へ抜けて台座へ）
	if through:
		_carry_swap(before, _stage_sun())
		_cloud.set("interior_start", CABIN_FOG_START)
		# 監督は舞台の環境へ戻した：本戦の環境から少しずつ寄せる（寄せ終わったら舞台の環境のまま）
		var venue_env := director.presenter().environment() if director.presenter() != null else null
		_blend_environment(venue_env, _world_environment(), null, ENV_BLEND)
	else:
		_cloud.call("clear_deck")
	var puppet := director.puppet(winner)
	puppet.set_visible(true)
	var walker: RefCounted = (_runners.get(winner, {}) as Dictionary).get("walker")
	if walker == null:
		walker = Walker.new(puppet)
		puppet.cancel_blend()
	_walker_on_plane(walker)
	_runners = {winner: {"phase": "seated", "walker": walker, "t": 0.0}}
	if not through:
		_lens.seed(0.0)
	_update_home_winner(0.0)
	# 入れ替えたフレームのうちにカメラも舞台の上空へ（機体から見た位置はそのまま）
	_home_camera(0.0, 0.0)
	_cloud.call("update", _lens.get("eye"), 0.0)


func update_home(delta: float) -> String:
	_t += delta
	_lens.advance(delta)
	var leave := float(_home.get("leave_h", H_LEAVE))
	if plane.visible:
		_place_plane_home(_t)
		if _t > leave + 6.0:
			plane.visible = false
	# スロープと上のふた（台座の近くで開く。離れて少ししたら閉める）
	var u := FloatplaneFlight._ss5((_t - (leave - H_RAMP_LEAD)) / 2.0) * (1.0 - smoothstep(leave + 1.5, leave + 3.5, _t))
	plane.set_ramp(u)
	plane.set_upper_door(minf(u * 1.15, 1.0))
	if _t >= leave - H_RAMP_LEAD and _cue("ramp"):
		AudioManager.play_sfx(&"fp_ramp")
		AudioManager.play_sfx(&"fp_ramp_wind", -4.0)
	if _t >= H_RED_AT and _t < leave - 2.0 and _cue("red_light"):
		plane.set_jump_light("red")
	if _t >= leave - 2.0 and _cue("green"):
		plane.set_jump_light("green")
		AudioManager.play_sfx(&"fp_green_light")
	_update_exposure(delta)
	if bool(_home.landed):
		# 着地したら監督の帰還の画へ（監督はカットせず、今のカメラからなめらかに寄せる）。ぼけはその間に消していく
		_cloud.call("update", _lens.get("eye"), delta)
		_lens.settle(delta)
		return ""
	var landed := _update_home_winner(delta)
	_feel(delta)
	_home_camera(_t, delta)
	_cloud.set("interior_start", CABIN_FOG_START if _t < leave + 0.3 else 0.0)
	_cloud.call("update", _lens.get("eye"), delta)
	if _cloud.call("has_deck") and _t > 4.0 and _cue("deck_away"):
		_cloud.call("clear_deck", 5.0)
	if landed:
		_home.landed = true
		return "landed"
	return ""


## 帰還の道すじ：雲の中（台座から約 150 m）から、ゴールの観客席の上を越えて、台座の上を低く（スロープは床から約 4 m）通る。
## 遠いほど速く高く（約 26 m/秒・7° の下り）、最後の 30 m で床の近くへ下りる。勝者が離れたら推力を上げ、上がりながら旋回して去る。
## 距離（離れる点までの残り）ごとの時刻の表を作る。
func _build_home_path() -> void:
	var d := H_FROM
	var h := 0.0
	var times := PackedFloat32Array()
	var dists := PackedFloat32Array()
	while d > 0.0:
		times.append(h)
		dists.append(d)
		var v := _home_speed(d)
		var step := v / 120.0
		d -= step
		h += 1.0 / 120.0
	times.append(h)
	dists.append(0.0)
	_home["path_t"] = times
	_home["path_d"] = dists
	# 離れる時刻は道すじの長さで決まる（表の終わり）
	_home["leave_h"] = h


func _home_speed(d: float) -> float:
	return lerpf(H_SPEED, 26.0, smoothstep(12.0, 120.0, d))


func _home_height(d: float) -> float:
	if d > 30.0:
		return H_HIGH + (d - 30.0) * tan(deg_to_rad(7.0))
	return H_HIGH * FloatplaneFlight._ss5(d / 30.0)


## 帰還の機体の原点（h は帰還の秒）。
func _home_position(h: float) -> Vector3:
	var at: Vector3 = _home.plane_at_leave
	var leave := float(_home.get("leave_h", H_LEAVE))
	if h <= leave:
		var times: PackedFloat32Array = _home.path_t
		var dists: PackedFloat32Array = _home.path_d
		var i := clampi(int(h * 120.0), 0, times.size() - 2)
		var f := clampf(h * 120.0 - float(i), 0.0, 1.0)
		var d := lerpf(dists[i], dists[i + 1], f)
		return Vector3(at.x, at.y + _home_height(d), at.z + d)
	var after := h - leave
	var y := at.y + maxf(0.0, after - H_CLIMB_AFTER) * maxf(0.0, after - H_CLIMB_AFTER) * 2.5
	var go := maxf(0.0, after - 0.3)
	var turn := maxf(0.0, after - 0.6)
	var x := at.x + float(_home.get("turn_sign", 1.0)) * 0.5 * H_TURN_ACCEL * turn * turn
	return Vector3(x, y, at.z - H_SPEED * after - 0.5 * H_ACCEL * go * go)


## 帰還の機体：機首は進む向き、低い速さなので機首を少し上げた姿勢（下りるとき・上がるときはそのぶん傾ける）、旋回で翼を傾ける。
## 雲の中で入れ替えた直後は、上昇の機首の角度から 1.5 秒で下りの姿勢へ（雲の中で白いあいだに）。
func _plane_home_xf(h: float) -> Transform3D:
	var p := _home_position(h)
	var vel := (_home_position(h + 0.05) - _home_position(maxf(h - 0.05, 0.0))) / (0.05 + minf(h, 0.05))
	var forward := maxf(-vel.z, 1.0)
	var gamma := atan2(vel.y, forward)
	var pitch := clampf(deg_to_rad(5.5) + gamma * 0.3, deg_to_rad(-4.0), deg_to_rad(14.0))
	pitch = lerpf(float(_home.get("pitch_from", pitch)), pitch, FloatplaneFlight._ss5(h / 1.5))
	var yaw := atan2(-vel.x, forward)
	var leave := float(_home.get("leave_h", H_LEAVE))
	var turn := maxf(0.0, h - (leave + 0.6))
	var bank := atan(float(_home.get("turn_sign", 1.0)) * H_TURN_ACCEL / FloatplaneFlight.G) * smoothstep(0.0, 0.6, turn)
	bank += deg_to_rad(1.1) * sin(TAU * h * 0.37 + 0.6) + deg_to_rad(0.5) * sin(TAU * h * 0.83 + 2.1)
	pitch += deg_to_rad(0.4) * sin(TAU * h * 0.53 + 1.2)
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, bank), p)


func _place_plane_home(h: float) -> void:
	plane.global_transform = _plane_home_xf(h)
	_apply_attitude_carry()
	plane.set_props(1.0)
	var leave := float(_home.get("leave_h", H_LEAVE))
	plane.set_flaps(1.0 - 0.6 * smoothstep(leave + 0.8, leave + 4.0, h))


## 勝者：座って待つ → ベルトを外して立つ → 通り道へ出てスロープの端の手前まで歩く → 端へ駆けて飛び降りる → 着地。
## 着地のクリップが終わったら true。
func _update_home_winner(delta: float) -> bool:
	var winner := int(_home.winner)
	var puppet := director.puppet(winner)
	var clip := String(_home.clip)
	var info: Dictionary = _home.info
	var r: Dictionary = _runners[winner]
	var walker: RefCounted = r.walker
	var xf := plane.global_transform
	walker.set("space", xf)
	var leave := float(_home.get("leave_h", H_LEAVE))
	var t_start := leave - float(info.get("leave", 0.433))
	_home.t_start = t_start
	var c := _t - t_start
	if c < 0.0:
		match str(r.phase):
			"seated":
				DropMotion.place_puppet(puppet, DropMotion.BENCH_SIT, _t + 3.0, _seat_frame(winner))
				puppet.apply_blend(delta)
				if _t >= leave - H_UNBUCKLE_LEAD:
					r.phase = "unbuckle"
					r.u_t = 0.0
			"unbuckle":
				r.u_t = float(r.u_t) + delta * UNBUCKLE_SPEED
				DropMotion.place_puppet(puppet, DropMotion.BENCH_UNBUCKLE, float(r.u_t), _seat_frame(winner))
				puppet.apply_blend(delta)
				if float(r.u_t) >= 0.3 and _cue("unbelt"):
					plane.set_belt(winner, false)
					AudioManager.play_sfx(&"fp_belt", -2.0, 0.85)
				var length := float(DropMotion.clip_info(DropMotion.BENCH_UNBUCKLE).length)
				if float(r.u_t) >= length - 0.02:
					var stood := xf.affine_inverse() * (_seat_frame(winner) * DropMotion.root_offset(DropMotion.BENCH_UNBUCKLE, length))
					walker.set("feet", stood)
					walker.set("yaw", _seat_local_yaw(winner))
					walker.set("speed", 0.0)
					puppet.begin_blend(0.25)
					var lane := Vector3(LANE_X * _side(winner) * 0.6, CABIN_FLOOR, stood.z + 0.4)
					walker.call("set_path", [lane, _home.origin_local as Vector3], 1.7, Walker.RUN)
					r.phase = "walk"
			"walk":
				# 機体と一緒に動く床の上を歩く（歩きの部品は機体のローカル）
				walker.call("step", delta)
				if walker.call("arrived"):
					r.phase = "ready"
			"ready":
				walker.call("turn_to", 0.0, delta, 2.5)
		return false
	var frame: Transform3D
	if c < float(info.get("leave", 0.433)):
		frame = Transform3D(Basis(Vector3.UP, atan2(xf.basis.z.x, xf.basis.z.z)), xf * (_home.origin_local as Vector3))
	else:
		if not _cues.has("leave"):
			_cue("leave")
			# スロープの端から台座へ飛び降りる
			AudioManager.play_sfx(&"fp_jump")
			var at_leave := _plane_home_xf(leave)
			_home.frame = Transform3D(Basis(Vector3.UP, atan2(at_leave.basis.z.x, at_leave.basis.z.z)), at_leave * (_home.origin_local as Vector3))
		frame = _home.frame
	if _cue("home_clip"):
		puppet.begin_blend(0.2)
	var length2 := float(info.get("length", 3.0))
	DropMotion.place_puppet(puppet, clip, minf(c, length2), frame)
	puppet.apply_blend(delta)
	if c >= float(info.get("land", 1.5)) and _cue("land"):
		AudioManager.play_sfx(&"jump_land", -2.0)
		AudioManager.play_sfx(&"crowd_goal_cheer", -8.0)
	if c >= length2:
		var pelvis := puppet.parts().get("pelvis") as Node3D
		if pelvis != null:
			_home.feet = Vector3(pelvis.global_position.x, FLOOR_Y, pelvis.global_position.z)
		return true
	return false


## 帰還のカメラ（カットなし）：機内（操縦席の段の上から後ろ、開いたスロープの外にゴールの観客席と台座が流れていく）
## → 勝者がスロープの端へ歩くと後ろから付いていき → 飛び降りた勝者を追ってスロープから外へ出て → 台座の前（今までの帰還の画）へ下がる。
func _home_camera(h: float, delta: float) -> void:
	var winner := int(_home.winner)
	var xf := plane.global_transform
	var leave := float(_home.get("leave_h", H_LEAVE))
	# 雲の中から操縦席の窓の外（下りていく先の台座）を見て、スロープが開く前に後ろへ向き直る
	var turn_at := leave - H_RAMP_LEAD - 1.9
	var view := _turn_view(h, 1.0 - (h - turn_at) / 1.6) if bool(_home.get("through", false)) else _cabin_view(h)
	var name := "home_cockpit" if h < turn_at + 0.8 and bool(_home.get("through", false)) else "home_cabin"
	var body := director.puppet(winner).center()
	var r: Dictionary = _runners[winner]
	if str(r.phase) in ["walk", "ready"] or h >= float(_home.t_start):
		# 勝者の背中の 2.6 m 前（機首の側）・頭の少し上から、スロープの先を見る（機内に収める）
		var local := xf.affine_inverse() * body
		var eye_local := Vector3(clampf(local.x * 0.4, -1.2, 1.2), CABIN_FLOOR + 2.75, clampf(local.z - 2.8, -3.4, EDGE_Z - 1.8))
		var follow := {"eye": xf * eye_local, "aim": body + xf.basis.z * 3.0 + Vector3(0.0, -0.6, 0.0), "fov": 62.0}
		var w := smoothstep(0.0, 1.2, h - float(_cues.get("walk_cam", h)))
		if not _cues.has("walk_cam"):
			_cues["walk_cam"] = h
		view = Lens.mix(view, follow, w)
		name = "home_follow"
		_lens.focus_on(body)
	if h >= leave:
		# 飛び降りた勝者を追う：カメラはその場にとどまり（機体は前へ進み去るので、カメラは開いたスロープの上を抜けて外へ出る）、
		# 機体が前の上へ離れてから、台座の前の帰還の画へ下がる
		var since := h - leave
		if not _home.has("cam_hold"):
			_home["cam_hold"] = _lens.get("eye")
		var hold: Vector3 = _home.cam_hold
		var home_eye := _podium + Vector3(0.0, 4.6, -15.5)
		var home_aim := _podium + Vector3(0.0, 3.6, 0.0)
		var stay := {"eye": hold + Vector3(0.0, -0.4, 0.0) * smoothstep(0.0, 1.2, since), "aim": body + Vector3(0.0, 0.2, 0.0), "fov": 62.0}
		view = Lens.mix(stay, {"eye": home_eye, "aim": home_aim.lerp(body, 0.35), "fov": 56.0}, FloatplaneFlight._ss5((since - 1.2) / 2.2))
		name = "home_jump"
		_lens.focus_on(body)
	_lens.shoot(view.eye, view.aim, float(view.fov), name)


## 着地した勝者の足もと（台へ跳び乗る始まり）。
func home_feet() -> Vector3:
	return _home.get("feet", _podium) as Vector3


# ================================================================== 走る（共通）

func _start_run(r: Dictionary, puppet: StagingPuppet, path: Array, clip: String, speed: float) -> void:
	r.path = path
	r.seg = 0
	r.clip = clip
	r.clip_t = 0.0
	r.speed = speed
	puppet.begin_blend(0.2)


## 道すじに沿って足もとを進め、進む向きへ体を回す。着いたら true。ground は足もとの (x, z) から床の高さを返す。
func _follow(r: Dictionary, delta: float, ground: Callable) -> bool:
	var path: Array = r.path
	var i := int(r.seg)
	var feet: Vector3 = r.feet
	var step := float(r.speed) * delta
	var heading := Vector3.ZERO
	while i < path.size():
		var target: Vector3 = path[i]
		var flat := Vector3(target.x - feet.x, 0.0, target.z - feet.z)
		var d := flat.length()
		heading = flat
		if d <= step:
			feet = Vector3(target.x, feet.y, target.z)
			step -= d
			i += 1
			if step <= 0.0:
				break
		else:
			feet += flat / maxf(d, 0.0001) * step
			break
	feet.y = float(ground.call(feet))
	r.feet = feet
	r.seg = i
	if heading.length() > 0.05:
		r.yaw = lerp_angle(float(r.yaw), atan2(heading.x, heading.z), 1.0 - exp(-12.0 * delta))
	return i >= path.size()


func _drive_run(puppet: StagingPuppet, r: Dictionary, delta: float) -> void:
	r.clip_t = float(r.clip_t) + delta
	_drive(puppet, String(r.clip), float(r.clip_t), r.feet, float(r.yaw))
	puppet.apply_blend(delta)


## DropMotion のクリップを当て、クリップの根が feet（足もと）に来るように置く（クリップ自身の前への進みは打ち消す）。
func _drive(puppet: StagingPuppet, clip: String, local: float, feet: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var frame := Transform3D(basis, feet - basis * DropMotion.root_offset(clip, local))
	DropMotion.place_puppet(puppet, clip, local, frame)


# ------------------------------------------------------------------ helpers

func _cam(xf: Transform3D, fov: float, shot: String, cut := false) -> void:
	director.stage_camera(xf, fov, shot, cut)


func _look(eye: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


func _cue(cue_name: String) -> bool:
	if _cues.has(cue_name):
		return false
	_cues[cue_name] = _t
	return true


func _side(player: int) -> float:
	return 1.0 if player == 1 else -1.0


## 機首を +X（台座の外の海）へ向けた向き。
func _nose_out() -> Basis:
	return Basis(Vector3.UP, -PI * 0.5)


func _seat_yaw(player: int) -> float:
	var f := _seat_frame(player).basis.z
	return atan2(f.x, f.z)


## カメラを持つ人の狙う点：target をばね（omega、減衰は臨界）で追う。reset でその点に置く。
func _operator(target: Vector3, delta: float, reset := false, omega := 4.0) -> Vector3:
	if reset or not _op_ready:
		_op_aim = target
		_op_vel = Vector3.ZERO
		_op_ready = true
		return _op_aim
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var h := delta / float(steps)
	for _i in range(steps):
		_op_vel += ((target - _op_aim) * omega * omega - _op_vel * 2.0 * omega) * h
		_op_aim += _op_vel * h
	return _op_aim


## 機体の少し先の点（ばねで追うと 2/omega 秒遅れるので、そのぶん先を狙う）。offset は機体の原点からのワールドのずれ。
func _lead_point(t: float, offset: Vector3, omega: float) -> Vector3:
	if _flight == null:
		return plane.global_position + offset
	return _flight.position_at(t + 2.0 / maxf(omega, 0.1)) + offset


## カメラの体（fp_lens.gd）へ、このフレームの揺れの元を渡す（撮る前に呼ぶ）：
##   プロペラの回転（機内の震え）・水の上を走る跳ね（機内のカメラ）・近くを通る機体の風圧（機外のカメラ。プロペラの回転に比例）・
##   開いた後ろの扉から吹き込む風（扉の近くの機内）と、空で開いた扉の外の風（降下・帰還で機外へ出たカメラ）。
##   被写体（機体の真ん中）の位置と速さ（動く被写体の進む側に余白をあける）。
func _feel(delta: float) -> void:
	if _lens == null or plane == null:
		return
	var xf := plane.global_transform
	var center := xf * Vector3(0.0, 2.6, 0.0)
	var vel := Vector3.ZERO
	var fresh := _feel_prev == Vector3.INF or delta <= 0.0 or _feel_prev.distance_to(center) > 90.0 * delta + 2.0
	if not fresh:
		vel = (center - _feel_prev) / delta
		_feel_vel = _feel_vel.lerp(vel, 1.0 - exp(-8.0 * delta))
	elif _feel_prev != Vector3.INF and delta > 0.0:
		# 雲の中の入れ替えで機体が飛んだ：速さは機体の向きへ運ぶ（余白がとばない）
		_feel_vel = xf.basis * (Vector3(0.0, 0.0, -1.0) * _feel_vel.length())
	_feel_prev = center
	_lens.call("track", center, _feel_vel)
	_lens.set("prop", plane.prop_speed)
	if _flight == null:
		_wet = false
	_lens.set("chop", smoothstep(4.0, 28.0, absf(_water_v)) if _wet else 0.0)
	var eye: Vector3 = _lens.get("eye")
	var local := xf.affine_inverse() * eye
	var inside := absf(local.x) < 2.3 and local.y > 1.0 and local.y < 6.2 and local.z > -7.0 and local.z < EDGE_Z + 0.3
	var rumble := 0.0
	if not inside:
		rumble = (1.0 - smoothstep(6.0, 34.0, eye.distance_to(center))) * plane.prop_speed
	var aloft := _scene in ["cruise", "drop", "home"]
	if aloft and plane.ramp_t > 0.2:
		if inside:
			rumble = maxf(rumble, 0.4 * clampf(plane.ramp_t, 0.0, 1.0) * smoothstep(-1.0, HINGE_Z, local.z))
		else:
			rumble = maxf(rumble, 0.6 * (1.0 - smoothstep(8.0, 30.0, eye.distance_to(center))))
	if _scene == "drop" and not inside and eye.y < center.y:
		# 2 人と一緒に落ちている（向かい風）。本戦の画へ渡す前に静める（本戦のカメラは揺れない）
		var calm := 1.0 - smoothstep(_handover_at - 1.2, _handover_at, _t) if is_finite(_handover_at) else 1.0
		rumble = maxf(rumble, 0.4) * calm
	_lens.set("rumble", rumble)


## 水の場面を出る（雲の覆いの下・飛ばしたとき）：航跡と残ったしぶきを消す。
func _clear_water() -> void:
	_flight = null
	_step = ""
	if _wake != null:
		_wake.clear()
	if plane != null:
		plane.clear_water_fx()


## 航跡を消して、波を合わせる海を替える。
func _reset_wake(ocean: MeshInstance3D) -> void:
	if _wake == null:
		return
	_wake.clear()
	_wake.set_ocean(ocean)


## ステージの海（StageEnvironment の Ocean）。
func _stage_ocean() -> MeshInstance3D:
	var env: Node = director.stage_env if director != null else null
	if env == null:
		return null
	var ocean: Variant = env.get("_ocean_surface")
	if ocean is MeshInstance3D and is_instance_valid(ocean):
		return ocean as MeshInstance3D
	return env.find_child("Ocean", true, false) as MeshInstance3D


## カメラのぼけと露出を当て続ける。後ろの扉から差し込む光の演出はなし（2026-10-22 ユーザーの指示で外した）ので、露出は 1 のまま。
func _update_exposure(delta: float) -> void:
	_expo_value = move_toward(_expo_value, 1.0, delta * 0.8)
	_set_exposure(_expo_value, true)


## 監督のカメラの露出の倍率（カメラの体のぼけと同じ設定に当てる。fp_lens.gd）。active でなければ、ぼけも露出も外す
## （水上機の場面を出るとき）。
func _set_exposure(value: float, active: bool) -> void:
	if _lens == null:
		return
	if active:
		_lens.call("set_exposure", value)
	else:
		_lens.call("release_optics")


## 雲の中の入れ替えで、画の環境（空の明るさ・まわりの光・霧）を length 秒かけて from から to へ寄せる（c130_float.md 10.9）。
## 数値と色だけを寄せる（空そのもの＝Sky は入れ替えた瞬間に to のもの。雲の白さで見えない）。寄せ終わったら final を
## カメラへ当てる（null＝舞台の環境）。途中で誰かがカメラの環境を替えたら（中断・やり直し）そこでやめる。
func _blend_environment(from_env: Environment, to_env: Environment, final_env: Environment, length: float) -> void:
	_end_environment_blend()
	var camera := director.main_camera() if director != null else null
	if camera == null or from_env == null or to_env == null or from_env == to_env:
		return
	var blend := to_env.duplicate() as Environment
	var keys: Array = []
	for prop: Dictionary in to_env.get_property_list():
		if not (int(prop.usage) & PROPERTY_USAGE_STORAGE) or not (int(prop.type) in [TYPE_FLOAT, TYPE_COLOR]):
			continue
		var a: Variant = from_env.get(prop.name)
		var b: Variant = to_env.get(prop.name)
		if a == b:
			continue
		keys.append([prop.name, a, b])
		blend.set(prop.name, a)
	# 霧が片方だけにあるときは、ない方を濃さ 0 として寄せる
	if from_env.fog_enabled != to_env.fog_enabled:
		blend.fog_enabled = true
		keys = keys.filter(func(k: Array) -> bool: return k[0] != "fog_density")
		var fa := from_env.fog_density if from_env.fog_enabled else 0.0
		var fb := to_env.fog_density if to_env.fog_enabled else 0.0
		keys.append(["fog_density", fa, fb])
		blend.fog_density = fa
	# 空：舞台の空は天気が時刻の太陽の向きを毎フレーム渡し、本戦の空は渡されない（空の色と、機体に映り込む空が違う）。
	# 同じシェーダーの空なら、入れ替えた先の空を複製して数値を前の空から寄せる
	_sky_blend = null
	_sky_keys = []
	var sky_a := from_env.sky.sky_material as ShaderMaterial if from_env.sky != null else null
	var sky_b := to_env.sky.sky_material as ShaderMaterial if to_env.sky != null else null
	if sky_a != null and sky_b != null and sky_a != sky_b and sky_b.shader != null and sky_a.shader == sky_b.shader:
		var sky_keys: Array = []
		for uniform: Dictionary in sky_b.shader.get_shader_uniform_list():
			if not (int(uniform.type) in [TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR]):
				continue
			var ua: Variant = sky_a.get_shader_parameter(uniform.name)
			var ub: Variant = sky_b.get_shader_parameter(uniform.name)
			if ua == null or ub == null or ua == ub or typeof(ua) != typeof(ub):
				continue
			sky_keys.append([uniform.name, ua, ub])
		if not sky_keys.is_empty():
			var sky := to_env.sky.duplicate() as Sky
			_sky_blend = sky_b.duplicate() as ShaderMaterial
			for k: Array in sky_keys:
				_sky_blend.set_shader_parameter(k[0], k[1])
			sky.sky_material = _sky_blend
			blend.sky = sky
			_sky_keys = sky_keys
	if keys.is_empty() and _sky_keys.is_empty():
		return
	camera.environment = blend
	_env_blend = blend
	_env_keys = keys
	_env_final = final_env
	_env_t = 0.0
	_env_len = maxf(length, 0.01)


func _end_environment_blend() -> void:
	if _env_blend == null:
		return
	var camera := director.main_camera() if director != null else null
	if camera != null and camera.environment == _env_blend:
		camera.environment = null if _scene == "" else _env_final
	_env_blend = null
	_env_keys = []
	_sky_blend = null
	_sky_keys = []


func _process(delta: float) -> void:
	if _skip_hint != null and director != null:
		var english := director.game_state != null and director.game_state.use_english_ui
		_skip_hint.set_shown(director.is_active() and director.can_skip(), english)
		_skip_hint.advance(delta)
	_apply_cloud_light()
	if _env_blend == null:
		return
	var camera := director.main_camera() if director != null else null
	if camera == null or camera.environment != _env_blend:
		_env_blend = null
		_env_keys = []
		_sky_blend = null
		_sky_keys = []
		return
	_env_t += delta
	var u := smoothstep(0.0, 1.0, _env_t / _env_len)
	for k: Array in _env_keys:
		_env_blend.set(k[0], lerp(k[1], k[2], u))
	if _sky_blend != null:
		for k: Array in _sky_keys:
			var value: Variant = lerp(k[1], k[2], u)
			if k[1] is Vector3 and (k[1] as Vector3).is_normalized() and (k[2] as Vector3).is_normalized():
				value = (k[1] as Vector3).slerp(k[2], u)
			_sky_blend.set_shader_parameter(k[0], value)
	if _env_t >= _env_len:
		camera.environment = _env_final
		_env_blend = null
		_env_keys = []
		_sky_blend = null
		_sky_keys = []


## 降下の最後（本戦へ渡す所）の海の深さ：本戦のラウンドの頭の深さ（SkyGatePresenter.round_sea_depth(0)、約 1795 m）にそろえる
## （渡したあと海が沈んでいく動きがなくなる）。本戦がその口を持たないときは DROP_SEA_DEPTH。
func _drop_sea_depth() -> float:
	var presenter: Object = director.presenter() if director != null else null
	if presenter != null and presenter.has_method("round_sea_depth"):
		return float(presenter.call("round_sea_depth", 0.0))
	return DROP_SEA_DEPTH


## 雲の中の入れ替え：機体を入れ替えた先へ置いたあとに呼ぶ。入れ替えの前の機体の姿 before から今の姿への写し（水平の向きの
## 回転と移動）で、雲の層・霧のむら・雲の明暗の太陽・カメラをまとめて運ぶ（機体から見て何も動かない）。そのあと雲の明暗の
## 太陽は入れ替えた先の太陽 sun_to へ ENV_BLEND 秒で回し、カメラは CARRY_BLEND 秒で新しい場面の画へ寄せる。
func _carry_swap(before: Transform3D, sun_to: Vector3) -> void:
	var placed := plane.global_transform
	var map := _yaw_map(before, placed)
	# 機体の傾きも入れ替えの前のまま運び（機内のカメラが機体に対してずれない）、ATTITUDE_BLEND 秒で新しい場面の姿勢へ戻す
	var carried := map * before
	_att_offset = placed.basis.orthonormalized().inverse() * carried.basis.orthonormalized()
	_att_until = _t + ATTITUDE_BLEND
	plane.global_transform = carried
	_cloud.call("relocate", map)
	_cloud.call("set_sun", sun_to, ENV_BLEND)
	_lens.carry(map, CARRY_BLEND)


## 入れ替えで運んだ機体の傾きを、新しい場面の姿勢に重ねる（置いた直後に呼ぶ。ATTITUDE_BLEND 秒でなくなる）。
func _apply_attitude_carry() -> void:
	if _att_until < 0.0:
		return
	var w := 1.0 - FloatplaneFlight._ss5(1.0 - (_att_until - _t) / ATTITUDE_BLEND)
	if w <= 0.0:
		_att_until = -1.0
		return
	var xf := plane.global_transform
	plane.global_transform = Transform3D(xf.basis * Basis.IDENTITY.slerp(_att_offset, w), xf.origin)


## a から b への写し：水平の向きの回転（機首の向きの差）と移動（a の位置を b の位置へ）。
static func _yaw_map(a: Transform3D, b: Transform3D) -> Transform3D:
	var fa := -a.basis.z
	var fb := -b.basis.z
	var yaw := Basis(Vector3.UP, atan2(-fb.x, -fb.z) - atan2(-fa.x, -fa.z))
	return Transform3D(yaw, b.origin - yaw * a.origin)


## 雲の中の日の光：カメラの層の中の深さで、舞台の太陽・地面の照り返し（GroundBounce）・画面のふちの暗さ（ビネット）を
## 弱める（毎フレーム、舞台の天気が太陽を決めたあと）。いちばん深い所では 0 なので、入れ替えで機体と太陽の向きの関係が
## 変わっても、地上の表示が消える／戻る（照り返しとビネットも一緒に消える／戻る）ときも、画が変わらない。
## ほかの誰か（天気など）が値を変えたら、それを元の値として覚え直す。層の外では元の値へ戻して手を離す。
func _apply_cloud_light() -> void:
	var depth := float(_cloud.get("depth")) if _cloud != null and _scene != "" else 0.0
	var k := 1.0 - smoothstep(SUN_IN_CLOUD.x, SUN_IN_CLOUD.y, depth)
	if k >= 1.0 and _dims.is_empty():
		return
	_look_atmosphere()
	_dim("sun", _sun_node(), &"light_energy", false, k)
	_dim("bounce", _bounce_light, &"light_energy", false, k)
	_dim("vignette", _vignette_material, &"strength", true, k)


func _dim(key: String, target: Object, prop: StringName, param: bool, k: float) -> void:
	if target == null or not is_instance_valid(target):
		_dims.erase(key)
		return
	var current := float(target.get_shader_parameter(prop) if param else target.get(prop))
	var d: Dictionary = _dims.get(key, {})
	var active: bool = d.has("applied") and d.get("target") == target
	if not active or not is_equal_approx(current, float(d.applied)):
		d = {"target": target, "prop": prop, "param": param, "base": current}
		active = false
	if k >= 1.0:
		if active:
			_set_dim(target, prop, param, float(d.base))
		_dims.erase(key)
		return
	d["applied"] = float(d.base) * k
	_dims[key] = d
	_set_dim(target, prop, param, float(d.applied))


static func _set_dim(target: Object, prop: StringName, param: bool, value: float) -> void:
	if param:
		(target as ShaderMaterial).set_shader_parameter(prop, value)
	else:
		target.set(prop, value)


func _restore_cloud_light() -> void:
	for key: String in _dims.keys():
		var d: Dictionary = _dims[key]
		var target: Object = d.get("target")
		if target == null or not is_instance_valid(target) or not d.has("applied"):
			continue
		var current := float(target.get_shader_parameter(d.prop) if d.param else target.get(d.prop))
		if is_equal_approx(current, float(d.applied)):
			_set_dim(target, d.prop, d.param, float(d.base))
	_dims.clear()


## 舞台の雰囲気（StageAtmosphere）の地面の照り返しの光とビネットの材質を探す（画質を変えて作り直されたら探し直す）。
func _look_atmosphere() -> void:
	var stage: Node = director.stage_env if director != null else null
	if stage == null:
		return
	var bounce_ok := _bounce_light == null or is_instance_valid(_bounce_light)
	var vignette_ok := _vignette_material == null or is_instance_valid(_vignette_material)
	if _atmosphere_looked and bounce_ok and vignette_ok:
		return
	_atmosphere_looked = true
	_bounce_light = stage.find_child("GroundBounce", true, false) as DirectionalLight3D
	_vignette_material = null
	for layer: Node in stage.find_children("*", "CanvasLayer", true, false):
		if layer.has_meta(&"stage_atmosphere_vignette"):
			var rect := layer.get_node_or_null("Vignette") as CanvasItem
			if rect != null:
				_vignette_material = rect.material as ShaderMaterial
			break


func _sun_node() -> DirectionalLight3D:
	var env: Variant = director.stage_env if director != null else null
	var light: Variant = env.get("directional_light") if env != null else null
	return light as DirectionalLight3D if light is DirectionalLight3D else null


## 舞台の環境（WorldEnvironment。カメラに環境を当てていないときに映る環境）。
func _world_environment() -> Environment:
	var camera := director.main_camera() if director != null else null
	var world := camera.get_world_3d() if camera != null else null
	if world == null:
		return null
	return world.environment if world.environment != null else world.fallback_environment


## 舞台の太陽へ向かう向き（ワールド）。
func _stage_sun() -> Vector3:
	var env: Variant = director.stage_env if director != null else null
	var light: Variant = env.get("directional_light") if env != null else null
	if light is DirectionalLight3D:
		return (light as DirectionalLight3D).global_transform.basis.z.normalized()
	return Vector3(-0.22, 0.77, 0.6).normalized()


func get_debug_snapshot() -> Dictionary:
	var out := {"scene": _scene, "t": snappedf(_t, 0.01), "handover_at": snappedf(_handover_at, 0.01)}
	if plane != null:
		out["plane"] = [snappedf(plane.global_position.x, 0.01), snappedf(plane.global_position.y, 0.01), snappedf(plane.global_position.z, 0.01)]
		out["plane_visible"] = plane.visible
	var phases := {}
	for player: int in _runners:
		phases[player] = str((_runners[player] as Dictionary).get("phase", ""))
	out["runners"] = phases
	if not _home.is_empty():
		out["home_clip"] = _home.get("clip", "")
	if _cloud != null:
		out["cloud_depth"] = snappedf(float(_cloud.get("depth")), 0.01)
	if _flight != null:
		var now := _flight.sample(_t)
		out["step"] = _step
		out["flight"] = {"v": snappedf(float(now.v), 0.01), "a": snappedf(float(now.a), 0.01), "d": snappedf(float(now.d), 0.01),
			"touchdown_at": snappedf(_flight.touchdown_at, 0.01) if is_finite(_flight.touchdown_at) else -1.0,
			"liftoff_at": snappedf(_flight.liftoff_at, 0.01) if is_finite(_flight.liftoff_at) else -1.0,
			"stop_at": snappedf(_stop_at, 0.01) if is_finite(_stop_at) else -1.0}
	return out
