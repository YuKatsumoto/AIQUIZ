class_name PracticeDirector
extends Node

## 練習の監督（docs/new_tutorial/foundation_design.md 7.2、phase4_design.md 4.2）。練習のモードのゲーム画面に1つ置かれ
## （game_world.gd が作って setup を呼ぶ）、PracticeSession.course_id のコースの台本を1レッスンずつ進める。本編の入口
## （game_state.start_practice_round・set_practice_rules など）を呼び、game_state の出来事をいまのレッスンへ渡す。
## オーバーレイ（PracticeOverlay）と案内役のハテナ（HatenaGuide）、看板の壁（PracticeSignWall）と床の印（PracticeFloorMarks）もここで作る。
##
## 本編側（担当 A）と舞台の小物（担当 C）の段階4の道具は、約束の名前で呼ぶ。小物はスクリプトを load できたときだけ作り、
## 本編側の関数・signal はあるときだけ使う（ないときは何もしないか、今ある仕組みで代わりにする）。
##
## レッスン（PracticeStep.on_event）へ渡す出来事と data：
##   &"wall_contact" {player, door, correct}   壁に着いた（door < 0 は壁、-2 はドアの境目）
##   &"correct" {} / &"wrong" {message}        本編の正解・不正解
##   &"health_changed" {player, previous, hp}
##   &"entered_ocean" {player} / &"ocean_bitten" {player} / &"caught_by_saw" {player}
##   &"fence_touched" {player} / &"quizzes_finished" {} / &"question_completed" {wall_index, correct}
##   &"wall_landed" {wall_index}               壁が空から落ちて着地した（drop_wall のあと）
##   &"round_lost" {reason}                    本番どおりのルールで全員アウト（&"hp" か &"ocean"）
##   &"state_changed" {state} / &"jumped" {player} / &"emoted" {player, emote}
##   &"pause_changed" {paused}                 ポーズ画面を開いた・閉じた（ゲーム画面の practice_pause_changed、なければ tree の paused を見る）
##   &"result_action" {action}                 リザルトのカードで評価を押した・問題履歴を開いた・閉じた（&"rated"・&"history_opened"・&"history_closed"）
##   &"coach_exit" {}                          画面のコーチ（担当 D の PracticeCoach）を Esc などで抜けたい
##
## 段階5（docs/new_tutorial/phase5_design.md 6章）：ポーズ画面とリザルトのカードの上では、画面のコーチ（担当 D）を
## coach_begin で出し、coach_focus で本物の部品（ゲーム画面の practice_coach_target、担当 A）を光らせる。コーチの間の say は
## コーチの吹き出しに出す。監督はポーズ中も動く（PROCESS_MODE_ALWAYS）が、ポーズの間はコーチの吹き出しとポーズの出来事のほかは止める。
## 本物のリザルトのカードの『リトライ』『メニュー』は、本編側が retry_run・leave_to_menu を呼ぶ。
##
## 段階6（docs/new_tutorial/phase6_design.md 4章）：2人のコース③の出来事も渡す。
##   &"push" {kind, player}                      押し合い（local_push_event の "contact"・"stalemate"・"hit"・"clash"。player は一押しした人）
##   &"winner" {question, mask}                 2人の問題の勝ち（question_winner_decided。mask は 1 = P1、2 = P2、3 = 同時、0 = だれも）
##   &"ceremony_phase" {phase}                  スコアタワーの演出の段階（result_ceremony_phase_changed。QuizGameState.ResultCeremonyPhase）
##   &"saw_caught" {player}                     のこぎりに捕まった（本編側の practice_saw_caught。MatchRules.saw = REPORT_ONLY のとき）
##   &"ghost_ready" {player} / &"ghost_dash" {player} / &"ghost_hit" {attacker, victim} / &"ghost_missed" {player}
##                                             ゴーストシャーク（本編側の practice_ghost_*）
##   &"ghost_skip" {}                           ゴーストの演出を Enter で飛ばした（allow_ghost_skip の間）
##   &"ceremony_finished" {winner}              スコアタワーの判定が出た（本編側の practice_ceremony_finished。0 = 引き分け）
##   &"cpu_finished" {action}                   CPU（担当 C の PracticeCpu）の move_to・go_door などが終わった
##   &"cpu_charging" {target}                   CPU のゴーストが構えた（ためはじめた。PracticeCpu.ghost_charging）
##
## 段階7（docs/new_tutorial/phase7_design.md 1.2）：オンラインの見せ方の練習試合（④の 4-6）の出来事も渡す。
##   &"quit_confirm" {open}                     Esc の「たいせんを やめますか？」を開いた・閉じた（ゲーム画面の practice_quit_confirm_changed）
## CPU（担当 C の PracticeCpu）は setup_cpu で作って子にする。本編側の practice_p2_cpu・practice_set_cpu_input と、
## 担当 C のスクリプトは、あるときだけ使う（class_name を直接書かない）。

signal step_started(step_id: String)
signal course_finished(course_id: String, star: bool)
## 吹き出しを出した（テストが台本の言葉を順に確かめるのに使う）
signal said(text_id: String)

const MAIN_MENU_SCENE := "res://ui/main_menu.tscn"
## 舞台の小物（担当 C）のスクリプト。まだないときは、看板はオーバーレイの文字とチェックのカードで代わりにし、床の印は出さない。
const SIGN_WALL_PATH := "res://scripts/world/practice/sign_wall.gd"
const FLOOR_MARKS_PATH := "res://scripts/world/practice/practice_floor_marks.gd"
## 画面のコーチ（担当 D）。まだないときは、コーチの言葉はオーバーレイの吹き出しに出し、光らせない。
const COACH_PATH := "res://scripts/practice/ui/practice_coach.gd"
## 吹き出しを出している時間（台本①の 1.2）：0.8秒＋1文字あたり0.12秒、最短1.8秒・最長4.0秒
const SAY_BASE_SECONDS := 0.8
const SAY_SECONDS_PER_CHAR := 0.12
const SAY_MIN_SECONDS := 1.8
const SAY_MAX_SECONDS := 4.0
## まきもどしの画面効果の長さ（台本①の 1.6）
const REWIND_SECONDS := 0.6
## 同じレッスンでこの回数失敗したら、正解のドアへの矢印・壁を半分の速さ（台本①の 1.6）
const ARROW_HINT_FAILURES := 2
const SLOW_WALL_FAILURES := 3
## 正解のドアへの矢印の根もと（x、コンベア上の z）。プレイヤーが戻る所（x 0、z 0）の少し前
const ARROW_FROM := Vector2(0.0, 2.5)
## 看板の壁を置く距離（P1 から、m。台本①の 1.4）
const SIGN_DISTANCE := 14.0
## ハテナの立ち位置（台本①の 1.3）：いまの壁の前の x（+が画面の左、ドアの外側）と、壁の z から手前への距離。
## 次の壁がないときは、プレイヤーの前（左へ少しずらして、プレイヤーと重ならないように）。壁から壁へは 0.8 秒で跳ぶ
const HATENA_WALL_X := 9.5
const HATENA_WALL_FRONT := 1.2
const HATENA_PLAYER_FRONT := Vector3(2.6, 0.0, 3.0)
const HATENA_JUMP_SECONDS := 0.8
## 跳び終えたあと、動く壁へ追いつく速さ（壁の速さに足す、m/s）
const HATENA_CATCH_UP := 3.0
## 立ち位置がこれより遠くへ飛んだら（まきもどしで壁が置き直されたなど）、歩いて追わずに跳び直す（m）
const HATENA_REHOP_DISTANCE := 2.5
## 雲に乗っているときの足の高さ（雲は足の裏から 0.83m 下まであるので、床に触れないように。担当 C から）
const HATENA_CLOUD_Y := 0.9
## プレイヤーがこの近さ（x の差、ハテナまでの z）でハテナのほうへ来たら、ハテナが横へよける
const DODGE_RANGE := Vector2(1.5, 2.6)
const DODGE_HOLD_SECONDS := 0.7
## クリアのとき、ハテナが着地する所（プレイヤーからの位置、m）。クリアカードに隠れないよう、前の少し左（x は +が左）。
const CLEAR_HATENA_OFFSET := Vector3(6.2, 0.0, 6.5)
## クリアのとき、ハテナが手をふる客席のほう（x は +が画面の左）
const CLEAR_STAND_POINT := Vector3(40.0, 6.0, 8.0)
## コンベアがゆっくり止まるまでの秒数（クリア）
const CLEAR_STOP_SECONDS := 1.0
## 遊ぶキー（移動・ジャンプ・エモート）。どれかを押している間は idle_seconds を数えない。
const PLAY_KEYS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE, KEY_1, KEY_2, KEY_3]
## 2人のときに足す P2 のキー（右の Ctrl・8 9 0・テンキーの 7 8 9）
const P2_PLAY_KEYS := [KEY_CTRL, KEY_8, KEY_9, KEY_0, KEY_KP_7, KEY_KP_8, KEY_KP_9]
## CPU（担当 C）。まだないときは、CPU は何もしない（P2 は止まったまま）。
const CPU_PATH := "res://scripts/practice/practice_cpu.gd"
## のこぎり（本編）のノード名（ゲーム画面の子）。操縦席のハテナの位置と見た目に使う。
const SAW_NODE := "SawChaseController"
## コーチのスクリプトがないとき、コーチの言葉を出すオーバーレイを上げる層（ポーズ画面 100 より上。コーチの吹き出しと同じ 106）
const COACH_FALLBACK_LAYER := 106
## 練習の音（tools/audio/make_practice_sfx.py）：見えないさくの「ぽよん」、チェックの「ピコン」
const FENCE_SFX := &"practice_fence"
const PICO_SFX := &"practice_tick"

