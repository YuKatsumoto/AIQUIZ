extends Control

const TutorialCourseSelectorScript := preload("res://scripts/ui/tutorial_course_selector.gd")
const TutorialCompletionCardScript := preload("res://scripts/ui/tutorial_completion_card.gd")

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
var bgm_vol_slider: HSlider = null
# speed_slider は廃止（壁速度は難易度から自動決定）
@onready var res_option: OptionButton = %ResOption
var graphics_quality_option: OptionButton = null

var game_state: QuizGameState
var _tutorial_row: HBoxContainer = null
var _tutorial_main_btn: Button = null
var _tutorial_selector: Control = null

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
var _pending_customize_tutorial_on_ready: bool = false
var _embedded_customize_close_pending: bool = false
var _tutorial_completion_card: Control = null
var _customize_tutorial_completion_showing: bool = false
var _tutorial_completion_previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _tutorial_completion_mouse_mode_saved: bool = false

## ステップインジケータの各ピル {sb: StyleBoxFlat, lbl: Label}
var _step_pills: Array[Dictionary] = []
var _step_indicator_bright_sky: bool = false

func _ready() -> void:
	game_state = QuizManager.game_state
	_pending_customize_tutorial_on_ready = game_state.has_pending_solo_customize_tour()
	_hide_coop_mode_if_disabled()
	game_state.game_state = Constants.STATE_MENU
	# 戻るボタン等からの遷移時に状態を保持するため、menu_stepの強制リセットを削除
	settings_panel.visible = false
	_setup_live_background()
	_enhance_title()
	_apply_menu_text_shadows()
	_setup_step_indicator()
	_setup_menu_exit_targets()
	_setup_embedded_customize()
	_reset_menu_visual_state()

	_setup_audio_settings()
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_MENU)

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

	_setup_graphics_quality_option()
	ApiStatusAutoload.check_completed.connect(_update_api_status_text)
	
	LiveConfigManager.config_updated.connect(_on_live_config_updated)
	_on_live_config_updated()

	_ensure_tutorial_button()
	_ensure_tutorial_selector()
	_style_all_buttons()
	
	prev_grade_btn.pressed.connect(_on_prev_grade_pressed)
	next_grade_btn.pressed.connect(_on_next_grade_pressed)
	prev_subject_btn.pressed.connect(_on_prev_subject_pressed)
	next_subject_btn.pressed.connect(_on_next_subject_pressed)
	prev_diff_btn.pressed.connect(_on_prev_diff_pressed)
	next_diff_btn.pressed.connect(_on_next_diff_pressed)
	
	_update_ui()
	if _pending_customize_tutorial_on_ready:
		_entrance_done = true
		call_deferred("_begin_pending_customize_tutorial")
	else:
		SceneTransition.reveal_current()
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
	# モニター/ウィンドウの実解像度に合わせて背景の描画解像度を自動最適化する。
	# 固定解像度のままだと大画面で引き伸ばされてボケるため、実サイズに追従させる。
	_update_live_viewport_quality()
	get_window().size_changed.connect(_update_live_viewport_quality)

