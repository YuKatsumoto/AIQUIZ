class_name OnlineStagingTimeline
extends RefCounted

## オンライン対戦のマッチング演出（docs/online_match_staging/spec.md）の調整できる値。
## 時刻・カメラ・速さはここだけに置き、演出のコードに数値を散らさない（仕様書 17）。
##
## 座標の約束（仕様書 5）：カメラ・目印は「ヘリの座標（H）」で書く。
##   原点＝ヘリの接地点（スキッドの下面の中心）、+x＝機体の右、+y＝上、-z＝機首。
## ヘリポートのビルダー（assets/online_heliport/source/blender/ohp_common.py）は CAMERAS を
## この形のまま正規表現で読むので、1 行 1 カメラ・Vector3(...) の書き方を崩さないこと。

## 状態の長さ（秒）。"short" は設定「オンラインの えんしゅつ：みじかい」（D11）
## v1.6：REVEAL は火花を散らし震えながらゆっくり開くので長くした（1.80 → 3.20、みじかいは 1.30 → 2.20）。
## v1.3：ユーザーの依頼で、どの場面も長く見せる。CLIMB は「ホバー → ジェットブーストを広げる → 急発進 → 暗転」（仕様書 22）
const DURATIONS := {
	"normal": {
		"BOARDING": 4.70, "COCKPIT": 2.40, "TAKEOFF": 2.60, "CLIMB": 4.40,
		"JOIN": 3.20, "FORMATION": 1.80, "CUTIN_IN": 0.90, "CUTIN_HOLD_MIN": 1.40, "REVEAL": 3.20,
	},
	"short": {
		"BOARDING": 2.94, "COCKPIT": 0.0, "TAKEOFF": 1.60, "CLIMB": 3.00,
		"JOIN": 2.20, "FORMATION": 1.20, "CUTIN_IN": 0.90, "CUTIN_HOLD_MIN": 0.80, "REVEAL": 2.20,
	},
}
## みじかい演出の乗り込みは、ふつうの動きを 1.6 倍で再生する
const SHORT_BOARDING_SPEED := 1.6
## 早めのマッチ（仕様書 4）。乗り込みは 2.6 倍（v1.3 で長くした分を取り戻す）。合流・並走・読み込みの最短は「みじかい」の長さ（2.20・1.20・0.80）にする
const EARLY_BOARDING_SPEED := 2.6
const EARLY_TAKEOFF_SPEED := 1.5
const EARLY_TAKEOFF_SECONDS := 1.0
const EARLY_LIFT_TO_JOIN := 0.6
const CANCEL_FADE_SECONDS := 0.35
const REQUEUE_LEAVE_SECONDS := 1.2
const GUEST_START_WARN_SECONDS := 12.0
const REVEAL_SYNC_TIMEOUT := 4.0

## カメラ（H 座標）。pos＝位置、look＝注視点、fov＝縦の画角（度）
## S1〜S5 の実際のカメラは下の MOVE_*／CRUISE_SEQUENCE（動くカメラ）。CAM_Board・CAM_Cockpit・CAM_PadLow は
## ヘリポートのビルダーが確認用のカメラとして読む代表の画（CAM_Idle は街の置き場所の基準にもなる。動かさない）
const CAMERAS := {
	"CAM_Idle": {"pos": Vector3(-10.2, 3.1, -8.6), "look": Vector3(-1.0, 1.7, -0.6), "fov": 40.0},
	"CAM_Board": {"pos": Vector3(-7.2, 1.45, -4.4), "look": Vector3(-1.3, 1.65, -1.3), "fov": 42.0},
	"CAM_Cockpit": {"pos": Vector3(-0.3, 2.35, -6.6), "look": Vector3(0.0, 2.15, -1.2), "fov": 34.0},
	"CAM_PadLow": {"pos": Vector3(-8.5, 0.55, -9.5), "look": Vector3(0.0, 2.4, 0.0), "fov": 50.0},
	"CAM_Formation": {"pos": Vector3(-6.0, 1.6, -26.0), "look": Vector3(-6.0, 1.3, 0.0), "fov": 30.0},
}
## 飛んでいるショットも H（自分のヘリの接地点。揺れは含めない枠）を基準にする

