extends Control
class_name UnitSlotReel

## 単元スロット（3リール）。準備パネルの進行バーの上に置く。
## 見た目は準備パネルの進行バーに揃え（紺の枠・青のアクセント）、上下の単元が奥へ回り込む
## ドラムの動きだけで抽選を見せる。全リールが止まって少し間を置いたら finished を出す。

signal finished

const REEL_COUNT := 3
const SLOT_SIZE := Vector2(548.0, 60.0)
const REEL_SIZE := Vector2(176.0, 60.0)
const REEL_GAP := 10.0
const CELL_HEIGHT := 34.0
## ドラムの半径。中央の1段が正面、上下の段は奥へ傾いて小さく暗く見える。
const DRUM_RADIUS := 42.0
const CELL_SIDE_MARGIN := 8.0

## 1本目のリールが流す単元数。後のリールほど長く回るので多めに流す。
const SPIN_CELLS := 16
const SPIN_CELLS_PER_REEL := 6
const STOP_TIMES: Array[float] = [1.4, 1.9, 2.4]
const WINDUP_SEC := 0.12
const WINDUP_CELLS := 0.25
const BOUNCE_SEC := 0.2
const BOUNCE_CELLS := 0.18
const HOLD_AFTER_STOP_SEC := 0.3

const FONT_SIZE_MAX := 18
const FONT_SIZE_SINGLE_LINE_MIN := 13
const FONT_SIZE_TWO_LINES := 12

## 準備パネルの進行バーと同じ色
const COLOR_BG := Color(0.12, 0.14, 0.22, 1.0)
const COLOR_BORDER := Color(0.3, 0.4, 0.6, 0.5)
const COLOR_ACCENT := Color(0.25, 0.55, 1.0, 1.0)
const COLOR_TEXT := Color(0.7, 0.75, 0.85)
const COLOR_RESULT := Color(1.0, 1.0, 1.0)

var _spinning: bool = false
var _run_id: int = 0
var _stopped_count: int = 0
var _tweens: Array[Tween] = []

var _reels: Array[Panel] = []
var _reel_labels: Array = []  # Array[Array[Label]]
var _scroll: Array[float] = []
var _prev_scroll: Array[float] = []
var _speed: Array[float] = []
var _frame_styles: Array[StyleBoxFlat] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SLOT_SIZE
	_build_reels()
	_layout_all_labels()


func is_spinning() -> bool:
	return _spinning


## final_units[i] が i 本目の当たり。pool はリールを流れる単元名（その学年の全単元）。
func start(final_units: PackedStringArray, pool: PackedStringArray) -> void:
	_stop_tweens()
	_run_id += 1
	var run_id := _run_id
	_stopped_count = 0
	var reel_count := mini(_reels.size(), final_units.size())
	if reel_count == 0:
		_spinning = false
		finished.emit()
		return
	_spinning = true
	for r in range(_reels.size()):
		_reset_reel(r, r < reel_count)
	for r in range(reel_count):
		# 当たりの下にも1段流しておき、止まったときに上下とも隣の単元がうっすら見えるようにする
		var names := _spin_sequence(pool, SPIN_CELLS + r * SPIN_CELLS_PER_REEL, final_units[r])
		names.append(final_units[r])
		names.append(_pick_other(pool, final_units[r]))
		var stop_at := float(names.size() - 2)
		_fill_reel(r, names, names.size() - 2)
		_scroll[r] = 0.0
		_prev_scroll[r] = 0.0
		var main_sec := STOP_TIMES[r] - WINDUP_SEC - BOUNCE_SEC
		var tween := create_tween()
		tween.tween_method(_set_scroll.bind(r), 0.0, -WINDUP_CELLS, WINDUP_SEC) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_method(_set_scroll.bind(r), -WINDUP_CELLS, stop_at + BOUNCE_CELLS, main_sec) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.tween_method(_set_scroll.bind(r), stop_at + BOUNCE_CELLS, stop_at, BOUNCE_SEC) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_on_reel_stopped.bind(r, reel_count, run_id))
		_tweens.append(tween)
	_layout_all_labels()


## 回さずに結果だけを表示する。pool があれば上下の段にほかの単元を並べる。
func show_result(final_units: PackedStringArray, pool: PackedStringArray = PackedStringArray()) -> void:
	_stop_tweens()
	_run_id += 1
	_spinning = false
	for r in range(_reels.size()):
		var has_unit := r < final_units.size()
		_reset_reel(r, has_unit)
		if has_unit:
			var names := PackedStringArray([
				_pick_other(pool, final_units[r]), final_units[r], _pick_other(pool, final_units[r]),
			])
			_fill_reel(r, names, 1)
			_scroll[r] = 1.0
			_prev_scroll[r] = 1.0
			_frame_styles[r].border_color = COLOR_ACCENT
	_layout_all_labels()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	for r in range(_reels.size()):
		var raw := absf(_scroll[r] - _prev_scroll[r]) / maxf(delta, 0.0001)
		_speed[r] = lerpf(_speed[r], raw, clampf(delta * 18.0, 0.0, 1.0))
		_prev_scroll[r] = _scroll[r]
	_layout_all_labels()


func _set_scroll(value: float, reel_index: int) -> void:
	_scroll[reel_index] = value


func _reset_reel(reel_index: int, visible_now: bool) -> void:
	_reels[reel_index].visible = visible_now
	_reels[reel_index].scale = Vector2.ONE
	_frame_styles[reel_index].border_color = COLOR_BORDER