## 実際のウィンドウ/モニター解像度に応じて LiveViewport の描画解像度とスーパーサンプリング倍率を決める。
## 本プロジェクトの stretch mode (canvas_items, 基準1280x720) では Control のサイズは常に論理座標のままで、
## ウィンドウを最大化しても SubViewportContainer は論理サイズ(≒1280x720)しか持たない。
## そのため stretch=true の SubViewport は論理解像度でしか描画されず、高解像度モニタでは
## 物理ピクセルまで引き伸ばされてボケていた（2D UIはcanvas_itemsが自動で物理解像度描画するためボケない）。
## 対策として、コンテナを物理ピクセルサイズへ広げてから逆スケールで論理サイズに縮めて表示することで、
## SubViewport を常にモニタの実ピクセル解像度で描画させる。リサイズ/最大化/解像度変更のたびに再計算される。
func _update_live_viewport_quality() -> void:
	if not live_background or not live_viewport:
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	if logical.x <= 0.0 or logical.y <= 0.0:
		return
	# canvas_items stretch の拡大率。物理解像度 = 論理解像度 × 拡大率
	var stretch_scale: Vector2 = get_window().get_final_transform().get_scale()
	var target: Vector2 = logical * stretch_scale

	var is_mobile := OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	# 背景はあくまで演出用途のため、過大な負荷を避けるための上限（デスクトップは4K相当まで実解像度）
	var max_w: float = 1280.0 if is_mobile else 3840.0
	if target.x > max_w:
		target *= max_w / target.x
	target.x = maxf(target.x, 640.0)
	target.y = maxf(target.y, 360.0)

	live_background.stretch_shrink = 1
	live_background.set_anchors_preset(Control.PRESET_TOP_LEFT)
	live_background.position = Vector2.ZERO
	live_background.size = target
	live_background.scale = logical / target

	# 物理解像度で描画できている時はスーパーサンプリングを控えめに、低解像度時は強めに掛ける
	# 壁のLabel3Dを含むため、常にネイティブ解像度を維持する。
	GraphicsQuality.apply_text_viewport(live_viewport, GameManager.graphics_quality)

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

## ④ タイトル強化: アクセントバーを追加
func _enhance_title() -> void:
	if not menu_vbox or not is_instance_valid(title_label):
		return
	var title_row := title_label.get_parent() as Control
	if not title_row:
		return
	var insert_idx := title_row.get_index() + 1

	var accent := ColorRect.new()
	accent.name = "TitleAccentBar"
	accent.color = Color(1.0, 0.88, 0.25)
	accent.custom_minimum_size = Vector2(96, 4)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu_vbox.add_child(accent)
	menu_vbox.move_child(accent, insert_idx)

## ③ 文字影: 背景に負けないようメニュー内ラベルへ影を付ける
func _apply_menu_text_shadows() -> void:
	if not menu_vbox:
		return
	for lbl in _get_all_labels(menu_vbox):
		_apply_label_shadow(lbl, false)
	_apply_label_shadow(title_label, true)

func _apply_label_shadow(lbl: Label, strong: bool) -> void:
	if not lbl:
		return
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85 if strong else 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 2 if strong else 1)
	lbl.add_theme_constant_override("shadow_offset_y", 2 if strong else 1)
	if strong:
		lbl.add_theme_constant_override("shadow_outline_size", 1)

func _get_all_labels(node: Node) -> Array[Label]:
	var labels: Array[Label] = []
	if node is Label:
		labels.append(node)
	for child in node.get_children():
		labels.append_array(_get_all_labels(child))
	return labels

## ⑥ ステップ表示: 「手順 1/3」テキストを3つのピル(モード→設定→スタート)に置き換える
func _setup_step_indicator() -> void:
	if not menu_vbox or not status_label:
		return
	var row := HBoxContainer.new()
	row.name = "StepIndicator"
	row.add_theme_constant_override("separation", 8)

	var steps := [["1", "モード"], ["2", "設定"], ["3", "スタート"]]
	_step_pills.clear()
	for s in steps:
		var pill := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.10)
		sb.set_corner_radius_all(11)
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		pill.add_theme_stylebox_override("panel", sb)

		var lbl := Label.new()
		lbl.text = "%s %s" % [s[0], s[1]]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86))
		pill.add_child(lbl)

		row.add_child(pill)
		_step_pills.append({"sb": sb, "lbl": lbl})

	menu_vbox.add_child(row)
	menu_vbox.move_child(row, status_label.get_index())

func _process(_delta: float) -> void:
	var bright_sky := WeatherCycle.is_bright_sky()
	if bright_sky == _step_indicator_bright_sky:
		return
	_update_step_indicator()