## S0 待機のゆっくりした揺れ（周期 9 秒と 7 秒、振れ幅 m）
const IDLE_DRIFT := {"period_x": 9.0, "amp_x": 0.12, "period_y": 7.0, "amp_y": 0.06}
## S7 並走：カメラは毎秒 1.0 m 下がる
const FORMATION_DOLLY_BACK := 1.0

# ---------- S1〜S5 のカメラワーク（仕様書 21。v1.2） ----------
# 撮り方の決まり：
#   ・カメラはずっと機体の左（太陽の側。順光）にいる。ヘリの進む向きは、上昇から検索中まで画面の左（イマジナリーラインを越えない）
#   ・止まった画を切り替えるのではなく、どのショットも動機のある動き（追う・寄る・上がる・回り込む）をする
#   ・注視は被写体を画面の決めた位置（screen：-1〜1、右と上が正）に置く。進む向きの前を空ける
#   ・揺れ（シェイク）は使わない（仕様書 16）。手持ちの「ただよい」は 0.13〜0.34 Hz の低い周波数だけ

## カメラの道具（StagingCameraRig）：ただよいの大きさ、ぼけ（被写界深度）、機体の傾きにつられる割合
const CAMERA_RIG := {
	"float_pos_m": 0.05, "float_yaw_deg": 0.30, "float_pitch_deg": 0.22,
	"float_fade_seconds": 1.2,
	# ピントの距離 f に対して：奥は f × (1 + far_start) からぼけ始め、f × far_transition でぼけきる。手前は f × near_start より近く
	"dof_far_start": 0.45, "dof_far_transition": 1.6, "dof_near_start": 0.55, "dof_near_transition": 0.30,
	"focus_lag": 0.20,
}

## 被写体（H 座標）。キャラは体の中心（StagingPuppet.center）を追う
const SUBJECTS := {
	"heli": Vector3(0.0, 1.9, 0.6),       # 機体の中心（客室と尾の真ん中より少し前）
	"cockpit": Vector3(-0.2, 2.15, -1.3), # 2 人の顔のあいだ（少しプレイヤー寄り）
}

