class_name OnlineHomePage
extends OnlineMenuPage

const MobileUi = preload("res://scripts/core/mobile_ui.gd")

## オンラインメニューのトップ。なまえ（入力かサイコロの二つ名）と、あそぶ問題の
## せってい（教科・学年・むずかしさ）を決めて、ランダムマッチか ともだちと あそぶ へ進む。
## メインメニューの設定画面を通らずに来るので、せっていはここで選べるようにしている。

var _name_input: LineEdit
var _name_hint: Label
var _dice: DiceButton
var _find_button: Button
var _friend_button: Button
var _values: Dictionary = {}  # &"subject" / &"grade" / &"difficulty" -> Label
## 「あそぶ もんだい」のカードと、きょうか・がくねん・むずかしさの行（練習のコーチが光らせる）
var _rule_card: Control
var _rows: Dictionary = {}  # &"subject" / &"grade" / &"difficulty" -> HBoxContainer


func _ready() -> void:
	var name_card := OnlineMenuStyle.card(self)
	OnlineMenuStyle.section(name_card, "あなたの なまえ", "サイコロで 二つ名")
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 10)
	name_card.add_child(name_row)
	_name_input = OnlineMenuStyle.line_edit("なまえ", NetNameFilter.MAX_LENGTH, Vector2(400, 60), 28)
	_name_input.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_input)
	_dice = DiceButton.new()
	_dice.custom_minimum_size = Vector2(60, 60)
	MobileUi.ensure_touch_size(_dice)
	_dice.pressed.connect(roll_name)
	name_row.add_child(_dice)
	_name_hint = OnlineMenuStyle.wrap_label("", MobileUi.font(15), OnlineMenuStyle.WARN)
	name_card.add_child(_name_hint)

	var rule_card := OnlineMenuStyle.card(self, 8)
	_rule_card = rule_card.get_parent()
	OnlineMenuStyle.section(rule_card, "あそぶ もんだい")
	_add_stepper(rule_card, &"subject", "きょうか")
	_add_stepper(rule_card, &"grade", "がくねん")
	_add_stepper(rule_card, &"difficulty", "むずかしさ")

	add_child(OnlineMenuStyle.spacer(4))
	_find_button = OnlineMenuStyle.button("ランダムマッチ", Vector2(0, 72), 26, true)
	_find_button.pressed.connect(func() -> void: request(&"find"))
	_friend_button = OnlineMenuStyle.button("ともだちと あそぶ", Vector2(0, 52), 20)
	_friend_button.pressed.connect(func() -> void: request(&"friend"))
	if MobileUi.is_touch_ui():
		# スマホ：指の大きさのボタンを縦に 2 つ積むと 720 の高さに収まらないので、横に並べる
		var actions := HBoxContainer.new()
		actions.name = "Actions"
		actions.add_theme_constant_override("separation", 12)
		add_child(actions)
		for button: Button in [_find_button, _friend_button]:
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			actions.add_child(button)
		_find_button.size_flags_stretch_ratio = 1.3
	else:
		add_child(_find_button)
		add_child(_friend_button)


func enter(_args: Dictionary) -> void:
	if _name_input.text != GameManager.online_name:
		_name_input.text = GameManager.online_name
	_validate_name(_name_input.text)
	_refresh_settings()


func default_focus() -> Control:
	return _find_button if not _find_button.disabled else _name_input


## 練習の形で、画面のコーチが光らせる部品（docs/new_tutorial/phase7_design.md 1.1）。なければ null。
##   &"name_field"・&"name_dice"・&"quiz_box"（あそぶ もんだい）・&"subject"・&"grade"・&"difficulty"・&"random_match"・&"friends"
func practice_part(id: StringName) -> Control:
	match id:
		&"name_field":
			return _name_input
		&"name_dice":
			return _dice
		&"quiz_box":
			return _rule_card
		&"subject", &"grade", &"difficulty":
			return _rows.get(id) as Control
		&"random_match":
			return _find_button
		&"friends":
			return _friend_button
	return null


## サイコロ: 新しい二つ名をすぐ入れる（動きは付けない）。
func roll_name() -> void:
	_name_input.text = NetEpithets.roll()
	_name_input.caret_column = _name_input.text.length()
	_on_name_changed(_name_input.text)


func _add_stepper(parent: Control, key: StringName, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	_rows[key] = row
	var name_label := OnlineMenuStyle.label(title, MobileUi.font(18), OnlineMenuStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_label)
	var prev := OnlineMenuStyle.arrow_button("◀")
	prev.pressed.connect(_shift.bind(key, -1))
	row.add_child(prev)
	var value := OnlineMenuStyle.readout(row, 22)
	var next := OnlineMenuStyle.arrow_button("▶")
	next.pressed.connect(_shift.bind(key, 1))
	row.add_child(next)
	_values[key] = value


func _shift(key: StringName, direction: int) -> void:
	var game_state := QuizManager.game_state
	match key:
		&"subject":
			game_state.cycle_subject(direction)
		&"grade":
			game_state.update_grade(direction)
		&"difficulty":
			game_state.cycle_difficulty(direction)
	_refresh_settings()


func _refresh_settings() -> void:
	var game_state := QuizManager.game_state
	game_state.grade = Constants.normalize_grade_for_subject(game_state.subject, game_state.grade)
	(_values[&"subject"] as Label).text = game_state.subject
	(_values[&"grade"] as Label).text = "%d年生" % game_state.grade
	(_values[&"difficulty"] as Label).text = game_state.difficulty


func _on_name_changed(text: String) -> void:
	if _validate_name(text):
		GameManager.set_online_name(NetNameFilter.normalize(text))


## 入力中のなまえを検査し、理由を出して、使えないあいだは対戦ボタンを止める。
func _validate_name(text: String) -> bool:
	var result := NetNameFilter.check(text)
	var ok := result == NetNameFilter.Result.OK
	_name_hint.text = NetNameFilter.message(result)
	_name_hint.visible = not _name_hint.text.is_empty()
	_find_button.disabled = not ok
	_friend_button.disabled = not ok
	return ok
