extends Control
class_name TutorialKeyboardIntro

## One complete key map before the existing playable tutorial.
## All actions stay visible; only the finger demonstration changes focus.
signal completed(course: String)
signal cancelled

const KeyboardScript = preload("res://scripts/ui/tutorial_keyboard.gd")
const DESIGN_SIZE := Vector2(1280, 720)
const SOLO := "SOLO"
const LOCAL_2P := "LOCAL_2P"
const NAVY := Color("0c1728")
const INK := Color("14243b")
const IVORY := Color("f5f1e8")
const MUTED := Color("b4c4d8")
const P1 := Color("ffa440")
const P2 := Color("51d8ec")
const DEMO_SECONDS := 3.6

var _course := SOLO
var _groups: Array[Dictionary] = []
var _tasks: Array[Dictionary] = []
var _players: Array[Dictionary] = []
var _focus_index := -1
var _step_clock := 0.0
var _paused := false
var _built := false
var _active_group := ""
var _deck: Control
var _keyboard: Control
var _eyebrow: Label
var _title: Label
var _body: Label
var _status: Label
var _player_labels: Array[Label] = []
var _cards: Array[Panel] = []
var _card_keys: Array[Label] = []
var _card_roles: Array[Label] = []
var _next: Button
var _replay: Button
var _pause: Button
var _close: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()


func show_intro(course: String) -> void:
	if not _built:
		_build_ui()
	_course = LOCAL_2P if course == LOCAL_2P else SOLO
	_build_key_map()
	_step_clock = 0.0
	_focus_index = -1
	_active_group = ""
	_paused = false
	_keyboard.set_reduced_motion(false)
	_keyboard.set_demonstration_override({})
	_keyboard.replay_demo()
	_eyebrow.text = "ローカル2Pの操作方法" if _course == LOCAL_2P else "1Pの操作方法"
	_title.text = "キーボード操作"
	_body.text = "P1はオレンジ、P2は水色で表示しています。各プレイヤーの操作キーを確認してください。" if _course == LOCAL_2P else "移動にはW・A・S・D、または矢印キーを使用します。実際にキーを押して確認できます。"
	_status.text = "P2のエモートはテンキー7・8・9にも対応。" if _course == LOCAL_2P else "枠と指のアニメーションで入力位置を示します。"
	_pause.set_pressed_no_signal(false)
	_pause.text = "アニメーション停止"
	_rebuild_cards()
	show()
	_update_focus()
	_update_active_card()
	_layout()
	_next.grab_focus()


func is_active() -> bool:
	return visible and not _tasks.is_empty()


func get_start_button() -> Button:
	return _next


func _process(delta: float) -> void:
	if not is_active():
		return
	if not _paused:
		_step_clock += maxf(delta, 0.0)
	_update_focus()
	_keyboard.advance(delta)
	_update_active_card()
	_layout()


func _input(event: InputEvent) -> void:
	if not is_active() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()
		return
	# Practice keys never activate the focused start button or the menu below.
	# Tab and Enter retain ordinary accessible button navigation.
	if key.keycode in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE, KEY_CTRL,
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_1, KEY_2, KEY_3,
		KEY_8, KEY_9, KEY_0, KEY_KP_7, KEY_KP_8, KEY_KP_9]:
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	var background := ColorRect.new()
	background.name = "FullScreenBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = NAVY
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)
	_deck = Control.new()
	_deck.name = "KeyboardIntroduction"
	_deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_deck)
	_eyebrow = _label("", 16, MUTED)
	_title = _label("", 35, IVORY)
	_body = _label("", 18, IVORY)
	_status = _label("枠と指のアニメーションで入力位置を示します。", 16, MUTED)
	_keyboard = KeyboardScript.new()
	_keyboard.name = "PhysicalKeyboard"
	_keyboard.show_footnote = false
	_deck.add_child(_keyboard)
	_next = _button("チュートリアル開始", _start_practice)
	_next.name = "StartPractice"
	_style_button(_next, true)
	_replay = _button("操作例を再生", _replay_demo)
	_pause = _button("アニメーション停止", _toggle_pause)
	_pause.toggle_mode = true
	_close = _button("Esc  コース選択", _cancel)
	_close.add_theme_font_size_override("font_size", 16)


func _label(text: String, font_size: int, color: Color, host: Control = null) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	(host if host else _deck).add_child(label)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(callback)
	_deck.add_child(button)
	_style_button(button, false)
	return button


