class_name NetOverlay
extends CanvasLayer

## オンライン対戦中の画面表示。
## ・つながりなおし中／相手待ちの一時停止と、復帰時の 3-2-1
## ・不戦勝や切断で試合が終わったときのカード
## ・ESC の「やめる？」確認（オンラインは時間を止められないのでポーズしない）
## ・F8 で回線の状態（RTT・バッファ・補正量・通信量）
## ・右上に今の通信状況（ping）を常に表示

signal quit_requested

## ping の色分けのさかい目（ミリ秒）。これ未満なら良好（緑）／ふつう（黄）、以上は悪い（赤）。
const PING_GOOD_MS := 80.0
const PING_FAIR_MS := 150.0
const PING_GOOD_COLOR := Color(0.35, 0.95, 0.45)
const PING_FAIR_COLOR := Color(1.0, 0.82, 0.25)
const PING_BAD_COLOR := Color(1.0, 0.36, 0.3)
const PING_UNKNOWN_COLOR := Color(0.62, 0.66, 0.72)
const PING_REFRESH_SECONDS := 0.5

var _net: NetGameState
var _dim: ColorRect
var _panel: PanelContainer
var _message: Label
var _countdown: Label
var _button_row: HBoxContainer
var _primary: Button
var _secondary: Button
var _stats: Label
var _ping_panel: PanelContainer
var _ping_bars: Control
var _ping_label: Label
var _ping_color := PING_UNKNOWN_COLOR
var _ping_level := 0  # 0〜3 本（0 は不明・切断中）
var _ping_timer := PING_REFRESH_SECONDS
var _mode := ""  # "", "pause", "over", "confirm"
var _stats_timer := 0.0
var _last_snap_bytes := 0
var _last_cmd_bytes := 0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_hide_panel()


func setup(net: NetGameState) -> void:
	_net = net
	net.pause_changed.connect(_on_pause_changed)
	net.match_over.connect(_on_match_over)
	if net.paused:
		_on_pause_changed(true, net.pause_message)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.07, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(center)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.15, 0.94)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(28)
	style.border_color = Color(1, 0.88, 0.25, 0.8)
	style.set_border_width_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_panel.add_child(box)
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 30)
	_message.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	box.add_child(_message)
	_countdown = Label.new()
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.add_theme_font_size_override("font_size", 72)
	_countdown.add_theme_color_override("font_color", Color(1, 0.88, 0.25))
	box.add_child(_countdown)
	_button_row = HBoxContainer.new()
	_button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_row.add_theme_constant_override("separation", 16)
	box.add_child(_button_row)
	_primary = _make_button()
	_secondary = _make_button()
	_primary.pressed.connect(_on_primary)
	_secondary.pressed.connect(_on_secondary)

	_stats = Label.new()
	_stats.position = Vector2(12, 12)
	_stats.add_theme_font_size_override("font_size", 14)
	_stats.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_stats.add_theme_color_override("font_outline_color", Color.BLACK)
	_stats.add_theme_constant_override("outline_size", 4)
	_stats.visible = false
	add_child(_stats)
	_build_ping()


