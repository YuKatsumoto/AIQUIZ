extends CanvasLayer

## シーン遷移アニメーション (Autoload)
## ハーフトーンワイプ / フェード / ドア・ワイプ でシーン切り替えを管理する

const T_CIRCLE_SCENE := preload("res://assets/TransitionKit/transitions/t_circle.tscn")
const LOADING_CHARACTER_SCRIPT := preload("res://scripts/ui/loading_character_3d.gd")

enum LoadingCharacterPhase {
	HIDDEN,
	ENTERING,
	WAITING,
	EXITING,
}

var _overlay: ColorRect
var _door_left: ColorRect
var _door_right: ColorRect
var _hold_texture_rect: TextureRect
var _modular_rect: TransitionRect
var _loading_holder: Control
var _loading_character: Control
var _loading_label: Label
var _loading_tween: Tween
var _loading_phase: int = LoadingCharacterPhase.HIDDEN
var _loading_reveal_requested: bool = false
var _loading_reveal_color: Color = Color.BLACK
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
const MODULAR_DURATION := 0.85
const MODULAR_WIPE_WIDTH := 0.3
const HOLD_TEXTURE_REVEAL_DURATION := 0.22
const DOOR_DURATION := 0.5
const LOADING_SLIDE_OUT_DURATION := 0.18
const LOADING_APPEAR_COVER_FACTOR := 0.36
const LOADING_EXIT_SAFE_FACTOR := 0.08
const LOADING_REVEAL_WIPE_WIDTH := 0.08
const LOADING_REVEAL_GRADIENT_HOLD := 0.32
const MODULAR_GRADIENT_FROM := Vector2(0.0, 1.0)
const MODULAR_GRADIENT_TO := Vector2(1.0, 0.0)
const LOADING_REVEAL_GRADIENT_FROM := Vector2(0.0, 0.94)
const LOADING_REST_LEFT := 28.0
const LOADING_OFFSCREEN_LEFT := -220.0
const LOADING_BOTTOM := 24.0
const LOADING_HOLDER_SIZE := Vector2(88.0, 92.0)
const LOADING_LABEL_GAP_X := 8.0
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

	_setup_modular_wipe()
	_setup_loading_character()

func _setup_modular_wipe() -> void:
	_modular_rect = T_CIRCLE_SCENE.instantiate() as TransitionRect
	_modular_rect.name = "ModularWipe"
	_modular_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modular_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modular_rect.visible = false

	var gradient := Gradient.new()
	var gradient_tex := GradientTexture2D.new()
	gradient_tex.gradient = gradient
	gradient_tex.fill_from = MODULAR_GRADIENT_FROM
	gradient_tex.fill_to = MODULAR_GRADIENT_TO

	_modular_rect.gradient_texture = gradient_tex
	_modular_rect.gradient_fixed = true
	_modular_rect.width = MODULAR_WIPE_WIDTH
	_modular_rect.shape_tiling = 16.0
	_modular_rect.factor = 0.0
	add_child(_modular_rect)


func _setup_loading_character() -> void:
	_loading_holder = Control.new()
	_loading_holder.name = "BlackHoldLoadingCharacter"
	_loading_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_holder.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_loading_holder.offset_left = LOADING_OFFSCREEN_LEFT
	_loading_holder.offset_right = LOADING_OFFSCREEN_LEFT + LOADING_HOLDER_SIZE.x
	_loading_holder.offset_top = -LOADING_BOTTOM - LOADING_HOLDER_SIZE.y
	_loading_holder.offset_bottom = -LOADING_BOTTOM
	add_child(_loading_holder)

	_loading_character = LOADING_CHARACTER_SCRIPT.new() as Control
	_loading_character.name = "HeadSpinCharacter3D"
	_loading_character.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_character.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_holder.add_child(_loading_character)

	_loading_label = Label.new()
	_loading_label.name = "LoadingLabel"
	_loading_label.text = "LOADING..."
	_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_loading_label.add_theme_font_size_override("font_size", 18)
	_loading_label.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0))
	_loading_label.add_theme_color_override("font_outline_color", Color(0.04, 0.07, 0.12, 1.0))
	_loading_label.add_theme_constant_override("outline_size", 4)
	_loading_holder.add_child(_loading_label)
	_align_loading_label_to_character()

	# 3DモデルとFBXを画面遷移より前に準備し、ワイプ中の引っ掛かりを防ぐ。
	_loading_character.call("set_player", true)
	_reset_loading_character()

