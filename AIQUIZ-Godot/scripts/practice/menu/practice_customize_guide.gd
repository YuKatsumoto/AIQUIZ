class_name PracticeCustomizeGuide
extends Node

## メインメニューの上のコース⑤「カスタマイズ」（docs/new_tutorial/phase8_design.md 1.3、course5_script.md v0.2）。
## コース選択で⑤を選ぶと、main_menu.practice_start_here が作って setup(menu, resume) を呼ぶ（画面は移らない）。
## メニュー・カスタマイズの画面・設定パネルの本物の部品を画面のコーチ（PracticeCoach）で光らせ、のこぎりの操縦席のハテナが
## 雲で出てきて案内する（②の 2-6 と同じ）。カスタマイズの間は左上に浮かび（カメラが動いても画面の同じ所）、設定パネルの間は右下の小窓。
##   5-1 カスタマイズへ（『10問チャレンジ』→『カスタマイズ』）→ 5-2 帽子 → 5-3 エモート → 5-4 壁の速さ（試したあと元の設定に戻す）
##   → 5-5 決定（『✓ 決定して戻る』）→ 5-6 設定（『設定 / API状態』→ サウンド・画面・ゲーム・接続状態 →『戻る』）
##   クリア：クリアカードとスタンプ（★なし。5つそろったら一言）→［メニューに戻る］でモード選択へ。ハテナは席へ戻る。
## Esc で、いまのレッスンをとばす（次のレッスンに要る画面は、練習が開く・閉じる）。
## 文字は全部 PracticeTexts の ID（c5.*）。

## 案内を終えた
signal finished
## 進み具合が変わった（&"arrive"・&"5-1"〜&"5-6"・&"clear"・&"card"・&"leaving"・&"done"。テスト用）
signal phase_changed(phase: StringName)

const COURSE_ID := "c5"
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const HATENA_PATH := "res://scripts/world/practice/hatena_guide.gd"
## ⑤のレッスンの数（5-1〜5-6。上の進み具合の点）
const LESSON_COUNT := 6
const LESSONS: Array[StringName] = [&"5-1", &"5-2", &"5-3", &"5-4", &"5-5", &"5-6"]
## 背景のハテナの大きさ（HatenaGuide は等倍の 1.3 倍。席のハテナ（等倍）と同じくらいにする。②と同じ）
const HATENA_SCALE := 0.77
## 雲の大きさ（等倍の雲は体より大きく、メニューの右側をふさぐので少し小さく。②と同じ）
const CLOUD_SIZE := 0.75
## メニューで浮かぶ所：画面の割合の位置と、カメラからの奥行き（m）。メニューの UI は画面の左半分（②と同じ）
const SPOT_SIDE := Vector2(0.85, 0.47)
const SPOT_SIDE_DEPTH := 10.0
## カスタマイズの間に浮かぶ所：左上の空（右に設定のパネル、キャラはタブで位置が変わる）。プレビューのキャラより手前に
## 出るよう、カメラの近くに置き、見た目の大きさが変わらないよう近い分だけ小さくする
const SPOT_CUSTOMIZE := Vector2(0.1, 0.3)
const SPOT_CUSTOMIZE_DEPTH := 2.4
## カスタマイズの間の見た目の大きさ（メニューの右側のふだんの大きさに対して）。タブでカメラの画角が変わっても、この大きさに見える
const CUSTOMIZE_SIZE := 0.9
## 浮かぶ所を移るときの、画面の上の弧の高さ（画面の高さの割合）
const GLIDE_ARC := 0.06
## 浮かんでいる間、カメラの動き（カスタマイズのタブを替えたときの寄り）に付いていく速さ（1/秒）
const HOVER_FOLLOW := 10.0
## クリア：真ん中の手前 → クリアカードの右（②と同じ）
const SPOT_FRONT := Vector2(0.6, 0.56)
const SPOT_FRONT_DEPTH := 7.5
const SPOT_CARD := Vector2(0.86, 0.58)
const SPOT_CARD_DEPTH := 8.5
## 席を離れる・戻る秒、浮かぶ所を移る秒と、雲の弧の高さ（m）
const LEAVE_SECONDS := 1.4
const RETURN_SECONDS := 1.0
const MOVE_SECONDS := 0.7
const FLY_ARC := 0.7
## 設定の画面が出そろうまでの秒（メニューの入場の動き。②と同じ）
const CONFIG_SETTLE := 0.5
## タブ・パネルが変わってから光らせるまでの間（中身がそろうまで）
const SCREEN_SETTLE := 0.3
## 画面が開く・閉じるのを待つ秒の上限
const SCREEN_WAIT := 4.0
## 席が来るのを待つ秒の上限（メニューの最初の入場の間）
const SEAT_WAIT := 6.0

