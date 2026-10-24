extends "res://tests/pv_capture/pv_take_base.gd"

## PV S09「実際のプレイ画面（カウントダウンからボス壁まで）」を、本物の GameWorld の 10 問・難易度「普通」の通しで撮る。
## 既定はローカル 2P（S04〜S07 と同じく 2 人）。players=1 で 1 人版（2026-10-20 の最初の版）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s09 quality=ultra sub=8 tag=s09_sub8
## PV のための専用の演出（PV カメラ・スロー・HUD の切り替え・演技の上乗せ）は使わない。カメラ・HUD・効果音・時間の速さはゲームのまま
## （2 人の HUD の対戦カード・連続正解の炎のバッジ・後ろのチップソー・やられた人の小窓と幽霊のサメもゲームのまま）。
## 外から決めるのは「問題（offline_bank.json の算数 4 年から固定）」と「キー入力」だけ。キーは毎回の更新の前に、
## いまのゲームの状態（いる位置・相手の位置・次の壁までの距離・壁の速さ）から決めて本物のキーイベントで送る（同じ台本なら何度でも同じ絵になる）。
## 出来事の間の待ちは詰めない（通しのまま）。各出来事の PV フレームを report.json の events に書き、40 拍に詰めるのは編集（レーン 6）。
##
## 流れ（ゲームの状態どおり）:
##   開始待ち（WAITING_START）：準備中に届いた 10 枚の壁の最後の 1 枚が落ちるところから撮り始める → カウントダウンの壁が落ちて着地
##   → 着地の ENTER_DELAY 秒後に Enter → 空撮（FLYOVER 3.8 秒）→ カウントダウン（5〜1、4.99 秒）→ 壁が爆発して PLAYING
##   2 人（_plan_2p）：1 問目は 2 人とも正解のドアへ、P1 が先に突き破る → 2 問目は P2 がわざと不正解のドアへ（ゴツン、P2 のハート 3 → 2）、
##   P1 は少し遅れて正解 → 3 問目で P2 がコンベアの横から落ちてサメに噛まれる（ハートに関係なく脱落し、幽霊のサメになる）、P1 は正解
##   → P2 の幽霊がサメに乗り、照準を P1 へ合わせてチャージし、PERFECT で放して P1 に体当たり（P1 はベルトの上に残る。ghost_hit=0 で無し）
##   → 4〜10 問目は P1 が正解（10 問目は 4 択のボス壁）→ ゴールレース（P1 はゴールへ走る）
##   1 人（players=1）：1 問目正解 → 2 問目わざと不正解（ハート 3 → 2）→ 3〜10 問目正解 → クリア。fall=<問題番号> でその問題で横から落ちる
##   （1 人ではサメで脱落するとゲームオーバーなので、落下とボス壁は 1 回の通しに入らない）
## 人が遊んでいるような動き（human。human=0 で v3 のまっすぐなだけの動き）。v5（2026-10-22 ユーザーの指示）で、ジャンプを減らして
## プレイヤー同士の押し合い（docs/local_push_duel.md）を多くし、PV では少ないカット（2 本の通し）で見せられる順番にした：
##   カウントダウンは 2 人が踊る（「1」のあいだにジャンプのキーで止める。カウントダウン中は跳ばない）
##   → 1 問目：2 人が同じ正解のドアに並び、肩で押し合う（P1・P2・P1・同時に当たって相殺・P1）→ 2 人とも突破
##   → 2 問目：P1 が P2 を一押しで突き放し、P2 はそのまま不正解の赤いドアへ（ゴツン）
##   → 3 問目：右の端に立った P2 に P1 が追いついて肩で押し、海へ落とす → P1 は勝ち誇って踊る → サメが噛む（ジャンプで踊りを止めて戻る。
##     ジャンプはこの 1 回だけ）→ 4〜8 問目は P1 だけ → 9 問目（ボス壁の直前）で、踊って待つ P1 に幽霊のサメが体当たり
##   → 遅れた P1 の後ろにチップソー → 10 問目のボス壁（となりのドアへ寄りかけてから）→ ゴールレース
## 押し合いは、横に並んで体が触れた 2 人が相手へ向かう左右キーを押して踏ん張り、片方がそのキーを離して押し直すと一押し（同じ更新で
## 離して押す：_shove）。エモートはゲームのキー（1・2・3 / 8・9・0）、踊り出しの最初のフレームの T ポーズは写し直す（_fix_emote_start）。
## ヘリの到着は飛ばす（リトライと同じ。プレイヤーは最初からベルトの上）。昼の位相 0.25（ほかのカットと同じ）。
## sub=8 の撮影だけの手当て：ゲームのカメラの揺れとカウントダウン中のバリアの震えは、更新ごとに乱数の位置へ飛ぶ。sub 回に分けた
## 更新を重ねると 4 重写しになるので、揺れている間だけ、PV フレームの撮る最初の更新の位置をそのフレームの終わりまで保つ
## （60 fps のゲームと同じく 1 フレームに 1 回だけ揺れる。_hold_random_jitter）。サメの襲撃のカメラはなめらかな揺れなので保たない。

const SUBJECT := "算数"
const GRADE := 4
const DIFFICULTY := "普通"
## 10 問（ゲームの順。1 問目がいちばん手前の壁）。問題文は問題集のまま（ゲームが和文間の空白を詰め、分数を縦書きにして看板に出す）。
## 2026-10-20 ユーザーの指示で選び直した：暗算で答えられる問題だけにし、ジャンルを分け（面積・単位・分数・角度・小数・わり算・かけ算・角）、
## 看板が 1 行か、切れ目の自然な 2 行（「たて8cm、よこ6cmの / 長方形の面積は？」「【角度】分度器で測る / ものは何？」）になる問題にした
## （折り返しは tests/pv_capture/measure_question.gd で確かめる）。
## [問題, ドアの並び（0 番 = +x・後ろから見て左の青、1 番 = −x・右の赤）]。2 択は問題集の正解と誤答 1 つ（ゲームは誤答を乱数で選んで
## 並びも混ぜるので、ここで固定する）、4 択は問題集の並びのまま。正解の番号は問題集の正解の文字から決める（_install_quizzes で照らし合わせる）
const QUIZZES := [
	["たて8cm、よこ6cmの長方形の面積は？", ["48㎠", "14㎠"]],
	["1㎡は何㎠ですか？", ["10000㎠", "100㎠"]],
	["【分数】2/5 ＋ 1/5 =", ["3/5", "2/5"]],
	["【角度】分度器で測るものは何？", ["長さ", "角度"]],
	["【小数】0.3 ＋ 0.5 =", ["0.8", "0.08"]],
	["96 ÷ 4 の答えは？", ["14", "24"]],
	["【分数】4/7 － 2/7 =", ["3/7", "2/7"]],         # 正解を右（−x）に：幽霊のサメの体当たりは右のドアの前で受ける
	["【計算】25 × 4 ＝ ？", ["110", "100"]],
	["【小数】4.5 - 1.2 =", ["3.3", "2.3"]],
	["1直角は 何度ですか？", ["45度", "60度", "90度", "180度"]],
]
## human では、3 問目（右の端で押し落とす）と 9 問目（幽霊のサメの体当たり）の正解を右（−x）のドアにする（並びを入れ替える）
const HUMAN_SWAPPED_Q := [3, 9]
const WRONG_Q := 2                    # わざと不正解のドアへ行く問題（1 始まり）。誤答の「100㎠」は赤いドア（青い P2 が見分けやすい）
const P2_FALL_Q := 3                  # 2 人のとき P2 がコンベアから落ちる問題
const P2_FALL_SIDE := -1.0            # P2 は −x（後ろから見て右）へ落ちる（2 問目の赤いドアの側。P1 の前を横切らない）
## 見た目（pv_v3_runtime.gd と同じ。このPCの保存データは読まない）
const P1_HAT := 11                    # プロペラ帽子
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12                    # キツネ帽子
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"
const DAY_PHASE := 0.25
const WARMUP_FRAMES := 150            # 問題を渡す前に回す（影・シェーダーの準備）

## 遊び方（ゲームの秒）
const ENTER_DELAY := 1.0              # カウントダウンの壁が着地してから Enter を押すまで
const READ_SEC := 0.5                 # 問題が出てから動き出すまで（読む間）
const BOSS_READ_SEC := 0.9            # 4 択のボス壁は少し長く読む
const FALL_READ_SEC := 0.35           # 落ちる問題で横へ走り出すまで
const PLAYER_SPEED := 7.6             # GameTuning.player_speed（斜めは入力が正規化されて各 0.71 倍）
const ALIGN_TOL := 0.12               # ドアの中心からこの範囲に入ったら横を離す（ドアの半分の幅は 2 択 1.8 m・4 択 1.45 m）
const RUN_SAFETY := 1.5               # 斜めに走るとドアの正面へ着く前に壁へ届くときは、前を離して横だけにする（その余裕 m）
## キー：[+x（後ろから見て左）, −x, 前]
const MOVE_KEYS := {1: [KEY_A, KEY_D, KEY_W], 2: [KEY_LEFT, KEY_RIGHT, KEY_UP]}

