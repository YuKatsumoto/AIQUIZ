extends CanvasLayer
class_name RaceHUD

const BIKE_RULES_SCRIPT = preload("res://scripts/core/bike_race_rules.gd")

var _root: Control
var _section_label: Label
var _distance_label: Label
var _p1_speed: Label
var _p2_speed: Label
var _p1_status: Label
var _p2_status: Label
var _p1_stamina: ProgressBar
var _p2_stamina: ProgressBar
var _course_progress: ProgressBar
var _help_label: Label
var _intro_timer: float = 0.0


func _ready() -> void:
	layer = 35
	_build_hud()
	visible = false


func update_from_state(gs: QuizGameState, course, dt: float) -> void:
	visible = gs.game_state == Constants.STATE_ATHLETIC_RACE
	if not visible:
		_intro_timer = 0.0
		return
	_intro_timer += dt
	var p1_progress: float = clampf(gs.player_z - gs.bike_start_z, 0.0, BIKE_RULES_SCRIPT.COURSE_LENGTH)
	var p2_progress: float = clampf(gs.player2_z - gs.bike_start_z, 0.0, BIKE_RULES_SCRIPT.COURSE_LENGTH)
	var leader_progress: float = maxf(p1_progress, p2_progress)
	var section_name: String = course.get_section_name(leader_progress) if course != null else "ママチャリ"
	_section_label.text = "🚲  %s" % section_name
	_distance_label.text = "P1 %.0fm  •  P2 %.0fm  /  %.0fm" % [p1_progress, p2_progress, BIKE_RULES_SCRIPT.COURSE_LENGTH]
	_p1_speed.text = "P1  %3d km/h" % roundi(gs.bike_p1_speed * 3.6)
	_p2_speed.text = "P2  %3d km/h" % roundi(gs.bike_p2_speed * 3.6)
	_p1_stamina.value = gs.bike_p1_stamina * 100.0
	_p2_stamina.value = gs.bike_p2_stamina * 100.0
	_course_progress.value = leader_progress / BIKE_RULES_SCRIPT.COURSE_LENGTH * 100.0
	_p1_status.text = _status_text(gs, 1, p1_progress, p2_progress)
	_p2_status.text = _status_text(gs, 2, p2_progress, p1_progress)
	_help_label.visible = _intro_timer < 5.5
	if _help_label.visible:
		_help_label.modulate.a = 1.0 if _intro_timer < 4.3 else clampf((5.5 - _intro_timer) / 1.2, 0.0, 1.0)


func _status_text(gs: QuizGameState, player_index: int, own_progress: float, other_progress: float) -> String:
	var recovery_state: String = (
		gs.bike_p1_recovery_state
		if player_index == 1
		else gs.bike_p2_recovery_state
	)
	var start_delay: float = gs.bike_p1_start_delay if player_index == 1 else gs.bike_p2_start_delay
	var slipstream: bool = gs.bike_p1_slipstream if player_index == 1 else gs.bike_p2_slipstream
	var boosting: bool = gs.bike_p1_boosting if player_index == 1 else gs.bike_p2_boosting
	var checkpoint: int = gs.bike_p1_checkpoint if player_index == 1 else gs.bike_p2_checkpoint
	if recovery_state == BIKE_RULES_SCRIPT.RIDER_TUMBLING:
		return "自転車ごとラグドール転倒中"
	if start_delay > 0.0:
		return "スタート待ち %.1fs" % start_delay
	if boosting:
		return "立ち漕ぎ BOOST"
	if slipstream:
		return "SLIPSTREAM +1.2m/s"
	var rank: String = "1st" if own_progress >= other_progress else "2nd"
	return "%s  CP %d/%d" % [rank, checkpoint + 1, BIKE_RULES_SCRIPT.CHECKPOINTS.size()]


func _build_hud() -> void:
	_root = Control.new()
	_root.name = "RaceHUDRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "RacePanel"
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.025
	panel.anchor_bottom = 0.235
	panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(panel)

	var vertical: VBoxContainer = VBoxContainer.new()
	vertical.add_theme_constant_override("separation", 5)
	panel.add_child(vertical)

	_section_label = _make_label("🚲  ママチャリ", 25, Color(1.0, 0.86, 0.28), HORIZONTAL_ALIGNMENT_CENTER)
	vertical.add_child(_section_label)
	_distance_label = _make_label("P1 0m • P2 0m", 16, Color(0.86, 0.91, 0.98), HORIZONTAL_ALIGNMENT_CENTER)
	vertical.add_child(_distance_label)

	var racers: HBoxContainer = HBoxContainer.new()
	racers.add_theme_constant_override("separation", 18)
	vertical.add_child(racers)
	var p1_box: VBoxContainer = _make_racer_box(1)
	var p2_box: VBoxContainer = _make_racer_box(2)
	racers.add_child(p1_box)
	racers.add_child(p2_box)

	_course_progress = ProgressBar.new()
	_course_progress.custom_minimum_size = Vector2(0.0, 10.0)
	_course_progress.show_percentage = false
	_course_progress.min_value = 0.0
	_course_progress.max_value = 100.0
	_course_progress.add_theme_stylebox_override("background", _bar_style(Color(0.05, 0.07, 0.11, 0.88), 5.0))
	_course_progress.add_theme_stylebox_override("fill", _bar_style(Color(0.35, 0.92, 0.60), 5.0))
	vertical.add_child(_course_progress)

	_help_label = _make_label("走行: W / ↑　操舵: A D / ← →　障害物に当たると自転車ごと転倒", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_help_label.anchor_left = 0.08
	_help_label.anchor_right = 0.92
	_help_label.anchor_top = 0.82
	_help_label.anchor_bottom = 0.90
	_help_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_help_label.add_theme_constant_override("shadow_offset_x", 2)
	_help_label.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_help_label)


func _make_racer_box(player_index: int) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var color: Color = Color(1.0, 0.50, 0.14) if player_index == 1 else Color(0.18, 0.64, 1.0)
	var speed_label: Label = _make_label("P%d  0 km/h" % player_index, 19, color, HORIZONTAL_ALIGNMENT_LEFT)
	var stamina: ProgressBar = ProgressBar.new()
	stamina.custom_minimum_size = Vector2(220.0, 13.0)
	stamina.min_value = 0.0
	stamina.max_value = 100.0
	stamina.value = 100.0
	stamina.show_percentage = false
	stamina.add_theme_stylebox_override("background", _bar_style(Color(0.04, 0.05, 0.08, 0.95), 5.0))
	stamina.add_theme_stylebox_override("fill", _bar_style(color, 5.0))
	var status: Label = _make_label("1st  CP 1/5", 14, Color(0.82, 0.87, 0.94), HORIZONTAL_ALIGNMENT_LEFT)
	box.add_child(speed_label)
	box.add_child(stamina)
	box.add_child(status)
	if player_index == 1:
		_p1_speed = speed_label
		_p1_stamina = stamina
		_p1_status = status
	else:
		_p2_speed = speed_label
		_p2_stamina = stamina
		_p2_status = status
	return box


func _make_label(text: String, size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	var font: Font = load("res://resources/fonts/NotoSansJP-Regular.otf") as Font
	if font != null:
		label.add_theme_font_override("font", font)
	return label


func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.065, 0.88)
	style.border_color = Color(0.35, 0.70, 1.0, 0.70)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _bar_style(color: Color, radius: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(roundi(radius))
	return style