## S1 乗り込み（3.30 秒、1 本の長回し）：待機の画からそのまま動き出し、歩くキャラと並んで 3/4 前へ回り込み、
## 段を上がるところで低く構え、座ってドアが閉まるところへ寄る。時刻は乗り込みの始まりから（秒）。
## pos の最初の点（0 秒）は待機のカメラ（止まった状態から加速する）。aim_in の間に、待機の注視からキャラを追う注視へ移る
const MOVE_BOARD := {
	"pos": [[1.50, Vector3(-8.7, 2.25, -6.6)], [2.85, Vector3(-7.0, 1.75, -4.75)], [4.70, Vector3(-5.9, 1.9, -3.6)]],
	"fov": [[0.0, 40.0], [1.50, 38.0], [2.85, 36.0], [4.70, 34.0]],
	"screen": [[0.0, Vector2(0.14, 0.02)], [1.50, Vector2(0.18, 0.06)], [2.85, Vector2(0.08, 0.06)], [4.70, Vector2(0.10, 0.02)]],
	"aim_in": [0.10, 0.90],
	"lag_look": 0.14, "float": 0.6, "dof": 0.06,
}
## S2 操縦席（2.40 秒）：正面から 2 人の顔へゆっくり押し込む（ドリーイン＋少しズーム）。キーは状態の進み（0〜1）
const MOVE_COCKPIT := {
	"pos": [[0.0, Vector3(-0.75, 1.95, -8.4)], [1.0, Vector3(-0.30, 2.30, -6.0)]],
	"fov": [[0.0, 34.0], [1.0, 29.0]],
	"screen": [[0.0, Vector2(0.0, 0.02)], [1.0, Vector2(0.0, 0.06)]],
	"aim": "cockpit", "lag_look": 0.0, "float": 0.4, "dof": 0.08,
}
## S3 離陸〜S4 急発進のカメラの位置（パッドの H）。三脚に据えたように動かさず、向き（パン・ティルト）と画角だけで追う
const LIFTOFF_CAMERA_POS := Vector3(-10.8, 3.4, -6.6)
## S3 離陸：パッドの左前の少し高い所に据えたカメラから、上がっていくヘリを向きだけで追う。
## 注視はばねで少し遅れ、ヘリは画面の上へ抜けていく。キーは離陸の進み（0〜1。早めのマッチの 1.0 秒でも同じ形）
const MOVE_TAKEOFF := {
	"pos": [[0.0, LIFTOFF_CAMERA_POS]],
	"fov": [[0.0, 46.0], [1.0, 54.0]],
	"screen": [[0.0, Vector2(0.04, 0.0)], [1.0, Vector2(0.04, 0.10)]],
	"aim": "heli", "lag_look": 0.22, "float": 0.0, "dof": 0.0,
}
## S4 ジェットブーストの急発進（CLIMB）：離陸の画から切らずに続ける 1 本。カメラは離陸と同じ位置から動かず、
## 点火で一度だけ短く揺れ（IGNITE_KICK。向きだけ）、向き（パン・ティルト）と
## ズーム（画角を狭める）で、画面の左の空へ小さくなっていくヘリを追う。キーは CLIMB の進み（0〜1）
const MOVE_BOOST := {
	"pos": [[0.0, LIFTOFF_CAMERA_POS]],
	"fov": [[0.0, 54.0], [0.48, 40.0], [0.62, 31.0], [0.84, 22.0], [1.0, 19.0]],
	"screen": [[0.0, Vector2(0.04, 0.10)], [0.48, Vector2(0.06, 0.12)], [0.60, Vector2(0.14, 0.06)], [1.0, Vector2(0.06, 0.0)]],
	"aim": "heli", "lag_look": 0.10, "float": 0.0, "dof": 0.0,
}
## 点火の一瞬の揺れ（Helldivers 2 の発進の手ごたえ。0.45 秒で消える。光の点滅はない）
const IGNITE_KICK := {"deg": 0.55, "m": 0.0, "seconds": 0.45, "rate": 21.0}
## S6 合流（JOIN）のカメラ：並走の位置の左前の斜め上から。注視は動かない点（自分のヘリ → 並走の真ん中）なので、
## 相手のヘリは画面の右の外から飛び込んでくる。キーは JOIN の進み（0〜1）、位置は揺れない枠の H
const MOVE_JOIN := {
	"pos": [[0.0, Vector3(-30.0, 11.0, -30.0)], [1.0, Vector3(-21.0, 6.5, -28.0)]],
	"fov": [[0.0, 34.0], [1.0, 30.0]],
	"aim_points": [[0.0, Vector3(-3.0, 1.9, 0.6)], [0.6, Vector3(-6.0, 1.9, 0.6)], [1.0, Vector3(-6.0, 1.9, 0.6)]],
	"screen": [[0.0, Vector2(0.05, 0.0)], [1.0, Vector2(0.0, -0.02)]],
	"lag_look": 0.25, "float": 0.8, "dof": 0.03,
}