var menu: Control = null
var game_state: QuizGameState = null
var coach: PracticeCoach = null
var overlay: PracticeOverlay = null
## 背景の世界（メニューとカスタマイズの共有の 3D）に置いた HatenaGuide
var hatena: HatenaGuide = null
var phase := &""
var first_run := false
## 旧チュートリアル（1P・ローカル2P 実践コース）のあとのカスタマイズ紹介として始めた（main_menu._begin_pending_customize_tutorial）。
## このときは、ほかのコース（①〜④）のスタンプを数える一言（c5.clear.all）を出さない
var from_tutorial := false
## とばしたレッスンの数
var skipped := 0

## Esc で、いまのレッスンをとばす
var _skip := false
## いまのレッスンが Esc でとばせるか
var _skippable := false
var _ending := false
## いまの _fly の番号（新しい _fly が始まったら、前のは止まる）
var _fly_serial := 0
## true の間、ハテナは浮かぶ所（_hover_spot）にいて、カメラが動いても付いていく
var _hover := false
## _fly で飛んでいる最中
var _flying := false
## 押した・動かした（踊りの一覧・壁の速さのスライダー）
var _picked := false
var _moved := false
## 5-4 の前の壁の速さ（tuning.wall_speed_override。0 は自動）。_wall_saved の間は、レッスンを抜けるときに戻す
var _wall_before := 0.0
var _wall_saved := false
## メニューのカメラの画角（度。始めたとき）。カスタマイズのタブで画角が変わっても、ハテナの見た目の大きさをそろえる
var _menu_fov := 0.0
## 席へ戻る・席を離れる動きの最中（PracticeSeatMoves）
var _seat_moves: PracticeSeatMoves = null


func setup(main_menu: Control, resume: Dictionary) -> void:
	menu = main_menu
	game_state = QuizManager.game_state
	first_run = bool(resume.get("first_run", false))
	from_tutorial = bool(resume.get("from_tutorial", false))
	skipped = int(resume.get("skipped", 0))
	coach = PracticeCoach.new()
	coach.name = "PracticeCustomizeCoach"
	add_child(coach)
	coach.exit_requested.connect(_on_exit_requested)
	coach.set_anchor(_hatena_anchor)
	# 設定パネルの行は横に広いので、吹き出しが小窓のハテナの顔にかぶるより、光っている行の端にかかるほうを選ぶ
	coach.portrait_avoid = 2.0
	overlay = PracticeOverlay.new()
	overlay.name = "PracticeCustomizeOverlay"
	add_child(overlay)
	overlay.set_course(PracticeTexts.get_text("c5.title"), LESSON_COUNT)
	overlay.set_progress(0)
	overlay.clear_button_pressed.connect(_on_card_button)
	var camera := _camera()
	_menu_fov = camera.fov if camera != null else 0.0
	_make_hatena()
	_run.call_deferred()


# ---------- 流れ ----------

func _run() -> void:
	_set_phase(&"arrive")
	await _leave_seat()
	_hover = true
	await _begin_lesson(0)
	await _go_lesson()
	_end_lesson()
	await _begin_lesson(1)
	await _hat_lesson()
	_end_lesson()
	await _begin_lesson(2)
	await _emote_lesson()
	_end_lesson()
	await _begin_lesson(3)
	await _speed_lesson()
	_end_lesson()
	await _begin_lesson(4)
	await _done_lesson()
	_end_lesson()
	await _begin_lesson(5)
	await _settings_lesson()
	_end_lesson()
	if is_inside_tree():
		await _clear()


## レッスンを始める：進み具合の点・とばせるようにする・そのレッスンに要る画面にする
func _begin_lesson(index: int) -> void:
	_skip = false
	_skippable = true
	_set_phase(LESSONS[index])
	overlay.set_progress(index)
	coach.clear_focus()
	if index == 0:
		await _show_menu_screen(false)
	elif index <= 4:
		await _show_customize()
	else:
		await _show_menu_screen(true)


