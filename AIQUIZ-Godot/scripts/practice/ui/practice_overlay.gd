class_name PracticeOverlay
extends CanvasLayer

## 練習の画面の表示（docs/new_tutorial/foundation_design.md 8章）。PracticeDirector が作る。
##   上の真ん中：コース名と進み具合の点（●○○○○○○）
##   吹き出し：ハテナの頭の画面位置（anchor_provider）に付いて動く。画面の端で止める。1行・大きめの文字
##   看板の文字とチェックのカード（「← ✓」など）：画面の下。看板の壁（PracticeSignWall）がないときの代わり
##   しあげの表示（「しあげ 1/3」）：上の真ん中、コース名の下。カウントダウン（「3」「2」「1」「スタート！」）：真ん中
##   まきもどしの画面効果、クリアカード（コース名・「クリア！」・スタンプ・ボタン）
## ポーズ中も動く（クリアカードのボタンを押せるように）。

signal clear_button_pressed(index: int)
## スマホ：ハテナの吹き出しをタップした（監督が Enter・スペースと同じ早送りにする）
signal bubble_tapped
## スマホ：「スキップ ▶」を押した（監督が Enter と同じくゴーストの演出を飛ばす）
signal touch_skip_pressed

const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const TouchHud = preload("res://scripts/ui/touch_hud/touch_hud.gd")
## ゲームの HUD（5）とゴーストの HUD（12）より上、ポーズ画面と画面の切り替え（100）より下
const LAYER := 20
const TEXT := Color(0.96, 0.97, 1.0)
const INK := Color(0.10, 0.13, 0.20)
const MUTED := Color(0.66, 0.72, 0.82)
const ACCENT := Color("#ffd94a")
const DONE := Color("#5fe08a")
const PANEL := Color(0.06, 0.11, 0.19, 0.86)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.14)
const STAMP_RED := Color("#e5483d")
## カウントダウンの「スタート！」：出てから止まっている秒、上へ抜けて消える秒と高さ（px）
const LAST_COUNT_HOLD := 0.3
const LAST_COUNT_OUT := 0.25
const LAST_COUNT_RISE := 140.0
const BUBBLE_FONT_SIZE := 30
const BUBBLE_TAIL := Vector2(26.0, 18.0)
## 吹き出しを画面の端から離す幅と、上に空けておく幅（コース名の下）
const EDGE_MARGIN := 16.0
const TOP_RESERVED := 84.0

## 吹き出しを付ける画面位置を返す（Vector2。Vector2.INF ならコース名の下に出す）。
var anchor_provider: Callable

var _root: Control = null
var _header: PanelContainer = null
var _title: Label = null
var _dots: HBoxContainer = null
var _dot_count := 0
var _progress := 0
var _bubble: PanelContainer = null
var _bubble_label: Label = null
var _bubble_tail: Polygon2D = null
var _bubble_tween: Tween = null
## スマホ：演出を飛ばせる間だけ右下に出す「スキップ ▶」
var _touch_skip: Button = null
var _sign: PanelContainer = null
var _sign_label: Label = null
var _checks: HBoxContainer = null
## key → {card: PanelContainer, mark: Label, glyph: Label, done: bool}
var _check_cards := {}
var _blink_tween: Tween = null
var _rewind: Control = null
var _round: PanelContainer = null
var _round_label: Label = null
var _countdown: Label = null
var _countdown_tween: Tween = null
var _clear: Control = null
var _clear_buttons: Array[Button] = []


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.name = "PracticeOverlayRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_top()
	_build_bottom()
	_build_countdown()
	_build_bubble()
	_build_rewind()
	_build_touch_controls()


# ---------- スマホ（タッチ操作） ----------

## スマホだけ：吹き出しのタップで早送り、演出を飛ばせる間の「スキップ ▶」ボタン。
func _build_touch_controls() -> void:
	if not MobileUi.is_touch_ui():
		return
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	_bubble.gui_input.connect(func(event: InputEvent) -> void:
		# タッチはマウスのクリックとしても届くので、クリックだけを見る（1回のタップで2つ進まないように）。
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			bubble_tapped.emit()
	)
	_touch_skip = TouchHud.make_button("スキップ ▶", 22)
	_touch_skip.name = "TouchSkipButton"
	_touch_skip.visible = false
	_touch_skip.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_touch_skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_touch_skip.grow_vertical = Control.GROW_DIRECTION_BOTH
	_touch_skip.pressed.connect(func() -> void: touch_skip_pressed.emit())
	_root.add_child(_touch_skip)
	TouchHud.on_safe_area_changed(_layout_touch_skip)
	_layout_touch_skip()