var game_state: QuizGameState = null
var world: Node3D = null
var camera_controller: Node3D = null
var player_node: Node3D = null
var stage_env: StageEnvironment = null

var course: PracticeCourse = null
var steps: Array[PracticeStep] = []
var step_index := -1
## いまのレッスン（コースが終わったら null）
var step: PracticeStep = null
## レッスンが変わる・やり直す・とばすたびに増える番号。レッスンの流れは await のあとで is_current(番号) を確かめる。
var step_serial := 0
## いまのレッスンで失敗した回数（2回で矢印のヒント、3回で壁を半分の速さ）
var step_failures := 0
var course_failures := 0
var skipped_steps := 0
## ★をもらえる（コースの最後のレッスンが決める。①は しあげをノーミスで終えたとき）
var star_earned := false
## いま game_state に入れているルール
var rules: MatchRules = null
var hatena: HatenaGuide = null
var overlay: PracticeOverlay = null
## 看板の壁（担当 C の PracticeSignWall）。出していないとき・スクリプトがないときは null。
var sign_wall: Node3D = null
## 床の印（担当 C の PracticeFloorMarks）。スクリプトがないときは null。
var floor_marks: Node3D = null
## true の間、ハテナはいまの壁の前に立って壁といっしょに動く（台本①の 1.3）。レッスンがハテナを動かす間は false。
var hatena_follow := false
## 遊ぶキー（PLAY_KEYS）を押していない秒数（1-2 の「キーを おして みて」など）。レッスンが 0 に戻してよい。
var idle_seconds := 0.0
## コースの終わり（クリアの演出から先）
var finished := false
## 画面のコーチ（担当 D の PracticeCoach。CanvasLayer）。coach_begin で作る。スクリプトがないときは null のまま。
var coach: CanvasLayer = null
## true の間、吹き出しをハテナに付けずに画面の上（コース名の下）に出す（②の 2-4 の開始の画面など、ハテナが見えない間）。
var bubble_unanchored := false
## 吹き出しの付け根のグローバルな位置を返す（Vector3）。入れている間は、ハテナの頭の代わりにここへ付ける
## （③の 3-5 の操縦席のハテナなど）。NAN を返したら・画面の外なら、しっぽのない吹き出しを上に出す。
var bubble_point: Callable
## CPU（担当 C の PracticeCpu）。CPU と練習していないとき・スクリプトがないときは null。
var cpu: Node = null
## true の間、Enter でゴーストシャークの演出を飛ばせる（③の 3-6・3-7 の2回目から。本編側の practice_skip_ghost_intro）。
var allow_ghost_skip := false
## ゴーストシャークの演出を始めた回数（③。2回目から Enter で飛ばせる）
var ghost_intros := 0

var _say: SayTicket = null
var _leaving := false
var _jump_counts := [0, 0]
var _emotes := [0, 0]
## path → Script（読めなかったら null）
var _prop_scripts := {}
## 看板の壁の代わり（オーバーレイ）を使っている
var _sign_fallback := false
var _hatena_key := ""
var _hatena_player_spot := Vector3.ZERO
var _hatena_hold := 0.0
var _dodged := false
## いま床に出している矢印の x（出していなければ NAN）
var _arrow_x := NAN
## 本編側に壁の落下がないときの、着地の代わりの合図（番号が変わったら古い合図は捨てる）
var _landing_serial := 0
## コーチを出している（coach_begin から coach_end まで）。この間の say はコーチの吹き出しに出し、ポーズ中も時間が進む。
var _coach_on := false
## 最後に知らせたポーズの状態（&"pause_changed" を1回ずつ出す）
var _paused_seen := false


## 1つの吹き出し。出し終わる（時間・Enter・次の吹き出し）と done が来る。
class SayTicket extends RefCounted:
	signal done
	var text_id := ""
	var remaining := 0.0


func setup(state: QuizGameState, game_world: Node3D, camera: Node3D, players: Node3D, stage: StageEnvironment) -> void:
	game_state = state
	world = game_world
	camera_controller = camera
	player_node = players
	stage_env = stage
	name = "PracticeDirector"
	# ポーズ画面の上のコーチ（台本②の 2-3）を進めるため、監督はポーズ中も動く。ただし _process は、ポーズの間は
	# コーチの吹き出しとポーズの出来事のほかは何もしない（レッスンの時間・ハテナ・待ち時間 wait はポーズで止まる）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = PracticeOverlay.new()
	overlay.name = "PracticeOverlay"
	overlay.anchor_provider = _bubble_anchor
	overlay.clear_button_pressed.connect(_on_clear_button_pressed)
	# スマホ：吹き出しのタップは Enter・スペースの早送り、「スキップ ▶」は Enter のゴースト演出飛ばし。
	overlay.bubble_tapped.connect(_on_touch_bubble_tapped)
	overlay.touch_skip_pressed.connect(_on_touch_ghost_skip)
	add_child(overlay)
	hatena = HatenaGuide.new()
	hatena.name = "HatenaGuide"
	world.add_child(hatena)
	hatena.setup(GameManager.graphics_quality)
	hatena.visible = false
	floor_marks = _make_prop(FLOOR_MARKS_PATH)
	if floor_marks != null:
		floor_marks.name = "PracticeFloorMarks"
		world.add_child(floor_marks)
	_connect_state(true)
	_connect_world(true)
	# 練習の試合は、ゲーム画面の準備（_ready）が済んでから始める。
	call_deferred("_begin")


func _begin() -> void:
	if game_state == null or _leaving:
		return
	var id := PracticeSession.course_id if not PracticeSession.course_id.is_empty() else "c1"
	var entry := PracticeCatalog.find(id)
	var path := str(entry.get("course_script", ""))
	var script: Script = load(path) as Script if not path.is_empty() and ResourceLoader.exists(path) else null
	course = script.new() as PracticeCourse if script != null else null
	if course == null:
		push_error("PracticeDirector: course %s has no script" % id)
		quit_course()
		return
	steps = course.build_steps()
	overlay.set_course(course.title(), _lesson_ids().size())
	# 最初は止めたまま（コンベアも操作も）。最初のレッスンがすぐに自分のルールへ入れかえる。
	var opening := MatchRules.new()
	opening.world_speed = 0.0
	opening.input_locked = true
	var no_quizzes: Array[QuizItem] = []
	restart_round(no_quizzes, opening)
	if steps.is_empty():
		finish_course(false)
		return
	_enter_step(0)


func _exit_tree() -> void:
	if game_state != null:
		_connect_state(false)
		# game_state はシーンをまたいで残るので、P2 を CPU にしたままにしない
		_set_p2_cpu(false)
	if world != null:
		_connect_world(false)


# ---------- レッスンの進め方 ----------

func _enter_step(index: int) -> void:
	step_index = index
	step = steps[index]
	step_failures = 0
	step_serial += 1
	idle_seconds = 0.0
	overlay.set_progress(_lesson_ids().find(step.id))
	step_started.emit(step.id)
	step.enter(self)


func _leave_step() -> void:
	step_serial += 1
	if step != null:
		step.exit(self)
	_finish_say()
	coach_end()
	overlay.clear_lesson()
	clear_marks()


## await のあとで、まだ同じレッスンの同じ回か（serial は待つ前の step_serial）。
func is_current(serial: int) -> bool:
	return serial == step_serial and not finished and not _leaving


## 次のレッスンへ。最後のレッスンなら、コースの終わり（finish_course）。
func complete_step() -> void:
	if finished or _leaving or step == null:
		return
	_leave_step()
	if step_index + 1 < steps.size():
		_enter_step(step_index + 1)
	else:
		finish_course(star_earned)