func _update_step_indicator() -> void:
	if _step_pills.is_empty() or not game_state:
		return
	var active := 1 if game_state.menu_step == Constants.MENU_STEP_CONFIG else 0
	var bright_sky := WeatherCycle.is_bright_sky()
	_step_indicator_bright_sky = bright_sky
	for i in range(_step_pills.size()):
		var sb: StyleBoxFlat = _step_pills[i]["sb"]
		var lbl: Label = _step_pills[i]["lbl"]
		if i == active:
			sb.bg_color = Color(0.18, 0.43, 0.75, 0.95)
			sb.set_border_width_all(0)
			lbl.add_theme_color_override("font_color", Color(1, 1, 1))
			lbl.add_theme_constant_override("outline_size", 0)
		elif i < active:
			sb.bg_color = Color(0.18, 0.43, 0.75, 0.40)
			sb.set_border_width_all(0)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
			lbl.add_theme_constant_override("outline_size", 0)
		elif bright_sky:
			sb.bg_color = Color(0.10, 0.18, 0.34, 0.88)
			sb.border_color = Color(0.20, 0.34, 0.55, 1.0)
			sb.set_border_width_all(2)
			lbl.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
			lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.12, 0.78))
			lbl.add_theme_constant_override("outline_size", 4)
		else:
			sb.bg_color = Color(1, 1, 1, 0.10)
			sb.set_border_width_all(0)
			lbl.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86))
			lbl.add_theme_constant_override("outline_size", 0)

## ② メニュー本体を半透明パネルで囲う（VBoxの背後に敷き、_processで追従）
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
	if overlay.has_signal("tutorial_tour_completed"):
		overlay.connect("tutorial_tour_completed", Callable(self, "_on_customize_tutorial_completed"))
	if overlay.has_signal("tutorial_tour_aborted"):
		overlay.connect("tutorial_tour_aborted", Callable(self, "_on_customize_tutorial_aborted"))
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


func _begin_pending_customize_tutorial() -> void:
	if not game_state.has_pending_solo_customize_tour() or not _embedded_customize:
		game_state.abort_solo_customize_tour()
		SceneTransition.reveal_current()
		return
	_open_embedded_customize()
	if _embedded_customize.has_method("begin_tutorial_tour"):
		_embedded_customize.call("begin_tutorial_tour")
	else:
		game_state.abort_solo_customize_tour()
	SceneTransition.reveal_current()


func _on_customize_tutorial_completed() -> void:
	if _customize_tutorial_completion_showing:
		return
	_customize_tutorial_completion_showing = true
	_tutorial_completion_previous_mouse_mode = Input.get_mouse_mode()
	_tutorial_completion_mouse_mode_saved = true
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	var card := TutorialCompletionCardScript.new() as Control
	card.name = "SoloTutorialCompletionCard"
	add_child(card)
	_tutorial_completion_card = card
	card.tree_exited.connect(func() -> void:
		if _tutorial_completion_card == card:
			_tutorial_completion_card = null
	)
	card.connect(
		"hold_completed",
		Callable(self, "_on_customize_tutorial_completion_hold_finished"),
		CONNECT_ONE_SHOT,
	)
	var is_duo := game_state.get_pending_customize_tour_course() == GameManager.TUTORIAL_COURSE_LOCAL_2P
	card.call("present", {
		"step": "2 / 2  TUTORIAL COMPLETE",
		"title": "ローカル2Pチュートリアル完了！" if is_duo else "1Pチュートリアル完了！",
		"body": (
			"2人プレイの操作とカスタマイズの紹介が完了しました。"
			if is_duo
			else "ステージ操作とカスタマイズの紹介が完了しました。"
		),
		"progress": "✓ ステージ実践　　✓ カスタマイズ",
		"footer": "まもなくメニューへ戻ります",
		"duration": 3.8,
	})
	AudioManager.play_tutorial_complete()


