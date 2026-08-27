class_name ResultCeremonyOverlay
extends Control

const P1_COLOR := Color(1.0, 0.55, 0.15)
const P2_COLOR := Color(0.18, 0.78, 1.0)
const GOLD := Color(1.0, 0.79, 0.22)
const PALE_GOLD := Color(1.0, 0.91, 0.54)
const INK := Color(0.018, 0.027, 0.052)
const UI_FONT: Font = preload("res://resources/fonts/NotoSansJP-Medium.otf")
const UI_FONT_BOLD: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

var game_state: QuizGameState = null
var _retry_action: Callable
var _history_action: Callable
var _menu_action: Callable
var _suppressed: bool = false
var _interactive_focused: bool = false
var _visual_phase: int = QuizGameState.ResultCeremonyPhase.NONE
var _visual_phase_elapsed: float = 0.0

var _bottom_veil: TextureRect = null
var _roll_stage: Control = null
var _p1_roll_root: Control = null
var _p2_roll_root: Control = null
var _p1_roll_score: Label = null
var _p2_roll_score: Label = null
var _final_stage: Control = null
var _winner_root: Control = null
var _winner_title: Label = null
var _winner_name: Label = null
var _final_p1_root: Control = null
var _final_p2_root: Control = null
var _final_p1_score: Label = null
var _final_p2_score: Label = null
var _stats_panel: PanelContainer = null
var _stat_values: Array[Label] = []
var _rating_shell: PanelContainer = null
var _rating_row: HBoxContainer = null
var _rating_prompt: Label = null
var _rating_good: Button = null
var _rating_bad: Button = null
var _action_shell: PanelContainer = null
var _retry_button: Button = null


func setup(
	state: QuizGameState,
	retry_action: Callable,
	history_action: Callable,
	menu_action: Callable
) -> void:
	game_state = state
	_retry_action = retry_action
	_history_action = history_action
	_menu_action = menu_action
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_soft_veil()
	_build_roll_stage()
	_build_final_stage()
	_build_bottom_controls()
	visible = false


func set_suppressed(value: bool) -> void:
	_suppressed = value
	if value:
		visible = false
	else:
		_interactive_focused = false


func update_overlay(delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if size != viewport_size:
		position = Vector2.ZERO
		size = viewport_size
	if game_state == null:
		visible = false
		return
	var active := (
		game_state.result_presentation_active
		and game_state.game_state in [Constants.STATE_RESULT_CEREMONY, Constants.STATE_CLEAR]
	)
	visible = active and not _suppressed
	if not active:
		_reset_visual_state()
		return

	var phase := game_state.result_ceremony_phase
	if phase != _visual_phase:
		_visual_phase = phase
		_visual_phase_elapsed = 0.0
	else:
		# INTERACTIVEへ入るフレームでgame_stateはCLEARに変わり、状態側の
		# phase_elapsedは0で止まる。表示用時計はHUD側で必ず進める。
		_visual_phase_elapsed += maxf(delta, 0.0)

	var rolling := phase == QuizGameState.ResultCeremonyPhase.SCORE_ROLL
	_roll_stage.visible = rolling
	if rolling:
		_update_score_roll()

	var verdict_visible := game_state.is_result_verdict_visible()
	_final_stage.visible = verdict_visible
	if verdict_visible:
		_update_final_display()

	var interactive := phase == QuizGameState.ResultCeremonyPhase.INTERACTIVE
	_stats_panel.visible = interactive
	_rating_shell.visible = interactive and game_state.rating_target_quiz != null
	_action_shell.visible = interactive
	_bottom_veil.visible = interactive
	if interactive:
		_update_stats()
		_update_rating()
		# 最初のフレームから判読でき、以後は短く滑らかに100%へ到達する。
		# これにより状態側の時計が止まってもボタンが透明なまま残らない。
		var controls_in := lerpf(
			0.34,
			1.0,
			_ease_out_cubic(clampf(_visual_phase_elapsed / 0.34, 0.0, 1.0))
		)
		_stats_panel.modulate.a = controls_in
		_rating_shell.modulate.a = controls_in
		_action_shell.modulate.a = controls_in
		_bottom_veil.modulate.a = controls_in
		if not _interactive_focused and not _suppressed:
			_interactive_focused = true
			_retry_button.grab_focus()
	else:
		_interactive_focused = false


func _reset_visual_state() -> void:
	_visual_phase = QuizGameState.ResultCeremonyPhase.NONE
	_visual_phase_elapsed = 0.0
	_interactive_focused = false
	_roll_stage.visible = false
	_final_stage.visible = false
	_stats_panel.visible = false
	_rating_shell.visible = false
	_action_shell.visible = false
	_bottom_veil.visible = false


func _build_soft_veil() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.015, 0.025, 0.045, 0.0),
		Color(0.008, 0.015, 0.030, 0.66),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 4
	texture.height = 192
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	_bottom_veil = TextureRect.new()
	_bottom_veil.name = "CeremonyBottomVeil"
	_bottom_veil.texture = texture
	_bottom_veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bottom_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_bottom_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_veil.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_veil.offset_top = -168.0
	_bottom_veil.visible = false
	add_child(_bottom_veil)


