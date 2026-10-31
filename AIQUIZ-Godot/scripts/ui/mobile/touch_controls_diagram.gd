extends Control

## チュートリアル前の操作紹介（TutorialKeyboardIntro）で、スマホのときにキーボードの絵の代わりに出す図。
## 横持ちの画面の枠に、移動のスティック・ジャンプ・エモート 1〜3・一時停止（Ⅱ）の場所と名前を描く。
## 絵だけで入力は受けない（チュートリアル本編で実際のボタンを使う）。

const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const P1 := Color("ffa440")
const IVORY := Color("f5f1e8")
const MUTED := Color("b4c4d8")
const SCREEN := Color("10203a")
const FRAME := Color("4c647f")
const BUTTON := Color("21344d")
## 画面の枠の縦横比（Z Flip 7 の横持ち 21:9）。
const SCREEN_ASPECT := 21.0 / 9.0

var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock = fmod(_clock + delta, 1000.0)
	queue_redraw()


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	if area.size.x < 10.0 or area.size.y < 10.0:
		return
	# 画面の枠（左右に説明の余白を残す）
	var screen_h := area.size.y * 0.92
	var screen_w := minf(screen_h * SCREEN_ASPECT, area.size.x * 0.5)
	screen_h = screen_w / SCREEN_ASPECT
	var screen := Rect2(Vector2((area.size.x - screen_w) * 0.5, (area.size.y - screen_h) * 0.5), Vector2(screen_w, screen_h))
	var frame := StyleBoxFlat.new()
	frame.bg_color = SCREEN
	frame.border_color = FRAME
	frame.set_border_width_all(4)
	frame.set_corner_radius_all(int(screen_h * 0.12))
	draw_style_box(frame, screen)
	var unit := screen_h / 100.0
	var pulse := 0.5 + 0.5 * sin(_clock * TAU * 0.8)

	# 左下：移動のスティック（つまみがゆっくり回る）
	var stick := screen.position + Vector2(screen.size.x * 0.16, screen.size.y * 0.66)
	var stick_r := 20.0 * unit
	draw_circle(stick, stick_r, Color(BUTTON, 0.95))
	draw_arc(stick, stick_r, 0.0, TAU, 40, Color(P1, 0.7), 3.0, true)
	var knob := stick + Vector2(cos(_clock * 1.6), sin(_clock * 1.6)) * stick_r * 0.45
	draw_circle(knob, stick_r * 0.42, Color(P1, 0.85))
	# 右下：ジャンプ（大）とエモート 1〜3（小）
	var jump := screen.position + Vector2(screen.size.x * 0.86, screen.size.y * 0.70)
	var jump_r := 15.0 * unit
	draw_circle(jump, jump_r, Color(P1, 0.55 + 0.35 * pulse))
	draw_arc(jump, jump_r, 0.0, TAU, 36, IVORY, 2.0, true)
	_text_center(jump, "ジャンプ", int(5.6 * unit), Color("14243b"))
	var emote_r := 7.5 * unit
	for index: int in range(3):
		var angle := deg_to_rad(200.0 + 50.0 * index)
		var center := jump + Vector2(cos(angle), sin(angle)) * (jump_r + emote_r + 5.0 * unit)
		draw_circle(center, emote_r, BUTTON)
		draw_arc(center, emote_r, 0.0, TAU, 24, Color(P1, 0.8), 2.0, true)
		_text_center(center, str(index + 1), int(6.0 * unit), IVORY)
	# 左上：一時停止（TouchControls は SafeArea の左上に置く）
	var pause := screen.position + Vector2(screen.size.x * 0.07, screen.size.y * 0.15)
	draw_circle(pause, 7.0 * unit, BUTTON)
	draw_arc(pause, 7.0 * unit, 0.0, TAU, 24, MUTED, 2.0, true)
	_text_center(pause, "Ⅱ", int(6.5 * unit), IVORY)

	# 説明（枠の外の左右）
	var font_size := int(clampf(6.2 * unit, 14.0, 22.0))
	_callout(stick, Vector2(area.position.x + 4.0, stick.y - 4.0 * unit), "スティック", "いどう（まえ・うしろ・左右）", font_size, false)
	_callout(jump, Vector2(area.end.x - 4.0, jump.y + 6.0 * unit), "ジャンプ", "おしているあいだ ジャンプ", font_size, true)
	var emote_mid := jump + Vector2(cos(deg_to_rad(250.0)), sin(deg_to_rad(250.0))) * (jump_r + emote_r + 5.0 * unit)
	_callout(emote_mid, Vector2(area.end.x - 4.0, emote_mid.y - 10.0 * unit), "エモート 1・2・3", "おどりを おどる", font_size, true)
	_callout(pause, Vector2(area.position.x + 4.0, screen.position.y + 2.0 * unit), "Ⅱ", "いちじ ていし", font_size, false)


## from（図の部品）から説明の文字の位置まで線を引き、見出しと説明を 2 行で書く。right_side なら右寄せ。
func _callout(from: Vector2, at: Vector2, title: String, detail: String, font_size: int, right_side: bool) -> void:
	var title_width := FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var detail_width := FONT.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size * 0.8)).x
	var width := maxf(title_width, detail_width)
	var left := at.x - width if right_side else at.x
	var anchor := Vector2(left if right_side else left + width, at.y + font_size * 0.3)
	draw_line(from, anchor, Color(MUTED, 0.6), 2.0, true)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if right_side else HORIZONTAL_ALIGNMENT_LEFT
	draw_string(FONT, Vector2(left, at.y), title, align, width, font_size, P1)
	draw_string(FONT, Vector2(left, at.y + font_size * 1.2), detail, align, width, int(font_size * 0.8), IVORY)


func _text_center(center: Vector2, text: String, font_size: int, color: Color) -> void:
	font_size = maxi(font_size, 10)
	var text_size := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y - text_size.y * 0.5 + FONT.get_ascent(font_size)
	draw_string(FONT, Vector2(center.x - text_size.x * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