func _on_customize_tutorial_completion_hold_finished() -> void:
	if not _customize_tutorial_completion_showing:
		return
	if not game_state.has_pending_solo_customize_tour():
		_dismiss_customize_tutorial_completion_card()
		return
	# 完了カードを十分に見せた後で初めて保存する。閉じる処理より先に
	# pending を解除し、通常の close が中断扱いにしないようにする。
	game_state.complete_solo_customize_tour()
	_on_embedded_customize_close_requested()
	while _menu_exit_in_progress and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_dismiss_customize_tutorial_completion_card()


func _dismiss_customize_tutorial_completion_card() -> void:
	_customize_tutorial_completion_showing = false
	if _tutorial_completion_card and is_instance_valid(_tutorial_completion_card):
		_tutorial_completion_card.call("dismiss")
	_restore_tutorial_completion_mouse_mode()


func _restore_tutorial_completion_mouse_mode() -> void:
	if not _tutorial_completion_mouse_mode_saved:
		return
	Input.set_mouse_mode(_tutorial_completion_previous_mouse_mode)
	_tutorial_completion_mouse_mode_saved = false


func _on_customize_tutorial_aborted() -> void:
	game_state.abort_solo_customize_tour()
	_on_embedded_customize_close_requested()


func _on_embedded_customize_close_requested() -> void:
	if not _embedded_customize_open or not _embedded_customize:
		return
	# 開くアニメーション直後の Esc / 戻る操作も失わない。
	# 入口 Tween と3Dプレビューの初期化が終わるまで1本の待機処理にまとめる。
	if _menu_exit_in_progress:
		if not _embedded_customize_close_pending:
			_embedded_customize_close_pending = true
			call_deferred("_wait_for_embedded_customize_open_then_close")
		return
	_embedded_customize_close_pending = false
	if _embedded_customize.has_method("_prepare_embedded_close"):
		_embedded_customize.call("_prepare_embedded_close")
	if game_state.has_pending_solo_customize_tour():
		game_state.abort_solo_customize_tour()
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


func _wait_for_embedded_customize_open_then_close() -> void:
	while _menu_exit_in_progress:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_embedded_customize_close_pending = false
	_on_embedded_customize_close_requested()


func _set_buttons_disabled_in(node: Node, disabled: bool) -> void:
	if node is Button:
		(node as Button).disabled = disabled
	for child in node.get_children():
		_set_buttons_disabled_in(child, disabled)

func _play_exit_and_change_scene(
	path: String,
	start_standard_round: bool = false,
	tutorial_course: String = ""
) -> void:
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

	_begin_scene_change(path, start_standard_round, tutorial_course)


## 現在画面を完全に黒で覆ってから、同期的な問題準備を実行する。
## 重いオフライン問題処理をワイプの途中に重ねず、黒画面の裏へ隠す。
func _begin_scene_change(
	path: String,
	start_standard_round: bool = false,
	tutorial_course: String = ""
) -> void:
	await get_tree().process_frame
	var show_loading_character: bool = path.ends_with("game_world.tscn")
	await SceneTransition.fade_to_color_and_wait(Color.BLACK, show_loading_character)
	if not is_inside_tree():
		return
	if not tutorial_course.is_empty():
		game_state.start_tutorial(tutorial_course)
	elif start_standard_round:
		game_state.start_game()
	if path.ends_with("game_world.tscn"):
		get_tree().change_scene_to_packed(GAME_WORLD_SCENE)
	else:
		get_tree().change_scene_to_file(path)

func _set_all_buttons_disabled(disabled: bool) -> void:
	for btn: Button in _get_all_buttons(self):
		btn.disabled = disabled


func _exit_tree() -> void:
	_restore_tutorial_completion_mouse_mode()


func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED or not live_viewport:
		return
	live_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE if visible else SubViewport.UPDATE_DISABLED

