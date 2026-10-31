class_name PracticeOnlineGuide
extends Node

## オンラインの画面の上のレッスン（コース④。docs/new_tutorial/phase7_design.md 1.1・1.3、course4_script.md v0.2）。
## online_menu.gd が練習の形で開いたとき（PracticeSession.resume_in_menu が {"course": "c4", "step": "" か "clear", "first_run": …}）に作り、
## setup(menu, resume) を呼ぶ。オンラインの画面の本物の部品（menu.practice_coach_target）を画面のコーチ（PracticeCoach）で光らせ、
## 背景の自分のヘリの操縦士のハテナが雲に乗って出てきて、画面の右側で案内する（②の 2-6 のメニューのガイドと同じ考え方）。
##   4-1 オンラインの画面 → 4-2 名前（サイコロ）→ 4-3 遊ぶ問題 → 4-4 相手の探し方（ともだちのページ → ← もどる）
##   → 4-5 スキン（3D の看板 → 何か1つ変える → ✓ けってい）→ 4-6 の始め（『ランダムマッチ』→ 本物のマッチングの演出（短い形）
##   → 約3秒で相手（CPU）が見つかる → VS カットイン → ゲーム画面の練習試合。続きは scripts/practice/courses/course_4.gd）
##   クリア（step "clear"。練習試合の『オンラインメニューへ』で戻ってきたとき）：クリアカードとスタンプ →［ランダムマッチで遊ぶ］［あとで］
## ［ランダムマッチで遊ぶ］は練習の形を終えて本物の『ランダムマッチ』と同じ流れ（ここから通信する）、［あとで］はオンラインの画面に残る。
## Esc で、いまのレッスンをとばす（4-6 は『ランダムマッチ』を押す前まで。4-6 をとばしたらクリアへ）。
## 練習の形の間は通信しない（menu.practice が true の間、オンラインの画面はリレーにつながない）。
## 文字は全部 PracticeTexts の ID（c4.*）。

## 案内を終えた。started_match は［ランダムマッチで遊ぶ］で本物のマッチングが始まったか
signal finished(started_match: bool)
## 進み具合が変わった（&"arrive"・&"4-1"〜&"4-5"・&"4-6"・&"matching"・&"clear"・&"card"・&"leaving"・&"done"。テスト用）
signal phase_changed(phase: StringName)

const COURSE_ID := "c4"
const HATENA_PATH := "res://scripts/world/practice/hatena_guide.gd"
## ④のレッスンの数（4-1〜4-6。上の進み具合の点）
const LESSON_COUNT := 6
const LESSONS: Array[StringName] = [&"4-1", &"4-2", &"4-3", &"4-4", &"4-5", &"4-6"]
## 背景のハテナの大きさ（HatenaGuide は等倍の 1.3 倍。操縦士のハテナ（等倍）と同じくらいにする）
const HATENA_SCALE := 0.77
## 雲の大きさ（等倍の雲は体より大きいので少し小さく。②のメニューと同じ）
const CLOUD_SIZE := 0.75
## ハテナが浮かぶ所：画面の割合の位置と、カメラからの奥行き（m）。オンラインの画面の UI は左の列、まん中に自分のキャラと看板。
## 吹き出しが右上の接続の表示にかからない高さ。スキン設定の間はカメラがキャラへ寄って、うしろのヘリがハテナを隠すので、
## 右上の角のカメラの近くへ（見た目の大きさが変わらないよう、近い分だけ小さくする）
const SPOT_SIDE := Vector2(0.89, 0.43)
const SPOT_SIDE_DEPTH := 10.0
const SPOT_SKIN := Vector2(0.935, 0.35)
const SPOT_SKIN_DEPTH := 1.8
## スキン設定の間の見た目の大きさ（右側のふだんの大きさに対して。キャラの光る枠にかからないよう少し小さく）
const SKIN_SIZE := 0.75
## 浮かんでいる間、カメラの動き（待機のゆれ・スキン設定の寄り）に付いていく速さ（1/秒）
const HOVER_FOLLOW := 3.0
## 光らせる部品ができるのを待つ秒の上限（3D の看板が出てくる間など）
const TARGET_WAIT := 2.0
## クリア：まん中の手前 → クリアカードの右
const SPOT_FRONT := Vector2(0.62, 0.52)
const SPOT_FRONT_DEPTH := 7.0
const SPOT_CARD := Vector2(0.87, 0.56)
const SPOT_CARD_DEPTH := 8.5
## 席を離れる・戻る秒と、雲の弧の高さ（m）
const LEAVE_SECONDS := 1.4
const RETURN_SECONDS := 1.0
const QUICK_RETURN_SECONDS := 0.6
const FLY_ARC := 0.7
## 舞台が待機の画になるのを待つ秒の上限（画面が開く間）
const STAGE_WAIT := 6.0
## 検索中に入ってから、相手（CPU）が見つかるまで（台本④の 4-6：3秒）
const SEARCH_SECONDS := 3.0
## ページが変わってから光らせるまでの間（ページの中身がそろうまで）
const PAGE_SETTLE := 0.25
## 背景のカメラは、監督が置いたあとスキン設定の寄り（OnlineSkinCloseup、process_priority 100）が動かす。
## ハテナの置き場所と吹き出しの付け根は、そのあとのカメラで決める
const AFTER_CAMERA_PRIORITY := 200

