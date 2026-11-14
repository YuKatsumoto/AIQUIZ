class_name PracticeCustomizeGuide
extends Node

## メインメニューの上のコース⑤「カスタマイズ」（course5_script.md v0.3）。以前のチュートリアルのカスタマイズ紹介と同じ、
## 画像カード（PracticeImageTour）で紹介する。コース選択で⑤を選ぶと main_menu.practice_start_here が、
## 実践コース（1P・ローカル2P）のあとは main_menu._begin_pending_customize_tutorial が作って setup(menu, resume) を呼ぶ（画面は移らない）。
##   ページ：カスタマイズの開き方 → 帽子 → エモート → 壁の速さ → 設定（画像は tests/customize_tour_capture_bootstrap.gd で撮る）
##   クリア：クリアカードとスタンプ（★なし。5つそろったら一言）→［メニューに戻る］でモード選択へ。
## ← → でページをめくり、Esc で残りのページをとばしてクリアへ。設定は何も変えない（見るだけ）。
## 文字は全部 PracticeTexts の ID（c5.*）。

## 案内を終えた
signal finished
## 進み具合が変わった（ページの id（&"menu"・&"hat"・&"emote"・&"speed"・&"set"）・&"clear"・&"card"・&"leaving"・&"done"。テスト用）
signal phase_changed(phase: StringName)

const COURSE_ID := "c5"
## ページ：id・画像・枠（画像に対する割合。tests/customize_tour_capture_runtime.gd が書く artifacts/customize_tour/focus.json の値）・
## 文字の ID（c5.tour.<text>.title・.body・.note）
const PAGES: Array[Dictionary] = [
	{"id": &"menu", "image": preload("res://assets/ui/tutorial/customize_menu.png"),
		"focus": Rect2(0.261, 0.572, 0.18, 0.061), "text": "menu"},
	{"id": &"hat", "image": preload("res://assets/ui/tutorial/customize_skin_hat.png"),
		"focus": Rect2(0.584, 0.467, 0.363, 0.139), "text": "hat"},
	{"id": &"emote", "image": preload("res://assets/ui/tutorial/customize_emote.png"),
		"focus": Rect2(0.506, 0.328, 0.441, 0.511), "text": "emote"},
	{"id": &"speed", "image": preload("res://assets/ui/tutorial/customize_wall_speed.png"),
		"focus": Rect2(0.584, 0.372, 0.363, 0.276), "text": "speed"},
	{"id": &"set", "image": preload("res://assets/ui/tutorial/customize_settings.png"),
		"focus": Rect2(0.203, 0.401, 0.594, 0.322), "text": "set"},
]
## ⑤のページの数（上の進み具合の点）
const LESSON_COUNT := 5
## スタンプが押されてから、全部そろった一言を出すまでの秒
const ALL_STAMPS_DELAY := 0.8

var menu: Control = null
var game_state: QuizGameState = null
var overlay: PracticeOverlay = null
var tour: PracticeImageTour = null
var phase := &""
var first_run := false
## 旧チュートリアル（1P・ローカル2P 実践コース）のあとのカスタマイズ紹介として始めた（main_menu._begin_pending_customize_tutorial）。
## このときは、ほかのコース（①〜④）のスタンプを数える一言（c5.clear.all）を出さない
var from_tutorial := false
## とばしたページの数
var skipped := 0

var _ending := false
## 見たページ（とばした数を数える）
var _seen := {}
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _mouse_saved := false