## 人が遊んでいるような動き（human）。エモートの枠は S16・S21 の台本と同じ
const P1_EMOTES: Array[int] = [2, 7, 13]          # キー 1 = ホースダンス、2 = シリーダンス、3 = YMCA
const P2_EMOTES: Array[int] = [17, 19, 15]        # キー 8 = ランニングマン、9 = ウェーブヒップホップ、0 = ヒップホップ2
const EMOTE_KEYS := {1: [KEY_1, KEY_2, KEY_3], 2: [KEY_8, KEY_9, KEY_0]}
const JUMP_KEYS := {1: KEY_SPACE, 2: KEY_CTRL}    # P2 は右 Ctrl（pv_take_base.gd の send_key が右として送る）
const TAP_SEC := 0.1                  # エモート・ジャンプのキーを押す長さ（ゲームの秒）
const DANCE_AFTER_LAND := [0.25, 0.55]  # カウントダウンの壁が着地してから踊り出すまで（P1, P2）
const DANCE_SWITCH_AT := [3, 2]       # カウントダウンのこの数字で、踊りを替える（P1 は YMCA、P2 はウェーブ）
const DANCE_STOP_LEFT := [0.45, 0.35]  # カウントダウンの残りがこの秒になったら、ジャンプのキーで踊りを止める（カウントダウン中は跳ばない）
const TAUNT_DELAY := 0.3              # 3 問目に P2 を海へ落としてから、P1 が勝ち誇って踊り出すまで
const GHOST_DANCE_DELAY := 0.15       # P1 が体当たりを待って立ち止まってから踊り出すまで

## 押し合い（human。scripts/core/local_push_duel.gd）
const BODY := 1.24                    # LocalPushDuel.BODY_WIDTH：横に並んで体が触れる 2 人の間（前後の差 0 のとき）
const DUEL_Q := 1                     # 同じドアに並んで押し合う問題
## 1 問目の押し合い：体が触れてからの秒と、押す人（1・2、0 = 2 人が同時に押して相殺）。押せる状態（拮抗が 0.1 秒続いた直後）に
## なるまでは待つ。終わったら DUEL_RUN 秒おいて、2 人とも前へ走ってドアを突き破る
const DUEL_SHOVES := [[0.30, 1], [0.72, 2], [1.14, 1], [1.56, 0], [1.98, 1]]
const DUEL_RUN := 0.45
const DUEL_P2_OFFSET := 1.0           # P2 は P1 の内側（右）を狙う（体の幅 1.24 より内側を狙い、肩が当たって止まったところで触れる）
const PART_SHOVE_AT := 0.25           # 2 問目：P2 が踏ん張ってからこの秒で、P1 が P2 を突き放す
const PART_WAIT_MAX := 0.9            # 突き放しが出なくても、この秒で P2 は不正解のドアへ走り出す
const EDGE_X := -11.75                # 3 問目に P2 が立ち止まる、右の端の近く（端は |x| 12。一押し 0.52 m で落ちる）
const EDGE_SHOVE_AFTER := 0.18        # 3 問目：体が触れてからこの秒で、P1 が押す（拮抗 0.1 秒のあと）
const GHOST_HIT_Q_HUMAN := 9          # human：体当たりはボス壁の直前の 9 問目（そのままボス壁へ続けて撮れる）

## 幽霊のサメの体当たり（2 人。P2 が脱落したあと、tests/pv_capture/pv_s17_runtime.gd と同じ操作）。
## サメは P2 が落ちた側（右、−x）のコンベアの外で P1 より先に浮かぶので、突進は右前から左後ろへの斜めになり、命中すると P1 は
## 左（+x）後ろへ最大 18 m/s で弾かれる（10 m/s² で弱まり、何もしなければ約 16 m）。P1 が右のドア（x = −3.5）の前にいれば、左の端（12 m）
## の内側に止まる。命中のあと P1 は自分のドアへ戻ろうと横だけ押して踏ん張る（前は弾かれる勢いが弱まってから）。
## 体当たりをするのは、照準ができる（AIMING）ようになってから最初に出る、正解が右のドアの問題（GHOST_HIT_MIN_Q 問目から。human では 9 問目）。
## P1 はその問題で正解のドアの正面に立ち止まり（GHOST_HIT_STAND 秒より短くは待たない）、P2 が照準を P1 へ滑らせてチャージし、PERFECT で放す
const GHOST_HIT_MIN_Q := P2_FALL_Q + 1
const GHOST_AIM_DELAY := 0.3          # P1 が立ち止まってから照準を動かし始めるまで（秒）
const GHOST_AIM_SPEED := 9.0          # GhostSharkRideController.AIM_SPEED（m/s）
const GHOST_CHARGE_GAP := 0.45        # 照準が P1 に着いてからチャージを押すまで
const GHOST_CHARGE_HOLD := 0.415      # 右 Ctrl を押す長さ。0.415 / 0.5 = 0.83（PERFECT の帯 0.72〜0.94 の真ん中）
const P1_RECOVER_SPEED := 1.5         # 弾かれる勢いがこれ（m/s）より弱まるまで、P1 は前へ走らない

## 撮る長さ
const MAX_FRAMES := 4800              # 安全のための上限（80 秒）
const HOLD_AFTER_FRAMES := 180        # 最後の出来事（ボス壁の突破・1 人の落下ではサメ）のあと、編集のつなぎ用に撮る長さ

## 問題だけを固定で渡す出題元（通信しない・記録しない）。released までは何も返さず、準備中で止めておく
class PinnedProvider extends QuizProvider:
	var items: Array[QuizItem] = []
	var released := false
	var _given := 0

	func _load_bank() -> Dictionary:
		return {}

	func get_quizzes(_subject: String, _grade: int, _difficulty: String,
			_mode: String, count: int, _exclude_texts: Array[String] = []) -> Array[QuizItem]:
		var result: Array[QuizItem] = []
		if not released:
			return result
		while result.size() < count and _given < items.size():
			result.append(items[_given])
			_given += 1
		return result

	func submit_result(_quiz: QuizItem, _correct: bool) -> void:
		pass

var gs: QuizGameState
var world: Node
var player: PlayerController
var provider: PinnedProvider
var camera_controller: Node
var cam: Camera3D
var ride: Node                         # GhostSharkRideController
var players := 2
var ghost_hit := true                  # 2 人のとき、幽霊のサメで P1 に体当たりする（ghost_hit=0 で前の版）
var fall_q := 0                        # 1 人のとき：0 = ふだんの通し。1〜10 = その問題でコンベアから落ちる
var fall_side := 1.0                   # 落ちる側（+1 = +x・後ろから見て左）
var _explicit_frames := false
var _bank: Dictionary = {}
var _answers: Array[int] = []
var _saved_provider_mode := ""
var _events: Array = []
var _questions: Array = []
var _trace: Array = []
var _last_state := ""
var _barrier_seen := false
var _barrier_landed_time := -1.0
var _enter_sent := false
var _countdown_shown := 0
var _q_index := -1
var _q_shown_time := 0.0
var _end_frame := -1
var _boss_frame := -1
var _fell := {}                        # 人 → フレーム
var _ocean := {}
var _bite := {}
var _ghost := {}
var _hp_log: Array = []
var _frame_pose := Transform3D()
var _frame_fov := 0.0
var _frame_barrier := Vector3.ZERO
var _hold_camera := false
var _hold_barrier := false
var _camera_held_frames := 0
var _barrier_held_frames := 0
var _hit_q := -1                       # 体当たりをする問題（1 始まり）
var _p1_ready_t := -1.0                # その問題で P1 がドアの正面に立ち止まったゲームの秒
var _aim_key := KEY_NONE
var _aim_end_t := -1.0
var _charge_start_t := -1.0
var _last_ride_phase := -1
var _ghost_hit_frame := -1
var _ghost_resolved := false
var _ghost_power := 0.0
var _ghost_perfect := false
var _p1_after_hit: Array = []          # 命中のあと P1 がいちばん端へ寄った位置など
var human := true                      # 人が遊んでいるような動き（human=0 で前の版）
var _taps: Dictionary = {}             # 短く押しているキー → 離すゲームの秒
var _acts: Dictionary = {}             # 一度だけの動き（名前 → 押した PV フレーム）
var _playing_t := -1.0                 # PLAYING に入ったゲームの秒
var _boss_t := -1.0                    # ボス壁を突き破ったゲームの秒
var _last_emote := [0, 0]
var _jump_counts := [0, 0]
var _emote_log: Array = []
var _shove_queue: Array = []           # この更新の前に一押しする人（同じ更新でキーを離して押し直す）
var _push_log: Array = []              # ゲームの押し合いの出来事（contact・hit・clash）
var _duel_contact_t := -1.0            # 1 問目の押し合いで体が触れたゲームの秒
var _duel_step := 0                    # DUEL_SHOVES のどこまで押したか
var _duel_last_t := -1.0               # 最後に押したゲームの秒
var _duel_p2_target := 0.0
var _part_hit_t := -1.0                # 2 問目に P1 が P2 を突き放したゲームの秒
var _edge_contact_t := -1.0            # 3 問目に P1 が P2 に触れたゲームの秒
var _edge_shoves := 0
var _edge_last_shove_t := -1.0
var _edge_fall_t := -1.0               # 3 問目に P2 が落ちた（落下が確定した）ゲームの秒
var hide_wipe := true                  # 幽霊がサメに乗ったあとは、右下の小窓（ワイプ）を出さない（wipe_keep で出す）
var _wipe_hidden := false
var _shark_track: Array = []           # 乗ってから登場までのサメの場所と画面の位置（report の ghost.shark_track）


func _init() -> void:
	take_name = "s09"


func _default_frames() -> int:
	return MAX_FRAMES


