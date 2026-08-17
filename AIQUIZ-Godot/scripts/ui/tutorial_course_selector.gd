extends Control
class_name TutorialCourseSelector

signal course_selected(course: String)
signal dismissed

const NAVY := Color(0.025, 0.045, 0.105, 0.97)
const SOLO_COLOR := Color(1.0, 0.56, 0.17, 1.0)
const DUO_COLOR := Color(0.18, 0.86, 1.0, 1.0)

var _solo_badge: Label = null
var _duo_badge: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_selector()


func show_selector() -> void:
	_update_badges()
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.22)


func hide_selector() -> void:
	visible = false


func _build_selector() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.01, 0.04, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -470.0
	panel.offset_top = -270.0
	panel.offset_right = 470.0
	panel.offset_bottom = 270.0
	var style := StyleBoxFlat.new()
	style.bg_color = NAVY
	style.border_color = Color(0.35, 0.56, 0.96, 0.78)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 28.0
	style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	panel.add_child(root)
	var eyebrow := Label.new()
	eyebrow.text = "TUTORIAL V3"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", Color(0.52, 0.68, 0.94))
	root.add_child(eyebrow)
	var title := Label.new()
	title.text = "体験するコースを選んでください"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.24))
	root.add_child(title)
	var description := Label.new()
	description.text = "短いカメラ演出と実際の操作で、最新版のゲーム内容を順番に学びます。"
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Color(0.80, 0.86, 0.96))
	root.add_child(description)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 22)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cards)
	var solo := _create_course_card(
		"1P 実践コース",
		"走りながらの移動とジャンプ\nコース外の海とサメの危険\n誘導あり／なしのクイズとゴール",
		"約2分30秒",
		"res://assets/ui/1p.png",
		SOLO_COLOR,
		GameManager.TUTORIAL_COURSE_SOLO
	)
	cards.add_child(solo)
	_solo_badge = solo.get_node("Content/Badge") as Label
	var duo := _create_course_card(
		"ローカル2P 実践コース",
		"2人分の操作とエモート\n海とゴーストシャークで反撃\n1人ずつ判定される実戦と最終レース",
		"約4分",
		"res://assets/ui/2p.png",
		DUO_COLOR,
		GameManager.TUTORIAL_COURSE_LOCAL_2P
	)
	cards.add_child(duo)
	_duo_badge = duo.get_node("Content/Badge") as Label

	var later := Button.new()
	later.text = "あとで"
	later.custom_minimum_size = Vector2(180.0, 42.0)
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later.add_theme_font_size_override("font_size", 17)
	later.pressed.connect(func() -> void:
		dismissed.emit()
		hide_selector()
	)
	root.add_child(later)


func _create_course_card(
		title_text: String,
		detail_text: String,
		time_text: String,
		texture_path: String,
		accent: Color,
		course: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(385.0, 305.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.085, 0.16, 0.96)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.76)
	style.set_border_width_all(2)
	style.set_corner_radius_all(15)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 15.0
	style.content_margin_bottom = 16.0
	card.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)

	var badge := Label.new()
	badge.name = "Badge"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_theme_font_size_override("font_size", 14)
	content.add_child(badge)
	var icon := TextureRect.new()
	icon.texture = load(texture_path)
	icon.custom_minimum_size = Vector2(0.0, 78.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(icon)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", accent)
	content.add_child(title)
	var detail := Label.new()
	detail.text = detail_text
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 15)
	detail.add_theme_color_override("font_color", Color(0.82, 0.88, 0.98))
	content.add_child(detail)
	var time := Label.new()
	time.text = time_text
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time.add_theme_font_size_override("font_size", 13)
	time.add_theme_color_override("font_color", Color(0.55, 0.68, 0.86))
	content.add_child(time)
	var start := Button.new()
	start.text = "このコースを始める"
	start.custom_minimum_size.y = 42.0
	start.add_theme_font_size_override("font_size", 17)
	start.pressed.connect(func() -> void:
		course_selected.emit(course)
		hide_selector()
	)
	content.add_child(start)
	return card


func _update_badges() -> void:
	if _solo_badge:
		_solo_badge.text = "✓ 完了" if GameManager.tutorial_solo_completed else "未完了"
		_solo_badge.add_theme_color_override(
			"font_color", Color(0.36, 1.0, 0.60) if GameManager.tutorial_solo_completed else Color(0.62, 0.68, 0.80)
		)
	if _duo_badge:
		_duo_badge.text = "✓ 完了" if GameManager.tutorial_local_2p_completed else "未完了"
		_duo_badge.add_theme_color_override(
			"font_color", Color(0.36, 1.0, 0.60) if GameManager.tutorial_local_2p_completed else Color(0.62, 0.68, 0.80)
		)
