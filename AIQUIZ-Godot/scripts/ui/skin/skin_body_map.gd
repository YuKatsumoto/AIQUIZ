extends Control
class_name SkinBodyMap

## 正面から見た人型。各パーツを今の色で描き、クリックでパーツを選ぶ。
## 正面図なので、キャラの 左うで は画面の右側に来る（カーソルを乗せると名前が出る）。
## interactive = false ならサムネイル（おすすめ）用で、入力を受けない。

signal part_clicked(part_id: StringName)
signal part_hovered(part_id: StringName)

## キーボード（←→↑↓）で巡る順番（上から、画面の左から）。
const KEY_ORDER: Array[StringName] = [
	&"all", &"head", &"chest", &"waist", &"r_arm", &"l_arm", &"r_hand", &"l_hand",
	&"r_leg", &"l_leg", &"r_foot", &"l_foot",
]
## 小さいパーツ（て・くつ）も押しやすいよう当たり判定を広げる量（px）。
const HIT_GROW := 8.0
const NEAREST_LIMIT := 26.0

var interactive: bool = true
var padding: float = 10.0
var accent: Color = SkinUiStyle.GOLD

var _layout: Dictionary = {}
var _screen_rects: Array[Rect2] = []
var _skin: Dictionary = {}
var _selected: StringName = &""
var _hovered: StringName = &""
## 選べないパーツ（プレイヤー2 のあたまなど）。斜線を引き、クリックも受けない。
var _locked: Array[StringName] = []


func _ready() -> void:
	_layout = PlayerSkinRig.front_view_layout()
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	if interactive:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "ぬりたいところをクリックしてね（キーボードは ← → で切りかえ）"
	resized.connect(_relayout)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_exited.connect(func() -> void: _set_hovered(&""))
	_relayout()


func set_skin(skin: Dictionary) -> void:
	_skin = skin
	queue_redraw()


func set_selected(part_id: StringName) -> void:
	_selected = part_id
	queue_redraw()


## 外から（3D のホバーなど）ホバー表示だけ合わせる。
func show_hover(part_id: StringName) -> void:
	if _locked.has(part_id):
		part_id = &""
	if _hovered == part_id:
		return
	_hovered = part_id
	queue_redraw()


func set_locked(part_ids: Array[StringName]) -> void:
	_locked = part_ids.duplicate()
	if _locked.has(_hovered):
		_hovered = &""
	queue_redraw()


func region_center(part_id: StringName) -> Vector2:
	return region_rect(part_id).get_center()


func region_rect(part_id: StringName) -> Rect2:
	var regions: Array = _layout.get("regions", [])
	for index: int in range(mini(regions.size(), _screen_rects.size())):
		if (regions[index] as Dictionary).part == part_id:
			return _screen_rects[index]
	return Rect2(size * 0.5, Vector2.ZERO)


func _relayout() -> void:
	_screen_rects.clear()
	var body: Rect2 = _layout.get("body", Rect2(0, 0, 1, 1))
	var available := (size - Vector2.ONE * padding * 2.0).max(Vector2.ONE)
	var fit := minf(available.x / maxf(body.size.x, 0.001), available.y / maxf(body.size.y, 0.001))
	var origin := (size - body.size * fit) * 0.5
	for region: Dictionary in _layout.get("regions", []):
		var rect: Rect2 = region.rect
		var screen := Rect2(origin + (rect.position - body.position) * fit, rect.size * fit)
		_screen_rects.append(Rect2(screen.position.round(), (screen.end.round() - screen.position.round()).max(Vector2.ONE * 2.0)))
	queue_redraw()


func _draw() -> void:
	var regions: Array = _layout.get("regions", [])
	var outline := Color(0.02, 0.03, 0.05, 0.85)
	for index: int in range(mini(regions.size(), _screen_rects.size())):
		var part: StringName = (regions[index] as Dictionary).part
		draw_rect(_screen_rects[index], PlayerSkin.part_color(_skin, part))
		draw_rect(_screen_rects[index], outline, false, 1.0)
	if not interactive:
		return
	var select_all := _selected == PlayerSkin.ALL
	for index: int in range(mini(regions.size(), _screen_rects.size())):
		var part: StringName = (regions[index] as Dictionary).part
		var rect := _screen_rects[index]
		if _locked.has(part):
			_draw_locked(rect)
		elif select_all or part == _selected:
			draw_rect(rect.grow(2.0), Color(accent.r, accent.g, accent.b, 0.35), false, 5.0)
			draw_rect(rect.grow(1.0), accent, false, 2.5)
		elif part == _hovered:
			draw_rect(rect.grow(1.0), Color(1, 1, 1, 0.85), false, 2.0)
	_draw_hover_tag()
	if has_focus():
		SkinUiStyle.draw_focus_ring(self, Rect2(Vector2.ZERO, size).grow(-2.0), 10)


