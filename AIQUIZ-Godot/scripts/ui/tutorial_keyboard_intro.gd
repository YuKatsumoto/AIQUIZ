extends Control
class_name TutorialKeyboardIntro

## One complete key map before the existing playable tutorial.
## Static: all actions stay visible and only real key input is highlighted.
signal completed(course: String)
signal cancelled

const KeyboardScript = preload("res://scripts/ui/tutorial_keyboard.gd")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")
## スマホ（タッチだけ）では、キーボードの絵の代わりに画面のボタンの図を出す。
const TouchDiagramScript = preload("res://scripts/ui/mobile/touch_controls_diagram.gd")
## ローカル2Pでは、キーボードの絵の代わりに机を見下ろす3Dの場面を出す。
const DeskScript = preload("res://scripts/ui/tutorial_keyboard_desk_3d.gd")
const DESIGN_SIZE := Vector2(1280, 720)
## 3Dの机のときの説明カードの列（P1は左手なので左、P2は右手なので右）と幅。
const DESK_COLUMNS := [24.0, 1044.0]
const DESK_CARD_WIDTH := 212.0
## 3Dの机でチュートリアルを始めるとき、モニターへ寄る演出の始めに文字とカードを消す時間。
const START_FADE_SECONDS := 0.3
const SOLO := "SOLO"
const LOCAL_2P := "LOCAL_2P"
const NAVY := Color("0c1728")
const IVORY := Color("f5f1e8")
const MUTED := Color("b4c4d8")
const P1 := Color("ffa440")
const P2 := Color("51d8ec")

var _course := SOLO
var _groups: Array[Dictionary] = []
var _tasks: Array[Dictionary] = []
var _players: Array[Dictionary] = []
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
var _card_keys: Array[KeyHintRow] = []
var _card_roles: Array[Label] = []
var _next: Button
var _close: Button
var _touch_diagram: Control = null
var _desk_3d: DeskScript = null
## 3Dの机でモニターへ寄る演出の途中（入力を受け付けず、二重に始めない）と、その経過秒。
var _starting := false
var _start_elapsed := 0.0
## 寄り終えた画面の静止画（メインメニューが take_start_cover() で受け取り、本編へ移る間の覆いにする）。
var _start_cover: Texture2D = null


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
	_active_group = ""
	_starting = false
	_start_cover = null
	_deck.modulate.a = 1.0
	_eyebrow.text = "ローカル2Pの操作方法" if _course == LOCAL_2P else "1Pの操作方法"
	_title.text = "キーボード操作"
	_body.text = "P1は左手でオレンジのキー\nP2は両手で水色のキー" if _course == LOCAL_2P else "移動はWASDか矢印キー"
	_status.text = "P2のエモートは左手で押す\nテンキー7・8・9でもOK" if _course == LOCAL_2P else "キーを押すと対応するカードが光る"
	if _touch_diagram != null:
		_eyebrow.text = "操作方法"
		_title.text = "タッチ操作"
		_body.text = "左のスティックで移動　右のボタンでジャンプとエモート"
		_status.text = "左上のⅡで一時停止できる"
	_rebuild_cards()
	_configure_keyboard()
	_apply_presentation()
	show()
	# 作り直したカードは、まだ何も押されていなくても配色を付ける。
	_update_active_card(true)
	_layout()
	_next.grab_focus()


func is_active() -> bool:
	return visible and not _tasks.is_empty()


func get_start_button() -> Button:
	return _next


## 3Dの机のモニターに映す映像（メインメニューの背景の LiveViewport）。
func set_monitor_texture(texture: Texture2D) -> void:
	if not _built:
		_build_ui()
	if _desk_3d != null:
		_desk_3d.set_monitor_texture(texture)


func _process(delta: float) -> void:
	if not is_active():
		return
	_keyboard.advance(delta)
	if _starting:
		_start_elapsed += delta
		_deck.modulate.a = 1.0 - clampf(_start_elapsed / START_FADE_SECONDS, 0.0, 1.0)
	if _desk_3d != null and _desk_3d.visible:
		_desk_3d.advance(delta)
	_update_active_card()
	_layout()