## まきもどし（台本①の 1.6）：失敗を数え、line_id（例「もういちど！」）を言ってから、
## 画面効果のあとにレッスンの始めへ戻す（PracticeStep.rewind）。2回目からは正解のドアへの矢印と「やじるしの ほうへ！」。
func fail_step(line_id := "") -> void:
	if finished or _leaving or step == null:
		return
	step_failures += 1
	course_failures += 1
	step_serial += 1
	var serial := step_serial
	if not line_id.is_empty():
		await say(line_id)
		if not is_current(serial):
			return
	overlay.play_rewind(REWIND_SECONDS)
	await wait(REWIND_SECONDS)
	if not is_current(serial):
		return
	step_serial += 1
	idle_seconds = 0.0
	_finish_say()
	step.rewind(self)
	_update_arrow_hint()
	if arrow_hint_active() and is_finite(_arrow_x):
		var arrow_line := course.text_id("any.arrow")
		if not arrow_line.is_empty():
			say(arrow_line)


## まきもどしをしない失敗（1-5 の「想定外のこと」など）を数える。矢印と遅い壁は fail_step と同じに出る。
func count_failure() -> void:
	step_failures += 1
	course_failures += 1
	_update_arrow_hint()


## 失敗が2回以上（正解のドアへの矢印を出す）
func arrow_hint_active() -> bool:
	return step_failures >= ARROW_HINT_FAILURES


## 失敗が3回以上（練習の壁を半分の速さに、しあげは自動の速さを一番遅く）
func slow_hint_active() -> bool:
	return step_failures >= SLOW_WALL_FAILURES


## 練習の壁の速さ（base m/s）。3回失敗したら半分。
func practice_speed(base: float) -> float:
	return base * 0.5 if slow_hint_active() else base


## ポーズ画面の「このレッスンをスキップ」。スキップしても、最後まで行けばスタンプはもらえる（台本①の 1.8）。
func skip_step() -> void:
	if finished or _leaving or step == null:
		return
	skipped_steps += 1
	complete_step()


## ポーズ画面の「タイトルに戻る」：コースをやめてメニューへ（スタンプはなし）。
func quit_course() -> void:
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {}
	_go_to_menu()


## リザルトのカードの『リトライ』（docs/new_tutorial/phase5_design.md 3.3。本編側の gameplay_hud が練習のときに呼ぶ）。
## どうするかは、いまのレッスンが決める（PracticeStep.on_retry。②の 2-4 はミニ本番の開始の画面から）。
func retry_run() -> void:
	if finished or _leaving or step == null:
		return
	step.on_retry(self)


## リザルトのカードの『メニュー』（本編側が練習のときに呼ぶ）。いまのレッスンが受けなければ、コースをやめてメニューへ。
func leave_to_menu() -> void:
	if finished or _leaving:
		return
	if step != null and step.on_leave_to_menu(self):
		return
	quit_course()


## メニューの上のレッスンへ続ける（②の 2-5 → 2-6）。PracticeSession.resume_in_menu にコースの続き
## （★・とばした数・初回の案内から始めたか）を入れて、メニューへ戻る（メニューが続きを始める。担当 D）。
## scene はメニューの画面（④はオンラインの画面。練習の形で開いて続きを始める）。
## 戻れない（画面の切り替えの最中）ときは false。
func continue_in_menu(next_step: String, scene := MAIN_MENU_SCENE) -> bool:
	if finished or _leaving or course == null:
		return false
	PracticeSession.return_to_select = false
	PracticeSession.resume_in_menu = {"course": course.id, "step": next_step, "star": star_earned,
		"skipped": skipped_steps, "first_run": PracticeSession.from_first_run}
	if _go_to_menu(scene):
		return true
	PracticeSession.resume_in_menu = {}
	return false


## いまのレッスンをやめて、step_id のレッスンから始め直す（②の 2-5 の『リトライ』でミニ本番へ戻るなど）。
func restart_from(step_id: String) -> void:
	if finished or _leaving:
		return
	for i in range(steps.size()):
		if steps[i].id == step_id:
			_leave_step()
			_enter_step(i)
			return


## コースの終わり：クリアの演出 → クリアカードとスタンプ（保存する）→ ボタン（どちらもコース選択へ戻る）。
func finish_course(star: bool) -> void:
	if finished or _leaving:
		return
	_leave_step()
	finished = true
	step = null
	var lock := rules.duplicate_rules() if rules != null else MatchRules.new()
	lock.input_locked = true
	set_rules(lock)
	overlay.set_progress(_lesson_ids().size())
	if course != null:
		GameManager.mark_practice_stamp(course.id, star)
		course_finished.emit(course.id, star)
	if course != null and course.handles_clear():
		course.play_clear(self, star)
	else:
		_play_clear(star)


## クリア（台本①のクリア）：0.0 コンベアがゆっくり止まり、ハテナがプレイヤーの前へ。0.5 花火と歓声・「やったー！ クリア！」。
## 2.0 ノーミスなら「ノーミス！ すごい！」。3.0 客席に手をふる → ウェーブ。5.0 クリアカードとスタンプ。7.0 最後のひとこと。
func _play_clear(star: bool) -> void:
	hatena_follow = false
	_stop_conveyor_slowly(CLEAR_STOP_SECONDS)
	close_sign()
	var front := player_point(1) + CLEAR_HATENA_OFFSET
	front.y = 0.0
	if not hatena.visible:
		hatena.place_at(front + Vector3(0.0, 8.0, 2.0))
	hatena.set_cloud(false)
	await hatena.hop_to(front, 0.5)
	if _leaving:
		return
	hatena.face_toward(player_point(1))
	hatena.play(&"cheer")
	world_call(&"practice_celebrate")
	var first := course.text_id("clear.1")
	if not first.is_empty():
		say(first)
	await wait(1.5)
	if _leaving:
		return
	var nomiss := course.text_id("clear.nomiss")
	if star and not nomiss.is_empty():
		say(nomiss)
	await wait(1.0)
	if _leaving:
		return
	hatena.face_toward(CLEAR_STAND_POINT)
	hatena.play(&"wave")
	world_call(&"practice_crowd_wave")
	await wait(2.0)
	if _leaving:
		return
	hatena.face_toward(player_point(1))
	var card_id := course.text_id("clear.card")
	var lines := PracticeTexts.get_parts(card_id) if not card_id.is_empty() else PackedStringArray([course.title()])
	var buttons_id := course.text_id("clear.buttons")
	var buttons := PracticeTexts.get_parts(buttons_id) if not buttons_id.is_empty() else PackedStringArray()
	# 初回の案内から始めたときは［つぎの コースへ］を、そうでなければ［メニューに もどる］を選んでおく（台本①のクリア）
	var focus := 0 if PracticeSession.from_first_run else buttons.size() - 1
	var number := str(PracticeCatalog.find(course.id).get("number", ""))
	overlay.show_clear_card(lines, number, star, buttons, focus)
	await wait(2.0)
	if _leaving:
		return
	var last := course.text_id("clear.2")
	if not last.is_empty():
		say(last)


## いまのコンベアの速さから、seconds かけて 0 にする（ルールの world_speed を下げていく）。
func _stop_conveyor_slowly(seconds: float) -> void:
	var lock := rules
	var from := current_world_speed()
	lock.world_speed = from
	# 監督はポーズ中も動くので、tween はポーズで止める
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_method(func(value: float) -> void:
		if rules == lock:
			lock.world_speed = value, from, 0.0, maxf(seconds, 0.01))


func _on_clear_button_pressed(index: int) -> void:
	# 1つ目のボタン（［つぎの コースへ］）は、メニューに戻ってすぐ次のコースを始める（PracticeSession.launch_next。
	# メニューが始める。担当 D）。ほかのボタンと、次のコースがないときはコース選択へ戻る。
	var next := course.next_course if course != null and index == 0 and overlay.clear_buttons().size() > 1 else ""
	if not next.is_empty() and PracticeCatalog.is_available(next):
		PracticeSession.launch_next = next
		PracticeSession.return_to_select = false
	else:
		PracticeSession.launch_next = ""
		PracticeSession.return_to_select = true
	if not _go_to_menu():
		PracticeSession.launch_next = ""
		overlay.enable_clear_buttons()


## メニューへ戻り始めたら true（画面の切り替えの最中で戻れないときは false）。
## scene が メインメニューでない（④のオンラインの画面）ときは、本番のオンラインの戻り方と同じワイプで移る。
func _go_to_menu(scene := MAIN_MENU_SCENE) -> bool:
	if _leaving:
		return true
	if SceneTransition.is_transitioning():
		return false
	_leaving = true
	if step != null:
		step.exit(self)
		step = null
	step_serial += 1
	_finish_say()
	coach_end()
	setup_cpu(false)
	get_tree().paused = false
	AudioManager.set_music_paused(false)
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_MENU)
	game_state.reset_to_menu()
	if scene == MAIN_MENU_SCENE:
		SceneTransition.change_scene(MAIN_MENU_SCENE)
	else:
		SceneTransition.change_scene(scene, Color.BLACK, SceneTransition.WipeStyle.DATA)
	return true


func _lesson_ids() -> Array[String]:
	if course != null and not course.lesson_ids.is_empty():
		return course.lesson_ids
	var ids: Array[String] = []
	for each: PracticeStep in steps:
		ids.append(each.id)
	return ids


