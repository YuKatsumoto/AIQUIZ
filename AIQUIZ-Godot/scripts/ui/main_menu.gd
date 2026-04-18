extends Control

## メインメニュー画面 (STAGE A: 最低限のUI)
## Python版 hud.py のメニュー部分に相当

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var mode_container: VBoxContainer = $VBoxContainer/ModeContainer
@onready var config_container: VBoxContainer = $VBoxContainer/ConfigContainer
@onready var start_button: Button = $VBoxContainer/ConfigContainer/ConfigBtnRow/StartButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var grade_label: Label = $VBoxContainer/ConfigContainer/GradeRow/GradeLabel
@onready var subject_label: Label = $VBoxContainer/ConfigContainer/SubjectRow/SubjectLabel
@onready var diff_label: Label = $VBoxContainer/ConfigContainer/DiffRow/DiffLabel
@onready var players_btn: Button = $VBoxContainer/ConfigContainer/PlayersRow/PlayersToggleBtn
@onready var llm_toggle_btn: Button = $VBoxContainer/ConfigContainer/LlmRow/LlmToggleBtn

@onready var settings_panel: Panel = $SettingsPanel
@onready var api_status_label: RichTextLabel = $SettingsPanel/VBox/ApiStatusLabel
@onready var vol_slider: HSlider = $SettingsPanel/VBox/VolBox/VolSlider
@onready var speed_slider: HSlider = $SettingsPanel/VBox/SpeedBox/SpeedSlider
@onready var res_option: OptionButton = %ResOption

var game_state: QuizGameState

# Filter state


func _ready() -> void:
	game_state = QuizManager.game_state
	game_state.game_state = Constants.STATE_MENU
	game_state.menu_step = Constants.MENU_STEP_MODE
	settings_panel.visible = false
	
	vol_slider.value = AudioManager.sfx_volume
	speed_slider.value = game_state.tuning.wall_speed
	
	res_option.item_selected.connect(_on_resolution_selected)
	res_option.add_item("1280x720 (HD)", 0)
	res_option.add_item("1920x1080 (FHD)", 1)
	res_option.add_item("2560x1440 (WQHD)", 2)
	res_option.add_item("3840x2160 (4K)", 3)
	res_option.add_item("フルスクリーン", 4)
	
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		res_option.select(4)
	else:
		var w = DisplayServer.window_get_size().x
		if w >= 3840:
			res_option.select(3)
		elif w >= 2560:
			res_option.select(2)
		elif w >= 1920:
			res_option.select(1)
		else:
			res_option.select(0)
	
	ApiStatusAutoload.check_completed.connect(_update_api_status_text)
	_style_all_buttons()
	_update_ui()


func _style_all_buttons() -> void:
	"""全ボタンにダークテーマのスタイルを動的に適用"""
	# 通常ボタンのスタイル
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.14, 0.16, 0.22)
	normal_style.border_color = Color(0.28, 0.32, 0.42)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(10)
	normal_style.content_margin_left = 16.0
	normal_style.content_margin_right = 16.0
	normal_style.content_margin_top = 8.0
	normal_style.content_margin_bottom = 8.0
	
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.18, 0.20, 0.28)
	hover_style.border_color = Color(0.4, 0.5, 0.7)
	hover_style.set_border_width_all(1)
	hover_style.set_corner_radius_all(10)
	hover_style.content_margin_left = 16.0
	hover_style.content_margin_right = 16.0
	hover_style.content_margin_top = 8.0
	hover_style.content_margin_bottom = 8.0
	
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.10, 0.12, 0.18)
	pressed_style.border_color = Color(0.35, 0.45, 0.65)
	pressed_style.set_border_width_all(1)
	pressed_style.set_corner_radius_all(10)
	pressed_style.content_margin_left = 16.0
	pressed_style.content_margin_right = 16.0
	pressed_style.content_margin_top = 8.0
	pressed_style.content_margin_bottom = 8.0
	
	# 全ボタンを再帰的に取得してスタイル適用
	var all_buttons := _get_all_buttons(self)
	for btn: Button in all_buttons:
		btn.add_theme_stylebox_override("normal", normal_style.duplicate())
		btn.add_theme_stylebox_override("hover", hover_style.duplicate())
		btn.add_theme_stylebox_override("pressed", pressed_style.duplicate())
		btn.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
		btn.add_theme_color_override("font_hover_color", Color(0.95, 0.97, 1.0))
	
	# スタートボタンにアクセントカラー
	var start_normal := StyleBoxFlat.new()
	start_normal.bg_color = Color(0.15, 0.35, 0.65)
	start_normal.border_color = Color(0.3, 0.55, 0.9)
	start_normal.set_border_width_all(2)
	start_normal.set_corner_radius_all(12)
	start_normal.content_margin_left = 20.0
	start_normal.content_margin_right = 20.0
	start_normal.content_margin_top = 10.0
	start_normal.content_margin_bottom = 10.0
	
	var start_hover := start_normal.duplicate()
	start_hover.bg_color = Color(0.2, 0.42, 0.75)
	start_hover.border_color = Color(0.4, 0.65, 1.0)
	
	start_button.add_theme_stylebox_override("normal", start_normal)
	start_button.add_theme_stylebox_override("hover", start_hover)
	start_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	start_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

func _get_all_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		buttons.append_array(_get_all_buttons(child))
	return buttons