func _parse_arg(arg: String) -> void:
	if arg.begins_with("players="):
		players = clampi(int(arg.trim_prefix("players=")), 1, 2)
	elif arg.begins_with("fall="):
		fall_q = clampi(int(arg.trim_prefix("fall=")), 0, QUIZZES.size())
	elif arg.begins_with("fall_side="):
		fall_side = -1.0 if float(arg.trim_prefix("fall_side=")) < 0.0 else 1.0
	elif arg.begins_with("ghost_hit="):
		ghost_hit = arg.trim_prefix("ghost_hit=") != "0"
	elif arg.begins_with("human="):
		human = arg.trim_prefix("human=") != "0"
	elif arg == "wipe_keep":
		hide_wipe = false


## 台本：問題番号（1 始まり）と人 → 動き。do = "correct"（正解のドア）/ "wrong"（不正解のドア）/ "fall"（横から落ちる）/ ""（何もしない）。
## read = 問題が出てから動き出すまでの秒。behind = 相手より behind m 後ろにいる間だけ前へ走る（相手がこの問題を答えるまで。2 人が
## 同じ列で重ならないため。チップソーは先頭の 14 m 後ろまで迫るので、それより近くに保つ）
func _plan(q: int, p: int) -> Dictionary:
	var read := BOSS_READ_SEC if q == QUIZZES.size() else READ_SEC
	if players == 1:
		if fall_q == q:
			return {"do": "fall", "read": FALL_READ_SEC}
		return {"do": "wrong" if q == WRONG_Q else "correct", "read": read}
	return _plan_2p(q, p, read)


func _plan_2p(q: int, p: int, read: float) -> Dictionary:
	var plan := _plan_2p_moves(q, p, read)
	if human:
		plan.merge(_plan_2p_human(q, p), true)
	return plan


func _plan_2p_moves(q: int, p: int, read: float) -> Dictionary:
	if p == 1:
		if q == WRONG_Q:
			# P2 が先にゴツンするのを待つ：P2 より 7 m 後ろを保って正解のドアへ走る（P2 が前を斜めに横切って赤いドアへ行く）
			return {"do": "correct", "read": 0.25, "behind": 7.0}
		if q == P2_FALL_Q:
			# P2 が落ちてサメに噛まれる（右下の小窓）のと、P1 の正解の緑の光が重ならないよう、P2 が噛まれて脱落するまで走り出さない
			return {"do": "correct", "read": READ_SEC, "wait_other_out": true}
		return {"do": "correct", "read": read}
	match q:
		1:
			# 1 問目は P2 も正解のドアへ。P1 の 3 m 後ろを走るので P1 が先に突き破る
			return {"do": "correct", "read": 0.8, "behind": 3.0}
		WRONG_Q:
			return {"do": "wrong", "read": 0.3}
		P2_FALL_Q:
			return {"do": "fall", "read": FALL_READ_SEC, "side": P2_FALL_SIDE}
	return {"do": "", "read": 0.0}


## 人が遊んでいるような動き（human、v5）。do を置き換えるもの（上書き）と、足すものがある。
##   do = "duel"：同じ正解のドアに並んで押し合う（_duel_keys。P1 がドアの中心、P2 はその内側に並ぶ。DUEL_SHOVES）
##   part_shove（P1）/ parted（P2）：2 問目の頭に、2 人とも踏ん張り、P1 が P2 を一押しで突き放す（P2 はそのまま不正解のドアへ）
##   do = "edge_wait"（P2）：右の端（EDGE_X）まで走って立ち止まり、P1 が触れたら踏ん張る（P1 の押しの予備動作の間は力を抜く）
##   do = "edge_push"（P1）：P2 の内側まで走って肩で押し、海へ落とす。落としたら勝ち誇って踊り、サメが噛んだら跳んで止めて正解のドアへ
##   wiggle = 読んだあと、決めたドアへ向かう前に [ドア, 秒] の順に横だけ寄る（迷い。"correct" / "wrong" / ドアの番号）
func _plan_2p_human(q: int, p: int) -> Dictionary:
	match q:
		DUEL_Q:
			return {"do": "duel", "read": 0.5 if p == 1 else 0.6}
		WRONG_Q:
			return {"part_shove": true} if p == 1 else {"parted": true}
		P2_FALL_Q:
			return {"do": "edge_push", "read": READ_SEC} if p == 1 else {"do": "edge_wait", "read": FALL_READ_SEC}
		10:
			if p == 1:
				return {"wiggle": [[3, 0.35]]}                    # ボス壁：となりの「180度」へ寄りかけてから「90度」
	return {}


func _ghost_hit_min_q() -> int:
	return GHOST_HIT_Q_HUMAN if human else GHOST_HIT_MIN_Q


func _setup() -> void:
	var explicit_tag := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("frames="):
			_explicit_frames = true
		elif arg.begins_with("tag="):
			explicit_tag = true
	if players == 1 and fall_q > 0:
		# 1 人の落下の版は、出力先の既定を s09_fall にする
		take_name = "s09_fall"
		report["tool"] = "pv_take_" + take_name
		if not explicit_tag:
			tag = take_name
			out = OUT_ROOT + tag + "/"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	elif players == 2:
		fall_q = 0                             # 2 人では落ちるのは台本の P2（P2_FALL_Q）
	if players == 1:
		human = false                          # 押し合い・踊りは 2 人の台本
	_bank = JSON.parse_string(FileAccess.get_file_as_string("res://offline_bank.json"))
	provider = PinnedProvider.new()
	provider.items = _install_quizzes()
	gs = QuizGameState.new(provider)
	gs.num_players = players
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"                  # 問題集の問題。問題がそろったらすぐ開始待ちへ（ゲームのオフラインの流れ）
	gs.subject = SUBJECT
	gs.grade = GRADE
	gs.difficulty = DIFFICULTY
	gs.tuning.wall_speed_override = 0.0      # 壁の速さは自動（問題の予測解答時間から。ゲームの既定）
	gs.start_game()                          # ゲームと同じ初期化。出題元がまだ何も返さないので準備中（PRELOADING）で止まる
	gs.skip_start_helicopter_arrival = true  # リトライと同じく、プレイヤーは最初からベルトの上
	gs.p1_hat = P1_HAT
	gs.set_player_skin(1, PlayerSkin.from_code(P1_SKIN_CODE))
	if players == 2:
		gs.p2_hat = P2_HAT
		gs.set_player_skin(2, PlayerSkin.from_code(P2_SKIN_CODE))
	gs.p1_emote_slots = P1_EMOTES.duplicate()        # 選手の骨格がエモートを読み込む前に（GameWorld を作る前に）決める
	gs.p2_emote_slots = P2_EMOTES.duplicate()
	gs.local_push_event.connect(_on_push_event)
	gs.question_completed.connect(_on_question_completed)
	gs.health_changed.connect(_on_health_changed)
	gs.player_entered_ocean.connect(_on_entered_ocean)
	QuizManager.game_state = gs
	_saved_provider_mode = QuizManager.provider.llm_mode
	QuizManager.provider.llm_mode = "OFFLINE"   # GameWorld は準備中の壁の落とし方をグローバルの出題元の設定で決める
	var scene := load("res://scenes/game_world.tscn") as PackedScene
	world = scene.instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	player = world.get_node("Player") as PlayerController
	player.prepare_for_loading(gs)
	await _frames(30)
	var stage: StageEnvironment = world.get("stage_env")
	var weather: Node = stage.get("weather_cycle") if stage != null else null
	if weather != null:
		weather.call("force_day_phase", DAY_PHASE)
	camera_controller = world.get("camera_controller")
	cam = camera_controller.get_node_or_null("Camera3D") as Camera3D
	ride = world.get("_ghost_shark_ride_controller")
	if players == 1:
		ghost_hit = false
	await _frames(WARMUP_FRAMES)
	# 問題を渡す → ゲームが開始待ちへ進み、準備中の 10 枚の壁を組み立てて奥から順に落とす。最後の 1 枚が落ち始めたら撮り始める
	provider.released = true
	var waited := 0
	while not _all_preview_drops_started() and waited < 1200:
		await get_tree().process_frame
		waited += 1
	if not _all_preview_drops_started():
		failures.append("setup: preview walls did not start dropping (state %s, quizzes %d)" % [gs.game_state, gs.quiz_list.size()])
	_last_state = gs.game_state
	var plan := []
	for q in range(1, QUIZZES.size() + 1):
		plan.append([_plan(q, 1), _plan(q, 2)] if players == 2 else [_plan(q, 1)])
	report["plan"] = {
		"players": players, "subject": SUBJECT, "grade": GRADE, "difficulty": DIFFICULTY, "fall_q": fall_q, "fall_side": fall_side,
		"enter_delay": ENTER_DELAY, "setup_updates": waited, "per_question": plan, "human": human,
		"emote_slots": [P1_EMOTES, P2_EMOTES],
	}


