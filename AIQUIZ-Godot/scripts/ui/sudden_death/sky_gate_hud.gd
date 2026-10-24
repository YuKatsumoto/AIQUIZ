class_name SkyGateHud
extends CanvasLayer

## サドンデス「つきやぶれ！スカイゲート」の HUD（docs/sudden_death_v2/sky_gate.md 3.1節、skygate_build_plan.md 4.5節）。
## 上の真ん中に ROUND とゲートの数・残りの帯、左上と右上に 2 人の札（「15 の上」「セーフ！」「アウト」）、下に小さく動かし方のキー。
## 問題文は出さない（ボードの看板だけ）。図解ルールカード（3 枚の絵は、ゲーム内の 3D の実演 SkyGateRuleDemo を映す。
## 見せ方が set_rule_textures で渡す）、ラウンドの大きな見出し（「ROUND 2」）、
## 小さな知らせ（「ボードが動く！」「早い者勝ち！」）、勝者の札と勝者のダンスのキー。
## 見せ方（SkyGatePresenter）が毎フレーム set_state() で中身を渡し、出入りの動きはここの時計で付ける。
## 1280×720 を基準に、画面の大きさに合わせて縮める。カウントダウン・閃光は共通の SuddenDeathHud。マウスは受け取らない。

const REFERENCE := Vector2(1280.0, 720.0)
## SuddenDeathHud（8）の下、ゲームの HUD（5）の上。
const HUD_LAYER := 7
const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const INK := Color(0.094, 0.118, 0.165)
const MUTED := Color(0.376, 0.416, 0.486)
const PANEL := Color(1.0, 1.0, 1.0, 0.93)
const DARK := Color(0.078, 0.102, 0.149, 0.80)
const GOOD := Color(0.25, 0.77, 0.43)
const BAD := Color(0.91, 0.28, 0.28)
const AMBER := Color(1.0, 0.69, 0.18)
const PLAYER_COLORS: Array[Color] = [Color(0.95, 0.55, 0.20), Color(0.18, 0.59, 0.90)]
const IMAGE_RADIUS := 16.0
const IMAGE_BORDER := 5.0
const FADE_RATE := 6.0
## 残りの帯が赤くなる（残り 3/8）。
const WARN_RATIO := 0.375

const TEXT_JA := {
	"rules": "ルール", "enter": "Enter でスタート", "move": "で動く", "gate": "ゲート %d/%d", "overtime": "延長",
	"one_by_one": "1枚ずつ %d秒", "on": "%s の上", "safe": "セーフ！", "boom": "ドカン！", "out": "アウト", "revive": "復活！",
	"slow": "おそい…", "win": "勝ち！", "emote_keys": "キーでエモート",
	"r1": "動いて、正しい答えの\nパネルの上へ", "r1s": "P1 は WASD、P2 は 矢印",
	"r2": "時間切れで、正解の\nパネルはつき破れる！", "r2s": "次のゲートへ",
	"r3": "まちがいは破れない！\nはね返されてドカン", "r3s": "アウト。相手が残れば相手の勝ち",
	"rule_bottom": "2人とも地上に着いたら、次のラウンド（だんだん速く・むずかしく）",
}
const TEXT_EN := {
	"rules": "RULES", "enter": "Enter to start", "move": "to move", "gate": "GATE %d/%d", "overtime": "OVERTIME",
	"one_by_one": "ONE BY ONE %ds", "on": "ON %s", "safe": "SAFE!", "boom": "BOOM!", "out": "OUT", "revive": "BACK!",
	"slow": "TOO SLOW…", "win": "WIN!", "emote_keys": "keys to dance",
	"r1": "Move over the panel\nwith the right answer", "r1s": "P1: WASD, P2: arrow keys",
	"r2": "Time's up: the right\npanel breaks open!", "r2s": "on to the next gate",
	"r3": "The wrong panel holds:\nbounce and BOOM!", "r3s": "you're out - if the other survives, they win",
	"rule_bottom": "Both reach the ground: next round (faster and harder each time)",
}