func _build_roll_stage() -> void:
	_roll_stage = Control.new()
	_roll_stage.name = "CeremonyScoreRoll"
	_roll_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_roll_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_roll_stage)
	var p1_cluster := _create_roll_cluster("P1", P1_COLOR, true)
	_p1_roll_root = p1_cluster.root as Control
	_p1_roll_score = p1_cluster.score as Label
	var p2_cluster := _create_roll_cluster("P2", P2_COLOR, false)
	_p2_roll_root = p2_cluster.root as Control
	_p2_roll_score = p2_cluster.score as Label
	_roll_stage.visible = false


func _create_roll_cluster(player_name: String, color: Color, left_side: bool) -> Dictionary:
	var root := Control.new()
	root.name = "%sScoreRoll" % player_name
	root.anchor_left = 0.055 if left_side else 0.945
	root.anchor_right = root.anchor_left
	root.anchor_top = 0.22
	root.anchor_bottom = 0.22
	root.offset_left = 0.0 if left_side else -250.0
	root.offset_top = 0.0
	root.offset_right = 250.0 if left_side else 0.0
	root.offset_bottom = 280.0
	root.pivot_offset = Vector2(125.0, 138.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll_stage.add_child(root)
	for index in range(8):
		var length := 206.0 - float(index % 4) * 23.0
		var streak := _create_horizontal_streak(color, length, 0.34 - float(index) * 0.025)
		streak.position = Vector2(
			(16.0 + float(index % 3) * 12.0) if left_side else (226.0 - length - float(index % 3) * 12.0),
			76.0 + float(index) * 14.0
		)
		root.add_child(streak)
	var title := _create_glow_label(player_name, 28, color, 5)
	title.position = Vector2(0.0, 10.0)
	title.size = Vector2(250.0, 50.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var score := _create_glow_label("00", 108, color, 10)
	score.position = Vector2(0.0, 48.0)
	score.size = Vector2(250.0, 142.0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score.pivot_offset = Vector2(125.0, 71.0)
	root.add_child(score)
	var caption := _create_glow_label("トゥルルル…", 21, color, 5)
	caption.position = Vector2(0.0, 197.0)
	caption.size = Vector2(250.0, 42.0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(caption)
	return {"root": root, "score": score}


func _build_final_stage() -> void:
	_final_stage = Control.new()
	_final_stage.name = "CeremonyVerdict"
	_final_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_final_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_final_stage)
	var p1_cluster := _create_final_score_cluster("P1", P1_COLOR, true)
	_final_p1_root = p1_cluster.root as Control
	_final_p1_score = p1_cluster.score as Label
	var p2_cluster := _create_final_score_cluster("P2", P2_COLOR, false)
	_final_p2_root = p2_cluster.root as Control
	_final_p2_score = p2_cluster.score as Label
	_winner_root = Control.new()
	_winner_root.name = "WinnerLaurel"
	_winner_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_winner_root.offset_left = -164.0
	_winner_root.offset_top = 14.0
	_winner_root.offset_right = 164.0
	_winner_root.offset_bottom = 140.0
	_winner_root.pivot_offset = Vector2(164.0, 63.0)
	_winner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_final_stage.add_child(_winner_root)
	var glow := _create_horizontal_streak(GOLD, 250.0, 0.42)
	glow.position = Vector2(39.0, 48.0)
	glow.size.y = 28.0
	_winner_root.add_child(glow)
	_build_laurel_side(_winner_root, true)
	_build_laurel_side(_winner_root, false)
	_winner_title = _create_glow_label("勝 者", 35, GOLD, 8)
	_winner_title.position = Vector2(64.0, 4.0)
	_winner_title.size = Vector2(200.0, 54.0)
	_winner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner_root.add_child(_winner_title)
	_winner_name = _create_glow_label("P1", 33, GOLD, 8)
	_winner_name.position = Vector2(64.0, 53.0)
	_winner_name.size = Vector2(200.0, 52.0)
	_winner_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner_root.add_child(_winner_name)
	_final_stage.visible = false


func _create_final_score_cluster(player_name: String, color: Color, left_side: bool) -> Dictionary:
	var root := Control.new()
	root.name = "%sFinalScore" % player_name
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.offset_left = -358.0 if left_side else 198.0
	root.offset_top = 22.0
	root.offset_right = -198.0 if left_side else 358.0
	root.offset_bottom = 154.0
	root.pivot_offset = Vector2(80.0, 66.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_final_stage.add_child(root)
	var title := _create_glow_label(player_name, 22, color, 5)
	title.position = Vector2.ZERO
	title.size = Vector2(160.0, 36.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var score := _create_glow_label("00", 62, color, 8)
	score.position = Vector2(0.0, 27.0)
	score.size = Vector2(160.0, 86.0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(score)
	return {"root": root, "score": score}


func _build_laurel_side(parent: Control, left_side: bool) -> void:
	for index in range(6):
		var leaf := Panel.new()
		leaf.name = "LaurelLeaf%s%d" % ["L" if left_side else "R", index + 1]
		leaf.size = Vector2(21.0, 7.0)
		leaf.pivot_offset = leaf.size * 0.5
		var t := float(index) / 5.0
		var x := lerpf(31.0, 67.0, t) if left_side else lerpf(276.0, 240.0, t)
		var y := lerpf(73.0, 17.0, t)
		leaf.position = Vector2(x, y)
		leaf.rotation = deg_to_rad(lerpf(-56.0, -21.0, t) if left_side else lerpf(56.0, 21.0, t))
		leaf.add_theme_stylebox_override("panel", _panel_style(GOLD, PALE_GOLD, 1, 4))
		leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(leaf)


func _build_bottom_controls() -> void:
	_stats_panel = PanelContainer.new()
	_stats_panel.name = "CeremonyStats"
	_stats_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stats_panel.offset_left = -286.0
	_stats_panel.offset_top = -162.0
	_stats_panel.offset_right = 286.0
	_stats_panel.offset_bottom = -112.0
	_stats_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0)
	)
	add_child(_stats_panel)
	var stat_row := HBoxContainer.new()
	stat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stat_row.add_theme_constant_override("separation", 8)
	_stats_panel.add_child(stat_row)
	_create_stat_chip(stat_row, "正答率")
	_create_stat_chip(stat_row, "連続正解")
	_create_stat_chip(stat_row, "タイム")
	_rating_shell = PanelContainer.new()
	_rating_shell.name = "CeremonyRatingShell"
	_rating_shell.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_rating_shell.offset_left = -220.0
	_rating_shell.offset_top = -108.0
	_rating_shell.offset_right = 220.0
	_rating_shell.offset_bottom = -72.0
	_rating_shell.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.018, 0.033, 0.058, 0.76), Color(1.0, 1.0, 1.0, 0.17), 1, 12, 5.0)
	)
	add_child(_rating_shell)
	_rating_row = HBoxContainer.new()
	_rating_row.name = "CeremonyRating"
	_rating_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_rating_row.add_theme_constant_override("separation", 9)
	_rating_shell.add_child(_rating_row)
	_rating_prompt = Label.new()
	_rating_prompt.text = "この問題を評価"
	_rating_prompt.add_theme_font_override("font", UI_FONT)
	_rating_prompt.add_theme_font_size_override("font_size", 13)
	_rating_prompt.add_theme_color_override("font_color", Color(0.91, 0.94, 1.0))
	_rating_prompt.add_theme_color_override("font_outline_color", INK)
	_rating_prompt.add_theme_constant_override("outline_size", 4)
	_rating_row.add_child(_rating_prompt)
	_rating_good = _create_small_button("◯  良い")
	_rating_good.pressed.connect(func(): game_state.rate_last_question(true); _update_rating())
	_rating_row.add_child(_rating_good)
	_rating_bad = _create_small_button("×  悪い")
	_rating_bad.pressed.connect(func(): game_state.rate_last_question(false); _update_rating())
	_rating_row.add_child(_rating_bad)
	_action_shell = PanelContainer.new()
	_action_shell.name = "CeremonyActionBar"
	_action_shell.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_shell.offset_left = -322.0
	_action_shell.offset_top = -66.0
	_action_shell.offset_right = 322.0
	_action_shell.offset_bottom = -10.0
	_action_shell.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.008, 0.018, 0.035, 0.46), Color(1.0, 1.0, 1.0, 0.12), 1, 16, 8.0)
	)
	add_child(_action_shell)
	var button_row := HBoxContainer.new()
	button_row.name = "CeremonyActions"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 8)
	_action_shell.add_child(button_row)
	_retry_button = _create_action_button("もう一度")
	_retry_button.pressed.connect(func(): _retry_action.call())
	button_row.add_child(_retry_button)
	var history_button := _create_action_button("履歴")
	history_button.pressed.connect(func(): _history_action.call())
	button_row.add_child(history_button)
	var menu_button := _create_action_button("メニュー")
	menu_button.pressed.connect(func(): _menu_action.call())
	button_row.add_child(menu_button)