func _on_live_config_updated() -> void:
	if LiveConfigManager.is_active and not LiveConfigManager.announcement.is_empty():
		announcement_label.text = "%s" % LiveConfigManager.announcement
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

	# チュートリアル系ボタンも他ボタンと同じ配色（上のループで既に適用済み）

func _get_all_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		buttons.append_array(_get_all_buttons(child))
	return buttons

func _ensure_tutorial_button() -> void:
	if _tutorial_main_btn:
		return
	_tutorial_row = HBoxContainer.new()
	_tutorial_row.name = "TutorialRow"
	_tutorial_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_tutorial_row.add_theme_constant_override("separation", 12)
	mode_container.add_child(_tutorial_row)

	# 初回起動時と同じコース選択オーバーレイを開く
	_tutorial_main_btn = Button.new()
	_tutorial_main_btn.name = "TutorialMainBtn"
	_tutorial_main_btn.custom_minimum_size = Vector2(260, 52)
	_tutorial_main_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tutorial_main_btn.add_theme_font_size_override("font_size", 18)
	_tutorial_main_btn.pressed.connect(_on_tutorial_pressed)
	_tutorial_row.add_child(_tutorial_main_btn)


func _ensure_tutorial_selector() -> void:
	if _tutorial_selector:
		return
	_tutorial_selector = TutorialCourseSelectorScript.new() as Control
	_tutorial_selector.name = "TutorialCourseSelector"
	add_child(_tutorial_selector)
	_tutorial_selector.connect("course_selected", _on_tutorial_course_selected)
	_tutorial_selector.connect("dismissed", _on_tutorial_selector_dismissed)


func _show_tutorial_selector() -> void:
	if _tutorial_selector:
		_tutorial_selector.call("show_selector")


## コースを選んだだけでは「見た」扱いにしない。途中で抜けたときに初回プロンプトが
## 二度と出なくなるため、既読化はクリア時（mark_tutorial_course_completed）か
## 明示的な×（_on_tutorial_selector_dismissed）に任せる。
func _on_tutorial_course_selected(course: String) -> void:
	_start_tutorial_game(course)


func _on_tutorial_selector_dismissed() -> void:
	GameManager.dismiss_tutorial()


const GAME_SCENE := "res://scenes/game_world.tscn"

func _go_to_game(
	start_standard_round: bool = false,
	tutorial_course: String = ""
) -> void:
	if _menu_exit_in_progress:
		return
	_play_exit_and_change_scene(GAME_SCENE, start_standard_round, tutorial_course)


func _start_tutorial_game(course: String = GameManager.TUTORIAL_COURSE_SOLO) -> void:
	_go_to_game(false, course)

func _start_first_run_tutorial() -> void:
	_show_tutorial_selector()

func _update_ui() -> void:
	if not game_state:
		return

	_hide_coop_mode_if_disabled()
	game_state.refresh_status_text()
	status_label.text = game_state.status_text
	# メニュー中はステップピルが「手順N/3」を兼ねるので重複テキストを消す
	if game_state.game_state == Constants.STATE_MENU:
		status_label.text = ""
	_update_step_indicator()
	if _tutorial_main_btn:
		_tutorial_main_btn.text = "チュートリアル"

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
			p_text = "1人プレイ"
		elif game_state.num_players == 2:
			if game_state.mode == Constants.MODE_COOP:
				p_text = "2人協力"
			else:
				p_text = "2人プレイ"
		else:
			p_text = "オンライン対戦"
		players_btn.text = p_text

		# エンドレスモードはオフライン問題のみ対応（オンラインAI生成は選択不可）
		if game_state.mode == Constants.MODE_ENDLESS:
			if QuizManager.provider.llm_mode != "OFFLINE":
				QuizManager.provider.set_llm_mode("OFFLINE")
			llm_toggle_btn.text = "出題: OFFLINE 固定 🔒"
			llm_toggle_btn.disabled = true
			llm_toggle_btn.focus_mode = Control.FOCUS_NONE
			llm_toggle_btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
			llm_toggle_btn.tooltip_text = "エンドレスモードはオフライン問題のみ対応しています"
			_set_llm_toggle_locked_style(true)
		else:
			llm_toggle_btn.disabled = false
			llm_toggle_btn.focus_mode = Control.FOCUS_ALL
			llm_toggle_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			llm_toggle_btn.tooltip_text = ""
			_set_llm_toggle_locked_style(false)
			var llm_text: String = "出題: ONLINE (AI生成)" if QuizManager.provider.llm_mode == "ONLINE" else "出題: OFFLINE (内蔵問題)"
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
	if game_state.mode == Constants.MODE_ENDLESS:
		return  # エンドレスモードはオフライン固定のため切り替え不可
	var new_mode := "ONLINE" if QuizManager.provider.llm_mode == "OFFLINE" else "OFFLINE"
	QuizManager.provider.set_llm_mode(new_mode)
	_update_ui()

