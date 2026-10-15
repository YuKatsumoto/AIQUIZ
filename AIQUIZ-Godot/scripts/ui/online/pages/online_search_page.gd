class_name OnlineSearchPage
extends OnlineMenuPage

## あいてを さがしているあいだ（検索中の飛行 S5 の下の帯。D7）。20 秒たつとリレーが条件を広げる。
## ともだちコードで待つときは、帯にコードを大きく出す（enter({"code": ...}) か show_code）。

const WIDEN_AFTER_S := 20.0

var _elapsed := 0.0
var _clock: Label
var _hint: Label
var _code_row: HBoxContainer
var _code_label: Label
var _cancel: Button
var _friend := false


func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var card := OnlineMenuStyle.card(self, 6)
	card.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	row.add_child(texts)
	_code_row = HBoxContainer.new()
	_code_row.add_theme_constant_override("separation", 14)
	texts.add_child(_code_row)
	_code_row.add_child(OnlineMenuStyle.label("この コードを ともだちに おしえてね：", 20, OnlineMenuStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	_code_label = OnlineMenuStyle.label("-----", 40, OnlineMenuStyle.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	_code_row.add_child(_code_label)
	_clock = OnlineMenuStyle.label("", 24, OnlineMenuStyle.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	texts.add_child(_clock)
	_hint = OnlineMenuStyle.label("おなじ 学年の ほかの 教科の 人とも さがしています", 15, OnlineMenuStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	texts.add_child(_hint)
	_cancel = OnlineMenuStyle.button("やめる", Vector2(150, 52), 20)
	_cancel.pressed.connect(func() -> void: request(&"cancel"))
	row.add_child(_cancel)


func page_title() -> String:
	return "ともだちと あそぶ" if _friend else "ランダムマッチ"


func wide_layout() -> bool:
	return true


## args: code（ともだちコードで待つとき。"" ならまだ届いていない）, friend（true ならコードの行を出す）
func enter(args: Dictionary) -> void:
	_elapsed = 0.0
	_friend = bool(args.get("friend", false))
	_code_row.visible = _friend
	show_code(str(args.get("code", "")))
	_refresh()


func show_code(code: String) -> void:
	_code_label.text = code if not code.is_empty() else "-----"


func handle_back() -> bool:
	request(&"cancel")
	return true


func default_focus() -> Control:
	return _cancel


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_elapsed += dt
	_refresh()


func _refresh() -> void:
	var wait := "ともだちを まっています…" if _friend else "あいてを さがしています…"
	_clock.text = "%s  %d:%02d" % [wait, int(_elapsed) / 60, int(_elapsed) % 60]
	_hint.visible = not _friend and _elapsed >= WIDEN_AFTER_S
