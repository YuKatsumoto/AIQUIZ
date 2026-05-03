extends Control

## ローディング演出オーバーレイ
## プリロード中の背景に浮遊パーティクル、回転リング、
## 問題取得時のパルスエフェクトを描画する

# ── 状態 ──
var _elapsed: float = 0.0
var _current: int = 0
var _target: int = 10
var _is_complete: bool = false
var _prev_current: int = 0

# ── パーティクル ──
var _stars: Array[Dictionary] = []
var _pulses: Array[Dictionary] = []  # 問題取得時のパルスエフェクト

# ── フォント ──
var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_init_stars()
	if ResourceLoader.exists("res://resources/fonts/NotoSansJP-Regular.otf"):
		_font = load("res://resources/fonts/NotoSansJP-Regular.otf") as Font
	if _font == null:
		_font = ThemeDB.fallback_font


func _init_stars() -> void:
	_stars.clear()
	for i: int in range(50):
		_stars.append({
			"x": randf(),  # 0-1 正規化座標
			"y": randf(),
			"speed": randf_range(8.0, 35.0),
			"size": randf_range(1.0, 3.0),
			"alpha": randf_range(0.08, 0.3),
			"phase": randf() * TAU,
		})


func update_progress(current: int, target: int, is_complete: bool) -> void:
	_prev_current = _current
	_current = current
	_target = target
	_is_complete = is_complete

	# 新しい問題が取得されたらパルスを発生
	if current > _prev_current and _prev_current >= 0:
		_spawn_pulse()


func _spawn_pulse() -> void:
	"""問題取得時に中央からリング状のパルスを発生"""
	_pulses.append({
		"time": 0.0,
		"max_radius": 250.0,
		"duration": 1.2,
	})


func _process(dt: float) -> void:
	if not visible:
		return
	_elapsed += dt

	# 星の更新
	for star: Dictionary in _stars:
		star["y"] += star["speed"] * dt / size.y
		if star["y"] > 1.05:
			star["y"] = -0.05
			star["x"] = randf()

	# パルスの更新
	var pi := _pulses.size() - 1
	while pi >= 0:
		_pulses[pi]["time"] += dt
		if _pulses[pi]["time"] >= _pulses[pi]["duration"]:
			_pulses.remove_at(pi)
		pi -= 1

	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	var cy := h * 0.5

	# ── 1. 背景グラデーション（半透明 — 3Dシーンを透かして見せる）──
	var bg_top := Color(0.04, 0.05, 0.12, 0.5)
	var bg_bot := Color(0.08, 0.04, 0.16, 0.5)
	# 横線で簡易グラデーション（60本で十分滑らか）
	var grad_steps := 60
	for i: int in range(grad_steps):
		var t := float(i) / float(grad_steps)
		var y0 := h * t
		var y1 := h * (t + 1.0 / float(grad_steps))
		draw_rect(Rect2(0, y0, w, y1 - y0), bg_top.lerp(bg_bot, t))

	# ── 2. 浮遊する星パーティクル ──
	for star: Dictionary in _stars:
		var sx: float = star["x"] * w
		var sy: float = star["y"] * h
		var sa: float = star["alpha"]
		# 微かな明滅
		sa *= 0.7 + 0.3 * sin(_elapsed * 2.0 + star["phase"])
		var star_color := Color(0.6, 0.7, 1.0, sa)
		draw_circle(Vector2(sx, sy), star["size"], star_color)

	# ── 3. 中央の回転リング ──
	_draw_orbit_ring(cx, cy, 120.0, 2.0, Color(0.2, 0.4, 0.9, 0.12), _elapsed * 0.5)
	_draw_orbit_ring(cx, cy, 160.0, 1.5, Color(0.3, 0.5, 1.0, 0.08), -_elapsed * 0.35)
	_draw_orbit_ring(cx, cy, 200.0, 1.0, Color(0.4, 0.3, 0.8, 0.06), _elapsed * 0.2)

	# ── 4. 進捗ドット（円周上に問題数分のドット）──
	if _target > 1:
		_draw_progress_dots(cx, cy, 140.0)

	# ── 5. パルスエフェクト（問題取得時のリング波紋）──
	for pulse: Dictionary in _pulses:
		var pt: float = pulse["time"]
		var pd: float = pulse["duration"]
		var progress := pt / pd
		var radius: float = pulse["max_radius"] * ease(progress, 0.3)
		var alpha := (1.0 - progress) * 0.35
		var pulse_color := Color(0.4, 0.7, 1.0, alpha)
		_draw_ring(cx, cy, radius, 2.0, pulse_color)

	# ── 6. 完了時のグロー ──
	if _is_complete:
		var glow_alpha := 0.08 + 0.04 * sin(_elapsed * 4.0)
		draw_circle(Vector2(cx, cy), 180.0, Color(0.3, 1.0, 0.5, glow_alpha))

	# ── 7. 進捗カウンター（パネルの上に薄く表示）──
	if _target > 1 and not _is_complete:
		var count_text := "%d / %d" % [_current, _target]
		var font_size := 16
		var text_w := _font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		var text_pos := Vector2(cx - text_w * 0.5, cy + 90.0)
		var text_color := Color(0.5, 0.6, 0.8, 0.4 + 0.1 * sin(_elapsed * 3.0))
		draw_string(_font, text_pos, count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func _draw_orbit_ring(cx: float, cy: float, radius: float, thickness: float, color: Color, angle: float) -> void:
	"""回転するリングを点線で描画"""
	var segments := 48
	var gap := 8  # 点線の間隔
	for i: int in range(segments):
		if i % gap < gap / 2:
			continue
		var a0 := angle + TAU * float(i) / float(segments)
		var a1 := angle + TAU * float(i + 1) / float(segments)
		var p0 := Vector2(cx + cos(a0) * radius, cy + sin(a0) * radius)
		var p1 := Vector2(cx + cos(a1) * radius, cy + sin(a1) * radius)
		draw_line(p0, p1, color, thickness, true)


func _draw_ring(cx: float, cy: float, radius: float, thickness: float, color: Color) -> void:
	"""完全なリングを描画"""
	var segments := 64
	for i: int in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector2(cx + cos(a0) * radius, cy + sin(a0) * radius)
		var p1 := Vector2(cx + cos(a1) * radius, cy + sin(a1) * radius)
		draw_line(p0, p1, color, thickness, true)


func _draw_progress_dots(cx: float, cy: float, radius: float) -> void:
	"""進捗を示すドットを円周上に配置"""
	for i: int in range(_target):
		var angle := -PI / 2.0 + TAU * float(i) / float(_target)
		var px := cx + cos(angle) * radius
		var py := cy + sin(angle) * radius

		if i < _current:
			# 取得済み → 明るい青ドット + グロー
			var dot_alpha := 0.7 + 0.2 * sin(_elapsed * 3.0 + float(i))
			draw_circle(Vector2(px, py), 5.0, Color(0.3, 0.6, 1.0, dot_alpha))
			draw_circle(Vector2(px, py), 10.0, Color(0.3, 0.6, 1.0, 0.1))
		else:
			# 未取得 → 暗いグレードット
			draw_circle(Vector2(px, py), 4.0, Color(0.3, 0.35, 0.45, 0.3))
