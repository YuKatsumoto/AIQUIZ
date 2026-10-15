extends Control
## 連続正解バッジ（炎＋回数）。対戦カードの正解数の右に並ぶ。
## 炎は After Effects で作ったループ（assets/ui/streak_flame/flame_sheet.png）、点火・カウントアップ・消火の
## 動きは同じ AE プロジェクトから 60 Hz で書き出した曲線（motion.json）をそのまま再生する。
## 表示の判断はカード側が渡す連続正解数だけで行い、ゲームの状態は変えない。

const SHEET := preload("res://assets/ui/streak_flame/flame_sheet.png")
const MOTION_PATH := "res://assets/ui/streak_flame/motion.json"
const MIN_STREAK := 2
const CELL := Vector2(128, 160)
const COLUMNS := 6
## シートの 1 セル内での炎の根元（AE の 256 x 320 コンプの (128, 282) を半分に縮めた位置）。
const CELL_BASE := Vector2(64, 141)
const FLAME_SIZE := Vector2(20, 25)
const FLAME_GAP := 1.0
const UNIT_GAP := 1.0
const COUNT_COLOR := Color(1.0, 0.80, 0.34)
const UNIT_COLOR := Color(0.98, 0.70, 0.36)
const RING_COLOR := Color(1.0, 0.72, 0.28)
const OUTLINE := Color(0.027, 0.047, 0.082, 0.96)

enum Phase { HIDDEN, IGNITE, BURN, OUT }

static var _motion_cache: Dictionary = {}

var _tracks: Dictionary
var _loop_fps := 30.0
var _loop_frames := 30
var _phase := Phase.HIDDEN
var _phase_time := 0.0
var _pop_time := 10.0
var _clock := 0.0
var _shown := 0
var _heat := 1.0
var _count: Label
var _unit: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _motion_cache.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(MOTION_PATH))
		if data is Dictionary:
			_motion_cache = data
	_tracks = _motion_cache.get("tracks", {})
	var loop: Dictionary = _motion_cache.get("loop", {})
	_loop_fps = float(loop.get("fps", 30))
	_loop_frames = int(loop.get("frames", 30))


func setup(english: bool) -> void:
	_count = _make_label("StreakCount", 18, COUNT_COLOR)
	_count.add_theme_color_override("font_outline_color", OUTLINE)
	_count.add_theme_constant_override("outline_size", 3)
	_unit = _make_label("StreakUnit", 9, UNIT_COLOR)
	_unit.text = "streak" if english else "連続"
	visible = false


