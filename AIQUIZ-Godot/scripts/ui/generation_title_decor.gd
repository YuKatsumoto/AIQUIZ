class_name GenerationTitleDecor
extends Control

## 「問題を準備中」パネルのタイトルの飾り。タイトルの左にリサージュ曲線を走る光の筋を描き、
## 問題がそろったら筋が中心へ吸い込まれて緑の円がポンと出て、チェックが引かれ、輪と光線がはじける。
## タイトルの Label と同じ矩形に重ね、GameplayHUD が text_width と mode を渡して advance() で進める。

const GOOD := Color(0.34, 0.86, 0.5)
const CHECK_INK := Color(0.04, 0.1, 0.06)
const CHECK_POP_SECONDS := 0.16

## 光の筋と、チェックが出るときの光線の色（2本の筋とも同じ青一色）。
const ACCENT := Color(0.38, 0.68, 1.0)
## 筋の下に重ねる同じ青のにじみ（太さの倍率と濃さ）。暗いパネルの上で光って見えるようにする。
const GLOW_WIDTH := 2.6
const GLOW_ALPHA := 0.22

## 光の筋が描くリサージュ曲線の縦横の周波数比。RATIO_SECONDS ごとに次の比へなめらかに移り、形を変え続ける。
const TRAIL_RATIOS: Array[Vector2] = [
	Vector2(3, 2), Vector2(1, 2), Vector2(3, 4), Vector2(5, 4), Vector2(1, 1), Vector2(2, 1), Vector2(3, 1),
]
const RATIO_SECONDS := 2.6
## 比を保つ時間の割合。残りで次の比へ移る。
const RATIO_HOLD := 0.55
## 筋の速さ（rad/秒）：ふだんは BASE、ときどき BURST ぶん「シュッ」と加速する。
const TRAIL_BASE_SPEED := 1.8
const TRAIL_BURST_SPEED := 4.2
const TRAIL_SECONDS := 0.5
const TRAIL_RADIUS := 9.0
const TRAIL_WIDTH := 3.0
## 反対側から追いかける2本目の筋の最大の濃さ。ゆっくり現れては消える。
const TWIN_ALPHA := 0.7

## チェックへの変化（"done" になってからの秒数）：筋が吸い込まれ → 円がポン → チェックを引く。
const COLLAPSE_SECONDS := 0.2
const DISC_DELAY := 0.14
const CHECK_DRAW_DELAY := 0.22
const CHECK_DRAW_SECONDS := 0.16
## 円が出たのと同時に広がる輪と光線。
const BURST_SECONDS := 0.42
const BURST_RAYS := 8

var text_width := 0.0
## "busy"（光の筋）、"done"（チェック）、それ以外は何も描かない。
var mode := "busy"
var _clock := 0.0
var _done_since := -1.0
var _last_mode := ""
var _trail_phase := Vector2.ZERO
var _trail_head := PackedVector2Array()
var _trail_twin := PackedVector2Array()
var _trail_twin_alpha := PackedFloat32Array()
var _trail_time := PackedFloat32Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func advance(dt: float) -> void:
	dt = maxf(dt, 0.0)
	_clock += dt
	if mode != _last_mode and mode == "busy":
		_clear_trail()
	_last_mode = mode
	if mode == "done":
		if _done_since < 0.0:
			_done_since = _clock
	else:
		_done_since = -1.0
	if mode == "busy":
		_advance_trail(dt)
	elif mode != "done" or _done_age() > COLLAPSE_SECONDS:
		_clear_trail()
	queue_redraw()


## 筋の先頭を進めて履歴に足し、TRAIL_SECONDS より古い点を捨てる。
## 縦横の位相を別々に積むので、周波数比が変わっても先頭は飛ばずにつながる。
func _advance_trail(dt: float) -> void:
	var speed := TRAIL_BASE_SPEED + TRAIL_BURST_SPEED * pow(maxf(0.0, sin(_clock * 1.4)), 6.0)
	_trail_phase += _trail_ratio(_clock) * speed * dt
	_trail_head.append(Vector2(sin(_trail_phase.x + 0.5), sin(_trail_phase.y)))
	_trail_twin.append(Vector2(sin(_trail_phase.x + PI + 0.5), sin(_trail_phase.y + PI * 0.5)))
	_trail_twin_alpha.append((0.5 + 0.5 * sin(_clock * 0.8)) * TWIN_ALPHA)
	_trail_time.append(_clock)
	while _trail_time.size() > 2 and _trail_time[0] < _clock - TRAIL_SECONDS:
		_trail_head.remove_at(0)
		_trail_twin.remove_at(0)
		_trail_twin_alpha.remove_at(0)
		_trail_time.remove_at(0)


func _clear_trail() -> void:
	_trail_head.clear()
	_trail_twin.clear()
	_trail_twin_alpha.clear()
	_trail_time.clear()


func _trail_ratio(time: float) -> Vector2:
	var step := time / RATIO_SECONDS
	var index := int(step) % TRAIL_RATIOS.size()
	var next := (index + 1) % TRAIL_RATIOS.size()
	var blend := smoothstep(0.0, 1.0, (fposmod(step, 1.0) - RATIO_HOLD) / (1.0 - RATIO_HOLD))
	return TRAIL_RATIOS[index].lerp(TRAIL_RATIOS[next], blend)


func _done_age() -> float:
	return _clock - _done_since if _done_since >= 0.0 else -1.0


