extends Control

## メインメニュー画面 (STAGE A: 最低限のUI)
## Python版 hud.py のメニュー部分に相当

@onready var title_label: Label = $VBoxContainer/TitleRow/TitleLabel
@onready var background_overlay: ColorRect = $Background
@onready var menu_vbox: VBoxContainer = $VBoxContainer
@onready var live_background: SubViewportContainer = $LiveBackground
@onready var live_viewport: SubViewport = $LiveBackground/LiveViewport
@onready var live_camera: Camera3D = $LiveBackground/LiveViewport/LiveCamera
@onready var announcement_label: RichTextLabel = %AnnouncementLabel
@onready var mode_container: VBoxContainer = $VBoxContainer/ModeContainer
@onready var config_container: VBoxContainer = $VBoxContainer/ConfigContainer
@onready var start_button: Button = $VBoxContainer/ConfigContainer/ConfigBtnRow/StartButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var prev_grade_btn: Button = %PrevGradeBtn
@onready var current_grade_label: Label = %CurrentGradeLabel
@onready var next_grade_btn: Button = %NextGradeBtn
@onready var prev_subject_btn: Button = %PrevSubjectBtn
@onready var next_subject_btn: Button = %NextSubjectBtn
@onready var current_subject_label: Label = %CurrentSubjectLabel
@onready var prev_diff_btn: Button = %PrevDiffBtn
@onready var current_diff_label: Label = %CurrentDiffLabel
@onready var next_diff_btn: Button = %NextDiffBtn
@onready var players_btn: Button = %PlayersToggleBtn
@onready var llm_toggle_btn: Button = %LlmToggleBtn
@onready var customize_btn: Button = %CustomizeBtn

@onready var settings_panel: Panel = $SettingsPanel
@onready var settings_btn: Button = %SettingsBtn
@onready var api_status_label: RichTextLabel = $SettingsPanel/VBox/ApiStatusLabel
@onready var vol_slider: HSlider = $SettingsPanel/VBox/VolBox/VolSlider
# speed_slider は廃止（壁速度は難易度から自動決定）
@onready var res_option: OptionButton = %ResOption
@onready var model_option: OptionButton = %ModelOption

var game_state: QuizGameState
var _tutorial_row: HBoxContainer = null
var _tutorial_btn: Button = null
var _tutorial_2p_btn: Button = null

const PICKER_HEIGHT := 52.0
const PICKER_ANIM_DURATION := 0.18
const SHOW_COOP_MODE := false
const GAME_WORLD_SCENE: PackedScene = preload("res://scenes/game_world.tscn")
const CUSTOMIZE_SETTINGS_SCENE: PackedScene = preload("res://ui/customize_settings.tscn")
const MenuWallBackgroundPreviewScene := preload("res://scripts/ui/menu_wall_background_preview.gd")

# --- 推移アニメーション設定 ---
const ANIM_SLIDE_OFFSET := 56.0
const ANIM_FADE_DURATION := 0.32
const ANIM_STAGGER := 0.055
const MENU_EXIT_DURATION := 0.34
const MENU_EXIT_OFFSET_X := -520.0

var _prev_menu_step: String = ""
var _entrance_done: bool = false
var _menu_wall_preview: Node = null
var _menu_exit_in_progress: bool = false
var _menu_exit_targets: Array[Control] = []
var _embedded_customize: Control = null
var _embedded_customize_open: bool = false

