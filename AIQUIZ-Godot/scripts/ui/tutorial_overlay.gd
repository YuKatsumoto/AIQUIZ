extends Control
class_name TutorialOverlay

const P1_COLOR := Color(1.0, 0.52, 0.16, 1.0)
const P2_COLOR := Color(0.20, 0.88, 1.0, 1.0)
const SYSTEM_COLOR := Color(1.0, 0.88, 0.24, 1.0)
const CARD_SLIDE_SECONDS := 0.45
const CARD_SLIDE_DISTANCE := 360.0

var game_state: QuizGameState = null
var _center_panel: PanelContainer = null
var _progress_label: Label = null
var _title_label: Label = null
var _body_label: Label = null
var _skip_label: Label = null
var _p1_card: PanelContainer = null
var _p2_card: PanelContainer = null
var _signature: String = ""
var _p1_task_count: int = 1
var _p2_task_count: int = 1
var _p1_was_visible: bool = false
var _p2_was_visible: bool = false
var _p1_slide_elapsed: float = -1.0
var _p2_slide_elapsed: float = -1.0


func setup(state: QuizGameState) -> void:
	game_state = state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func update_overlay(delta: float = 0.0) -> void:
	if game_state == null or game_state.mode != Constants.MODE_TUTORIAL:
		visible = false
		_reset_card_slides()
		return
	var model := game_state.get_tutorial_overlay_model()
	# 開始演出中（待機・フライオーバー・カウントダウン）は本編と同じ見え方を優先
	visible = bool(model.get("visible", false)) and game_state.game_state not in [
		Constants.STATE_CLEAR,
		Constants.STATE_GAME_OVER,
		Constants.STATE_PRELOADING,
		Constants.STATE_WAITING_START,
		Constants.STATE_FLYOVER,
		Constants.STATE_COUNTDOWN,
	]
	if not visible:
		_reset_card_slides()
		return
	var locked := bool(model.get("presentation_locked", false))
	_layout_center_panel(locked)
	# The solo exercise view stays intentionally sparse: its task card is the
	# instruction. 2P keeps a shared step card so both players see the same goal.
	_center_panel.visible = locked or game_state.num_players >= 2
	_progress_label.text = "STEP %d / %d" % [
		int(model.get("step_number", 1)), int(model.get("step_count", 1))
	]
	_title_label.text = str(model.get("title", "チュートリアル"))
	_body_label.text = str(model.get("body", ""))
	_body_label.visible = locked or game_state.num_players < 2 or not game_state.tutorial_flow.is_quiz_step()
	_skip_label.text = str(model.get("skip_text", ""))
	_skip_label.visible = locked
	_center_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)

	var ghost_ready := _is_ghost_control_display_ready()
	var signature := "%s:%s:%s:%s" % [
		str(model.get("revision", 0)), str(locked), str(game_state.num_players), str(ghost_ready)
	]
	if signature != _signature:
		_signature = signature
		_rebuild_player_cards(model, locked)
	_update_card_slides(delta)


