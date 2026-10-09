class_name SettingsHallPanel
extends Control

## 設定画面（ui/settings_hall.tscn）の左カラム。3D 無しで単体でも作れる（tests）。
## 旧 main_menu の SettingsPanel の項目を引き継ぐ: API状態と再チェック、BGM・効果音、解像度、画質、
## サドンデス（QuizGameState.sudden_death_available の時だけ、画質の行の直後）、ダッシュボード、戻る。
## API は ApiStatusAutoload の状態フラグとメッセージだけを見せる（get_env() の中身は表示しない）。
## 効果音スライダーは離したときに短い効果音を鳴らし、音量を確かめられる。
## 見出しの右の「実習場を見る」で、カメラが講義室と実習場（PracticeYard）を行き来する（view_toggled）。

signal back_requested
signal graphics_quality_changed(quality: String)
signal api_status_changed(summary: Dictionary)
signal view_toggled(practice: bool)
## 効果音の音量を変えて試し鳴らしをした（講義室の生徒が音のほうを振り向く）。
signal sfx_tested

const MenuMetalButtonScript := preload("res://scripts/ui/menu_metal_button.gd")
const FONT_BOLD: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const FONT_MEDIUM: Font = preload("res://resources/fonts/NotoSansJP-Medium.otf")

const PANEL_LEFT := 48.0
const PANEL_TOP := 28.0
const PANEL_WIDTH := 460.0
## 入場・退場（main_menu._play_entrance と同じ値）。
const SLIDE_OFFSET := 56.0
const FADE_DURATION := 0.32
const STAGGER := 0.055
## ApiStatusAutoload.check_completed は固定 3 秒で鳴るが、要求は最長 8 秒かかるので状態が決まるまで見に行く。
const API_POLL_INTERVAL := 0.25
const API_POLL_TIMEOUT := 10.0
const SUDDEN_DEATH_ON := 0
const SUDDEN_DEATH_OFF := 1
const DASHBOARD_URL := "http://localhost:3000"

const GOLD := Color(1.0, 0.88, 0.25)
const BODY := Color(0.80, 0.86, 0.96)
const MUTED := Color(0.62, 0.68, 0.78)
const DOT_OK := Color(0.35, 0.90, 0.45)
const DOT_FAIL := Color(1.0, 0.35, 0.35)
const DOT_CHECKING := Color(1.0, 0.80, 0.30)
const DOT_IDLE := Color(0.55, 0.60, 0.70)
const SUBTITLE_LECTURE := "地下神殿 講義室 ― 連結チップソー概論 開講中"
const SUBTITLE_PRACTICE := "地下神殿 実習場 ― 連結チップソー 操作実習中"
const VIEW_TO_PRACTICE := "実習場を見る ▶"
const VIEW_TO_LECTURE := "◀ 講義室へ"

var _column: VBoxContainer = null
## key -> {"dot": Label, "msg": Label}
var _api_rows: Dictionary = {}
var _offline_label: Label = null
var _recheck_btn: Button = null
var _bgm_slider: HSlider = null
var _bgm_pct: Label = null
var _sfx_slider: HSlider = null
var _sfx_pct: Label = null
var _display_rows: VBoxContainer = null
var _res_option: OptionButton = null
var _quality_option: OptionButton = null
var _sudden_death_option: OptionButton = null
var _poll_timer: Timer = null
var _poll_elapsed := 0.0
var _check_started := false
var _checking := false
var _clock := 0.0
var _subtitle: Label = null
var _view_btn: Button = null
var _practice_view := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
	offset_left = PANEL_LEFT
	offset_right = PANEL_LEFT + PANEL_WIDTH
	offset_top = PANEL_TOP
	offset_bottom = -PANEL_TOP
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column.add_theme_constant_override("separation", 10)
	add_child(_column)
	_build_title()
	_build_api_card()
	_build_audio_card()
	_build_display_card()
	_build_buttons()
	_build_hint()
	_poll_timer = Timer.new()
	_poll_timer.name = "ApiPoll"
	_poll_timer.wait_time = API_POLL_INTERVAL
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)
	if ApiStatusAutoload != null:
		ApiStatusAutoload.check_completed.connect(refresh_api_status)
	refresh_api_status()


func _exit_tree() -> void:
	if ApiStatusAutoload != null and ApiStatusAutoload.check_completed.is_connected(refresh_api_status):
		ApiStatusAutoload.check_completed.disconnect(refresh_api_status)


# ------------------------------------------------------------------ build

