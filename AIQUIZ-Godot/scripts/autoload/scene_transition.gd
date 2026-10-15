extends CanvasLayer

## シーン遷移アニメーション (Autoload)
## ハーフトーンワイプ / フェード / ドア・ワイプ / 中央の線が開く（versus_split）でシーン切り替えを管理する

const T_CIRCLE_SCENE := preload("res://assets/TransitionKit/transitions/t_circle.tscn")
const T_DATA_SHAPE := preload("res://assets/TransitionKit/src/texture/transition_shape/noise/data_02.tres")
const VERSUS_SPLIT_SHADER := preload("res://shaders/versus_split_mask.gdshader")
## 火花の筋 4×2 コマ（Higgsfield で作った絵をグレーにしたもの。色は粒子の色で付ける。頭が +Y＝進む向き）
const VERSUS_SPARK_TEXTURE := preload("res://assets/ui/versus_split/spark_streaks.png")
const LOADING_CHARACTER_SCRIPT := preload("res://scripts/ui/loading_character_3d.gd")

enum LoadingCharacterPhase {
	HIDDEN,
	ENTERING,
	WAITING,
	EXITING,
}

## モジュラーワイプの柄。CIRCLE は通常の丸、DATA はオンライン対戦画面の出入り
## （TransitionKit の t_data。demo.tscn の TData と同じ設定）。
enum WipeStyle {
	CIRCLE,
	DATA,
}

var _overlay: ColorRect
var _door_left: ColorRect
var _door_right: ColorRect
var _hold_texture_rect: TextureRect
var _split_rect: ColorRect
var _split_material: ShaderMaterial
var _split_sparks: Array[CPUParticles2D] = []
var _split_grind_sparks: Array[CPUParticles2D] = []
var _split_spark_material: CanvasItemMaterial
var _split_camera_pull := 0.0
var _split_seam: Array = []
var _split_colors: Array = []
var _split_sparked := false
## VS の覆いが開いている最中（reveal_current から開ききるまで）。演出の重さの計測とゲーム画面の待ち合わせに使う
var versus_split_opening := false
var _split_duration := 0.7
## 覆っているあいだも動き続けるカットイン（hold_versus_split の live）。開くときに写して静止画と差しかえる
var _live_cover: Control
var _split_open := 0.0
var _modular_rect: TransitionRect
var _circle_shape_texture: Texture2D
var _circle_shape_scroll: Vector2
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
const MODULAR_SHAPE_TILING := 16.0
const DATA_WIPE_WIDTH := 0.6
const DATA_SHAPE_TILING := 4.0
const DATA_SHAPE_SCROLL := Vector2(-0.1, 0.0)
const DATA_GRADIENT_FROM := Vector2(1.0, 1.0)
const DATA_GRADIENT_TO := Vector2(0.0, 0.0)
const HOLD_TEXTURE_REVEAL_DURATION := 0.22
const DOOR_DURATION := 0.5
## 中央の線が開く遷移（オンライン対戦のマッチング演出 S10、v1.6）。長さは OnlineStagingTimeline の REVEAL を渡す
const VERSUS_SPLIT_DURATION := 3.2
## 開く長さ全体に対する割合：稲妻が上から下へ走る（〜strike_end）→ 溜め（charge_start〜burst）→ 割れて、震えながらゆっくり開く
## （burst〜exit）→ 割れ目の光が消える（〜light_end）。開き方は「はじめにがくんと少し開く（jolt を jolt_k まで）→ こすれながら
## ゆっくり → 最後に速く」。揺れは 2D だけ（仕様書 16：±6 px まで）。割れた瞬間の揺れ shake_px が引くのと入れかわりに、
## 左右の半分が別々に grind_px で震え続け、切り口から火花（grind_*）がこぼれる。3D のカメラは開くのと同時に寄る
const VERSUS_SPLIT_FX := {
	"strike_end": 0.156, "charge_start": 0.125, "burst": 0.234, "exit": 0.95, "light_end": 0.62,
	"jolt": 0.05, "jolt_k": 0.10, "exit_power": 1.7,
	"crack_px": 4.0, "tremble_px": 2.5, "shake_px": 6.0, "shake_seconds": 0.18,
	"grind_px": 4.0, "grind_hz": 38.0, "grind_end": 0.80,
	"sparks": 110, "spark_lifetime": 1.1,
	"grind_sparks": 150, "grind_spark_lifetime": 0.75,
}
## 左右の半分の動き（versus_split_mask.gdshader の travel・tilt_deg・grow へ渡す）
const VERSUS_SPLIT_TRAVEL := 0.62
const VERSUS_SPLIT_TILT_DEG := 5.0
const VERSUS_SPLIT_GROW := 0.10
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

	_split_rect = ColorRect.new()
	_split_rect.name = "VersusSplit"
	_split_rect.visible = false
	_split_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_split_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_split_material = ShaderMaterial.new()
	_split_material.shader = VERSUS_SPLIT_SHADER
	_split_rect.material = _split_material
	_split_material.set_shader_parameter("travel", VERSUS_SPLIT_TRAVEL)
	_split_material.set_shader_parameter("tilt_deg", VERSUS_SPLIT_TILT_DEG)
	_split_material.set_shader_parameter("grow", VERSUS_SPLIT_GROW)
	add_child(_split_rect)
	_split_spark_material = CanvasItemMaterial.new()
	_split_spark_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_split_spark_material.particles_animation = true
	_split_spark_material.particles_anim_h_frames = 4
	_split_spark_material.particles_anim_v_frames = 2
	_split_spark_material.particles_anim_loop = false
	for side: float in [-1.0, 1.0]:
		_split_sparks.append(_make_split_sparks(side))
	for side: float in [-1.0, 1.0]:
		_split_grind_sparks.append(_make_grind_sparks(side))

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
	# 画面の縦横比でY成分を圧縮せず、左下→右上の対角線をそのまま使う。
	_modular_rect.gradient_fixed = false
	_modular_rect.width = MODULAR_WIPE_WIDTH
	_modular_rect.shape_tiling = MODULAR_SHAPE_TILING
	_modular_rect.factor = 0.0
	_circle_shape_texture = _modular_rect.shape_texture
	_circle_shape_scroll = _modular_rect.shape_scroll
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