func _build_ui() -> void:
	_center_panel = PanelContainer.new()
	_center_panel.name = "TutorialStepCard"
	_center_panel.add_theme_stylebox_override("panel", _panel_style(SYSTEM_COLOR, 0.92, 16))
	add_child(_center_panel)
	var center_box := VBoxContainer.new()
	center_box.add_theme_constant_override("separation", 5)
	_center_panel.add_child(center_box)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 13)
	_progress_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.90))
	center_box.add_child(_progress_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", SYSTEM_COLOR)
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_title_label.add_theme_constant_override("outline_size", 5)
	center_box.add_child(_title_label)

	_body_label = Label.new()
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	center_box.add_child(_body_label)

	_skip_label = Label.new()
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_label.add_theme_font_size_override("font_size", 14)
	_skip_label.add_theme_color_override("font_color", Color(0.72, 0.80, 0.94))
	center_box.add_child(_skip_label)

	_p1_card = _create_player_card("P1", P1_COLOR)
	_p1_card.name = "P1TutorialTasks"
	add_child(_p1_card)
	_p2_card = _create_player_card("P2", P2_COLOR)
	_p2_card.name = "P2TutorialTasks"
	add_child(_p2_card)
	_layout_player_cards()


func _layout_center_panel(locked: bool) -> void:
	_center_panel.set_anchors_preset(Control.PRESET_CENTER_TOP if not locked else Control.PRESET_CENTER)
	_center_panel.offset_left = -290.0
	_center_panel.offset_right = 290.0
	if locked:
		_center_panel.offset_top = -112.0
		_center_panel.offset_bottom = 112.0
	else:
		var quiz_compact: bool = (
			game_state != null
			and game_state.num_players >= 2
			and game_state.tutorial_flow != null
			and game_state.tutorial_flow.is_quiz_step()
		)
		_center_panel.offset_top = 104.0 if quiz_compact else 18.0
		_center_panel.offset_bottom = 184.0 if quiz_compact else 132.0


func _layout_player_cards() -> void:
	_layout_player_card(_p1_card, 1, 1)
	_layout_player_card(_p2_card, 2, 1)


func _layout_player_card(card: PanelContainer, player_index: int, task_count: int) -> void:
	var card_height := 72.0 + float(maxi(1, task_count)) * 32.0
	var bottom_margin := 22.0
	# The existing ghost rider HUD owns the bottom corner. Keep the tutorial
	# checklist above it so charge feedback and required tasks stay readable.
	if (
		game_state != null
		and game_state.is_tutorial_ghost_practice()
		and game_state.get_tutorial_ghost_player() == player_index
	):
		bottom_margin = 116.0
	card.set_anchors_preset(
		Control.PRESET_BOTTOM_LEFT if player_index == 1 else Control.PRESET_BOTTOM_RIGHT
	)
	card.offset_top = -bottom_margin - card_height
	card.offset_bottom = -bottom_margin
	if player_index == 1:
		card.offset_left = 22.0
		card.offset_right = 330.0
	else:
		card.offset_left = -330.0
		card.offset_right = -22.0


func _create_player_card(player_label: String, accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(accent, 0.84, 13))
	var root := VBoxContainer.new()
	root.name = "Content"
	root.add_theme_constant_override("separation", 7)
	card.add_child(root)
	var header := Label.new()
	header.name = "Header"
	header.text = "%s  操作" % player_label
	header.add_theme_font_size_override("font_size", 19)
	header.add_theme_color_override("font_color", accent)
	header.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	header.add_theme_constant_override("outline_size", 4)
	root.add_child(header)
	var task_box := VBoxContainer.new()
	task_box.name = "Tasks"
	task_box.add_theme_constant_override("separation", 4)
	root.add_child(task_box)
	return card


func _rebuild_player_cards(model: Dictionary, locked: bool) -> void:
	var show_p1 := false
	var show_p2 := false
	_p1_task_count = 1
	_p2_task_count = 1
	if locked:
		_set_card_visible(_p1_card, 1, false)
		_set_card_visible(_p2_card, 2, false)
		return
	for player_variant: Variant in model.get("players", []):
		var player: Dictionary = player_variant
		var index := int(player.get("player", 0))
		var card := _p1_card if index == 1 else _p2_card
		var accent := P1_COLOR if index == 1 else P2_COLOR
		var tasks: Array = player.get("tasks", [])
		# ゴーストシャーク練習の操作カードは、サメ操作フェーズに入ってから表示する
		if (
			game_state.is_tutorial_ghost_practice()
			and index == game_state.get_tutorial_ghost_player()
			and not _is_ghost_control_display_ready()
		):
			tasks = []
		var should_show := not tasks.is_empty()
		if index == 2 and game_state.num_players < 2:
			should_show = false
		var task_box := card.get_node("Content/Tasks") as VBoxContainer
		for child: Node in task_box.get_children():
			child.queue_free()
		for task_variant: Variant in tasks:
			_add_task_row(task_box, task_variant as Dictionary, accent)
		if index == 1:
			_p1_task_count = maxi(1, tasks.size())
			show_p1 = should_show
		else:
			_p2_task_count = maxi(1, tasks.size())
			show_p2 = should_show
	_set_card_visible(_p1_card, 1, show_p1)
	_set_card_visible(_p2_card, 2, show_p2)


func _set_card_visible(card: PanelContainer, player_index: int, should_show: bool) -> void:
	var was_visible := _p1_was_visible if player_index == 1 else _p2_was_visible
	card.visible = should_show
	if should_show and not was_visible:
		if player_index == 1:
			_p1_slide_elapsed = 0.0
			_p1_was_visible = true
		else:
			_p2_slide_elapsed = 0.0
			_p2_was_visible = true
		_apply_card_slide(player_index)
	elif not should_show:
		if player_index == 1:
			_p1_was_visible = false
			_p1_slide_elapsed = -1.0
		else:
			_p2_was_visible = false
			_p2_slide_elapsed = -1.0
		card.modulate.a = 1.0
	else:
		_apply_card_slide(player_index)


func _reset_card_slides() -> void:
	_p1_was_visible = false
	_p2_was_visible = false
	_p1_slide_elapsed = -1.0
	_p2_slide_elapsed = -1.0
	if _p1_card:
		_p1_card.visible = false
		_p1_card.modulate.a = 1.0
	if _p2_card:
		_p2_card.visible = false
		_p2_card.modulate.a = 1.0


func _update_card_slides(delta: float) -> void:
	if _p1_slide_elapsed >= 0.0:
		_p1_slide_elapsed = minf(CARD_SLIDE_SECONDS, _p1_slide_elapsed + delta)
		_apply_card_slide(1)
		if _p1_slide_elapsed >= CARD_SLIDE_SECONDS:
			_p1_slide_elapsed = -1.0
	elif _p1_was_visible:
		_apply_card_slide(1)
	if _p2_slide_elapsed >= 0.0:
		_p2_slide_elapsed = minf(CARD_SLIDE_SECONDS, _p2_slide_elapsed + delta)
		_apply_card_slide(2)
		if _p2_slide_elapsed >= CARD_SLIDE_SECONDS:
			_p2_slide_elapsed = -1.0
	elif _p2_was_visible:
		_apply_card_slide(2)


func _apply_card_slide(player_index: int) -> void:
	var card := _p1_card if player_index == 1 else _p2_card
	if card == null or not card.visible:
		return
	var task_count := _p1_task_count if player_index == 1 else _p2_task_count
	var elapsed := _p1_slide_elapsed if player_index == 1 else _p2_slide_elapsed
	_layout_player_card(card, player_index, task_count)
	if elapsed < 0.0:
		card.modulate.a = 1.0
		return
	var progress := clampf(elapsed / CARD_SLIDE_SECONDS, 0.0, 1.0)
	var weight := 1.0 - pow(1.0 - progress, 3.0)
	if player_index == 1:
		var target_left := 22.0
		var target_right := 330.0
		card.offset_left = lerpf(target_left - CARD_SLIDE_DISTANCE, target_left, weight)
		card.offset_right = lerpf(target_right - CARD_SLIDE_DISTANCE, target_right, weight)
	else:
		var target_left := -330.0
		var target_right := -22.0
		card.offset_left = lerpf(target_left + CARD_SLIDE_DISTANCE, target_left, weight)
		card.offset_right = lerpf(target_right + CARD_SLIDE_DISTANCE, target_right, weight)
	card.modulate.a = weight


func _is_ghost_control_display_ready() -> bool:
	if game_state == null or not game_state.is_tutorial_ghost_practice():
		return true
	var ghost_player := game_state.get_tutorial_ghost_player()
	if ghost_player <= 0:
		return true
	var world := _find_game_world()
	if world == null or not world.has_method("is_ghost_shark_control_active"):
		return false
	return bool(world.call("is_ghost_shark_control_active", ghost_player))


func _find_game_world() -> Node:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("is_ghost_shark_control_active"):
			return node
		node = node.get_parent()
	return null


func _add_task_row(parent: VBoxContainer, task: Dictionary, accent: Color) -> void:
	var done := bool(task.get("done", false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var state_label := Label.new()
	state_label.custom_minimum_size.x = 25.0
	state_label.text = "✓" if done else "◆"
	state_label.add_theme_font_size_override("font_size", 17)
	state_label.add_theme_color_override(
		"font_color", Color(0.36, 1.0, 0.60) if done else SYSTEM_COLOR
	)
	row.add_child(state_label)

	var key_panel := PanelContainer.new()
	key_panel.custom_minimum_size = Vector2(88.0, 28.0)
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = Color(0.08, 0.11, 0.20, 0.94)
	key_style.border_color = Color(0.36, 1.0, 0.60) if done else accent
	key_style.set_border_width_all(1 if done else 2)
	key_style.set_corner_radius_all(6)
	key_style.content_margin_left = 6.0
	key_style.content_margin_right = 6.0
	key_panel.add_theme_stylebox_override("panel", key_style)
	row.add_child(key_panel)
	var key_label := Label.new()
	key_label.text = str(task.get("key", ""))
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.add_theme_color_override("font_color", Color(0.72, 1.0, 0.80) if done else Color.WHITE)
	key_panel.add_child(key_label)

	var caption := Label.new()
	caption.text = str(task.get("caption", ""))
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Color(0.58, 0.72, 0.65) if done else Color(0.88, 0.92, 1.0))
	row.add_child(caption)


func _panel_style(accent: Color, alpha: float, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.105, alpha)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.78)
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 17.0
	style.content_margin_right = 17.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style