func _build_title() -> void:
	var block := VBoxContainer.new()
	block.name = "TitleBlock"
	block.add_theme_constant_override("separation", 2)
	_column.add_child(block)
	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("separation", 12)
	block.add_child(title_row)
	var title := Label.new()
	title.name = "Title"
	title.text = "設定"
	title.add_theme_font_override("font", FONT_BOLD)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.12, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_view_btn = _metal_button("ViewBtn", VIEW_TO_PRACTICE, false)
	_view_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_view_btn.pressed.connect(_on_view_pressed)
	title_row.add_child(_view_btn)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = SUBTITLE_LECTURE
	_subtitle = subtitle
	subtitle.add_theme_font_override("font", FONT_MEDIUM)
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", BODY)
	subtitle.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.12, 0.85))
	subtitle.add_theme_constant_override("outline_size", 5)
	block.add_child(subtitle)


func _build_api_card() -> void:
	var rows := _card("ApiCard")
	_header(rows, "API状態")
	_api_row(rows, "internet", "InternetRow", "インターネット")
	_api_row(rows, "gateway", "GatewayRow", "AI Gateway")
	_api_row(rows, "firebase", "FirebaseRow", "Firebase")
	_offline_label = Label.new()
	_offline_label.name = "OfflineRow"
	_offline_label.add_theme_font_override("font", FONT_MEDIUM)
	_offline_label.add_theme_font_size_override("font_size", 15)
	_offline_label.add_theme_color_override("font_color", MUTED)
	rows.add_child(_offline_label)
	var button_row := HBoxContainer.new()
	button_row.name = "RecheckRow"
	button_row.alignment = BoxContainer.ALIGNMENT_END
	rows.add_child(button_row)
	_recheck_btn = _metal_button("RecheckBtn", "再チェック", false)
	_recheck_btn.pressed.connect(begin_api_check)
	button_row.add_child(_recheck_btn)


func _api_row(rows: VBoxContainer, key: String, node_name: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 8)
	rows.add_child(row)
	var dot := Label.new()
	dot.name = "Dot"
	dot.text = "●"
	dot.add_theme_font_size_override("font_size", 18)
	dot.add_theme_color_override("font_color", DOT_IDLE)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = title
	name_label.custom_minimum_size = Vector2(124.0, 0.0)
	name_label.add_theme_font_override("font", FONT_MEDIUM)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", BODY)
	row.add_child(name_label)
	var msg := Label.new()
	msg.name = "Message"
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.clip_text = true
	msg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	msg.add_theme_font_override("font", FONT_MEDIUM)
	msg.add_theme_font_size_override("font_size", 16)
	msg.add_theme_color_override("font_color", MUTED)
	row.add_child(msg)
	_api_rows[key] = {"dot": dot, "msg": msg}


func _build_audio_card() -> void:
	var rows := _card("AudioCard")
	_header(rows, "音量")
	var bgm := _slider_row(rows, "BgmVolBox", "BgmVolSlider", "BGM音量", AudioManager.bgm_volume)
	_bgm_slider = bgm.slider
	_bgm_pct = bgm.pct
	_bgm_slider.value_changed.connect(_on_bgm_changed)
	var sfx := _slider_row(rows, "VolBox", "VolSlider", "効果音量", AudioManager.sfx_volume)
	_sfx_slider = sfx.slider
	_sfx_pct = sfx.pct
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_sfx_slider.drag_ended.connect(_on_sfx_drag_ended)


