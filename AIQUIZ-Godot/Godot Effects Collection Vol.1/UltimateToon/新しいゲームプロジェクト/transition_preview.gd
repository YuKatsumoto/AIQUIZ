extends Control

# Godot Modular Transitions のプリセット確認用。
# ←/→: 切り替え  Space: 自動再生のオン/オフ  スライダー: factor を手動操作

const DEMO_SCENE := preload("res://assets/TransitionKit/demo.tscn")
const BACKGROUND := preload("res://preview.png")
const PLAY_SECONDS := 1.6

var _transitions: Array = []
var _index := 0
var _auto_play := true
var _time := 0.0

var _name_label: Label
var _slider: HSlider
var _auto_check: CheckBox


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# demo.tscn の調整済みインスタンスをそのまま使う
	var demo := DEMO_SCENE.instantiate()
	add_child(demo)
	for child in demo.get_node("CanvasLayer").get_children():
		if child is ColorRect and "factor" in child:
			_transitions.append(child)

	_build_hud()
	_show(0)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	panel.add_child(box)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_name_label)

	var nav := HBoxContainer.new()
	box.add_child(nav)
	var prev := Button.new()
	prev.text = "◀ 前"
	prev.pressed.connect(func() -> void: _show(_index - 1))
	prev.focus_mode = Control.FOCUS_NONE
	nav.add_child(prev)
	var next := Button.new()
	next.text = "次 ▶"
	next.pressed.connect(func() -> void: _show(_index + 1))
	next.focus_mode = Control.FOCUS_NONE
	nav.add_child(next)
	_auto_check = CheckBox.new()
	_auto_check.text = "自動再生"
	_auto_check.button_pressed = _auto_play
	_auto_check.toggled.connect(func(on: bool) -> void: _auto_play = on)
	_auto_check.focus_mode = Control.FOCUS_NONE
	nav.add_child(_auto_check)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value_changed.connect(_on_slider_changed)
	_slider.focus_mode = Control.FOCUS_NONE
	box.add_child(_slider)

	var hint := Label.new()
	hint.text = "←/→: 切り替え   Space: 自動再生   スライダー: factor"
	hint.add_theme_font_size_override("font_size", 13)
	box.add_child(hint)


func _show(index: int) -> void:
	_index = wrapi(index, 0, _transitions.size())
	for i in _transitions.size():
		_transitions[i].visible = i == _index
	_time = 0.0
	_update_label()


func _update_label() -> void:
	var t = _transitions[_index]
	_name_label.text = "%d / %d  %s   factor %.2f" % [_index + 1, _transitions.size(), t.name, t.factor]


func _process(delta: float) -> void:
	if not _auto_play:
		return
	_time += delta
	# 0 → 1 → 0 を往復させる
	var f := pingpong(_time / PLAY_SECONDS, 1.0)
	_slider.set_value_no_signal(f)
	_transitions[_index].factor = f
	_update_label()


func _on_slider_changed(value: float) -> void:
	_auto_play = false
	_auto_check.set_pressed_no_signal(false)
	_transitions[_index].factor = value
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		_show(_index + 1)
	elif event.is_action_pressed("ui_left"):
		_show(_index - 1)
	elif event.is_action_pressed("ui_accept"):
		_auto_play = not _auto_play
		_auto_check.set_pressed_no_signal(_auto_play)