func _ready() -> void:
	game_state = QuizManager.game_state
	_hide_coop_mode_if_disabled()
	game_state.game_state = Constants.STATE_MENU
	# 戻るボタン等からの遷移時に状態を保持するため、menu_stepの強制リセットを削除
	settings_panel.visible = false
	_setup_live_background()
	_setup_menu_exit_targets()
	_setup_embedded_customize()
	_reset_menu_visual_state()
	SceneTransition.reveal_current()

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

	model_option.item_selected.connect(_on_model_selected)
	model_option.add_item("gemini-3-flash-preview", 0)
	model_option.add_item("gemini-3.1-pro-preview", 1)
	model_option.add_item("gemini-3.1-flash-lite", 2)
	match ApiStatusAutoload.gemini_model:
		"gemini-3-flash-preview": model_option.select(0)
		"gemini-3.1-pro-preview": model_option.select(1)
		"gemini-3.1-flash-lite": model_option.select(2)
		_:
			model_option.add_item(ApiStatusAutoload.gemini_model, 3)
			model_option.select(3)

	ApiStatusAutoload.check_completed.connect(_update_api_status_text)
	
	LiveConfigManager.config_updated.connect(_on_live_config_updated)
	_on_live_config_updated()

	_ensure_tutorial_button()
	_style_all_buttons()
	
	prev_grade_btn.pressed.connect(_on_prev_grade_pressed)
	next_grade_btn.pressed.connect(_on_next_grade_pressed)
	prev_subject_btn.pressed.connect(_on_prev_subject_pressed)
	next_subject_btn.pressed.connect(_on_next_subject_pressed)
	prev_diff_btn.pressed.connect(_on_prev_diff_pressed)
	next_diff_btn.pressed.connect(_on_next_diff_pressed)
	
	_update_ui()
	_play_initial_entrance()
	
	if GameManager.should_show_tutorial_on_start():
		call_deferred("_start_first_run_tutorial")

func _setup_live_background() -> void:
	if not live_background or not live_viewport:
		return
	live_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_background.stretch = true
	live_viewport.own_world_3d = true
	live_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	_spawn_menu_wall_preview()
	if live_camera:
		live_camera.current = false

func _sync_menu_wall_preview_players() -> void:
	if not _menu_wall_preview or not _menu_wall_preview.has_method("sync_menu_player_count"):
		return
	var count := 2 if game_state.num_players == 2 else 1
	_menu_wall_preview.call("sync_menu_player_count", count)


func _spawn_menu_wall_preview() -> void:
	if _menu_wall_preview or not live_viewport:
		return
	_menu_wall_preview = MenuWallBackgroundPreviewScene.new()
	live_viewport.add_child(_menu_wall_preview)
	_sync_menu_wall_preview_players()

func _setup_menu_exit_targets() -> void:
	_menu_exit_targets = []
	if menu_vbox:
		_menu_exit_targets.append(menu_vbox)
	if settings_btn:
		_menu_exit_targets.append(settings_btn)
	if background_overlay:
		_menu_exit_targets.append(background_overlay)
	for target in _menu_exit_targets:
		if not target.has_meta("base_position"):
			target.set_meta("base_position", target.position)

func _reset_menu_visual_state() -> void:
	_menu_exit_in_progress = false
	_set_all_buttons_disabled(false)
	for target in _menu_exit_targets:
		var base_pos: Variant = target.get_meta("base_position", target.position)
		target.position = base_pos
		target.modulate.a = 1.0
		target.visible = true


func _setup_embedded_customize() -> void:
	if _embedded_customize or not CUSTOMIZE_SETTINGS_SCENE:
		return
	var overlay := CUSTOMIZE_SETTINGS_SCENE.instantiate() as Control
	if not overlay:
		return
	if overlay.has_method("set"):
		overlay.set("embedded_mode", true)
	overlay.visible = false
	overlay.modulate.a = 0.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if overlay.has_signal("request_close"):
		overlay.connect("request_close", Callable(self, "_on_embedded_customize_close_requested"))
	add_child(overlay)
	_embedded_customize = overlay
	# 共有3Dワールド（メニュー背景）へカスタマイズ用キャラ等を事前構築し、開閉時のヒッチを防ぐ
	if _menu_wall_preview and overlay.has_method("setup_embedded"):
		overlay.call("setup_embedded", _menu_wall_preview)


