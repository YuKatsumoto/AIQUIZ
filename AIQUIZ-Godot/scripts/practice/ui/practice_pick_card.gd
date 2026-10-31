class_name PracticePickCard
extends CanvasLayer

## 相手を選ぶカード（docs/new_tutorial/phase6_design.md 3.2、台本③の 3-0）。ゲーム画面の上に重ねる。監督（コース③）が作って子にする。
## 「誰と練習する？」と［2人で］［CPUと］。矢印キーと Enter・マウスで選ぶ。Esc は［CPUと］。
## ［2人で］を選ぶと「P2は右Ctrlで参加」を出して待つ（Esc か「← 戻る」で選び直し）。右の Ctrl（テンキーの 0 でもよい）が
## 押されたら p2_joined を出し、「P2が参加」を見せてから閉じて chosen(false)。［CPUと］はすぐ閉じて chosen(true)。
## 木に入ると開く（open_on_ready）。閉じたあとは隠れるだけなので、要らなくなったら呼んだ側が queue_free する。
## 見た目はコース選択（PracticeCourseSelect）のカードと、クリアカード（PracticeOverlay）の板にそろえる。
## ポーズ中も動く。

## 選んだ（［2人で］は P2 が参加して「P2が参加」を見せ終わったとき）
signal chosen(with_cpu: bool)
## P2 が右の Ctrl を押して参加した（「P2が参加」を出した時）
signal p2_joined

enum Mode { CLOSED, PICK, JOIN, JOINED }

const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
const TouchHud = preload("res://scripts/ui/touch_hud/touch_hud.gd")
## 練習のオーバーレイ（20）より上、ポーズ画面と画面の切り替え（100）より下
const LAYER := 22
const TEXT := Color(0.95, 0.97, 1.0)
const MUTED := Color(0.64, 0.70, 0.80)
const ACCENT := Color("#ffd94a")
const DONE := Color("#5fe08a")
const PANEL_FACE := Color(0.07, 0.13, 0.22, 0.97)
const CARD_FACE := Color(0.10, 0.17, 0.27, 0.98)
const CARD_HOVER := Color(0.14, 0.23, 0.36, 0.98)
const CARD_SIZE := Vector2(270, 236)
## 2人の色（画面の下のカードと同じ：P1 はだいだい、P2 は青）
const P1_COLOR := Color(0.95, 0.55, 0.20)
const P2_COLOR := Color(0.20, 0.65, 0.90)
const FADE_SECONDS := 0.2
## 「P2が参加」を見せておく秒
const JOINED_SECONDS := 0.9

## 木に入ったら開く
var open_on_ready := true

var _mode := Mode.CLOSED
var _root: Control = null
var _sheet: PanelContainer = null
var _heading: Label = null
var _cards_row: HBoxContainer = null
var _pair: Button = null
var _cpu: Button = null
var _join_box: VBoxContainer = null
var _join_key: KeyCapIcon = null
var _join_label: Label = null
var _back: Button = null
var _tween: Tween = null
var _pulse: Tween = null


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build()
	if open_on_ready:
		open()


func is_open() -> bool:
	return _mode != Mode.CLOSED


## &"pick"（選ぶ）・&"join"（P2 を待つ）・&"joined"（「P2が参加」）・&"closed"
func mode() -> StringName:
	return [&"closed", &"pick", &"join", &"joined"][_mode]


## ボタン（テスト用）：0 = 2人で、1 = CPUと、2 = 「← 戻る」（P2 を待つとき）
func button(index: int) -> Button:
	return [_pair, _cpu, _back][clampi(index, 0, 2)]