## S5 検索中（ループ）：空撮の 6 本を順に。どれも左（太陽の側）から撮り、ヘリは画面の左へ進む。
## 1 本 CRUISE_SHOT_SECONDS 秒。終わりの CRUISE_BLEND_SECONDS 秒で次のショットへ、機体のまわりを回り込んでつなぐ
## （"cut": true のショットへは切る）。from → to は見えている間の一定の速さの動き（カメラの船が少しずつ位置を変える）。
## screen の y は下の帯（検索の文言）より上にヘリを置く。bank は機体の横揺れにつられて画面を傾ける割合
const CRUISE_SHOT_SECONDS := 12.0
const CRUISE_BLEND_SECONDS := 3.0
const CRUISE_SEQUENCE := [
	{"name": "CR_Chase", "from": Vector3(-7.5, 3.2, 13.5), "to": Vector3(-5.8, 2.6, 11.8), "fov": [44.0, 42.0], "aim": "heli", "screen": Vector2(0.0, 0.16), "bank": 0.30, "dof": 0.03},
	{"name": "CR_Profile", "from": Vector3(-17.0, 2.2, 2.5), "to": Vector3(-16.5, 3.0, -1.5), "fov": [30.0, 30.0], "aim": "heli", "screen": Vector2(-0.04, 0.14), "bank": 0.0, "dof": 0.03},
	{"name": "CR_Hero", "from": Vector3(-8.0, 1.1, -11.6), "to": Vector3(-5.6, 1.5, -10.6), "fov": [34.0, 31.0], "aim": "cockpit", "screen": Vector2(0.10, 0.24), "bank": 0.25, "dof": 0.07},
	{"name": "CR_High", "from": Vector3(-12.0, 7.5, -9.0), "to": Vector3(-10.5, 8.0, -6.0), "fov": [40.0, 39.0], "aim": "heli", "screen": Vector2(0.0, 0.14), "bank": 0.0, "dof": 0.03},
	{"name": "CR_Wide", "from": Vector3(-30.0, 7.0, -19.0), "to": Vector3(-21.0, 5.0, -12.5), "fov": [36.0, 35.0], "aim": "heli", "screen": Vector2(0.26, 0.18), "bank": 0.0, "dof": 0.0},
	{"name": "CR_Low", "from": Vector3(-13.0, -4.4, 10.5), "to": Vector3(-11.0, -3.6, 7.0), "fov": [44.0, 42.0], "aim": "heli", "screen": Vector2(0.0, 0.18), "bank": 0.20, "dof": 0.03, "cut": true},
]
## 検索中のショットの注視の遅れ（秒）。機体の揺れを、カメラマンが少し遅れて追う
const CRUISE_LAG_LOOK := 0.35
## 探し直し（REQUEUE）から検索中へ戻るとき：並走の画（正面）からいちばん近い CR_Hero（左前）へ、この秒数でつなぐ
const REQUEUE_CAMERA_BLEND := 2.4
const REQUEUE_CRUISE_SHOT := 2

## S1 乗り込み（プレイヤーの動き）。時刻は BOARDING の始まりから。目印は helicopter_boarding_layout.json
const BOARD := {
	"turn_end": 0.45,          # ヘリの方を向く（ハテナが手を振るのを見る）
	"walk_end": 1.50,          # MK_BoardStand まで歩く（Walk_Loop × 1.0）
	"walk_rate": 1.0,
	"step1_end": 1.95,         # MK_Step（1 段目）
	"step2_end": 2.45,         # MK_DoorSill（2 段目、かがむ）
	"crouch_mix": 0.30,
	"turn_seat_end": 2.85,     # MK_SeatFront へ移りながら機首へ 90° 回る
	"sit_end": 4.15,           # Sitting_Enter（1.3 秒）で MK_SeatPassenger へ
	"door_open_at": 0.0,
	"door_close_at": 4.00,
	"belt_at": 4.50,
	"belt_grow": 0.12,
	"wave_end": 1.60,          # ハテナが手を振る
	"ui_hide": 0.25,           # 操作の列が左へ消える
}
## S1 プレイヤーの動きの区切りのつなぎ（秒。StagingPuppet.begin_blend）。"前>次"。
## 立つ → 歩く → 座る → ハンドルを握る を、切れ目のない 1 つの動きに見せる。ここにない組み合わせ（待機へ戻す・飛ばす）はつながない
const CAST_BLEND := {
	"idle>walk": 0.30,         # 立ち姿から歩き出す
	"walk>sit": 0.40,          # かがんで向きを変えたところから座り始める
	"sit>drive": 0.60,         # 座り終わりから手を伸ばしてハンドルを握る
}
## S2 操縦席（2 人が前を向き、ハテナが前を指す。ローターが回りきる）
const COCKPIT := {"point_start": 0.60, "point_end": 1.60, "rotor_start_from_boarding_end": -0.10}

## ローター（OnlineHeliportHelicopter と同じ式）
const SPOOL_UP_RATE := 0.45
const SPOOL_DOWN_RATE := 0.22
const SPOOL_LIFTOFF := 0.6
const ROTOR_BLUR_SPOOL := 0.8