func _slider_row(rows: VBoxContainer, row_name: String, slider_name: String, title: String, value: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 10)
	rows.add_child(row)
	var label := Label.new()
	label.name = "Label"
	label.text = title
	label.custom_minimum_size = Vector2(100.0, 0.0)
	label.add_theme_font_override("font", FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", BODY)
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(200.0, 0.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var pct := Label.new()
	pct.name = "Percent"
	pct.custom_minimum_size = Vector2(48.0, 0.0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.add_theme_font_override("font", FONT_MEDIUM)
	pct.add_theme_font_size_override("font_size", 15)
	pct.add_theme_color_override("font_color", MUTED)
	pct.text = _percent(value)
	row.add_child(pct)
	return {"slider": slider, "pct": pct}


func _build_display_card() -> void:
	_display_rows = _card("DisplayCard")
	_header(_display_rows, "画面")
	# 解像度（main_menu と同じ項目と初期選択）
	var res_row := _option_row("ResolutionBox", "解像度", "ResOption")
	_res_option = res_row.get_node("ResOption") as OptionButton
	_res_option.add_item("1280x720 (HD)", 0)
	_res_option.add_item("1920x1080 (FHD)", 1)
	_res_option.add_item("2560x1440 (WQHD)", 2)
	_res_option.add_item("3840x2160 (4K)", 3)
	_res_option.add_item("フルスクリーン", 4)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		_res_option.select(4)
	else:
		var w := DisplayServer.window_get_size().x
		if w >= 3840:
			_res_option.select(3)
		elif w >= 2560:
			_res_option.select(2)
		elif w >= 1920:
			_res_option.select(1)
		else:
			_res_option.select(0)
	_res_option.item_selected.connect(_on_resolution_selected)
	# 画質（軽量 / 標準 / 高画質 / 最高画質。項目番号 = GraphicsQuality.rank）
	var quality_row := _option_row("GraphicsQualityBox", "画質", "GraphicsQualityOption")
	_quality_option = quality_row.get_node("GraphicsQualityOption") as OptionButton
	for index: int in range(GraphicsQuality.VALID_QUALITIES.size()):
		_quality_option.add_item(GraphicsQuality.display_name(GraphicsQuality.VALID_QUALITIES[index]), index)
	_quality_option.select(GraphicsQuality.rank(GameManager.graphics_quality))
	_quality_option.item_selected.connect(_on_quality_selected)
	# サドンデス（廃止中は出さない。画質の行のすぐ下、同じ見た目）
	if QuizGameState.sudden_death_available:
		var sudden_row := _option_row("SuddenDeathBox", "サドンデス（2P 10問の引き分け）", "SuddenDeathOption")
		_sudden_death_option = sudden_row.get_node("SuddenDeathOption") as OptionButton
		_sudden_death_option.add_item("オン", SUDDEN_DEATH_ON)
		_sudden_death_option.add_item("オフ", SUDDEN_DEATH_OFF)
		_sudden_death_option.select(_sudden_death_option.get_item_index(
			SUDDEN_DEATH_ON if GameManager.sudden_death_enabled else SUDDEN_DEATH_OFF))
		_sudden_death_option.item_selected.connect(_on_sudden_death_selected)


func _option_row(row_name: String, title: String, option_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 12)
	_display_rows.add_child(row)
	var label := Label.new()
	label.name = "Label"
	label.text = title
	label.custom_minimum_size = Vector2(120.0, 0.0)
	label.add_theme_font_override("font", FONT_MEDIUM)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", BODY)
	row.add_child(label)
	var option := OptionButton.new()
	option.name = option_name
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_override("font", FONT_MEDIUM)
	option.add_theme_font_size_override("font_size", 18)
	_style_plain_button(option)
	row.add_child(option)
	return row


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.name = "ButtonRow"
	row.add_theme_constant_override("separation", 12)
	_column.add_child(row)
	var dashboard := _metal_button("DashboardBtn", "ダッシュボードを開く", false)
	dashboard.pressed.connect(_on_dashboard_pressed)
	row.add_child(dashboard)
	var back := _metal_button("BackBtn", "メニューへ戻る", true)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_on_back_pressed)
	row.add_child(back)


func _build_hint() -> void:
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Esc で戻る"
	hint.add_theme_font_override("font", FONT_MEDIUM)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", MUTED)
	_column.add_child(hint)


func _card(node_name: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.105, 0.80)
	style.border_color = Color(0.35, 0.56, 0.96, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	_column.add_child(panel)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	return rows


func _header(rows: VBoxContainer, text: String) -> void:
	var header := Label.new()
	header.name = "Header"
	header.text = text
	header.add_theme_font_override("font", FONT_BOLD)
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", MUTED)
	rows.add_child(header)


func _metal_button(node_name: String, text: String, featured: bool) -> Button:
	var button := MenuMetalButtonScript.new() as Button
	button.name = node_name
	button.text = text
	button.set("compact", true)
	button.set("featured", featured)
	button.add_theme_font_size_override("font_size", 16)
	return button


## OptionButton に main_menu._style_all_buttons と同じ暗い配色。
func _style_plain_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.16, 0.22)
	normal.border_color = Color(0.28, 0.32, 0.42)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.20, 0.28)
	hover.border_color = Color(0.4, 0.5, 0.7)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.10, 0.12, 0.18)
	pressed.border_color = Color(0.35, 0.45, 0.65)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
	button.add_theme_color_override("font_hover_color", Color(0.95, 0.97, 1.0))


# ------------------------------------------------------------------ API status