func _end_lesson() -> void:
	_skippable = false
	if _wall_saved:
		_restore_wall_speed()
	if _skip:
		skipped += 1
		coach.hide_bubble()
		coach.clear_focus()
	_skip = false


## 5-1 カスタマイズへ：「自分らしく飾ってみよう！」→『10問チャレンジ』を押すまで待つ →『カスタマイズ』を押すまで待つ
func _go_lesson() -> void:
	_play(&"wave")
	if not await _line("c5.go.1"):
		return
	_point_menu(&"mode_ten", true)
	coach.say("c5.go.2", -1.0, true)
	if not await _until(func() -> bool: return game_state.menu_step == Constants.MENU_STEP_CONFIG):
		return
	coach.clear_focus()
	_play(&"clap")
	await coach.wait(CONFIG_SETTLE)
	if _skip:
		return
	_point_menu(&"customize", true)
	coach.say("c5.go.3", -1.0, true)
	await _until(func() -> bool: return bool(menu.call(&"practice_customize_open")))


## 5-2 帽子：『スキン』を押すまで待つ →「◀ ▶で変えてみて！」→ 変えるまで待つ →「似合ってる！」（プロペラ帽はゆっくり落ちる）
## →「P2の帽子も選べるよ」（プレイヤー１・２。押してもよい）→「右ドラッグで回せるよ」（プレビュー。試してもよい）
func _hat_lesson() -> void:
	if not await _open_tab(&"skin", &"tab_skin", "c5.hat.1"):
		return
	var p1_before := game_state.p1_hat
	var p2_before := game_state.p2_hat
	_point_customize([&"skin_hat"], true)
	coach.say("c5.hat.2", -1.0, true)
	if not await _until(func() -> bool: return game_state.p1_hat != p1_before or game_state.p2_hat != p2_before):
		return
	coach.clear_focus()
	_play(&"clap")
	var hat := game_state.p1_hat if game_state.p1_hat != p1_before else game_state.p2_hat
	if not await _line("c5.hat.propeller" if hat == HatData.HAT_PROPELLER else "c5.hat.3"):
		return
	# 『プレイヤー１』『プレイヤー２』を光らせ、帽子もそのまま選べる
	_point_customize([&"skin_players"], true, false, [&"skin_hat"])
	if not await _line("c5.hat.4"):
		return
	# プレビュー（右ドラッグで回る・ホイールで大きさ）。プレイヤーと帽子もそのまま選べる
	_point_customize([&"preview"], true, false, [&"skin_players", &"skin_hat"])
	await _line("c5.hat.5")


## 5-3 エモート：『エモート』を押すまで待つ →「枠を選んで踊りを入れてみよう！」（枠と一覧）→ 1つ選ぶまで待つ →「いい踊りだね！」
## →「1番は勝ったときのダンスになるよ」（1番の枠）→「ゲーム中は1・2・3キーで出せるよ」（枠）
func _emote_lesson() -> void:
	if not await _open_tab(&"emote", &"tab_emote", "c5.emote.1"):
		return
	_picked = false
	var cards := _emote_cards()
	for card: BaseButton in cards:
		if not card.pressed.is_connected(_on_emote_picked):
			card.pressed.connect(_on_emote_picked)
	_point_customize([&"emote_slots", &"emote_grid"], true)
	coach.say("c5.emote.2", -1.0, true)
	var picked := await _until(func() -> bool: return _picked)
	for card: BaseButton in cards:
		if is_instance_valid(card) and card.pressed.is_connected(_on_emote_picked):
			card.pressed.disconnect(_on_emote_picked)
	if not picked:
		return
	coach.clear_focus()
	_play(&"clap")
	if not await _line("c5.emote.3"):
		return
	_point_customize([&"emote_slot1"], false)
	if not await _line("c5.emote.4"):
		return
	_point_customize([&"emote_slots"], false)
	await _line("c5.emote.5")


func _on_emote_picked() -> void:
	_picked = true