# ---------- レッスンが使う道具 ----------

## 吹き出しを出す。出し終わると返り値の signal が来る（await d.say("c1.welcome.1")）。
## 次の say で前の吹き出しは打ち切られ、それを待っていた流れは次のフレームで続く。
## 操作をロックしている間（rules.input_locked）は、Enter かスペースで次へ送れる（台本①の 1.2）。
## コーチを出している間（coach_begin のあと）は、コーチの吹き出しに出す（時間・早送りはコーチが決める）。
## hold（「押して みて」の段階）：コーチの吹き出しを、時間が過ぎても次の say まで残す（早送りもしない）。
func say(text_id: String, hold := false) -> Signal:
	if _coach_on and coach != null and coach.has_method(&"say"):
		_finish_say()
		var shown: Variant = coach.call(&"say", PracticeTexts.get_text(text_id), -1.0, hold)
		if shown is Signal:
			said.emit(text_id)
			return shown
	if _say != null:
		var replaced := _say
		_say = null
		call_deferred("_emit_say_done", replaced)
	var text := PracticeTexts.get_text(text_id)
	var ticket := SayTicket.new()
	ticket.text_id = text_id
	ticket.remaining = say_seconds(text)
	_say = ticket
	overlay.show_bubble(text)
	AudioManager.play_sfx(&"practice_pop")  # 吹き出しの「ぽこっ」
	said.emit(text_id)
	return ticket.done


## 吹き出しを出しておく秒数。
static func say_seconds(text: String) -> float:
	return clampf(SAY_BASE_SECONDS + SAY_SECONDS_PER_CHAR * text.length(), SAY_MIN_SECONDS, SAY_MAX_SECONDS)


## いま出している吹き出しの ID（なければ ""）。
func saying() -> String:
	return _say.text_id if _say != null else ""


## seconds 秒待つ（ポーズ中は止まる）。
func wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds, false).timeout


## seconds 秒待つ（ポーズ中も進む。ポーズ画面の上のコーチで使う）。
func coach_wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds, true).timeout


## condition が true になるまで毎フレーム待つ（ポーズ中も見る）。とちゅうでレッスンが変わったら false。
func until(condition: Callable, serial: int) -> bool:
	while is_current(serial) and not bool(condition.call()):
		await get_tree().process_frame
	return is_current(serial)


## 「ピコン」（台本①の 1.9。tools/audio/make_practice_sfx.py）
func play_pico() -> void:
	AudioManager.play_sfx(PICO_SFX)


func set_rules(next: MatchRules) -> void:
	rules = next
	game_state.set_practice_rules(next)


## 練習の回を始め直す（game_state.start_practice_round）。ハート・位置・壁が始めの状態に戻る（1-7 のやり直しなど）。
## 1人のときの開始位置（z −8）は台本の位置ではないので、置き直すのはレッスンの側。
## start_state を Constants.STATE_WAITING_START にすると、本番と同じ始まり方（開始の画面 → 空撮 → カウントダウン。②の 2-4）。
func restart_round(quizzes: Array[QuizItem], next: MatchRules, boss_indices: Array[int] = [],
		start_state: String = Constants.STATE_PLAYING) -> void:
	rules = next
	var players := 1
	if course != null:
		# ④は1人で遊ぶが、試合は CPU との2人（PracticeCatalog の round_players）
		var entry := PracticeCatalog.find(course.id)
		players = int(entry.get("round_players", entry.get("players", 1)))
	game_state.start_practice_round(quizzes, players, next, boss_indices, start_state)
	_jump_counts = [game_state.p1_jump_count, game_state.p2_jump_count]
	_emotes = [game_state.p1_emote, game_state.p2_emote]
	_hatena_key = ""


## 台本の問題に差し替える（いまの壁から）。
func set_quizzes(quizzes: Array[QuizItem], boss_indices: Array[int] = []) -> void:
	game_state.set_practice_quizzes(quizzes, boss_indices)


## プレイヤーを置き直す（x、コンベア上の z）。
func place_player(player_index: int, x: float, local_z: float) -> void:
	game_state.practice_place_player(player_index, x, local_z)


## いまの壁を、P1 から distance（m）先に置き直す（落とさない。まきもどしで使う）。
func place_wall(distance: float) -> void:
	game_state.practice_place_current_wall(distance)


## いまの壁を、P1 から distance（m）先へ空から落とす（本編側の practice_drop_current_wall）。着地で &"wall_landed"。
## 本編側にまだないときは置き直すだけにして、少しあとに着地の合図を出す。
func drop_wall(distance: float) -> void:
	_landing_serial += 1
	if game_state.has_method(&"practice_drop_current_wall") and game_state.has_signal(&"practice_wall_landed"):
		game_state.call(&"practice_drop_current_wall", distance)
		return
	game_state.practice_place_current_wall(distance)
	_fake_landing(_landing_serial, game_state.current_wall_index)


func _fake_landing(serial: int, wall_index: int) -> void:
	await wait(0.55)
	if serial == _landing_serial and not _leaving:
		_emit(&"wall_landed", {"wall_index": wall_index})


func set_hp(player_index: int, hp: int) -> void:
	game_state.practice_set_hp(player_index, hp)


func revive(player_index: int) -> void:
	game_state.practice_revive(player_index)


## プレイヤーの位置（x、コンベア上の z）。
func player_pos(player_index := 1) -> Vector2:
	if player_index == 2:
		return Vector2(game_state.player2_x, game_state.player2_local_z)
	return Vector2(game_state.player_x, game_state.player_local_z)


## プレイヤーの足もとのゲーム画面の座標（x、高さ、コンベア上の z）。
func player_point(player_index := 1) -> Vector3:
	if player_index == 2:
		return Vector3(game_state.player2_x, game_state.player2_y, game_state.player2_local_z)
	return Vector3(game_state.player_x, game_state.player_y, game_state.player_local_z)


## 床に立っている（アウト・落下中・海の中でない）
func player_standing(player_index := 1) -> bool:
	if player_index == 2:
		return game_state.p2_alive and not game_state.p2_fall_committed and not game_state.p2_waiting_for_shark
	return game_state.p1_alive and not game_state.p1_fall_committed and not game_state.p1_waiting_for_shark


## いまの壁までの距離（P1 から、m）。壁がなければ INF。
func wall_distance() -> float:
	if game_state.current_quiz == null:
		return INF
	return game_state.wall_z - game_state.player_z


## いまの壁のコンベア上の z（壁がなければ NAN）。
func wall_local_z() -> float:
	if game_state.current_quiz == null:
		return NAN
	return game_state.wall_z - game_state.world_scroll_z


## ドアの真ん中の x（door はドアの番号、choices は 2 か 4）。
func door_x(door: int, choices := 2) -> float:
	var t := game_state.tuning
	if choices == 4:
		return t.door4_xs[clampi(door, 0, t.door4_xs.size() - 1)]
	return t.left_door_x if door == 0 else t.right_door_x


## いまの壁の正解のドアの x（壁がない・正解のドアがないときは NAN）。
func answer_door_x() -> float:
	var quiz := game_state.current_quiz
	if quiz == null or quiz.a < 0 or quiz.a >= quiz.c.size():
		return NAN
	return door_x(quiz.a, quiz.c.size())


## いまのコンベアの速さ（m/s）。
func current_world_speed() -> float:
	if rules != null and rules.world_speed >= 0.0:
		return rules.world_speed
	return float(game_state.get("_active_wall_speed"))


func camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


## ゲーム画面の練習の道具（担当 A：practice_celebrate など）。ないときは何もしないで null。
func world_call(method: StringName, args: Array = []) -> Variant:
	if world != null and world.has_method(method):
		return world.callv(method, args)
	return null


## ハテナの段階4の動き（担当 C：walk_to・dodge など）。ないときは何もしないで null。
func hatena_call(method: StringName, args: Array = []) -> Variant:
	if hatena != null and hatena.has_method(method):
		return hatena.callv(method, args)
	return null


## ハテナの動き（担当 C）を呼んで、終わりの signal を返す。ないときは代わりに hop_to で pos へ跳ぶ。
func hatena_move(method: StringName, args: Array, pos: Vector3, seconds: float) -> Signal:
	var result: Variant = hatena_call(method, args)
	if result is Signal:
		return result
	return hatena.hop_to(pos, seconds)


## ハテナを、いまの立ち位置（壁の前など）へ戻してついて行かせる。
func follow_walls() -> void:
	hatena_follow = true
	_hatena_key = ""


## seconds の間、ついて行くハテナの位置を動かさない（ぶるぶる・よけるなど、ハテナ自身の動きの間）。
func hold_hatena(seconds: float) -> void:
	_hatena_hold = maxf(_hatena_hold, seconds)


# ---------- 2人の道具（③。docs/new_tutorial/phase6_design.md 2章・3章） ----------

