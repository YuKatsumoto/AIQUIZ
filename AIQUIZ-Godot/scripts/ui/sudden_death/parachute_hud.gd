class_name ParachuteHud
extends CanvasLayer

## サドンデス「ひらけ！パラシュート」の HUD（docs/sudden_death_v2/parachute.md 第8章・3.1節・6.6節）。
## 問題パネル（上）・4択（下、P1 と P2 のキーの札）・2人の段の印（左上・右上）・高度計（右）・最後の1問の札・
## 図解ルールカード（3枚の絵）・勝者のダンスのキー（下）。見せ方（ParachutePresenter）が毎フレーム
## set_state() で中身を渡し、出入りの動きはここの時計で付ける。1280×720 を基準に、画面の大きさに合わせて縮める。
## 共通の部分（カウントダウン・勝者・閃光・掛け声）は SuddenDeathHud が受け持つ。マウスは受け取らない。

const REFERENCE := Vector2(1280.0, 720.0)
## SuddenDeathHud（8）の下、ゲームの HUD（5）の上。
const HUD_LAYER := 7
const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const RULE_IMAGES := [
	"res://assets/sudden_death/parachute/rule_card/rule_correct.png",
	"res://assets/sudden_death/parachute/rule_card/rule_wrong.png",
	"res://assets/sudden_death/parachute/rule_card/rule_win.png",
]
const INK := Color(0.094, 0.118, 0.165)
const MUTED := Color(0.376, 0.416, 0.486)
const PANEL := Color(1.0, 1.0, 1.0, 0.93)
const DARK := Color(0.078, 0.102, 0.149, 0.80)
const GOOD := Color(0.25, 0.77, 0.43)
const BAD := Color(0.91, 0.28, 0.28)
const AMBER := Color(1.0, 0.69, 0.18)
const PLAYER_COLORS: Array[Color] = [Color(0.95, 0.55, 0.20), Color(0.18, 0.59, 0.90)]
## ルールカードの絵の角の丸みと白いふち。
const IMAGE_RADIUS := 16.0
const IMAGE_BORDER := 5.0
## 出入りの速さ（1 秒あたり）。
const FADE_RATE := 6.0

const TEXT_JA := {
	"answered": "回答済み", "shrunk": "しぼんだ…", "miss": "はずれ…", "opened": "ひらけ！", "final": "高度150m！ 最後の1問（先に正解した方の勝ち）",
	"correct": "正解", "rules": "ルール", "how": "答え方", "order": "選択肢の左から順",
	"final_rule": "高度150mまでに決まらなければ「最後の1問」。先に正解した方の勝ち", "enter": "Enter でスタート",
	"emote_keys": "キーでエモート",
	"r1": "正解でパラシュートが\n1段ひらく", "r1s": "3段で全開",
	"r2": "まちがえると1段しぼんで\nきりもみ", "r2s": "答えなければそのまま",
	"r3": "先に全開した方が\n着地台に降りて勝ち！", "r3s": "勝ったら台の上でダンス！",
}
const TEXT_EN := {
	"answered": "ANSWERED", "shrunk": "SHRUNK…", "miss": "MISS…", "opened": "OPEN!", "final": "150 m! FINAL QUESTION - first right answer wins",
	"correct": "RIGHT", "rules": "RULES", "how": "ANSWER", "order": "choices from the left",
	"final_rule": "Not decided by 150 m? One final question: the first right answer wins", "enter": "Enter to start",
	"emote_keys": "keys to dance",
	"r1": "Right answer:\nthe chute opens 1 step", "r1s": "3 steps = fully open",
	"r2": "Wrong answer:\nit shrinks and you spin", "r2s": "no answer: no change",
	"r3": "Fully open first:\nland on the float and win!", "r3s": "the winner dances on the float!",
}

class Painter extends Control:
	var hud: ParachuteHud

	func _draw() -> void:
		if hud != null:
			hud._paint(self)