## 5-4 壁の速さ：『壁速度』を押すまで待つ →「ふだんは自動がおすすめだよ」（自動／手動の表示）→「スライダーを動かしてみて！」
## → 動かすまで待つ →「速すぎたらゆっくりにしてね」→「元に戻しておくね」（『自動モードに戻す』。5-4 の前の設定へ戻す）
func _speed_lesson() -> void:
	_wall_before = game_state.tuning.wall_speed_override
	_wall_saved = true
	if not await _open_tab(&"wall", &"tab_wall", "c5.speed.1"):
		return
	_point_customize([&"wall_mode"], false)
	if not await _line("c5.speed.2"):
		return
	_moved = false
	var slider := _customize_target(&"wall_slider") as Range
	if slider != null and not slider.value_changed.is_connected(_on_slider_moved):
		slider.value_changed.connect(_on_slider_moved)
	_point_customize([&"wall_slider"], true)
	coach.say("c5.speed.3", -1.0, true)
	var moved := await _until(func() -> bool: return _moved or slider == null)
	if slider != null and slider.value_changed.is_connected(_on_slider_moved):
		slider.value_changed.disconnect(_on_slider_moved)
	if not moved:
		return
	coach.clear_focus()
	_play(&"clap")
	if not await _line("c5.speed.4"):
		return
	_point_customize([&"wall_reset"], false)
	_restore_wall_speed()
	await _line("c5.speed.5")


func _on_slider_moved(_value: float) -> void:
	_moved = true


## 5-4 の前の壁の速さへ戻す（自動だったら『自動モードに戻す』と同じ）
func _restore_wall_speed() -> void:
	_wall_saved = false
	var customize := _customize()
	if customize != null and customize.has_method(&"practice_set_wall_speed"):
		customize.call(&"practice_set_wall_speed", _wall_before)
	else:
		game_state.tuning.wall_speed_override = _wall_before


## 5-5 決定：「『✓ 決定して戻る』を押してね！」→ 押すまで待つ（カスタマイズが閉じる）
func _done_lesson() -> void:
	_point_customize([&"done"], true)
	coach.say("c5.done.1", -1.0, true)
	await _until(func() -> bool: return not bool(menu.call(&"practice_customize_open")))


## 5-6 設定：「次はメニューの設定を見よう」→『設定 / API状態』を押すまで待つ → 設定パネル（ハテナは右下の小窓）：
## サウンド（動かしてもよい）→ 画面 →（ゲームの行が出ているときだけ）サドンデス → 接続状態 →『戻る』を押すまで待つ
func _settings_lesson() -> void:
	_play(&"wave")
	if not await _line("c5.set.1"):
		return
	_point_menu(&"settings", true)
	coach.say("c5.set.3", -1.0, true)
	if not await _until(func() -> bool: return bool(menu.call(&"practice_settings_open"))):
		return
	coach.clear_focus()
	coach.hide_bubble()
	_set_settings_view(true)
	await coach.wait(SCREEN_SETTLE)
	if _skip:
		return
	_point_menu_many([&"set_bgm", &"set_sfx"], true, false)
	if not await _line("c5.set.4"):
		return
	_point_menu_many([&"set_resolution", &"set_fps", &"set_quality"], false)
	if not await _line("c5.set.5"):
		return
	var sudden := menu.call(&"practice_coach_target", &"set_sudden") as Control
	if sudden != null and sudden.is_visible_in_tree():
		_point_menu_many([&"set_sudden"], false)
		if not await _line("c5.set.6"):
			return
	_point_menu_many([&"set_connection"], false)
	if not await _line("c5.set.7"):
		return
	_point_menu(&"set_back", true)
	coach.say("c5.set.8", -1.0, true)
	if await _until(func() -> bool: return not bool(menu.call(&"practice_settings_open"))):
		coach.clear_focus()
		coach.hide_bubble()
		_set_settings_view(false)


