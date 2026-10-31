extends RefCounted

## 3D プレビュー（カスタマイズのキャラ・エモート）を指で回す・拡大縮小するための読み取り役。
## 1 本指のドラッグ → 回転量（画面の px）、2 本指の間の広がり（ピンチ）→ 拡大率。
## タッチ画面のない環境（--mobile-preview のデスクトップ）では、左ドラッグを 1 本指として扱う。
## 呼ぶ側は gui_input で feed() に渡し、返り値の rotate / zoom をカメラに足す。
##
## Use: const PreviewTouchGestures = preload("res://scripts/ui/mobile/preview_touch_gestures.gd")
##      var _gestures := PreviewTouchGestures.new()
##      var g := _gestures.feed(event)   # {"rotate": Vector2, "zoom": float (>1 で指が広がった), "handled": bool}

var _touches: Dictionary = {}  # index -> Vector2
var _pinch_distance := 0.0
var _mouse_dragging := false


func feed(event: InputEvent) -> Dictionary:
	var result := {"rotate": Vector2.ZERO, "zoom": 1.0, "handled": false}
	var touchscreen := DisplayServer.is_touchscreen_available()
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		_pinch_distance = _spread()
		result.handled = true
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _touches.size() == 1:
			result.rotate = drag.relative
		elif _touches.size() >= 2:
			var spread := _spread()
			if _pinch_distance > 1.0 and spread > 1.0:
				result.zoom = spread / _pinch_distance
			_pinch_distance = spread
		result.handled = true
	elif event is InputEventMagnifyGesture:
		# 2 本指の追跡でピンチを取っているときは、OS のピンチ（同じ動き）を二重に足さない
		if _touches.size() < 2:
			result.zoom = (event as InputEventMagnifyGesture).factor
			result.handled = true
	elif not touchscreen:
		# デスクトップのプレビュー：左ドラッグ ＝ 1 本指（タッチ画面では指がマウスにも化けるので使わない）
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_mouse_dragging = (event as InputEventMouseButton).pressed
		elif event is InputEventMouseMotion and _mouse_dragging:
			result.rotate = (event as InputEventMouseMotion).relative
			result.handled = true
	return result


## 指がすべて離れた扱いにする（タブの切り替え・画面を閉じたとき）。
func reset() -> void:
	_touches.clear()
	_pinch_distance = 0.0
	_mouse_dragging = false


func is_pinching() -> bool:
	return _touches.size() >= 2


func _spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)
