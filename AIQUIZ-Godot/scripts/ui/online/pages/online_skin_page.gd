class_name OnlineSkinPage
extends OnlineMenuPage

## 「スキン設定」：右に立っている自分のキャラを見ながら、帽子と体の色をその場で変える。
## 色の編集はカスタマイズ画面と同じ SkinEditor で、相手に見える自分の見た目（このPCのプレイヤー1）を変える。
## 変えた見た目はすぐ保存する。3D のキャラへの反映は OnlineMenu に頼む
## （skin_look：体の色、skin_hat：帽子、skin_part：選んだパーツを光らせる、skin_hover：人型マップで指したパーツを
## うすく光らせる、skin_done：トップへ戻る）。右の 3D のキャラをクリックしてパーツを選ぶのも OnlineMenu が受け持ち、
## editor.select_part を呼ぶ。

const PLAYER := 1

var editor: SkinEditor
var _hat_label: Label
var _hat_prev: Button
var _hat_next: Button
var _done_button: Button


func _ready() -> void:
	var hat_card := OnlineMenuStyle.card(self, 6)
	var hat_row := HBoxContainer.new()
	hat_row.name = "HatRow"
	hat_row.add_theme_constant_override("separation", 10)
	hat_card.add_child(hat_row)
	var caption := OnlineMenuStyle.label("ぼうし", 18, OnlineMenuStyle.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	caption.custom_minimum_size = Vector2(90, 0)
	hat_row.add_child(caption)
	_hat_prev = OnlineMenuStyle.arrow_button("◀")
	_hat_prev.tooltip_text = "前のぼうし"
	_hat_prev.pressed.connect(_step_hat.bind(-1))
	hat_row.add_child(_hat_prev)
	_hat_label = OnlineMenuStyle.readout(hat_row, 22)
	_hat_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hat_next = OnlineMenuStyle.arrow_button("▶")
	_hat_next.tooltip_text = "次のぼうし"
	_hat_next.pressed.connect(_step_hat.bind(1))
	hat_row.add_child(_hat_next)

	# ① ぬるところ（左）と ② 色（右）を横に並べ、その下にツールバー
	var color_card := OnlineMenuStyle.card(self, 10)
	var columns := HBoxContainer.new()
	columns.name = "SkinColumns"
	columns.add_theme_constant_override("separation", 14)
	color_card.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(160, 0)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	editor = SkinEditor.new()
	add_child(editor)
	editor.build_left(left, false)
	var pick_hint := SkinUiStyle.label("キャラを クリックしても\nえらべるよ", 12, SkinUiStyle.MUTED)
	pick_hint.name = "PickHint"
	left.add_child(pick_hint)
	editor.build_right(right, 20.0)
	var toolbar := HBoxContainer.new()
	toolbar.name = "SkinToolbar"
	color_card.add_child(toolbar)
	editor.build_toolbar(toolbar, false)
	editor.look_changed.connect(func(_slot: int, skin: Dictionary) -> void: request(&"skin_look", {"skin": skin}))
	editor.part_selected.connect(func(_slot: int, part_id: StringName) -> void: request(&"skin_part", {"part": part_id}))
	editor.part_hovered.connect(func(_slot: int, part_id: StringName) -> void: request(&"skin_hover", {"part": part_id}))
	editor.hat_restore_requested.connect(func(_slot: int, hat_id: int) -> void: _apply_hat(hat_id))

	_done_button = OnlineMenuStyle.button("✓ けってい", Vector2(0, 56), 22, true)
	_done_button.tooltip_text = "この見た目で トップにもどります（もう ほぞんしてあります）"
	_done_button.pressed.connect(func() -> void: request(&"skin_done"))
	add_child(_done_button)


func page_title() -> String:
	return "スキン設定"


func enter(_args: Dictionary) -> void:
	editor.target = PlayerSkin.ALL
	editor.set_editing_player(PLAYER)
	_hat_label.text = HatData.get_hat_name(QuizManager.game_state.p1_hat)


func leave() -> void:
	editor.history.break_coalescing(PLAYER)
	PlayerSkinStore.flush()


func default_focus() -> Control:
	var chain := editor.focus_chain()
	return chain[0] if not chain.is_empty() else _done_button


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and editor.handle_shortcut(event):
		get_viewport().set_input_as_handled()


func _step_hat(direction: int) -> void:
	var old_hat := QuizManager.game_state.p1_hat
	var hat := HatData.step_hat(old_hat, direction)
	if hat == old_hat:
		return
	editor.record_hat_change(PLAYER, old_hat)
	_apply_hat(hat)


func _apply_hat(hat_id: int) -> void:
	QuizManager.game_state.p1_hat = hat_id
	PlayerSkinStore.set_hat(PLAYER, hat_id)
	_hat_label.text = HatData.get_hat_name(hat_id)
	request(&"skin_hat", {"hat": hat_id})