class Painter extends Control:
	var hud: SkyGateHud

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
var _alpha := {"round": 0.0, "players": 0.0, "keys": 0.0, "rules": 0.0, "banner": 0.0, "notice": 0.0, "emote": 0.0, "winner": 0.0}
## 消えていく間も描けるよう、最後に見えていた中身を覚えておく。
var _last := {}
var _rules_since := 0.0
var _banner_since := 0.0
var _banner_text := ""
var _notice_since := 0.0
var _notice_text := ""
var _tag_since := [0.0, 0.0]
var _tag_text := ["", ""]
var _gate_since := 0.0
var _gate_key := ""
var _rects := {}


func _init() -> void:
	name = "SkyGateHud"
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
	_painter.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(_painter)


## 図解ルールカードの 3 枚の絵（見せ方の SkyGateRuleDemo の ViewportTexture。動く絵なので毎フレーム描き直される）。
func set_rule_textures(textures: Array[Texture2D]) -> void:
	_images = textures


## 中身：
##   "rules": bool, "rules_prompt": bool（Enter を受け付ける）
##   "round": {"visible", "round", "gate"（0 から）, "gates", "timer"（0〜1）, "overtime", "gate_time", "done": [P1 の枚数, P2]}
##   "players": {"visible", "tags": [{"text", "tone"（"player" / "good" / "bad"）}, …]}
##   "keys": bool（動かし方のキー）
##   "banner": {"text", "sub", "color"}（大きな見出し）・"notice": {"text", "color"}（小さな知らせ）
##   "winner": 1 / 2・"emote": {"visible", "player", "names", "playing", "seconds"}
func set_state(next: Dictionary) -> void:
	for key: String in ["round", "players"]:
		if bool((next.get(key, {}) as Dictionary).get("visible", false)):
			_last[key] = next[key]
	if int(next.get("winner", 0)) > 0:
		_last["winner"] = int(next.winner)
	if bool(next.get("rules", false)) and not bool(state.get("rules", false)):
		_rules_since = _clock
	var banner: Dictionary = next.get("banner", {})
	if not banner.is_empty():
		if str(banner.get("text", "")) != _banner_text:
			_banner_text = str(banner.get("text", ""))
			_banner_since = _clock
		_last["banner"] = banner
	var notice: Dictionary = next.get("notice", {})
	if not notice.is_empty():
		if str(notice.get("text", "")) != _notice_text:
			_notice_text = str(notice.get("text", ""))
			_notice_since = _clock
		_last["notice"] = notice
	var round_state: Dictionary = next.get("round", {})
	if bool(round_state.get("visible", false)):
		var key := "%d|%d|%s" % [int(round_state.get("round", 0)), int(round_state.get("gate", 0)), str(round_state.get("overtime", false))]
		if key != _gate_key:
			_gate_key = key
			_gate_since = _clock
	var tags: Array = (next.get("players", {}) as Dictionary).get("tags", [])
	for side: int in [0, 1]:
		var text := str((tags[side] as Dictionary).get("text", "")) if side < tags.size() else ""
		if text != str(_tag_text[side]):
			_tag_text[side] = text
			_tag_since[side] = _clock
	state = next


func hide_all() -> void:
	state = {}


func debug_step(seconds: float) -> void:
	_advance(maxf(seconds, 0.0))


