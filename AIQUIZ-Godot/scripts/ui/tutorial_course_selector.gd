extends Control
class_name TutorialCourseSelector

## チュートリアルの開始画面（V7）。コース選択と操作キーの説明を1画面にまとめる。
## 左でコース（1P / ローカル2P）を選ぶと、右のキーボードと操作の説明がそのコースのキーに切り替わる。
## キーボードは実際の入力だけで光り、自動で動く見本は出さない（res://scripts/ui/tutorial_keyboard.gd）。
## 操作の説明は、キーを横に引き延ばさず、実際の配列どおりの並びと大きさで描く。
## 「はじめる」（Enter）で開始、Esc か「閉じる」で閉じる。練習用のキーではボタンが反応しない。

signal course_selected(course: String)
signal dismissed

const KeyboardScript = preload("res://scripts/ui/tutorial_keyboard.gd")
const DESIGN_SIZE := Vector2(1280, 720)
const SOLO := "SOLO"
const LOCAL_2P := "LOCAL_2P"
const COURSE_TIMES := {SOLO: "約2分", LOCAL_2P: "約4分"}
const SOLO_CHAPTERS: Array[String] = ["move", "wave", "door", "crown"]
const DUO_CHAPTERS: Array[String] = ["move", "wave", "door", "crown", "flag"]
## 練習用のキー。押しても画面のボタンやメニューに届かない。Tab と Enter はボタン操作に残す。
const PRACTICE_KEYS := [
	KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE, KEY_CTRL,
	KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_1, KEY_2, KEY_3,
	KEY_8, KEY_9, KEY_0, KEY_KP_7, KEY_KP_8, KEY_KP_9,
]

var _course: String = SOLO
var _built: bool = false
var _deck: Control
var _cards: Dictionary = {}
var _badges: Dictionary = {}
var _keyboard: Control
var _keys_label: Label
var _legend_root: VBoxContainer
var _legend_cards: Array[Dictionary] = []
var _status: Label
var _start: Button
var _close: Button
var _active_group: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func show_selector() -> void:
	if not _built:
		_build_ui()
	_update_badges()
	_select_course(_course)
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.22)
	_layout()
	_start.grab_focus()


func hide_selector() -> void:
	visible = false


func is_active() -> bool:
	return visible


func get_start_button() -> Button:
	return _start


func get_selected_course() -> String:
	return _course


func _process(delta: float) -> void:
	if not visible:
		return
	_keyboard.advance(delta)
	_update_active_legend()
	_layout()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_dismiss()
		get_viewport().set_input_as_handled()
		return
	# 練習用のキーは、フォーカス中のボタンや下のメニューを動かさない。
	if key.keycode in PRACTICE_KEYS:
		get_viewport().set_input_as_handled()


# ---------- 構築 ----------