## 開く（選ぶ所から）。［CPUと］を選んでおく。
func open() -> void:
	if _root == null:
		return
	_root.visible = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_show_pick()
	if _tween != null:
		_tween.kill()
	_root.modulate.a = 0.0
	_sheet.pivot_offset = _sheet.size * 0.5
	_sheet.scale = Vector2(0.92, 0.92)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_SECONDS)
	_tween.tween_property(_sheet, "scale", Vector2.ONE, FADE_SECONDS * 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _input(event: InputEvent) -> void:
	if _mode == Mode.CLOSED or _mode == Mode.JOINED:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _mode == Mode.PICK:
			_choose_cpu()
		else:
			_show_pick()
		return
	if _mode == Mode.JOIN and _is_p2_join_key(key):
		get_viewport().set_input_as_handled()
		_on_p2_joined()


## 右の Ctrl（左の Ctrl は P1 の手の届く所なので受けない）か、テンキーの 0。
static func _is_p2_join_key(key: InputEventKey) -> bool:
	if (key.keycode == KEY_CTRL or key.physical_keycode == KEY_CTRL) and key.location == KEY_LOCATION_RIGHT:
		return true
	return key.keycode == KEY_KP_0 or key.physical_keycode == KEY_KP_0


func _show_pick() -> void:
	_mode = Mode.PICK
	_stop_pulse()
	_heading.text = PracticeTexts.get_text("c3.pick.card")
	_heading.visible = true
	_cards_row.visible = true
	_join_box.visible = false
	_pair.disabled = false
	_cpu.disabled = false
	# スマホはフォーカスを置かない（ジャンプのボタンが流し込む Space で選ばれないように）。
	if not MobileUi.is_touch_ui():
		_cpu.grab_focus.call_deferred()


func _choose_pair() -> void:
	if _mode != Mode.PICK:
		return
	_mode = Mode.JOIN
	_heading.visible = false
	_cards_row.visible = false
	_join_box.visible = true
	if _join_key != null:
		_join_key.done = false
		_join_key.queue_redraw()
	_join_label.text = PracticeTexts.get_text("c3.pick.join")
	_join_label.add_theme_color_override("font_color", TEXT)
	_back.visible = true
	_back.disabled = false
	if not MobileUi.is_touch_ui():
		_back.grab_focus.call_deferred()
	# 右 Ctrl のキーを P2 の色でゆっくり光らせる（押してほしいキー）
	_stop_pulse()
	if _join_key == null:
		AudioManager.play_sfx(&"ui_click")
		return
	_join_key.glow = 0.0
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_join_key, "glow", 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(_join_key, "glow", 0.0, 0.55).set_trans(Tween.TRANS_SINE)
	AudioManager.play_sfx(&"ui_click")


func _choose_cpu() -> void:
	if _mode != Mode.PICK:
		return
	AudioManager.play_sfx(&"ui_click")
	_close()
	chosen.emit(true)


func _on_p2_joined() -> void:
	_mode = Mode.JOINED
	_stop_pulse()
	if _join_key != null:
		_join_key.done = true
		_join_key.glow = 1.0
		_join_key.queue_redraw()
	_join_label.text = PracticeTexts.get_text("c3.pick.joined")
	_join_label.add_theme_color_override("font_color", DONE)
	_back.visible = false
	# 「P2が参加」がぽんと出る
	_join_box.pivot_offset = _join_box.size * 0.5
	_join_box.scale = Vector2(1.08, 1.08)
	var pop := create_tween()
	pop.tween_property(_join_box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx(&"ui_start")
	p2_joined.emit()
	var timer := get_tree().create_timer(JOINED_SECONDS, true)
	await timer.timeout
	if _mode != Mode.JOINED:
		return
	_close()
	chosen.emit(false)


func _close() -> void:
	_mode = Mode.CLOSED
	_stop_pulse()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pair.disabled = true
	_cpu.disabled = true
	_back.disabled = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(func() -> void:
		if _mode == Mode.CLOSED:
			_root.visible = false)


func _stop_pulse() -> void:
	if _pulse != null:
		_pulse.kill()
		_pulse = null


# ---------- 作る ----------

func _build() -> void:
	_root = Control.new()
	_root.name = "PracticePickCardRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.06, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	var style := _box(PANEL_FACE, Color(ACCENT, 0.7), 2, 18, Vector4(40, 28, 40, 30))
	style.shadow_color = Color(0.0, 0.02, 0.06, 0.45)
	style.shadow_size = 14
	_sheet.add_theme_stylebox_override("panel", style)
	center.add_child(_sheet)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	_sheet.add_child(column)
	_heading = _label("", 32, ACCENT)
	column.add_child(_heading)
	_cards_row = HBoxContainer.new()
	_cards_row.name = "Choices"
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", 24)
	column.add_child(_cards_row)
	var labels := PracticeTexts.get_parts("c3.pick.buttons")
	_pair = _choice_card(labels[0], false)
	_pair.name = "PairBtn"
	_pair.pressed.connect(_choose_pair)
	_cards_row.add_child(_pair)
	_cpu = _choice_card(labels[1] if labels.size() > 1 else "", true)
	_cpu.name = "CpuBtn"
	_cpu.pressed.connect(_choose_cpu)
	_cards_row.add_child(_cpu)
	for pair: Array in [[_pair, _cpu], [_cpu, _pair]]:
		var from: Button = pair[0]
		var to: Button = pair[1]
		from.focus_neighbor_left = from.get_path_to(to)
		from.focus_neighbor_right = from.get_path_to(to)
		from.focus_neighbor_top = from.get_path_to(from)
		from.focus_neighbor_bottom = from.get_path_to(from)
	_build_join(column)


## P2 を待つ所：右 Ctrl のキーと、P2 の人の絵、「P2は右Ctrlで参加」と「← 戻る」。
func _build_join(column: VBoxContainer) -> void:
	_join_box = VBoxContainer.new()
	_join_box.name = "Join"
	_join_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_box.add_theme_constant_override("separation", 18)
	_join_box.visible = false
	column.add_child(_join_box)
	var art := HBoxContainer.new()
	art.alignment = BoxContainer.ALIGNMENT_CENTER
	art.add_theme_constant_override("separation", 28)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_join_box.add_child(art)
	var figure := PlayersIcon.new()
	figure.players = [2]
	figure.custom_minimum_size = Vector2(110, 150)
	art.add_child(figure)
	if TouchHud.is_touch():
		# スマホ：右Ctrl のキーの絵の代わりに、押すと右Ctrl を流し込む「P2 参加」ボタン（キーと同じ道で参加する）。
		var join_button := TouchHud.make_button("P2 参加", 30, P2_COLOR)
		join_button.name = "P2JoinButton"
		join_button.custom_minimum_size = Vector2(240, 120)
		join_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		join_button.pressed.connect(func() -> void:
			if _mode == Mode.JOIN:
				TouchHud.tap_key(KEY_CTRL, KEY_LOCATION_RIGHT))
		art.add_child(join_button)
	else:
		_join_key = KeyCapIcon.new()
		_join_key.custom_minimum_size = Vector2(200, 150)
		art.add_child(_join_key)
	_join_label = _label("", 30, TEXT)
	_join_box.add_child(_join_label)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_box.add_child(footer)
	_back = MenuMetalButton.new()
	_back.name = "BackBtn"
	_back.compact = true
	_back.text = PracticeTexts.get_text("select.back")
	_back.custom_minimum_size = Vector2(200, MobileUi.touch(50))
	_back.add_theme_font_size_override("font_size", MobileUi.font(18))
	if MobileUi.is_touch_ui():
		_back.compact = false
	_back.pressed.connect(func() -> void:
		if _mode == Mode.JOIN:
			_show_pick())
	footer.add_child(_back)


## 選ぶカード（コース選択のカードと同じ板）：上に2人の絵、下に文字。
func _choice_card(text: String, with_cpu: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _box(CARD_FACE, Color(1, 1, 1, 0.16), 2, 14, Vector4.ZERO))
	button.add_theme_stylebox_override("hover", _box(CARD_HOVER, Color(1, 1, 1, 0.3), 2, 14, Vector4.ZERO))
	button.add_theme_stylebox_override("pressed", _box(CARD_FACE.darkened(0.2), ACCENT, 3, 14, Vector4.ZERO))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), ACCENT, 3, 14, Vector4.ZERO))
	button.add_theme_stylebox_override("disabled", _box(CARD_FACE, Color(1, 1, 1, 0.16), 2, 14, Vector4.ZERO))
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.offset_top = 14
	content.offset_bottom = -16
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 8)
	button.add_child(content)
	var icon := PlayersIcon.new()
	icon.players = [1, 2]
	icon.cpu = with_cpu
	icon.custom_minimum_size = Vector2(0, 150)
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(icon)
	content.add_child(_label(text, 30, TEXT))
	return button


