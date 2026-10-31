class_name PracticeMenuGuide
extends Node

## メインメニューの上のレッスン（docs/new_tutorial/phase5_design.md 5.2、course2_script.md の 2-6 とクリア）。
## main_menu.gd が PracticeSession.resume_in_menu（{"course": "c2", "step": "2-6", "star", "skipped", "first_run"}）を見て作り、
## setup(menu, resume) を呼ぶ。メニューの本物の部品（menu.practice_coach_target）を画面のコーチ（PracticeCoach）で光らせ、
## のこぎりの操縦席のハテナ（メニューの 3D の背景）が雲で出てきて、画面の右側で案内する。
##   2-6：モード選択 →『10問チャレンジ』を押す → 設定の画面（教科を変える → 学年・むずかしさ・出題・人数・カスタマイズ・ゲーム開始）
##   クリア：ハテナが真ん中の手前へ → クリアカードとスタンプ（GameManager.mark_practice_stamp）→［ほんばんを はじめる］［あとで］
## ［ほんばんを はじめる］は、ハテナが席へ戻ってから本物の『ゲーム開始』と同じ流れ（main_menu._on_start_pressed）。
## ［あとで］は、設定の画面のまま残る（ハテナは席へ戻る）。Esc でいつでも 2-6 を とばして、クリアへ進む。
## 文字は全部 PracticeTexts の ID（c2.menu.*・c2.clear.*）。

## コーチを終えた。started_game は［ほんばんを はじめる］で本番の出発が始まったか
signal finished(started_game: bool)
## 進み具合が変わった（&"arrive"・&"mode"・&"config"・&"clear"・&"card"・&"leaving"・&"done"。テスト用）
signal phase_changed(phase: StringName)

const COURSE_ID := "c2"
const STEP_ID := "2-6"
const HATENA_PATH := "res://scripts/world/practice/hatena_guide.gd"
## ②のレッスンの数（2-1〜2-6。上の進み具合の点）と、2-6 の番号（0 から）
const LESSON_COUNT := 6
const LESSON_INDEX := 5
## 背景のハテナの大きさ（HatenaGuide は等倍の 1.3 倍。席のハテナ（等倍）と同じくらいにする）
const HATENA_SCALE := 0.77
## 雲の大きさ（HatenaGuide.set_cloud_size。等倍の雲は体より大きく、メニューの右側をふさぐので少し小さく）
const CLOUD_SIZE := 0.75
## ハテナが浮かぶ所：画面の割合の位置と、カメラからの奥行き（m）。メニューの UI は画面の左半分
const SPOT_SIDE := Vector2(0.85, 0.47)
const SPOT_SIDE_DEPTH := 10.0
## クリア：真ん中の手前 → クリアカードの右
const SPOT_FRONT := Vector2(0.6, 0.56)
const SPOT_FRONT_DEPTH := 7.5
const SPOT_CARD := Vector2(0.86, 0.58)
const SPOT_CARD_DEPTH := 8.5
## HatenaGuide は体を FOOT_Y（−1.2 m）下げて描く（y = 0 で床の上）
const HATENA_FOOT_Y := -1.2
## 席を離れる・戻る秒と、雲の弧の高さ（m）
const LEAVE_SECONDS := 1.4
const RETURN_SECONDS := 1.0
const START_RETURN_SECONDS := 0.6
const FLY_ARC := 0.7
## 設定の画面が出そろうまでの秒（メニューの入場の動き）
const CONFIG_SETTLE := 0.5
## 席が来るのを待つ秒の上限（メニューの最初の入場の間）
const SEAT_WAIT := 6.0

var menu: Control = null
var game_state: QuizGameState = null
var coach: PracticeCoach = null
var overlay: PracticeOverlay = null
## 背景の世界に置いた HatenaGuide（担当 C）
var hatena: HatenaGuide = null
var phase := &""
var star := false
var skipped := 0
var first_run := false

## Esc で 2-6 を抜けた
var _exit := false
var _ending := false
## いまの _fly の番号（新しい _fly が始まったら、前のは止まる）
var _fly_serial := 0
## 席へ戻る・席を離れる動きの最中（PracticeSeatMoves）
var _seat_moves: PracticeSeatMoves = null


