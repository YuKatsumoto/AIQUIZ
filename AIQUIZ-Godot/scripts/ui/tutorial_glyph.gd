extends Control
class_name TutorialGlyph

## チュートリアルのミッションバー・ルール表示・クリア画面で使う単色アイコン。
## 画像を持たず 24×24 の設計枠で描き、Control の大きさに合わせて拡大する。
## glyph: move / jump / emote / wave / shark / saw / door / heart / heart_broken /
##        crown / flag / check

const DESIGN := 24.0

var glyph: String = "":
	set(value):
		glyph = value
		queue_redraw()
var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()
## のこぎりの軸穴や割れたハートの割れ目など、背景色で抜く部分の色。
var cut_color: Color = Color(0.04, 0.07, 0.13, 1.0):
	set(value):
		cut_color = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 0.0 or glyph.is_empty():
		return
	var scale_factor := side / DESIGN
	var origin := (size - Vector2(side, side)) * 0.5
	draw_set_transform(origin, 0.0, Vector2(scale_factor, scale_factor))
	match glyph:
		"move":
			_draw_move()
		"jump":
			_poly([Vector2(12, 2), Vector2(18.5, 9), Vector2(14.2, 9), Vector2(14.2, 15), Vector2(9.8, 15), Vector2(9.8, 9), Vector2(5.5, 9)])
			draw_rect(Rect2(4.5, 18, 15, 2.6), color)
		"emote":
			draw_circle(Vector2(8.2, 17.2), 3.4, color)
			draw_rect(Rect2(10.2, 3.5, 2.0, 13.8), color)
			_poly([Vector2(12.2, 3.5), Vector2(19, 5.8), Vector2(19, 9.4), Vector2(12.2, 7.1)])
		"wave":
			_wave(8.5)
			_wave(15.5)
		"shark":
			_poly([Vector2(3, 17.5), Vector2(8.6, 15), Vector2(12.4, 3.5), Vector2(15.4, 11.5), Vector2(21, 17.5)])
			draw_rect(Rect2(2, 18.6, 20, 2.2), color)
		"saw":
			_draw_saw()
		"door":
			_draw_door()
		"heart":
			_poly(_heart_points(Vector2(12, 12.6), 1.0))
		"heart_broken":
			_poly(_heart_points(Vector2(12, 12.6), 1.0))
			draw_polyline(PackedVector2Array([
				Vector2(12.6, 6.0), Vector2(10.6, 10.4), Vector2(13.4, 12.8), Vector2(11.2, 17.4), Vector2(12.2, 21.0),
			]), cut_color, 1.9, true)
		"crown":
			_poly([Vector2(2.5, 7.5), Vector2(7.5, 11.7), Vector2(12, 4), Vector2(16.5, 11.7), Vector2(21.5, 7.5), Vector2(19.5, 18.5), Vector2(4.5, 18.5)])
			draw_rect(Rect2(4.5, 19.6, 15, 2.4), color)
		"flag":
			draw_rect(Rect2(5, 2, 2.2, 20), color)
			_poly([Vector2(8, 3), Vector2(20, 3), Vector2(17.2, 7.5), Vector2(20, 12), Vector2(8, 12)])
		"check":
			draw_polyline(PackedVector2Array([Vector2(4.5, 12.8), Vector2(9.3, 17.5), Vector2(19.5, 7)]), color, 3.4, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _poly(points: Array) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)


func _draw_move() -> void:
	_poly([Vector2(12, 1.5), Vector2(15.6, 5.3), Vector2(8.4, 5.3)])
	draw_rect(Rect2(10.8, 5.3, 2.4, 4.2), color)
	_poly([Vector2(12, 22.5), Vector2(8.4, 18.7), Vector2(15.6, 18.7)])
	draw_rect(Rect2(10.8, 14.5, 2.4, 4.2), color)
	_poly([Vector2(1.5, 12), Vector2(5.3, 8.4), Vector2(5.3, 15.6)])
	draw_rect(Rect2(5.3, 10.8, 4.2, 2.4), color)
	_poly([Vector2(22.5, 12), Vector2(18.7, 15.6), Vector2(18.7, 8.4)])
	draw_rect(Rect2(14.5, 10.8, 4.2, 2.4), color)


func _wave(center_y: float) -> void:
	var points := PackedVector2Array()
	for i: int in range(25):
		var x := 2.0 + 20.0 * float(i) / 24.0
		points.append(Vector2(x, center_y + sin(float(i) / 24.0 * TAU * 2.0) * 1.8))
	draw_polyline(points, color, 2.6, true)


func _draw_saw() -> void:
	var star := PackedVector2Array()
	var teeth := 12
	for i: int in range(teeth * 2):
		var angle := TAU * float(i) / float(teeth * 2) - PI * 0.5
		var radius := 10.6 if i % 2 == 0 else 8.2
		star.append(Vector2(12, 12) + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(star, color)
	draw_circle(Vector2(12, 12), 2.6, cut_color)


func _draw_door() -> void:
	draw_rect(Rect2(5, 2.2, 14, 19.6), color, false, 2.4)
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := 14
	var text_size := font.get_string_size("?", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, Vector2(12.0 - text_size.x * 0.5, 17.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _heart_points(center: Vector2, scale_factor: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(36):
		var t := TAU * float(i) / 36.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		points.append(center + Vector2(x, -y) * 0.58 * scale_factor)
	return points