func _update_score_roll() -> void:
	var step := int(_visual_phase_elapsed * 12.0)
	_p1_roll_score.text = "%d" % ((step * 7 + 3) % 11)
	_p2_roll_score.text = "%d" % ((step * 5 + 8) % 11)
	var entrance := _ease_out_back(clampf(_visual_phase_elapsed / 0.42, 0.0, 1.0))
	var alpha := clampf(_visual_phase_elapsed / 0.20, 0.0, 1.0)
	var pulse := 1.0 + sin(_visual_phase_elapsed * 28.0) * 0.035
	_p1_roll_root.scale = Vector2.ONE * lerpf(0.76, 1.0, entrance)
	_p2_roll_root.scale = Vector2.ONE * lerpf(0.76, 1.0, entrance)
	_p1_roll_root.modulate.a = alpha
	_p2_roll_root.modulate.a = alpha
	_p1_roll_score.scale = Vector2.ONE * pulse
	_p2_roll_score.scale = Vector2.ONE * pulse


func _update_final_display() -> void:
	_final_p1_score.text = "%d" % game_state.result_p1_score
	_final_p2_score.text = "%d" % game_state.result_p2_score
	var winner := game_state.result_winner
	if winner == 1:
		_winner_title.text = "勝 者"
		_winner_name.text = "P1"
	elif winner == 2:
		_winner_title.text = "勝 者"
		_winner_name.text = "P2"
	else:
		_winner_title.text = "引き分け"
		_winner_name.text = "DRAW"
	_final_p1_root.modulate.a = 0.52 if winner == 2 else 1.0
	_final_p2_root.modulate.a = 0.52 if winner == 1 else 1.0
	var reveal := _ease_out_back(clampf((_visual_phase_elapsed - 0.48) / 0.30, 0.0, 1.0))
	_winner_root.scale = Vector2.ONE * lerpf(0.72, 1.0, reveal)
	_winner_root.modulate.a = clampf((_visual_phase_elapsed - 0.48) / 0.20, 0.0, 1.0)
	_final_p1_root.scale = Vector2.ONE * lerpf(0.92, 1.0, clampf(reveal, 0.0, 1.0))
	_final_p2_root.scale = _final_p1_root.scale