## クリア（台本⑤のクリア）：0.0 ハテナが雲で真ん中の手前へ「クリア！自分だけのスタイルだね」。1.5 スタンプ（カード。★なし）。
## 3.5（5つそろったときだけ）「スタンプが全部そろったね！」→「楽しんでね！」とボタン［メニューに戻る］。
func _clear() -> void:
	_set_phase(&"clear")
	_skippable = false
	_hover = false
	coach.clear_focus()
	coach.hide_bubble()
	# とばしてきたときも、カードはメニュー（設定パネル・カスタマイズを閉じた所）の上で
	await _close_panels()
	overlay.set_progress(LESSON_COUNT)
	if hatena != null:
		hatena.set_cloud(true)
		_fly(_screen_spot.bind(SPOT_FRONT, SPOT_FRONT_DEPTH), 0.8, HATENA_SCALE)
		_play(&"cheer")
	coach.say("c5.clear.1")
	await coach.wait(1.5)
	if _ending:
		return
	GameManager.mark_practice_stamp(COURSE_ID, false)
	# カードのボタンを押せるように、コーチの押せない仕組みを外す（吹き出しは出す）
	coach.set_guard(false)
	_set_phase(&"card")
	var lines := PracticeTexts.get_parts("c5.clear.card")
	var buttons := PracticeTexts.get_parts("c5.clear.buttons")
	var number := str(PracticeCatalog.find(COURSE_ID).get("number", 5))
	overlay.show_clear_card(lines, number, false, buttons, 0)
	if hatena != null:
		_fly(_screen_spot.bind(SPOT_CARD, SPOT_CARD_DEPTH), 0.6, HATENA_SCALE)
		_play(&"clap")
	await coach.wait(2.0)
	if _ending:
		return
	if not from_tutorial and all_stamps():
		_play(&"cheer")
		coach.say("c5.clear.all")
		await coach.wait(2.0)
		if _ending:
			return
	_play(&"wave")
	coach.say("c5.clear.2", -1.0, true)


## スタンプが5つ（コース選択の全部のコース）そろったか
func all_stamps() -> bool:
	for course: Dictionary in PracticeCatalog.COURSES:
		if not GameManager.has_practice_stamp(str(course.id)):
			return false
	return true


## ［メニューに戻る］：カードを閉じ、ハテナは席へ戻る。メニューはモード選択に戻る。
func _on_card_button(_index: int) -> void:
	if _ending:
		return
	_ending = true
	_set_phase(&"leaving")
	coach.close()
	overlay.hide_clear_card()
	overlay.visible = false
	menu.call(&"practice_menu_show_mode")
	await _return_to_seat(RETURN_SECONDS)
	_set_phase(&"done")
	finished.emit()
	queue_free()


func _on_exit_requested() -> void:
	if not _skippable or _skip or _ending:
		return
	_skip = true
	coach.hide_bubble()
	coach.clear_focus()


## クリアカードの間は、コーチの押せない仕組みを外しているので、Esc は［メニューに戻る］にする。
func _input(event: InputEvent) -> void:
	if phase != &"card" or _ending or not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	_on_card_button(0)


func _set_phase(next: StringName) -> void:
	phase = next
	phase_changed.emit(next)


# ---------- 画面 ----------

## メニュー（カスタマイズと設定パネルを閉じた所）にする。config なら設定の画面、でなければモード選択。
func _show_menu_screen(config: bool) -> void:
	await _close_panels()
	var step := Constants.MENU_STEP_CONFIG if config else Constants.MENU_STEP_MODE
	if game_state.menu_step != step:
		menu.call(&"practice_menu_show_config" if config else &"practice_menu_show_mode")
		await coach.wait(CONFIG_SETTLE)


## 設定パネルとカスタマイズを閉じる（とばしてきたときは練習が閉じる）。閉じる動き（メニューのボタンが戻ってくる）が
## 済むまで待ち、ハテナはメニューの右側へ戻る。
func _close_panels() -> void:
	if bool(menu.call(&"practice_settings_open")):
		menu.call(&"practice_close_settings")
	_set_settings_view(false)
	if bool(menu.call(&"practice_customize_open")):
		menu.call(&"practice_close_customize")
	await _until(func() -> bool: return bool(menu.call(&"practice_menu_idle")), SCREEN_WAIT, false)
	await _glide()


## カスタマイズを開いた所にする（とばしてきたときは練習が開く）。開ききったら、ハテナは左上へ。
func _show_customize() -> void:
	if bool(menu.call(&"practice_settings_open")):
		menu.call(&"practice_close_settings")
	_set_settings_view(false)
	if not bool(menu.call(&"practice_customize_open")):
		if game_state.menu_step != Constants.MENU_STEP_CONFIG:
			menu.call(&"practice_menu_show_config")
			await coach.wait(CONFIG_SETTLE)
		menu.call(&"practice_open_customize")
	await _until(func() -> bool: return bool(menu.call(&"practice_customize_ready")), SCREEN_WAIT, false)
	await _glide()


