extends RefCounted

## 試合中の HUD・チュートリアル・練習・サドンデスで使う、タッチ専用の小道具。
## デスクトップでは呼ばれない（呼び出し側が is_touch() で分ける）ので、PC の見た目は変わらない。
##
## ・tap_key / press_key / release_key: TouchControls（オートロード）経由でキーを流し込む。
##   キーで進む既存の処理（Enter でスタートなど）を、画面のボタンからそのまま動かす。
## ・make_button: 指で押しやすい大きさの丸角ボタン（フォーカスを取らない）。
## ・make_tap_catcher: 画面全体を覆う透明なボタン（どこをタップしても閉じるカード用）。
##
## Use: const TouchHud = preload("res://scripts/ui/touch_hud/touch_hud.gd")

const MobileUi = preload("res://scripts/core/mobile_ui.gd")

const BUTTON_BG := Color(0.10, 0.13, 0.22, 0.92)
const BUTTON_BG_PRESSED := Color(0.20, 0.26, 0.42, 0.96)
const BUTTON_ACCENT := Color(1.0, 0.86, 0.36, 1.0)

## own_button_allowed: "持ち主のID:ボタン名" -> TouchControls のボタンが出ていないのを最初に見たフレーム。
static var _own_free_since: Dictionary = {}


static func is_touch() -> bool:
	return MobileUi.is_touch_ui()


## SafeArea（オートロード）の余白。名前で探すので、オートロードがまだ無い環境でも読み込める（無ければ 0）。
static func _safe_area() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("SafeArea")


static func safe_left() -> float:
	var node := _safe_area()
	return float(node.get("left")) if node != null else 0.0


static func safe_top() -> float:
	var node := _safe_area()
	return float(node.get("top")) if node != null else 0.0


static func safe_right() -> float:
	var node := _safe_area()
	return float(node.get("right")) if node != null else 0.0


static func safe_bottom() -> float:
	var node := _safe_area()
	return float(node.get("bottom")) if node != null else 0.0


## TouchControls が SafeArea の左上に置くポーズボタン（Ⅱ）の右端・下端までの幅（SafeArea の端から、すき間込み）。
## 左上に置く HUD はこの分だけ右へずらす。大きさは TouchControls._layout と同じ式（設定の touch_controls_scale で変わる）。
const PAUSE_EDGE_MARGIN := 36.0
const PAUSE_SIZE := 80.0
const PAUSE_GAP := 14.0


static func pause_clearance() -> float:
	var ui_scale := 1.0
	var tree := Engine.get_main_loop() as SceneTree
	var manager: Node = tree.root.get_node_or_null("GameManager") if tree != null else null
	if manager != null:
		var value: Variant = manager.get("touch_controls_scale")
		if value != null:
			ui_scale = clampf(float(value), 0.8, 1.3)
	return PAUSE_EDGE_MARGIN * ui_scale * 0.5 + maxf(PAUSE_SIZE * ui_scale, MobileUi.MIN_TOUCH_SIZE) + PAUSE_GAP


## SafeArea.changed に callback をつなぐ（オートロードが無ければ何もしない）。
static func on_safe_area_changed(callback: Callable) -> void:
	var node := _safe_area()
	if node != null and node.has_signal("changed") and not node.is_connected("changed", callback):
		node.connect("changed", callback)


static func _touch_controls() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("TouchControls")


## TouchControls（オートロード）が自分のボタン（"ConfirmButton" = スタート/OK/つぎへ/スキップ の Enter、
## "SkipButton" = Space のスキップ）をいま出しているか。出しているときは同じ働きのボタンを HUD 側で重ねて出さない。
## TouchControls が無い・使われていない（デスクトップ、試合の外）ときは false。
## 公開の is_confirm_shown() / is_skip_shown() があればそれを使い、無い版では内部のノード（TouchRoot/<name>）を見る。
static func touch_layer_shows(button_name: String) -> bool:
	var controls := _touch_controls()
	if controls == null:
		return false
	if controls.has_method("is_active") and not bool(controls.call("is_active")):
		return false
	var accessor := ""
	match button_name:
		"ConfirmButton":
			accessor = "is_confirm_shown"
		"SkipButton":
			accessor = "is_skip_shown"
	if not accessor.is_empty() and controls.has_method(accessor):
		return bool(controls.call(accessor))
	var button := controls.get_node_or_null("TouchRoot/" + button_name) as CanvasItem
	return button != null and button.is_visible_in_tree()