## オンライン対戦の VS カットインを写した静止画で覆う。reveal_current()（読み込みが終わったとき）で、両陣営の色を編んだ
## 稲妻が線（seam：画面の割合の点）を上から下へ走り、溜めてから、左右の半分が外へ飛んで開く（仕様書 S10 v1.4）。
## duration は稲妻から開ききるまでの長さ（「みじかい」演出は短い）。colors は [左の色, 右の色]（カットインの side_colors）。
## live（カットインの層）を渡すと、それをこの層へ移して静止画の上に重ね、次の画面を組み立てて開くまで動かし続ける
## （静止画のままだと、読み込みが終わってから開くまでカットインが止まって見える）。開くときにその時の絵を写して割る。
func hold_versus_split(texture: Texture2D, seam: Array, duration: float = VERSUS_SPLIT_DURATION, colors: Array = [], live: Control = null) -> void:
	_reset_loading_character()
	_clear_texture_hold()
	_hide_doors()
	_hide_modular()
	_overlay.color.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_split_material.set_shader_parameter("screen_tex", texture)
	for i in range(mini(seam.size(), 6)):
		_split_material.set_shader_parameter("seam_%d" % i, seam[i])
	_split_seam = seam.duplicate()
	_split_colors = colors.duplicate() if colors.size() >= 2 else [PlayerController.P1_BODY, PlayerController.P2_BODY]
	_split_material.set_shader_parameter("left_color", _split_colors[0])
	_split_material.set_shader_parameter("right_color", _split_colors[1])
	_split_material.set_shader_parameter("rect_size", get_viewport().get_visible_rect().size)
	_setup_grind_sparks()
	_split_camera_pull = 1.0
	_split_sparked = false
	_split_rect.position = Vector2.ZERO
	_split_duration = maxf(duration, 0.1)
	_update_split_fx(0.0)
	_split_rect.visible = true
	_split_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	if live != null:
		_live_cover = live
		if live.get_parent() != null:
			live.get_parent().remove_child(live)
		add_child(live)
		live.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = true
	_active_style = "versus_split"


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
## wipe_style の柄は次の reveal_current() の開示にも引き継がれる。
func change_scene(
	path: String,
	fade_color: Color = Color.BLACK,
	wipe_style: WipeStyle = WipeStyle.CIRCLE,
) -> void:
	if _is_transitioning:
		return
	_reset_loading_character()
	_clear_texture_hold()
	_hide_doors()
	_is_transitioning = true
	_active_style = "modular"
	_prepare_modular_cover(fade_color, wipe_style)

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
	wipe_style: WipeStyle = WipeStyle.CIRCLE,
) -> void:
	_reset_loading_character()
	_clear_texture_hold()
	_hide_doors()
	_is_transitioning = true
	_active_style = "modular"
	_prepare_modular_cover(fade_color, wipe_style)
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
		"versus_split":
			_reveal_versus_split()
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

