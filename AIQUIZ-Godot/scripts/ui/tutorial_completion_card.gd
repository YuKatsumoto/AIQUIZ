extends Control
class_name TutorialCompletionCard

signal hold_completed
signal dismissed

var _card: PanelContainer
var _step_label: Label
var _title_label: Label
var _body_label: Label
var _progress_label: Label
var _footer_label: Label
var _time_bar: ProgressBar
var _auto_seconds: float = 0.0
var _auto_dismiss: bool = false
var _elapsed: float = 0.0
var _holding: bool = false
var _hold_emitted: bool = false
var _dismissing: bool = false
var _confetti_fired: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 500

	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.018, 0.045, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.z_index = 2
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(640.0, 300.0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.025, 0.055, 0.105, 0.985)
	card_style.border_color = Color(1.0, 0.78, 0.18, 0.98)
	card_style.set_border_width_all(3)
	card_style.set_corner_radius_all(24)
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	card_style.shadow_size = 18
	card_style.content_margin_left = 42.0
	card_style.content_margin_right = 42.0
	card_style.content_margin_top = 28.0
	card_style.content_margin_bottom = 26.0
	_card.add_theme_stylebox_override("panel", card_style)
	center.add_child(_card)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(content)

	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_font_size_override("font_size", 14)
	_step_label.add_theme_color_override("font_color", Color(0.58, 0.74, 0.96))
	content.add_child(_step_label)

	var check := Label.new()
	check.text = "✓"
	check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check.add_theme_font_size_override("font_size", 48)
	check.add_theme_color_override("font_color", Color(0.34, 1.0, 0.60))
	content.add_child(check)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.28))
	content.add_child(_title_label)

	_body_label = Label.new()
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 18)
	_body_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	content.add_child(_body_label)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 16)
	_progress_label.add_theme_color_override("font_color", Color(0.48, 0.96, 0.72))
	content.add_child(_progress_label)

	_footer_label = Label.new()
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_label.add_theme_font_size_override("font_size", 13)
	_footer_label.add_theme_color_override("font_color", Color(0.62, 0.70, 0.84))
	content.add_child(_footer_label)

	_time_bar = ProgressBar.new()
	_time_bar.custom_minimum_size = Vector2(0.0, 8.0)
	_time_bar.min_value = 0.0
	_time_bar.max_value = 100.0
	_time_bar.value = 0.0
	_time_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.10, 0.15, 0.24, 0.95)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(1.0, 0.76, 0.18, 1.0)
	bar_fill.set_corner_radius_all(4)
	_time_bar.add_theme_stylebox_override("background", bar_bg)
	_time_bar.add_theme_stylebox_override("fill", bar_fill)
	content.add_child(_time_bar)

	modulate.a = 0.0
	set_process(false)


func present(config: Dictionary) -> void:
	_step_label.text = str(config.get("step", ""))
	_title_label.text = str(config.get("title", "チュートリアル完了！"))
	_body_label.text = str(config.get("body", ""))
	_progress_label.text = str(config.get("progress", ""))
	_footer_label.text = str(config.get("footer", "自動で次へ進みます"))
	_auto_seconds = maxf(0.1, float(config.get("duration", 3.0)))
	# シーンが切り替わらない呼び出し元（2Pコース完了→リザルト）では、
	# カードが入力を飲み込んだまま残らないよう自分で閉じる。
	_auto_dismiss = bool(config.get("auto_dismiss", false))
	_elapsed = 0.0
	_holding = true
	_hold_emitted = false
	_time_bar.value = 0.0
	set_process(true)
	call_deferred("_play_entrance")
	call_deferred("_fire_confetti")


func _play_entrance() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.92, 0.92)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.28)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.34)


func _fire_confetti() -> void:
	if _confetti_fired or not is_inside_tree():
		return
	_confetti_fired = true
	var colors := [
		Color(1.0, 0.78, 0.18),
		Color(0.28, 0.78, 1.0),
		Color(0.34, 1.0, 0.60),
		Color(1.0, 0.38, 0.42),
		Color(0.76, 0.45, 1.0),
		Color.WHITE,
	]
	var burst_origin := get_viewport_rect().size * Vector2(0.5, 0.38)
	for color in colors:
		var emitter := CPUParticles2D.new()
		emitter.z_index = 1
		emitter.one_shot = true
		emitter.explosiveness = 0.94
		emitter.amount = GraphicsQuality.particle_amount(9, GameManager.graphics_quality)
		emitter.lifetime = 2.7
		emitter.position = burst_origin
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emitter.emission_rect_extents = Vector2(64.0, 14.0)
		emitter.direction = Vector2.UP
		emitter.spread = 72.0
		emitter.gravity = Vector2(0.0, 780.0)
		emitter.initial_velocity_min = 330.0
		emitter.initial_velocity_max = 720.0
		emitter.angular_velocity_min = -660.0
		emitter.angular_velocity_max = 660.0
		emitter.scale_amount_min = 7.0
		emitter.scale_amount_max = 13.0
		emitter.color = color
		var fade := Gradient.new()
		fade.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
		fade.add_point(0.72, Color(1.0, 1.0, 1.0, 1.0))
		fade.add_point(1.0, Color(1.0, 1.0, 1.0, 0.0))
		emitter.color_ramp = fade
		add_child(emitter)
		emitter.emitting = true
		# カードが先に閉じても解放済みノードを掴んだままにならないよう、
		# ツリータイマーのラムダではなくエミッタ自身の完了通知で片付ける。
		emitter.finished.connect(emitter.queue_free)


func _process(delta: float) -> void:
	if not _holding or _hold_emitted:
		return
	_elapsed = minf(_auto_seconds, _elapsed + delta)
	_time_bar.value = (_elapsed / _auto_seconds) * 100.0
	if _elapsed >= _auto_seconds:
		_hold_emitted = true
		set_process(false)
		hold_completed.emit()
		if _auto_dismiss:
			dismiss()


func dismiss() -> void:
	if _dismissing:
		return
	_dismissing = true
	_holding = false
	set_process(false)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.26)
	tween.tween_property(_card, "scale", Vector2(0.96, 0.96), 0.26)
	await tween.finished
	dismissed.emit()
	queue_free()


func _input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()