var english := false
## テストは debug_step で時計を進める。
var debug_manual_clock := false
var state := {}
var _painter: Painter
var _images: Array[Texture2D] = []
var _clock := 0.0
var _last_usec := 0
## 要素ごとの見え方 0〜1。
var _alpha := {"quiz": 0.0, "status": 0.0, "altimeter": 0.0, "final": 0.0, "rules": 0.0, "emote": 0.0, "winner": 0.0}
## 消えていく間も中身を描けるよう、最後に見えていた問題・勝者を覚えておく。
var _last_quiz := {}
var _last_winner := 0
var _quiz_number := -1
var _quiz_since := 0.0
var _reveal_since := 0.0
var _was_reveal := false
var _rules_since := 0.0
var _rects := {}


func _init() -> void:
	name = "ParachuteHud"
	layer = HUD_LAYER
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_painter = Painter.new()
	_painter.name = "Painter"
	_painter.hud = self
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ルールカードの絵（960×720）を縮めて描くので、ミップマップで縮める（ざらつかないように）
	_painter.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(_painter)
	for path: String in RULE_IMAGES:
		_images.append(load(path) as Texture2D)


func set_state(next: Dictionary) -> void:
	var quiz: Dictionary = next.get("quiz", {})
	if bool(quiz.get("visible", false)):
		_last_quiz = quiz
	if int(next.get("winner", 0)) > 0:
		_last_winner = int(next.winner)
	var number := int(quiz.get("number", -1))
	if number != _quiz_number and bool(quiz.get("visible", false)):
		_quiz_number = number
		_quiz_since = _clock
	var reveal := bool(quiz.get("reveal", false))
	if reveal and not _was_reveal:
		_reveal_since = _clock
	_was_reveal = reveal
	if bool(next.get("rules", false)) and not bool(state.get("rules", false)):
		_rules_since = _clock
	state = next
	if bool(next.get("instant", false)):
		# カットの瞬間：消えるものは、時計が進むのを待たずにこのフレームで消す
		if not bool(next.get("quiz", {}).get("visible", false)):
			_alpha["quiz"] = 0.0
		if not bool(next.get("final_alert", false)):
			_alpha["final"] = 0.0
		_painter.queue_redraw()


func hide_all() -> void:
	state = {}


func debug_step(seconds: float) -> void:
	_advance(maxf(seconds, 0.0))


func get_debug_snapshot() -> Dictionary:
	var alphas := {}
	for key: String in _alpha:
		alphas[key] = snappedf(float(_alpha[key]), 0.01)
	return {"alpha": alphas, "quiz_number": _quiz_number, "rects": _rects.duplicate(), "state_keys": state.keys()}


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now
	var step := clampf(float(now - _last_usec) / 1000000.0, 0.0, 0.25)
	_last_usec = now
	if not debug_manual_clock:
		_advance(step)


func _advance(dt: float) -> void:
	_clock += dt
	var targets := {
		"quiz": bool(state.get("quiz", {}).get("visible", false)),
		"status": bool(state.get("status", {}).get("visible", false)),
		"altimeter": bool(state.get("altimeter", {}).get("visible", false)),
		"final": bool(state.get("final_alert", false)),
		"rules": bool(state.get("rules", false)),
		"emote": bool(state.get("emote", {}).get("visible", false)),
		"winner": int(state.get("winner", 0)) > 0,
	}
	var instant := bool(state.get("instant", false))
	for key: String in _alpha:
		var target := 1.0 if bool(targets[key]) else 0.0
		# カットの瞬間（instant）は、消えるものをすぐ消す
		if instant and target == 0.0:
			_alpha[key] = 0.0
		else:
			_alpha[key] = move_toward(float(_alpha[key]), target, dt * FADE_RATE)
	_painter.queue_redraw()


func _t(key: String) -> String:
	return str((TEXT_EN if english else TEXT_JA).get(key, key))


# ------------------------------------------------------------------ paint