func _prepare_modular_cover(
	fade_color: Color = Color.BLACK,
	wipe_style: WipeStyle = WipeStyle.CIRCLE,
) -> void:
	var is_data := wipe_style == WipeStyle.DATA
	_overlay.color.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modular_rect.base_color = fade_color
	_modular_rect.width = DATA_WIPE_WIDTH if is_data else MODULAR_WIPE_WIDTH
	_modular_rect.shape_texture = T_DATA_SHAPE if is_data else _circle_shape_texture
	_modular_rect.shape_tiling = DATA_SHAPE_TILING if is_data else MODULAR_SHAPE_TILING
	_modular_rect.shape_scroll = DATA_SHAPE_SCROLL if is_data else _circle_shape_scroll
	var gradient_texture := _modular_rect.gradient_texture as GradientTexture2D
	if gradient_texture != null:
		gradient_texture.fill_from = DATA_GRADIENT_FROM if is_data else MODULAR_GRADIENT_FROM
		gradient_texture.fill_to = DATA_GRADIENT_TO if is_data else MODULAR_GRADIENT_TO
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

func _reveal_versus_split() -> void:
	_capture_live_cover()
	_split_sparked = false
	versus_split_opening = true
	# 稲妻 → 溜め → 割れる → こすれて開く → 抜ける、の時刻に合わせた 1 本の音（「みじかい」演出は短い版）
	AudioManager.fade_out_sfx(&"versus_charge", 0.12)
	AudioManager.play_sfx(&"versus_reveal_short" if _split_duration < 2.7 else &"versus_reveal")
	var tw := create_tween()
	tw.tween_method(_update_split_fx, 0.0, _split_duration, _split_duration)
	tw.tween_callback(func():
		_clear_versus_split()
		_is_transitioning = false
		_active_style = ""
	)


