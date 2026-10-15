extends BaseButton
class_name SkinPresetThumb

## 「おすすめ」のサムネイル。全身のミニ人形と名前。押すと全身にその見た目を当てる。

var preset_id: StringName
var _map: SkinBodyMap
var _hovered := false


func _init(p_preset_id: StringName = &"standard") -> void:
	preset_id = p_preset_id
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(52, 70)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "「%s」を全身にあてる（あとで「もどす」で取り消せます）" % PlayerSkin.preset_label(preset_id)
	_map = SkinBodyMap.new()
	_map.interactive = false
	_map.padding = 3.0
	add_child(_map)


func _ready() -> void:
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(_layout)
	_layout()


## head_locked なら あたまは標準色で見せる（当てても あたまは変わらないため）。
func show_for_slot(slot: int, head_locked: bool = false) -> void:
	var skin := PlayerSkin.preset_skin(preset_id, slot)
	_map.set_skin(PlayerSkin.with_default_head(skin, slot) if head_locked else PlayerSkin.resolve(skin, slot))


func _set_hover(value: bool) -> void:
	_hovered = value
	queue_redraw()


func _layout() -> void:
	_map.position = Vector2(2, 3)
	_map.size = Vector2(size.x - 4.0, size.y - 21.0)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	SkinUiStyle.draw_card(self, rect, _hovered, false)
	SkinUiStyle.draw_text_centered(self, Rect2(0, size.y - 19.0, size.x, 17.0), PlayerSkin.preset_label(preset_id), 10, SkinUiStyle.TEXT)
	if has_focus():
		SkinUiStyle.draw_focus_ring(self, rect)
