class_name OnlineMenuPage
extends VBoxContainer

## オンライン専用メニューの 1 ページ。ページは見た目と入力だけを持ち、通信や
## 画面の行き来は action_requested で OnlineMenu に頼む（ページ同士は直接さわらない）。
## 新しいページの足し方は docs/online_menu.md を参照。

signal action_requested(action: StringName, data: Dictionary)


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## ヘッダーに出す見出し。
func page_title() -> String:
	return "オンライン対戦"


## ページが表に出たとき。args は OnlineMenu.go() に渡したもの。
func enter(_args: Dictionary) -> void:
	pass


## ページが裏に回るとき。
func leave() -> void:
	pass


## もどる（Esc / ←）を自分で処理したら true。false ならひとつ前のページへ戻る。
func handle_back() -> bool:
	return false


## true なら画面の下のまん中の帯に置く（3D の背景を大きく見せたいページ。VS）。ふだんは左の列。
func wide_layout() -> bool:
	return false


## 最初にフォーカスを当てるコントロール（キーボード操作用）。
func default_focus() -> Control:
	return null


func request(action: StringName, data: Dictionary = {}) -> void:
	action_requested.emit(action, data)