## CPU と練習するか（③の 3-0 で選んだもの）。
func with_cpu() -> bool:
	return PracticeSession.with_cpu


## P2 を CPU にする・やめる。on なら本編側の practice_p2_cpu を入れ、担当 C の PracticeCpu を作って子にする
## （スクリプトがないときは作らない。P2 は止まったまま）。off なら CPU を消して、P2 をキーボードに戻す。
func setup_cpu(on: bool) -> void:
	_set_p2_cpu(on)
	if not on:
		if cpu != null and is_instance_valid(cpu):
			cpu.queue_free()
		cpu = null
		return
	if cpu != null and is_instance_valid(cpu):
		return
	var script := tool_script(CPU_PATH)
	cpu = script.new() as Node if script != null else null
	if cpu == null:
		return
	cpu.name = "PracticeCpu"
	# CPU も、ポーズの間は止める（監督はポーズ中も動くので、子の既定を変える）
	cpu.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(cpu)
	if cpu.has_method(&"setup"):
		cpu.call(&"setup", game_state, world)
	if cpu.has_signal(&"finished"):
		cpu.connect(&"finished", _on_cpu_finished)
	if cpu.has_signal(&"ghost_charging"):
		cpu.connect(&"ghost_charging", _on_cpu_charging)


func _set_p2_cpu(on: bool) -> void:
	if game_state != null and &"practice_p2_cpu" in game_state:
		game_state.set(&"practice_p2_cpu", on)


## CPU の動き（担当 C の PracticeCpu：idle・wave・move_to・go_door・wander・push_toward_p1・ghost_attack など）。
## CPU がない・道具がないときは何もしないで null。
func cpu_call(method: StringName, args: Array = []) -> Variant:
	if cpu != null and is_instance_valid(cpu) and cpu.has_method(method):
		return cpu.callv(method, args)
	return null


## CPU のスクリプトがあって動かせる（なければ、CPU の動きを待つレッスンは時間で先へ進む）。
func has_cpu() -> bool:
	return cpu != null and is_instance_valid(cpu)


func _on_cpu_finished(action: StringName) -> void:
	_emit(&"cpu_finished", {"action": action})


func _on_cpu_charging(target_player: int) -> void:
	_emit(&"cpu_charging", {"target": target_player})


## 本編側（担当 A）の練習の道具を呼ぶ（game_state にあればそれを、なければゲーム画面のものを）。ないときは null。
func practice_call(method: StringName, args: Array = []) -> Variant:
	if game_state != null and game_state.has_method(method):
		return game_state.callv(method, args)
	return world_call(method, args)


## 本編側（担当 A）にその練習の道具がある（game_state かゲーム画面）。
func has_practice(method: StringName) -> bool:
	return (game_state != null and game_state.has_method(method)) or (world != null and world.has_method(method))


## 本編側（担当 A）にその練習の signal がある（game_state かゲーム画面）。
func has_practice_signal(signal_name: StringName) -> bool:
	return (game_state != null and game_state.has_signal(signal_name)) or (world != null and world.has_signal(signal_name))


## メニューへ戻り始めた（クリアの演出などの待ちのあとで確かめる）。
func is_leaving() -> bool:
	return _leaving


## のこぎりに捕まっても、ゴーストにもアウトにもしない（本編側の MatchRules.saw = Saw.REPORT_ONLY）。ないときは false。
static func set_saw_report_only(next: MatchRules) -> bool:
	if not (&"saw" in next):
		return false
	var enums: Variant = (next.get_script() as Script).get_script_constant_map().get("Saw", {})
	if not (enums is Dictionary) or not (enums as Dictionary).has("REPORT_ONLY"):
		return false
	next.set(&"saw", int(enums["REPORT_ONLY"]))
	return true


## のこぎり（本編のノード。操縦席のハテナ）。ないときは null。
func saw_node() -> Node3D:
	return world.get_node_or_null(SAW_NODE) as Node3D if world != null else null


## 操縦席のハテナの体の真ん中（グローバルな位置）。のこぎりがないときは NAN。
func saw_seat_point() -> Vector3:
	var saw := saw_node()
	if saw == null or not saw.has_method(&"operator_seat_point"):
		return Vector3(NAN, NAN, NAN)
	return saw.call(&"operator_seat_point")


## 操縦席のハテナを隠す・出す（案内のハテナが雲で席へ移ったように見せる。本編側の practice_set_saw_operator_hidden、
## ないときはのこぎりのノードに直接）。
func set_saw_operator_hidden(hidden: bool) -> void:
	if world != null and world.has_method(&"practice_set_saw_operator_hidden"):
		world.call(&"practice_set_saw_operator_hidden", hidden)
		return
	var saw := saw_node()
	if saw != null and saw.has_method(&"set_operator_hidden"):
		saw.call(&"set_operator_hidden", hidden)


## 正解の数を入れる（本編側の practice_set_score。ないときは game_state の数を直接入れる）。
func set_score(player_index: int, correct: int) -> void:
	if has_practice(&"practice_set_score"):
		practice_call(&"practice_set_score", [player_index, correct])
	elif player_index == 1:
		game_state.score = correct
	elif player_index == 2:
		game_state.player2_score = correct


## 正解の数（P1 は score、P2 は player2_score）。
func player_score(player_index: int) -> int:
	return game_state.score if player_index == 1 else game_state.player2_score


## player_index をアウトにして、本番の脱落の演出からゴーストシャークに乗せる（本編側の practice_make_ghost）。
## 演出は2回目から Enter で飛ばせる（allow_ghost_skip）。道具がないときは false。
func make_ghost(player_index: int, skip_intro := false) -> bool:
	if not has_practice(&"practice_make_ghost"):
		return false
	ghost_intros += 1
	allow_ghost_skip = not skip_intro and ghost_intros >= 2
	_watch_ghost_charges()
	practice_call(&"practice_make_ghost", [player_index, skip_intro])
	return true


## 本編側に practice_ghost_hit・practice_ghost_missed がないときの代わり：ゴーストの操縦（本編）の突進の終わり
## （charge_resolved）を、当たり・外れの出来事にする。
func _watch_ghost_charges() -> void:
	if has_practice_signal(&"practice_ghost_hit") or world == null:
		return
	var ride := world.get_node_or_null("GhostSharkRideController")
	if ride == null or not ride.has_signal(&"charge_resolved"):
		return
	if not ride.is_connected(&"charge_resolved", _on_charge_resolved):
		ride.connect(&"charge_resolved", _on_charge_resolved)


func _on_charge_resolved(player_index: int, hit: bool, _power: float) -> void:
	if hit:
		_on_ghost_hit(player_index, 3 - player_index)
	else:
		_on_ghost_missed(player_index)


## ゴーストシャークの演出を飛ばす（本編側の practice_skip_ghost_intro）。
func skip_ghost_intro() -> void:
	practice_call(&"practice_skip_ghost_intro")


## ゴーストシャークの見せ方（ゲーム画面の get_ghost_shark_presentation。phase は "MOUNTING"・"AIMING" など）。
func ghost_presentation(player_index: int) -> Dictionary:
	var state: Variant = world_call(&"get_ghost_shark_presentation", [player_index])
	return state if state is Dictionary else {"active": false}


## player_index のゴーストシャークのため（0〜1）と、光る帯（PERFECT）に入っているか（本編側の practice_ghost_state。
## ないときはゴーストの操縦のため）。乗っていない・道具がないときは {charge: 0, perfect: false}。
func ghost_charge(player_index: int) -> Dictionary:
	if game_state != null and game_state.has_method(&"practice_ghost_state"):
		var state: Dictionary = game_state.call(&"practice_ghost_state", player_index)
		var charging := bool(state.get("charging", false))
		return {"charge": float(state.get("charge", 0.0)) if charging else 0.0, "perfect": charging and bool(state.get("perfect", false))}
	var ride := world.get_node_or_null("GhostSharkRideController") if world != null else null
	if ride == null or not ride.has_method(&"get_charge_amount"):
		return {"charge": 0.0, "perfect": false}
	var charge := float(ride.call(&"get_charge_amount"))
	var constants: Dictionary = (ride.get_script() as Script).get_script_constant_map()
	var low := float(constants.get("PERFECT_CHARGE_MIN", 0.72))
	var high := float(constants.get("PERFECT_CHARGE_MAX", 0.94))
	return {"charge": charge, "perfect": charge >= low and charge <= high}


## スクリプト（舞台の小物・CPU・カードなど）を読む。ない・読めない・作れないときは null。
func tool_script(path: String) -> Script:
	return _prop_script(path)


# ---------- 看板の壁（担当 C の PracticeSignWall） ----------