var menu: OnlineMenu = null
var coach: PracticeCoach = null
var overlay: PracticeOverlay = null
## 背景の舞台に置いた HatenaGuide（操縦士のハテナの代わりに出てくる）
var hatena: HatenaGuide = null
var phase := &""
var first_run := false
## とばしたレッスンの数
var skipped := 0

## Esc で、いまのレッスンをとばす
var _skip := false
## いまのレッスンが Esc でとばせるか
var _skippable := false
var _ending := false
## いまの _fly の番号（新しい _fly が始まったら、前のは止まる）
var _fly_serial := 0
## 押した（サイコロ）
var _dice_pressed := false
## VS の覆いに写すために隠した（このあと吹き出しは出さない）
var _swapping := false
## true の間、ハテナは画面の右側の決まった所に浮かび、カメラが動いても付いていく
var _hover := false
## _fly で飛んでいる最中
var _flying := false
## 席へ戻る・席を離れる動きの最中（PracticeSeatMoves）
var _seat_moves: PracticeSeatMoves = null


func setup(online_menu: OnlineMenu, resume: Dictionary) -> void:
	menu = online_menu
	first_run = bool(resume.get("first_run", false))
	skipped = int(resume.get("skipped", 0))
	process_priority = AFTER_CAMERA_PRIORITY
	coach = PracticeCoach.new()
	coach.name = "PracticeOnlineCoach"
	coach.process_priority = AFTER_CAMERA_PRIORITY
	add_child(coach)
	coach.exit_requested.connect(_on_exit_requested)
	coach.set_anchor(_hatena_anchor)
	overlay = PracticeOverlay.new()
	overlay.name = "PracticeOnlineOverlay"
	add_child(overlay)
	overlay.set_course(PracticeTexts.get_text("c4.title"), LESSON_COUNT)
	overlay.set_progress(0)
	overlay.clear_button_pressed.connect(_on_card_button)
	_make_hatena()
	if str(resume.get("step", "")) == "clear":
		_run_clear.call_deferred()
	else:
		_run.call_deferred()


# ---------- 流れ ----------

func _run() -> void:
	_set_phase(&"arrive")
	await _wait_ready()
	await _leave_seat(_hover_spot)
	_hover = true
	await _begin_lesson(0)
	await _home_lesson()
	_end_lesson()
	await _begin_lesson(1)
	await _name_lesson()
	_end_lesson()
	await _begin_lesson(2)
	await _quiz_lesson()
	_end_lesson()
	await _begin_lesson(3)
	await _find_lesson()
	_end_lesson()
	await _begin_lesson(4)
	await _skin_lesson()
	_end_lesson()
	await _begin_lesson(5)
	var started := await _match_lesson()
	_end_lesson()
	if started:
		return  # ゲーム画面の練習試合へ（この画面ごと消える）
	# 4-6 を Esc でとばした：そのままクリアへ
	await _clear()


## 練習試合から戻ってきた：クリア
func _run_clear() -> void:
	_set_phase(&"arrive")
	overlay.set_progress(LESSON_COUNT)
	await _wait_ready()
	await _clear()