## 選べないパーツ：うすい斜線をかける。
func _draw_locked(rect: Rect2) -> void:
	draw_rect(rect, Color(0.04, 0.05, 0.08, 0.35))
	var step := 6.0
	var offset := -rect.size.y
	while offset < rect.size.x:
		var a := rect.position + Vector2(offset, rect.size.y)
		var b := rect.position + Vector2(offset + rect.size.y, 0.0)
		var from := a
		var to := b
		# 矩形の左右からはみ出した分を切る（斜め 45°）
		if from.x < rect.position.x:
			from = Vector2(rect.position.x, from.y - (rect.position.x - from.x))
		if to.x > rect.end.x:
			to = Vector2(rect.end.x, to.y + (to.x - rect.end.x))
		if from.x < to.x:
			draw_line(from, to, Color(1, 1, 1, 0.28), 1.0, true)
		offset += step


## カーソルが乗っているパーツの名前を、そのパーツの上に小さく出す。
func _draw_hover_tag() -> void:
	if _hovered == &"" or _hovered == PlayerSkin.ALL:
		return
	var text := PlayerSkin.part_label(_hovered)
	var font := SkinUiStyle.FONT_BOLD
	var font_size := 13
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var anchor := region_rect(_hovered)
	var tag := Rect2(Vector2.ZERO, text_size + Vector2(12, 4))
	tag.position = Vector2(anchor.get_center().x - tag.size.x * 0.5, anchor.position.y - tag.size.y - 3.0)
	if tag.position.y < 0.0:
		tag.position.y = anchor.end.y + 3.0
	tag.position.x = clampf(tag.position.x, 0.0, maxf(size.x - tag.size.x, 0.0))
	tag.position.y = clampf(tag.position.y, 0.0, maxf(size.y - tag.size.y, 0.0))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.07, 0.92)
	style.border_color = Color(1, 1, 1, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	draw_style_box(style, tag)
	SkinUiStyle.draw_text_centered(self, tag, text, font_size, Color(1, 1, 1), true)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		_set_hovered(_part_at((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			var part := _part_at(button.position)
			if part != &"" and not _locked.has(part):
				grab_focus()
				part_clicked.emit(part)
				accept_event()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var step := 0
		if event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
			step = 1
		elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
			step = -1
		if step != 0:
			var index := KEY_ORDER.find(_selected)
			index = index if index >= 0 else 0
			for attempt: int in range(KEY_ORDER.size()):
				index = posmod(index + step, KEY_ORDER.size())
				if not _locked.has(KEY_ORDER[index]):
					break
			part_clicked.emit(KEY_ORDER[index])
			accept_event()


func _set_hovered(part_id: StringName) -> void:
	if _locked.has(part_id):
		part_id = &""
	if _hovered == part_id:
		return
	_hovered = part_id
	part_hovered.emit(part_id)
	queue_redraw()


func _part_at(point: Vector2) -> StringName:
	var regions: Array = _layout.get("regions", [])
	var best: StringName = &""
	var best_area := INF
	for index: int in range(mini(regions.size(), _screen_rects.size())):
		var rect := _screen_rects[index]
		var grow := HIT_GROW if rect.get_area() < 900.0 else 2.0
		if rect.grow(grow).has_point(point) and rect.get_area() < best_area:
			best = (regions[index] as Dictionary).part
			best_area = rect.get_area()
	if best != &"":
		return best
	var nearest_distance := NEAREST_LIMIT
	for index: int in range(mini(regions.size(), _screen_rects.size())):
		var rect := _screen_rects[index]
		var distance := point.clamp(rect.position, rect.end).distance_to(point)
		if distance < nearest_distance:
			nearest_distance = distance
			best = (regions[index] as Dictionary).part
	return best