func _create_stat_chip(parent: HBoxContainer, title_text: String) -> void:
	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(174.0, 46.0)
	shell.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.015, 0.030, 0.052, 0.72), Color(1.0, 1.0, 1.0, 0.16), 1, 12, 5.0)
	)
	parent.add_child(shell)
	var chip := VBoxContainer.new()
	chip.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_theme_constant_override("separation", -2)
	shell.add_child(chip)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UI_FONT)
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.69, 0.76, 0.86, 0.96))
	chip.add_child(title)
	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_override("font", UI_FONT_BOLD)
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0))
	chip.add_child(value)
	_stat_values.append(value)


func _update_stats() -> void:
	if _stat_values.size() < 3:
		return
	var denominator := maxi(1, game_state.target_count)
	var best_score := maxi(game_state.result_p1_score, game_state.result_p2_score)
	var accuracy := float(best_score) / float(denominator) * 100.0
	var minutes := floori(game_state.play_time / 60.0)
	var seconds := int(game_state.play_time) % 60
	_stat_values[0].text = "%.0f%%" % accuracy
	_stat_values[1].text = "%d" % game_state.max_streak
	_stat_values[2].text = "%d:%02d" % [minutes, seconds]


func _update_rating() -> void:
	var has_feedback := not game_state.rating_feedback.is_empty()
	_rating_prompt.text = game_state.rating_feedback if has_feedback else "この問題を評価"
	_rating_good.visible = not has_feedback
	_rating_bad.visible = not has_feedback