## 開く演出の t 秒目（0〜_split_duration）：稲妻・溜め・割れて震えながら開く・光・揺れ・火花・カメラの寄り。
func _update_split_fx(t: float) -> void:
	var fx: Dictionary = VERSUS_SPLIT_FX
	var d := maxf(_split_duration, 0.1)
	var u := clampf(t / d, 0.0, 1.0)
	var m := _split_material
	m.set_shader_parameter("fx_time", t)
	# 稲妻の頭：上の端から下の端へ（入りと着きをなめらかに）
	var s := clampf(u / float(fx.strike_end), 0.0, 1.0)
	m.set_shader_parameter("strike", s * s * (3.0 - 2.0 * s))
	var b := float(fx.burst)
	var charge := smoothstep(float(fx.charge_start), b, u)
	m.set_shader_parameter("charge", charge)
	m.set_shader_parameter("crack", float(fx.crack_px) * charge)
	# 開く：がくんと少し開いてから、こすれながらゆっくり、最後に速く外へ
	var k := clampf((u - b) / (float(fx.exit) - b), 0.0, 1.0)
	_set_split_open(_split_open_curve(k))
	m.set_shader_parameter("burst", clampf((u - b) / (float(fx.light_end) - b), 0.0, 1.0))
	# 3D のカメラ：開くのと同時に、引いた位置から本来の位置へ寄る（get_reveal_camera_pull）
	_split_camera_pull = 1.0 - smoothstep(0.0, 1.0, k)
	# 揺れ（2D）：溜めで小さく震え、割れた瞬間に ±6 px。その揺れが引くのと入れかわりに左右の半分が別々に震え続ける
	# （割れた瞬間の揺れ ×(1−settle) と半分の震え ×settle を足しても ±6 px をこえない）
	var shake := Vector2.ZERO
	if u >= float(fx.charge_start) and u < b:
		shake = Vector2(sin(t * 83.0), cos(t * 71.0)) * float(fx.tremble_px) * charge
	var since := t - b * d
	var settle := 0.0
	if since >= 0.0:
		settle = clampf(since / float(fx.shake_seconds), 0.0, 1.0)
		shake = Vector2(sin(since * 97.0), cos(since * 89.0)) * float(fx.shake_px) * (1.0 - settle)
	_split_rect.position = shake
	var grind := 0.0
	if since >= 0.0:
		grind = float(fx.grind_px) * settle * (1.0 - smoothstep(float(fx.grind_end) - 0.2, float(fx.grind_end), k))
	var w := float(fx.grind_hz) * TAU
	var shake_l := Vector2(sin(t * w) + 0.5 * sin(t * w * 1.73 + 1.1), 0.6 * cos(t * w * 0.91 + 0.4)) * grind * 0.66
	var shake_r := Vector2(sin(t * w * 1.07 + 2.3) + 0.5 * sin(t * w * 1.61), 0.6 * cos(t * w * 0.87 + 1.9)) * grind * 0.66
	m.set_shader_parameter("shake_l", shake_l)
	m.set_shader_parameter("shake_r", shake_r)
	if since >= 0.0 and not _split_sparked and t > 0.0:
		_split_sparked = true
		_emit_split_sparks()
	_update_grind_sparks(since >= 0.0 and k < float(fx.grind_end) and t > 0.0, [shake_l, shake_r])


## 開く割合（k：開きはじめ 0 → 開ききる 1）。はじめにがくんと jolt まで開き、こすれながらゆっくり、最後に速く外へ。
func _split_open_curve(k: float) -> float:
	var fx: Dictionary = VERSUS_SPLIT_FX
	var jolt := float(fx.jolt)
	var j := clampf(k / float(fx.jolt_k), 0.0, 1.0)
	var slide := pow(smoothstep(float(fx.jolt_k) * 0.5, 1.0, k), float(fx.exit_power))
	return jolt * (1.0 - (1.0 - j) * (1.0 - j)) + (1.0 - jolt) * slide


## 3D のカメラをどれだけ引いておくか（1＝いちばん引いた位置、0＝本来の位置）。中央の線が開く覆いの間だけ 0 より大きい。
## ゲーム画面のカメラ（camera_controller）が読み、開くのと同時に寄る。
func get_reveal_camera_pull() -> float:
	if _active_style != "versus_split" or not _split_rect.visible:
		return 0.0
	return _split_camera_pull


## 写した画面の点（px）が、いま左右どちらかの半分の上でどこ（px）に見えるか（シェーダーの piece_px の逆）。
func _split_piece_to_screen(q: Vector2, side: float, size: Vector2, shake: Vector2) -> Vector2:
	var pivot := Vector2(0.25 if side < 0.0 else 0.75, 0.5) * size
	var a := -side * deg_to_rad(VERSUS_SPLIT_TILT_DEG) * _split_open
	var grow := 1.0 + VERSUS_SPLIT_GROW * _split_open
	var crack := float(VERSUS_SPLIT_FX.crack_px)
	var offset := Vector2(side * (_split_open * VERSUS_SPLIT_TRAVEL * size.x + crack), 0.0)
	return (q - pivot).rotated(-a) * grow + pivot + offset + shake + _split_rect.position