func _build_ui() -> void:
	if _built:
		return
	_built = true
	var background := ColorRect.new()
	background.name = "Background"
	background.color = TutorialUiStyle.NAVY
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var glow := TextureRect.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.texture = _glow_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)

	_deck = Control.new()
	_deck.name = "Deck"
	_deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck.size = DESIGN_SIZE
	add_child(_deck)

	var left := VBoxContainer.new()
	left.name = "Courses"
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.position = Vector2(46, 44)
	left.size = Vector2(400, 630)
	left.add_theme_constant_override("separation", 14)
	_deck.add_child(left)
	left.add_child(TutorialUiStyle.make_label("チュートリアル", 34, Color.WHITE))
	var lead := TutorialUiStyle.make_label("遊びながら操作とルールを覚えます", 15, TutorialUiStyle.MUTED, TutorialUiStyle.FONT_MEDIUM)
	left.add_child(lead)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, 6)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(spacer)
	left.add_child(_course_card(SOLO, "1P コース", "res://assets/ui/1p.png", TutorialUiStyle.P1, SOLO_CHAPTERS))
	left.add_child(_course_card(LOCAL_2P, "ローカル2P コース", "res://assets/ui/2p.png", TutorialUiStyle.P2, DUO_CHAPTERS))

	var right := VBoxContainer.new()
	right.name = "Keys"
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.position = Vector2(476, 44)
	right.size = Vector2(758, 640)
	right.add_theme_constant_override("separation", 12)
	_deck.add_child(right)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(top)
	_keys_label = TutorialUiStyle.make_label("", 15, TutorialUiStyle.MUTED)
	_keys_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_keys_label)
	_close = _make_button("Esc  閉じる", false)
	_close.name = "Close"
	_close.custom_minimum_size = Vector2(150, 38)
	_close.pressed.connect(_dismiss)
	top.add_child(_close)

	_keyboard = KeyboardScript.new()
	_keyboard.name = "PhysicalKeyboard"
	_keyboard.show_footnote = false
	_keyboard.show_demo = false
	_keyboard.custom_minimum_size = Vector2(758, 250)
	right.add_child(_keyboard)

	_legend_root = VBoxContainer.new()
	_legend_root.name = "Legend"
	_legend_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend_root.add_theme_constant_override("separation", 8)
	right.add_child(_legend_root)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 12)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(bottom)
	_status = TutorialUiStyle.make_label("", 13, TutorialUiStyle.MUTED, TutorialUiStyle.FONT_MEDIUM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(_status)
	# Enter のキーは「はじめる」の横にそろえて置く。
	var start_row := HBoxContainer.new()
	start_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_row.add_theme_constant_override("separation", 12)
	start_row.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(start_row)
	var enter_chip := TutorialKeyChip.new()
	enter_chip.setup("Enter", TutorialKeyChip.Look.IDLE, TutorialUiStyle.ACCENT, 26.0)
	enter_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start_row.add_child(enter_chip)
	_start = _make_button("はじめる", true)
	_start.name = "StartPractice"
	_start.custom_minimum_size = Vector2(220, 54)
	_start.pressed.connect(_start_course)
	start_row.add_child(_start)


func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(0.13, 0.25, 0.47, 0.55), Color(0.13, 0.25, 0.47, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.72, 0.18)
	texture.fill_to = Vector2(1.25, 0.9)
	texture.width = 128
	texture.height = 72
	return texture


func _make_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", TutorialUiStyle.FONT_BOLD)
	button.add_theme_font_size_override("font_size", 20 if primary else 15)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var bg := TutorialUiStyle.ACCENT if primary else Color(1.0, 1.0, 1.0, 0.05)
		if state == "hover":
			bg = bg.lightened(0.12) if primary else Color(1.0, 1.0, 1.0, 0.1)
		elif state == "pressed":
			bg = bg.darkened(0.12)
		var style := TutorialUiStyle.box(bg, Color.TRANSPARENT if primary else TutorialUiStyle.LINE, 0 if primary else 1, 14, 18.0, 6.0)
		button.add_theme_stylebox_override(state, style)
	var focus := TutorialUiStyle.box(Color.TRANSPARENT, Color.WHITE, 3, 16)
	focus.expand_margin_left = 4
	focus.expand_margin_top = 4
	focus.expand_margin_right = 4
	focus.expand_margin_bottom = 4
	button.add_theme_stylebox_override("focus", focus)
	var ink := Color("2a1d00") if primary else TutorialUiStyle.TEXT
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ink)
	return button


