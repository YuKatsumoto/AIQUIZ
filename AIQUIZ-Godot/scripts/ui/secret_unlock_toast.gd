extends PanelContainer

## シークレットを解放した瞬間に、画面の上から出る知らせ。数秒で自分から消える。
## 入力は受けない（試合の操作をじゃましない）。

const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")
const GOLD := Color(1.0, 0.88, 0.25)
## 画面のいちばん上（左のハートと右の正解数のあいだ）。壁の問題文にかぶらない高さ。
const REST_TOP := 20.0
const SLIDE_FROM_TOP := -12.0
const FADE_IN_SEC := 0.35
const HOLD_SEC := 4.5
const FADE_OUT_SEC := 0.6

var _title: Label
var _detail: Label


func _init() -> void:
	name = "SecretUnlockToast"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_title = _make_label(24, GOLD)
	box.add_child(_title)
	_detail = _make_label(16, Color(0.95, 0.96, 0.97))
	box.add_child(_detail)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## id は UnlockStore の ID。ツリーに入れてから呼ぶ。
func present(id: StringName) -> void:
	_title.text = "シークレット解放！"
	_detail.text = "%s ― カスタマイズの「スキン」で乗れます" % UnlockStore.label(id)
	# 画面の上・中央に置く（幅は中身に合わせて左右へ均等に広がる）。
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = 0.0
	offset_right = 0.0
	_set_top(SLIDE_FROM_TOP)
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, FADE_IN_SEC)
	tween.tween_method(_set_top, SLIDE_FROM_TOP, REST_TOP, FADE_IN_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_interval(HOLD_SEC)
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_SEC)
	tween.tween_callback(queue_free)


## 上端の位置だけ動かす（高さは中身に合わせる）。
func _set_top(top: float) -> void:
	offset_top = top
	offset_bottom = top
