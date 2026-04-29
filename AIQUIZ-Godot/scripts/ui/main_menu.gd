extends Control

## メインメニュー画面 (STAGE A: 最低限のUI)
## Python版 hud.py のメニュー部分に相当

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var mode_container: VBoxContainer = $VBoxContainer/ModeContainer
@onready var config_container: VBoxContainer = $VBoxContainer/ConfigContainer
@onready var start_button: Button = $VBoxContainer/ConfigContainer/ConfigBtnRow/StartButton
@onready var tutorial_button: Button = %TutorialButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var grade_label: Label = $VBoxContainer/ConfigContainer/QuizSettingsCard/QuizSettingsVBox/GradeRow/GradeLabel
@onready var subject_label: Label = $VBoxContainer/ConfigContainer/QuizSettingsCard/QuizSettingsVBox/SubjectRow/SubjectLabel
@onready var diff_label: Label = $VBoxContainer/ConfigContainer/QuizSettingsCard/QuizSettingsVBox/DiffRow/DiffLabel
@onready var players_btn: Button = %PlayersToggleBtn
@onready var llm_toggle_btn: Button = %LlmToggleBtn
@onready var wall_speed_btn: Button = %WallSpeedBtn
@onready var quiz_settings_card: PanelContainer = $VBoxContainer/ConfigContainer/QuizSettingsCard
@onready var game_settings_card: PanelContainer = $VBoxContainer/ConfigContainer/GameSettingsCard

@onready var settings_panel: Panel = $SettingsPanel
@onready var api_status_label: RichTextLabel = $SettingsPanel/VBox/ApiStatusLabel
@onready var vol_slider: HSlider = $SettingsPanel/VBox/VolBox/VolSlider
# speed_slider は廃止（壁速度は難易度から自動決定）
@onready var res_option: OptionButton = %ResOption

var game_state: QuizGameState

func _ready() -> void:
	game_state = QuizManager.game_state
	game_state.game_state = Constants.STATE_MENU
	# 戻るボタン等からの遷移時に状態を保持するため、menu_stepの強制リセットを削除
	settings_panel.visible = false
	
	vol_slider.value = AudioManager.sfx_volume

	
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
	_style_config_cards()
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

	# チュートリアルボタン（視認しやすい緑系アクセント）
	var tutorial_normal := StyleBoxFlat.new()
	tutorial_normal.bg_color = Color(0.12, 0.42, 0.30)
	tutorial_normal.border_color = Color(0.22, 0.68, 0.48)
	tutorial_normal.set_border_width_all(2)
	tutorial_normal.set_corner_radius_all(10)
	tutorial_normal.content_margin_left = 18.0
	tutorial_normal.content_margin_right = 18.0
	tutorial_normal.content_margin_top = 8.0
	tutorial_normal.content_margin_bottom = 8.0

	var tutorial_hover := tutorial_normal.duplicate()
	tutorial_hover.bg_color = Color(0.16, 0.5, 0.36)
	tutorial_hover.border_color = Color(0.30, 0.82, 0.58)

	tutorial_button.add_theme_stylebox_override("normal", tutorial_normal)
	tutorial_button.add_theme_stylebox_override("hover", tutorial_hover)
	tutorial_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	tutorial_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

func _get_all_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		buttons.append_array(_get_all_buttons(child))
	return buttons

func _style_config_cards() -> void:
	"""クイズ設定・ゲーム設定カードに角丸ダーク背景を適用"""
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.11, 0.13, 0.19, 0.85)
	card_style.border_color = Color(0.25, 0.30, 0.45, 0.6)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(14)
	card_style.content_margin_left = 20.0
	card_style.content_margin_right = 20.0
	card_style.content_margin_top = 14.0
	card_style.content_margin_bottom = 14.0
	
	if quiz_settings_card:
		quiz_settings_card.add_theme_stylebox_override("panel", card_style.duplicate())
	if game_settings_card:
		var game_card_style := card_style.duplicate()
		game_card_style.border_color = Color(0.3, 0.25, 0.45, 0.6)
		game_settings_card.add_theme_stylebox_override("panel", game_card_style)
	
	# ◀▶ ボタンにアクセントカラーを適用
	var arrow_normal := StyleBoxFlat.new()
	arrow_normal.bg_color = Color(0.15, 0.22, 0.38)
	arrow_normal.border_color = Color(0.3, 0.45, 0.7)
	arrow_normal.set_border_width_all(1)
	arrow_normal.set_corner_radius_all(8)
	arrow_normal.content_margin_left = 6.0
	arrow_normal.content_margin_right = 6.0
	arrow_normal.content_margin_top = 4.0
	arrow_normal.content_margin_bottom = 4.0
	
	var arrow_hover := arrow_normal.duplicate()
	arrow_hover.bg_color = Color(0.2, 0.3, 0.5)
	arrow_hover.border_color = Color(0.4, 0.6, 0.9)
	
	var arrow_btns: Array[Button] = []
	for name_str in ["GradeDownBtn", "GradeUpBtn", "SubjectLeftBtn", "SubjectRightBtn", "DiffLeftBtn", "DiffRightBtn"]:
		var btn := get_node_or_null("%%%s" % name_str) as Button
		if btn:
			arrow_btns.append(btn)
	
	for btn in arrow_btns:
		btn.add_theme_stylebox_override("normal", arrow_normal.duplicate())
		btn.add_theme_stylebox_override("hover", arrow_hover.duplicate())
		btn.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.85, 0.92, 1.0))

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
		
		
		# Update wall speed button label
		if wall_speed_btn:
			if game_state.tuning.wall_speed_override > 0:
				wall_speed_btn.text = "⚡ 壁速度: %.1f（手動）" % game_state.tuning.wall_speed_override
			else:
				wall_speed_btn.text = "⚡ 壁速度設定（自動）"
		
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

func _on_wall_speed_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/wall_speed_settings.tscn")

func _on_hat_select_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/hat_select.tscn")

func _on_emote_select_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/emote_select.tscn")

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

func _on_tutorial_button_pressed() -> void:
	# チュートリアルは1P前提で実行する
	game_state.num_players = 1
	# 途中で完了済みでも、ボタンから再実行できるようにする
	if game_state.has_method("reset_tutorial_progress"):
		game_state.reset_tutorial_progress()
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
	
	var proxy := ApiStatusAutoload.get_env("PROXY_URL")
	if not proxy.is_empty():
		# プロキシ稼働時はAI Gatewayとして表示（内部チェックはgemini_statusを使用）
		var p_col = "green" if ApiStatusAutoload.gemini_status else ("red" if ApiStatusAutoload.gemini_status == false else "yellow")
		text += "[color=%s]AI Gateway (Proxy): %s[/color] (設定済)\n" % [p_col, ApiStatusAutoload.gemini_msg]
	else:
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

# _on_speed_slider_changed は廃止（壁速度は難易度から自動決定）

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