func _open_embedded_customize() -> void:
	if _embedded_customize_open or _menu_exit_in_progress or not _embedded_customize:
		return
	_embedded_customize_open = true
	_menu_exit_in_progress = true
	_set_all_buttons_disabled(true)
	settings_panel.visible = false
	if _embedded_customize.has_method("prepare_embedded_open"):
		_embedded_customize.call("prepare_embedded_open")
	_embedded_customize.visible = true
	_embedded_customize.mouse_filter = Control.MOUSE_FILTER_STOP
	_embedded_customize.modulate.a = 0.0
	_set_buttons_disabled_in(_embedded_customize, false)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	for target in _menu_exit_targets:
		if not target:
			continue
		var base_pos: Variant = target.get_meta("base_position", target.position)
		tw.tween_property(target, "position:x", base_pos.x + MENU_EXIT_OFFSET_X, MENU_EXIT_DURATION)
		tw.tween_property(target, "modulate:a", 0.0, MENU_EXIT_DURATION * 0.9)
	tw.tween_property(_embedded_customize, "modulate:a", 1.0, MENU_EXIT_DURATION)
	tw.chain().tween_callback(func() -> void:
		_menu_exit_in_progress = false
	)


func _on_embedded_customize_close_requested() -> void:
	if not _embedded_customize_open or _menu_exit_in_progress or not _embedded_customize:
		return
	_menu_exit_in_progress = true
	_embedded_customize_open = false

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	for target in _menu_exit_targets:
		if not target:
			continue
		var base_pos: Variant = target.get_meta("base_position", target.position)
		tw.tween_property(target, "position:x", base_pos.x, MENU_EXIT_DURATION)
		tw.tween_property(target, "modulate:a", 1.0, MENU_EXIT_DURATION * 0.9)
	tw.tween_property(_embedded_customize, "modulate:a", 0.0, MENU_EXIT_DURATION * 0.9)
	tw.chain().tween_callback(func() -> void:
		_embedded_customize.visible = false
		_embedded_customize.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_all_buttons_disabled(false)
		_menu_exit_in_progress = false
	)


func _set_buttons_disabled_in(node: Node, disabled: bool) -> void:
	if node is Button:
		(node as Button).disabled = disabled
	for child in node.get_children():
		_set_buttons_disabled_in(child, disabled)

func _play_exit_and_change_scene(path: String) -> void:
	if _menu_exit_in_progress:
		return
	_menu_exit_in_progress = true
	_set_all_buttons_disabled(true)
	settings_panel.visible = false

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)

	for target in _menu_exit_targets:
		if not target:
			continue
		var base_pos: Variant = target.get_meta("base_position", target.position)
		tw.tween_property(target, "position:x", base_pos.x + MENU_EXIT_OFFSET_X, MENU_EXIT_DURATION)
		tw.tween_property(target, "modulate:a", 0.0, MENU_EXIT_DURATION * 0.9)

	tw.chain().tween_callback(_begin_scene_change.bind(path))

func _begin_scene_change(path: String) -> void:
	await get_tree().process_frame
	_hold_menu_frame_before_scene_change()
	if path.ends_with("game_world.tscn"):
		get_tree().change_scene_to_packed(GAME_WORLD_SCENE)
	else:
		get_tree().change_scene_to_file(path)

func _hold_menu_frame_before_scene_change() -> void:
	if not live_viewport:
		SceneTransition.hold_color()
		return
	var viewport_texture: ViewportTexture = live_viewport.get_texture()
	if not viewport_texture:
		SceneTransition.hold_color()
		return
	var frame_image: Image = viewport_texture.get_image()
	if frame_image.is_empty():
		SceneTransition.hold_color()
		return
	SceneTransition.hold_image_texture(ImageTexture.create_from_image(frame_image))

func _set_all_buttons_disabled(disabled: bool) -> void:
	for btn: Button in _get_all_buttons(self):
		btn.disabled = disabled