func _draw() -> void:
	var center := size * 0.5
	var left := Vector2(center.x - text_width * 0.5 - 22.0, center.y)
	if mode == "busy":
		_draw_trail(left, 1.0)
	elif mode == "done":
		var age := _done_age()
		var collapse := clampf(age / COLLAPSE_SECONDS, 0.0, 1.0)
		if collapse < 1.0:
			_draw_trail(left, 1.0 - collapse)
		_draw_burst(left, age - DISC_DELAY)
		_draw_check(left, 10.0 * _pop_scale(age - DISC_DELAY),
			clampf((age - CHECK_DRAW_DELAY) / CHECK_DRAW_SECONDS, 0.0, 1.0))


## 筋の軌道ごとゆっくり回し、大きさを呼吸させる。古い点ほど細く薄く、先頭は丸く描く。
## remain が 1 → 0 に減ると、筋は回りながら中心へ縮んで消える（チェックへの変化）。
func _draw_trail(origin: Vector2, remain: float) -> void:
	if _trail_time.size() < 2 or remain <= 0.0:
		return
	var shrink := remain * remain
	var radius := TRAIL_RADIUS * (0.82 + 0.14 * sin(_clock * 1.3)) * shrink
	var fade := smoothstep(0.0, 0.4, remain)
	draw_set_transform(origin, _clock * 0.35 + (1.0 - remain) * 2.4, Vector2.ONE)
	_draw_trail_line(_trail_twin, radius, true, fade)
	_draw_trail_line(_trail_head, radius, false, fade)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_trail_line(points: PackedVector2Array, radius: float, twin: bool, fade: float) -> void:
	# 変化中は筋を止めたまま縮めるので、尾の古さは "done" になった時刻で測る。
	var now := _done_since if _done_since >= 0.0 else _clock
	var last := points.size() - 1
	for pass_glow: bool in [true, false]:
		for i: int in range(1, points.size()):
			var fresh := clampf(1.0 - (now - _trail_time[i]) / TRAIL_SECONDS, 0.0, 1.0)
			var alpha := fresh * fade * (_trail_twin_alpha[i] if twin else 1.0)
			if alpha < 0.02:
				continue
			var width := TRAIL_WIDTH * (0.35 + 0.65 * fresh)
			if pass_glow:
				draw_line(points[i - 1] * radius, points[i] * radius, Color(ACCENT, alpha * GLOW_ALPHA), width * GLOW_WIDTH, true)
			else:
				draw_line(points[i - 1] * radius, points[i] * radius, Color(ACCENT, alpha), width, true)
	var head_alpha := fade * (_trail_twin_alpha[last] if twin else 1.0)
	if head_alpha >= 0.02:
		var head := points[last] * radius
		draw_circle(head, TRAIL_WIDTH * 1.3, Color(ACCENT, head_alpha * GLOW_ALPHA), true, -1.0, true)
		draw_circle(head, TRAIL_WIDTH * 0.6, Color(ACCENT, head_alpha), true, -1.0, true)


## 円が出た瞬間に外へ広がって消える輪と光線。
func _draw_burst(center: Vector2, age: float) -> void:
	if age < 0.0 or age > BURST_SECONDS:
		return
	var p := age / BURST_SECONDS
	var out := 1.0 - pow(1.0 - p, 3.0)
	var alpha := 1.0 - p
	draw_arc(center, lerpf(9.0, 19.0, out), 0.0, TAU, 40, Color(GOOD.lightened(0.3), alpha * 0.8), lerpf(2.6, 0.6, p), true)
	for i: int in range(BURST_RAYS):
		var dir := Vector2.from_angle(TAU * float(i) / float(BURST_RAYS) + PI / float(BURST_RAYS))
		var from := dir * lerpf(12.0, 20.0, out)
		var to := dir * lerpf(14.0, 24.0, out)
		draw_line(center + from, center + to, Color(ACCENT, alpha), lerpf(2.4, 1.0, p), true)


## チェックがポンと出る大きさ：0 → 1.25 に膨らんでから 1.0 に戻る。
func _pop_scale(age: float) -> float:
	if age < 0.0:
		return 0.0
	var p := clampf(age / CHECK_POP_SECONDS, 0.0, 1.0)
	if p < 0.45:
		return lerpf(0.0, 1.25, p / 0.45)
	return lerpf(1.25, 1.0, smoothstep(0.0, 1.0, (p - 0.45) / 0.55))


## 緑の円の上に、stroke（0 → 1）の割合までチェックの線を引く。
func _draw_check(center: Vector2, radius: float, stroke: float) -> void:
	if radius <= 0.5:
		return
	draw_circle(center, radius, GOOD, true, -1.0, true)
	if stroke <= 0.0:
		return
	var s := radius / 7.5
	var corners := PackedVector2Array([
		center + Vector2(-3.4, 0.2) * s,
		center + Vector2(-0.9, 2.8) * s,
		center + Vector2(3.8, -2.6) * s,
	])
	var first := (corners[1] - corners[0]).length()
	var total := first + (corners[2] - corners[1]).length()
	var reach := total * smoothstep(0.0, 1.0, stroke)
	var points := PackedVector2Array([corners[0]])
	if reach <= first:
		points.append(corners[0].lerp(corners[1], reach / first))
	else:
		points.append(corners[1])
		points.append(corners[1].lerp(corners[2], (reach - first) / (total - first)))
	draw_polyline(points, CHECK_INK, 2.1 * s, true)
