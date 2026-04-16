extends CanvasLayer

## シーン遷移フェードアニメーション (Autoload)
## 全画面を覆う ColorRect でフェードイン/アウトを管理する

var _overlay: ColorRect
var _is_transitioning: bool = false

const FADE_DURATION := 0.45

func _ready() -> void:
	layer = 100  # Always on top
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

## シーン切り替え (フェードアウト → 切替 → フェードイン)
func change_scene(path: String, fade_color: Color = Color.BLACK) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input during transition
	
	# Fade out (transparent → opaque)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	tween.tween_property(_overlay, "color:a", 1.0, FADE_DURATION)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(path)
		# Fade in is handled by the new scene's _ready() calling fade_in_current()
	)

## フェードインのみ (シーン読み込み後に呼ばれる)
func fade_in_current(fade_color: Color = Color.BLACK) -> void:
	# Only fade in if overlay is actually visible (after a fade-out), otherwise skip
	if _overlay.color.a < 0.01 and not _is_transitioning:
		return
	_fade_in(fade_color)

func _fade_in(fade_color: Color) -> void:
	_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, 1.0)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_overlay, "color:a", 0.0, FADE_DURATION)
	tween.tween_callback(func():
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_is_transitioning = false
	)

## 遷移中かどうか
func is_transitioning() -> bool:
	return _is_transitioning