func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED or not live_viewport:
		return
	live_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE if visible else SubViewport.UPDATE_DISABLED

func _on_live_config_updated() -> void:
	if LiveConfigManager.is_active and not LiveConfigManager.announcement.is_empty():
		announcement_label.text = "📢 %s" % LiveConfigManager.announcement
		announcement_label.visible = true
	else:
		announcement_label.visible = false

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
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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

	if not GameManager.tutorial_completed:
		_style_tutorial_button(_tutorial_btn)
		_style_tutorial_button(_tutorial_2p_btn)

func _get_all_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		buttons.append_array(_get_all_buttons(child))
	return buttons

func _ensure_tutorial_button() -> void:
	if _tutorial_btn and _tutorial_2p_btn:
		return
	_tutorial_row = HBoxContainer.new()
	_tutorial_row.name = "TutorialRow"
	_tutorial_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_tutorial_row.add_theme_constant_override("separation", 12)
	mode_container.add_child(_tutorial_row)

	_tutorial_btn = _make_tutorial_button("TutorialBtn", _on_tutorial_pressed)
	_tutorial_2p_btn = _make_tutorial_button("Tutorial2PBtn", _on_tutorial_2p_pressed)
	_tutorial_row.add_child(_tutorial_btn)
	_tutorial_row.add_child(_tutorial_2p_btn)

func _make_tutorial_button(node_name: String, pressed_callable: Callable) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.custom_minimum_size = Vector2(260, 52)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(pressed_callable)
	return btn

func _style_tutorial_button(btn: Button) -> void:
	if not btn:
		return
	var tutorial_normal := StyleBoxFlat.new()
	tutorial_normal.bg_color = Color(0.28, 0.20, 0.08)
	tutorial_normal.border_color = Color(0.85, 0.62, 0.18)
	tutorial_normal.set_border_width_all(2)
	tutorial_normal.set_corner_radius_all(12)
	tutorial_normal.content_margin_left = 18.0
	tutorial_normal.content_margin_right = 18.0
	tutorial_normal.content_margin_top = 9.0
	tutorial_normal.content_margin_bottom = 9.0
	var tutorial_hover := tutorial_normal.duplicate()
	tutorial_hover.bg_color = Color(0.36, 0.26, 0.10)
	btn.add_theme_stylebox_override("normal", tutorial_normal)
	btn.add_theme_stylebox_override("hover", tutorial_hover)
	btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.78))


const GAME_SCENE := "res://scenes/game_world.tscn"

func _go_to_game() -> void:
	if _menu_exit_in_progress:
		return
	_play_exit_and_change_scene(GAME_SCENE)

func _start_tutorial_game(tutorial_players: int = 1) -> void:
	game_state.start_tutorial(tutorial_players)
	_go_to_game()

func _start_first_run_tutorial() -> void:
	GameManager.dismiss_tutorial()
	_start_tutorial_game()