## コースのカード。押すとそのコースを選ぶ（開始は「はじめる」）。
func _course_card(course: String, title: String, icon_path: String, accent: Color, chapters: Array[String]) -> Button:
	var card := Button.new()
	card.name = "Course_%s" % course
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = Vector2(400, 142)
	card.set_meta("accent", accent)
	card.pressed.connect(func() -> void: _select_course(course))
	var focus := TutorialUiStyle.box(Color.TRANSPARENT, Color.WHITE, 3, 18)
	focus.expand_margin_left = 4
	focus.expand_margin_top = 4
	focus.expand_margin_right = 4
	focus.expand_margin_bottom = 4
	card.add_theme_stylebox_override("focus", focus)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.offset_top = 14
	row.offset_bottom = -14
	card.add_child(row)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(104, 0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	column.add_child(TutorialUiStyle.make_label(title, 22, accent))
	var chapter_row := HBoxContainer.new()
	chapter_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chapter_row.add_theme_constant_override("separation", 6)
	column.add_child(chapter_row)
	for glyph: String in chapters:
		chapter_row.add_child(TutorialUiStyle.glyph_disc(glyph, 28.0, Color(1.0, 1.0, 1.0, 0.1), TutorialUiStyle.TEXT))
	# 所要時間と完了の印は同じ行に置く（長い「内容を更新しました」でもカードからはみ出さない）。
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override("separation", 12)
	column.add_child(foot)
	foot.add_child(TutorialUiStyle.make_label(str(COURSE_TIMES.get(course, "")), 13, TutorialUiStyle.MUTED))
	var badge := TutorialUiStyle.make_label("", 12, TutorialUiStyle.MUTED)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(badge)
	_badges[course] = badge
	_cards[course] = card
	return card


# ---------- コースの切り替え ----------

func _select_course(course: String) -> void:
	_course = LOCAL_2P if course == LOCAL_2P else SOLO
	for key: Variant in _cards.keys():
		var card: Button = _cards[key]
		var selected: bool = str(key) == _course
		var accent: Color = card.get_meta("accent", TutorialUiStyle.P1)
		for state: String in ["normal", "hover", "pressed"]:
			var bg := Color(accent, 0.12) if selected else Color(1.0, 1.0, 1.0, 0.04)
			if state == "hover" and not selected:
				bg = Color(1.0, 1.0, 1.0, 0.08)
			card.add_theme_stylebox_override(state, TutorialUiStyle.box(
				bg, accent if selected else Color(1.0, 1.0, 1.0, 0.12), 2, 16
			))
	var duo := _course == LOCAL_2P
	_keys_label.text = "ローカル2P の操作キー（押すと光ります）" if duo else "1P の操作キー（押すと光ります）"
	_status.text = "P2のエモートはテンキー7・8・9でも踊れます" if duo else ""
	_keyboard.configure({
		"step_id": "course_select_" + _course,
		"lesson_kind": "key_map",
		"players": _key_map(duo),
	}, duo)
	_build_legend(duo)
	_active_group = ""


## キーボードを光らせるための操作一覧（実際に読むキー）。
func _key_map(duo: bool) -> Array[Dictionary]:
	var players: Array[Dictionary] = []
	for player: int in ([1, 2] if duo else [1]):
		var p2 := player == 2
		var digits: Array = ["8", "9", "0"] if p2 else ["1", "2", "3"]
		var tasks: Array[Dictionary] = [
			{"id": "left", "key": "←" if p2 else ("A" if duo else "A / ←"), "group": "move"},
			{"id": "right", "key": "→" if p2 else ("D" if duo else "D / →"), "group": "move"},
			{"id": "forward", "key": "↑" if p2 else ("W" if duo else "W / ↑"), "group": "move"},
			{"id": "back", "key": "↓" if p2 else ("S" if duo else "S / ↓"), "group": "move"},
			{"id": "jump", "key": "Ctrl" if p2 else "Space", "group": "jump"},
		]
		for index: int in range(digits.size()):
			tasks.append({"id": "emote_%d" % (index + 1), "key": digits[index], "group": "emote"})
		players.append({"player": player, "tasks": tasks})
	return players


## 操作の説明。キーは実際の配列どおりに並べ、横に引き延ばさない。
func _build_legend(duo: bool) -> void:
	for child: Node in _legend_root.get_children():
		_legend_root.remove_child(child)
		child.queue_free()
	_legend_cards.clear()
	var unit := 24.0 if duo else 28.0
	for player: int in ([1, 2] if duo else [1]):
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		_legend_root.add_child(row)
		if duo:
			var tag := TutorialUiStyle.make_label("P%d" % player, 20, TutorialUiStyle.player_color(player))
			tag.custom_minimum_size = Vector2(34, 0)
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tag)
		for group: Dictionary in _legend_groups(player, duo):
			row.add_child(_legend_card(player, group, unit))


func _legend_groups(player: int, duo: bool) -> Array[Dictionary]:
	var accent := TutorialUiStyle.player_color(player)
	var alt := TutorialUiStyle.P1.lerp(TutorialUiStyle.IVORY, 0.5)
	var wasd := [[{"text": "W", "offset": 1.0}], [{"text": "A"}, {"text": "S"}, {"text": "D"}]]
	var arrows := [[{"text": "↑", "offset": 1.0}], [{"text": "←"}, {"text": "↓"}, {"text": "→"}]]
	var move_clusters: Array = []
	if player == 2:
		move_clusters.append({"rows": arrows, "color": accent})
	else:
		move_clusters.append({"rows": wasd, "color": accent})
		if not duo:
			move_clusters.append({"rows": arrows, "color": alt})
	return [
		{
			"id": "move", "title": "移動", "clusters": move_clusters,
			"caption": "矢印キーでも動ける" if not duo else "前後左右に動く",
		},
		{
			"id": "jump", "title": "ジャンプ",
			"clusters": [{
				"rows": [[{"text": "右Ctrl", "units": 1.6}]] if player == 2 else [[{"text": "Space", "units": 5.0}]],
				"color": accent,
			}],
			"caption": "左のCtrlは使えない" if player == 2 else "エモートも止まる",
		},
		{
			"id": "emote", "title": "エモート",
			"clusters": [{
				"rows": [[{"text": "8"}, {"text": "9"}, {"text": "0"}]] if player == 2 else [[{"text": "1"}, {"text": "2"}, {"text": "3"}]],
				"color": accent,
			}],
			"caption": "相手を煽ろう!!",
		},
	]