func _layout_touch_skip() -> void:
	if _touch_skip == null:
		return
	_touch_skip.offset_right = -EDGE_MARGIN - TouchHud.safe_right()
	_touch_skip.offset_left = _touch_skip.offset_right
	_touch_skip.offset_top = 0.0
	_touch_skip.offset_bottom = 0.0


## スマホ：「スキップ ▶」を出す・隠す（デスクトップでは何もしない）。
func set_touch_skip_visible(on: bool) -> void:
	if _touch_skip == null:
		return
	# 画面のタッチ操作の層が同じ「スキップ」（Enter）を出しているときは重ねない（同じフレームに両方は出さない）。
	on = TouchHud.own_button_allowed(_touch_skip, "ConfirmButton", on)
	if _touch_skip.visible != on:
		_touch_skip.visible = on


# ---------- 上の真ん中：コース名と進み具合 ----------

func _build_top() -> void:
	var column := _full_column(BoxContainer.ALIGNMENT_BEGIN, 14.0)
	var panel := _panel(PANEL, 14, Vector4(22, 8, 22, 10))
	panel.name = "CourseHeader"
	_header = panel
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_title = _label("", 20, TEXT)
	box.add_child(_title)
	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.add_theme_constant_override("separation", 8)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_dots)
	# しあげの表示（台本①の 1.7）。コース名の下に小さく
	_round = _panel(Color(0.05, 0.09, 0.16, 0.9), 12, Vector4(20, 4, 20, 6))
	_round.name = "RoundLabel"
	(_round.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(ACCENT, 0.8)
	(_round.get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(2)
	_round.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_round_label = _label("", 24, ACCENT)
	_round.add_child(_round_label)
	_round.visible = false
	column.add_child(_round)


## コース名と、進み具合の点の数（台本のレッスンの数）。
func set_course(title: String, dots: int) -> void:
	_title.text = title
	_dot_count = maxi(dots, 0)
	for child: Node in _dots.get_children():
		child.queue_free()
	for i in range(_dot_count):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dots.add_child(dot)
	set_progress(_progress)


## いまのレッスンの番号（0 から）。それより前は済み（●）、それより後は まだ（○）。dots 以上で全部済み。
func set_progress(index: int) -> void:
	_progress = index
	var i := 0
	for dot: Node in _dots.get_children():
		if dot.is_queued_for_deletion():
			continue
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(7)
		if i < index:
			style.bg_color = TEXT
		elif i == index:
			style.bg_color = ACCENT
			style.border_color = Color(1, 1, 1, 0.9)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(1, 1, 1, 0.0)
			style.border_color = Color(1, 1, 1, 0.55)
			style.set_border_width_all(2)
		(dot as Panel).add_theme_stylebox_override("panel", style)
		i += 1


func course_title() -> String:
	return _title.text


## 上のコース名と進み具合を出す・隠す（本物のリザルトのカードの見出しに重ならないように）。
func set_header_visible(on: bool) -> void:
	if _header != null and _header.visible != on:
		_header.visible = on


func header_visible() -> bool:
	return _header != null and _header.visible


func dot_count() -> int:
	return _dot_count


func progress_index() -> int:
	return _progress


## しあげの表示（例「しあげ 1/3」）。"" で隠す。数が変わるときは、ぽんと大きくなる。
func set_round_label(text: String) -> void:
	var changed := text != _round_label.text
	_round_label.text = text
	_round.visible = not text.is_empty()
	if changed and _round.visible:
		_round.pivot_offset = _round.get_combined_minimum_size() * 0.5
		_round.scale = Vector2(1.25, 1.25)
		create_tween().tween_property(_round, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func round_label() -> String:
	return _round_label.text if _round.visible else ""


# ---------- カウントダウン ----------

func _build_countdown() -> void:
	_countdown = _label("", 150, TEXT)
	_countdown.name = "Countdown"
	_countdown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown.offset_bottom = -90.0
	_countdown.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.12, 0.95))
	_countdown.add_theme_constant_override("outline_size", 22)
	_countdown.visible = false
	_root.add_child(_countdown)


## カウントダウンの1つ（「3」など）を真ん中に出す。last（「スタート！」）は色を変えて、すぐ上へ抜けて消える
## （同じ時に最初の壁が来るので、ドアと問題文に長くかぶらないように。0.55 秒で消える）。
## 時間と音は監督が決める（ポーズで止まるように）。"" で隠す。
func show_countdown(text: String, last := false) -> void:
	if _countdown_tween != null:
		_countdown_tween.kill()
		_countdown_tween = null
	_countdown.position.y = 0.0
	_countdown.text = text
	_countdown.visible = not text.is_empty()
	if text.is_empty():
		return
	_countdown.add_theme_color_override("font_color", ACCENT if last else TEXT)
	_countdown.add_theme_font_size_override("font_size", 104 if last else 150)
	_countdown.pivot_offset = _root.size * 0.5 - Vector2(0.0, 45.0)
	_countdown.scale = Vector2(1.6, 1.6)
	_countdown.modulate.a = 0.0
	_countdown_tween = create_tween().set_parallel(true)
	_countdown_tween.tween_property(_countdown, "scale", Vector2.ONE, 0.18 if last else 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_countdown_tween.tween_property(_countdown, "modulate:a", 1.0, 0.1)
	if last:
		_countdown_tween.chain().tween_property(_countdown, "modulate:a", 0.0, LAST_COUNT_OUT).set_delay(LAST_COUNT_HOLD)
		_countdown_tween.tween_property(_countdown, "position:y", -LAST_COUNT_RISE, LAST_COUNT_OUT).set_delay(LAST_COUNT_HOLD) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_countdown_tween.chain().tween_callback(func() -> void:
			_countdown.visible = false
			_countdown.position.y = 0.0)


func countdown_text() -> String:
	return _countdown.text if _countdown.visible else ""


# ---------- 吹き出し ----------

func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.name = "HatenaBubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.97)
	style.set_corner_radius_all(22)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	style.shadow_color = Color(0.0, 0.03, 0.1, 0.35)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	_bubble.add_theme_stylebox_override("panel", style)
	_bubble_label = _label("", BUBBLE_FONT_SIZE, INK)
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bubble.add_child(_bubble_label)
	_bubble_tail = Polygon2D.new()
	_bubble_tail.color = Color(1, 1, 1, 0.97)
	_bubble_tail.polygon = PackedVector2Array([
		Vector2(-BUBBLE_TAIL.x * 0.5, 0.0), Vector2(BUBBLE_TAIL.x * 0.5, 0.0), Vector2(0.0, BUBBLE_TAIL.y)])
	_bubble.add_child(_bubble_tail)
	_bubble.visible = false
	_root.add_child(_bubble)


## 吹き出しを出す（1行）。出るときに、ぽこっと大きくなる。
func show_bubble(text: String) -> void:
	_bubble_label.text = text
	_bubble.reset_size()
	_bubble.visible = true
	# クリアカードなど、あとから足した表示より上に出す
	_root.move_child(_bubble, _root.get_child_count() - 1)
	_place_bubble()
	if _bubble_tween != null:
		_bubble_tween.kill()
	_bubble.scale = Vector2(0.72, 0.72)
	_bubble.modulate.a = 0.0
	_bubble_tween = create_tween().set_parallel(true)
	_bubble_tween.tween_property(_bubble, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_property(_bubble, "modulate:a", 1.0, 0.1)


func hide_bubble() -> void:
	if _bubble_tween != null:
		_bubble_tween.kill()
		_bubble_tween = null
	_bubble.visible = false
	_bubble_label.text = ""


## いま出している吹き出しの文字（出していなければ ""）。
func bubble_text() -> String:
	return _bubble_label.text if _bubble.visible else ""


## 吹き出しの位置：しっぽの先をハテナの頭の上に合わせ、画面からはみ出す分は端で止める。
func _place_bubble() -> void:
	var view := _root.size
	var bubble_size := _bubble.get_combined_minimum_size()
	_bubble.size = bubble_size
	var anchor: Vector2 = anchor_provider.call() if anchor_provider.is_valid() else Vector2.INF
	var has_anchor := anchor.is_finite()
	if not has_anchor:
		anchor = Vector2(view.x * 0.5, TOP_RESERVED + bubble_size.y + BUBBLE_TAIL.y)
	var pos := anchor - Vector2(bubble_size.x * 0.5, bubble_size.y + BUBBLE_TAIL.y)
	# スマホはカメラの穴と角丸（SafeArea）の内側で止める。デスクトップは 0。
	var touch := MobileUi.is_touch_ui()
	var min_x := EDGE_MARGIN + (TouchHud.safe_left() if touch else 0.0)
	var max_x := view.x - bubble_size.x - EDGE_MARGIN - (TouchHud.safe_right() if touch else 0.0)
	var min_y := TOP_RESERVED + (TouchHud.safe_top() if touch else 0.0)
	var max_y := view.y - bubble_size.y - BUBBLE_TAIL.y - EDGE_MARGIN - (TouchHud.safe_bottom() if touch else 0.0)
	pos.x = clampf(pos.x, min_x, maxf(min_x, max_x))
	pos.y = clampf(pos.y, min_y, maxf(min_y, max_y))
	_bubble.position = pos
	_bubble.pivot_offset = Vector2(bubble_size.x * 0.5, bubble_size.y)
	# しっぽは、止めた吹き出しの中でもハテナのほうへ寄せる
	var tail_x := clampf(anchor.x - pos.x, 28.0, bubble_size.x - 28.0)
	_bubble_tail.position = Vector2(tail_x, bubble_size.y - 1.0)
	_bubble_tail.visible = has_anchor


func _process(_delta: float) -> void:
	if _bubble != null and _bubble.visible:
		_place_bubble()


# ---------- 画面の下：看板の文字とチェックのカード ----------

func _build_bottom() -> void:
	var column := _full_column(BoxContainer.ALIGNMENT_END, 18.0)
	column.add_theme_constant_override("separation", 10)
	_sign = _panel(Color(0.05, 0.09, 0.16, 0.9), 14, Vector4(26, 8, 26, 10))
	_sign.name = "Sign"
	(_sign.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(ACCENT, 0.8)
	(_sign.get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(2)
	_sign.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sign_label = _label("", 26, TEXT)
	_sign.add_child(_sign_label)
	_sign.visible = false
	column.add_child(_sign)
	_checks = HBoxContainer.new()
	_checks.name = "Checks"
	_checks.alignment = BoxContainer.ALIGNMENT_CENTER
	_checks.add_theme_constant_override("separation", 18)
	_checks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_checks.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_checks)


## 看板の文字（看板の壁ができるまでの代わり）。"" で隠す。「／」は2行にする。
func set_sign(text: String) -> void:
	_sign_label.text = text.replace("／", "\n")
	_sign.visible = not text.is_empty()


func sign_text() -> String:
	return _sign_label.text if _sign.visible else ""


## チェックのカードを並べ直す。cards は [{key, glyph, sub}]（例 {key = &"left", glyph = "←", sub = "A"}）。
func show_checks(cards: Array) -> void:
	hide_checks()
	for entry: Dictionary in cards:
		var card := _panel(PANEL, 14, Vector4(16, 4, 16, 6))
		card.custom_minimum_size = Vector2(112, 0)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(box)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var glyph := _label(str(entry.get("glyph", "")), 48, TEXT)
		row.add_child(glyph)
		var mark := _label("✓", 36, DONE)
		mark.modulate.a = 0.0
		row.add_child(mark)
		box.add_child(_label(str(entry.get("sub", "")), 18, MUTED))
		_checks.add_child(card)
		_check_cards[StringName(entry.get("key", ""))] = {"card": card, "mark": mark, "glyph": glyph, "done": false}


## key のカードに ✓ を付ける（ピコン）。
func tick_check(key: StringName) -> void:
	var entry: Dictionary = _check_cards.get(key, {})
	if entry.is_empty() or entry.done:
		return
	entry.done = true
	var card := entry.card as PanelContainer
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = DONE
	style.set_border_width_all(3)
	(entry.glyph as Label).add_theme_color_override("font_color", DONE)
	var mark := entry.mark as Label
	mark.pivot_offset = mark.size * 0.5
	mark.scale = Vector2(1.6, 1.6)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(mark, "modulate:a", 1.0, 0.12)
	tween.tween_property(mark, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card.modulate = Color(1, 1, 1, 1)
	AudioManager.play_sfx(&"practice_tick")  # 「ピコン」


func is_check_done(key: StringName) -> bool:
	return bool((_check_cards.get(key, {}) as Dictionary).get("done", false))


func check_keys() -> Array:
	return _check_cards.keys()


## まだ ✓ のないカードを点滅させる（「キーを おして みて」のとき）。
func blink_checks() -> void:
	if _blink_tween != null:
		_blink_tween.kill()
	var targets: Array[Control] = []
	for entry: Dictionary in _check_cards.values():
		if not entry.done:
			targets.append(entry.card as Control)
	if targets.is_empty():
		return
	_blink_tween = create_tween()
	for i in range(3):
		for card: Control in targets:
			_blink_tween.parallel().tween_property(card, "modulate:a", 0.35, 0.16)
		_blink_tween.tween_interval(0.01)
		for card: Control in targets:
			_blink_tween.parallel().tween_property(card, "modulate:a", 1.0, 0.16)
		_blink_tween.tween_interval(0.01)


func hide_checks() -> void:
	if _blink_tween != null:
		_blink_tween.kill()
		_blink_tween = null
	for child: Node in _checks.get_children():
		_checks.remove_child(child)
		child.queue_free()
	_check_cards.clear()


## レッスンが変わるときの片付け（看板・チェック・吹き出し・しあげの表示・カウントダウン）。
func clear_lesson() -> void:
	set_sign("")
	hide_checks()
	hide_bubble()
	set_round_label("")
	show_countdown("")


# ---------- まきもどし ----------

func _build_rewind() -> void:
	_rewind = Control.new()
	_rewind.name = "Rewind"
	_rewind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rewind.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rewind.visible = false
	_root.add_child(_rewind)
	var wash := ColorRect.new()
	wash.name = "Wash"
	wash.color = Color(0.86, 0.9, 1.0, 0.38)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rewind.add_child(wash)
	for i in range(5):
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.55)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		line.custom_minimum_size = Vector2(0, 5)
		_rewind.add_child(line)


## まきもどしの画面効果（台本①の 1.6：色がうすくなり、横線が流れる）と音（テープを巻き戻す「キュルルル」。0.6 秒）。
func play_rewind(seconds: float) -> void:
	_rewind.visible = true
	_rewind.modulate.a = 1.0
	AudioManager.play_sfx(&"practice_rewind")
	var height := _root.size.y
	var tween := create_tween().set_parallel(true)
	var index := 0
	for child: Node in _rewind.get_children():
		if child.name == "Wash":
			continue
		var line := child as Control
		var start := height * (0.12 + 0.19 * index)
		line.position.y = start
		tween.tween_property(line, "position:y", start - height * 0.35, seconds)
		index += 1
	tween.tween_property(_rewind, "modulate:a", 0.0, seconds * 0.4).set_delay(seconds * 0.6)
	tween.chain().tween_callback(func() -> void: _rewind.visible = false)


# ---------- クリアカード ----------

## クリアカードを出す。lines は上から（例 ["① はじめの いっぽ", "クリア！"]）、stamp_label はスタンプの中の文字、
## buttons はボタンの文字（左から）、focus_index は最初に選んでおくボタン。押すと clear_button_pressed(番号)。
func show_clear_card(lines: PackedStringArray, stamp_label: String, star: bool, buttons: PackedStringArray, focus_index: int) -> void:
	hide_clear_card()
	_clear = Control.new()
	_clear.name = "ClearCard"
	_clear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clear.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_clear)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.06, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clear.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear.add_child(center)
	var card := _panel(Color(0.07, 0.13, 0.22, 0.97), 18, Vector4(44, 26, 44, 28))
	(card.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(ACCENT, 0.7)
	(card.get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(2)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	for i in range(lines.size()):
		var is_last := i == lines.size() - 1 and lines.size() > 1
		column.add_child(_label(lines[i], 60 if is_last else 26, TEXT if is_last else ACCENT))
	var stamp := make_stamp(stamp_label, star, 132.0)
	stamp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(stamp)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)
	_clear_buttons.clear()
	for i in range(buttons.size()):
		var button := MenuMetalButton.new()
		button.compact = not MobileUi.is_touch_ui()
		button.text = buttons[i]
		button.custom_minimum_size = Vector2(240, MobileUi.touch(56))
		button.add_theme_font_size_override("font_size", MobileUi.font(20))
		button.pressed.connect(_on_clear_button.bind(i))
		row.add_child(button)
		_clear_buttons.append(button)
	if _clear_buttons.size() > 1:
		for i in range(_clear_buttons.size()):
			var left := _clear_buttons[wrapi(i - 1, 0, _clear_buttons.size())]
			var right := _clear_buttons[wrapi(i + 1, 0, _clear_buttons.size())]
			_clear_buttons[i].focus_neighbor_left = _clear_buttons[i].get_path_to(left)
			_clear_buttons[i].focus_neighbor_right = _clear_buttons[i].get_path_to(right)
	# カードがふわっと出て、スタンプがポンと押される
	card.modulate.a = 0.0
	stamp.modulate.a = 0.0
	stamp.scale = Vector2(2.1, 2.1)
	stamp.rotation = -0.5
	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.25)
	tween.tween_callback(func() -> void:
		stamp.pivot_offset = stamp.size * 0.5
		AudioManager.play_sfx(&"practice_stamp"))  # スタンプの「ポン」
	tween.tween_property(stamp, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(stamp, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(stamp, "rotation", -0.18, 0.26)
	if not _clear_buttons.is_empty():
		var focus_button := _clear_buttons[clampi(focus_index, 0, _clear_buttons.size() - 1)]
		# スマホはフォーカスを置かない（ジャンプのボタンが流し込む Space で押されないように）。
		if not MobileUi.is_touch_ui():
			focus_button.grab_focus.call_deferred()


func hide_clear_card() -> void:
	if _clear != null:
		_clear.queue_free()
		_clear = null
	_clear_buttons.clear()


func clear_card_visible() -> bool:
	return _clear != null and _clear.visible


func clear_buttons() -> Array[Button]:
	return _clear_buttons


## 押したあと止めたボタンを、また押せるようにする（メニューへ戻れなかったとき）。
func enable_clear_buttons() -> void:
	for button: Button in _clear_buttons:
		button.disabled = false


func _on_clear_button(index: int) -> void:
	for button: Button in _clear_buttons:
		button.disabled = true
	clear_button_pressed.emit(index)


# ---------- 部品 ----------

## スタンプ（赤い丸の中に文字。star なら上に★）。stamped = false なら、うすい空の枠。コース選択でも使う。
static func make_stamp(label_text: String, star: bool, diameter: float, stamped := true) -> Control:
	var stamp := Stamp.new()
	stamp.label_text = label_text
	stamp.star = star
	stamp.stamped = stamped
	stamp.custom_minimum_size = Vector2(diameter, diameter)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return stamp


class Stamp extends Control:
	var label_text := ""
	var star := false
	var stamped := true

	func _draw() -> void:
		var radius := minf(size.x, size.y) * 0.5
		var center := size * 0.5
		var color := STAMP_RED if stamped else Color(1, 1, 1, 0.22)
		var ring := maxf(3.0, radius * 0.09)
		if stamped:
			draw_circle(center, radius - ring * 0.5, Color(STAMP_RED, 0.12))
		draw_arc(center, radius - ring * 0.5, 0.0, TAU, 64, color, ring, true)
		draw_arc(center, radius - ring * 2.2, 0.0, TAU, 64, Color(color, color.a * 0.6), maxf(1.5, ring * 0.35), true)
		var font_size := int(radius * (0.95 if label_text.length() <= 1 else 0.6))
		var text_size := FONT.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := center.y + (FONT.get_ascent(font_size) - FONT.get_descent(font_size)) * 0.5
		draw_string(FONT, Vector2(center.x - text_size.x * 0.5, baseline + (radius * 0.08 if star else 0.0)),
			label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		if star and stamped:
			var star_size := int(radius * 0.5)
			var star_width := FONT.get_string_size("★", HORIZONTAL_ALIGNMENT_LEFT, -1, star_size).x
			draw_string(FONT, Vector2(center.x - star_width * 0.5, center.y - radius * 0.38), "★",
				HORIZONTAL_ALIGNMENT_LEFT, -1, star_size, ACCENT)


## 画面いっぱいの縦の並び（子は真ん中に寄せる）。margin は上か下の余白。
func _full_column(alignment: BoxContainer.AlignmentMode, margin: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = alignment
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# スマホは上下の SafeArea（角丸）の分も空ける。デスクトップは 0。
	var touch := MobileUi.is_touch_ui()
	if alignment == BoxContainer.ALIGNMENT_BEGIN:
		column.offset_top = margin + (TouchHud.safe_top() if touch else 0.0)
	else:
		column.offset_bottom = -margin - (TouchHud.safe_bottom() if touch else 0.0)
	_root.add_child(column)
	return column


## 角丸のパネル。margins は (左, 上, 右, 下)。
static func _panel(color: Color, radius: int, margins: Vector4) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = PANEL_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	panel.add_theme_stylebox_override("panel", style)
	return panel


static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	# スマホでは小さい文字だけ読める大きさへ（大きい見出しと吹き出しはそのまま）。
	label.add_theme_font_size_override("font_size", MobileUi.font(font_size) if font_size <= 24 else font_size)
	label.add_theme_color_override("font_color", color)
	return label
