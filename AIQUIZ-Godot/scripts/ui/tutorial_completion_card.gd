extends Control
class_name TutorialCompletionCard

## チュートリアルのクリア画面（V7）。
## チェックと「TUTORIAL CLEAR」の見出しの下に、1P はクリアタイムと残りハート、
## 2P はクリアタイムとスコアタワーの結果（1行）を出す。成績の評価（メダルなど）は付けない。
## 一定時間で自動的に次（カスタマイズ紹介）へ進み、MIN_SECONDS 見せた後は Enter で先へ進める。
##
## present() の config:
##   course_label: String           例「1P コース」
##   stats: Array[Dictionary]       {"value", "label"}
##   result_line: String            2P のスコアタワーの結果（なければ出さない）
##   next: String                   例「次はカスタマイズ紹介」
##   duration: float                自動で次へ進むまでの秒数
##   auto_dismiss: bool             時間が来たら自分で閉じるか

signal hold_completed
signal dismissed

## これより早い Enter は飲み込む（見せ切る前に誤って飛ばさない）。
const MIN_SECONDS := 1.0
const CHECK_SIZE := 64.0

var _card: PanelContainer
var _course_label: Label
var _title_label: Label
var _check: Control
var _stat_row: HBoxContainer
var _result_label: Label
var _next_label: Label
var _time_fill: ColorRect
var _time_track: Control
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
	dim.color = Color(0.005, 0.018, 0.045, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.z_index = 2
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_card = PanelContainer.new()
	_card.name = "ClearCard"
	_card.custom_minimum_size = Vector2(780.0, 0.0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_style := TutorialUiStyle.box(
		TutorialUiStyle.PANEL_SOLID, Color(TutorialUiStyle.ACCENT, 0.85), 2, 26, 40.0, 0.0
	)
	card_style.content_margin_top = 30.0
	card_style.content_margin_bottom = 26.0
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	card_style.shadow_size = 24
	_card.add_theme_stylebox_override("panel", card_style)
	center.add_child(_card)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(content)

	_course_label = _centered(TutorialUiStyle.make_label("", 14, TutorialUiStyle.MUTED))
	content.add_child(_course_label)
	_check = TutorialUiStyle.glyph_disc("check", CHECK_SIZE, TutorialUiStyle.DONE, Color("05301a"))
	_check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_check.pivot_offset = Vector2(CHECK_SIZE, CHECK_SIZE) * 0.5
	content.add_child(_check)
	_title_label = _centered(TutorialUiStyle.make_label("TUTORIAL CLEAR", 52, TutorialUiStyle.ACCENT))
	_title_label.add_theme_constant_override("line_spacing", 0)
	content.add_child(_title_label)

	_stat_row = HBoxContainer.new()
	_stat_row.name = "Stats"
	_stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_stat_row.add_theme_constant_override("separation", 14)
	content.add_child(_stat_row)

	_result_label = _centered(TutorialUiStyle.make_label("", 17, TutorialUiStyle.TEXT))
	content.add_child(_result_label)

	var next_row := HBoxContainer.new()
	next_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_row.alignment = BoxContainer.ALIGNMENT_CENTER
	next_row.add_theme_constant_override("separation", 10)
	content.add_child(next_row)
	_next_label = TutorialUiStyle.make_label("", 15, TutorialUiStyle.MUTED)
	_next_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next_row.add_child(_next_label)
	var enter_chip := TutorialKeyChip.new()
	enter_chip.setup("Enter", TutorialKeyChip.Look.IDLE, TutorialUiStyle.ACCENT, 24.0)
	next_row.add_child(enter_chip)
	_time_track = Panel.new()
	_time_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_track.custom_minimum_size = Vector2(160.0, 5.0)
	_time_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_track.clip_contents = true
	_time_track.add_theme_stylebox_override("panel", TutorialUiStyle.box(Color(1.0, 1.0, 1.0, 0.14), Color.TRANSPARENT, 0, 3))
	next_row.add_child(_time_track)
	_time_fill = ColorRect.new()
	_time_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_fill.color = TutorialUiStyle.ACCENT
	_time_fill.size = Vector2(0.0, 5.0)
	_time_track.add_child(_time_fill)

	modulate.a = 0.0
	set_process(false)


func _centered(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func present(config: Dictionary) -> void:
	_course_label.text = str(config.get("course_label", ""))
	_course_label.visible = not _course_label.text.is_empty()
	_title_label.text = str(config.get("title", "TUTORIAL CLEAR"))
	_build_stats(config.get("stats", []))
	_result_label.text = str(config.get("result_line", ""))
	_result_label.visible = not _result_label.text.is_empty()
	_next_label.text = str(config.get("next", "次へ進みます"))
	_auto_seconds = maxf(0.1, float(config.get("duration", 4.0)))
	# シーンが切り替わらない呼び出し元では、カードが入力を飲み込んだまま残らないよう自分で閉じる。
	_auto_dismiss = bool(config.get("auto_dismiss", false))
	_elapsed = 0.0
	_holding = true
	_hold_emitted = false
	set_process(true)
	call_deferred("_play_entrance")
	call_deferred("_fire_confetti")


func _build_stats(stats: Array) -> void:
	for child: Node in _stat_row.get_children():
		child.queue_free()
	for stat_variant: Variant in stats:
		var stat: Dictionary = stat_variant
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", TutorialUiStyle.box(Color(1.0, 1.0, 1.0, 0.06), Color.TRANSPARENT, 0, 12, 20.0, 8.0))
		_stat_row.add_child(panel)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 0)
		panel.add_child(column)
		column.add_child(_centered(TutorialUiStyle.make_label(str(stat.get("value", "")), 26, Color.WHITE)))
		column.add_child(_centered(TutorialUiStyle.make_label(str(stat.get("label", "")), 12, TutorialUiStyle.MUTED)))
	_stat_row.visible = not stats.is_empty()


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
	# チェックはカードより少し遅れて押されるように出す。
	_check.scale = Vector2.ZERO
	tween.tween_property(_check, "scale", Vector2.ONE, 0.32).set_delay(0.22)


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
	_time_fill.size = Vector2(_time_track.size.x * (_elapsed / _auto_seconds), 5.0)
	if _elapsed >= _auto_seconds:
		_finish_hold()


func _finish_hold() -> void:
	if _hold_emitted:
		return
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


## テスト用。表示中の見出しと数値。
func get_debug_snapshot() -> Dictionary:
	return {
		"title": _title_label.text,
		"course": _course_label.text,
		"stats": _stat_row.get_child_count(),
		"result_line": _result_label.text,
		"elapsed": _elapsed,
	}


## カードの間はほかの操作を通さない。MIN_SECONDS 見せた後の Enter だけは、
## ゲーム側（クリア画面の演出を早送りする処理）へ渡す。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if (
		key != null
		and key.pressed
		and not key.echo
		and key.keycode in [KEY_ENTER, KEY_KP_ENTER]
		and _elapsed >= MIN_SECONDS
	):
		return
	get_viewport().set_input_as_handled()