## 開いているあいだ、左右の半分の切り口（いま動いている所）から火花をこぼし続ける。
func _update_grind_sparks(active: bool, shakes: Array) -> void:
	if not active:
		for sparks: CPUParticles2D in _split_grind_sparks:
			sparks.emitting = false
		return
	var size := get_viewport().get_visible_rect().size
	for i in range(_split_grind_sparks.size()):
		var side := -1.0 if i == 0 else 1.0
		var points := PackedVector2Array()
		for j in range(_split_seam.size() - 1):
			var a: Vector2 = _split_seam[j]
			var c: Vector2 = _split_seam[j + 1]
			for n in range(5):
				var p := _split_piece_to_screen(a.lerp(c, float(n) / 5.0) * size, side, size, shakes[i])
				if p.y >= -8.0 and p.y <= size.y + 8.0:
					points.append(p)
		var sparks := _split_grind_sparks[i]
		if points.is_empty():
			sparks.emitting = false
			continue
		sparks.emission_points = points
		if not sparks.emitting:
			sparks.visible = true
			sparks.emitting = true


func _set_split_open(value: float) -> void:
	_split_open = value
	_split_material.set_shader_parameter("open", value)


## 割れた瞬間に線から飛び散る火花（左の陣営の色は左へ、右は右へ）。
func _make_split_sparks(side: float) -> CPUParticles2D:
	var sparks := CPUParticles2D.new()
	sparks.name = "VersusSparksL" if side < 0.0 else "VersusSparksR"
	sparks.emitting = false
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.randomness = 0.5
	sparks.local_coords = false
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	sparks.direction = Vector2(side, -0.4)
	sparks.spread = 40.0
	sparks.initial_velocity_min = 420.0
	sparks.initial_velocity_max = 1500.0
	sparks.gravity = Vector2(0.0, 1100.0)
	sparks.damping_min = 40.0
	sparks.damping_max = 140.0
	sparks.scale_amount_min = 0.14
	sparks.scale_amount_max = 0.38
	sparks.particle_flag_align_y = true
	sparks.material = _split_spark_material
	sparks.texture = VERSUS_SPARK_TEXTURE
	sparks.anim_offset_max = 1.0
	sparks.visible = false
	add_child(sparks)
	return sparks


## 開いているあいだ切り口からこぼれる火花（こすれ合う扉の火花）。すき間の側へはじけて、重さで落ちる。
func _make_grind_sparks(side: float) -> CPUParticles2D:
	var fx: Dictionary = VERSUS_SPLIT_FX
	var sparks := CPUParticles2D.new()
	sparks.name = "VersusGrindSparksL" if side < 0.0 else "VersusGrindSparksR"
	sparks.emitting = false
	sparks.one_shot = false
	sparks.explosiveness = 0.0
	sparks.randomness = 0.6
	sparks.local_coords = false
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	# 左の半分の切り口は右（すき間）へ、右の半分は左へ。少し上向きにはじけて落ちる
	sparks.direction = Vector2(-side, -0.55)
	sparks.spread = 38.0
	sparks.initial_velocity_min = 260.0
	sparks.initial_velocity_max = 980.0
	sparks.gravity = Vector2(0.0, 1500.0)
	sparks.damping_min = 30.0
	sparks.damping_max = 110.0
	sparks.scale_amount_min = 0.20
	sparks.scale_amount_max = 0.46
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.35))
	sparks.scale_amount_curve = shrink
	sparks.particle_flag_align_y = true
	sparks.material = _split_spark_material
	sparks.texture = VERSUS_SPARK_TEXTURE
	sparks.anim_offset_max = 1.0
	sparks.lifetime = float(fx.grind_spark_lifetime)
	sparks.visible = false
	add_child(sparks)
	return sparks


## こぼれる火花の色と数（画質の設定に合わせる）。
func _setup_grind_sparks() -> void:
	var fx: Dictionary = VERSUS_SPLIT_FX
	var quality := GameManager.graphics_quality if GameManager != null else "balanced"
	for i in range(_split_grind_sparks.size()):
		var sparks := _split_grind_sparks[i]
		var colour: Color = _split_colors[i] if i < _split_colors.size() else Color.WHITE
		sparks.color_ramp = _spark_ramp(colour, true)
		sparks.amount = maxi(GraphicsQuality.particle_amount(int(fx.grind_sparks), quality), 8)
		sparks.emitting = false
		sparks.visible = false