func _create_glow_label(text_value: String, font_size: int, color: Color, outline: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", UI_FONT_BOLD)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.045, 0.92))
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.54))
	label.add_theme_constant_override("shadow_outline_size", maxi(2, int(round(float(outline) * 0.5))))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _create_horizontal_streak(color: Color, width: float, alpha: float) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.82, 1.0])
	gradient.colors = PackedColorArray([
		Color(color.r, color.g, color.b, 0.0),
		Color(color.r, color.g, color.b, alpha),
		Color(color.r, color.g, color.b, alpha),
		Color(color.r, color.g, color.b, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var streak := TextureRect.new()
	streak.texture = texture
	streak.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	streak.stretch_mode = TextureRect.STRETCH_SCALE
	streak.size = Vector2(width, 3.0)
	streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return streak


func _create_action_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(196.0, 44.0)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", UI_FONT_BOLD)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.025, 0.045, 0.075, 0.78), Color(1.0, 1.0, 1.0, 0.14), 1, 11))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.18, 0.25, 0.92), Color(1.0, 0.91, 0.55, 0.72), 1, 11))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.08, 0.025, 0.94), GOLD, 2, 11))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.18, 0.13, 0.025, 0.94), PALE_GOLD, 2, 11, 5.0))
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 0.94))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	return button


func _create_small_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(96.0, 32.0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", UI_FONT)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.045, 0.075, 0.11, 0.82), Color(1.0, 1.0, 1.0, 0.18), 1, 9))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.18, 0.25, 0.96), PALE_GOLD, 1, 9))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.08, 0.025, 1.0), GOLD, 2, 9))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.08, 0.10, 0.14, 0.92), PALE_GOLD, 2, 9))
	button.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	return button


func _button_style(
	background: Color,
	border: Color,
	border_width: int,
	corner_radius: int,
	shadow_size: float = 0.0
) -> StyleBoxFlat:
	var style := _panel_style(background, border, border_width, corner_radius, shadow_size)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _panel_style(
	background: Color,
	border: Color,
	border_width: int,
	corner_radius: int = 5,
	shadow_size: float = 0.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	if shadow_size > 0.0:
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
		style.shadow_size = int(shadow_size)
		style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _ease_out_cubic(value: float) -> float:
	var inverse := 1.0 - value
	return 1.0 - inverse * inverse * inverse


func _ease_out_back(value: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(value - 1.0, 3.0) + c1 * pow(value - 1.0, 2.0)