## S3 離陸の水しぶき（離陸の始まりからの秒、半径 m）
const TAKEOFF := {"splash_start": 0.0, "splash_end": 3.4, "splash_r0": 2.0, "splash_r1": 16.0}
## S3〜S4 の発進の道すじ（StagingFlight.departure。仕様書 24）：ホバーで止まらず、浮いたら前へ進みながら上がり、
## 左（カメラの側）へ旋回しはじめる（旋回の向きへ傾き、カメラに機体の上面を見せる）。点火のあとも旋回を少し続け、
## ゆるめながら画面の左へ飛び去る
const DEPART := {
	"pre_seconds": 4.5,                        # 浮いてから点火までの長さ（ふつう：離陸 2.4 秒＋CLIMB の 0.48）。ほかの長さでは同じ道すじを速さを変えて通る
	"rise_seconds": 1.0, "climb_mps": 4.5,     # 浮いて 1 秒で上へ 4.5 m/秒になり、そのまま上がり続ける
	"climb_gain_mps": 6.0,                     # 旋回しながら上る速さをさらに足していく（点火の直前で 10.5 m/秒。点火で高さ約 27 m）
	"pre_speed": 9.0,                          # 点火の直前の前への速さ（m/秒。0 からだんだん速める）
	"pre_turn_deg": -40.0,                     # 点火までに回る角度（正＝右、負＝左）
	"pre_pitch_deg": 32.0,                     # 旋回しながら機首を上へ向けていく（正＝機首上げ。この機体は尾が上へ反っているので大きめに）
	"turn_decay_seconds": 0.55,                # 点火のあと、旋回がゆるむ速さ（さらに約 20° 回る）
	"bank_gain": 1.0, "max_bank_deg": 28.0,    # 傾き＝横の加速度からの角度（最大 28°）
	"bank_blend_seconds": 0.25,                # 点火のあと、最大の傾きへ深める長さ（そのあと暗転まで保つ）
}
## S4 ジェットブーストの急発進（CLIMB。Helldivers 2 の発進のイメージ）。時刻は CLIMB の進み（0〜1。みじかいでも同じ形）。
##   旋回しながら上がるあいだに左右のジェットポッドを広げて溜める（機体が震える）→ 点火して旋回の向きの前の上へ急発進 →
##   カメラは向きで追う → 暗転して検索中へ
const BOOST := {
	"charge_start": 0.06, "charge_end": 0.48,  # ポッドを広げて溜める（OnlineHeliportHelicopter.set_jet_charge 0 → 1）
	"fade_start": 0.84, "fade_end": 0.97,      # 暗転（このあと検索中の画面で明ける）
	"speed": 120.0, "accel_seconds": 0.60,     # 点火から 0.6 秒で 120 m/秒
	"climb_deg": 34.0,                         # 前から上へ向ける角度
	"pitch_deg": 36.0, "pitch_seconds": 0.35,  # 機首を上げて、上る向きへ機体を向ける
	"shudder_m": 0.07, "shudder_rate": 145.0,  # 溜めの震え（機体ごと。カメラは揺らさない）
	"rotor_factor_charge": 1.55, "rotor_factor_boost": 1.8,
}
## 暗転から明けるまで（検索中に入ったとき）・早めのマッチで暗転の途中から合流に切ったとき
const CRUISE_FADE_IN := 0.60
const JOIN_FADE_IN := 0.35

## S5 検索中の飛行（原点を動かさない：海と雲を流す）
const CRUISE := {
	"speed": 24.0,
	"roll_deg": 6.0, "roll_period": 8.0,
	"pitch_deg": -3.0, "pitch_amp_deg": 1.0, "pitch_period": 5.0,
	"bob_m": 0.35, "bob_period": 5.0,
	"yaw_deg": 4.0, "yaw_period": 11.0,
	"altitude": 70.0,
}