func _make_label(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	return label


## 炎・数字・単位の合計幅。カードはこれを使って正解数の右に収める。
func content_width() -> float:
	var width := FLAME_SIZE.x + FLAME_GAP + _text_width(_count)
	if _unit.visible:
		width += UNIT_GAP + _text_width(_unit)
	return width


## 正解数が長くて幅が足りないときは「連続」を省き、炎と回数だけにする。
func set_compact(compact: bool) -> void:
	_unit.visible = not compact
	size = Vector2(content_width(), 32)


## 表示中のカードが毎フレーム呼ぶ。streak はそのプレイヤーの現在の連続正解数。
func advance(dt: float, streak: int) -> void:
	_clock = fmod(_clock + dt, float(_loop_frames) / _loop_fps)
	_phase_time += dt
	_pop_time += dt
	var lit := streak >= MIN_STREAK
	match _phase:
		Phase.HIDDEN, Phase.OUT:
			if lit:
				_set_count(streak)
				_phase = Phase.IGNITE
				_phase_time = 0.0
				_pop_time = 10.0
			elif _phase == Phase.OUT and _phase_time >= _duration("out_alpha"):
				_phase = Phase.HIDDEN
		Phase.IGNITE, Phase.BURN:
			if not lit:
				_phase = Phase.OUT
				_phase_time = 0.0
			else:
				if _phase == Phase.IGNITE and _phase_time >= _duration("ignite_scale"):
					_phase = Phase.BURN
				if streak != _shown:
					_set_count(streak)
					if _phase == Phase.BURN:
						_pop_time = 0.0
	# 5連続・10連続で炎が一回り大きく燃え上がる。
	var target_heat := 1.0 + (0.12 if _shown >= 5 else 0.0) + (0.12 if _shown >= 10 else 0.0)
	_heat = lerpf(_heat, target_heat, 1.0 - exp(-dt * 6.0))
	visible = _phase != Phase.HIDDEN
	_layout_labels()
	queue_redraw()


## カードが画面外から戻ったときなど、演出なしで今の値に合わせる。
func snap(streak: int) -> void:
	_set_count(streak)
	_phase = Phase.BURN if streak >= MIN_STREAK else Phase.HIDDEN
	_phase_time = 10.0
	_pop_time = 10.0
	_heat = 1.0 + (0.12 if streak >= 5 else 0.0) + (0.12 if streak >= 10 else 0.0)
	visible = _phase != Phase.HIDDEN
	_layout_labels()


func _set_count(streak: int) -> void:
	_shown = streak
	_count.text = str(streak)
	_count.size = Vector2(_text_width(_count), 24)


func _flame_scale() -> Vector2:
	match _phase:
		Phase.IGNITE:
			return Vector2.ONE * _sample("ignite_scale", _phase_time)
		Phase.OUT:
			return Vector2(_sample("out_scale_x", _phase_time), _sample("out_scale_y", _phase_time))
	return Vector2.ONE * _sample("pop_scale", _pop_time)


func _alpha() -> float:
	match _phase:
		Phase.IGNITE:
			return _sample("ignite_alpha", _phase_time)
		Phase.OUT:
			return _sample("out_alpha", _phase_time)
	return 1.0


func _layout_labels() -> void:
	var x := FLAME_SIZE.x + FLAME_GAP
	_count.position = Vector2(x, 8)
	_count.size = Vector2(_text_width(_count), 24)
	_count.pivot_offset = _count.size * 0.5
	var count_scale := 1.0
	match _phase:
		Phase.IGNITE:
			count_scale = _sample("count_in_scale", _phase_time)
		Phase.OUT:
			count_scale = _sample("out_scale_x", _phase_time)
		_:
			count_scale = _sample("count_pop_scale", _pop_time)
	_count.scale = Vector2.ONE * count_scale
	_count.modulate.a = _alpha()
	_unit.position = Vector2(x + _count.size.x + UNIT_GAP, 17)
	_unit.size = Vector2(_text_width(_unit), 15)
	_unit.modulate.a = _alpha()
	size = Vector2(content_width(), 32)


func _draw() -> void:
	if _phase == Phase.HIDDEN:
		return
	var base := Vector2(FLAME_SIZE.x * 0.5, 31)
	if _phase == Phase.IGNITE and _phase_time < _duration("ring_scale"):
		var ring_radius := 16.0 * _sample("ring_scale", _phase_time)
		draw_arc(base + Vector2(0, -11), ring_radius, 0, TAU, 40, Color(RING_COLOR, _sample("ring_alpha", _phase_time)), 1.5, true)
	var flame_scale := _flame_scale() * _heat
	var frame := int(_clock * _loop_fps) % _loop_frames
	var source := Rect2(Vector2(frame % COLUMNS, floori(frame / float(COLUMNS))) * CELL, CELL)
	var cell_scale := FLAME_SIZE / CELL * flame_scale
	var origin := base - CELL_BASE * cell_scale
	draw_texture_rect_region(SHEET, Rect2(origin, CELL * cell_scale), source, Color(1, 1, 1, _alpha()))


func _text_width(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x


func _duration(track_name: String) -> float:
	return float(_tracks.get(track_name, {}).get("duration", 0.0))


func _sample(track_name: String, time: float) -> float:
	var track: Dictionary = _tracks.get(track_name, {})
	var values: Array = track.get("values", [])
	if values.is_empty():
		return 1.0
	var at := clampf(time / float(track.duration), 0.0, 1.0) * float(values.size() - 1)
	var start := int(floor(at))
	return lerpf(float(values[start]), float(values[mini(start + 1, values.size() - 1)]), at - float(start))