## 問題集（offline_bank.json の算数 4 年）と照らし合わせて QuizItem を作る。予測解答時間は問題集の t（問題を作った AI の予測）
func _install_quizzes() -> Array[QuizItem]:
	var items: Array[QuizItem] = []
	var bank_items: Array = _bank.get(SUBJECT, {}).get(str(GRADE), [])
	for i in range(QUIZZES.size()):
		var q: String = QUIZZES[i][0]
		var choices: Array = (QUIZZES[i][1] as Array).duplicate()
		if human and HUMAN_SWAPPED_Q.has(i + 1) and choices.size() == 2:
			choices.reverse()                      # 正解を右（−x）のドアへ
		var found: Dictionary = {}
		for raw: Dictionary in bank_items:
			if str(raw.get("q", "")) == q:
				found = raw
				break
		var answer := 0
		var est := 4.0
		if found.is_empty():
			failures.append("bank: %s %d年「%s」が見つからない" % [SUBJECT, GRADE, q])
		else:
			var c: Array = found.get("c", [])
			var correct := str(c[int(found.get("a", 0))])
			answer = choices.find(correct)
			for choice: Variant in choices:
				if not c.has(choice):
					failures.append("bank: 「%s」の選択肢「%s」が問題集にない（%s）" % [q, str(choice), str(c)])
			if answer < 0:
				failures.append("bank: 「%s」の正解「%s」がドアにない" % [q, correct])
				answer = 0
			if choices.size() == 4 and choices != c:
				failures.append("bank: 「%s」の 4 択の並びが問題集と違う" % q)
			est = clampf(float(found.get("t", 4.0)), 1.5, 10.0)
		var item := QuizItem.create(q, PackedStringArray(choices), answer, str(found.get("exp", "")), "OFFLINE")
		item.estimated_seconds = est
		items.append(item)
		_answers.append(answer)
		var expected := 4 if i == QUIZZES.size() - 1 else 2
		if choices.size() != expected:
			failures.append("plan: Q%d は %d 択のはず" % [i + 1, expected])
	return items


func _all_preview_drops_started() -> bool:
	if gs.game_state != Constants.STATE_WAITING_START:
		return false
	var started: Array = world.get("_pw_drop_started")
	if started.size() < QUIZZES.size():
		return false
	for value: bool in started:
		if not value:
			return false
	return true


# ------------------------------------------------------------------ 入力（毎回の更新の前に、いまの状態から決める）

func _before_update(_n: int) -> void:
	if players == 2:
		world.set("_push_focus_lost", false)   # 撮影中にウィンドウのフォーカスが外れても、押し合いの入力の扱いを変えない
	hold_keys(_keys_now())
	# 一押し：相手へ向かうキーを、同じ更新の中で離して押し直す（tests/local_push_runtime.gd の _repress と同じ）
	for p: int in _shove_queue:
		var key := _inward_key(p)
		send_key(key, false)
		send_key(key, true)
		_event("shove", {"player": p, "q": gs.current_index + 1, "key": OS.get_keycode_string(key)})
	_shove_queue.clear()


func _keys_now() -> Dictionary:
	var want: Dictionary = {}
	match gs.game_state:
		Constants.STATE_WAITING_START:
			if _barrier_landed_time >= 0.0 and not _enter_sent and _game_time - _barrier_landed_time >= ENTER_DELAY:
				want[KEY_ENTER] = true
				_enter_sent = true
				_event("enter_pressed")
		Constants.STATE_PLAYING:
			for p in range(1, players + 1):
				want.merge(_play_keys(p))
			if players == 2 and not gs.p2_alive:
				want.merge(_ghost_keys())
		Constants.STATE_GOAL_RACE:
			if gs.p1_alive:
				want[KEY_W] = true                    # ボス壁のあと、P1 はゴールへ走る
	if human:
		_human_acts()
	for key: Variant in _taps.keys():
		if _game_time < float(_taps[key]):
			want[key] = true
		else:
			_taps.erase(key)
	return want


## 人が遊んでいるような動きのうち、問題によらないもの：待っている間の踊り（カウントダウンの「1」で跳ばずに止める）、
## 体当たりのあと踊りを止める
func _human_acts() -> void:
	var state := gs.game_state
	if state in [Constants.STATE_WAITING_START, Constants.STATE_FLYOVER, Constants.STATE_COUNTDOWN] and _barrier_landed_time >= 0.0:
		for p in range(1, players + 1):
			if _game_time - _barrier_landed_time >= DANCE_AFTER_LAND[p - 1]:
				_act("p%d_dance_wait" % p, EMOTE_KEYS[p][0], p)            # P1 ホースダンス、P2 ランニングマン
			if state == Constants.STATE_COUNTDOWN and _countdown_shown > 0 and _countdown_shown <= DANCE_SWITCH_AT[p - 1]:
				_act("p%d_dance_switch" % p, EMOTE_KEYS[p][2 if p == 1 else 1], p)   # P1 YMCA、P2 ウェーブヒップホップ
			# カウントダウン中のジャンプのキーは踊りを止めるだけ（ゲームは PLAYING でしか跳ばない）。スタートの前に離す
			if state == Constants.STATE_COUNTDOWN and _countdown_shown == 1 and gs.countdown_timer <= DANCE_STOP_LEFT[p - 1]:
				_act("p%d_dance_stop" % p, JUMP_KEYS[p])
	if _acts.has("p1_dance_ghost") and _ghost_hit_frame > 0:
		_act("p1_dance_ghost_stop", JUMP_KEYS[1])                         # 弾かれて宙にいる間に押すので、踊りが止まるだけ（跳ばない）


## 一度だけの動き：key を TAP_SEC 秒押す。on_floor_of（人の番号）を渡したら、その人が床の上にいるときだけ（エモートは宙では始まらない）
func _act(name: String, key: Key, on_floor_of := 0) -> bool:
	if _acts.has(name):
		return false
	if on_floor_of > 0 and (gs.player_y if on_floor_of == 1 else gs.player2_y) > 0.0:
		return false
	_acts[name] = _signal_frame()
	_taps[key] = _game_time + TAP_SEC
	_event("act_" + name, {"key": OS.get_keycode_string(key)})
	return true


func _play_keys(p: int) -> Dictionary:
	var want: Dictionary = {}
	if not _active(p) or gs.choice_locked or _evaluated(p):
		return want
	var index := gs.current_index
	if index >= QUIZZES.size():
		return want
	var plan := _plan(index + 1, p)
	var keys: Array = MOVE_KEYS[p]
	var since := _game_time - _q_shown_time
	var other := 3 - p
	# 2 問目の頭：2 人とも相手へ向かうキーで踏ん張り、P1 が P2 を一押しで突き放す（P2 はそのまま不正解のドアへ）
	if (plan.has("part_shove") or plan.has("parted")) and not _part_done(since) and _active(other):
		want[_inward_key(p)] = true
		if plan.has("part_shove") and since >= PART_SHOVE_AT and _part_hit_t < 0.0 and _can_shove(p) \
				and not _shove_queue.has(p) and _find_event_where("shove", {"player": p, "q": index + 1}).is_empty():
			_shove_queue.append(p)
		return want
	if str(plan["do"]) == "" or since < float(plan["read"]):
		return want
	match str(plan["do"]):
		"fall":
			# コンベアの横から落ちる：ドアへ向かわずに横へ走り続ける
			want[keys[0] if float(plan.get("side", fall_side)) > 0.0 else keys[1]] = true
			return want
		"duel":
			return _duel_keys(p, index)
		"edge_wait":
			return _edge_wait_keys(p)
		"edge_push":
			if not _acts.has("taunt_stop_q%d" % (index + 1)):
				return _edge_push_keys(p, index)
	# 迷い：決めたドアへ向かう前に、ほかのドアへ横だけ少し寄る（前へは走らない）
	var wt := since - float(plan["read"])
	for step: Array in plan.get("wiggle", []):
		if wt < float(step[1]):
			var wdx := _door_x(_plan_door(step[0], index)) - _x(p)
			if absf(wdx) > ALIGN_TOL:
				want[keys[0] if wdx > 0.0 else keys[1]] = true
			return want
		wt -= float(step[1])
	var door := _plan_door(plan["do"], index)
	var dx := _door_x(door) - _x(p)
	var dist := gs.wall_z - 0.4 - _z(p)                         # 壁の判定まで
	var wall_speed := float(gs.get("_active_wall_speed"))
	var run := true
	if absf(dx) > ALIGN_TOL:
		want[keys[0] if dx > 0.0 else keys[1]] = true
		var diag := PLAYER_SPEED * 0.70710678
		if dist - (diag + wall_speed) * absf(dx) / diag < RUN_SAFETY:
			run = false
	if plan.has("behind") and players == 2 and _active(other) and not _evaluated(other) \
			and _z(p) > _z(other) - float(plan["behind"]):
		run = false
	if plan.get("wait_other_out", false) and players == 2 and (gs.p2_alive if other == 2 else gs.p1_alive):
		run = false                                             # 相手が落ちてサメに噛まれる（脱落する）まで待つ
	if p == 1 and index + 1 == _hit_q and not _ghost_resolved:
		# 幽霊のサメの体当たりを、正解のドアの正面に立ち止まって受ける（human では踊りながら待つ）
		run = false
		if absf(dx) <= ALIGN_TOL and _p1_ready_t < 0.0:
			_p1_ready_t = _game_time
			_event("p1_stand_for_ghost", {"q": index + 1, "x": snappedf(_x(1), 0.01)})
		if human and _p1_ready_t >= 0.0 and _game_time - _p1_ready_t >= GHOST_DANCE_DELAY:
			_act("p1_dance_ghost", EMOTE_KEYS[1][0], 1)         # ホースダンス
	if p == 1 and gs.p1_external_velocity.length() > P1_RECOVER_SPEED:
		run = false                                             # 弾かれている間は横だけ押して踏ん張る
	if run:
		want[keys[2]] = true
	return want


# ------------------------------------------------------------------ 押し合い（human）