## テスト用: 画面の行（ResolutionBox / GraphicsQualityBox / SuddenDeathBox）を持つ VBox。
func display_rows() -> VBoxContainer:
	return _display_rows


func begin_api_check() -> void:
	if ApiStatusAutoload == null:
		return
	_check_started = true
	_checking = true
	_poll_elapsed = 0.0
	ApiStatusAutoload.run_connectivity_check()
	refresh_api_status()
	if is_inside_tree():
		_poll_timer.start()


func _on_poll() -> void:
	_poll_elapsed += API_POLL_INTERVAL
	var settled := not ApiStatusAutoload.checking and not _any_status_pending()
	if settled or _poll_elapsed >= API_POLL_TIMEOUT:
		_poll_timer.stop()
		_checking = false
	refresh_api_status()


func _any_status_pending() -> bool:
	return ApiStatusAutoload.internet_ok == null or ApiStatusAutoload.proxy_status == null or ApiStatusAutoload.firebase_status == null


func is_checking() -> bool:
	return _checking


## ApiStatusAutoload の今の状態を行に写し、api_status_changed を出す。
func refresh_api_status() -> void:
	if ApiStatusAutoload == null:
		return
	var checked := _check_started or ApiStatusAutoload.internet_msg != "未チェック"
	_set_api_row("internet", ApiStatusAutoload.internet_ok, ApiStatusAutoload.internet_msg, checked, true)
	var gateway_msg: String = ApiStatusAutoload.proxy_msg
	if ApiStatusAutoload.proxy_configured and not ApiStatusAutoload.gemini_model.is_empty():
		gateway_msg += " · " + ApiStatusAutoload.gemini_model
	else:
		gateway_msg += "（PROXY_URL %s）" % ("設定済" if ApiStatusAutoload.proxy_configured else "未設定")
	_set_api_row("gateway", ApiStatusAutoload.proxy_status, gateway_msg, checked, ApiStatusAutoload.proxy_configured)
	var firebase_msg: String = "%s（DB URL %s）" % [ApiStatusAutoload.firebase_msg, "設定済" if ApiStatusAutoload.firebase_configured else "未設定"]
	_set_api_row("firebase", ApiStatusAutoload.firebase_status, firebase_msg, checked, ApiStatusAutoload.firebase_configured)
	_offline_label.text = "オフライン問題数: %d問" % ApiStatusAutoload.offline_count
	if _recheck_btn != null:
		_recheck_btn.disabled = _checking
		_recheck_btn.text = "チェック中…" if _checking else "再チェック"
	api_status_changed.emit(api_summary())


func _set_api_row(key: String, status: Variant, message: String, checked: bool, configured: bool) -> void:
	var row: Dictionary = _api_rows.get(key, {})
	if row.is_empty():
		return
	var dot := row.dot as Label
	var msg := row.msg as Label
	msg.text = message
	var color := DOT_IDLE
	if checked:
		if status == null:
			color = DOT_CHECKING if configured else DOT_FAIL
		else:
			color = DOT_OK if bool(status) else DOT_FAIL
	dot.add_theme_color_override("font_color", color)
	dot.set_meta("pulse", checked and status == null and configured)
	msg.add_theme_color_override("font_color", BODY if checked else MUTED)


## 3D 側（黒板・ランプ）へ渡すまとめ。null = 不明 / チェック中、true = OK、false = 失敗。
func api_summary() -> Dictionary:
	if ApiStatusAutoload == null:
		return {}
	return {
		"checked": _check_started or ApiStatusAutoload.internet_msg != "未チェック",
		"checking": _checking,
		"internet": ApiStatusAutoload.internet_ok,
		"gateway": ApiStatusAutoload.proxy_status,
		"firebase": ApiStatusAutoload.firebase_status,
		"gateway_configured": ApiStatusAutoload.proxy_configured,
		"firebase_configured": ApiStatusAutoload.firebase_configured,
		"offline_count": ApiStatusAutoload.offline_count,
		"internet_msg": ApiStatusAutoload.internet_msg,
		"gateway_msg": ApiStatusAutoload.proxy_msg,
		"firebase_msg": ApiStatusAutoload.firebase_msg,
	}


func _process(delta: float) -> void:
	_clock += delta
	if not _checking:
		return
	var alpha := 0.6 + 0.4 * sin(_clock * TAU * 1.5)
	for key: String in _api_rows:
		var dot := (_api_rows[key] as Dictionary).dot as Label
		dot.modulate.a = alpha if bool(dot.get_meta("pulse", false)) else 1.0