func setup(main_menu: Control, resume: Dictionary) -> void:
	menu = main_menu
	game_state = QuizManager.game_state
	star = bool(resume.get("star", false))
	skipped = int(resume.get("skipped", 0))
	first_run = bool(resume.get("first_run", false))
	coach = PracticeCoach.new()
	coach.name = "PracticeMenuCoach"
	add_child(coach)
	coach.exit_requested.connect(_on_exit_requested)
	coach.set_anchor(_hatena_anchor)
	overlay = PracticeOverlay.new()
	overlay.name = "PracticeMenuOverlay"
	add_child(overlay)
	overlay.set_course(PracticeTexts.get_text("c2.title"), LESSON_COUNT)
	overlay.set_progress(LESSON_INDEX)
	overlay.clear_button_pressed.connect(_on_card_button)
	_make_hatena()
	_run.call_deferred()


# ---------- 流れ ----------

func _run() -> void:
	_set_phase(&"arrive")
	await _leave_seat()
	if not _exit:
		await _mode_lesson()
	if not _exit:
		await _config_lesson()
	await _clear()


## メニューに着く：席のハテナが立ち上がり、呼んだ雲に跳び乗って、画面の右側へ飛んでくる（PracticeSeatMoves.saw_leave）。
## 席がなければ、雲に乗って画面の右下から飛んでくる。
func _leave_seat() -> void:
	if hatena == null:
		return
	var saw := _saw()
	if saw != null:
		await _until(func() -> bool:
			return not saw.operator_arriving() and (saw.dock == null or saw.dock.is_deployed()), SEAT_WAIT)
	if _exit:
		return
	hatena.play(&"wave")
	if saw != null and saw.operator_seat != null:
		var moves := _new_seat_moves()
		await moves.saw_leave(hatena, saw, _camera_point(), _side_spot, HATENA_SCALE, LEAVE_SECONDS)
		_end_seat_moves(moves)
	else:
		hatena.place_at(_seat_spot(), _facing(_seat_spot()))
		hatena.ride_cloud_to(_side_spot(), LEAVE_SECONDS)
		await _until(func() -> bool: return not hatena.is_moving(), LEAVE_SECONDS + 1.0)
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


## モード選択（台本②の 2-6 の上の表）
func _mode_lesson() -> void:
	_set_phase(&"mode")
	if game_state.menu_step != Constants.MENU_STEP_MODE:
		menu.call("practice_menu_show_mode")
	hatena.play(&"wave")
	if not await _line("c2.menu.1"):
		return
	_point(&"mode_ten", false)
	if not await _line("c2.menu.2"):
		return
	if not await _line("c2.menu.3"):
		return
	_point(&"mode_endless", false)
	if not await _line("c2.menu.4"):
		return
	if not await _line("c2.menu.5"):
		return
	_point(&"mode_online", false)
	if not await _line("c2.menu.6"):
		return
	_point(&"mode_ten", true)
	coach.say("c2.menu.7", -1.0, true)
	await _until(func() -> bool: return game_state.menu_step == Constants.MENU_STEP_CONFIG)


## 設定（台本②の 2-6 の下の表）。『10問チャレンジ』で本物の設定の画面に変わってから。
func _config_lesson() -> void:
	_set_phase(&"config")
	coach.clear_focus()
	hatena.play(&"clap")
	await coach.wait(CONFIG_SETTLE)
	if _exit or not await _line("c2.menu.8"):
		return
	var before := game_state.subject
	_point(&"subject", true)
	coach.say("c2.menu.9", -1.0, true)
	if not await _until(func() -> bool: return game_state.subject != before and not _conveyor_moving()):
		return
	hatena.play(&"clap")
	# 学年は変えなくてもよい（押せるが、Enter は吹き出しの早送りのまま）
	_point(&"grade", true, false)
	if not await _line("c2.menu.10"):
		return
	_point(&"difficulty", false)
	if not await _line("c2.menu.11"):
		return
	_point(&"llm", false)
	if not await _line("c2.menu.12"):
		return
	_point(&"players", false)
	if not await _line("c2.menu.13"):
		return
	_point(&"customize", false)
	if not await _line("c2.menu.14"):
		return
	_point(&"start", false)
	await _line("c2.menu.15")