func _update_ui() -> void:
	if not game_state:
		return

	_hide_coop_mode_if_disabled()
	game_state.refresh_status_text()
	status_label.text = game_state.status_text
	if _tutorial_btn:
		_tutorial_btn.text = "はじめてのチュートリアル" if not GameManager.tutorial_completed else "1人用チュートリアル"
	if _tutorial_2p_btn:
		_tutorial_2p_btn.text = "2人用チュートリアル"

	var step_changed := game_state.menu_step != _prev_menu_step
	if game_state.menu_step == Constants.MENU_STEP_MODE:
		mode_container.visible = true
		config_container.visible = false
		if step_changed and _entrance_done:
			_play_entrance(mode_container, false)
	elif game_state.menu_step == Constants.MENU_STEP_CONFIG:
		mode_container.visible = false
		config_container.visible = true
		if step_changed and _entrance_done:
			_play_entrance(config_container, true)

		# Update config labels
		_update_grade_carousel()
		_update_diff_carousel()
		_update_subject_carousel()
		var p_text: String
		if game_state.num_players == 1:
			p_text = "👤 1人プレイ"
		elif game_state.num_players == 2:
			if game_state.mode == Constants.MODE_COOP:
				p_text = "🤝 2人協力"
			else:
				p_text = "👥 2人プレイ"
		else:
			p_text = "🌐 オンライン対戦"
		players_btn.text = p_text

		var llm_text: String = "🌐 ONLINE (AI生成)" if QuizManager.provider.llm_mode == "ONLINE" else "📦 OFFLINE (内蔵問題)"
		llm_toggle_btn.text = llm_text

		if customize_btn:
			customize_btn.visible = true
			customize_btn.text = "カスタマイズ"

	_sync_menu_wall_preview_players()

	_prev_menu_step = game_state.menu_step

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
	if not SHOW_COOP_MODE:
		if game_state.mode == Constants.MODE_COOP:
			game_state.mode = Constants.MODE_TEN
		if game_state.num_players == 1:
			game_state.num_players = 2
		elif game_state.num_players == 2:
			game_state.num_players = 3
		else:
			game_state.num_players = 1
		_update_ui()
		return

	# 1人 → 2人(ローカル) → 2人協力 → オンライン対戦 のサイクル
	if game_state.num_players == 1:
		game_state.num_players = 2
		if game_state.mode == Constants.MODE_COOP:
			game_state.mode = Constants.MODE_TEN
	elif game_state.num_players == 2 and game_state.mode != Constants.MODE_COOP:
		game_state.mode = Constants.MODE_COOP
	elif game_state.num_players == 2 and game_state.mode == Constants.MODE_COOP:
		game_state.num_players = 3
		game_state.mode = Constants.MODE_TEN
	else:
		game_state.num_players = 1
		if game_state.mode == Constants.MODE_COOP:
			game_state.mode = Constants.MODE_TEN
	_update_ui()

func _on_customize_pressed() -> void:
	_open_embedded_customize()

func _on_tutorial_pressed() -> void:
	_start_tutorial_game()

func _on_tutorial_2p_pressed() -> void:
	_start_tutorial_game(2)

func _on_prev_grade_pressed() -> void:
	game_state.grade -= 1
	if game_state.grade < 1: game_state.grade = 6
	game_state.refresh_status_text()
	_update_ui()

func _on_next_grade_pressed() -> void:
	game_state.grade += 1
	if game_state.grade > 6: game_state.grade = 1
	game_state.refresh_status_text()
	_update_ui()

func _on_prev_diff_pressed() -> void:
	var diffs = Constants.DIFFICULTY_LEVELS
	var current_idx = diffs.find(game_state.difficulty)
	if current_idx == -1: current_idx = 0
	var prev_idx = (current_idx - 1 + diffs.size()) % diffs.size()
	game_state.difficulty = diffs[prev_idx]
	game_state.refresh_status_text()
	_update_ui()

func _on_next_diff_pressed() -> void:
	var diffs = Constants.DIFFICULTY_LEVELS
	var current_idx = diffs.find(game_state.difficulty)
	if current_idx == -1: current_idx = 0
	var next_idx = (current_idx + 1) % diffs.size()
	game_state.difficulty = diffs[next_idx]
	game_state.refresh_status_text()
	_update_ui()

func _on_prev_subject_pressed() -> void:
	var current_idx = Constants.SUBJECTS.find(game_state.subject)
	if current_idx == -1: current_idx = 0
	var prev_idx = (current_idx - 1 + Constants.SUBJECTS.size()) % Constants.SUBJECTS.size()
	game_state.subject = Constants.SUBJECTS[prev_idx]
	game_state.refresh_status_text()
	_update_ui()

