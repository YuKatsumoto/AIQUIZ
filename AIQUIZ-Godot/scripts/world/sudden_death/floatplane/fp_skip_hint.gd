extends CanvasLayer

## 「SPACE でスキップ」の表示（docs/sudden_death_v2/c130_float.md 12 章）。画面の右下に、角の丸い暗い半透明の帯：
## 左に白いキーキャップ「SPACE」、右に白い太字の「でスキップ」（英語の画面は「SKIP」）。
## FloatplaneStaging が毎フレーム set_shown(監督の can_skip()) を呼ぶ。出し入れは少しの時間でなめらかに。

const FONT_BOLD: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const LAYER := 9                 # サドンデスの HUD（8）の上、ポーズの画面（100）の下
const FADE_IN := 0.25
const FADE_OUT := 0.18
const MARGIN := Vector2(28.0, 26.0)

var _root: Control = null
var _label: Label = null
var _amount := 0.0
var _shown := false
var _english := false


func _init() -> void:
	name = "SkipHint"
	layer = LAYER
	_build()


func set_shown(shown: bool, english := false) -> void:
	_shown = shown
	if english != _english:
		_english = english
		_label.text = "SKIP" if english else "でスキップ"


func advance(delta: float) -> void:
	var rate := 1.0 / (FADE_IN if _shown else FADE_OUT)
	_amount = move_toward(_amount, 1.0 if _shown else 0.0, rate * maxf(delta, 0.0))
	_root.visible = _amount > 0.001
	_root.modulate.a = _amount
	_root.position.x = (1.0 - smoothstep(0.0, 1.0, _amount)) * 18.0


func _build() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	holder.add_child(_root)
	var band := PanelContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	band.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	band.grow_vertical = Control.GROW_DIRECTION_BEGIN
	band.offset_left = -MARGIN.x
	band.offset_right = -MARGIN.x
	band.offset_top = -MARGIN.y
	band.offset_bottom = -MARGIN.y
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.11, 0.62)
	bg.set_corner_radius_all(14)
	bg.content_margin_left = 14.0
	bg.content_margin_right = 18.0
	bg.content_margin_top = 9.0
	bg.content_margin_bottom = 9.0
	band.add_theme_stylebox_override("panel", bg)
	_root.add_child(band)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	band.add_child(row)
	# キーキャップ：白い角丸の板に濃い字、下に少し厚み
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cap_box := StyleBoxFlat.new()
	cap_box.bg_color = Color(0.97, 0.98, 1.0)
	cap_box.set_corner_radius_all(6)
	cap_box.border_width_bottom = 3
	cap_box.border_color = Color(0.70, 0.74, 0.82)
	cap_box.content_margin_left = 12.0
	cap_box.content_margin_right = 12.0
	cap_box.content_margin_top = 2.0
	cap_box.content_margin_bottom = 3.0
	cap.add_theme_stylebox_override("panel", cap_box)
	row.add_child(cap)
	var key := Label.new()
	key.text = "SPACE"
	key.add_theme_font_override("font", FONT_BOLD)
	key.add_theme_font_size_override("font_size", 17)
	key.add_theme_color_override("font_color", Color(0.06, 0.08, 0.14))
	cap.add_child(key)
	_label = Label.new()
	_label.text = "でスキップ"
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label.add_theme_font_override("font", FONT_BOLD)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	row.add_child(_label)