func _set_llm_toggle_locked_style(locked: bool) -> void:
	## エンドレスモードでオフライン固定のとき、ボタンをグレーアウトして操作不可を明示する
	if not llm_toggle_btn:
		return
	if locked:
		var disabled_style := StyleBoxFlat.new()
		disabled_style.bg_color = Color(0.10, 0.11, 0.14)
		disabled_style.border_color = Color(0.20, 0.22, 0.28)
		disabled_style.set_border_width_all(1)
		disabled_style.set_corner_radius_all(10)
		disabled_style.content_margin_left = 16.0
		disabled_style.content_margin_right = 16.0
		disabled_style.content_margin_top = 8.0
		disabled_style.content_margin_bottom = 8.0
		llm_toggle_btn.add_theme_stylebox_override("disabled", disabled_style)
		llm_toggle_btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.55))
		llm_toggle_btn.modulate = Color(1, 1, 1, 0.85)
	else:
		llm_toggle_btn.remove_theme_stylebox_override("disabled")
		llm_toggle_btn.remove_theme_color_override("font_disabled_color")
		llm_toggle_btn.modulate = Color(1, 1, 1, 1)

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
	_show_tutorial_selector()

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
	current_grade_label.text = "%d年生" % game_state.grade
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.20)
	normal.border_color = Color(0.25, 0.30, 0.40)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	current_grade_label.add_theme_stylebox_override("normal", normal)

func _update_diff_carousel() -> void:
	current_diff_label.text = "%s" % game_state.difficulty
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.20)
	normal.border_color = Color(0.25, 0.30, 0.40)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	current_diff_label.add_theme_stylebox_override("normal", normal)

