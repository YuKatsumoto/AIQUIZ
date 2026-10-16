class_name OnlineFriendPage
extends OnlineMenuPage

## ともだちと 5 文字のコードで あそぶ。コードを つくる（まつ側）か、いれる（はいる側）。
## つくったコードは、乗り込みの演出のあと検索中の下の帯（OnlineSearchPage）に大きく出す。

enum Mode { CHOOSE, JOIN }

const CODE_LENGTH := 5

var _mode: Mode = Mode.CHOOSE
var _boxes: Dictionary = {}  # Mode -> Control
var _code_input: LineEdit
var _create_button: Button
var _join_button: Button


func _ready() -> void:
	var choose := OnlineMenuStyle.card(self, 12)
	OnlineMenuStyle.section(choose, "ともだちと コードで あそぼう")
	_create_button = OnlineMenuStyle.button("コードを つくる", Vector2(0, 56), 22)
	_create_button.pressed.connect(func() -> void: request(&"friend_create"))
	choose.add_child(_create_button)
	var to_join := OnlineMenuStyle.button("コードを いれる", Vector2(0, 56), 22)
	to_join.pressed.connect(func() -> void: _set_mode(Mode.JOIN))
	choose.add_child(to_join)
	_boxes[Mode.CHOOSE] = choose.get_parent()

	var join := OnlineMenuStyle.card(self, 12)
	OnlineMenuStyle.section(join, "ともだちの コード", "%dもじ" % CODE_LENGTH)
	_code_input = OnlineMenuStyle.line_edit("ABCDE", CODE_LENGTH, Vector2(0, 60), 32)
	_code_input.text_changed.connect(_on_code_changed)
	_code_input.text_submitted.connect(func(_text: String) -> void: _submit_code())
	join.add_child(_code_input)
	_join_button = OnlineMenuStyle.button("さんかする", Vector2(0, 56), 22, true)
	_join_button.pressed.connect(_submit_code)
	join.add_child(_join_button)
	_boxes[Mode.JOIN] = join.get_parent()


func page_title() -> String:
	return "ともだちと あそぶ"


func enter(_args: Dictionary) -> void:
	_set_mode(Mode.CHOOSE)


func handle_back() -> bool:
	match _mode:
		Mode.JOIN:
			_set_mode(Mode.CHOOSE)
			return true
	return false


func default_focus() -> Control:
	if _mode == Mode.JOIN:
		return _code_input
	return _create_button


func _set_mode(mode: Mode) -> void:
	_mode = mode
	for key in _boxes:
		(_boxes[key] as Control).visible = key == mode
	if mode == Mode.JOIN:
		_code_input.text = ""
	var focus := default_focus()
	if focus != null and is_visible_in_tree():
		focus.grab_focus.call_deferred()


func _on_code_changed(text: String) -> void:
	var upper := text.to_upper()
	if upper != text:
		var caret := _code_input.caret_column
		_code_input.text = upper
		_code_input.caret_column = caret


func _submit_code() -> void:
	var code := _code_input.text.strip_edges().to_upper()
	request(&"friend_join", {"code": code})