## 相手へ向かう左右キー（P1：相手が −x なら D、P2：相手が +x なら ←）。押し合いの向き（pose_direction）と同じ
func _inward_key(p: int) -> Key:
	if p == 1:
		return KEY_D if gs.player2_x < gs.player_x else KEY_A
	return KEY_LEFT if gs.player_x > gs.player2_x else KEY_RIGHT


## いま一押しできるか：体が触れていて、拮抗（2 人とも相手へ向かうキー）が 0.1 秒続いた直後の受付の間にいて、次の一押しまでの間も過ぎた
func _can_shove(p: int) -> bool:
	var lp = gs.local_push
	return bool(lp.contact) and float(lp.armed_until) >= float(lp.time) and float(lp.time) >= float(lp.cooldown_until[p - 1]) \
		and float(lp.pending[p - 1]) < 0.0


func _part_done(since: float) -> bool:
	return (_part_hit_t >= 0.0 and _game_time - _part_hit_t >= 0.05) or since >= PART_WAIT_MAX


## 1 問目：P1 は正解のドアの中心、P2 はその内側（DUEL_P2_OFFSET）へ横だけで寄る（2 人とも前へは走らないので前後はそろったまま）。
## 体が触れたら 2 人とも相手へ向かうキーで踏ん張り、DUEL_SHOVES の時刻に一押しする（押せる状態になるまでは待つ。0 は 2 人同時で相殺）。
## 押し終えて DUEL_RUN 秒たったら、横を離して前へ走り、2 人並んでドアを突き破る
func _duel_keys(p: int, index: int) -> Dictionary:
	var want: Dictionary = {}
	var keys: Array = MOVE_KEYS[p]
	var lp = gs.local_push
	var door_x := _door_x(_answers[index])
	if _duel_p2_target == 0.0:
		_duel_p2_target = door_x + (DUEL_P2_OFFSET if gs.player2_x > door_x else -DUEL_P2_OFFSET)
	if _duel_contact_t < 0.0 and bool(lp.contact):
		_duel_contact_t = _game_time
		_event("duel_contact", {"q": index + 1, "x": [snappedf(gs.player_x, 0.01), snappedf(gs.player2_x, 0.01)]})
	var done := _duel_step >= DUEL_SHOVES.size()
	var dist := gs.wall_z - 0.4 - _z(p)
	var give_up := (_duel_contact_t < 0.0 and _game_time - _q_shown_time > 3.0) or dist < 4.0
	if (done and _game_time - _duel_last_t >= DUEL_RUN) or give_up:
		want[keys[2]] = true                                    # 2 人並んで前へ
		return want
	if _duel_contact_t < 0.0:
		var target := door_x if p == 1 else _duel_p2_target
		var dx := target - _x(p)
		if absf(dx) > 0.06:
			want[keys[0] if dx > 0.0 else keys[1]] = true
		return want
	want[_inward_key(p)] = true                                 # 踏ん張る
	if p == 2 and not done:
		# 押す順番は P2 の更新でまとめて決める（P1 の分も。相殺は 2 人が同じ更新で押し直す）
		var at: float = DUEL_SHOVES[_duel_step][0]
		var who: int = DUEL_SHOVES[_duel_step][1]
		if _game_time - _duel_contact_t >= at:
			var ready := (_can_shove(1) and _can_shove(2)) if who == 0 else _can_shove(who)
			if ready:
				for q_p: int in ([1, 2] if who == 0 else [who]):
					_shove_queue.append(q_p)
				_duel_step += 1
				_duel_last_t = _game_time
	return want


## 3 問目の P2：右の端（EDGE_X）まで横に走って立ち止まる。P1 が触れたら相手へ向かうキーで踏ん張るが、P1 の一押しの予備動作と
## 押されている間は力を抜く（抵抗すると押される距離が 25% の左右入力の分だけ縮み、端を越えないため）
func _edge_wait_keys(p: int) -> Dictionary:
	var want: Dictionary = {}
	var keys: Array = MOVE_KEYS[p]
	var lp = gs.local_push
	if bool(lp.contact):
		var pushed := _shove_queue.has(1) or float(lp.pending[0]) >= 0.0 or float(lp.time) - float(lp.shove_start[1]) < 0.2
		if not pushed:
			want[_inward_key(p)] = true
		return want
	var dx := EDGE_X - _x(p)
	if absf(dx) > 0.04:
		want[keys[0] if dx > 0.0 else keys[1]] = true
	return want


## 3 問目の P1：P2 の内側まで横に走り、触れたら踏ん張って、EDGE_SHOVE_AFTER 秒後に一押しで海へ落とす（落ちなければ 0.5 秒ごとに押し直す）。
## 落としたら TAUNT_DELAY 秒後から勝ち誇って踊り、サメが噛んだら（壁が近すぎるときはその前に）跳んで踊りを止め、正解のドアへ
func _edge_push_keys(p: int, index: int) -> Dictionary:
	var want: Dictionary = {}
	var keys: Array = MOVE_KEYS[p]
	var lp = gs.local_push
	var q := index + 1
	var dist := gs.wall_z - 0.4 - _z(p)
	if _edge_fall_t < 0.0 and gs.p2_fall_committed:
		_edge_fall_t = _game_time
	if _edge_fall_t >= 0.0:
		if _game_time - _edge_fall_t >= TAUNT_DELAY:
			_act("taunt_q%d" % q, EMOTE_KEYS[1][1], 1)              # シリーダンス
		if _bite.has(2) or dist < 7.5:
			_act("taunt_stop_q%d" % q, JUMP_KEYS[1])                 # 跳んで踊りを止める（このあと _play_keys のふつうの動きで正解のドアへ）
		return want
	if not bool(lp.contact):
		if _edge_contact_t < 0.0:
			want[keys[1] if gs.player2_x < gs.player_x else keys[0]] = true   # P2 へ向かって横に走る
		return want
	if _edge_contact_t < 0.0:
		_edge_contact_t = _game_time
		_event("edge_contact", {"q": q, "x": [snappedf(gs.player_x, 0.01), snappedf(gs.player2_x, 0.01)]})
	want[_inward_key(p)] = true
	var since_contact := _game_time - _edge_contact_t
	var next_at := EDGE_SHOVE_AFTER if _edge_shoves == 0 else _edge_last_shove_t - _edge_contact_t + 0.5
	if since_contact >= next_at and _edge_shoves < 3 and _can_shove(1) and not _shove_queue.has(1):
		_shove_queue.append(1)
		_edge_shoves += 1
		_edge_last_shove_t = _game_time
	return want


## ゲームの押し合いの出来事（GameWorld の local_push_event）：contact・hit・clash を記録する
func _on_push_event(event: Dictionary) -> void:
	if not _running:
		return
	var kind := str(event.get("kind", ""))
	var entry := {"kind": kind, "player": int(event.get("player", 0)), "q": gs.current_index + 1, "frame": _signal_frame()}
	_push_log.append(entry)
	_event("push_" + kind, {"player": entry["player"], "q": entry["q"]})
	if kind == "hit" and entry["player"] == 1 and entry["q"] == WRONG_Q and _part_hit_t < 0.0:
		_part_hit_t = _game_time


## 台本のドアの書き方（"correct" / "wrong" / 番号）→ ドアの番号
func _plan_door(which: Variant, index: int) -> int:
	if which is String:
		if which == "wrong":
			return (_answers[index] + 1) % gs.num_choices
		return _answers[index]
	return clampi(int(which), 0, gs.num_choices - 1)


## 幽霊（P2）のキー：P1 が立ち止まったら、← / → で照準の輪を P1 の足もとへ滑らせ、右 Ctrl を GHOST_CHARGE_HOLD 秒押して PERFECT で放す
func _ghost_keys() -> Dictionary:
	var want: Dictionary = {}
	if not ghost_hit or _p1_ready_t < 0.0 or _ghost_resolved or ride == null:
		return want
	var phase := int(ride.get("phase"))
	if phase != GhostSharkRideController.Phase.AIMING:
		return want
	var now := _game_time
	if _aim_end_t < 0.0:
		if now - _p1_ready_t < GHOST_AIM_DELAY:
			return want
		var origin: Vector3 = ride.get("_aim_origin")
		var offset: Vector2 = ride.get("_aim_offset")
		var need := gs.player_x - (origin.x + offset.x)
		_aim_key = KEY_LEFT if need > 0.0 else KEY_RIGHT              # ← = +x、→ = −x（2 人のときの P2 の左右）
		_aim_end_t = now + absf(need) / GHOST_AIM_SPEED
		_event("ghost_aim", {"need_x": snappedf(need, 0.01), "hold": snappedf(absf(need) / GHOST_AIM_SPEED, 0.001)})
	if now < _aim_end_t:
		want[_aim_key] = true
		return want
	var charge_from := _aim_end_t + GHOST_CHARGE_GAP
	if now >= charge_from and now < charge_from + GHOST_CHARGE_HOLD:
		if _charge_start_t < 0.0:
			_charge_start_t = now
			_event("ghost_charge")
		want[KEY_CTRL] = true                                   # 右 Ctrl（pv_take_base.gd の send_key が右として送る）
	return want


func _x(p: int) -> float:
	return gs.player_x if p == 1 else gs.player2_x


func _z(p: int) -> float:
	return gs.player_z if p == 1 else gs.player2_z


## まだ答えられる（生きていて、落ちていない・サメ待ちでない）
func _active(p: int) -> bool:
	if p == 1:
		return gs.p1_alive and not gs.p1_fall_committed and not gs.p1_waiting_for_shark
	return players == 2 and gs.p2_alive and not gs.p2_fall_committed and not gs.p2_waiting_for_shark