## 画面が開ききって、背景が待機の画になるまで待つ
func _wait_ready() -> void:
	await _until(func() -> bool: return not SceneTransition.is_transitioning(), INF, false)
	var director := menu.director
	await _until(func() -> bool:
		return director == null or (director.state == OnlineStagingDirector.State.IDLE and director.fade <= 0.01), STAGE_WAIT, false)


## レッスンを始める：進み具合の点・トップのページに戻す・とばせるようにする
func _begin_lesson(index: int) -> void:
	_skip = false
	_skippable = true
	_set_phase(LESSONS[index])
	overlay.set_progress(index)
	coach.clear_focus()
	if menu.current_id() != OnlineMenu.HOME:
		menu.go_home()
		await coach.wait(PAGE_SETTLE)


func _end_lesson() -> void:
	_skippable = false
	menu.practice_sign_enabled = false
	menu.practice_pick_enabled = false
	if _skip:
		skipped += 1
		coach.hide_bubble()
		# ともだちのページ（いれる側）を開いたままとばしたときも、選ぶ側に戻しておく
		var friend := menu.page(OnlineMenu.FRIEND) as OnlineFriendPage
		if friend != null:
			friend.practice_show_join(false)
	_skip = false


## 4-1 オンラインの画面：「ここがオンラインの画面」→「離れた相手と対戦できる」→「練習ではつながないよ」（接続の表示）
func _home_lesson() -> void:
	_play(&"wave")
	if not await _line("c4.home.1"):
		return
	if not await _line("c4.home.2"):
		return
	_point(&"status", false)
	await _line("c4.home.3")


## 4-2 名前：「相手に見える名前」（欄。打ちこんでもよい）→「本名は入れないで」→「サイコロでも決められる」→ 押すまで待つ
## →「OK」→「不適切な言葉は使えない」
func _name_lesson() -> void:
	_point(&"name_field", true, false)
	if not await _line("c4.name.1"):
		return
	if not await _line("c4.name.2"):
		return
	_dice_pressed = false
	var dice := menu.practice_coach_target(&"name_dice") as BaseButton
	if dice != null and not dice.pressed.is_connected(_on_dice_pressed):
		dice.pressed.connect(_on_dice_pressed)
	_point(&"name_dice", true)
	coach.say("c4.name.3", -1.0, true)
	var rolled := await _until(func() -> bool: return _dice_pressed or dice == null)
	if dice != null and dice.pressed.is_connected(_on_dice_pressed):
		dice.pressed.disconnect(_on_dice_pressed)
	if not rolled:
		return
	coach.clear_focus()
	_play(&"clap")
	if not await _line("c4.name.4"):
		return
	await _line("c4.name.5")


func _on_dice_pressed() -> void:
	_dice_pressed = true


## 4-3 遊ぶ問題：「ここで問題を選ぶ」（あそぶ もんだい）→「近い学年の相手と組まれる」（がくねん）
func _quiz_lesson() -> void:
	_point(&"quiz_box", true, false)
	if not await _line("c4.quiz.1"):
		return
	_point(&"grade", true, false)
	await _line("c4.quiz.2")


## 4-4 相手の探し方：『ランダムマッチ』（見せるだけ）→『ともだちと あそぶ』を押すまで待つ → ともだちのページ
## 『コードを つくる』『コードを いれる』（見せるだけ）→ コードの欄 →『← もどる』を押すまで待つ
func _find_lesson() -> void:
	_point(&"random_match", false)
	if not await _line("c4.find.1"):
		return
	_point(&"friends", true)
	coach.say("c4.find.2", -1.0, true)
	if not await _until(func() -> bool: return menu.current_id() == OnlineMenu.FRIEND):
		return
	coach.clear_focus()
	await coach.wait(PAGE_SETTLE)
	if _skip:
		return
	_point(&"code_make", false)
	if not await _line("c4.find.3"):
		return
	_point(&"code_enter", false)
	if not await _line("c4.find.4"):
		return
	# コードの欄は、いれる側のときだけ見える（押さずに見せるだけ）
	var friend := menu.page(OnlineMenu.FRIEND) as OnlineFriendPage
	friend.practice_show_join(true)
	await coach.wait(0.05)
	_point(&"code_field", false)
	if not await _line("c4.find.5"):
		return
	# 『← もどる』でトップへ（選ぶ側へ戻してから。いれる側のままだと、もどるは選ぶ側へ戻るだけ）
	friend.practice_show_join(false)
	_point(&"back", true)
	coach.say("c4.find.6", -1.0, true)
	await _until(func() -> bool: return menu.current_id() == OnlineMenu.HOME)


