extends CanvasLayer

## スマホ専用：Enter で閉じるカード（サドンデスのルールカード、ゴーストシャークの溜めの説明など）を
## タップで閉じるための透明な層。画面のどこをタップしても、下の大きなボタンを押しても同じ。
##
## 持ち主（監督）が2つの Callable を渡す：
##   waiting.call() -> bool … いまカードが出て、閉じるのを待っているか（毎フレーム見る）
##   confirm.call() -> Variant … 閉じる（キーの Enter と同じ口。読む時間の下限は持ち主が守る）
## デスクトップでは作らない（持ち主が is_touch() のときだけ new する）。

const TouchHud = preload("res://scripts/ui/touch_hud/touch_hud.gd")
const MobileUi = preload("res://scripts/core/mobile_ui.gd")

## サドンデスの HUD（7〜8）より上、ポーズ画面より下。
const LAYER := 9
const BUTTON_MARGIN_BOTTOM := 36.0

var _waiting: Callable
var _confirm: Callable
var _root: Control
var _catcher: Button
var _button: Button


func setup(waiting: Callable, confirm: Callable, label: String = "▶ タップでスタート") -> void:
	_waiting = waiting
	_confirm = confirm
	layer = LAYER
	# ポーズ中はタップを受けない（ポーズの画面が先）。
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_root = Control.new()
	_root.name = "TapToConfirm"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_catcher = TouchHud.make_tap_catcher()
	_catcher.name = "TapCatcher"
	_catcher.pressed.connect(_on_pressed)
	_root.add_child(_catcher)
	_button = TouchHud.make_button(label, 24)
	_button.name = "ConfirmButton"
	_button.custom_minimum_size = Vector2(MobileUi.MIN_TOUCH_SIZE * 4.0, MobileUi.MIN_TOUCH_SIZE)
	_button.pressed.connect(_on_pressed)
	# 出すかどうかは _process が毎フレーム決める（TouchControls の「OK」と同じフレームに出さない）。
	_button.visible = false
	_root.add_child(_button)
	TouchHud.on_safe_area_changed(_layout)
	_layout()
	_root.visible = false


func _layout() -> void:
	if _button == null:
		return
	_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var width := _button.custom_minimum_size.x
	_button.offset_left = -width * 0.5
	_button.offset_right = width * 0.5
	_button.offset_bottom = -BUTTON_MARGIN_BOTTOM - TouchHud.safe_bottom()
	_button.offset_top = _button.offset_bottom - _button.custom_minimum_size.y


func _process(_delta: float) -> void:
	if _root == null:
		return
	var waiting_now := _waiting.is_valid() and bool(_waiting.call())
	if _root.visible != waiting_now:
		_root.visible = waiting_now
	# 画面のタッチ操作の層が同じ働きの「OK」（Enter）を出しているときは、下のボタンを重ねない（どこをタップしても閉じるのは同じ）。
	# 同じフレームに両方は出さない（own_button_allowed は、TouchControls が出していないのを2フレーム見てから許す）。
	_button.visible = TouchHud.own_button_allowed(_button, "ConfirmButton", waiting_now)


func _on_pressed() -> void:
	if not _root.visible or not _confirm.is_valid():
		return
	_confirm.call()
	if _waiting.is_valid() and not bool(_waiting.call()):
		_root.visible = false