## 看板の壁を出す（なければ P1 から distance m 先に作って空から落とす）。lines は問題パネルの文字（2行まで）、
## panels はパネル2枚（PracticeSignWall.set_panels の形）。着地で返り値の signal が来る（もう出ていればすぐ）。
## 看板の壁のスクリプトがないときは、オーバーレイの看板の文字とチェックのカードで代わりにする。
func open_sign(lines: PackedStringArray, panels: Array, distance := SIGN_DISTANCE) -> Signal:
	if sign_wall == null:
		sign_wall = _make_prop(SIGN_WALL_PATH)
		if sign_wall != null:
			sign_wall.name = "PracticeSignWall"
			world.add_child(sign_wall)
			sign_wall.call(&"setup", GameManager.graphics_quality)
			sign_wall.position = Vector3(0.0, 0.0, game_state.player_local_z + distance)
			_sign_fallback = false
			sign_wall.call(&"set_title", lines)
			sign_wall.call(&"set_panels", panels)
			_hatena_key = ""
			return sign_wall.call(&"drop_in")
	set_sign(lines, panels)
	return wait(0.01)


## 看板の壁の文字とパネルを変える（panels が空ならパネルはそのまま）。
func set_sign(lines: PackedStringArray, panels: Array = []) -> void:
	if sign_wall != null:
		sign_wall.call(&"set_title", lines)
		if not panels.is_empty():
			sign_wall.call(&"set_panels", panels)
		return
	_sign_fallback = true
	overlay.set_sign("／".join(lines))
	if panels.is_empty():
		return
	var cards: Array = []
	for panel: Dictionary in panels:
		if panel.has("glyph"):
			cards.append(panel)
	if cards.is_empty():
		overlay.hide_checks()
	else:
		overlay.show_checks(cards)


## パネルが光って ✓（ピコン）。
func tick_sign(key: StringName) -> void:
	if sign_wall != null:
		if not bool(sign_wall.call(&"is_panel_done", key)):
			sign_wall.call(&"tick_panel", key)
			play_pico()
	elif not overlay.is_check_done(key):
		overlay.tick_check(key)


func is_sign_done(key: StringName) -> bool:
	if sign_wall != null:
		return bool(sign_wall.call(&"is_panel_done", key))
	return overlay.is_check_done(key)


## 看板の壁の道具（担当 C の PracticeSignWall。tick_panel_key など）。看板の壁がない・道具がないときは何もしないで null。
func sign_call(method: StringName, args: Array = []) -> Variant:
	if sign_wall != null and sign_wall.has_method(method):
		return sign_wall.callv(method, args)
	return null


## パネルを点滅させる（「キーを おして みて」）。
func blink_sign() -> void:
	if sign_wall != null:
		sign_wall.call(&"blink_panels")
	else:
		overlay.blink_checks()


## 看板の壁を空へ戻す（戻り終わったら消す）。返り値は戻り終わりの signal。
func close_sign() -> Signal:
	if _sign_fallback:
		_sign_fallback = false
		overlay.set_sign("")
		overlay.hide_checks()
	if sign_wall == null:
		return wait(0.01)
	var leaving := sign_wall
	sign_wall = null
	_hatena_key = ""
	var result: Variant = leaving.call(&"fly_away")
	if result is Signal:
		var done: Signal = result
		# 看板のメソッドへ直接つなぐ（戻り終わる前に画面が変わって看板が消えれば、つながりも消える）
		done.connect(leaving.queue_free, CONNECT_ONE_SHOT)
		return done
	leaving.queue_free()
	return wait(0.01)


## 看板の壁のコンベア上の z（出していなければ NAN）。
func sign_local_z() -> float:
	return sign_wall.position.z if sign_wall != null else NAN


# ---------- 床の印（担当 C の PracticeFloorMarks） ----------

func marks_call(method: StringName, args: Array = []) -> void:
	if floor_marks != null:
		floor_marks.callv(method, args)


## 床の端が赤く脈打つ（&"left" / &"right" / &"back"）。
func show_edge_glow(sides: Array) -> void:
	marks_call(&"show_edge_glow", [sides])


## 黄色いギリギリ ゾーン（Rect2：x の範囲, z の範囲）。
func show_zones(zones: Array) -> void:
	marks_call(&"show_zones", [zones])


func flash_zone(index: int) -> void:
	marks_call(&"flash_zone", [index])


## 床の印を全部消す（矢印も）。
func clear_marks() -> void:
	marks_call(&"clear_all")
	_arrow_x = NAN


## 的のマーク（壁の前面に付ける）。床の印のスクリプトがないときは null。
func make_target_mark() -> Node3D:
	var script := _prop_script(FLOOR_MARKS_PATH)
	if script == null:
		return null
	return script.call(&"make_target_mark") as Node3D


## 的のマークを付ける所（壁のノードの中）。床の印のスクリプトの TARGET_MARK_POSITION（2つのドアの間の柱の前）、
## なければ fallback。
func target_mark_position(fallback: Vector3) -> Vector3:
	var script := _prop_script(FLOOR_MARKS_PATH)
	if script == null:
		return fallback
	var value: Variant = script.get_script_constant_map().get("TARGET_MARK_POSITION", fallback)
	return value if value is Vector3 else fallback


## いま床に出している矢印の x（出していなければ NAN）。
func arrow_hint_x() -> float:
	return _arrow_x


## 2回失敗したら、レッスンの指すドアへの矢印を出す（指すものが変わったら向きを変える）。
func _update_arrow_hint() -> void:
	var x := NAN
	if step != null and not finished and arrow_hint_active():
		x = step.hint_door_x(self)
	if is_nan(x) and is_nan(_arrow_x):
		return
	if is_finite(x) and is_finite(_arrow_x) and absf(x - _arrow_x) < 0.01:
		return
	_arrow_x = x
	if is_finite(x):
		marks_call(&"show_arrow", [ARROW_FROM, x])
	else:
		marks_call(&"hide_arrow")


## 舞台の小物のスクリプト（担当 C）と画面のコーチ（担当 D）。ない・読めない・作れないときは null。
func _prop_script(path: String) -> Script:
	if not _prop_scripts.has(path):
		var script := load(path) as Script if ResourceLoader.exists(path) else null
		_prop_scripts[path] = script if script != null and script.can_instantiate() else null
	return _prop_scripts[path]


func _make_prop(path: String) -> Node3D:
	var script := _prop_script(path)
	return script.new() as Node3D if script != null else null


# ---------- 画面のコーチ（担当 D の PracticeCoach）と、光らせる本物の部品（担当 A） ----------

## コーチを出す（ポーズ画面・リザルトのカードの上。docs/new_tutorial/phase5_design.md 5.1）。with_portrait なら
## ハテナの小窓（担当 C の HatenaPortrait）も出す（吹き出しはその頭の上）。コーチの間の say はコーチの吹き出しに出る。
## コーチのスクリプトがないときは false：言葉はオーバーレイの吹き出し（ポーズ画面より上へ上げる）に出し、光らせない。
func coach_begin(with_portrait := true) -> bool:
	if coach == null:
		var script := _prop_script(COACH_PATH)
		coach = script.new() as CanvasLayer if script != null else null
		if coach != null:
			coach.name = "PracticeCoach"
			add_child(coach)
			if coach.has_signal(&"exit_requested"):
				coach.connect(&"exit_requested", _on_coach_exit)
	_coach_on = true
	if coach == null:
		overlay.layer = COACH_FALLBACK_LAYER
		return false
	# 吹き出しの付け根は、小窓が出ていれば小窓のハテナの頭の上（コーチが決める）
	coach_call(&"show_portrait", [with_portrait])
	return true


## コーチを終える（光・暗い幕・吹き出し・小窓を消す）。出していなければ何もしない。
func coach_end() -> void:
	if not _coach_on:
		return
	_coach_on = false
	coach_call(&"close")
	if overlay != null:
		overlay.layer = PracticeOverlay.LAYER


## コーチを出している（coach_begin から coach_end まで。コーチのスクリプトがないときも true）。
func coach_active() -> bool:
	return _coach_on


## コーチのスクリプトがあって、出せる。
func has_coach() -> bool:
	return coach != null or _prop_script(COACH_PATH) != null


func coach_call(method: StringName, args: Array = []) -> Variant:
	if coach != null and coach.has_method(method):
		return coach.callv(method, args)
	return null


## ids の本物の部品（ゲーム画面の practice_coach_target：&"pause_resume"・&"result_retry" など）を光らせる。
## clickable なら、光っている所だけ押せる。false なら見せるだけ。見つからない部品は外し、1つもなければ光を消す。
func coach_focus(ids: Array, clickable := true) -> void:
	var targets: Array = []
	for id: Variant in ids:
		var target := coach_target(StringName(id))
		if target != null:
			targets.append(target)
	if targets.is_empty():
		coach_call(&"clear_focus")
	else:
		coach_call(&"focus", [targets, clickable])


## 光らせる本物の部品（担当 A の game_world.practice_coach_target）。ないときは null。
func coach_target(id: StringName) -> Control:
	var target: Variant = world_call(&"practice_coach_target", [id])
	return target as Control if target is Control and is_instance_valid(target) else null