## タブ section を開いた所にする：開いていなければ tab を光らせて「押してみて」（text_id）と待つ。Esc でとばしたら false。
func _open_tab(section: StringName, tab: StringName, text_id: String) -> bool:
	var customize := _customize()
	if customize == null:
		return false
	if StringName(customize.call(&"practice_section")) != section:
		_point_customize([tab], true)
		coach.say(text_id, -1.0, true)
		if not await _until(func() -> bool: return StringName(customize.call(&"practice_section")) == section):
			return false
	coach.clear_focus()
	await coach.wait(SCREEN_SETTLE)
	return not _skip


## 設定パネルの間：背景のハテナはパネルに隠れるので、右下の小窓で案内する。上のコース名は、パネルの見出し「設定」に
## 重なるので隠す
func _set_settings_view(on: bool) -> void:
	coach.show_portrait(on)
	overlay.set_header_visible(not on)


func _customize() -> Control:
	return menu.call(&"practice_customize") as Control


func _customize_target(id: StringName) -> Control:
	var customize := _customize()
	return customize.call(&"practice_coach_target", id) as Control if customize != null else null


## 踊りの一覧のボタン
func _emote_cards() -> Array[BaseButton]:
	var cards: Array[BaseButton] = []
	var grid := _customize_target(&"emote_grid")
	if grid == null:
		return cards
	for child: Node in grid.get_children():
		if child is BaseButton:
			cards.append(child as BaseButton)
	return cards


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


## メニューの部品（main_menu.practice_coach_target）を光らせ、ハテナはそちらを指す。
func _point_menu(id: StringName, clickable: bool, grab_focus := true) -> void:
	_point_menu_many([id], clickable, grab_focus)


func _point_menu_many(ids: Array, clickable: bool, grab_focus := true) -> void:
	var targets: Array = []
	var hidden: Array = []
	for id: StringName in ids:
		var target := menu.call(&"practice_coach_target", id) as Control
		# スマホは設定の一部の行（解像度）を隠している：隠した行は光らせず、残りの行（FPS・画質）だけを指す。
		if target != null and not target.visible and MobileUi.is_touch_ui():
			hidden.append(target)
			continue
		targets.append(target)
	if targets.is_empty():
		targets = hidden
	coach.focus(targets, clickable, grab_focus)
	_play(&"point")


## カスタマイズの画面の部品を光らせる。also は光らせないが押せる部品
func _point_customize(ids: Array, clickable: bool, grab_focus := true, also: Array = []) -> void:
	var targets: Array = []
	for id: StringName in ids:
		targets.append(_customize_target(id))
	var extra: Array = []
	for id: StringName in also:
		extra.append(_customize_target(id))
	coach.focus(targets, clickable, grab_focus, extra)
	_play(&"point")


## 背景のハテナ（設定パネルの間は小窓のハテナ）の身ぶり
func _play(action: StringName) -> void:
	if bool(menu.call(&"practice_settings_open")) and coach.portrait() != null:
		coach.portrait().call(&"play", action)
		return
	if hatena != null:
		hatena.play(action)


# ---------- 背景のハテナ ----------

func _make_hatena() -> void:
	var world := menu.call(&"practice_menu_world") as Node
	if world == null or not ResourceLoader.exists(HATENA_PATH):
		return
	var script := load(HATENA_PATH) as Script
	var node: Object = script.new() if script != null else null
	if not (node is HatenaGuide):
		return
	hatena = node as HatenaGuide
	hatena.name = "PracticeCustomizeHatena"
	world.add_child(hatena)
	hatena.setup(str(GameManager.graphics_quality))
	hatena.scale = Vector3.ONE * HATENA_SCALE
	hatena.set_cloud_size(CLOUD_SIZE)
	hatena.visible = false


func _camera() -> Camera3D:
	return menu.call(&"practice_menu_camera") as Camera3D


func _camera_point() -> Vector3:
	var camera := _camera()
	return camera.global_position if camera != null else Vector3(0.0, 0.0, 30.0)


## pos からカメラのほうを向く角度（HatenaGuide.place_at の facing）
func _facing(pos: Vector3) -> float:
	var to := _camera_point() - pos
	return atan2(to.x, to.z)


func _saw() -> SawChaseController:
	return menu.call(&"practice_menu_saw") as SawChaseController


## 席のハテナの足もとに、ハテナ（HatenaGuide の位置）を置く所。席がなければ画面の右下。
func _seat_spot() -> Vector3:
	var saw := _saw()
	if saw == null:
		return _screen_spot(Vector2(0.66, 0.72), 14.0)
	var box := saw.operator_seat_bounds()
	var center := box.get_center()
	return Vector3(center.x, box.position.y - HatenaGuide.FOOT_Y * HATENA_SCALE, center.z)