func _input(event: InputEvent) -> void:
	if not is_active() or not event is InputEventKey:
		return
	if _starting:
		# モニターへ寄っている間は、Esc も含めてキーを下のメニューへ渡さない。
		get_viewport().set_input_as_handled()
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
	if not MobileUi.is_touch_ui():
		# カードや文字より奥に置く。
		_desk_3d = DeskScript.new()
		_desk_3d.name = "KeyboardDesk3D"
		_desk_3d.visible = false
		add_child(_desk_3d)
		_desk_3d.monitor_entered.connect(_on_monitor_entered)
	_deck = Control.new()
	_deck.name = "KeyboardIntroduction"
	_deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_deck)
	_eyebrow = _label("", 16, MUTED)
	_title = _label("", 35, IVORY)
	_body = _label("", 18, IVORY)
	_status = _label("キーを押すと対応するカードが光る", 16, MUTED)
	_keyboard = KeyboardScript.new()
	_keyboard.name = "PhysicalKeyboard"
	_keyboard.show_footnote = false
	_keyboard.show_demo = false
	_deck.add_child(_keyboard)
	if MobileUi.is_touch_ui():
		# キーボードの絵は隠すだけ（キーの状態の読み取りと get_evidence はそのまま動く）
		_keyboard.visible = false
		_touch_diagram = TouchDiagramScript.new()
		_touch_diagram.name = "TouchControlsDiagram"
		_deck.add_child(_touch_diagram)
	_next = _button("チュートリアル開始", _start_practice)
	_next.name = "StartPractice"
	(_next as MenuMetalButton).featured = true
	_close = _button(MobileUi.prompt("Esc  コース選択", "◀ コース選択"), _cancel)
	_close.add_theme_font_size_override("font_size", MobileUi.font(16))


func _label(text: String, font_size: int, color: Color, host: Control = null) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", MobileUi.font(font_size))
	label.add_theme_color_override("font_color", color)
	(host if host else _deck).add_child(label)
	return label


## メニュー画面と同じ金属プレートのボタン（MenuMetalButton）。
func _button(text: String, callback: Callable) -> Button:
	var button := MenuMetalButton.new()
	button.compact = true
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", MobileUi.font(19))
	button.pressed.connect(callback)
	_deck.add_child(button)
	return button


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
		tag.visible = _touch_diagram == null
		_player_labels.append(tag)
	for group: Dictionary in _groups:
		var card := Panel.new()
		card.name = str(group["id"]).replace(":", "_")
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# タッチでは図のほうに名前を書くので、キーのカードは出さない
		card.visible = _touch_diagram == null
		_deck.add_child(card)
		_cards.append(card)
		var accent := P2 if int(group["player"]) == 2 else P1
		_card_keys.append(_key_row(str(group["keys"]), accent, card))
		_card_roles.append(_label(str(group["role"]), 17, IVORY, card))


