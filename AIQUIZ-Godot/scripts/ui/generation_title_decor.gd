class_name GenerationTitleDecor
extends Control

## 「問題を準備中」パネルのタイトルの飾り。タイトルの左に回転アイコン、右に弾む3つの点を描き、
## 問題がそろったら回転アイコンの位置にチェックをポンと出す。
## タイトルの Label と同じ矩形に重ね、GameplayHUD が text_width と mode を渡して advance() で進める。

const PALE := Color(0.93, 0.95, 1.0)
const ACCENT := Color(0.38, 0.68, 1.0)
const GOOD := Color(0.34, 0.86, 0.5)
const SPIN_SPEED := 7.0
const CHECK_POP_SECONDS := 0.16

var text_width := 0.0
## "busy"（回転＋点）、"done"（チェック）、それ以外は何も描かない。
var mode := "busy"
var _clock := 0.0
var _done_since := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func advance(dt: float) -> void:
	_clock += maxf(dt, 0.0)
	if mode == "done":
		if _done_since < 0.0:
			_done_since = _clock
	else:
		_done_since = -1.0
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var left := Vector2(center.x - text_width * 0.5 - 22.0, center.y)
	if mode == "busy":
		draw_arc(left, 9.0, 0.0, TAU, 24, Color(ACCENT, 0.18), 3.0, true)
		var phase := _clock * SPIN_SPEED
		draw_arc(left, 9.0, phase, phase + TAU * 0.68, 20, ACCENT, 3.0, true)
		var dots_x := center.x + text_width * 0.5 + 9.0
		for i: int in range(3):
			var wave := sin(_clock * 6.0 - float(i) * 0.9)
			var lift := maxf(0.0, wave) * 5.0
			var alpha := lerpf(0.35, 1.0, maxf(0.0, wave))
			draw_circle(Vector2(dots_x + float(i) * 10.0, center.y + 6.0 - lift), 2.6, Color(PALE, alpha), true, -1.0, true)
	elif mode == "done":
		_draw_check(left, 10.0 * _pop_scale(_clock - _done_since))


## チェックがポンと出る大きさ：0 → 1.25 に膨らんでから 1.0 に戻る。
func _pop_scale(age: float) -> float:
	if age < 0.0:
		return 0.0
	var p := clampf(age / CHECK_POP_SECONDS, 0.0, 1.0)
	if p < 0.45:
		return lerpf(0.0, 1.25, p / 0.45)
	return lerpf(1.25, 1.0, smoothstep(0.0, 1.0, (p - 0.45) / 0.55))


func _draw_check(center: Vector2, radius: float) -> void:
	if radius <= 0.5:
		return
	draw_circle(center, radius, GOOD, true, -1.0, true)
	var s := radius / 7.5
	var points := PackedVector2Array([
		center + Vector2(-3.4, 0.2) * s,
		center + Vector2(-0.9, 2.8) * s,
		center + Vector2(3.8, -2.6) * s,
	])
	draw_polyline(points, Color(0.04, 0.1, 0.06), 2.1 * s, true)