## ハテナの小窓（コーチの portrait）。ないときは null。
func coach_portrait() -> Control:
	var portrait: Variant = coach_call(&"portrait")
	return portrait as Control if portrait is Control and is_instance_valid(portrait) else null


## ハテナの小窓の動き（HatenaGuide と同じ名前）。小窓がないときは何もしない。
func coach_play(action: StringName) -> void:
	var portrait := coach_portrait()
	if portrait != null and portrait.has_method(&"play"):
		portrait.call(&"play", action)


func _on_coach_exit() -> void:
	_emit(&"coach_exit", {})


## ポーズ画面を閉じる（ポーズ画面の『ゲームに戻る』を押したのと同じ。コーチを抜けたときなど）。
func resume_from_pause() -> void:
	if not get_tree().paused:
		return
	var button := coach_target(&"pause_resume") as BaseButton
	if button != null:
		button.pressed.emit()
	elif world != null and world.has_method(&"_toggle_pause"):
		world.call(&"_toggle_pause")


## 本物のリザルトのカードが出ている（担当 A の practice_result_card_visible）。道具がないときは false。
func result_card_visible() -> bool:
	return bool(world_call(&"practice_result_card_visible")) if has_result_screens() else false


## 本物の結果の画面（GAME OVER・CLEAR）を出すルールで、回が終わっている。
func _result_screen_up() -> bool:
	if rules == null or rules.get(&"real_result_screens") != true:
		return false
	return game_state.game_state in [Constants.STATE_GAME_OVER, Constants.STATE_CLEAR]


## 本編側に、本物の結果の画面（MatchRules.real_result_screens とカードの道具）がある。
func has_result_screens() -> bool:
	return world != null and world.has_method(&"practice_result_card_visible") and (&"real_result_screens" in MatchRules.new())


# ---------- カウントダウン（台本①の 1-7） ----------

## 3秒のカウントダウン：parts_id の「3／2／1／スタート！」を1秒ずつ出し、数字は本番の countdown_beep、
## 最後は countdown_go を鳴らす。最後の文字を出した時刻に返る（await d.countdown("c1.final.count")）。
func countdown(parts_id: String) -> void:
	var parts := PracticeTexts.get_parts(parts_id)
	var serial := step_serial
	for i in range(parts.size()):
		var last := i == parts.size() - 1
		overlay.show_countdown(parts[i], last)
		AudioManager.play_sfx(&"countdown_go" if last else &"countdown_beep")
		if last:
			return
		await wait(1.0)
		if not is_current(serial):
			overlay.show_countdown("")
			return


# ---------- 毎フレーム ----------

func _process(dt: float) -> void:
	if game_state == null or course == null or _leaving:
		return
	_watch_pause()
	var paused := get_tree().paused
	# ポーズ中は、コーチを出している間だけ吹き出しの時間を進める（ほかのレッスンの流れはポーズで止める）
	if _say != null and (not paused or _coach_on):
		_say.remaining -= dt
		if _say.remaining <= 0.0:
			_finish_say()
	if paused:
		return
	# 本物のリザルトのカード（と問題履歴）の間と、スコアタワーの演出の間（③の 3-8。本番の得点板の上の帯に重なる）は、
	# 上のコース名を隠す
	overlay.set_header_visible(not _result_screen_up() and game_state.game_state != Constants.STATE_RESULT_CEREMONY)
	_watch_players()
	idle_seconds = 0.0 if _any_play_key_held() else idle_seconds + dt
	if step != null and not finished:
		step.process(self, dt)
	_update_hatena(dt)
	_update_arrow_hint()
	if overlay != null:
		overlay.set_touch_skip_visible(allow_ghost_skip and not get_tree().paused)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or get_tree().paused:
		return
	# ③の 3-6・3-7：2回目からは、ゴーストシャークの演出を Enter で飛ばせる
	if allow_ghost_skip and key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		allow_ghost_skip = false
		skip_ghost_intro()
		get_viewport().set_input_as_handled()
		_emit(&"ghost_skip", {})
		return
	if _say == null or rules == null or not rules.input_locked:
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_finish_say()
		get_viewport().set_input_as_handled()


## スマホ：吹き出しのタップ（_unhandled_input の Enter・スペースと同じ条件で早送り）。
func _on_touch_bubble_tapped() -> void:
	if get_tree().paused or _say == null or rules == null or not rules.input_locked:
		return
	_finish_say()


## スマホ：「スキップ ▶」（_unhandled_input の Enter と同じくゴーストの演出を飛ばす）。
func _on_touch_ghost_skip() -> void:
	if get_tree().paused or not allow_ghost_skip:
		return
	allow_ghost_skip = false
	skip_ghost_intro()
	_emit(&"ghost_skip", {})


func _finish_say() -> void:
	if _say == null:
		return
	var ticket := _say
	_say = null
	overlay.hide_bubble()
	ticket.done.emit()


func _emit_say_done(ticket: SayTicket) -> void:
	ticket.done.emit()


## ハテナの立ち位置（台本①の 1.3）：いまの壁（クイズの壁、なければ看板の壁）の前。どちらもなければプレイヤーの前。
## 返り値は {key, pos, moving}。key が変わったら次の壁へ跳ぶ。
func _hatena_spot() -> Dictionary:
	if game_state.current_quiz != null:
		return {"key": "wall%d" % game_state.current_wall_index, "moving": true,
			"pos": Vector3(HATENA_WALL_X, 0.0, wall_local_z() - HATENA_WALL_FRONT)}
	if sign_wall != null:
		return {"key": "sign", "moving": false, "pos": Vector3(HATENA_WALL_X, 0.0, sign_local_z() - HATENA_WALL_FRONT)}
	if _hatena_key != "player":
		var front := player_point(1) + HATENA_PLAYER_FRONT
		front.x = clampf(front.x, -HATENA_WALL_X, HATENA_WALL_X)
		front.y = 0.0
		_hatena_player_spot = front
	return {"key": "player", "moving": false, "pos": _hatena_player_spot}


func _update_hatena(dt: float) -> void:
	if not hatena_follow or hatena == null or finished:
		return
	_hatena_hold = maxf(0.0, _hatena_hold - dt)
	var spot := _hatena_spot()
	var target: Vector3 = spot.pos
	if hatena.has_cloud():
		target.y = HATENA_CLOUD_Y
	var speed := absf(current_world_speed()) if bool(spot.moving) else 0.0
	# 跳ぶ・歩く・落ちる・雲で飛ぶ（HatenaGuide.is_moving）の間は、ハテナ自身に任せる
	var moving: Variant = hatena_call(&"is_moving")
	var busy: bool = hatena.is_hopping() or (moving is bool and moving)
	var rehop: bool = not busy and _hatena_hold <= 0.0 and hatena.position.distance_to(target) > HATENA_REHOP_DISTANCE
	if str(spot.key) != _hatena_key or rehop:
		_hatena_key = str(spot.key)
		# 跳んでいる間も壁は近づくので、着く時刻の壁の前へ跳ぶ
		var landing := target - Vector3(0.0, 0.0, speed * HATENA_JUMP_SECONDS)
		if not hatena.visible:
			hatena.place_at(landing)
		elif hatena.position.distance_to(landing) > 0.6:
			hatena.hop_to(landing, HATENA_JUMP_SECONDS)
		hatena.rotation.y = PI
		return
	if busy or _hatena_hold > 0.0:
		return
	hatena.position = hatena.position.move_toward(target, (speed + HATENA_CATCH_UP) * dt)
	# プレイヤーがハテナのいる所（x +9.5 のあたり）で壁へ向かってきたら、横へひょいとよける
	# （近くにいる間は1回だけ。離れたらまたよける）
	var near := false
	if bool(spot.moving) and player_standing(1):
		var player := player_point(1)
		var ahead := hatena.position.z - player.z
		near = absf(player.x - hatena.position.x) < DODGE_RANGE.x and ahead > -0.3 and ahead < DODGE_RANGE.y
		if near and not _dodged:
			hatena_call(&"dodge", [1.0 if player.x <= hatena.position.x else -1.0])
			hold_hatena(DODGE_HOLD_SECONDS)
	_dodged = near


## ジャンプとエモートは game_state の数と値の変化を見て、出来事にする。
func _watch_players() -> void:
	for index: int in [1, 2]:
		if index == 2 and game_state.num_players < 2:
			break
		var count := game_state.p1_jump_count if index == 1 else game_state.p2_jump_count
		if count != int(_jump_counts[index - 1]):
			_jump_counts[index - 1] = count
			_emit(&"jumped", {"player": index})
		var emote := game_state.p1_emote if index == 1 else game_state.p2_emote
		if emote != int(_emotes[index - 1]):
			_emotes[index - 1] = emote
			if emote > 0:
				_emit(&"emoted", {"player": index, "emote": emote})