func _on_reel_stopped(reel_index: int, reel_count: int, run_id: int) -> void:
	if run_id != _run_id:
		return
	_stopped_count += 1
	var reel := _reels[reel_index]
	reel.pivot_offset = reel.size * 0.5
	var pop := create_tween()
	pop.tween_property(reel, "scale", Vector2(1.04, 1.04), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pop.tween_property(reel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tweens.append(pop)
	var border := create_tween()
	border.tween_property(_frame_styles[reel_index], "border_color", COLOR_ACCENT, 0.15)
	_tweens.append(border)
	if _stopped_count < reel_count:
		return
	var hold := create_tween()
	hold.tween_interval(HOLD_AFTER_STOP_SEC)
	hold.tween_callback(func():
		if run_id != _run_id:
			return
		_spinning = false
		finished.emit()
	)
	_tweens.append(hold)


func _stop_tweens() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()


## ドラムの見た目: 中央からの距離を角度に直し、奥へ回り込む段ほど縦に潰して暗くする。
## 高速回転中は少し薄くして、流れて見えるようにする。
func _layout_all_labels() -> void:
	var center_y := REEL_SIZE.y * 0.5
	for r in range(_reels.size()):
		var blur := clampf((_speed[r] - 6.0) / 22.0, 0.0, 1.0)
		var labels: Array = _reel_labels[r]
		for i in range(labels.size()):
			var label: Label = labels[i]
			var angle := (float(i) - _scroll[r]) * CELL_HEIGHT / DRUM_RADIUS
			if absf(angle) >= 1.45:
				label.visible = false
				continue
			label.visible = true
			var depth := cos(angle)
			label.position.y = center_y + DRUM_RADIUS * sin(angle) - CELL_HEIGHT * 0.5
			label.scale = Vector2(1.0, maxf(depth, 0.05))
			label.modulate.a = depth * depth * (1.0 - 0.4 * blur)


func _build_reels() -> void:
	var total_w := REEL_SIZE.x * REEL_COUNT + REEL_GAP * (REEL_COUNT - 1)
	var left := (SLOT_SIZE.x - total_w) * 0.5
	for r in range(REEL_COUNT):
		var reel := Panel.new()
		reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reel.clip_contents = true
		reel.position = Vector2(left + r * (REEL_SIZE.x + REEL_GAP), 0.0)
		reel.size = REEL_SIZE
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_BG
		style.border_color = COLOR_BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		reel.add_theme_stylebox_override("panel", style)
		add_child(reel)

		var labels: Array[Label] = []
		for _i in range(SPIN_CELLS + SPIN_CELLS_PER_REEL * (REEL_COUNT - 1) + 2):
			var label := Label.new()
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.position = Vector2(CELL_SIDE_MARGIN, 0.0)
			label.size = Vector2(REEL_SIZE.x - CELL_SIDE_MARGIN * 2.0, CELL_HEIGHT)
			label.pivot_offset = label.size * 0.5
			label.visible = false
			reel.add_child(label)
			labels.append(label)
		_reel_labels.append(labels)

		_reels.append(reel)
		_frame_styles.append(style)
		_scroll.append(0.0)
		_prev_scroll.append(0.0)
		_speed.append(0.0)


## 同じ単元が上下に並ばず、当たりの直前にも当たりが来ないように pool から count 個を流す。
func _spin_sequence(pool: PackedStringArray, count: int, final_unit: String) -> PackedStringArray:
	var out := PackedStringArray()
	if pool.is_empty():
		return out
	var prev := ""
	for i in range(count):
		var pick := pool[randi() % pool.size()]
		if pool.size() > 2:
			while pick == prev or (i == count - 1 and pick == final_unit):
				pick = pool[randi() % pool.size()]
		out.append(pick)
		prev = pick
	return out


func _pick_other(pool: PackedStringArray, avoid: String) -> String:
	if pool.size() < 2:
		return ""
	var pick := avoid
	while pick == avoid:
		pick = pool[randi() % pool.size()]
	return pick


func _fill_reel(reel_index: int, names: PackedStringArray, result_index: int) -> void:
	var labels: Array = _reel_labels[reel_index]
	for i in range(labels.size()):
		var label: Label = labels[i]
		if i >= names.size():
			label.text = ""
			continue
		label.add_theme_color_override("font_color", COLOR_RESULT if i == result_index else COLOR_TEXT)
		_fit_text(label, names[i])


## 1行で収まる大きさまで縮め、それでも入らない長い単元名は2行にする。
## Label は文字列に合わせて自分で広がるので、折り返し・切り詰めを決めてから枠の大きさに戻す。
func _fit_text(label: Label, text: String) -> void:
	var cell := Vector2(REEL_SIZE.x - CELL_SIDE_MARGIN * 2.0, CELL_HEIGHT)
	var font := label.get_theme_font("font")
	var single_size := 0
	for font_size in range(FONT_SIZE_MAX, FONT_SIZE_SINGLE_LINE_MIN - 1, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= cell.x:
			single_size = font_size
			break
	if single_size > 0:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.max_lines_visible = -1
		label.clip_text = true
		label.add_theme_font_size_override("font_size", single_size)
	else:
		label.clip_text = false
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		label.add_theme_font_size_override("font_size", FONT_SIZE_TWO_LINES)
		label.add_theme_constant_override("line_spacing", -4)
	label.text = text
	label.size = cell
	label.pivot_offset = cell * 0.5