## シーン切替直前の画面を静止画として保持し、読み込み中の空白フレームを隠す
func hold_image_texture(texture: Texture2D) -> void:
	_reset_loading_character()
	_hide_doors()
	_hide_modular()
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
	_reset_loading_character()
	_clear_texture_hold()
	_hide_doors()
	_hide_modular()
	_overlay.color = color
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_is_transitioning = true
	_active_style = "fade"

## シーン切り替え (ハーフトーンワイプで覆う → 切替 → reveal_current で開示)
func change_scene(path: String, fade_color: Color = Color.BLACK) -> void:
	if _is_transitioning:
		return
	_reset_loading_character()
	_clear_texture_hold()
	_hide_doors()
	_is_transitioning = true
	_active_style = "modular"
	_prepare_modular_cover(fade_color)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_modular_rect, "factor", 1.0, MODULAR_DURATION)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(path)
	)

## ハーフトーンワイプで画面を覆ってから完了。状態は modular のまま保持し、
## 次シーンの reveal_current() で開示させる (change_scene_to_packed 等と併用)
func fade_to_color_and_wait(
	fade_color: Color = Color.BLACK,
	show_loading_character: bool = false,
) -> void:
	_reset_loading_character()
	_clear_texture_hold()
	_hide_doors()
	_is_transitioning = true
	_active_style = "modular"
	_prepare_modular_cover(fade_color)
	if show_loading_character:
		_start_loading_entry()
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_modular_rect, "factor", 1.0, MODULAR_DURATION)
	await tween.finished


## ドア・ワイプでシーン切り替え (左右パネルが seam から広がって画面を覆う)
func change_scene_doors(path: String, seam_x: float = -1.0, color: Color = ACCENT_BLUE) -> void:
	if _is_transitioning:
		return
	_reset_loading_character()
	_clear_texture_hold()
	_hide_modular()
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

## シーン読み込み後に遷移演出を解除 (modular / fade / doors 対応)
func reveal_current(fade_color: Color = Color.BLACK) -> void:
	if not _is_transitioning:
		_reset_loading_character()
		return
	if _loading_phase != LoadingCharacterPhase.HIDDEN:
		_loading_reveal_requested = true
		_loading_reveal_color = fade_color
		if _loading_phase == LoadingCharacterPhase.WAITING:
			_start_loading_exit()
		return
	_reveal_current_now(fade_color)


func _reveal_current_now(fade_color: Color) -> void:
	match _active_style:
		"modular":
			_reveal_modular()
		"doors":
			_reveal_doors()
		"fade":
			_fade_in(fade_color)
		"texture_hold":
			_reveal_texture_hold()
		_:
			_is_transitioning = false


func _start_loading_entry() -> void:
	if _loading_holder == null or _loading_character == null:
		return
	var is_p1: bool = randi_range(1, 2) == 1
	_loading_character.call("set_player", is_p1)
	_loading_holder.position = Vector2(LOADING_REST_LEFT, _loading_holder.position.y)
	_loading_phase = LoadingCharacterPhase.ENTERING

	# Ease-In Quadの閉じワイプが縮小後の左下領域を完全に追い越してから表示する。
	var appear_delay: float = MODULAR_DURATION * sqrt(LOADING_APPEAR_COVER_FACTOR)
	_loading_tween = create_tween()
	_loading_tween.tween_interval(appear_delay)
	_loading_tween.tween_callback(_finish_loading_entry)


func _finish_loading_entry() -> void:
	_loading_tween = null
	if _loading_phase != LoadingCharacterPhase.ENTERING:
		return
	_loading_character.call("set_active", true)
	_loading_holder.process_mode = Node.PROCESS_MODE_ALWAYS
	_loading_holder.visible = true
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if _loading_phase != LoadingCharacterPhase.ENTERING or not is_inside_tree():
		return
	_align_loading_label_to_character()
	_loading_phase = LoadingCharacterPhase.WAITING
	if _loading_reveal_requested:
		_start_loading_exit()