func _legend_card(player: int, group: Dictionary, unit: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Legend_P%d_%s" % [player, str(group.get("id", ""))]
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var keys := HBoxContainer.new()
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.add_theme_constant_override("separation", int(unit * 0.55))
	keys.alignment = BoxContainer.ALIGNMENT_BEGIN
	# 2段の配列（WASD・矢印）と1段の配列（Space・数字）の下端をそろえる。
	keys.custom_minimum_size = Vector2(0, unit * 2.0 + unit * 0.12 + unit * 0.14 * 2.0)
	column.add_child(keys)
	for cluster: Dictionary in group.get("clusters", []):
		var drawing := TutorialUiStyle.key_cluster(cluster.get("rows", []), cluster.get("color", TutorialUiStyle.P1), unit)
		drawing.size_flags_vertical = Control.SIZE_SHRINK_END
		keys.add_child(drawing)
	var labels := HBoxContainer.new()
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_theme_constant_override("separation", 10)
	column.add_child(labels)
	var title := TutorialUiStyle.make_label(str(group.get("title", "")), 15, Color.WHITE)
	labels.add_child(title)
	var caption := TutorialUiStyle.make_label(str(group.get("caption", "")), 12, TutorialUiStyle.MUTED, TutorialUiStyle.FONT_MEDIUM)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.add_child(caption)
	_legend_cards.append({"player": player, "id": str(group.get("id", "")), "card": card, "title": title.text, "caption": caption.text})
	_style_legend_card(card, player, false)
	return card


func _style_legend_card(card: PanelContainer, player: int, active: bool) -> void:
	var accent := TutorialUiStyle.player_color(player)
	card.add_theme_stylebox_override("panel", TutorialUiStyle.box(
		Color(accent, 0.12) if active else Color(1.0, 1.0, 1.0, 0.05),
		accent if active else Color.TRANSPARENT,
		2 if active else 0,
		12,
		14.0,
		10.0
	))


## 実際に押されたキーの操作の説明を縁取る。
func _update_active_legend() -> void:
	var state: Dictionary = _keyboard.get_action_state()
	var active := ""
	if bool(state.get("live", false)):
		var task_id := str(state.get("id", ""))
		var group := "move"
		if task_id == "jump":
			group = "jump"
		elif task_id.begins_with("emote"):
			group = "emote"
		elif task_id.is_empty():
			group = ""
		if not group.is_empty():
			active = "P%d:%s" % [int(state.get("player", 1)), group]
	if active == _active_group:
		return
	_active_group = active
	for entry: Dictionary in _legend_cards:
		var key := "P%d:%s" % [int(entry["player"]), str(entry["id"])]
		_style_legend_card(entry["card"], int(entry["player"]), key == active)


func _update_badges() -> void:
	for course: Variant in _badges.keys():
		var badge: Label = _badges[course]
		match GameManager.tutorial_course_badge(str(course)):
			"done":
				badge.text = "✓ 完了"
				badge.add_theme_color_override("font_color", TutorialUiStyle.DONE)
			"updated":
				badge.text = "★ 内容を更新しました"
				badge.add_theme_color_override("font_color", TutorialUiStyle.ACCENT)
			_:
				badge.text = "未完了"
				badge.add_theme_color_override("font_color", TutorialUiStyle.MUTED)


# ---------- 開始・終了 ----------

func _start_course() -> void:
	if not visible:
		return
	hide_selector()
	course_selected.emit(_course)


func _dismiss() -> void:
	if not visible:
		return
	hide_selector()
	dismissed.emit()


func _layout() -> void:
	var view := get_viewport_rect().size
	var factor := minf(view.x / DESIGN_SIZE.x, view.y / DESIGN_SIZE.y)
	_deck.size = DESIGN_SIZE
	_deck.scale = Vector2.ONE * factor
	_deck.position = (view - DESIGN_SIZE * factor) * 0.5


func get_evidence() -> Dictionary:
	var legend: Array[Dictionary] = []
	for entry: Dictionary in _legend_cards:
		var card: Control = entry["card"]
		legend.append({
			"id": "P%d:%s" % [int(entry["player"]), str(entry["id"])],
			"title": entry["title"],
			"caption": entry["caption"],
			"visible": card.is_visible_in_tree(),
			"rect": card.get_global_rect(),
		})
	return {
		"active": visible,
		"course": _course,
		"active_legend": _active_group,
		"legend": legend,
		"start_text": _start.text,
		"deck_rect": Rect2(_deck.position, DESIGN_SIZE * _deck.scale),
		"keyboard_rect": _keyboard.get_global_rect(),
		"keyboard": _keyboard.get_evidence(),
	}
