class_name OnlineVersusPage
extends OnlineMenuPage

## あいてが きまったときの VS。画面の下の帯に置き、3D の背景で 2 人が向き合うのを見せる。
## 3D の VS のカメラは手前の立ち位置（自分）を右、奥（あいて）を左に映すので、帯も左＝あいて・右＝じぶん。
## 3D の背景があるときは、相手のヘリが着くまで名前を伏せ、OnlineMenu が reveal() で出す。
## カウントダウンは OnlineMenu が進める。

var _card: Control
var _me: Label
var _them: Label
var _rules: Label
var _info: Label
var _revealed := true


func _ready() -> void:
	var column := OnlineMenuStyle.card(self, 6)
	_card = column.get_parent()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	column.add_child(row)
	_them = OnlineMenuStyle.label("", 28, OnlineMenuStyle.THEM, HORIZONTAL_ALIGNMENT_RIGHT)
	_them.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_them)
	row.add_child(OnlineMenuStyle.label("VS", 44, OnlineMenuStyle.ACCENT))
	_me = OnlineMenuStyle.label("", 28, OnlineMenuStyle.ME, HORIZONTAL_ALIGNMENT_LEFT)
	_me.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_me)
	_rules = OnlineMenuStyle.label("", 16, OnlineMenuStyle.MUTED)
	column.add_child(_rules)
	_info = OnlineMenuStyle.label("", 22)
	OnlineMenuStyle.shadow(_info)
	add_child(_info)


func page_title() -> String:
	return "たいせん"


func wide_layout() -> bool:
	return true


## args: me / them / rules（文字列）、arriving（相手のヘリが着くまで名前を伏せる）
func enter(args: Dictionary) -> void:
	_me.text = "じぶん：" + str(args.get("me", ""))
	_them.text = "あいて：" + str(args.get("them", ""))
	_rules.text = str(args.get("rules", ""))
	_info.text = ""
	_revealed = not bool(args.get("arriving", false))
	_card.visible = _revealed
	_card.modulate.a = 1.0
	_card.scale = Vector2.ONE


## 名前のカードを出す（相手のヘリが着いて、2 人が向き合ったとき）。
func reveal() -> void:
	if _revealed:
		return
	_revealed = true
	_card.visible = true
	_card.modulate.a = 0.0
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.85, 0.85)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_card, "modulate:a", 1.0, 0.25)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_revealed() -> bool:
	return _revealed


## VS カードの下の一行（カウントダウンや待ちの案内）。
func set_info(text: String) -> void:
	_info.text = text
