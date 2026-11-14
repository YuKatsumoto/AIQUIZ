extends Control

## 起動画面に出す「アップデートがあります」の案内。
## 「更新する」でパッチを落とし、終わったらゲームを立ち上げ直す。「あとで」ならそのまま起動を続ける。
## パッチで済まない版（GameUpdater.KIND_FULL）のときは、配布ページを開くボタンに替わる。
## 見た目は起動画面（startup_loading.gd）の青い文字と進みぐあいの棒に合わせている。

## restarting が true のときは、もうゲームを終了させている。呼び出し側は起動を続けない。
signal finished(restarting: bool)

const GameUpdater = preload("res://scripts/core/game_updater.gd")
const FONT_BOLD: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const FONT_MEDIUM: Font = preload("res://resources/fonts/NotoSansJP-Medium.otf")

const TEXT_COLOR := Color(0.78, 0.88, 1.0)
const DIM_COLOR := Color(0.56, 0.66, 0.80)
const ERROR_COLOR := Color(1.0, 0.72, 0.52)
const ACCENT_COLOR := Color(0.48, 0.72, 0.96)
const PANEL_COLOR := Color(0.06, 0.09, 0.14)
const BORDER_COLOR := Color(0.55, 0.72, 0.92, 0.85)
const PANEL_WIDTH := 560.0

var _updater: Node
var _offer: Dictionary = {}
var _status: Label
var _progress: ProgressBar
var _buttons: HBoxContainer
var _primary: Button
var _secondary: Button
var _busy := false


func setup(updater: Node, offer: Dictionary) -> void:
	_updater = updater
	_offer = offer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	if _updater != null and _updater.has_signal("progress"):
		_updater.connect("progress", _on_progress)
	_focus_default.call_deferred()


func _is_patch() -> bool:
	return str(_offer.get("kind", "")) == GameUpdater.KIND_PATCH


func _is_required() -> bool:
	return bool(_offer.get("required", false))


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "UpdatePanel"
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_COLOR
	box.border_color = BORDER_COLOR
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(32.0)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var version := str(_offer.get("version", ""))
	if _is_patch():
		column.add_child(_label("アップデートがあります", FONT_BOLD, 26, TEXT_COLOR))
		column.add_child(_label("バージョン %s（%s）" % [version, GameUpdater.format_size(int(_offer.get("size", 0)))],
			FONT_MEDIUM, 18, TEXT_COLOR))
	else:
		column.add_child(_label("新しいバージョンがあります", FONT_BOLD, 26, TEXT_COLOR))
		column.add_child(_label("バージョン %s は、ゲームをダウンロードし直す必要があります" % version,
			FONT_MEDIUM, 18, TEXT_COLOR))
	var notes := str(_offer.get("notes", "")).strip_edges()
	if not notes.is_empty():
		column.add_child(_label(notes, FONT_MEDIUM, 15, DIM_COLOR))

	_progress = ProgressBar.new()
	_progress.name = "DownloadProgress"
	_progress.custom_minimum_size = Vector2(0.0, 10.0)
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.show_percentage = false
	_progress.visible = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.30, 0.40)
	track.border_color = BORDER_COLOR
	track.set_border_width_all(1)
	track.set_content_margin_all(1.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT_COLOR
	_progress.add_theme_stylebox_override("background", track)
	_progress.add_theme_stylebox_override("fill", fill)
	column.add_child(_progress)

	_status = _label("", FONT_MEDIUM, 15, DIM_COLOR)
	_status.name = "StatusLabel"
	_status.visible = false
	column.add_child(_status)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 6.0)
	column.add_child(gap)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 12)
	column.add_child(_buttons)
	_secondary = _button("終了する" if _is_required() else "あとで", false)
	_secondary.name = "LaterButton"
	_secondary.pressed.connect(_on_secondary_pressed)
	_buttons.add_child(_secondary)
	_primary = _button("更新する" if _is_patch() else "ページを開く", true)
	_primary.name = "UpdateButton"
	_primary.pressed.connect(_on_primary_pressed)
	_buttons.add_child(_primary)
	# 配布ページが分からないときは、開くボタンを出さない。
	if not _is_patch() and str(_offer.get("page_url", "")).is_empty():
		_primary.visible = false


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150.0, 46.0)
	button.add_theme_font_override("font", FONT_BOLD)
	button.add_theme_font_size_override("font_size", 18)
	var text_color := Color(0.04, 0.07, 0.12) if primary else TEXT_COLOR
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, text_color)
	button.add_theme_stylebox_override("normal", _button_box(primary, 0.0))
	button.add_theme_stylebox_override("hover", _button_box(primary, 0.12))
	button.add_theme_stylebox_override("pressed", _button_box(primary, -0.12))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color.WHITE
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(8)
	focus.set_expand_margin_all(3.0)
	button.add_theme_stylebox_override("focus", focus)
	return button


func _button_box(primary: bool, lighten: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	var base := ACCENT_COLOR if primary else Color(0.14, 0.19, 0.27)
	box.bg_color = base.lightened(lighten) if lighten >= 0.0 else base.darkened(-lighten)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10.0)
	if not primary:
		box.border_color = BORDER_COLOR
		box.set_border_width_all(1)
	return box


func _focus_default() -> void:
	if _primary != null and _primary.visible:
		_primary.grab_focus()
	elif _secondary != null:
		_secondary.grab_focus()


func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status.visible = not text.is_empty()


func _on_primary_pressed() -> void:
	if _busy:
		return
	if not _is_patch():
		OS.shell_open(str(_offer.get("page_url", "")))
		_show_status("ブラウザーで配布ページを開きました", DIM_COLOR)
		return
	_busy = true
	_buttons.visible = false
	_progress.value = 0.0
	_progress.visible = true
	_show_status("ダウンロードしています", DIM_COLOR)
	var error: String = await _updater.call("download", _offer)
	if not error.is_empty():
		_busy = false
		_progress.visible = false
		_show_status(error, ERROR_COLOR)
		_primary.text = "もう一度"
		_buttons.visible = true
		_focus_default()
		return
	_show_status("アップデートを入れました。ゲームを再起動します", TEXT_COLOR)
	# 文が読めるだけ待ってから立ち上げ直す。
	await get_tree().create_timer(1.0).timeout
	finished.emit(true)
	_updater.call("restart")


func _on_secondary_pressed() -> void:
	if _busy:
		return
	if _is_required():
		get_tree().quit()
		finished.emit(true)
		return
	finished.emit(false)


func _on_progress(downloaded: int, total: int) -> void:
	if total <= 0:
		return
	_progress.value = 100.0 * downloaded / total
	_show_status("ダウンロードしています　%s / %s" % [
		GameUpdater.format_size(downloaded), GameUpdater.format_size(total)], DIM_COLOR)