## S6 合流：相手のヘリの道すじ（自分のヘリの H 座標）。最後が並走の位置（D15：間隔 12 m、自分の左）。
## 画面の外（うしろ左の高い所）からジェットブーストで飛び込み、曲がりながら（横の加速度で傾く）寄ってきて、
## jets_off でジェットを切り、機首を上げて（フレア）速さを落とし、並走の位置で止まる
const JOIN_PATH := [Vector3(-62.0, 24.0, 52.0), Vector3(-44.0, 14.0, 24.0), Vector3(-27.0, 6.0, 8.0), Vector3(-16.0, 1.5, 1.2), Vector3(-12.0, 0.0, 0.0)]
const JOIN := {
	"arrive": 0.82,            # 道すじの終わりに着く進み（そのあとは揺れに合わせる）
	"jets_off": 0.55,          # ジェットを切る進み
	"fold_seconds": 0.60,      # ポッドを畳む
	"bank_per_mps2": 1.6, "max_bank_deg": 42.0,   # 横の加速度 1 m/s² あたりの傾き（度）
	"pitch_per_mps2": 1.1, "max_pitch_deg": 16.0, # 前後の加速度で機首を上げ下げ（減速で上げる）
	"title_in": 0.20, "title_out": 2.60, "you_blue_in": 0.40, "you_blue_out": 2.40, "band_hide": 0.30,
}
const FORMATION_SPACING := 12.0
const FORMATION_SWAY_OFFSET := 0.7

## S8 カットイン（CUTIN_IN の始まりから）
const CUTIN := {
	"vignette_end": 0.18,
	"panels_end": 0.30, "panels_overshoot": 1.2,
	"bolt_start": 0.24, "bolt_end": 0.32, "flash_alpha": 0.45, "flash_seconds": 0.06,
	"chars_start": 0.30, "chars_end": 0.60,
	"vs_start": 0.42, "vs_end": 0.68, "shake_px": 6.0, "shake_seconds": 0.18,
	"names_start": 0.55, "names_end": 0.85,
	"rules_start": 0.70, "rules_end": 0.90,
	"gauge_in": 0.20,
}
## 稲妻の線（画面の幅・高さに対する割合）
const SEAM_POINTS := [Vector2(0.535, -0.02), Vector2(0.475, 0.20), Vector2(0.548, 0.36), Vector2(0.462, 0.58), Vector2(0.540, 0.76), Vector2(0.488, 1.02)]
## カットインのポーズ（D13）：[クリップ, スロット（AnimationRig）, 位置 0〜1]。
## 箱の人形を正面から撮り比べて決めた（artifacts/online_staging/probes/poses_front.png）
const CUTIN_POSES := [
	["Idle_FoldArms_Loop", 25, 0.30],
	["Punch_Cross", 24, 0.50],
	["Yes", 25, 0.20],
	["Dance_Loop", 24, 0.20],
]

## 音（仕様書 13）。効果音は今の方針（壁の音だけ）に合わせて既定では鳴らさない。VS のスティングは素材ができたら鳴る
const SFX_ENABLED := false
## [状態, その状態に入ってからの秒, 効果音の名前]
const SFX_TIMES := [
	["BOARDING", 0.10, "door_open"], ["BOARDING", 1.70, "step_metal"], ["BOARDING", 2.20, "step_metal"],
	["BOARDING", 4.50, "belt_click"], ["COCKPIT", 0.0, "rotor_spool"], ["JOIN", 0.0, "whoosh_flyby"],
	["CUTIN_IN", 0.24, "cutin_lightning"],
]
## VS のスティング：「VS」が落ちる 0.42 秒に頭の一打（0.3 秒目）を合わせるため、0.12 秒早く鳴らす
const STING_AT := 0.30


static func durations(short_mode: bool) -> Dictionary:
	return DURATIONS["short" if short_mode else "normal"]


static func camera(name: String) -> Dictionary:
	return CAMERAS.get(name, CAMERAS["CAM_Idle"])


## 名前から決まるカットインのポーズの番号（両方の画面で同じになる）。
static func cutin_pose_index(player_name: String) -> int:
	var h := 0
	for i in range(player_name.length()):
		h = (h * 31 + player_name.unicode_at(i)) % 1000003
	return h % CUTIN_POSES.size()
