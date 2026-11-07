class_name OnlineFriendPage
extends OnlineMenuPage

## ともだちと 5 文字のコードで あそぶ。コードを つくる（まつ側）か、いれる（はいる側）。
## つくったコードは、乗り込みの演出のあと検索中の下の帯（OnlineSearchPage）に大きく出す。

enum Mode { CHOOSE, JOIN }

const CODE_LENGTH := 5
const MobileUi = preload("res://scripts/core/mobile_ui.gd")

var _mode: Mode = Mode.CHOOSE
var _boxes: Dictionary = {}  # Mode -> Control
var _code_input: LineEdit
var _create_button: Button
var _join_button: Button
var _to_join_button: Button


func _ready() -> void:
	var choose := OnlineMenuStyle.card(self, 12)
	OnlineMenuStyle.section(choose, "ともだちと コードで あそぼう")
	_create_button = OnlineMenuStyle.button("コードを つくる", Vector2(0, 56), 22)
	_create_button.pressed.connect(func() -> void: request(&"friend_create"))
	choose.add_child(_create_button)
	var to_join := OnlineMenuStyle.button("コードを いれる", Vector2(0, 56), 22)
	to_join.pressed.connect(func() -> void: _set_mode(Mode.JOIN))
	choose.add_child(to_join)
	_to_join_button = to_join
	_boxes[Mode.CHOOSE] = choose.get_parent()

	var join := OnlineMenuStyle.card(self, 12)
	OnlineMenuStyle.section(join, "ともだちの コード", "%dもじ" % CODE_LENGTH)
	_code_input = OnlineMenuStyle.line_edit("ABCDE", CODE_LENGTH, Vector2(0, 60), 32)
	# 英字のコードなので、かな入力や予測変換の出ない英数字のキーボードを出す（大文字は _on_code_changed で直す）
	_code_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
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


## 練習の形で、画面のコーチが光らせる部品（docs/new_tutorial/phase7_design.md 1.1）。なければ null。
##   &"code_make"（コードを つくる）・&"code_enter"（コードを いれる）・&"code_field"（ともだちの コードの欄。いれる側のときだけ見える）
func practice_part(id: StringName) -> Control:
	match id:
		&"code_make":
			return _create_button
		&"code_enter":
			return _to_join_button
		&"code_field":
			return _code_input
	return null


## 練習の形で、コードの欄（いれる側）を見せる・選ぶ側へ戻す（押さずに見せるだけ）。
func practice_show_join(on: bool) -> void:
	_set_mode(Mode.JOIN if on else Mode.CHOOSE)


func _set_mode(mode: Mode) -> void:
	_mode = mode
	for key in _boxes:
		(_boxes[key] as Control).visible = key == mode
	if mode == Mode.JOIN:
		_code_input.text = ""
	var focus := default_focus()
	# タッチでは、コードの欄（ソフトキーボードを出す）だけにフォーカスを当てる
	if focus != null and is_visible_in_tree() and (not MobileUi.is_touch_ui() or focus == _code_input):
		focus.grab_focus.call_deferred()


func _on_code_changed(text: String) -> void:
	var fixed := normalize_code(text)
	if fixed != text:
		var caret := mini(_code_input.caret_column, fixed.length())
		_code_input.text = fixed
		_code_input.caret_column = caret


func _submit_code() -> void:
	var code := normalize_code(_code_input.text)
	request(&"friend_join", {"code": code})


## 日本語入力が ON のまま打った全角の英数字（Ｋ７ＸＱＭ）を半角に直し、空白（全角の空白も）を取り、大文字にする。
## 直さないと 5 文字のまま送られ、サーバーで「その コードの へやは みつかりません」になる。
static func normalize_code(text: String) -> String:
	var out := ""
	for ch: String in text:
		var code := ch.unicode_at(0)
		if code >= 0xFF01 and code <= 0xFF5E:
			code -= 0xFEE0
		if code == 0x20 or code == 0x3000 or code == 0x09:
			continue
		out += String.chr(code)
	return out.to_upper()


## コードに使える文字（半角の英字と数字）だけか。かな（日本語入力で母音を打つと「あ」などになる）は false。
static func is_code_text(code: String) -> bool:
	for ch: String in code:
		var c := ch.unicode_at(0)
		if not ((c >= 0x41 and c <= 0x5A) or (c >= 0x30 and c <= 0x39)):
			return false
	return true