func _style_button(button: Button, primary: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = P1 if primary else Color("21344d")
		if state == "hover":
			style.bg_color = style.bg_color.lightened(0.12)
		elif state == "pressed":
			style.bg_color = style.bg_color.darkened(0.12)
		style.border_color = P1 if primary else Color("4c647f")
		style.set_border_width_all(1)
		style.set_corner_radius_all(10)
		style.content_margin_left = 14
		style.content_margin_right = 14
		button.add_theme_stylebox_override(state, style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = IVORY
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(10)
	focus.expand_margin_left = 4
	focus.expand_margin_top = 4
	focus.expand_margin_right = 4
	focus.expand_margin_bottom = 4
	button.add_theme_stylebox_override("focus", focus)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK if primary else IVORY)


func _rebuild_cards() -> void:
	for card: Panel in _cards:
		card.free()
	for label: Label in _player_labels:
		label.free()
	_cards.clear()
	_card_keys.clear()
	_card_roles.clear()
	_player_labels.clear()
	for player: Dictionary in _players:
		var number := int(player["player"])
		var tag := _label("P%d" % number, 24, P2 if number == 2 else P1)
		_player_labels.append(tag)
	for group: Dictionary in _groups:
		var card := Panel.new()
		card.name = str(group["id"]).replace(":", "_")
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_deck.add_child(card)
		_cards.append(card)
		var accent := P2 if int(group["player"]) == 2 else P1
		_card_keys.append(_label(str(group["keys"]), 22, accent, card))
		_card_roles.append(_label(str(group["role"]), 17, IVORY, card))


func _build_key_map() -> void:
	_groups.clear()
	_tasks.clear()
	_players.clear()
	var player_numbers: Array[int] = [1]
	if _course == LOCAL_2P:
		player_numbers.append(2)
	for player: int in player_numbers:
		var p2 := player == 2
		var solo := _course == SOLO
		var player_tasks: Array[Dictionary] = []
		_add_group(player, "left_right", "←・→" if p2 else "A・D", "左右移動", [
			{"id": "left", "key": "←" if p2 else "A / ←" if solo else "A", "caption": "左移動"},
			{"id": "right", "key": "→" if p2 else "D / →" if solo else "D", "caption": "右移動"}], player_tasks)
		_add_group(player, "forward_back", "↑・↓" if p2 else "W・S", "↑：前進　↓：後退" if p2 else "W：前進　S：後退", [
			{"id": "forward", "key": "↑" if p2 else "W / ↑" if solo else "W", "caption": "前進"},
			{"id": "back", "key": "↓" if p2 else "S / ↓" if solo else "S", "caption": "後退"}], player_tasks)
		_add_group(player, "jump", "Ctrl（左右共通）" if p2 else "Space", "ジャンプ", [
			{"id": "jump", "key": "Ctrl" if p2 else "Space", "caption": "ジャンプ"}], player_tasks)
		var digits: Array = ["8", "9", "0"] if p2 else ["1", "2", "3"]
		var emotes: Array[Dictionary] = []
		for index: int in range(digits.size()):
			emotes.append({"id": "emote_%d" % index, "key": digits[index], "caption": "エモート %d" % (index + 1)})
		_add_group(player, "emote", "8・9・0" if p2 else "1・2・3", "エモート再生", emotes, player_tasks)
		_players.append({"player": player, "tasks": player_tasks})


func _add_group(player: int, suffix: String, keys: String, role: String, actions: Array, player_tasks: Array[Dictionary]) -> void:
	var group_id := "P%d:%s" % [player, suffix]
	_groups.append({"id": group_id, "player": player, "keys": keys, "role": role})
	for action: Dictionary in actions:
		var task := action.duplicate(true)
		task["player"] = player
		task["group"] = group_id
		_tasks.append(task)
		player_tasks.append(task)


func _update_focus() -> void:
	var next_focus := int(floor(_step_clock / DEMO_SECONDS)) % _tasks.size()
	if next_focus == _focus_index:
		return
	_focus_index = next_focus
	var focused: Dictionary = _tasks[_focus_index]
	_keyboard.configure({"step_id": "keyboard_intro_" + _course, "lesson_kind": "key_map",
		"focus_task": focused, "players": _players}, _course == LOCAL_2P)


func _update_active_card() -> void:
	var state: Dictionary = _keyboard.get_action_state()
	var active := ""
	for task: Dictionary in _tasks:
		if str(task["id"]) == str(state.get("id", "")) and int(task["player"]) == int(state.get("player", 1)):
			active = str(task["group"])
			break
	if active == _active_group:
		return
	_active_group = active
	for index: int in range(_cards.size()):
		var group: Dictionary = _groups[index]
		var accent := P2 if int(group["player"]) == 2 else P1
		var selected := str(group["id"]) == active
		var style := StyleBoxFlat.new()
		style.bg_color = Color("24374b") if selected else Color("17283e")
		style.border_color = accent if selected else accent.darkened(0.48)
		style.set_border_width_all(3 if selected else 1)
		style.set_corner_radius_all(10)
		_cards[index].add_theme_stylebox_override("panel", style)


func _start_practice() -> void:
	if not is_active():
		return
	hide()
	completed.emit(_course)


func _cancel() -> void:
	if not is_active():
		return
	hide()
	cancelled.emit()


func _replay_demo() -> void:
	_step_clock = 0.0
	_focus_index = -1
	_paused = false
	_pause.set_pressed_no_signal(false)
	_pause.text = "アニメーション停止"
	_keyboard.set_reduced_motion(false)
	_keyboard.replay_demo()
	_update_focus()
	_update_active_card()


func _toggle_pause() -> void:
	_paused = _pause.button_pressed
	_keyboard.set_reduced_motion(_paused)
	_pause.text = "アニメーション再開" if _paused else "アニメーション停止"


func _layout() -> void:
	var view := get_viewport_rect().size
	var factor := minf(view.x / DESIGN_SIZE.x, view.y / DESIGN_SIZE.y)
	_deck.size = DESIGN_SIZE
	_deck.scale = Vector2.ONE * factor
	_deck.position = (view - DESIGN_SIZE * factor) * 0.5
	_place(_eyebrow, Vector2(64, 23), Vector2(950, 24))
	_place(_title, Vector2(64, 48), Vector2(1050, 50))
	_place(_body, Vector2(64, 99), Vector2(1152, 27))
	_place(_close, Vector2(1040, 24), Vector2(176, 38))
	for index: int in range(_cards.size()):
		var row := int(index / 4)
		var column := index % 4
		var top := 137.0 if row == 0 else 568.0
		_place(_cards[index], Vector2(136 + column * 272, top), Vector2(264, 72))
		_place(_card_keys[index], Vector2(14, 6), Vector2(236, 31))
		_place(_card_roles[index], Vector2(14, 38), Vector2(236, 27))
	for index: int in range(_player_labels.size()):
		_place(_player_labels[index], Vector2(64, 151 if index == 0 else 582), Vector2(62, 40))
	if _course == LOCAL_2P:
		_place(_keyboard, Vector2(64, 223), Vector2(1152, 332))
	else:
		_place(_keyboard, Vector2(48, 220), Vector2(1184, 412))
	_place(_replay, Vector2(64, 662), Vector2(186, 44))
	_place(_pause, Vector2(266, 662), Vector2(212, 44))
	_place(_status, Vector2(500, 670), Vector2(420, 26))
	_place(_next, Vector2(950, 654), Vector2(266, 52))


func _place(node: Control, at: Vector2, extent: Vector2) -> void:
	node.position = at
	node.size = extent


func get_evidence() -> Dictionary:
	var players: Array[String] = []
	for player: Dictionary in _players:
		players.append("P%d" % int(player["player"]))
	var shown_actions: Array[String] = []
	var action_labels: Array[Dictionary] = []
	for index: int in range(_groups.size()):
		var group: Dictionary = _groups[index]
		shown_actions.append(str(group["id"]))
		action_labels.append({"id": group["id"], "keys": group["keys"], "role": group["role"],
			"visible": _cards[index].is_visible_in_tree(), "rect": _cards[index].get_global_rect()})
	return {"active": is_active(), "course": _course, "page_index": 0, "page_count": 1,
		"players": players, "shown_actions": shown_actions, "action_labels": action_labels,
		"demo_focus": _active_group, "title": _title.text, "paused": _paused, "next_text": _next.text,
		"deck_rect": _deck.get_global_rect(), "keyboard_rect": _keyboard.get_global_rect(),
		"keyboard": _keyboard.get_evidence(), "navigation": "single screen / Tab+Enter / Esc",
		"uses_character_demo": false}