func get_debug_snapshot() -> Dictionary:
	var alphas := {}
	for key: String in _alpha:
		alphas[key] = snappedf(float(_alpha[key]), 0.01)
	return {"alpha": alphas, "rects": _rects.duplicate(), "state_keys": state.keys(), "banner": _banner_text, "notice": _notice_text,
		"tags": _tag_text.duplicate()}


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
		"round": bool((state.get("round", {}) as Dictionary).get("visible", false)),
		"players": bool((state.get("players", {}) as Dictionary).get("visible", false)),
		"keys": bool(state.get("keys", false)),
		"rules": bool(state.get("rules", false)),
		"banner": not (state.get("banner", {}) as Dictionary).is_empty(),
		"notice": not (state.get("notice", {}) as Dictionary).is_empty(),
		"emote": bool((state.get("emote", {}) as Dictionary).get("visible", false)),
		"winner": int(state.get("winner", 0)) > 0,
	}
	for key: String in _alpha:
		_alpha[key] = move_toward(float(_alpha[key]), 1.0 if bool(targets[key]) else 0.0, dt * FADE_RATE)
	_painter.queue_redraw()


func _t(key: String) -> String:
	return str((TEXT_EN if english else TEXT_JA).get(key, key))


# ------------------------------------------------------------------ paint

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
	if _alpha.keys > 0.001:
		_paint_keys(ci, float(_alpha.keys))
	if _alpha.round > 0.001:
		_paint_round(ci, float(_alpha.round))
	if _alpha.players > 0.001:
		_paint_players(ci, float(_alpha.players))
	if _alpha.notice > 0.001:
		_paint_notice(ci, float(_alpha.notice))
	if _alpha.banner > 0.001:
		_paint_banner(ci, float(_alpha.banner))
	if _alpha.emote > 0.001:
		_paint_emote(ci, float(_alpha.emote))
	if _alpha.winner > 0.001 and int(_last.get("winner", 0)) > 0:
		var winner := int(_last.winner)
		var pop := _ease_out(float(_alpha.winner))
		_paint_pill(ci, Vector2(640.0, 52.0 - (1.0 - pop) * 20.0), "P%d WIN!" % winner, PLAYER_COLORS[winner - 1], 32, float(_alpha.winner))
	if _alpha.rules > 0.001:
		_paint_rules(ci, float(_alpha.rules))
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


