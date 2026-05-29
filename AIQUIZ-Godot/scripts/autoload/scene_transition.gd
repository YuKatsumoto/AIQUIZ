extends CanvasLayer

## シーン遷移アニメーション (Autoload)
## フェード / ドア・ワイプ でシーン切り替えを管理する

var _overlay: ColorRect
var _door_left: ColorRect
var _door_right: ColorRect
var _is_transitioning: bool = false
var _active_style: String = ""
var _door_seam_x: float = 0.0
var _door_color: Color = Color(0.18, 0.36, 0.62, 1.0)

const FADE_DURATION := 0.45
const DOOR_DURATION := 0.5
const ACCENT_BLUE := Color(0.18, 0.36, 0.62, 1.0)

func _ready() -> void:
	layer = 100  # Always on top
	process_mode = Node.PROCESS_MODE_ALWAYS

	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	_door_left = ColorRect.new()
	_door_left.visible = false
	_door_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_door_left)

	_door_right = ColorRect.new()
	_door_right.visible = false
	_door_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_door_right)

## シーン切り替え (フェードアウト → 切替 → フェードイン)
func change_scene(path: String, fade_color: Color = Color.BLACK) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_active_style = "fade"
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	tween.tween_property(_overlay, "color:a", 1.0, FADE_DURATION)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(path)
	)

## ドア・ワイプでシーン切り替え (左右パネルが seam から広がって画面を覆う)
func change_scene_doors(path: String, seam_x: float = -1.0, color: Color = ACCENT_BLUE) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_active_style = "doors"
	_door_color = color

	var vp := get_viewport().get_visible_rect().size
	if seam_x < 0.0:
		seam_x = vp.x * 0.5
	_door_seam_x = seam_x

	_hide_doors()
	_door_left.color = color
	_door_right.color = color
	_door_left.visible = true
	_door_right.visible = true
	_door_left.mouse_filter = Control.MOUSE_FILTER_STOP
	_door_right.mouse_filter = Control.MOUSE_FILTER_STOP

	# 左ドア: 右端を seam_x に固定し左へ伸長
	_door_left.position = Vector2(seam_x, 0.0)
	_door_left.size = Vector2(0.0, vp.y)
	# 右ドア: 左端を seam_x に固定し右へ伸長
	_door_right.position = Vector2(seam_x, 0.0)
	_door_right.size = Vector2(0.0, vp.y)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_door_left, "position:x", 0.0, DOOR_DURATION)
	tw.tween_property(_door_left, "size:x", seam_x, DOOR_DURATION)
	tw.tween_property(_door_right, "size:x", vp.x - seam_x, DOOR_DURATION)
	tw.chain().tween_callback(func():
		get_tree().change_scene_to_file(path)
	)

## シーン読み込み後に遷移演出を解除 (fade / doors 両対応)
func reveal_current(fade_color: Color = Color.BLACK) -> void:
	if not _is_transitioning:
		return
	match _active_style:
		"doors":
			_reveal_doors()
		"fade":
			_fade_in(fade_color)
		_:
			_is_transitioning = false

## フェードインのみ (後方互換)
func fade_in_current(fade_color: Color = Color.BLACK) -> void:
	if _overlay.color.a < 0.01 and not _is_transitioning:
		return
	reveal_current(fade_color)

func _fade_in(fade_color: Color) -> void:
	_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, 1.0)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_overlay, "color:a", 0.0, FADE_DURATION)
	tween.tween_callback(func():
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_transitioning = false
		_active_style = ""
	)

func _reveal_doors() -> void:
	var vp := get_viewport().get_visible_rect().size
	var seam_x := _door_seam_x

	# ドアが閉じた状態に揃える (シーン切替直後)
	_door_left.position = Vector2(0.0, 0.0)
	_door_left.size = Vector2(seam_x, vp.y)
	_door_right.position = Vector2(seam_x, 0.0)
	_door_right.size = Vector2(vp.x - seam_x, vp.y)
	_door_left.color = _door_color
	_door_right.color = _door_color
	_door_left.visible = true
	_door_right.visible = true
	_door_left.mouse_filter = Control.MOUSE_FILTER_STOP
	_door_right.mouse_filter = Control.MOUSE_FILTER_STOP

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_door_left, "position:x", -seam_x, DOOR_DURATION)
	tw.tween_property(_door_right, "position:x", vp.x, DOOR_DURATION)
	tw.chain().tween_callback(func():
		_hide_doors()
		_is_transitioning = false
		_active_style = ""
	)

func _hide_doors() -> void:
	_door_left.visible = false
	_door_right.visible = false
	_door_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_door_right.mouse_filter = Control.MOUSE_FILTER_IGNORE

## 遷移中かどうか
func is_transitioning() -> bool:
	return _is_transitioning