# ------------------------------------------------------------------ handlers (ported from main_menu.gd)

func _on_bgm_changed(value: float) -> void:
	AudioManager.set_bgm_volume(value)
	_bgm_pct.text = _percent(value)


func _on_sfx_changed(value: float) -> void:
	AudioManager.set_sfx_volume(value)
	_sfx_pct.text = _percent(value)


func _on_sfx_drag_ended(value_changed: bool) -> void:
	if value_changed:
		sfx_tested.emit()


func _on_quality_selected(index: int) -> void:
	var quality: String = GraphicsQuality.BALANCED
	if index >= 0 and index < GraphicsQuality.VALID_QUALITIES.size():
		quality = GraphicsQuality.VALID_QUALITIES[index]
	GameManager.set_graphics_quality(quality)
	graphics_quality_changed.emit(quality)


func _on_sudden_death_selected(index: int) -> void:
	if _sudden_death_option == null:
		return
	GameManager.set_sudden_death_enabled(_sudden_death_option.get_item_id(index) == SUDDEN_DEATH_ON)


func _on_resolution_selected(index: int) -> void:
	if index == 4:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	match index:
		0:
			DisplayServer.window_set_size(Vector2i(1280, 720))
		1:
			DisplayServer.window_set_size(Vector2i(1920, 1080))
		2:
			DisplayServer.window_set_size(Vector2i(2560, 1440))
		3:
			DisplayServer.window_set_size(Vector2i(3840, 2160))
	# ウィンドウを今の画面の中央へ
	var screen_idx := DisplayServer.window_get_current_screen()
	var screen_pos := DisplayServer.screen_get_position(screen_idx)
	var screen_size := DisplayServer.screen_get_size(screen_idx)
	var win_size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(screen_pos + (screen_size - win_size) / 2)


func _on_dashboard_pressed() -> void:
	OS.shell_open(DASHBOARD_URL)


func _on_view_pressed() -> void:
	set_practice_view(not _practice_view)


## 視点の表示を切り替えて知らせる（ボタンの文字と副題）。
func set_practice_view(practice: bool) -> void:
	_practice_view = practice
	if _view_btn != null:
		_view_btn.text = VIEW_TO_LECTURE if practice else VIEW_TO_PRACTICE
	if _subtitle != null:
		_subtitle.text = SUBTITLE_PRACTICE if practice else SUBTITLE_LECTURE
	view_toggled.emit(practice)


func is_practice_view() -> bool:
	return _practice_view


func _on_back_pressed() -> void:
	back_requested.emit()


# ------------------------------------------------------------------ transitions

## 子要素を左からスライド＋段階フェードで順に出す。await 可（最後の要素まで）。
func play_entrance() -> void:
	modulate.a = 0.0
	await get_tree().process_frame
	if not is_inside_tree() or _column == null:
		return
	var items := _visible_items()
	for item in items:
		item.modulate.a = 0.0
	modulate.a = 1.0
	var index := 0
	var last_tween: Tween = null
	for item in items:
		var target_x := item.position.x
		item.position.x = target_x - SLIDE_OFFSET
		var delay := float(index) * STAGGER
		var tw := create_tween()
		tw.set_parallel(true)
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(item, "modulate:a", 1.0, FADE_DURATION).set_delay(delay)
		tw.tween_property(item, "position:x", target_x, FADE_DURATION).set_delay(delay)
		last_tween = tw
		index += 1
	if last_tween != null:
		await last_tween.finished


## 退場: 左へ流れて消える。await 可。
func play_exit(seconds: float = 0.25) -> void:
	set_interactive(false)
	var items := _visible_items()
	if items.is_empty() or not is_inside_tree():
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	for item in items:
		tw.tween_property(item, "modulate:a", 0.0, seconds)
		tw.tween_property(item, "position:x", item.position.x - SLIDE_OFFSET, seconds)
	await tw.finished


func set_interactive(on: bool) -> void:
	_set_interactive_in(_column, on)


func _set_interactive_in(node: Node, on: bool) -> void:
	if node == null:
		return
	if node is Button:
		(node as Button).disabled = not on
	elif node is Slider:
		(node as Slider).editable = on
	for child in node.get_children():
		_set_interactive_in(child, on)


func _visible_items() -> Array[Control]:
	var items: Array[Control] = []
	if _column == null:
		return items
	for child in _column.get_children():
		if child is Control and (child as Control).visible:
			items.append(child as Control)
	return items


static func _percent(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))