## クリア（台本②のクリア）：0.0 ハテナが雲で真ん中の手前へ「これで じゅんび ばっちり！」。
## 1.5 クリアカードとスタンプ（保存する）。3.5「さあ ほんばん！ がんばってね」とボタン。
func _clear() -> void:
	_set_phase(&"clear")
	coach.clear_focus()
	coach.hide_bubble()
	if game_state.menu_step != Constants.MENU_STEP_CONFIG:
		# Esc でモード選択から抜けたときも、クリアは設定の画面の上で
		menu.call("practice_menu_show_config")
	overlay.set_progress(LESSON_COUNT)
	if hatena != null:
		if not hatena.visible:
			# 席を離れる前に Esc で抜けた：ここで席から出てくる
			hatena.place_at(_seat_spot(), _facing(_seat_spot()))
			var saw := _saw()
			if saw != null:
				saw.set_operator_hidden(true)
		hatena.set_cloud(true)
		_fly(_screen_spot.bind(SPOT_FRONT, SPOT_FRONT_DEPTH), 0.8)
		hatena.play(&"cheer")
	coach.say("c2.clear.1")
	await coach.wait(1.5)
	if _ending:
		return
	GameManager.mark_practice_stamp(COURSE_ID, star)
	# カードのボタンを押せるように、コーチの押せない仕組みを外す（吹き出しは出す）
	coach.set_guard(false)
	_set_phase(&"card")
	var lines := PracticeTexts.get_parts("c2.clear.card")
	var buttons := PracticeTexts.get_parts("c2.clear.buttons")
	var number := str(PracticeCatalog.find(COURSE_ID).get("number", 2))
	# 初回の案内から始めたときは［ほんばんを はじめる］を、そうでなければ［あとで］を選んでおく
	overlay.show_clear_card(lines, number, star, buttons, 0 if first_run else buttons.size() - 1)
	if hatena != null:
		_fly(_screen_spot.bind(SPOT_CARD, SPOT_CARD_DEPTH), 0.6)
		hatena.play(&"clap")
	await coach.wait(2.0)
	if _ending:
		return
	if hatena != null:
		hatena.play(&"wave")
	coach.say("c2.clear.2", -1.0, true)


func _on_card_button(index: int) -> void:
	if _ending:
		return
	if index == 0:
		_start_game()
	else:
		_later()


## ［ほんばんを はじめる］：ハテナが席へ戻ってから、本物の『ゲーム開始』と同じ流れ（出発の演出で席のハテナも飛ぶ）。
func _start_game() -> void:
	_ending = true
	_set_phase(&"leaving")
	_close_screens()
	await _return_to_seat(START_RETURN_SECONDS)
	var started := bool(menu.call("practice_menu_start_game"))
	_finish(started)


## ［あとで］：設定の画面のまま残る。コーチを終え、ハテナは席へ戻る。
func _later() -> void:
	_ending = true
	_set_phase(&"leaving")
	_close_screens()
	await _return_to_seat(RETURN_SECONDS)
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
	if _exit or _ending or phase not in [&"arrive", &"mode", &"config"]:
		return
	_exit = true
	skipped += 1
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

## 吹き出しを出して、出し終わるまで待つ。Esc で抜けたら false。
func _line(text_id: String) -> bool:
	if _exit:
		return false
	await coach.say(text_id)
	return not _exit


## condition が true になるまで待つ（seconds まで）。Esc で抜けたら false。
func _until(condition: Callable, seconds := INF) -> bool:
	var left := seconds
	while not _exit and not bool(condition.call()):
		if left <= 0.0:
			break
		await get_tree().process_frame
		left -= get_process_delta_time()
	return not _exit


## id の部品（main_menu.practice_coach_target）を光らせ、ハテナはそちらを指す。
func _point(id: StringName, clickable: bool, grab_focus := true) -> void:
	var target: Control = menu.call("practice_coach_target", id)
	coach.focus([target], clickable, grab_focus)
	if hatena != null:
		hatena.play(&"point")


func _conveyor_moving() -> bool:
	var conveyor: Variant = menu.get("config_conveyor")
	return conveyor is MenuConfigConveyor and (conveyor as MenuConfigConveyor).is_moving()


# ---------- 背景のハテナ ----------