## 4-5 スキン：「看板からスキンを変えられる」→ 3D の看板を押すまで待つ → スキン設定「帽子と体の色を選べる」（ぼうし）
## →「キャラをクリックしてもいい」（立っているキャラ）→ 何か1つ変えたら「いいね」→「『✓ けってい』で戻る」→ 押すまで待つ
func _skin_lesson() -> void:
	menu.practice_sign_enabled = true
	# 看板はトップに戻ってから立つので、出てくるのを待ってから光らせる
	await _wait_target(&"skin_sign")
	if _skip:
		return
	_point(&"skin_sign", true)
	coach.say("c4.skin.1", -1.0, true)
	var opened := await _until(func() -> bool: return menu.current_id() == OnlineMenu.SKIN)
	menu.practice_sign_enabled = false
	if not opened:
		return
	coach.clear_focus()
	var hat_before := QuizManager.game_state.p1_hat
	var skin_before := PlayerSkinStore.get_skin_code(1)
	var changed := func() -> bool:
		return QuizManager.game_state.p1_hat != hat_before or PlayerSkinStore.get_skin_code(1) != skin_before
	await coach.wait(PAGE_SETTLE)
	if _skip:
		return
	# 帽子の ◀ ▶ を光らせ、色も選べる（光らせないが押せる）
	coach.focus([menu.practice_coach_target(&"skin_hat")], true, false, [menu.practice_coach_target(&"skin_colors")])
	_play(&"point")
	if not await _line("c4.skin.2"):
		return
	# 立っているキャラを光らせる（クリックでパーツを選べる。帽子と色もそのまま選べる）
	menu.practice_pick_enabled = true
	coach.focus([menu.practice_coach_target(&"skin_character")], true, false,
		[menu.practice_coach_target(&"skin_hat"), menu.practice_coach_target(&"skin_colors")])
	_play(&"point")
	if not await _line("c4.skin.3"):
		return
	if not await _until(changed):
		return
	menu.practice_pick_enabled = false
	coach.clear_focus()
	_play(&"clap")
	if not await _line("c4.skin.4"):
		return
	_point(&"skin_done", true)
	coach.say("c4.skin.5", -1.0, true)
	await _until(func() -> bool: return menu.current_id() == OnlineMenu.HOME)


## 4-6 の始め：「『ランダムマッチ』を押して」→ 押すまで待つ → 本番のマッチングの演出（短い形。下の帯に「あいてを さがしています…」）
## →「相手を探しているところ」→ 3秒後に相手が見つかる →「今回の相手はCPU」（VS カットイン）→ ゲーム画面へ。
## 押したら true（このあとゲーム画面へ移る）。押す前に Esc でとばしたら false。
func _match_lesson() -> bool:
	# 先にハテナがヘリへ乗りこんで操縦席に座り、そこから『ランダムマッチ』を押すのを待つ
	# （押したあとに乗ると、本番の演出で乗りこむプレイヤーとドアで重なる）。吹き出しは操縦士の頭の上
	coach.hide_bubble()
	await _return_to_seat(RETURN_SECONDS)
	if not is_inside_tree():
		return false
	if _skip:
		return false
	_point(&"random_match", true)
	_play(&"point")
	coach.say("c4.match.1", -1.0, true)
	var director := menu.director
	var pressed := await _until(func() -> bool:
		return menu.chrome() != OnlineMenu.CHROME_MENU or (director != null and director.state != OnlineStagingDirector.State.IDLE))
	if not pressed:
		return false
	# ここからは とばせない（本番のマッチングの演出の最中）
	_skippable = false
	_set_phase(&"matching")
	coach.clear_focus()
	coach.hide_bubble()
	# ハテナは先に操縦席に座っている（まだ外にいれば、すぐ席へ戻る）。このあと本番の演出でヘリが飛ぶ
	if hatena != null and hatena.visible:
		_return_to_seat(QUICK_RETURN_SECONDS, true)
	# 検索中（下の帯）に入ったら「相手を探しているところ」
	await _until(func() -> bool: return menu.current_id() == OnlineMenu.SEARCH, 20.0, false)
	if not is_inside_tree():
		return true
	coach.say("c4.match.2")
	await coach.wait(SEARCH_SECONDS)
	if not is_inside_tree():
		return true
	menu.practice_fake_match()
	# 見つかって VS カットインが出たら「今回の相手はCPU」
	if director != null:
		await _until(func() -> bool: return director.state >= OnlineStagingDirector.State.CUTIN_IN, 10.0, false)
	else:
		await _until(func() -> bool: return menu.current_id() == OnlineMenu.VERSUS, 10.0, false)
	if is_inside_tree() and not _swapping:
		coach.say("c4.match.3")
	return true