## HUD 側の「同じ働きのボタン」を出してよいか（毎フレーム呼ぶ）。holder はボタンの持ち主、wanted は HUD が出したいか。
## TouchControls のボタン（touch_layer_shows）と同じフレームに両方が見えないよう、
## TouchControls が出していないのを2フレーム続けて見てから出す。消すのはすぐ。
## （TouchControls はオートロードなので、同じフレームでは HUD より先に自分のボタンを出し入れする。
##  HUD が先に出したくなったフレームに TouchControls が次のフレームで出す、という1フレームの重なりをこれで消す。）
static func own_button_allowed(holder: Object, button_name: String, wanted: bool) -> bool:
	if holder == null:
		return false
	var key := "%d:%s" % [holder.get_instance_id(), button_name]
	if not wanted or touch_layer_shows(button_name):
		_own_free_since.erase(key)
		return false
	var frame := Engine.get_process_frames()
	if not _own_free_since.has(key):
		_own_free_since[key] = frame
		return false
	return frame > int(_own_free_since[key])


## キーを押してすぐ（次のフレームで）離す。TouchControls がまだ無いときは直接流し込む。
static func tap_key(keycode: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var controls := _touch_controls()
	if controls != null and controls.has_method("tap_key"):
		controls.call("tap_key", keycode, location)
		return
	_inject(keycode, location, true)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_inject(keycode, location, false)
		return
	tree.process_frame.connect(func() -> void: _inject(keycode, location, false), CONNECT_ONE_SHOT)


static func press_key(keycode: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var controls := _touch_controls()
	if controls != null and controls.has_method("press_key"):
		controls.call("press_key", keycode, location)
		return
	_inject(keycode, location, true)


static func release_key(keycode: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var controls := _touch_controls()
	if controls != null and controls.has_method("release_key"):
		controls.call("release_key", keycode, location)
		return
	_inject(keycode, location, false)


static func _inject(keycode: Key, location: KeyLocation, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.location = location
	event.pressed = pressed
	Input.parse_input_event(event)


## 指で押しやすいボタン。フォーカスを取らない（流し込んだ Enter/Space で二重に押されないように）。
static func make_button(text: String, font_px: int = 22, accent: Color = BUTTON_ACCENT) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = Vector2(MobileUi.MIN_TOUCH_SIZE * 2.0, MobileUi.MIN_TOUCH_SIZE)
	button.add_theme_font_size_override("font_size", MobileUi.font(font_px))
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	button.add_theme_constant_override("outline_size", 3)
	for state: String in ["normal", "hover", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, _button_style(BUTTON_BG, accent))
	button.add_theme_stylebox_override("pressed", _button_style(BUTTON_BG_PRESSED, accent))
	accept_extra_fingers(button)
	return button


## A Button only hears the mouse Android emulates from the first finger. In 2P, while one
## player holds a stick, the other's tap is a second finger: release it as a press too.
static func accept_extra_fingers(button: BaseButton) -> void:
	button.gui_input.connect(func(event: InputEvent) -> void:
		var touch := event as InputEventScreenTouch
		if touch != null and touch.index > 0 and not touch.pressed and button.is_visible_in_tree() and not button.disabled:
			button.accept_event()
			button.pressed.emit()
	)


static func _button_style(bg: Color, accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


## 画面全体を覆う透明なボタン。カードの上をどこでもタップすれば閉じる、に使う。
static func make_tap_catcher() -> Button:
	var catcher := Button.new()
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		catcher.add_theme_stylebox_override(state, empty)
	accept_extra_fingers(catcher)
	return catcher


## キーキャップの代わりに出す、文字だけの札（「タップ」「スティック」など）。
static func make_touch_label(text: String, font_px: int = 18, color: Color = BUTTON_ACCENT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", MobileUi.font(font_px))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	return label


## キーの表記（「Space」「A / ←」「右Ctrl」など）を、タッチの画面で通じる短い札に置き換える。
## 移動は矢印の形、ジャンプ・エモートは TouchControls のボタンの呼び名に合わせる。
static func touch_glyph(spec: String) -> String:
	var text := spec.strip_edges()
	var lowered := text.to_lower()
	if lowered.contains("enter"):
		return "タップ"
	if lowered.contains("esc"):
		return "Ⅱ"
	if lowered.contains("space") or lowered.contains("ctrl"):
		return "ジャンプ"
	if text == "矢印" or lowered.contains("wasd"):
		return "スティック"
	var glyphs: Array[String] = []
	for part: String in text.replace(" ", "").split("/", false):
		var glyph := _single_glyph(part)
		if glyph.is_empty():
			return text
		if not glyphs.has(glyph):
			glyphs.append(glyph)
	return " ".join(glyphs) if not glyphs.is_empty() else text


static func _single_glyph(token: String) -> String:
	match token.to_upper():
		"A", "←":
			return "◀"
		"D", "→":
			return "▶"
		"W", "↑":
			return "▲"
		"S", "↓":
			return "▼"
		"1", "8":
			return "♪1"
		"2", "9":
			return "♪2"
		"3", "0":
			return "♪3"
	return ""