func _text_left(ci: Control, left_center: Vector2, text: String, size: int, color: Color, max_width := 0.0) -> void:
	var font_size := size
	if max_width > 0.0:
		while FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width and font_size > 10:
			font_size -= 1
	var ascent := FONT.get_ascent(font_size)
	var descent := FONT.get_descent(font_size)
	ci.draw_string(FONT, Vector2(left_center.x, left_center.y + (ascent - descent) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _ease_out(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _back_out(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	return 1.0 + 2.70158 * pow(k - 1.0, 3.0) + 1.70158 * pow(k - 1.0, 2.0)


func _paint_pill(ci: Control, center: Vector2, text: String, color: Color, size: int, alpha: float) -> Rect2:
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 44.0
	var rect := Rect2(center - Vector2(w * 0.5, size * 0.95), Vector2(w, size * 1.9))
	_box(ci, rect, Color(color, 0.95 * alpha), size * 0.95)
	_text(ci, center, text, size, Color(1, 1, 1, alpha))
	return rect


## 上の真ん中：ROUND とゲートの数（4 つの印）・残りの帯。ROUND 5 のあとは「延長」と「1枚ずつ n 秒」。
func _paint_round(ci: Control, alpha: float) -> void:
	var data: Dictionary = state.get("round", {})
	if not bool(data.get("visible", false)):
		data = _last.get("round", {})
	var overtime := bool(data.get("overtime", false))
	var gates := maxi(int(data.get("gates", 4)), 1)
	var gate := int(data.get("gate", 0))
	var slide := (1.0 - _ease_out(alpha)) * -30.0
	var rect := Rect2(440.0, 14.0 + slide, 400.0, 74.0)
	_shadow(ci, rect, alpha, 18.0)
	_box(ci, rect, Color(DARK, DARK.a * alpha), 18.0)
	var badge := Rect2(rect.position + Vector2(10, 10), Vector2(118, 38))
	_box(ci, badge, Color(BAD if overtime else Color(1, 1, 1), alpha), 12.0)
	var badge_text := _t("overtime") if overtime else "ROUND %d" % int(data.get("round", 1))
	_text(ci, badge.get_center(), badge_text, 20, Color(1, 1, 1, alpha) if overtime else Color(INK, alpha), badge.size.x - 12.0)
	var info_x := badge.end.x + 14.0
	if overtime:
		_text_left(ci, Vector2(info_x, badge.get_center().y), _t("one_by_one") % int(round(float(data.get("gate_time", 3.0)))), 19,
			Color(1, 1, 1, alpha), rect.end.x - info_x - 12.0)
	else:
		_text_left(ci, Vector2(info_x, badge.get_center().y), _t("gate") % [mini(gate + 1, gates), gates], 19, Color(1, 1, 1, alpha))
		# ゲートの印：通った（白）・今（明るく脈打つ）・まだ（うすい）
		var pop := _ease_out((_clock - _gate_since) / 0.3)
		for i in range(gates):
			var c := Vector2(rect.end.x - 26.0 - float(gates - 1 - i) * 30.0, badge.get_center().y)
			if i < gate:
				ci.draw_circle(c, 9.0, Color(1, 1, 1, 0.95 * alpha))
			elif i == gate:
				ci.draw_circle(c, 9.0 + 3.0 * (1.0 - pop), Color(AMBER, alpha))
			else:
				ci.draw_arc(c, 8.0, 0.0, TAU, 20, Color(1, 1, 1, 0.45 * alpha), 2.0, true)
	var timer := clampf(float(data.get("timer", 0.0)), 0.0, 1.0)
	var bar := Rect2(rect.position + Vector2(12, 56), Vector2(rect.size.x - 24.0, 8.0))
	_box(ci, bar, Color(1, 1, 1, 0.18 * alpha), 4.0)
	if timer > 0.0:
		var warn := timer < WARN_RATIO
		var color := BAD if warn else AMBER
		if warn:
			color = color.lerp(Color(1, 1, 1), 0.25 * (0.5 + 0.5 * sin(_clock * 18.0)))
		_box(ci, Rect2(bar.position, Vector2(bar.size.x * timer, bar.size.y)), Color(color, alpha), 4.0)
	_rects["round"] = rect


## 左上（P1）と右上（P2）の札：P の札と今の状態（「15 の上」「セーフ！」「ドカン！」「アウト」）。
func _paint_players(ci: Control, alpha: float) -> void:
	var data: Dictionary = state.get("players", {})
	if not bool(data.get("visible", false)):
		data = _last.get("players", {})
	var tags: Array = data.get("tags", [])
	for side: int in [0, 1]:
		var tag: Dictionary = tags[side] if side < tags.size() else {}
		var text := str(tag.get("text", ""))
		var tone := str(tag.get("tone", "player"))
		var color: Color = PLAYER_COLORS[side]
		if tone == "good":
			color = GOOD
		elif tone == "bad":
			color = BAD
		elif tone == "dim":
			color = Color(0.45, 0.48, 0.55)
		var w := 300.0
		var x := 18.0 if side == 0 else REFERENCE.x - 18.0 - w
		var rect := Rect2(x, 16.0, w, 58.0)
		_shadow(ci, rect, alpha, 18.0)
		_box(ci, rect, Color(DARK, DARK.a * alpha), 18.0)
		var chip := Rect2(rect.position + Vector2(8, 8), Vector2(56, 42))
		_box(ci, chip, Color(PLAYER_COLORS[side], alpha), 12.0)
		_text(ci, chip.get_center(), "P%d" % (side + 1), 22, Color(1, 1, 1, alpha))
		if text != "":
			# 中身が変わったら小さく跳ねる
			var pop := _back_out((_clock - float(_tag_since[side])) / 0.28)
			var tw := minf(FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 30.0, w - 84.0)
			var tr := Rect2(chip.end.x + 10.0, rect.position.y + 10.0, tw, 38.0)
			tr = Rect2(tr.get_center() - tr.size * 0.5 * pop, tr.size * pop)
			_box(ci, tr, Color(color, 0.95 * alpha), 19.0)
			_text(ci, tr.get_center(), text, 22, Color(1, 1, 1, alpha), tr.size.x - 18.0)
		_rects["player_%d" % (side + 1)] = rect


## 下の真ん中に小さく：P1 W A S D、P2 ↑ ← ↓ → で動く。
func _paint_keys(ci: Control, alpha: float) -> void:
	var key_sets := [["W", "A", "S", "D"], ["↑", "←", "↓", "→"]]
	var chip_w := 40.0
	var key_w := 28.0
	var gap := 4.0
	var label := _t("move")
	var label_w := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var w := 14.0 + 2.0 * (chip_w + 6.0 + 4.0 * (key_w + gap)) + 18.0 + label_w + 16.0
	var rect := Rect2(Vector2(640.0 - w * 0.5, 676.0), Vector2(w, 34.0))
	_box(ci, rect, Color(DARK, DARK.a * 0.85 * alpha), 17.0)
	var x := rect.position.x + 14.0
	for side: int in [0, 1]:
		var chip := Rect2(x, rect.position.y + 5.0, chip_w, 24.0)
		_box(ci, chip, Color(PLAYER_COLORS[side], alpha), 8.0)
		_text(ci, chip.get_center(), "P%d" % (side + 1), 15, Color(1, 1, 1, alpha))
		x += chip_w + 6.0
		for label_key: String in key_sets[side]:
			var key_rect := Rect2(x, rect.position.y + 5.0, key_w, 24.0)
			_box(ci, key_rect, Color(1, 1, 1, 0.95 * alpha), 6.0)
			_text(ci, key_rect.get_center(), label_key, 15, Color(INK, alpha))
			x += key_w + gap
		x += 9.0
	_text_left(ci, Vector2(x + 2.0, rect.get_center().y), label, 16, Color(1, 1, 1, alpha))
	_rects["keys"] = rect


## 大きな見出し（「ROUND 2」と小さな説明）。
func _paint_banner(ci: Control, alpha: float) -> void:
	var data: Dictionary = state.get("banner", {})
	if data.is_empty():
		data = _last.get("banner", {})
	var text := str(data.get("text", ""))
	if text == "":
		return
	var sub := str(data.get("sub", ""))
	var color: Color = data.get("color", INK)
	var t := _clock - _banner_since
	var pop := _back_out(t / 0.35)
	var center := Vector2(640.0, 196.0)
	var size := 64
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 80.0
	var rect := Rect2(center - Vector2(w * 0.5, 52.0), Vector2(w, 104.0))
	rect = Rect2(rect.get_center() - rect.size * 0.5 * pop, rect.size * pop)
	_shadow(ci, rect, alpha, 28.0)
	_box(ci, rect, Color(1, 1, 1, 0.96 * alpha), 28.0, Color(color, alpha), 5.0)
	if pop > 0.6:
		_text(ci, rect.get_center(), text, size, Color(color, alpha), rect.size.x - 30.0)
	if sub != "":
		var sub_rect := _paint_pill(ci, Vector2(640.0, rect.end.y + 26.0), sub, INK, 18, alpha * clampf((t - 0.15) / 0.2, 0.0, 1.0))
		_rects["banner_sub"] = sub_rect
	_rects["banner"] = rect


## 小さな知らせ（「ボードが動く！」「早い者勝ち！」）。ROUND の札の下。
func _paint_notice(ci: Control, alpha: float) -> void:
	var data: Dictionary = state.get("notice", {})
	if data.is_empty():
		data = _last.get("notice", {})
	var text := str(data.get("text", ""))
	if text == "":
		return
	var pop := _back_out((_clock - _notice_since) / 0.3)
	var color: Color = data.get("color", AMBER)
	var rect := _paint_pill(ci, Vector2(640.0, 114.0 + (1.0 - pop) * -10.0), text, color, 20, alpha)
	_rects["notice"] = rect


func _paint_rules(ci: Control, alpha: float) -> void:
	var dim := Color(0.04, 0.06, 0.11, 0.55 * alpha)
	ci.draw_rect(Rect2(Vector2(-2000, -2000), Vector2(6000, 6000)), dim)
	var t := _clock - _rules_since
	var card := Rect2(90.0, 56.0, 1100.0, 608.0)
	var pop := _ease_out(t / 0.3)
	card.position.y += (1.0 - pop) * 30.0
	_box(ci, card, Color(0.98, 0.98, 0.99, 0.97 * alpha), 30.0)
	_text(ci, card.position + Vector2(550, 46), _t("rules"), 38, Color(INK, alpha))
	var pw := 320.0
	var ph := 240.0
	var gap := 36.0
	var x0 := card.position.x + (card.size.x - (pw * 3 + gap * 2)) * 0.5
	var colors := [PLAYER_COLORS[0], GOOD, BAD]
	for i in range(3):
		var k := clampf((t - 0.12 * i) / 0.35, 0.0, 1.0)
		var back := _back_out(k)
		var y := card.position.y + 84.0 + (1.0 - back) * 30.0
		var x := x0 + i * (pw + gap)
		var a := alpha * k
		var image_rect := Rect2(x, y, pw, ph)
		_box(ci, Rect2(image_rect.position + Vector2(0, 5), image_rect.size), Color(0.05, 0.08, 0.14, 0.16 * a), IMAGE_RADIUS)
		if i < _images.size() and _images[i] != null:
			_rounded_image(ci, _images[i], image_rect, IMAGE_RADIUS, a)
		else:
			_box(ci, image_rect, Color(0.55, 0.72, 0.9, a), IMAGE_RADIUS)
		_box(ci, image_rect.grow(IMAGE_BORDER), Color(0, 0, 0, 0), IMAGE_RADIUS + IMAGE_BORDER, Color(1, 1, 1, a), IMAGE_BORDER)
		var badge := Rect2(x + 12, y + 12, 46, 46)
		_box(ci, badge, Color(colors[i], a), 23.0)
		_text(ci, badge.get_center(), str(i + 1), 26, Color(1, 1, 1, a))
		var lines := _t("r%d" % (i + 1)).split("\n")
		for l in range(lines.size()):
			_text(ci, Vector2(x + pw * 0.5, y + ph + 34 + l * 34), lines[l], 25, Color(INK, a), pw + 20)
		_text(ci, Vector2(x + pw * 0.5, y + ph + 34 + lines.size() * 34 + 4), _t("r%ds" % (i + 1)), 18, Color(MUTED, a), pw + 20)
	var strip := Rect2(card.position.x + 36, card.end.y - 104, card.size.x - 72, 62)
	_box(ci, strip, Color(0.925, 0.937, 0.961, alpha), 16.0)
	_text(ci, strip.get_center(), _t("rule_bottom"), 22, Color(INK, alpha), strip.size.x - 40.0)
	if bool(state.get("rules_prompt", false)):
		var blink := 0.65 + 0.35 * sin(t * 5.0)
		_paint_pill(ci, Vector2(card.end.x - 150.0, card.position.y + 46.0), _t("enter"), INK, 20, alpha * blink)
	_rects["rules"] = card


## 絵を角の丸い四角に切り抜いて描く。
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


## 勝者のダンスの間：下の真ん中に小さく「[1][2][3] キーでエモート」（P2 は 8・9・0）。
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
		_box(ci, r, Color(color, alpha), 8.0, Color(1, 1, 1, alpha), 3.0 if playing == i else 0.0)
		_text(ci, r.get_center(), keys[i], 18, Color(1, 1, 1, alpha))
		x += chip + gap
	_text_left(ci, Vector2(x + 4.0, rect.position.y + 20.0), label, size, Color(1, 1, 1, alpha))
	_rects["emote"] = rect