## 本物の VS の覆いに写す前に、案内の吹き出しと上のコース名を隠す（online_menu._on_swap_ready が呼ぶ）
func hide_for_swap() -> void:
	_swapping = true
	coach.close()
	overlay.visible = false


## クリア（台本④のクリア）：0.0 ハテナが雲で手前へ「オンラインの準備はこれで完了」。1.5 スタンプが押される（カード）。
## 3.5「マナーを守って楽しんで」とボタン［ランダムマッチで遊ぶ］［あとで］。スタンプは保存する（★はない）。
func _clear() -> void:
	_set_phase(&"clear")
	_skippable = false
	_hover = false
	coach.clear_focus()
	coach.hide_bubble()
	if menu.current_id() != OnlineMenu.HOME:
		menu.go_home()
	overlay.set_progress(LESSON_COUNT)
	if hatena != null:
		hatena.scale = Vector3.ONE * HATENA_SCALE
		if not hatena.visible:
			await _leave_seat(_screen_spot.bind(SPOT_FRONT, SPOT_FRONT_DEPTH))
		else:
			hatena.set_cloud(true)
			_fly(_screen_spot.bind(SPOT_FRONT, SPOT_FRONT_DEPTH), 0.8)
		_play(&"cheer")
	coach.say("c4.clear.1")
	await coach.wait(1.5)
	if _ending:
		return
	GameManager.mark_practice_stamp(COURSE_ID, false)
	# カードのボタンを押せるように、コーチの押せない仕組みを外す（吹き出しは出す）
	coach.set_guard(false)
	_set_phase(&"card")
	var lines := PracticeTexts.get_parts("c4.clear.card")
	var buttons := PracticeTexts.get_parts("c4.clear.buttons")
	var number := str(PracticeCatalog.find(COURSE_ID).get("number", 4))
	# 初回の案内から始めたときは［ランダムマッチで遊ぶ］を、そうでなければ［あとで］を選んでおく
	overlay.show_clear_card(lines, number, false, buttons, 0 if first_run else buttons.size() - 1)
	if hatena != null:
		_fly(_screen_spot.bind(SPOT_CARD, SPOT_CARD_DEPTH), 0.6)
		_play(&"clap")
	await coach.wait(2.0)
	if _ending:
		return
	_play(&"wave")
	coach.say("c4.clear.2", -1.0, true)


func _on_card_button(index: int) -> void:
	if _ending:
		return
	if index == 0:
		_start_match()
	else:
		_later()


## ［ランダムマッチで遊ぶ］：ハテナが席へ戻ってから、練習の形を終えて本物の『ランダムマッチ』と同じ流れ（ここから通信する）。
func _start_match() -> void:
	_ending = true
	_set_phase(&"leaving")
	_close_screens()
	await _return_to_seat(QUICK_RETURN_SECONDS)
	menu.practice_end()
	menu.find_match()
	_finish(true)


## ［あとで］：オンラインの画面に残る（練習の形を終える）。ハテナは席へ戻る。
func _later() -> void:
	_ending = true
	_set_phase(&"leaving")
	_close_screens()
	await _return_to_seat(RETURN_SECONDS)
	menu.practice_end()
	_finish(false)