## 火花の色：白熱 → 黄 → 陣営の色 → 消える。hot はこすれ火花（金属の火花らしく黄〜オレンジを長く保つ）
func _spark_ramp(colour: Color, hot: bool = false) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.97, 0.88, 1.0))
	ramp.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))
	if hot:
		ramp.add_point(0.25, Color(1.0, 0.82, 0.32, 1.0))
		ramp.add_point(0.6, Color(1.0, 0.5, 0.12, 0.9).lerp(colour, 0.35))
	else:
		ramp.add_point(0.18, Color(1.0, 0.85, 0.5, 1.0))
		ramp.add_point(0.45, colour.lightened(0.35))
	return ramp


func _emit_split_sparks() -> void:
	var fx: Dictionary = VERSUS_SPLIT_FX
	var size := get_viewport().get_visible_rect().size
	var points := PackedVector2Array()
	for i in range(_split_seam.size() - 1):
		var a: Vector2 = _split_seam[i]
		var c: Vector2 = _split_seam[i + 1]
		for j in range(6):
			points.append(a.lerp(c, float(j) / 6.0) * size)
	if points.is_empty():
		return
	var quality := GameManager.graphics_quality if GameManager != null else "balanced"
	for i in range(_split_sparks.size()):
		var sparks := _split_sparks[i]
		var colour: Color = _split_colors[i] if i < _split_colors.size() else Color.WHITE
		sparks.color_ramp = _spark_ramp(colour)
		sparks.emission_points = points
		sparks.amount = maxi(GraphicsQuality.particle_amount(int(fx.sparks), quality), 8)
		sparks.lifetime = float(fx.spark_lifetime)
		sparks.visible = true
		sparks.restart()
		sparks.emitting = true


## 動いているカットインの今の絵（前のフレームで描いた画面）を割る絵にして、カットインを消す。
## 写せないとき（画面のないテスト）は覆ったときの静止画のまま割る。
func _capture_live_cover() -> void:
	if _live_cover == null:
		return
	if DisplayServer.get_name() != "headless":
		var shot := get_viewport().get_texture().get_image()
		if shot != null and not shot.is_empty():
			_split_material.set_shader_parameter("screen_tex", ImageTexture.create_from_image(shot))
	_clear_live_cover()


func _clear_live_cover() -> void:
	if _live_cover != null and is_instance_valid(_live_cover):
		_live_cover.visible = false
		_live_cover.queue_free()
	_live_cover = null


func _clear_versus_split() -> void:
	versus_split_opening = false
	_clear_live_cover()
	if _split_rect == null:
		return
	_split_rect.visible = false
	_split_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_split_rect.position = Vector2.ZERO
	_split_material.set_shader_parameter("screen_tex", null)
	_split_camera_pull = 0.0
	for sparks: CPUParticles2D in _split_grind_sparks:
		sparks.emitting = false


func _clear_texture_hold() -> void:
	# 別の覆い方に切りかえるときは、VS の動くカットインも残さない（いちばん上に重なっているため）
	_clear_live_cover()
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


func get_cover_factor() -> float:
	if not _is_transitioning:
		return 0.0
	match _active_style:
		"modular":
			if _modular_rect == null:
				return 0.0
			return _modular_rect.factor
		"fade":
			return _overlay.color.a
		"doors":
			var viewport_size := get_viewport().get_visible_rect().size
			if viewport_size.x <= 0.001:
				return 0.0
			return clampf((_door_left.size.x + _door_right.size.x) / viewport_size.x, 0.0, 1.0)
		"texture_hold":
			return _hold_texture_rect.modulate.a if _hold_texture_rect.visible else 0.0
		"versus_split":
			return 1.0 - _split_open if _split_rect.visible else 0.0
		_:
			return 0.0


func is_fully_covered() -> bool:
	return is_transitioning() and get_cover_factor() >= 0.999