## 浮かぶ所：カスタマイズの間は左上（カメラの近く）、ほかはメニューの右側
func _hover_spot() -> Vector3:
	var place := _hover_place()
	return _screen_spot(place[0], place[1])


## 浮かぶ所の [画面の割合の位置, カメラからの奥行き（m）]
func _hover_place() -> Array:
	if bool(menu.call(&"practice_customize_open")):
		return [SPOT_CUSTOMIZE, SPOT_CUSTOMIZE_DEPTH]
	return [SPOT_SIDE, SPOT_SIDE_DEPTH]


## 浮かぶ所での大きさ（カメラから SPOT_SIDE_DEPTH のときに HATENA_SCALE。近いほど小さく）。カスタマイズの間は、
## タブでカメラの画角が狭くなっても大きく見えないよう、画角の分も小さくする
func _hover_scale() -> float:
	if not bool(menu.call(&"practice_customize_open")):
		return HATENA_SCALE
	var size := HATENA_SCALE * SPOT_CUSTOMIZE_DEPTH / SPOT_SIDE_DEPTH * CUSTOMIZE_SIZE
	var camera := _camera()
	if camera != null and _menu_fov > 1.0 and camera.fov > 1.0:
		size *= tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(_menu_fov) * 0.5)
	return size


## pos（背景の世界の座標）の [画面の割合の位置, カメラからの奥行き（m）]。カメラのうしろなら空
func _place_of(pos: Vector3) -> Array:
	var camera := _camera()
	if camera == null or camera.is_position_behind(pos):
		return []
	var view := menu.get_viewport_rect().size
	var on_screen: Vector2 = menu.call(&"practice_menu_to_screen", camera.unproject_position(pos))
	var depth := -(camera.global_transform.affine_inverse() * pos).z
	return [on_screen / view, depth]


## 画面の割合の位置（メニューの画面）に、カメラから depth m の所
func _screen_spot(ratio: Vector2, depth: float) -> Vector3:
	var camera := _camera()
	if camera == null:
		return Vector3.ZERO
	var view := menu.get_viewport_rect().size
	var on_screen: Vector2 = menu.call(&"practice_menu_from_screen", view * ratio)
	return camera.project_position(on_screen, depth)


## 浮かんでいる間は、カメラが動いても画面の同じ所にいるよう付いていく（_fly・雲の動きの間はしない）
func _process(delta: float) -> void:
	if not _hover or _flying or hatena == null or not hatena.visible or hatena.is_moving():
		return
	var k := 1.0 - exp(-HOVER_FOLLOW * delta)
	var pos := hatena.position.lerp(_hover_spot(), k)
	hatena.place_at(pos, _facing(pos))
	hatena.scale = hatena.scale.lerp(Vector3.ONE * _hover_scale(), k)


## 吹き出しの付け根：ハテナの頭の上（メニューの画面の座標）。設定パネルの間は付け根なし（小窓の頭の上に出る）
func _hatena_anchor() -> Vector2:
	if hatena == null or not hatena.visible or bool(menu.call(&"practice_settings_open")):
		return Vector2.INF
	var head := hatena.bubble_anchor(_camera())
	if not head.is_finite():
		return head
	return menu.call(&"practice_menu_to_screen", head)


## 席を離れる：席のハテナと入れ替わって立ち上がり、呼んだ雲に跳び乗って、メニューの右側へ飛んでくる（②の 2-6 と同じ。
## PracticeSeatMoves.saw_leave）。席がなければ、雲に乗って画面の右下から飛んでくる。
func _leave_seat() -> void:
	if hatena == null:
		return
	var saw := _saw()
	if saw != null:
		await _until(func() -> bool:
			return not saw.operator_arriving() and (saw.dock == null or saw.dock.is_deployed()), SEAT_WAIT, false)
	hatena.play(&"wave")
	if saw != null and saw.operator_seat != null:
		_flying = true
		var moves := _new_seat_moves()
		await moves.saw_leave(hatena, saw, _camera_point(), _hover_spot, HATENA_SCALE, LEAVE_SECONDS)
		_end_seat_moves(moves)
		_flying = false
	else:
		hatena.place_at(_seat_spot(), _facing(_seat_spot()))
		hatena.ride_cloud_to(_hover_spot(), LEAVE_SECONDS)
		await _until(func() -> bool: return not hatena.is_moving(), LEAVE_SECONDS + 1.0, false)
	if is_instance_valid(hatena):
		hatena.face_toward(_camera_point())


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