## HUD と同じキーキャップで並べる。「右Ctrl」は「右」を小さく添えて Ctrl のキーキャップを出す。
func _key_row(keys: String, accent: Color, host: Control) -> KeyHintRow:
	var row := KeyHintRow.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	host.add_child(row)
	if keys.begins_with("右"):
		row.add_text("右", accent, 16)
		keys = keys.trim_prefix("右")
	row.add_spec(keys, KeycapChip.DEFAULT_ACCENT, KeycapChip.SizeClass.NORMAL)
	return row


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
		_add_group(player, "jump", "右Ctrl" if p2 else "Space", "ジャンプ", [
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


func _configure_keyboard() -> void:
	_keyboard.configure({"step_id": "keyboard_intro_" + _course, "lesson_kind": "key_map",
		"players": _players}, _course == LOCAL_2P)


## ローカル2Pでは2Dのキーボードの絵を隠して3Dの机を出す。2Dのほうは入力の判定役として動かし続ける。
func _apply_presentation() -> void:
	var desk := _uses_desk()
	_keyboard.visible = _touch_diagram == null and not desk
	if _desk_3d != null:
		_desk_3d.visible = desk
		if desk:
			_desk_3d.bind_keyboard(_keyboard)
	# 机のときは、本文をモニターの左に収まる大きさにし、補足は右の列の幅で折り返す。
	_body.add_theme_font_size_override("font_size", MobileUi.font(16 if desk else 18))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if desk else TextServer.AUTOWRAP_OFF


func _uses_desk() -> bool:
	return _desk_3d != null and _course == LOCAL_2P


func _update_active_card(force: bool = false) -> void:
	var state: Dictionary = _keyboard.get_action_state()
	var active := ""
	for task: Dictionary in _tasks:
		if str(task["id"]) == str(state.get("id", "")) and int(task["player"]) == int(state.get("player", 1)):
			active = str(task["group"])
			break
	if active == _active_group and not force:
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
	if not is_active() or _starting:
		return
	if _uses_desk() and not bool(_keyboard.get_action_state().get("reduced_motion", false)):
		# 3Dの机では、文字とカードを消しながらカメラをモニターへ寄せ、画面いっぱいになってから始める（_on_monitor_entered）。
		_starting = true
		_start_elapsed = 0.0
		_desk_3d.enter_monitor()
		return
	hide()
	completed.emit(_course)


## モニターへ寄り終えた。その画面を静止画にしてから閉じ、始める（受け取った側が覆いにして、そのまま本編へ移る）。
func _on_monitor_entered() -> void:
	if not _starting:
		return
	_start_cover = _desk_3d.capture_frame()
	_starting = false
	hide()
	completed.emit(_course)


## モニターへ寄り終えた画面の静止画（一度だけ渡す）。なければ null。
func take_start_cover() -> Texture2D:
	var cover := _start_cover
	_start_cover = null
	return cover


func _cancel() -> void:
	if not is_active() or _starting:
		return
	hide()
	cancelled.emit()


func _layout() -> void:
	var view := get_viewport_rect().size
	var factor := minf(view.x / DESIGN_SIZE.x, view.y / DESIGN_SIZE.y)
	_deck.size = DESIGN_SIZE
	_deck.scale = Vector2.ONE * factor
	_deck.position = (view - DESIGN_SIZE * factor) * 0.5
	if _uses_desk():
		_layout_desk(view)
		return
	_place(_eyebrow, Vector2(64, 23), Vector2(950, 24))
	_place(_title, Vector2(64, 48), Vector2(1050, 50))
	_place(_body, Vector2(64, 99), Vector2(1152, 27))
	_place(_close, Vector2(1040, 24), Vector2(176, 38))
	for index: int in range(_cards.size()):
		var row := int(index / 4)
		var column := index % 4
		var top := 137.0 if row == 0 else 568.0
		_place(_cards[index], Vector2(136 + column * 272, top), Vector2(264, 72))
		_place(_card_keys[index], Vector2(14, 5), Vector2(236, 38))
		_place(_card_roles[index], Vector2(14, 42), Vector2(236, 26))
	for index: int in range(_player_labels.size()):
		_place(_player_labels[index], Vector2(64, 151 if index == 0 else 582), Vector2(62, 40))
	if _course == LOCAL_2P:
		_place(_keyboard, Vector2(64, 223), Vector2(1152, 332))
	else:
		_place(_keyboard, Vector2(48, 220), Vector2(1184, 412))
	_place(_status, Vector2(64, 670), Vector2(860, 26))
	_place(_next, Vector2(950, 654), Vector2(266, 52))
	if _touch_diagram != null:
		# 指で押せる大きさ（論理 80px 以上）。キーのカードの場所まで図を広げる
		_place(_touch_diagram, Vector2(48, 140), Vector2(1184, 480))
		_place(_close, Vector2(976, 14), Vector2(240, 80))
		_place(_status, Vector2(64, 648), Vector2(800, 34))
		_place(_next, Vector2(880, 626), Vector2(336, 84))


## 3Dの机の並び。P1の説明を左、P2を右の列に縦に並べ（手と同じ側）、開始ボタンは両腕の間の下の中央に置く。
func _layout_desk(view: Vector2) -> void:
	_desk_3d.fit_to_view(view)
	_place(_eyebrow, Vector2(64, 23), Vector2(420, 24))
	_place(_title, Vector2(64, 48), Vector2(420, 50))
	_place(_body, Vector2(64, 102), Vector2(290, 52))
	_place(_close, Vector2(1040, 24), Vector2(176, 38))
	for index: int in range(_cards.size()):
		_place(_cards[index], Vector2(DESK_COLUMNS[int(index / 4)], 236 + (index % 4) * 80), Vector2(DESK_CARD_WIDTH, 70))
		_place(_card_keys[index], Vector2(14, 5), Vector2(DESK_CARD_WIDTH - 28, 38))
		_place(_card_roles[index], Vector2(14, 41), Vector2(DESK_CARD_WIDTH - 28, 26))
	for index: int in range(_player_labels.size()):
		_place(_player_labels[index], Vector2(DESK_COLUMNS[index], 190), Vector2(62, 40))
	_place(_status, Vector2(DESK_COLUMNS[1], 560), Vector2(DESK_CARD_WIDTH, 48))
	_place(_next, Vector2(507, 654), Vector2(266, 52))


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
		"demo_focus": _active_group, "title": _title.text, "next_text": _next.text,
		"deck_rect": _deck.get_global_rect(), "keyboard_rect": _keyboard_rect(),
		"keyboard": _keyboard.get_evidence(), "navigation": "single screen / Tab+Enter / Esc",
		"uses_character_demo": false, "animated_demo": false,
		"presentation": "desk_3d" if _uses_desk() else "flat", "starting": _starting,
		"desk": _desk_3d.get_evidence() if _uses_desk() else {}}


## 画面のキーボードの範囲（3Dの机のときは、3Dのキーボードが映る範囲）。
func _keyboard_rect() -> Rect2:
	if not _uses_desk():
		return _keyboard.get_global_rect()
	var rect := _desk_3d.get_keyboard_screen_rect()
	var xform := _desk_3d.get_global_transform()
	return Rect2(xform * rect.position, xform.basis_xform(rect.size))