## 基準（1280×720）から画面への変換：拡大率と左上。
func _frame(ci: Control) -> Array:
	var size := ci.size
	var s := minf(size.x / REFERENCE.x, size.y / REFERENCE.y)
	var origin := (size - REFERENCE * s) * 0.5
	return [s, origin]


func _paint(ci: Control) -> void:
	var f := _frame(ci)
	var s: float = f[0]
	var o: Vector2 = f[1]
	ci.draw_set_transform(o, 0.0, Vector2(s, s))
	_rects.clear()
	if _alpha.rules > 0.001:
		_paint_rules(ci, float(_alpha.rules))
	if _alpha.quiz > 0.001:
		_paint_quiz(ci, float(_alpha.quiz))
	if _alpha.status > 0.001:
		_paint_status(ci, float(_alpha.status))
	if _alpha.altimeter > 0.001:
		_paint_altimeter(ci, float(_alpha.altimeter))
	if _alpha.final > 0.001:
		_paint_pill(ci, Vector2(640.0, 128.0), _t("final"), BAD, 20, float(_alpha.final))
	if _alpha.emote > 0.001:
		_paint_emote(ci, float(_alpha.emote))
	if _alpha.winner > 0.001 and _last_winner > 0:
		var pop := _ease_out(float(_alpha.winner))
		_paint_pill(ci, Vector2(640.0, 52.0 - (1.0 - pop) * 20.0), "P%d WIN!" % _last_winner, PLAYER_COLORS[_last_winner - 1], 32, float(_alpha.winner))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _box(ci: Control, rect: Rect2, color: Color, radius := 14.0, border := Color(0, 0, 0, 0), border_width := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	if border_width > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(border_width))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, rect)


func _shadow(ci: Control, rect: Rect2, alpha: float, radius := 14.0) -> void:
	_box(ci, Rect2(rect.position + Vector2(0, 4), rect.size), Color(0, 0, 0, 0.22 * alpha), radius)


