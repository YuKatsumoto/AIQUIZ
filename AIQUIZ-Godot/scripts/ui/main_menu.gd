extends Control

## メインメニュー画面 (STAGE A: 最低限のUI)
## Python版 hud.py のメニュー部分に相当

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var mode_container: VBoxContainer = $VBoxContainer/ModeContainer
@onready var config_container: VBoxContainer = $VBoxContainer/ConfigContainer
@onready var start_button: Button = $VBoxContainer/StartButton
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

var game_state: QuizGameState

func _ready() -> void:
	game_state = QuizManager.game_state
	game_state.game_state = Constants.STATE_MENU
	game_state.menu_step = Constants.MENU_STEP_MODE
	settings_panel.visible = false
	
	vol_slider.value = AudioManager.sfx_volume
	speed_slider.value = game_state.tuning.wall_speed
	
	ApiStatusAutoload.check_completed.connect(_update_api_status_text)
	_update_ui()

func _update_ui() -> void:
	if not game_state:
		return

	game_state.refresh_status_text()
	status_label.text = game_state.status_text

	if game_state.menu_step == Constants.MENU_STEP_MODE:
		mode_container.visible = true
		config_container.visible = false
		start_button.visible = false
	elif game_state.menu_step == Constants.MENU_STEP_CONFIG:
		mode_container.visible = false
		config_container.visible = true
		start_button.visible = true

		# Update config labels
		grade_label.text = "学年: %d" % game_state.grade
		subject_label.text = "教科: %s" % game_state.subject
		diff_label.text = "難易度: %s" % game_state.difficulty
		var p_text: String = "👥 2人プレイ中" if game_state.num_players >= 2 else "👤 1人プレイ中"
		players_btn.text = p_text

		var llm_text: String = "出題: ONLINE (AI生成)" if QuizManager.provider.llm_mode == "ONLINE" else "出題: OFFLINE (内蔵問題)"
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
	settings_panel.visible = true
	_on_recheck_btn_pressed()

func _on_settings_back_btn_pressed() -> void:
	settings_panel.visible = false

func _on_recheck_btn_pressed() -> void:
	api_status_label.text = "[color=yellow]API状態チェック中...[/color]"
	ApiStatusAutoload.run_connectivity_check()

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
	
	text += "\n[color=gray]オフライン問題数: %d問[/color]" % ApiStatusAutoload.offline_count
	
	api_status_label.text = text

func _on_vol_slider_changed(value: float) -> void:
	AudioManager.set_volume(value)

func _on_speed_slider_changed(value: float) -> void:
	game_state.set_wall_speed(value)