func _close_screens() -> void:
	coach.close()
	overlay.hide_clear_card()
	overlay.visible = false


func _finish(started: bool) -> void:
	_set_phase(&"done")
	finished.emit(started)
	queue_free()


func _on_exit_requested() -> void:
	if not _skippable or _skip or _ending:
		return
	_skip = true
	coach.hide_bubble()
	coach.clear_focus()


## クリアカードの間は、コーチの押せない仕組みを外しているので、Esc は［あとで］にする。
func _input(event: InputEvent) -> void:
	if phase != &"card" or _ending or not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	_on_card_button(1)


func _set_phase(next: StringName) -> void:
	phase = next
	phase_changed.emit(next)


# ---------- 道具 ----------

## 吹き出しを出して、出し終わるまで待つ。Esc でとばしたら false。
func _line(text_id: String) -> bool:
	if _skip:
		return false
	await coach.say(text_id)
	return not _skip


## condition が true になるまで待つ（seconds まで）。skippable のとき、Esc でとばしたら false。
func _until(condition: Callable, seconds := INF, skippable := true) -> bool:
	var left := seconds
	while not (skippable and _skip) and not bool(condition.call()):
		if left <= 0.0 or not is_inside_tree():
			break
		await get_tree().process_frame
		left -= get_process_delta_time()
	return not (skippable and _skip)


## id の部品（menu.practice_coach_target）ができる（見える）まで待つ（TARGET_WAIT まで）。
func _wait_target(id: StringName) -> void:
	await _until(func() -> bool: return menu.practice_coach_target(id) != null, TARGET_WAIT)


## id の部品（menu.practice_coach_target）を光らせ、ハテナはそちらを指す。
func _point(id: StringName, clickable: bool, grab_focus := true) -> void:
	var target := menu.practice_coach_target(id)
	coach.focus([target], clickable, grab_focus)
	_play(&"point")


func _play(action: StringName) -> void:
	if hatena != null:
		hatena.play(action)


# ---------- 背景のハテナ ----------

func _make_hatena() -> void:
	var stage := menu.practice_stage()
	if stage == null or not ResourceLoader.exists(HATENA_PATH):
		return
	var script := load(HATENA_PATH) as Script
	var node: Object = script.new() if script != null else null
	if not (node is HatenaGuide):
		return
	hatena = node as HatenaGuide
	hatena.name = "PracticeOnlineHatena"
	stage.add_child(hatena)
	hatena.setup(str(GameManager.graphics_quality))
	hatena.scale = Vector3.ONE * HATENA_SCALE
	hatena.set_cloud_size(CLOUD_SIZE)
	hatena.visible = false


func _camera() -> Camera3D:
	return menu.practice_camera()


func _camera_point() -> Vector3:
	var camera := _camera()
	return camera.global_position if camera != null else Vector3(0.0, 0.0, 30.0)


## pos（舞台の座標）からカメラのほうを向く角度（HatenaGuide.place_at の facing）
func _facing(pos: Vector3) -> float:
	var stage := menu.practice_stage()
	var camera := _camera_point() if stage == null else stage.to_local(_camera_point())
	var to := camera - pos
	return atan2(to.x, to.z)


## 操縦席のハテナの足もとに、ハテナ（HatenaGuide の位置。舞台の座標）を置く所。席がなければ画面の右下。
func _seat_spot() -> Vector3:
	var pilot := menu.practice_pilot()
	var stage := menu.practice_stage()
	if pilot == null or stage == null:
		return _screen_spot(Vector2(0.75, 0.8), 12.0)
	var box := _visual_bounds(pilot)
	if not box.has_volume():
		return stage.to_local(pilot.global_position)
	var center := box.get_center()
	var feet := Vector3(center.x, box.position.y, center.z)
	return stage.to_local(feet) - Vector3(0.0, HatenaGuide.FOOT_Y * HATENA_SCALE, 0.0)


## 浮かぶ所（舞台の座標）。スキン設定の間は右上の角のほう（カメラがキャラへ寄るので）
func _hover_spot() -> Vector3:
	if menu.current_id() == OnlineMenu.SKIN:
		return _screen_spot(SPOT_SKIN, SPOT_SKIN_DEPTH)
	return _screen_spot(SPOT_SIDE, SPOT_SIDE_DEPTH)