## 真ん中ぞろえの 1 行（幅に入らなければ縮める）。
func _text(ci: Control, center: Vector2, text: String, size: int, color: Color, max_width := 0.0) -> void:
	var font_size := size
	if max_width > 0.0:
		var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		while width > max_width and font_size > 10:
			font_size -= 1
			width = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ascent := FONT.get_ascent(font_size)
	var descent := FONT.get_descent(font_size)
	ci.draw_string(FONT, Vector2(center.x - w * 0.5, center.y + (ascent - descent) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _text_left(ci: Control, left_center: Vector2, text: String, size: int, color: Color) -> void:
	var ascent := FONT.get_ascent(size)
	var descent := FONT.get_descent(size)
	ci.draw_string(FONT, Vector2(left_center.x, left_center.y + (ascent - descent) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _ease_out(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _paint_pill(ci: Control, center: Vector2, text: String, color: Color, size: int, alpha: float) -> void:
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 44.0
	var rect := Rect2(center - Vector2(w * 0.5, size * 0.95), Vector2(w, size * 1.9))
	_box(ci, rect, Color(color, 0.95 * alpha), size * 0.95)
	_text(ci, center, text, size, Color(1, 1, 1, alpha))


## パラシュートの段の印（ドームとひも）。
func _chute_icon(ci: Control, center: Vector2, r: float, color: Color, filled: bool, alpha: float) -> void:
	var points := PackedVector2Array()
	for i in range(13):
		var a := PI + PI * float(i) / 12.0
		points.append(center + Vector2(cos(a), sin(a) * 0.9) * r)
	var fill := Color(color, alpha) if filled else Color(1, 1, 1, 0.18 * alpha)
	ci.draw_colored_polygon(points, fill)
	ci.draw_polyline(points, Color(1, 1, 1, alpha), maxf(1.5, r * 0.12), true)
	ci.draw_line(points[0], points[12], Color(1, 1, 1, alpha), maxf(1.5, r * 0.1), true)
	for k: float in [-0.85, 0.0, 0.85]:
		ci.draw_line(center + Vector2(r * k, 0.0), center + Vector2(0.0, r * 0.95), Color(1, 1, 1, alpha), maxf(1.0, r * 0.08), true)
	ci.draw_circle(center + Vector2(0.0, r), r * 0.16, Color(1, 1, 1, alpha))


func _paint_quiz(ci: Control, alpha: float) -> void:
	var quiz: Dictionary = state.get("quiz", {})
	if not bool(quiz.get("visible", false)):
		quiz = _last_quiz
	var slide := (1.0 - _ease_out((_clock - _quiz_since) / 0.25)) * -40.0
	var rect := Rect2(250.0, 14.0 + slide, 780.0, 82.0)
	_shadow(ci, rect, alpha)
	_box(ci, rect, Color(PANEL, PANEL.a * alpha), 20.0)
	var badge := Rect2(rect.position + Vector2(14, 14), Vector2(64, 54))
	_box(ci, badge, Color(BAD if bool(quiz.get("final", false)) else INK, alpha), 14.0)
	_text(ci, badge.get_center(), "Q%d" % int(quiz.get("number", 1)), 24, Color(1, 1, 1, alpha))
	_text(ci, rect.position + Vector2(440, 39), str(quiz.get("text", "")), 30, Color(INK, alpha), 660.0)
	var timer := clampf(float(quiz.get("timer", 0.0)), 0.0, 1.0)
	var bar := Rect2(rect.position + Vector2(94, 70), Vector2(670, 6))
	_box(ci, bar, Color(0.86, 0.88, 0.91, alpha), 3.0)
	var warn := timer < 3.0 / 8.0 and not bool(quiz.get("reveal", false))
	if timer > 0.0:
		_box(ci, Rect2(bar.position, Vector2(bar.size.x * timer, bar.size.y)), Color(BAD if warn else AMBER, alpha), 3.0)
	_rects["quiz"] = rect
	_paint_choices(ci, quiz, alpha)


func _paint_choices(ci: Control, quiz: Dictionary, alpha: float) -> void:
	var choices: Array = Array(quiz.get("choices", PackedStringArray()))
	var count := choices.size()
	if count == 0:
		return
	var keys: Array = quiz.get("keys", [])
	var reveal := bool(quiz.get("reveal", false))
	var correct := int(quiz.get("correct", -1))
	var picks: Array = quiz.get("picks", [-1, -1])
	var locked: Array = quiz.get("locked", [false, false])
	var w := 272.0 if count >= 4 else 330.0
	var gap := 14.0
	var total := w * count + gap * (count - 1)
	var x0 := (REFERENCE.x - total) * 0.5
	var y := 620.0
	for i in range(count):
		var delay := 0.05 * i
		var rise := (1.0 - _ease_out((_clock - _quiz_since - delay) / 0.25)) * 50.0
		var rect := Rect2(x0 + i * (w + gap), y + rise, w, 74.0)
		var picked := (int(picks[0]) == i) or (int(picks[1]) == i)
		var dim := reveal and i != correct and not picked
		var fill := Color(1, 1, 1, (0.55 if dim else 0.94) * alpha)
		var border := Color(0, 0, 0, 0)
		var bw := 0.0
		if reveal and i == correct:
			border = Color(GOOD, alpha)
			bw = 6.0
		elif reveal and picked:
			border = Color(BAD, alpha)
			bw = 6.0
		_shadow(ci, rect, alpha)
		_box(ci, rect, fill, 16.0, border, bw)
		var key_labels: Array = keys[i] if i < keys.size() else ["", ""]
		for side in [0, 1]:
			var label := str(key_labels[side])
			if label == "":
				continue
			var chip := Rect2(rect.position + Vector2(10, 9) if side == 0 else rect.position + Vector2(rect.size.x - 46, 9), Vector2(36, 30))
			var chip_color := PLAYER_COLORS[side]
			if bool(locked[side]):
				chip_color = Color(0.6, 0.6, 0.62)
			_box(ci, chip, Color(chip_color, alpha), 8.0)
			_text(ci, chip.get_center(), label, 18, Color(1, 1, 1, alpha))
		_text(ci, rect.position + Vector2(w * 0.5, 48), str(choices[i]), 26, Color(INK if not dim else MUTED, alpha), w - 30.0)
		if reveal and i == correct:
			var pop := _ease_out((_clock - _reveal_since) / 0.2)
			_text(ci, rect.position + Vector2(w * 0.5, -16 - 6 * pop), _t("correct"), 22, Color(GOOD, alpha * pop))
		if reveal:
			for side in [0, 1]:
				if int(picks[side]) == i:
					var tag := Rect2(rect.position + (Vector2(16, rect.size.y - 6) if side == 0 else Vector2(rect.size.x - 76, rect.size.y - 6)), Vector2(60, 28))
					_box(ci, tag, Color(PLAYER_COLORS[side], alpha), 12.0)
					_text(ci, tag.get_center(), "P%d" % (side + 1), 17, Color(1, 1, 1, alpha))
		_rects["choice_%d" % i] = rect


func _paint_status(ci: Control, alpha: float) -> void:
	var status: Dictionary = state.get("status", {})
	var stages: Array = status.get("stage", [0, 0])
	var tags: Array = status.get("tags", ["", ""])
	for side in [0, 1]:
		var x := 18.0 if side == 0 else REFERENCE.x - 18.0 - 236.0
		var rect := Rect2(x, 16.0, 236.0, 70.0)
		_shadow(ci, rect, alpha)
		_box(ci, rect, Color(DARK, DARK.a * alpha), 18.0)
		var chip := Rect2(rect.position + Vector2(10, 10), Vector2(58, 50))
		_box(ci, chip, Color(PLAYER_COLORS[side], alpha), 12.0)
		_text(ci, chip.get_center(), "P%d" % (side + 1), 24, Color(1, 1, 1, alpha))
		for k in range(3):
			_chute_icon(ci, rect.position + Vector2(104 + k * 48, 32), 17.0, PLAYER_COLORS[side], k < int(stages[side]), alpha)
		var tag := str(tags[side])
		if tag != "":
			var w := FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 26.0
			var tr := Rect2(rect.position + Vector2(rect.size.x * 0.5 - w * 0.5 + 30, rect.size.y + 6), Vector2(w, 28))
			var color := BAD if tag in [_t("shrunk"), _t("miss")] else (GOOD if tag == _t("opened") else PLAYER_COLORS[side])
			_box(ci, tr, Color(color, alpha), 14.0)
			_text(ci, tr.get_center(), tag, 17, Color(1, 1, 1, alpha))
		_rects["status_%d" % (side + 1)] = rect


func _paint_altimeter(ci: Control, alpha: float) -> void:
	var data: Dictionary = state.get("altimeter", {})
	var altitude := float(data.get("altitude", 2000.0))
	var rel: Array = data.get("rel", [0.0, 0.0])
	var rect := Rect2(REFERENCE.x - 68.0, 150.0, 50.0, 400.0)
	_shadow(ci, rect, alpha, 22.0)
	_box(ci, rect, Color(DARK, DARK.a * alpha), 22.0)
	_text(ci, rect.position + Vector2(25, -14), "%dm" % int(round(altitude)), 17, Color(1, 1, 1, alpha))
	var track := Rect2(rect.position + Vector2(19, 18), Vector2(12, rect.size.y - 46))
	_box(ci, track, Color(1, 1, 1, 0.25 * alpha), 6.0)
	var frac := clampf(altitude / ParachuteGame.ALTITUDE_START, 0.0, 1.0)
	var top := track.position.y + track.size.y * (1.0 - frac)
	_box(ci, Rect2(track.position.x, top, track.size.x, track.end.y - top), Color(0.47, 0.78, 1.0, 0.9 * alpha), 6.0)
	# 下に着地台
	ci.draw_circle(Vector2(rect.position.x + 25, track.end.y + 13), 9.0, Color(1.0, 0.82, 0.16, alpha))
	for side in [0, 1]:
		var y := clampf(top - float(rel[side]) * 10.0, track.position.y, track.end.y)
		var cx := track.position.x - 3.0 if side == 0 else track.end.x + 3.0
		ci.draw_circle(Vector2(cx, y), 9.0, Color(1, 1, 1, alpha))
		ci.draw_circle(Vector2(cx, y), 7.0, Color(PLAYER_COLORS[side], alpha))
	_rects["altimeter"] = rect


func _paint_rules(ci: Control, alpha: float) -> void:
	var dim := Color(0.04, 0.06, 0.11, 0.55 * alpha)
	ci.draw_rect(Rect2(Vector2(-2000, -2000), Vector2(6000, 6000)), dim)
	var t := _clock - _rules_since
	var card := Rect2(90.0, 52.0, 1100.0, 616.0)
	var pop := _ease_out(t / 0.3)
	card.position.y += (1.0 - pop) * 30.0
	_box(ci, card, Color(0.98, 0.98, 0.99, 0.97 * alpha), 30.0)
	_text(ci, card.position + Vector2(550, 46), _t("rules"), 38, Color(INK, alpha))
	var pw := 320.0
	var ph := 240.0
	var gap := 36.0
	var x0 := card.position.x + (card.size.x - (pw * 3 + gap * 2)) * 0.5
	var colors := [GOOD, BAD, PLAYER_COLORS[0]]
	for i in range(3):
		# 左から 0.12 秒ずつずれて浮き上がる（少し行き過ぎて戻る）
		var k := clampf((t - 0.12 * i) / 0.35, 0.0, 1.0)
		var back := 1.0 + 2.70158 * pow(k - 1.0, 3.0) + 1.70158 * pow(k - 1.0, 2.0)
		var y := card.position.y + 84.0 + (1.0 - back) * 30.0
		var x := x0 + i * (pw + gap)
		var a := alpha * k
		var image_rect := Rect2(x, y, pw, ph)
		_box(ci, Rect2(image_rect.position + Vector2(0, 5), image_rect.size), Color(0.05, 0.08, 0.14, 0.16 * a), IMAGE_RADIUS)
		if i < _images.size() and _images[i] != null:
			_rounded_image(ci, _images[i], image_rect, IMAGE_RADIUS, a)
		# ふちは絵と同じ角の丸みで、絵の外側へ描く（角から絵がはみ出さない）
		_box(ci, image_rect.grow(IMAGE_BORDER), Color(0, 0, 0, 0), IMAGE_RADIUS + IMAGE_BORDER, Color(1, 1, 1, a), IMAGE_BORDER)
		var badge := Rect2(x + 12, y + 12, 46, 46)
		_box(ci, badge, Color(colors[i], a), 23.0)
		_text(ci, badge.get_center(), str(i + 1), 26, Color(1, 1, 1, a))
		if i == 0:
			for n in range(3):
				var lit := t > 0.5 + 0.4 * n
				_chute_icon(ci, Vector2(x + pw - 118 + n * 44, y + 38), 16.0, PLAYER_COLORS[0], lit, a)
		var lines := _t("r%d" % (i + 1)).split("\n")
		for l in range(lines.size()):
			_text(ci, Vector2(x + pw * 0.5, y + ph + 32 + l * 34), lines[l], 25, Color(INK, a), pw + 20)
		_text(ci, Vector2(x + pw * 0.5, y + ph + 32 + lines.size() * 34 + 4), _t("r%ds" % (i + 1)), 18, Color(MUTED, a), pw + 20)
	# 答え方の帯
	var strip := Rect2(card.position.x + 36, card.end.y - 140, card.size.x - 72, 60)
	_box(ci, strip, Color(0.925, 0.937, 0.961, alpha), 16.0)
	_text_left(ci, strip.position + Vector2(24, 30), _t("how"), 22, Color(INK, alpha))
	var kx := strip.position.x + 150.0
	var key_sets := [["A", "W", "S", "D"], ["←", "↑", "↓", "→"]]
	for side in [0, 1]:
		var chip := Rect2(kx, strip.position.y + 13, 50, 34)
		_box(ci, chip, Color(PLAYER_COLORS[side], alpha), 9.0)
		_text(ci, chip.get_center(), "P%d" % (side + 1), 18, Color(1, 1, 1, alpha))
		kx += 60.0
		for label: String in key_sets[side]:
			var key_rect := Rect2(kx, strip.position.y + 13, 36, 34)
			_box(ci, key_rect, Color(1, 1, 1, alpha), 8.0, Color(PLAYER_COLORS[side], alpha), 3.0)
			_text(ci, key_rect.get_center(), label, 18, Color(INK, alpha))
			kx += 42.0
		kx += 34.0
	_text_left(ci, Vector2(kx, strip.position.y + 30), _t("order"), 18, Color(MUTED, alpha))
	_text(ci, Vector2(card.position.x + card.size.x * 0.5, strip.end.y + 28), _t("final_rule"), 20, Color(INK, alpha), card.size.x - 80)
	if bool(state.get("rules_prompt", false)):
		var blink := 0.65 + 0.35 * sin(t * 5.0)
		_paint_pill(ci, Vector2(card.end.x - 150.0, card.position.y + 46.0), _t("enter"), INK, 20, alpha * blink)
	_rects["rules"] = card


## 絵を角の丸い四角に切り抜いて描く（角の外は描かない）。
func _rounded_image(ci: Control, texture: Texture2D, rect: Rect2, radius: float, alpha: float) -> void:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - radius, rect.position.y + radius), -PI * 0.5],
		[Vector2(rect.end.x - radius, rect.end.y - radius), 0.0],
		[Vector2(rect.position.x + radius, rect.end.y - radius), PI * 0.5],
		[Vector2(rect.position.x + radius, rect.position.y + radius), PI],
	]
	for corner: Array in corners:
		for n in range(9):
			var angle := float(corner[1]) + PI * 0.5 * n / 8.0
			var point: Vector2 = corner[0] + Vector2(cos(angle), sin(angle)) * radius
			points.append(point)
			uvs.append((point - rect.position) / rect.size)
	ci.draw_colored_polygon(points, Color(1, 1, 1, alpha), uvs, texture)


## 勝者のダンスの間：下の真ん中に小さく「[1][2][3] キーでエモート」（P2 は 8・9・0）。踊っている札は白いふち。
func _paint_emote(ci: Control, alpha: float) -> void:
	var data: Dictionary = state.get("emote", {})
	var player := clampi(int(data.get("player", 1)), 1, 2)
	var playing := int(data.get("playing", -1))
	var keys := ["1", "2", "3"] if player == 1 else ["8", "9", "0"]
	var color := PLAYER_COLORS[player - 1]
	var label := _t("emote_keys")
	var size := 18
	var chip := 30.0
	var gap := 6.0
	var label_w := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := 16.0 + chip * 3 + gap * 2 + 10.0 + label_w + 18.0
	var rect := Rect2(Vector2(640.0 - w * 0.5, 668.0), Vector2(w, 40.0))
	_box(ci, rect, Color(DARK, DARK.a * alpha), 20.0)
	var x := rect.position.x + 16.0
	for i in range(3):
		var r := Rect2(x, rect.position.y + 5.0, chip, chip)
		var on := playing == i
		_box(ci, r, Color(color, alpha), 8.0, Color(1, 1, 1, alpha), 3.0 if on else 0.0)
		_text(ci, r.get_center(), keys[i], 18, Color(1, 1, 1, alpha))
		x += chip + gap
	_text_left(ci, Vector2(x + 4.0, rect.position.y + 20.0), label, size, Color(1, 1, 1, alpha))
	_rects["emote"] = rect