## いまの壁でもう判定された（2 人のときの不正解は、相手が答えるまで壁が残る）
func _evaluated(p: int) -> bool:
	return int(gs.get("_hp_evaluated_wall")) == gs.current_wall_index and (int(gs.get("_hp_evaluated_mask")) & (1 << (p - 1))) != 0


func _door_x(door: int) -> float:
	if gs.num_choices == 4:
		return gs.tuning.door4_xs[door]
	return gs.tuning.left_door_x if door == 0 else gs.tuning.right_door_x


# ------------------------------------------------------------------ 出来事の記録

## この更新が終わった PV フレーム。ゲームの信号は GameWorld の更新の中（こちらの _process より前）で出るので、_step + 1 のフレーム
func _signal_frame() -> int:
	return frame_of(_step + 1)


func _event(name: String, extra: Dictionary = {}, frame := -1) -> void:
	var f := frame if frame >= 0 else _signal_frame()
	var entry := {"name": name, "frame": f, "t": snappedf((f - 1) / FPS, 0.001)}
	entry.merge(extra)
	_events.append(entry)


func _hearts() -> Array:
	return [gs.get_player_hp(1), gs.get_player_hp(2)] if players == 2 else [gs.get_player_hp(1)]


func _on_question_completed(wall_index: int, correct: bool) -> void:
	var f := _signal_frame()
	var correct_mask := int(gs.get("_hp_correct_mask"))
	var evaluated_mask := int(gs.get("_hp_evaluated_mask"))
	for q: Dictionary in _questions:
		if int(q["n"]) == wall_index + 1:
			q["hit_frame"] = f
			q["correct"] = correct
			q["correct_mask"] = correct_mask
			q["evaluated_mask"] = evaluated_mask
			q["p1_door"] = int(gs.get("_hp_chosen_door"))
			q["hp_after"] = _hearts()
	var boss := wall_index == QUIZZES.size() - 1
	var name := ("boss_break" if boss else "q%d_break" % (wall_index + 1)) if correct else "q%d_bonk" % (wall_index + 1)
	if boss and correct and _boss_frame < 0:
		_boss_frame = f
		_boss_t = _game_time
	_event(name, {"q": wall_index + 1, "correct": correct, "correct_mask": correct_mask, "hp": _hearts()})


func _on_health_changed(player_index: int, previous_hp: int, hp: int) -> void:
	if not _running:
		return
	_hp_log.append({"frame": _signal_frame(), "player": player_index, "from": previous_hp, "to": hp})
	_event("hp_%d_to_%d" % [previous_hp, hp], {"player": player_index})
	if hp < previous_hp and hp > 0:
		# 不正解のドアにゴツン（10 問のモードでハートが 1 つ減るのはこれだけ。0 になるのはサメ・刃・最後のハートの激突）
		_event("wall_bonk", {"player": player_index, "q": gs.current_index + 1, "hp": hp})


func _on_entered_ocean(player_index: int, _pos: Vector3) -> void:
	if not _ocean.has(player_index):
		_ocean[player_index] = _signal_frame()
		_event("ocean_splash", {"player": player_index, "q": gs.current_index + 1})


# ------------------------------------------------------------------ 毎回の更新のあと

func _update(n: int, _t: float, _dt: float) -> void:
	_hold_random_jitter()
	_fix_emote_start()
	_track_moves(n)
	_hide_wipe_after_mount(n)
	var state := gs.game_state
	if state != _last_state:
		_event("state_" + state.to_lower(), {}, n)
		if state == Constants.STATE_PLAYING and _last_state == Constants.STATE_COUNTDOWN:
			_event("barrier_explode", {}, n)
			_playing_t = _game_time
		_last_state = state
	var dropping := bool(world.get("_barrier_dropping"))
	if dropping and not _barrier_seen:
		_barrier_seen = true
		_event("barrier_drop", {}, n)
	elif _barrier_seen and not dropping and _barrier_landed_time < 0.0:
		_barrier_landed_time = _game_time
		_event("barrier_land", {}, n)
	if state == Constants.STATE_COUNTDOWN:
		var remain := int(ceil(gs.countdown_timer))
		if remain > 0 and remain != _countdown_shown:
			_countdown_shown = remain
			_event("countdown_%d" % remain, {}, n)
	if state == Constants.STATE_PLAYING and gs.current_index != _q_index and gs.current_index < QUIZZES.size():
		_q_index = gs.current_index
		_q_shown_time = _game_time
		_questions.append({"n": _q_index + 1, "q": gs.current_quiz.q if gs.current_quiz != null else "",
			"choices": Array(gs.current_quiz.c) if gs.current_quiz != null else [], "answer": gs.current_quiz.a if gs.current_quiz != null else -1,
			"num_choices": gs.num_choices, "wall_speed": snappedf(float(gs.get("_active_wall_speed")), 0.001),
			"estimated_seconds": gs.current_quiz.estimated_seconds if gs.current_quiz != null else 0.0, "shown_frame": n})
		_event("boss_shown" if _q_index == QUIZZES.size() - 1 else "q%d_shown" % (_q_index + 1), {"q": _q_index + 1}, n)
	# 体当たりをする問題：照準ができるようになってから最初に出る、正解が右（−x）のドアの問題（human では 9 問目から）。
	# 問題が出てから 1 秒の間に照準ができるようになれば、その問題にする
	if ghost_hit and players == 2 and _hit_q < 0 and state == Constants.STATE_PLAYING and _q_index >= 0 \
			and _q_index + 1 >= _ghost_hit_min_q() and not gs.p2_alive and _game_time - _q_shown_time < 1.0 \
			and ride != null and int(ride.get("phase")) == GhostSharkRideController.Phase.AIMING \
			and gs.num_choices == 2 and _door_x(_answers[_q_index]) < 0.0:
		_hit_q = _q_index + 1
		_event("ghost_hit_question", {"q": _hit_q}, n)
	_track_ghost(n)
	for p in range(1, players + 1):
		if not _fell.has(p) and (gs.p1_fall_committed if p == 1 else gs.p2_fall_committed):
			_fell[p] = n
			_event("fall_off", {"player": p, "q": gs.current_index + 1, "x": snappedf(_x(p), 0.01)}, n)
		if not _bite.has(p) and (gs.p1_shark_killed if p == 1 else gs.p2_shark_killed):
			_bite[p] = n
			_event("shark_bite", {"player": p, "q": gs.current_index + 1}, n)
		if not _ghost.has(p) and players == 2 and bool(world.call("is_ghost_shark_control_active", p)):
			_ghost[p] = n
			_event("ghost_ready", {"player": p, "q": gs.current_index + 1}, n)
	# 終わり：ボス壁の突破（1 人の落下ではサメに噛まれたとき、全員が脱落したときも）のあと、HOLD_AFTER_FRAMES だけ撮る
	var all_out := state == Constants.STATE_GAME_OVER
	if _end_frame < 0 and (_boss_frame > 0 or (players == 1 and _bite.has(1)) or all_out):
		_end_frame = n + HOLD_AFTER_FRAMES
		if not _explicit_frames:
			frame_count = _end_frame
	if (_step % sub) == 0 and (n % 4 == 1 or n == _end_frame):
		var entry := {"f": n, "state": state, "q": gs.current_index + 1, "hp": _hearts(),
			"ws": snappedf(float(gs.get("_active_wall_speed")), 0.001),
			"keys": _held.keys().map(func(k: Variant) -> String: return OS.get_keycode_string(int(k)))}
		for p in range(1, players + 1):
			var y := gs.player_y if p == 1 else gs.player2_y
			entry["p%d" % p] = [snappedf(_x(p), 0.01), snappedf(y, 0.01), snappedf(_z(p) - gs.world_scroll_z, 0.01),
				snappedf(gs.wall_z - 0.4 - _z(p), 0.01)]
		if players == 2:
			entry["saw_lz"] = snappedf(gs.saw.local_z, 0.01)
			entry["em"] = [gs.p1_emote, gs.p2_emote]
		_trace.append(entry)


## 踊りの最初のフレームは骨格がまだ初期姿勢（T ポーズ）なので、0 秒の位置を当てて写し直す（pv_v3_runtime.gd・pv_s16_runtime.gd と同じ）
func _fix_emote_start() -> void:
	for i in range(1, players + 1):
		var emote: int = gs.p1_emote if i == 1 else gs.p2_emote
		if emote > 0 and _last_emote[i - 1] != emote:
			var rig: AnimationRig = player.get("_p1_rig") if i == 1 else player.get("_p2_rig")
			var idx := rig.loaded_emotes.find(EmoteData.normalize_emote_id(emote)) if rig != null else -1
			if idx >= 0 and idx < AnimationRig.EMOTE_RIG_SLOTS.size():
				var slot: int = AnimationRig.EMOTE_RIG_SLOTS[idx]
				var ap := rig.aps[slot] as AnimationPlayer
				if ap != null:
					if not ap.is_playing():
						ap.play(rig.anim_names[slot])
					ap.seek(0.0, true)
					player.call("_apply_skeleton_pose", player.p1_parts if i == 1 else player.p2_parts,
						rig.skeletons[slot], rig.bone_indices_list[slot], true)


