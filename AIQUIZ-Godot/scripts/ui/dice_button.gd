class_name DiceButton
extends Button

## 二つ名を振るサイコロのボタン。絵文字に頼らず自前で描く（フォントに左右されない）。
## 動きは付けない。押すとロビーがすぐ新しい二つ名を入れる。

const BODY := Color(0.98, 0.97, 0.93)
const EDGE := Color(0.2, 0.22, 0.3)
const PIP := Color(0.85, 0.18, 0.22)
const PIP_DARK := Color(0.12, 0.13, 0.18)
const PIPS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
	3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
	4: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
	6: [Vector2(0.27, 0.25), Vector2(0.73, 0.25), Vector2(0.27, 0.5), Vector2(0.73, 0.5), Vector2(0.27, 0.75), Vector2(0.73, 0.75)],
}

var face := 5


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "ランダムな 二つ名に する"


func _draw() -> void:
	var side := minf(size.x, size.y) * 0.78
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var box := StyleBoxFlat.new()
	box.bg_color = BODY
	box.border_color = EDGE
	box.set_border_width_all(maxi(2, int(side * 0.06)))
	box.set_corner_radius_all(int(side * 0.2))
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 3
	box.shadow_offset = Vector2(1, 2)
	draw_style_box(box, rect)
	var radius := side * (0.12 if face == 1 else 0.085)
	for p: Vector2 in PIPS[face]:
		draw_circle(rect.position + p * side, radius, PIP if face == 1 else PIP_DARK)
