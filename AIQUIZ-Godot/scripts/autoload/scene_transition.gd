extends CanvasLayer

## シーン遷移アニメーション (Autoload)
## フェード / ドア・ワイプ でシーン切り替えを管理する

var _overlay: ColorRect
var _door_left: ColorRect
var _door_right: ColorRect
var _hold_texture_rect: TextureRect
var _is_transitioning: bool = false
var _active_style: String = ""
var _door_seam_x: float = 0.0
var _door_color: Color = Color(0.18, 0.36, 0.62, 1.0)
var _start_camera_eye: Vector3 = Vector3.ZERO
var _start_camera_look: Vector3 = Vector3.ZERO
var _start_camera_fov: float = 44.0
var _start_camera_h_offset: float = 0.0
var _has_start_camera_pose: bool = false

const FADE_DURATION := 0.45
const HOLD_TEXTURE_REVEAL_DURATION := 0.22
const DOOR_DURATION := 0.5
const ACCENT_BLUE := Color(0.18, 0.36, 0.62, 1.0)
const GAME_BG_COLOR := Color(0.82, 0.85, 0.90, 1.0)

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

	_hold_texture_rect = TextureRect.new()
	_hold_texture_rect.visible = false
	_hold_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hold_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hold_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_hold_texture_rect)

## シーン切替直前の画面を静止画として保持し、読み込み中の空白フレームを隠す
func hold_image_texture(texture: Texture2D) -> void:
	_hide_doors()
	_overlay.color.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_texture_rect.texture = texture
	_hold_texture_rect.modulate.a = 1.0
	_hold_texture_rect.visible = true
	_hold_texture_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_is_transitioning = true
	_active_style = "texture_hold"

## 静止画が取れない場合のフォールバック
func hold_color(color: Color = GAME_BG_COLOR) -> void:
	_clear_texture_hold()
	_hide_doors()
	_overlay.color = color
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_is_transitioning = true
	_active_style = "fade"

## シーン切り替え (フェードアウト → 切替 → フェードイン)
func change_scene(path: String, fade_color: Color = Color.BLACK) -> void:
	if _is_transitioning:
		return
	_clear_texture_hold()
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

## 黒(指定色)へフェードアウトしてから完了。状態は fade のまま保持し、
## 次シーンの reveal_current() でフェードインさせる (change_scene_to_packed 等と併用)
func fade_to_color_and_wait(fade_color: Color = Color.BLACK) -> void:
	_clear_texture_hold()
	_hide_doors()
	_is_transitioning = true
	_active_style = "fade"
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, _overlay.color.a)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_overlay, "color:a", 1.0, FADE_DURATION)
	await tween.finished

## ドア・ワイプでシーン切り替え (左右パネルが seam から広がって画面を覆う)
func change_scene_doors(path: String, seam_x: float = -1.0, color: Color = ACCENT_BLUE) -> void:
	if _is_transitioning:
		return
	_clear_texture_hold()
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
		"texture_hold":
			_reveal_texture_hold()
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

func _reveal_texture_hold() -> void:
	if not _hold_texture_rect.visible:
		_is_transitioning = false
		_active_style = ""
		return
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_hold_texture_rect, "modulate:a", 0.0, HOLD_TEXTURE_REVEAL_DURATION)
	tw.tween_callback(func():
		_clear_texture_hold()
		_is_transitioning = false
		_active_style = ""
	)

func _clear_texture_hold() -> void:
	_hold_texture_rect.visible = false
	_hold_texture_rect.texture = null
	_hold_texture_rect.modulate.a = 1.0
	_hold_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

## 次シーン開始時に使用する開始カメラ姿勢を保存
func set_start_camera_pose(
	eye: Vector3,
	look: Vector3,
	fov: float = 44.0,
	h_offset: float = 0.0,
) -> void:
	_start_camera_eye = eye
	_start_camera_look = look
	_start_camera_fov = fov
	_start_camera_h_offset = h_offset
	_has_start_camera_pose = true

## 保存済み開始カメラ姿勢を取り出す（取り出し時に消費）
func consume_start_camera_pose() -> Dictionary:
	if not _has_start_camera_pose:
		return {}
	_has_start_camera_pose = false
	return {
		"eye": _start_camera_eye,
		"look": _start_camera_look,
		"fov": _start_camera_fov,
		"h_offset": _start_camera_h_offset,
	}

## 遷移中かどうか
func is_transitioning() -> bool:
	return _is_transitioning