static func _box(face: Color, edge: Color, border: int, radius: int, margins: Vector4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = face
	style.border_color = edge
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	return style


static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## 人の絵：ゲームのキャラクターと同じ四角い体の人を並べる（P1 だいだい・P2 青）。頭の上に「P1」「P2」の札。
## cpu なら P2 の札を「CPU」（ゲームの名札と同じ文字）にする。
class PlayersIcon extends Control:
	var players: Array = [1, 2]
	var cpu := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var count := players.size()
		if count == 0:
			return
		var unit := minf(size.y / 6.2, size.x / (count * 2.6 + 0.4))
		var gap := unit * 2.6
		var left := size.x * 0.5 - gap * (count - 1) * 0.5
		for i: int in range(count):
			var index: int = players[i]
			var color := P1_COLOR if index == 1 else P2_COLOR
			var feet := Vector2(left + gap * i, size.y - unit * 0.25)
			_figure(feet, unit, color, (1.0 if i == 0 else -1.0) * (0.0 if count == 1 else 1.0))
			var tag := "CPU" if cpu and index == 2 else "P%d" % index
			_tag(feet - Vector2(0.0, unit * 5.25), unit, tag, color)

	## 四角い人（足もとが feet）。facing は顔を向ける横の向き（+1 右・−1 左・0 正面）。
	func _figure(feet: Vector2, unit: float, color: Color, facing: float) -> void:
		var dark := color.darkened(0.28)
		var shade := color.darkened(0.12)
		# 足・腕（体のうしろ）・体・頭
		draw_rect(Rect2(feet + Vector2(-unit * 0.55, -unit * 1.6), Vector2(unit * 0.5, unit * 1.6)), dark)
		draw_rect(Rect2(feet + Vector2(unit * 0.05, -unit * 1.6), Vector2(unit * 0.5, unit * 1.6)), dark)
		draw_rect(Rect2(feet + Vector2(-unit * 1.05, -unit * 3.2), Vector2(unit * 0.42, unit * 1.45)), shade)
		draw_rect(Rect2(feet + Vector2(unit * 0.63, -unit * 3.2), Vector2(unit * 0.42, unit * 1.45)), shade)
		draw_rect(Rect2(feet + Vector2(-unit * 0.62, -unit * 3.35), Vector2(unit * 1.24, unit * 1.85)), color)
		var head := Rect2(feet + Vector2(-unit * 0.55, -unit * 4.55), Vector2(unit * 1.1, unit * 1.1))
		draw_rect(head, color.lightened(0.12))
		# 目（向いている側へ寄せる）
		var eye_y := head.position.y + unit * 0.45
		var shift := facing * unit * 0.12
		for side: float in [-1.0, 1.0]:
			draw_rect(Rect2(Vector2(head.get_center().x + side * unit * 0.22 + shift - unit * 0.07, eye_y), Vector2(unit * 0.14, unit * 0.22)),
				Color(0.08, 0.10, 0.16))

	## 頭の上の札（丸い板に白い文字）。bottom は札の下の真ん中。
	func _tag(bottom: Vector2, unit: float, text: String, color: Color) -> void:
		var font_size := int(unit * 0.95)
		var text_size := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var pad := Vector2(unit * 0.32, unit * 0.12)
		var rect := Rect2(bottom - Vector2(text_size.x * 0.5 + pad.x, text_size.y + pad.y * 2.0), Vector2(text_size.x + pad.x * 2.0, text_size.y + pad.y * 2.0))
		var plate := StyleBoxFlat.new()
		plate.bg_color = color.darkened(0.45)
		plate.border_color = color
		plate.set_border_width_all(maxi(2, int(unit * 0.08)))
		plate.set_corner_radius_all(int(rect.size.y * 0.5))
		draw_style_box(plate, rect)
		var baseline := rect.get_center().y + (FONT.get_ascent(font_size) - FONT.get_descent(font_size)) * 0.5
		draw_string(FONT, Vector2(rect.get_center().x - text_size.x * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


## 右 Ctrl のキー：白いキーの面と側面、真ん中に「Ctrl」、下に小さく「右」。glow で P2 の色に光り、done で緑の ✓。
class KeyCapIcon extends Control:
	var glow := 0.0:
		set(value):
			glow = value
			queue_redraw()
	var done := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var key_size := Vector2(minf(size.x * 0.82, 170.0), minf(size.y * 0.62, 96.0))
		var top := Rect2(size * 0.5 - key_size * 0.5 - Vector2(0.0, key_size.y * 0.12), key_size)
		var edge_color := DONE if done else P2_COLOR
		# 光（キーのまわりの P2 の色の輪）
		if glow > 0.0:
			var halo := StyleBoxFlat.new()
			halo.bg_color = Color(edge_color, 0.0)
			halo.border_color = Color(edge_color, 0.25 + 0.55 * glow)
			halo.set_border_width_all(int(4.0 + 6.0 * glow))
			halo.set_corner_radius_all(18)
			draw_style_box(halo, top.grow(10.0 + 4.0 * glow))
		var side := StyleBoxFlat.new()
		side.bg_color = Color(0.58, 0.63, 0.72)
		side.set_corner_radius_all(14)
		draw_style_box(side, Rect2(top.position + Vector2(0.0, key_size.y * 0.14), key_size))
		var face := StyleBoxFlat.new()
		face.bg_color = Color(0.80, 0.97, 0.84) if done else Color(0.97, 0.97, 0.99)
		face.set_corner_radius_all(14)
		draw_style_box(face, top)
		var ink := Color(0.04, 0.10, 0.27)
		var font_size := int(key_size.y * 0.42)
		var text := "Ctrl"
		var text_size := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := top.get_center().y + (FONT.get_ascent(font_size) - FONT.get_descent(font_size)) * 0.5 - key_size.y * 0.04
		draw_string(FONT, Vector2(top.get_center().x - text_size.x * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
		var small := int(key_size.y * 0.22)
		draw_string(FONT, Vector2(top.position.x + key_size.x * 0.1, top.position.y + small + key_size.y * 0.08), "右",
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(ink, 0.7))
		if done:
			var center := top.position + Vector2(key_size.x - 6.0, 6.0)
			draw_circle(center, 22.0, Color.WHITE)
			draw_circle(center, 19.0, DONE.darkened(0.1))
			var check := FONT.get_string_size("✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
			draw_string(FONT, center + Vector2(-check.x * 0.5, 9.0), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