## 踊りの始まり・終わりとジャンプを記録する（report の emotes、events の emote_start / emote_stop / jump）
func _track_moves(n: int) -> void:
	for i in range(1, players + 1):
		var emote: int = gs.p1_emote if i == 1 else gs.p2_emote
		if emote != _last_emote[i - 1]:
			if emote > 0:
				_event("emote_start", {"player": i, "emote": emote, "emote_name": EmoteData.get_emote_name(emote)}, n)
			else:
				_event("emote_stop", {"player": i}, n)
			_emote_log.append([n, i, emote])
			_last_emote[i - 1] = emote
		var jumps: int = gs.p1_jump_count if i == 1 else gs.p2_jump_count
		if jumps != _jump_counts[i - 1]:
			_jump_counts[i - 1] = jumps
			_event("jump", {"player": i, "q": gs.current_index + 1}, n)


## v1.8（10/22、ユーザーの指示）：右下の小窓（GameWorld/DeathWipeLayer。脱落した人の視点の「ワイプ」）は、幽霊がサメに乗ったところ
## （MOUNTING）から先は出さない。ビームを出して上昇するところは本画面で見せる（小窓が右下の本画面を隠さないように）。
## CanvasLayer ごと隠す（ゲームは中の Control の表示を切り替えるだけなので、層を隠せば出てこない）。wipe_keep で前の版のまま
func _hide_wipe_after_mount(n: int) -> void:
	if not human or not hide_wipe or players < 2 or ride == null:
		return
	if not _wipe_hidden and int(ride.get("phase")) >= GhostSharkRideController.Phase.MOUNTING:
		_wipe_hidden = true
		_event("wipe_hidden", {}, n)
	if _wipe_hidden:
		var layer := world.get_node_or_null("DeathWipeLayer") as CanvasLayer
		if layer != null and layer.visible:
			layer.visible = false


## 幽霊のサメの段階（放す・突進・命中）と、命中のあとの P1 の動きを記録する
func _track_ghost(n: int) -> void:
	if ride == null or players < 2:
		return
	var rp := int(ride.get("phase"))
	if rp != _last_ride_phase:
		# 幽霊の段階が替わったところ（魂が浮かぶ・飛ぶ・乗る・ビーム・登場・照準…）。編集でビームの頭を探すのに使う
		var phase_name := str(GhostSharkRideController.Phase.keys()[rp]).to_lower() if rp >= 0 and rp < GhostSharkRideController.Phase.size() else str(rp)
		var info := {}
		if rp == GhostSharkRideController.Phase.BEAM_REVEAL:
			# ビームの柱の場所（待ち合わせの場所）と、遊んでいるときのカメラでの画面の横の位置（0〜1）
			var rv: Vector3 = ride.get("_rendezvous_position")
			info["rendezvous"] = [snappedf(rv.x, 0.01), snappedf(rv.y, 0.01), snappedf(rv.z - gs.world_scroll_z, 0.01)]
			if cam != null and not cam.is_position_behind(rv):
				var sp := cam.unproject_position(Vector3(rv.x, StageConstants.FLOOR_TOP_Y + 4.0, rv.z))
				info["screen_x"] = snappedf(sp.x / VIEW.x, 0.001)
		_event("ghost_phase_" + phase_name, info, n)
		if rp == GhostSharkRideController.Phase.WINDUP:
			_ghost_power = float(ride.get("_last_charge_power"))
			_ghost_perfect = bool(ride.get("_perfect_charge"))
			_event("ghost_release", {"power": snappedf(_ghost_power, 0.001), "perfect": _ghost_perfect}, n)
		elif rp == GhostSharkRideController.Phase.CHARGING:
			_event("ghost_dash", {}, n)
		elif rp == GhostSharkRideController.Phase.COOLDOWN and _last_ride_phase == GhostSharkRideController.Phase.CHARGING:
			_ghost_resolved = true                              # 当たっても外れても、突進が終わったら P1 は先へ進む
			_event("ghost_cooldown", {}, n)
		_last_ride_phase = rp
	# 乗ってからビーム・登場までのサメの場所（描画の座標）と、本画面での位置（0〜1）。10 フレームごと（ビームの場所を確かめる）
	if rp >= GhostSharkRideController.Phase.MOUNTING and rp <= GhostSharkRideController.Phase.ENTERING and (_step % sub) == 0 and n % 10 == 0:
		var shark: Node3D = ride.get("_shark")
		if shark != null and is_instance_valid(shark) and cam != null:
			var sp_pos := shark.global_position
			var row := {"f": n, "phase": rp, "pos": [snappedf(sp_pos.x, 0.01), snappedf(sp_pos.y, 0.01), snappedf(sp_pos.z, 0.01)],
				"cam": [snappedf(cam.global_position.x, 0.01), snappedf(cam.global_position.y, 0.01), snappedf(cam.global_position.z, 0.01)]}
			if not cam.is_position_behind(sp_pos):
				var sc := cam.unproject_position(sp_pos)
				row["screen"] = [snappedf(sc.x / VIEW.x, 0.001), snappedf(sc.y / VIEW.y, 0.001)]
			_shark_track.append(row)
	if _ghost_hit_frame < 0 and bool(ride.get("_hit_this_charge")):
		_ghost_hit_frame = n
		_ghost_resolved = true
		_event("ghost_hit", {"q": gs.current_index + 1, "p1_x": snappedf(gs.player_x, 0.01),
			"push": [snappedf(gs.p1_external_velocity.x, 0.01), snappedf(gs.p1_external_velocity.y, 0.01)], "p1_vy": snappedf(gs.player_vel_y, 0.01)}, n)
	if _ghost_hit_frame > 0 and n <= _ghost_hit_frame + 180 and (_step % sub) == 0:
		_p1_after_hit.append([n, snappedf(gs.player_x, 0.01), snappedf(gs.player_y, 0.01), snappedf(gs.player_local_z, 0.01),
			snappedf(gs.p1_external_velocity.length(), 0.01), gs.p1_fall_committed])


## 乱数の揺れ（カメラ：準備中・プレイ中・ゲームオーバーのカメラが randf で位置をずらす。バリア：カウントダウン中に randf で震える）は
## 更新ごとに別の位置へ飛ぶ。揺れている間だけ、PV フレームの撮る最初の更新（土台は後ろの sub/2 回を撮る）の位置を、
## そのフレームの残りの更新に書き戻す。どちらもゲームが毎回まっさらに決める位置なので、次の更新の計算は変わらない。
## サメの襲撃のカメラ（sin のなめらかな揺れで、前の位置から追う）と空撮（揺れなし）は触らない。
func _hold_random_jitter() -> void:
	if sub <= 1 or cam == null:
		return
	var s_in := ((_step - 1) % sub) + 1
	var first_shot := sub - maxi(1, sub / 2) + 1
	if s_in < first_shot:
		return
	var barrier := world.get("_start_barrier") as Node3D
	if s_in == first_shot:
		_frame_pose = cam.global_transform
		_frame_fov = cam.fov
		_hold_camera = false
		_hold_barrier = false
		if barrier != null and is_instance_valid(barrier):
			_frame_barrier = barrier.position
	var state := gs.game_state
	if not _hold_camera and state != Constants.STATE_FLYOVER and not bool(camera_controller.get("_ocean_attack_camera_active")) \
			and (gs.camera_shake > 0.0 or state == Constants.STATE_GAME_OVER):
		_hold_camera = true
		_camera_held_frames += 1
	if not _hold_barrier and state == Constants.STATE_COUNTDOWN and barrier != null and is_instance_valid(barrier):
		_hold_barrier = true
		_barrier_held_frames += 1
	if s_in == first_shot:
		return
	if _hold_camera:
		cam.global_transform = _frame_pose
		cam.fov = _frame_fov
	if _hold_barrier and barrier != null and is_instance_valid(barrier) and state == Constants.STATE_COUNTDOWN:
		barrier.position = _frame_barrier


# ------------------------------------------------------------------ 確認

func _check() -> void:
	# 編集（レーン 6 の tools/pv/pv_master.py）が読む名前でも、同じフレームを書く。shark_bite・boss_break はそのままの名前
	var aliases := {"countdown_burst": "barrier_explode", "correct_break": "q1_break", "bonk": "wall_bonk", "fall": "fall_off"}
	for alias: String in aliases:
		var frame := _find_event(str(aliases[alias]))
		if frame >= 0:
			_event(alias, {"same_as": aliases[alias]}, frame)
	report["events"] = _events
	report["camera_held_frames"] = _camera_held_frames
	report["barrier_held_frames"] = _barrier_held_frames
	report["questions"] = _questions
	report["hp_log"] = _hp_log
	report["end_frame"] = _end_frame
	report["final"] = {"state": gs.game_state, "hp": _hearts(), "alive": [gs.p1_alive, gs.p2_alive] if players == 2 else [gs.p1_alive],
		"score": [gs.score, gs.player2_score] if players == 2 else [gs.score], "current_index": gs.current_index,
		"saw_killed": [gs.p1_saw_killed, gs.p2_saw_killed] if players == 2 else []}
	report["trace"] = _trace
	if players == 2:
		var widest := 0.0
		for row: Array in _p1_after_hit:
			widest = maxf(widest, absf(float(row[1])))
		report["ghost"] = {"enabled": ghost_hit, "hit_question": _hit_q, "power": snappedf(_ghost_power, 0.001), "perfect": _ghost_perfect,
			"hit_frame": _ghost_hit_frame, "p1_widest_x_after_hit": snappedf(widest, 0.01), "p1_after_hit": _p1_after_hit,
			"shark_track": _shark_track}
		report["human"] = {"enabled": human, "acts": _acts, "emotes": _emote_log, "jumps": _jump_counts, "pushes": _push_log,
			"duel": {"contact_t": snappedf(_duel_contact_t, 0.001), "steps": _duel_step, "p2_target": snappedf(_duel_p2_target, 0.01)},
			"edge": {"contact_t": snappedf(_edge_contact_t, 0.001), "shoves": _edge_shoves, "fall_t": snappedf(_edge_fall_t, 0.001)}}
	for name: String in ["barrier_drop", "barrier_land", "enter_pressed", "state_flyover", "state_countdown", "countdown_3",
			"countdown_2", "countdown_1", "barrier_explode"]:
		if _find_event(name) < 0:
			failures.append("event %s not captured" % name)
	var by_n := {}
	for q: Dictionary in _questions:
		by_n[int(q["n"])] = q
	if players == 2:
		_check_2p(by_n)
	else:
		_check_1p(by_n)
	if _end_frame < 0:
		failures.append("the take did not reach its end (stopped at frame %d)" % frame_count)