## 浮かぶ所での大きさ（カメラから SPOT_SIDE_DEPTH のときに HATENA_SCALE。近いほど小さく）
func _hover_scale() -> float:
	if menu.current_id() == OnlineMenu.SKIN:
		return HATENA_SCALE * SPOT_SKIN_DEPTH / SPOT_SIDE_DEPTH * SKIN_SIZE
	return HATENA_SCALE


## 浮かんでいる間は、カメラが動いても画面の同じ所にいるよう、なめらかに付いていく（_fly・雲の動きの間はしない）
func _process(delta: float) -> void:
	if not _hover or _flying or hatena == null or not hatena.visible or hatena.is_moving():
		return
	var k := 1.0 - exp(-HOVER_FOLLOW * delta)
	var pos := hatena.position.lerp(_hover_spot(), k)
	hatena.place_at(pos, _facing(pos))
	hatena.scale = hatena.scale.lerp(Vector3.ONE * _hover_scale(), k)


## 画面の割合の位置（オンラインの画面）に、カメラから depth m の所（舞台の座標）
func _screen_spot(ratio: Vector2, depth: float) -> Vector3:
	var camera := _camera()
	var stage := menu.practice_stage()
	if camera == null or stage == null:
		return Vector3.ZERO
	var view := menu.get_viewport_rect().size
	var on_view := menu.practice_from_screen(view * ratio)
	return stage.to_local(camera.project_position(on_view, depth))


## node の下の見える物の、まとめたワールドの箱
static func _visual_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child: Node in node.find_children("*", "VisualInstance3D", true, false):
		var visual := child as VisualInstance3D
		if not visual.is_visible_in_tree():
			continue
		var local := visual.get_aabb()
		if not local.has_volume():
			continue
		var world := visual.global_transform * local
		box = world if first else box.merge(world)
		first = false
	return box


## 吹き出しの付け根：ハテナの頭の上（オンラインの画面の座標）。ハテナが出ていないときは、操縦席の操縦士のハテナの頭の上。
func _hatena_anchor() -> Vector2:
	var camera := _camera()
	if camera == null:
		return Vector2.INF
	# VS カットインは背景の 3D を覆うので、付け根なし（上のまん中に出す）
	if menu.director != null and menu.director.state >= OnlineStagingDirector.State.CUTIN_IN:
		return Vector2.INF
	var head := Vector2.INF
	if hatena != null and hatena.visible:
		head = hatena.bubble_anchor(camera)
	else:
		var pilot := menu.practice_pilot()
		if pilot == null or not pilot.is_visible_in_tree():
			return Vector2.INF
		var box := _visual_bounds(pilot)
		if not box.has_volume():
			return Vector2.INF
		var top := Vector3(box.get_center().x, box.end.y + 0.25, box.get_center().z)
		if camera.is_position_behind(top):
			return Vector2.INF
		head = camera.unproject_position(top)
	if not head.is_finite():
		return head
	var point := menu.practice_to_screen(head)
	# 画面の外（操縦席がカメラに入っていないなど）なら、付け根なし（上のまん中に出す）
	if not menu.get_viewport_rect().grow(-8.0).has_point(point):
		return Vector2.INF
	return point


## 席を離れる：操縦士のハテナと入れ替わって立ち上がり、かがんでドアを押し上げて降り、ドアを閉めて、呼んだ雲に跳び乗って
## goal（舞台の座標を返す Callable）へ飛んでくる（PracticeSeatMoves.heli_leave）。ヘリがなければ、席の所から雲で飛んでくる。
func _leave_seat(goal: Callable) -> void:
	if hatena == null:
		return
	hatena.play(&"wave")
	var heli := _heli()
	var stage := menu.practice_stage()
	if heli != null and heli.pilot != null and stage != null:
		_flying = true
		var moves := _new_seat_moves()
		await moves.heli_leave(hatena, heli, func() -> Vector3: return stage.to_global(goal.call()), HATENA_SCALE, LEAVE_SECONDS)
		_end_seat_moves(moves)
		_flying = false
	else:
		var seat := _seat_spot()
		hatena.place_at(seat, _facing(seat))
		_set_pilot_hidden(true)
		hatena.ride_cloud_to(goal.call(), LEAVE_SECONDS)
		await _until(func() -> bool: return not hatena.is_moving(), LEAVE_SECONDS + 1.0, false)
	if is_instance_valid(hatena):
		hatena.face_toward(_camera_point() if menu.practice_stage() == null else menu.practice_stage().to_local(_camera_point()))