func _make_hatena() -> void:
	var world := menu.call("practice_menu_world") as Node
	if world == null or not ResourceLoader.exists(HATENA_PATH):
		return
	var script := load(HATENA_PATH) as Script
	var node: Object = script.new() if script != null else null
	if not (node is HatenaGuide):
		return
	hatena = node as HatenaGuide
	hatena.name = "PracticeMenuHatena"
	world.add_child(hatena)
	hatena.setup(str(GameManager.graphics_quality))
	hatena.scale = Vector3.ONE * HATENA_SCALE
	# 雲は少し小さく（ハテナの小窓と同じ。C の set_cloud_size がまだないときは等倍のまま）
	if hatena.has_method(&"set_cloud_size"):
		hatena.call(&"set_cloud_size", CLOUD_SIZE)
	hatena.visible = false


func _camera() -> Camera3D:
	return menu.call("practice_menu_camera") as Camera3D


func _camera_point() -> Vector3:
	var camera := _camera()
	return camera.global_position if camera != null else Vector3(0.0, 0.0, 30.0)


## pos からカメラのほうを向く角度（HatenaGuide.place_at の facing）
func _facing(pos: Vector3) -> float:
	var to := _camera_point() - pos
	return atan2(to.x, to.z)


func _saw() -> SawChaseController:
	return menu.call("practice_menu_saw") as SawChaseController


## 席のハテナの足もとに、ハテナ（HatenaGuide の位置）を置く所。席がなければ画面の右下。
func _seat_spot() -> Vector3:
	var saw := _saw()
	if saw == null:
		return _screen_spot(Vector2(0.66, 0.72), 14.0)
	var box := saw.operator_seat_bounds()
	var center := box.get_center()
	return Vector3(center.x, box.position.y - HATENA_FOOT_Y * HATENA_SCALE, center.z)


func _side_spot() -> Vector3:
	return _screen_spot(SPOT_SIDE, SPOT_SIDE_DEPTH)


## 画面の割合の位置（メニューの画面）に、カメラから depth m の所
func _screen_spot(ratio: Vector2, depth: float) -> Vector3:
	var camera := _camera()
	if camera == null:
		return Vector3.ZERO
	var view := menu.get_viewport_rect().size
	var on_screen: Vector2 = menu.call("practice_menu_from_screen", view * ratio)
	return camera.project_position(on_screen, depth)


## 吹き出しの付け根：ハテナの頭の上（メニューの画面の座標）
func _hatena_anchor() -> Vector2:
	if hatena == null or not hatena.visible:
		return Vector2.INF
	var head := hatena.bubble_anchor(_camera())
	if not head.is_finite():
		return head
	return menu.call("practice_menu_to_screen", head)


## goal（位置を返す Callable。動く席にも付いていく）へ、雲で弧をえがいて飛ぶ。
func _fly(goal: Callable, seconds: float) -> void:
	if hatena == null:
		return
	var from := hatena.position
	var serial := _fly_serial + 1
	_fly_serial = serial
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


## 席へ戻り、席のハテナを出す：雲で席の横へ飛び、雲を残して座面へ跳び降りて、前を向いて座る（PracticeSeatMoves.saw_return）。
## 席がなければ、雲で席の所へ飛んで消える。
func _return_to_seat(seconds: float) -> void:
	if hatena == null or not hatena.visible:
		var saw_now := _saw()
		if saw_now != null:
			saw_now.set_operator_hidden(false)
		return
	var saw := _saw()
	if saw != null and saw.operator_seat != null:
		var moves := _new_seat_moves()
		await moves.saw_return(hatena, saw, _camera_point())
		_end_seat_moves(moves)
	else:
		hatena.set_cloud(true)
		await _fly(_seat_spot, seconds)
	if not is_instance_valid(hatena):
		return
	hatena.set_cloud(false)
	hatena.visible = false
	saw = _saw()
	if saw != null:
		saw.set_operator_hidden(false)


func _exit_tree() -> void:
	if _seat_moves != null and is_instance_valid(_seat_moves):
		_seat_moves.cancel()
	# メニューごと消えるときも、席のハテナは出しておく（のこぎりもメニューといっしょに消える）
	var saw := _saw() if menu != null and is_instance_valid(menu) else null
	if saw != null and is_instance_valid(saw):
		saw.set_operator_hidden(false)
	if hatena != null and is_instance_valid(hatena):
		hatena.queue_free()