func _on_next_subject_pressed() -> void:
	var current_idx = Constants.SUBJECTS.find(game_state.subject)
	if current_idx == -1: current_idx = 0
	var next_idx = (current_idx + 1) % Constants.SUBJECTS.size()
	game_state.subject = Constants.SUBJECTS[next_idx]
	game_state.refresh_status_text()
	_update_ui()

func _update_grade_carousel() -> void:
	current_grade_label.text = "📚 %d年生" % game_state.grade
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.20)
	normal.border_color = Color(0.25, 0.30, 0.40)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	current_grade_label.add_theme_stylebox_override("normal", normal)

func _update_diff_carousel() -> void:
	current_diff_label.text = "⚡ %s" % game_state.difficulty
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.20)
	normal.border_color = Color(0.25, 0.30, 0.40)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	current_diff_label.add_theme_stylebox_override("normal", normal)

func _update_subject_carousel() -> void:
	var colors = {
		"算数": {"icon": "📐 算数", "color": Color(0.15, 0.40, 0.80)},
		"理科": {"icon": "🔬 理科", "color": Color(0.15, 0.70, 0.35)},
		"国語": {"icon": "📖 国語", "color": Color(0.85, 0.25, 0.30)},
		"社会": {"icon": "🌍 社会", "color": Color(0.85, 0.60, 0.15)}
	}
	
	var sub = game_state.subject
	if not colors.has(sub): sub = "算数"
	
	var info = colors[sub]
	current_subject_label.text = info["icon"]
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = info["color"].darkened(0.2)
	normal.border_color = info["color"].lightened(0.2)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	
	current_subject_label.add_theme_stylebox_override("normal", normal)



func _on_start_pressed() -> void:
	if _menu_exit_in_progress:
		return
	_hide_coop_mode_if_disabled()
	if game_state.num_players == 3:
		# オンライン対戦: ロビー画面へ
		game_state.num_players = 2  # 実際のプレイは2人
		get_tree().change_scene_to_file("res://ui/online_lobby.tscn")
		return
	if game_state.mode == Constants.MODE_COOP:
		game_state.num_players = 2
	game_state.start_game()
	_go_to_game()

func _hide_coop_mode_if_disabled() -> void:
	if SHOW_COOP_MODE or not game_state:
		return
	if game_state.mode == Constants.MODE_COOP:
		game_state.mode = Constants.MODE_TEN
		if game_state.num_players < 2:
			game_state.num_players = 2

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

func _on_model_selected(index: int) -> void:
	var selected_model = model_option.get_item_text(index)
	ApiStatusAutoload.user_selected_gemini_model = selected_model
	ApiStatusAutoload.gemini_model = selected_model
	_on_recheck_btn_pressed()

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

# --- 入場 / ステップ切替アニメーション ---

func _play_initial_entrance() -> void:
	## メニュー表示時に全体を左からスライド＋段階的フェードインさせる
	_entrance_done = true
	_play_entrance($VBoxContainer, true)

func _play_entrance(container: Control, from_left: bool = true) -> void:
	## container の表示中の子要素を、方向付きスライド＋段階フェードで順番に出現させる
	if not container or not is_inside_tree():
		return
	# コンテナのレイアウト確定を待ってから各子の定位置を取得する
	await get_tree().process_frame
	if not is_instance_valid(container):
		return
	var dir := -1.0 if from_left else 1.0
	var idx := 0
	for child in container.get_children():
		if not (child is Control):
			continue
		var ci := child as Control
		if not ci.visible:
			continue
		var target_x: float = ci.position.x
		ci.modulate.a = 0.0
		ci.position.x = target_x + dir * ANIM_SLIDE_OFFSET
		var delay: float = idx * ANIM_STAGGER
		var tw := create_tween()
		tw.set_parallel(true)
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(ci, "modulate:a", 1.0, ANIM_FADE_DURATION).set_delay(delay)
		tw.tween_property(ci, "position:x", target_x, ANIM_FADE_DURATION).set_delay(delay)
		idx += 1