## goal（位置を返す Callable）へ、雲で弧をえがいて飛ぶ。
func _fly(goal: Callable, seconds: float) -> void:
	if hatena == null:
		return
	var from := hatena.position
	var serial := _fly_serial + 1
	_fly_serial = serial
	_flying = true
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		if not is_instance_valid(hatena) or serial != _fly_serial:
			return
		t += get_process_delta_time()
		var k := clampf(t / seconds, 0.0, 1.0)
		var eased := k * k * (3.0 - 2.0 * k)
		var to: Vector3 = goal.call()
		var pos := from.lerp(to, eased) + Vector3.UP * FLY_ARC * 4.0 * k * (1.0 - k)
		hatena.place_at(pos, _facing(pos))
	_flying = false


## 席へ戻り、席の操縦士のハテナを出す：雲でヘリの横へ飛んで降り、歩いてドアを押し上げ、ステップを上がってかがんで乗り、
## ドアを閉めて右の席に座る（PracticeSeatMoves.heli_board）。quick なら（とばしたときなど）、雲で席の所へ飛んで消える。
func _return_to_seat(seconds: float, quick := false) -> void:
	_hover = false
	if hatena == null or not hatena.visible:
		_set_pilot_hidden(false)
		return
	var heli := _heli()
	if not quick and heli != null and heli.pilot != null:
		_flying = true
		var moves := _new_seat_moves()
		await moves.heli_board(hatena, heli)
		_end_seat_moves(moves)
		_flying = false
	else:
		hatena.scale = Vector3.ONE * HATENA_SCALE
		hatena.set_cloud(true)
		await _fly(_seat_spot, seconds)
	if not is_instance_valid(hatena):
		return
	hatena.set_cloud(false)
	hatena.visible = false
	_set_pilot_hidden(false)


## 自分のヘリ（操縦士のハテナが乗っている）。なければ null。
func _heli() -> OnlineHeliportHelicopter:
	var stage := menu.practice_stage() if menu != null and is_instance_valid(menu) else null
	return stage.my_heli if stage != null else null


## 席へ戻る・席を離れる動き（終わったら _end_seat_moves で消す。案内ごと消えるときは止める）。
func _new_seat_moves() -> PracticeSeatMoves:
	_seat_moves = PracticeSeatMoves.new()
	_seat_moves.name = "SeatMoves"
	add_child(_seat_moves)
	return _seat_moves


func _end_seat_moves(moves: PracticeSeatMoves) -> void:
	if is_instance_valid(moves):
		moves.queue_free()
	if _seat_moves == moves:
		_seat_moves = null


## 操縦士のハテナを隠す・出す（座っている間だけ右の席のベルトも出す）。
func _set_pilot_hidden(hidden: bool) -> void:
	var pilot := menu.practice_pilot() if menu != null and is_instance_valid(menu) else null
	if pilot != null and is_instance_valid(pilot):
		pilot.visible = not hidden
	var heli := _heli()
	if heli != null and is_instance_valid(heli) and heli.pilot != null:
		heli.set_belt(PracticeSeatMoves.HELI_SEAT_BELT, 0.0 if hidden else 1.0)


## 席のハテナが隠れたままで終わらないように
func is_pilot_hidden() -> bool:
	var pilot := menu.practice_pilot() if menu != null and is_instance_valid(menu) else null
	return pilot != null and not pilot.visible


func _exit_tree() -> void:
	if _seat_moves != null and is_instance_valid(_seat_moves):
		_seat_moves.cancel()
	# 画面ごと消えるときも、席のハテナは出しておく（舞台も画面といっしょに消える）
	_set_pilot_hidden(false)
	var heli := _heli()
	if heli != null and is_instance_valid(heli):
		heli.set_door(PracticeSeatMoves.HELI_DOOR, 0.0)
	if hatena != null and is_instance_valid(hatena):
		hatena.queue_free()