func _update_ui() -> void:
	if not game_state:
		return

	game_state.refresh_status_text()
	status_label.text = game_state.status_text

	if game_state.menu_step == Constants.MENU_STEP_MODE:
		mode_container.visible = true
		config_container.visible = false
	elif game_state.menu_step == Constants.MENU_STEP_CONFIG:
		mode_container.visible = false
		config_container.visible = true

		# Update config labels
		grade_label.text = "📚 %d年生" % game_state.grade
		subject_label.text = "📖 %s" % game_state.subject
		diff_label.text = "⚡ %s" % game_state.difficulty
		var p_text: String = "👥 2人プレイ" if game_state.num_players >= 2 else "👤 1人プレイ"
		players_btn.text = p_text

		var llm_text: String = "🌐 ONLINE (AI生成)" if QuizManager.provider.llm_mode == "ONLINE" else "📦 OFFLINE (内蔵問題)"
		llm_toggle_btn.text = llm_text

func _on_ten_questions_pressed() -> void:
	game_state.select_mode_and_continue(Constants.MODE_TEN)
	_update_ui()

func _on_endless_pressed() -> void:
	game_state.select_mode_and_continue(Constants.MODE_ENDLESS)
	_update_ui()

func _on_back_pressed() -> void:
	game_state.back_to_mode_select()
	_update_ui()

func _on_llm_toggle_pressed() -> void:
	var new_mode := "ONLINE" if QuizManager.provider.llm_mode == "OFFLINE" else "OFFLINE"
	QuizManager.provider.set_llm_mode(new_mode)
	_update_ui()

func _on_players_toggle_pressed() -> void:
	game_state.num_players = 2 if game_state.num_players == 1 else 1
	_update_ui()

func _on_grade_down_pressed() -> void:
	game_state.update_grade(-1)
	_update_ui()

func _on_grade_up_pressed() -> void:
	game_state.update_grade(1)
	_update_ui()

func _on_subject_left_pressed() -> void:
	game_state.cycle_subject(-1)
	_update_ui()

func _on_subject_right_pressed() -> void:
	game_state.cycle_subject(1)
	_update_ui()

func _on_diff_left_pressed() -> void:
	game_state.cycle_difficulty(-1)
	_update_ui()

func _on_diff_right_pressed() -> void:
	game_state.cycle_difficulty(1)
	_update_ui()

func _on_start_pressed() -> void:
	game_state.start_game()
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")

# --- Settings ---

func _on_settings_btn_pressed() -> void:
	_show_panel_animated(settings_panel)
	_on_recheck_btn_pressed()

func _on_settings_back_btn_pressed() -> void:
	_hide_panel_animated(settings_panel)

func _on_recheck_btn_pressed() -> void:
	api_status_label.text = "[color=yellow]API状態チェック中...[/color]"
	ApiStatusAutoload.run_connectivity_check()

func _on_open_dashboard_pressed() -> void:
	# Opens the locally running Next.js dashboard in the default browser
	OS.shell_open("http://localhost:3000")

func _update_api_status_text() -> void:
	var text := ""
	
	var i_col = "green" if ApiStatusAutoload.internet_ok else ("red" if ApiStatusAutoload.internet_ok == false else "yellow")
	text += "[color=%s]インターネット: %s[/color]\n" % [i_col, ApiStatusAutoload.internet_msg]
	
	var o_col = "green" if ApiStatusAutoload.openai_status else ("red" if ApiStatusAutoload.openai_status == false else "yellow")
	var o_key = "設定済" if ApiStatusAutoload.openai_key_set else "未設定"
	text += "[color=%s]OpenAI: %s[/color] (キー: %s)\n" % [o_col, ApiStatusAutoload.openai_msg, o_key]
	
	var g_col = "green" if ApiStatusAutoload.gemini_status else ("red" if ApiStatusAutoload.gemini_status == false else "yellow")
	var g_key = "設定済" if ApiStatusAutoload.gemini_key_set else "未設定"
	text += "[color=%s]Gemini: %s[/color] (キー: %s)\n" % [g_col, ApiStatusAutoload.gemini_msg, g_key]
	
	var f_col = "green" if ApiStatusAutoload.firebase_status else ("red" if ApiStatusAutoload.firebase_status == false else "yellow")
	var f_key = "設定済" if ApiStatusAutoload.firebase_configured else "未設定"
	text += "[color=%s]Firebase: %s[/color] (DB URL: %s)\n" % [f_col, ApiStatusAutoload.firebase_msg, f_key]
	
	text += "\n[color=gray]オフライン問題数: %d問[/color]" % ApiStatusAutoload.offline_count
	
	api_status_label.text = text

func _on_vol_slider_changed(value: float) -> void:
	AudioManager.set_volume(value)

func _on_speed_slider_changed(value: float) -> void:
	game_state.set_wall_speed(value)

func _on_resolution_selected(index: int) -> void:
	if index == 4:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
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
		
		# Center the window on the current screen
		var screen_idx = DisplayServer.window_get_current_screen()
		var screen_pos = DisplayServer.screen_get_position(screen_idx)
		var screen_size = DisplayServer.screen_get_size(screen_idx)
		var win_size = DisplayServer.window_get_size()
		DisplayServer.window_set_position(screen_pos + (screen_size - win_size) / 2)



func _show_panel_animated(panel: Control, duration: float = 0.3) -> void:
	panel.visible = true
	panel.modulate.a = 1.0
	panel.scale = Vector2.ONE

func _hide_panel_animated(panel: Control, duration: float = 0.25) -> void:
	panel.visible = false