## 浮かぶ所が変わった（カスタマイズの開け閉め）ら、雲でそこへ飛ぶ。奥行きの違う所どうしを世界の中でまっすぐ結ぶと、
## 途中で画面の外へはみ出すので、画面の上の位置と奥行きを別々に移す（画面の上では小さな弧）
func _glide() -> void:
	if hatena == null or not hatena.visible or not _hover:
		return
	var from := _place_of(hatena.position)
	if from.is_empty():
		hatena.place_at(_hover_spot(), _facing(_hover_spot()))
		hatena.scale = Vector3.ONE * _hover_scale()
		return
	var to := _hover_place()
	var from_ratio: Vector2 = from[0]
	var from_depth: float = from[1]
	if from_ratio.distance_to(to[0]) < 0.01 and absf(from_depth - float(to[1])) < 0.05:
		return
	var from_scale := hatena.scale.x
	var serial := _fly_serial + 1
	_fly_serial = serial
	_flying = true
	var t := 0.0
	while t < MOVE_SECONDS:
		await get_tree().process_frame
		if not is_instance_valid(hatena) or serial != _fly_serial:
			return
		t += get_process_delta_time()
		var k := clampf(t / MOVE_SECONDS, 0.0, 1.0)
		var eased := k * k * (3.0 - 2.0 * k)
		to = _hover_place()
		var ratio: Vector2 = from_ratio.lerp(to[0], eased) - Vector2(0.0, GLIDE_ARC * 4.0 * k * (1.0 - k))
		var pos := _screen_spot(ratio, lerpf(from_depth, float(to[1]), eased))
		hatena.place_at(pos, _facing(pos))
		hatena.scale = Vector3.ONE * lerpf(from_scale, _hover_scale(), eased)
	_flying = false


## goal（位置を返す Callable。動く席・カメラにも付いていく）へ、雲で弧をえがいて飛ぶ。大きさは to_scale へ。
func _fly(goal: Callable, seconds: float, to_scale := -1.0) -> void:
	if hatena == null:
		return
	var from := hatena.position
	var from_scale := hatena.scale.x
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
		var arc := FLY_ARC * hatena.scale.x / HATENA_SCALE
		var pos := from.lerp(to, eased) + Vector3.UP * arc * 4.0 * k * (1.0 - k)
		hatena.place_at(pos, _facing(pos))
		if to_scale > 0.0:
			hatena.scale = Vector3.ONE * lerpf(from_scale, to_scale, eased)
	_flying = false


## 席へ戻り、席のハテナを出す：雲で席の横へ飛び、雲を残して座面へ跳び降りて、前を向いて座る（PracticeSeatMoves.saw_return）。
## 席がなければ、雲で席の所へ飛んで消える。
func _return_to_seat(seconds: float) -> void:
	_hover = false
	if hatena == null or not hatena.visible:
		var saw_now := _saw()
		if saw_now != null:
			saw_now.set_operator_hidden(false)
		return
	var saw := _saw()
	if saw != null and saw.operator_seat != null:
		_flying = true
		var moves := _new_seat_moves()
		await moves.saw_return(hatena, saw, _camera_point())
		_end_seat_moves(moves)
		_flying = false
	else:
		hatena.set_cloud(true)
		await _fly(_seat_spot, seconds, HATENA_SCALE)
	if not is_instance_valid(hatena):
		return
	hatena.set_cloud(false)
	hatena.visible = false
	saw = _saw()
	if saw != null:
		saw.set_operator_hidden(false)


func _exit_tree() -> void:
	# メニューごと消えるときも、席のハテナは出しておく。壁の速さを試している途中なら元に戻す
	if _wall_saved and menu != null and is_instance_valid(menu):
		_restore_wall_speed()
	if _seat_moves != null and is_instance_valid(_seat_moves):
		_seat_moves.cancel()
	var saw := _saw() if menu != null and is_instance_valid(menu) else null
	if saw != null and is_instance_valid(saw):
		saw.set_operator_hidden(false)
	if hatena != null and is_instance_valid(hatena):
		hatena.queue_free()