func _update_subject_carousel() -> void:
	var colors = {
		"算数": {"icon": "算数", "color": Color(0.15, 0.40, 0.80)},
		"理科": {"icon": "理科", "color": Color(0.15, 0.70, 0.35)},
		"国語": {"icon": "国語", "color": Color(0.85, 0.25, 0.30)},
		"社会": {"icon": "社会", "color": Color(0.85, 0.60, 0.15)}
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
	_go_to_game(true)

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

	var proxy := ApiStatusAutoload.get_proxy_url()
	var p_col = "green" if ApiStatusAutoload.proxy_status else ("red" if ApiStatusAutoload.proxy_status == false else "yellow")
	var p_cfg = "設定済" if ApiStatusAutoload.proxy_configured else "未設定"
	text += "[color=%s]AI Gateway (PROXY): %s[/color] (URL: %s)\n" % [p_col, ApiStatusAutoload.proxy_msg, p_cfg]

	var f_col = "green" if ApiStatusAutoload.firebase_status else ("red" if ApiStatusAutoload.firebase_status == false else "yellow")
	var f_key = "設定済" if ApiStatusAutoload.firebase_configured else "未設定"
	text += "[color=%s]Firebase: %s[/color] (DB URL: %s)\n" % [f_col, ApiStatusAutoload.firebase_msg, f_key]

	text += "\n[color=gray]オフライン問題数: %d問[/color]" % ApiStatusAutoload.offline_count

	api_status_label.text = text

func _on_vol_slider_changed(value: float) -> void:
	game_state.set_sfx_volume(value)

func _on_bgm_vol_slider_changed(value: float) -> void:
	game_state.set_bgm_volume(value)

func _setup_audio_settings() -> void:
	game_state.sfx_volume = AudioManager.sfx_volume
	game_state.bgm_volume = AudioManager.bgm_volume
	vol_slider.value = AudioManager.sfx_volume

	var sfx_row := $SettingsPanel/VBox/VolBox as HBoxContainer
	var sfx_label := sfx_row.get_node_or_null("Label") as Label
	if sfx_label:
		sfx_label.text = "効果音量:"

	var settings_vbox := $SettingsPanel/VBox as VBoxContainer
	var existing_slider := settings_vbox.get_node_or_null("BgmVolBox/BgmVolSlider") as HSlider
	if existing_slider:
		bgm_vol_slider = existing_slider
		bgm_vol_slider.value = AudioManager.bgm_volume
		return

	var bgm_row := HBoxContainer.new()
	bgm_row.name = "BgmVolBox"
	bgm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var bgm_label := Label.new()
	bgm_label.name = "Label"
	bgm_label.text = "BGM音量:"
	bgm_row.add_child(bgm_label)
	bgm_vol_slider = HSlider.new()
	bgm_vol_slider.name = "BgmVolSlider"
	bgm_vol_slider.custom_minimum_size = Vector2(250.0, 0.0)
	bgm_vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bgm_vol_slider.max_value = 1.0
	bgm_vol_slider.step = 0.05
	bgm_vol_slider.value = AudioManager.bgm_volume
	bgm_vol_slider.value_changed.connect(_on_bgm_vol_slider_changed)
	bgm_row.add_child(bgm_vol_slider)
	settings_vbox.add_child(bgm_row)
	settings_vbox.move_child(bgm_row, sfx_row.get_index())

# _on_speed_slider_changed は廃止（壁速度は難易度から自動決定）


func _setup_graphics_quality_option() -> void:
	var settings_vbox: VBoxContainer = $SettingsPanel/VBox
	var resolution_row: HBoxContainer = $SettingsPanel/VBox/ResolutionBox
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "GraphicsQualityBox"
	row.add_theme_constant_override("separation", 12)
	var label: Label = Label.new()
	label.name = "Label"
	label.text = "画質"
	label.custom_minimum_size = Vector2(120.0, 0.0)
	label.add_theme_font_size_override("font_size", 18)
	var option: OptionButton = OptionButton.new()
	option.name = "GraphicsQualityOption"
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 18)
	option.add_item("軽量", 0)
	option.add_item("標準", 1)
	option.add_item("高画質", 2)
	match GameManager.graphics_quality:
		GraphicsQuality.LOW:
			option.select(0)
		GraphicsQuality.HIGH:
			option.select(2)
		_:
			option.select(1)
	option.item_selected.connect(_on_graphics_quality_selected)
	row.add_child(label)
	row.add_child(option)
	settings_vbox.add_child(row)
	settings_vbox.move_child(row, resolution_row.get_index() + 1)
	graphics_quality_option = option


func _on_graphics_quality_selected(index: int) -> void:
	var quality: String = GraphicsQuality.BALANCED
	match index:
		0:
			quality = GraphicsQuality.LOW
		2:
			quality = GraphicsQuality.HIGH
	GameManager.set_graphics_quality(quality)
	GraphicsQuality.apply_text_viewport(live_viewport, quality)
	if _menu_wall_preview and _menu_wall_preview.has_method("apply_graphics_quality"):
		_menu_wall_preview.call("apply_graphics_quality")


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