func setup(main_menu: Control, resume: Dictionary) -> void:
	menu = main_menu
	game_state = QuizManager.game_state
	first_run = bool(resume.get("first_run", false))
	from_tutorial = bool(resume.get("from_tutorial", false))
	skipped = int(resume.get("skipped", 0))
	overlay = PracticeOverlay.new()
	overlay.name = "PracticeCustomizeOverlay"
	add_child(overlay)
	overlay.set_course(PracticeTexts.get_text("c5.title"), LESSON_COUNT)
	overlay.set_progress(0)
	# ページの上に「⑤ カスタマイズ 1 / 5」と点を出すので、上のコース名は隠す
	overlay.set_header_visible(false)
	overlay.clear_button_pressed.connect(_on_card_button)
	# 実践コースのあとはマウスを隠していることがある：紹介の間は出す
	_mouse_mode = Input.get_mouse_mode()
	_mouse_saved = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	tour = PracticeImageTour.new()
	tour.name = "PracticeCustomizeTour"
	tour.setup(tour_pages(), PracticeTexts.get_text("c5.title"))
	tour.page_changed.connect(_on_page_changed)
	tour.finished.connect(_on_tour_finished)
	add_child(tour)


## 画像カードのページ（文字は PracticeTexts から。スマホは TOUCH_TEXTS の言い方）
static func tour_pages() -> Array[Dictionary]:
	var pages: Array[Dictionary] = []
	for page: Dictionary in PAGES:
		var key := str(page.text)
		pages.append({"id": page.id, "image": page.image, "focus": page.focus,
			"title": PracticeTexts.get_text("c5.tour.%s.title" % key), "body": PracticeTexts.get_text("c5.tour.%s.body" % key),
			"note": PracticeTexts.get_text("c5.tour.%s.note" % key)})
	return pages


func _on_page_changed(index: int) -> void:
	_seen[index] = true
	overlay.set_progress(index)
	_set_phase(StringName(PAGES[index].id))


func _on_tour_finished(completed: bool) -> void:
	if not completed:
		skipped += PAGES.size() - _seen.size()
	_clear()


## クリア：スタンプ（カード。★なし）→（5つそろったときだけ）「スタンプが全部そろったね！」。ボタン［メニューに戻る］。
func _clear() -> void:
	if _ending or not is_inside_tree():
		return
	_set_phase(&"clear")
	overlay.set_progress(LESSON_COUNT)
	GameManager.mark_practice_stamp(COURSE_ID, false)
	_set_phase(&"card")
	var lines := PracticeTexts.get_parts("c5.clear.card")
	var buttons := PracticeTexts.get_parts("c5.clear.buttons")
	var number := str(PracticeCatalog.find(COURSE_ID).get("number", 5))
	overlay.show_clear_card(lines, number, false, buttons, 0)
	if not from_tutorial and all_stamps():
		await get_tree().create_timer(ALL_STAMPS_DELAY, true).timeout
		if not _ending and is_inside_tree():
			overlay.show_bubble(PracticeTexts.get_text("c5.clear.all"))


## スタンプが5つ（コース選択の全部のコース）そろったか
static func all_stamps() -> bool:
	for course: Dictionary in PracticeCatalog.COURSES:
		if not GameManager.has_practice_stamp(str(course.id)):
			return false
	return true


## ［メニューに戻る］：カードを閉じる。メニューはモード選択に戻る。
func _on_card_button(_index: int) -> void:
	if _ending:
		return
	_ending = true
	_set_phase(&"leaving")
	overlay.hide_bubble()
	overlay.hide_clear_card()
	overlay.visible = false
	_restore_mouse()
	menu.call(&"practice_menu_show_mode")
	_set_phase(&"done")
	finished.emit()
	queue_free()


## クリアカードの間は、Esc を［メニューに戻る］にする（紹介の間の Esc は PracticeImageTour がとばすのに使う）。
func _input(event: InputEvent) -> void:
	if phase != &"card" or _ending or not event.is_action_pressed(&"ui_cancel") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	_on_card_button(0)


func _set_phase(next: StringName) -> void:
	phase = next
	phase_changed.emit(next)


func _restore_mouse() -> void:
	if not _mouse_saved:
		return
	_mouse_saved = false
	Input.set_mouse_mode(_mouse_mode)


func _exit_tree() -> void:
	_restore_mouse()