## 2 人：どの問題も P1 が正解して終わる。P2 は 2 問目でゴツン（3 → 2）、3 問目で落ちてサメに噛まれて脱落、P1 はハート 3 のままボス壁を突破
func _check_2p(by_n: Dictionary) -> void:
	for n in range(1, QUIZZES.size() + 1):
		if not by_n.has(n) or not by_n[n].has("correct"):
			failures.append("Q%d was not answered" % n)
			continue
		var q: Dictionary = by_n[n]
		if str(q["q"]) != str(QUIZZES[n - 1][0]):
			failures.append("Q%d showed 「%s」" % [n, q["q"]])
		if not bool(q["correct"]) or (int(q["correct_mask"]) & 1) == 0:
			failures.append("Q%d was not won by P1 (correct %s, mask %d)" % [n, q["correct"], int(q["correct_mask"])])
	var bonk := _find_event_where("wall_bonk", {"player": 2})
	if bonk.is_empty() or int(bonk["q"]) != WRONG_Q or int(bonk["hp"]) != 2:
		failures.append("P2 did not bonk at Q%d (3 → 2): %s" % [WRONG_Q, str(bonk)])
	if not _find_event_where("wall_bonk", {"player": 1}).is_empty():
		failures.append("P1 bonked")
	var fall := _find_event_where("fall_off", {"player": 2})
	if fall.is_empty() or int(fall["q"]) != P2_FALL_Q or not _ocean.has(2) or not _bite.has(2):
		failures.append("P2 did not fall at Q%d and meet the shark: fall %s, ocean %s, bite %s" % [P2_FALL_Q, str(fall), _ocean, _bite])
	if gs.p2_alive:
		failures.append("P2 is still alive")
	if not by_n.has(QUIZZES.size()) or int(by_n[QUIZZES.size()]["num_choices"]) != 4:
		failures.append("Q10 was not the 4-choice boss wall")
	if _boss_frame < 0:
		failures.append("the boss wall was not broken")
	if not gs.p1_alive or gs.get_player_hp(1) != 3 or gs.p1_saw_killed:
		failures.append("P1 ended alive %s with %d hearts (saw %s), wanted alive with 3" % [gs.p1_alive, gs.get_player_hp(1), gs.p1_saw_killed])
	if gs.p2_saw_killed:
		failures.append("P2 was caught by the saw (wanted the shark)")
	if ghost_hit:
		if _hit_q < 0 or _find_event("ghost_aim") < 0:
			failures.append("the ghost never aimed at P1 (hit question %d)" % _hit_q)
		if not _ghost_perfect:
			failures.append("the ghost charge was not PERFECT (%.3f)" % _ghost_power)
		if _ghost_hit_frame < 0:
			failures.append("the ghost dash missed P1")
		var widest := 0.0
		for row: Array in _p1_after_hit:
			widest = maxf(widest, absf(float(row[1])))
			if bool(row[5]):
				failures.append("P1 was knocked off the conveyor by the ghost (frame %d)" % int(row[0]))
				break
		if widest > StageConstants.FLOOR_HALF_WIDTH - 0.8:
			failures.append("P1 was knocked to |x| = %.2f (too close to the edge)" % widest)
	if human:
		# 台本の動きが全部出たか（エモートは床の上でしか始まらないので、押せずに終わることがある）
		var wanted := ["p1_dance_wait", "p2_dance_wait", "p1_dance_switch", "p2_dance_switch", "p1_dance_stop", "p2_dance_stop",
			"taunt_q%d" % P2_FALL_Q, "taunt_stop_q%d" % P2_FALL_Q]
		if ghost_hit:
			wanted.append_array(["p1_dance_ghost", "p1_dance_ghost_stop"])
		for name: String in wanted:
			if not _acts.has(name):
				failures.append("human: %s did not happen" % name)
		var starts := [0, 0]
		for row: Array in _emote_log:
			if int(row[2]) > 0:
				starts[int(row[1]) - 1] += 1
		if starts[0] < (4 if ghost_hit else 3) or starts[1] < 2:
			failures.append("human: emotes started P1 %d / P2 %d times" % [starts[0], starts[1]])
		# 押し合い：1 問目は P1 が 3 回・P2 が 1 回以上押し当て、相殺が 1 回以上。2 問目は P1 が P2 を突き放す。
		# 3 問目は P1 の一押しで P2 が海へ落ちる（落下の確定が P1 の最後の一押しから 0.5 秒以内）
		var hits := {}
		var clashes := {}
		var last_edge_hit := -1
		for e: Dictionary in _push_log:
			var key := "q%d_p%d" % [int(e["q"]), int(e["player"])]
			if e["kind"] == "hit":
				hits[key] = int(hits.get(key, 0)) + 1
				if int(e["q"]) == P2_FALL_Q and int(e["player"]) == 1:
					last_edge_hit = int(e["frame"])
			elif e["kind"] == "clash":
				clashes[int(e["q"])] = int(clashes.get(int(e["q"]), 0)) + 1
		if int(hits.get("q%d_p1" % DUEL_Q, 0)) < 3 or int(hits.get("q%d_p2" % DUEL_Q, 0)) < 1 or int(clashes.get(DUEL_Q, 0)) < 1:
			failures.append("push: Q%d duel hits %s clashes %s" % [DUEL_Q, hits, clashes])
		if int(hits.get("q%d_p1" % WRONG_Q, 0)) < 1:
			failures.append("push: P1 did not shove P2 away at Q%d" % WRONG_Q)
		var fell_at := int(_fell.get(2, -1))
		if last_edge_hit < 0 or fell_at < 0 or fell_at - last_edge_hit > 30 or fell_at < last_edge_hit:
			failures.append("push: P2 was not shoved into the sea at Q%d (last hit %d, fall %d)" % [P2_FALL_Q, last_edge_hit, fell_at])
		# ジャンプは 3 問目に踊りを止める 1 回だけ（カウントダウン中と宙で押すジャンプのキーは跳ばない）
		if _jump_counts[0] > 1 or _jump_counts[1] > 0:
			failures.append("human: jumped P1 %d / P2 %d times (wanted 1 / 0)" % [_jump_counts[0], _jump_counts[1]])


func _check_1p(by_n: Dictionary) -> void:
	var last_q := fall_q - 1 if fall_q > 0 else QUIZZES.size()
	for n in range(1, last_q + 1):
		if not by_n.has(n) or not by_n[n].has("correct"):
			failures.append("Q%d was not answered" % n)
			continue
		var q: Dictionary = by_n[n]
		if str(q["q"]) != str(QUIZZES[n - 1][0]):
			failures.append("Q%d showed 「%s」" % [n, q["q"]])
		var want_correct := n != WRONG_Q
		if bool(q["correct"]) != want_correct:
			failures.append("Q%d answered %s, wanted %s" % [n, q["correct"], want_correct])
	if WRONG_Q <= last_q and (not by_n.has(WRONG_Q) or int(by_n[WRONG_Q].get("hp_after", [-1])[0]) != 2):
		failures.append("the wrong door at Q%d did not take one heart (3 → 2)" % WRONG_Q)
	if fall_q == 0:
		if not by_n.has(QUIZZES.size()) or int(by_n[QUIZZES.size()]["num_choices"]) != 4:
			failures.append("Q10 was not the 4-choice boss wall")
		if _boss_frame < 0:
			failures.append("the boss wall was not broken")
		if gs.game_state != Constants.STATE_CLEAR or not gs.p1_alive or gs.get_player_hp(1) != 2:
			failures.append("ended in %s (alive %s, hp %d), wanted CLEAR with 2 hearts" % [gs.game_state, gs.p1_alive, gs.get_player_hp(1)])
	else:
		if not _fell.has(1) or not _ocean.has(1) or not _bite.has(1):
			failures.append("fall=%d: fall %s, ocean %s, bite %s" % [fall_q, _fell, _ocean, _bite])
		if gs.p1_alive:
			failures.append("fall=%d: P1 is still alive after the shark" % fall_q)


func _find_event(name: String) -> int:
	for e: Dictionary in _events:
		if str(e["name"]) == name:
			return int(e["frame"])
	return -1


func _find_event_where(name: String, fields: Dictionary) -> Dictionary:
	for e: Dictionary in _events:
		if str(e["name"]) != name:
			continue
		var ok := true
		for key: Variant in fields:
			if e.get(key) != fields[key]:
				ok = false
		if ok:
			return e
	return {}


func _cleanup() -> void:
	QuizManager.provider.llm_mode = _saved_provider_mode