## ポーズ画面を開いた・閉じた（ゲーム画面の practice_pause_changed が来なくても、tree の paused の変化で知らせる）。
func _watch_pause() -> void:
	_on_world_pause_changed(get_tree().paused)


func _on_world_pause_changed(paused: bool) -> void:
	if paused == _paused_seen:
		return
	_paused_seen = paused
	_emit(&"pause_changed", {"paused": paused})


func _on_result_action(action: StringName) -> void:
	_emit(&"result_action", {"action": action})


func _on_quit_confirm_changed(open: bool) -> void:
	_emit(&"quit_confirm", {"open": open})


func _any_play_key_held() -> bool:
	for key: Key in PLAY_KEYS:
		if Input.is_key_pressed(key):
			return true
	if game_state.num_players >= 2:
		for key: Key in P2_PLAY_KEYS:
			if Input.is_key_pressed(key):
				return true
	return false


func _bubble_anchor() -> Vector2:
	var cam := camera()
	if bubble_unanchored or cam == null:
		return Vector2.INF
	if bubble_point.is_valid():
		return _point_anchor(cam, bubble_point.call())
	if hatena == null or not hatena.visible:
		return Vector2.INF
	# ハテナが画面の外（1-6 で海を映している間など）なら、しっぽのない吹き出しを上の真ん中に出す
	var anchor := hatena.bubble_anchor(cam)
	if anchor.is_finite() and not get_viewport().get_visible_rect().grow(-8.0).has_point(anchor):
		return Vector2.INF
	return anchor


## bubble_point の付け根（グローバルな位置 point を画面へ）。カメラのうしろ・画面の外・NAN なら Vector2.INF。
func _point_anchor(cam: Camera3D, point: Variant) -> Vector2:
	if not (point is Vector3) or not (point as Vector3).is_finite():
		return Vector2.INF
	if cam.is_position_behind(point as Vector3):
		return Vector2.INF
	var anchor := cam.unproject_position(point as Vector3)
	if not get_viewport().get_visible_rect().grow(-8.0).has_point(anchor):
		return Vector2.INF
	return anchor


func _emit(event: StringName, data: Dictionary) -> void:
	if step != null and not finished and not _leaving:
		step.on_event(self, event, data)


# ---------- game_state の出来事 ----------

func _connect_state(on: bool) -> void:
	var pairs := [
		[game_state.practice_wall_contact, _on_wall_contact],
		[game_state.practice_ocean_bitten, _on_ocean_bitten],
		[game_state.practice_fence_touched, _on_fence_touched],
		[game_state.practice_quizzes_finished, _on_quizzes_finished],
		[game_state.correct_answer, _on_correct],
		[game_state.wrong_answer, _on_wrong],
		[game_state.health_changed, _on_health_changed],
		[game_state.player_entered_ocean, _on_entered_ocean],
		[game_state.player_caught_by_saw, _on_caught_by_saw],
		[game_state.question_completed, _on_question_completed],
		[game_state.state_changed, _on_state_changed],
	]
	# 本編側（担当 A）の段階4の signal。まだないときはつながない（drop_wall が着地の代わりの合図を出す）。
	# 段階6（③）の2人の出来事も、あるものだけつなぐ（ゴーストの signal はゲーム画面にあればそちら。_connect_world）。
	for optional: Array in [[&"practice_wall_landed", _on_wall_landed], [&"practice_round_lost", _on_round_lost],
			[&"local_push_event", _on_local_push_event], [&"question_winner_decided", _on_question_winner],
			[&"result_ceremony_phase_changed", _on_ceremony_phase]] + _six_signals():
		if game_state.has_signal(optional[0]):
			pairs.append([Signal(game_state, optional[0]), optional[1]])
	for pair: Array in pairs:
		var sig: Signal = pair[0]
		var callback: Callable = pair[1]
		if on and not sig.is_connected(callback):
			sig.connect(callback)
		elif not on and sig.is_connected(callback):
			sig.disconnect(callback)


## ゲーム画面の段階5の signal（担当 A）。まだないときはつながない（ポーズは tree の paused を見る）。
## 段階7のオンラインの見せ方の「たいせんを やめますか？」（practice_quit_confirm_changed）も、あればつなぐ。
func _connect_world(on: bool) -> void:
	var world_only := [&"practice_pause_changed", &"practice_result_action", &"practice_quit_confirm_changed"]
	for pair: Array in [[&"practice_pause_changed", _on_world_pause_changed], [&"practice_result_action", _on_result_action],
			[&"practice_quit_confirm_changed", _on_quit_confirm_changed]] + _six_signals():
		if not world.has_signal(pair[0]):
			continue
		# 段階6の signal が game_state にもあれば、そちらだけにつなぐ（2回知らせない）
		if game_state != null and game_state.has_signal(pair[0]) and pair[0] not in world_only:
			continue
		var sig := Signal(world, pair[0])
		var callback: Callable = pair[1]
		if on and not sig.is_connected(callback):
			sig.connect(callback)
		elif not on and sig.is_connected(callback):
			sig.disconnect(callback)


## リザルトのカードの出来事の signal（評価・問題履歴）がゲーム画面にあるか（ないときは、押すまで待たずに進める）。
func has_result_actions() -> bool:
	return world != null and world.has_signal(&"practice_result_action")


## 本編側の practice_round_lost があるか（ないときは、レッスンが state_changed の GAME_OVER で代わりにする）。
func has_round_lost_signal() -> bool:
	return game_state.has_signal(&"practice_round_lost")


func _on_wall_contact(player_index: int, door: int, correct: bool) -> void:
	_emit(&"wall_contact", {"player": player_index, "door": door, "correct": correct})


func _on_ocean_bitten(player_index: int) -> void:
	_emit(&"ocean_bitten", {"player": player_index})


## 見えないさくにさわった：さわった所がうっすら光り、「ぽよん」（台本①の 1.5）。
func _on_fence_touched(player_index: int) -> void:
	var point := player_point(player_index)
	point.y = 0.0
	marks_call(&"flash_fence", [point])
	AudioManager.play_sfx(FENCE_SFX)
	_emit(&"fence_touched", {"player": player_index})


func _on_quizzes_finished() -> void:
	_emit(&"quizzes_finished", {})


func _on_correct() -> void:
	_emit(&"correct", {})


func _on_wrong(message: String) -> void:
	_emit(&"wrong", {"message": message})


func _on_health_changed(player_index: int, previous_hp: int, hp: int) -> void:
	_emit(&"health_changed", {"player": player_index, "previous": previous_hp, "hp": hp})


func _on_entered_ocean(player_index: int, _local_position: Vector3) -> void:
	_emit(&"entered_ocean", {"player": player_index})


func _on_caught_by_saw(player_index: int) -> void:
	_emit(&"caught_by_saw", {"player": player_index})


func _on_question_completed(wall_index: int, correct: bool) -> void:
	_emit(&"question_completed", {"wall_index": wall_index, "correct": correct})


func _on_state_changed(new_state: String) -> void:
	_emit(&"state_changed", {"state": new_state})


func _on_wall_landed(wall_index: int) -> void:
	_landing_serial += 1
	_emit(&"wall_landed", {"wall_index": wall_index})


func _on_round_lost(reason: StringName) -> void:
	_emit(&"round_lost", {"reason": reason})


## 段階6（③）の本編側の signal（担当 A）。game_state かゲーム画面のどちらかにある。
func _six_signals() -> Array:
	return [[&"practice_saw_caught", _on_saw_caught], [&"practice_ghost_ready", _on_ghost_ready],
		[&"practice_ghost_dash", _on_ghost_dash], [&"practice_ghost_hit", _on_ghost_hit],
		[&"practice_ghost_missed", _on_ghost_missed], [&"practice_ceremony_finished", _on_ceremony_finished]]


func _on_local_push_event(event: Dictionary) -> void:
	_emit(&"push", {"kind": StringName(str(event.get("kind", ""))), "player": int(event.get("player", 0))})


func _on_question_winner(question_index: int, winner_mask: int) -> void:
	_emit(&"winner", {"question": question_index, "mask": winner_mask})


func _on_ceremony_phase(phase: int) -> void:
	_emit(&"ceremony_phase", {"phase": phase})


func _on_saw_caught(player_index: int) -> void:
	_emit(&"saw_caught", {"player": player_index})


func _on_ghost_ready(player_index: int) -> void:
	_emit(&"ghost_ready", {"player": player_index})


func _on_ghost_dash(player_index: int) -> void:
	_emit(&"ghost_dash", {"player": player_index})


func _on_ghost_hit(attacker: int, victim: int) -> void:
	_emit(&"ghost_hit", {"attacker": attacker, "victim": victim, "player": attacker})


func _on_ghost_missed(player_index: int) -> void:
	_emit(&"ghost_missed", {"player": player_index})


func _on_ceremony_finished(winner: int) -> void:
	_emit(&"ceremony_finished", {"winner": winner})