func _align_loading_label_to_character() -> void:
	if _loading_label == null or _loading_character == null:
		return
	var font: Font = _loading_label.get_theme_font("font")
	var font_size: int = 18
	if font == null:
		font = ThemeDB.fallback_font
		font_size = ThemeDB.fallback_font_size
	var ascent: float = font.get_ascent(font_size)
	var character_bottom: float = LOADING_HOLDER_SIZE.y
	if _loading_character.has_method("get_visual_bottom_y"):
		character_bottom = float(_loading_character.call("get_visual_bottom_y"))
	if character_bottom <= 1.0:
		character_bottom = LOADING_HOLDER_SIZE.y
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_loading_label.reset_size()
	_loading_label.position = Vector2(
		LOADING_HOLDER_SIZE.x + LOADING_LABEL_GAP_X,
		character_bottom - ascent,
	)


func _start_loading_exit() -> void:
	if _loading_phase != LoadingCharacterPhase.WAITING or _loading_holder == null:
		return
	_loading_phase = LoadingCharacterPhase.EXITING
	_prepare_loading_reveal_mask()
	_reveal_current_now(_loading_reveal_color)

	# Ease-Out Quad の factor が実測安全値へ達する直前まで回転を継続する。
	# その後は Ease-Out Cubic で素早く左へ抜き、ハーフトーン境界を越えさせない。
	var exit_delay: float = MODULAR_DURATION * (1.0 - sqrt(LOADING_EXIT_SAFE_FACTOR))
	_loading_tween = create_tween()
	_loading_tween.tween_interval(exit_delay)
	_loading_tween.tween_property(
		_loading_holder,
		"position:x",
		LOADING_OFFSCREEN_LEFT,
		LOADING_SLIDE_OUT_DURATION,
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_loading_tween.tween_callback(_finish_loading_exit)


func _finish_loading_exit() -> void:
	_loading_tween = null
	_reset_loading_character()


func _reset_loading_character() -> void:
	if _loading_tween != null and _loading_tween.is_valid():
		_loading_tween.kill()
	_loading_tween = null
	_loading_phase = LoadingCharacterPhase.HIDDEN
	_loading_reveal_requested = false
	_loading_reveal_color = Color.BLACK
	if _loading_holder == null:
		return
	if _loading_character != null:
		_loading_character.call("set_active", false)
	_loading_holder.position = Vector2(LOADING_OFFSCREEN_LEFT, _loading_holder.position.y)
	_loading_holder.visible = false
	_loading_holder.process_mode = Node.PROCESS_MODE_DISABLED

## フェードインのみ (後方互換)
func fade_in_current(fade_color: Color = Color.BLACK) -> void:
	if _overlay.color.a < 0.01 and not _is_transitioning:
		return
	reveal_current(fade_color)

func _prepare_modular_cover(fade_color: Color = Color.BLACK) -> void:
	_overlay.color.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modular_rect.base_color = fade_color
	_modular_rect.width = MODULAR_WIPE_WIDTH
	var gradient_texture := _modular_rect.gradient_texture as GradientTexture2D
	if gradient_texture != null:
		gradient_texture.fill_from = MODULAR_GRADIENT_FROM
		gradient_texture.fill_to = MODULAR_GRADIENT_TO
		gradient_texture.gradient.offsets = PackedFloat32Array([0.0, 1.0])
		gradient_texture.gradient.colors = PackedColorArray([Color.BLACK, Color.WHITE])
	_modular_rect.visible = true
	_modular_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_modular_rect.factor = 0.0


func _prepare_loading_reveal_mask() -> void:
	if _modular_rect == null:
		return
	_modular_rect.width = LOADING_REVEAL_WIPE_WIDTH
	var gradient_texture := _modular_rect.gradient_texture as GradientTexture2D
	if gradient_texture != null:
		gradient_texture.fill_from = LOADING_REVEAL_GRADIENT_FROM
		gradient_texture.fill_to = MODULAR_GRADIENT_TO
		# 左下のキャラ領域だけ勾配を平坦にし、遷移終了直前まで完全な黒を残す。
		gradient_texture.gradient.offsets = PackedFloat32Array(
			[0.0, LOADING_REVEAL_GRADIENT_HOLD, 1.0]
		)
		gradient_texture.gradient.colors = PackedColorArray(
			[Color.BLACK, Color.BLACK, Color.WHITE]
		)

func _reveal_modular() -> void:
	_modular_rect.visible = true
	_modular_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_modular_rect.factor = 1.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_modular_rect, "factor", 0.0, MODULAR_DURATION)
	tween.tween_callback(func():
		_hide_modular()
		_is_transitioning = false
		_active_style = ""
	)

func _hide_modular() -> void:
	if _modular_rect == null:
		return
	_modular_rect.visible = false
	_modular_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modular_rect.factor = 0.0

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