## 右上の小さな札：電波の棒（3 本）と「Ping 42 ms」。
func _build_ping() -> void:
	_ping_panel = PanelContainer.new()
	_ping_panel.name = "PingDisplay"
	_ping_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.09, 0.72)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_ping_panel.add_theme_stylebox_override("panel", style)
	_ping_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ping_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ping_panel.offset_right = -12.0
	_ping_panel.offset_top = 10.0
	add_child(_ping_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ping_panel.add_child(row)
	_ping_bars = Control.new()
	_ping_bars.custom_minimum_size = Vector2(18, 16)
	_ping_bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ping_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ping_bars.draw.connect(_draw_ping_bars)
	row.add_child(_ping_bars)
	_ping_label = Label.new()
	_ping_label.add_theme_font_size_override("font_size", 17)
	_ping_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_ping_label.add_theme_constant_override("outline_size", 3)
	row.add_child(_ping_label)
	_refresh_ping()


func _refresh_ping() -> void:
	var rtt := NetworkManager.rtt_ms
	var reconnecting := NetworkManager.state == NetworkManager.State.RECONNECTING
	if reconnecting or rtt < 0.0:
		_ping_label.text = "Ping -- ms"
		_ping_color = PING_BAD_COLOR if reconnecting else PING_UNKNOWN_COLOR
		_ping_level = 0
	else:
		_ping_label.text = "Ping %d ms" % roundi(rtt)
		if rtt < PING_GOOD_MS:
			_ping_color = PING_GOOD_COLOR
			_ping_level = 3
		elif rtt < PING_FAIR_MS:
			_ping_color = PING_FAIR_COLOR
			_ping_level = 2
		else:
			_ping_color = PING_BAD_COLOR
			_ping_level = 1
	_ping_label.add_theme_color_override("font_color", _ping_color)
	_ping_bars.queue_redraw()


func _draw_ping_bars() -> void:
	var bar_width := 4.0
	var gap := 3.0
	var full_height := _ping_bars.size.y
	for i in 3:
		var height := full_height * (0.4 + 0.3 * i)
		var rect := Rect2(i * (bar_width + gap), full_height - height, bar_width, height)
		var lit := i < _ping_level
		_ping_bars.draw_rect(rect, _ping_color if lit else Color(1, 1, 1, 0.22))


func _make_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(200, 56)
	button.add_theme_font_size_override("font_size", 22)
	_button_row.add_child(button)
	return button


func _process(dt: float) -> void:
	if _net == null:
		return
	_ping_timer += dt
	if _ping_timer >= PING_REFRESH_SECONDS:
		_ping_timer = 0.0
		_refresh_ping()
	if _mode == "pause":
		if _net.resume_countdown > 0.0:
			_message.text = "さいかい します"
			_countdown.text = str(ceili(_net.resume_countdown))
			_countdown.visible = true
		elif NetworkManager.state == NetworkManager.State.RECONNECTING:
			_message.text = _net.pause_message
			_countdown.text = str(ceili(NetworkManager.reconnect_seconds_left()))
			_countdown.visible = true
		else:
			_message.text = _net.pause_message
			_countdown.visible = false
	if _stats.visible:
		_stats_timer += dt
		if _stats_timer >= 0.5:
			var snap_rate: float = (int(_net.stats.snap_bytes) - _last_snap_bytes) / _stats_timer
			var cmd_rate: float = (int(_net.stats.cmd_bytes) - _last_cmd_bytes) / _stats_timer
			_last_snap_bytes = int(_net.stats.snap_bytes)
			_last_cmd_bytes = int(_net.stats.cmd_bytes)
			_stats_timer = 0.0
			_stats.text = "NET %s  RTT %d ms\nbuffer %d  correction %.2f\nsnap %.1f KB/s  cmd %.1f KB/s" % [
				"HOST" if _net.is_host else "GUEST",
				int(NetworkManager.rtt_ms),
				int(_net.stats.buffer),
				float(_net.stats.correction),
				snap_rate / 1024.0,
				cmd_rate / 1024.0,
			]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_stats.visible = not _stats.visible
		get_viewport().set_input_as_handled()


func toggle_quit_confirm() -> void:
	if _mode == "over":
		return
	if _mode == "confirm":
		_restore_after_confirm()
		return
	_mode = "confirm"
	_show_panel("たいせんを やめますか？\n（あいての かちに なります）", ["やめる", "つづける"])


func _restore_after_confirm() -> void:
	if _net != null and _net.paused:
		_on_pause_changed(true, _net.pause_message)
	else:
		_hide_panel()


func _on_pause_changed(is_paused: bool, message: String) -> void:
	if _mode in ["over", "confirm"]:
		return
	if not is_paused:
		_hide_panel()
		return
	_mode = "pause"
	_show_panel(message, ["やめる"])


func _on_match_over(message: String) -> void:
	_mode = "over"
	_show_panel(message, ["メニューへ"])


func _show_panel(text: String, buttons: Array) -> void:
	_message.text = text
	_countdown.visible = false
	_primary.text = buttons[0] if buttons.size() > 0 else ""
	_primary.visible = buttons.size() > 0
	_secondary.text = buttons[1] if buttons.size() > 1 else ""
	_secondary.visible = buttons.size() > 1
	_dim.visible = true
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP


func _hide_panel() -> void:
	_mode = ""
	_dim.visible = false


func _on_primary() -> void:
	# pause / over / confirm の先頭ボタンはどれも「試合を抜けてメニューへ」。
	quit_requested.emit()


func _on_secondary() -> void:
	if _mode == "confirm":
		_restore_after_confirm()
