extends Control
class_name LoadingCharacter3D

const ToonPresets = preload("res://scripts/cosmetics/character_toon_presets.gd")

## 黒画面ローディング用の3Dキャラクター。
## ヘッドスピンFBXの骨格を、ゲーム本体と同じ立体ブロックマンへ転写して描画する。

const PREVIEW_SIZE := Vector2i(600, 624)

var _sub_viewport: SubViewport
var _output_rect: TextureRect
var _camera: Camera3D
var _fbx_node: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _animation_name: StringName = &""
var _bone_indices: Dictionary = {}
var _active: bool = false
var _rotation_clock_started_usec: int = 0
var _rotation_clock_offset: float = 0.0

var _p1_root: Node3D
var _p2_root: Node3D
var _p1_parts: Dictionary = {}
var _p2_parts: Dictionary = {}
var _p1_root_motion: Dictionary = {"ready": false, "origin": Vector3.ZERO}
var _p2_root_motion: Dictionary = {"ready": false, "origin": Vector3.ZERO}
var _p1_hat_id: int = HatData.HAT_NONE
var _p2_hat_id: int = HatData.HAT_NONE
var _p1_toon_preset_id: int = ToonPresets.STANDARD
var _p2_toon_preset_id: int = ToonPresets.STANDARD
var _is_p1: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	clip_contents = true
	_setup_viewport()
	_setup_players()
	_setup_head_spin_animation()
	set_active(false)


func _setup_viewport() -> void:
	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "LoadingCharacterViewport"
	_sub_viewport.size = PREVIEW_SIZE
	_sub_viewport.transparent_bg = true
	_sub_viewport.own_world_3d = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# 画面全体の設定に左右されず、100x104表示へ十分なスーパーサンプリングを確保する。
	GraphicsQuality.apply_character_preview(_sub_viewport, GraphicsQuality.HIGH)
	# このViewportは3D専用。不要な2D MSAAを切り、実行時警告と余分な負荷を避ける。
	_sub_viewport.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_sub_viewport)

	# SubViewportContainer の stretch は内部解像度を表示サイズへ戻してしまうため、
	# 600x624 の描画結果を TextureRect で 100x104 へ縮小して表示する。
	_output_rect = TextureRect.new()
	_output_rect.name = "LoadingCharacterOutput"
	_output_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_output_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_output_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_output_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_output_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_output_rect.texture = _sub_viewport.get_texture()
	add_child(_output_rect)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.50, 0.56)
	environment.ambient_light_energy = 1.15
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_sub_viewport.add_child(world_environment)

	_camera = Camera3D.new()
	_camera.name = "LoadingCharacterCamera"
	_camera.position = Vector3(0.0, -0.32, 4.2)
	_camera.fov = 32.0
	_sub_viewport.add_child(_camera)
	_camera.look_at(Vector3(0.0, -0.34, 0.0), Vector3.UP)
	_camera.current = true

	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	key_light.light_color = Color(1.0, 0.92, 0.82)
	key_light.light_energy = 1.65
	key_light.shadow_enabled = true
	_sub_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.rotation_degrees = Vector3(-18.0, 135.0, 0.0)
	fill_light.light_color = Color(0.58, 0.70, 1.0)
	fill_light.light_energy = 0.65
	fill_light.shadow_enabled = false
	_sub_viewport.add_child(fill_light)


func _setup_players() -> void:
	var game_state := QuizManager.game_state
	var p1_hat: int = game_state.p1_hat if game_state != null else HatData.HAT_NONE
	var p2_hat: int = game_state.p2_hat if game_state != null else HatData.HAT_NONE
	_rebuild_player(true, p1_hat, ToonPresets.resolve_player_preset(game_state, 1))
	_rebuild_player(false, p2_hat, ToonPresets.resolve_player_preset(game_state, 2))
	_apply_player_visibility()


func _rebuild_player(is_p1: bool, hat_id: int, toon_preset: int) -> void:
	var previous_root: Node3D = _p1_root if is_p1 else _p2_root
	if previous_root != null and is_instance_valid(previous_root):
		previous_root.queue_free()

	var player_root := Node3D.new()
	player_root.name = "P1LoadingPlayer" if is_p1 else "P2LoadingPlayer"
	_sub_viewport.add_child(player_root)
	var parts: Dictionary = EmoteBlockmanPreview.build_player_skeleton(
		is_p1,
		player_root,
		hat_id,
		toon_preset,
	)

	if is_p1:
		_p1_root = player_root
		_p1_parts = parts
		_p1_hat_id = hat_id
		_p1_toon_preset_id = ToonPresets.normalize(toon_preset)
		_p1_root_motion = {"ready": false, "origin": Vector3.ZERO}
	else:
		_p2_root = player_root
		_p2_parts = parts
		_p2_hat_id = hat_id
		_p2_toon_preset_id = ToonPresets.normalize(toon_preset)
		_p2_root_motion = {"ready": false, "origin": Vector3.ZERO}


func _setup_head_spin_animation() -> void:
	var fbx_path: String = EmoteData.get_emote_fbx(EmoteData.EMOTE_HEAD_SPINNING)
	if fbx_path.is_empty() or not ResourceLoader.exists(fbx_path):
		push_warning("Head-spin loading animation asset is unavailable")
		return
	var packed_scene := load(fbx_path) as PackedScene
	if packed_scene == null:
		push_warning("Head-spin loading animation could not be loaded")
		return

	_fbx_node = packed_scene.instantiate() as Node3D
	if _fbx_node == null:
		return
	_fbx_node.name = "HeadSpinAnimationRig"
	_sub_viewport.add_child(_fbx_node)
	for mesh_node: Node in _fbx_node.find_children("*", "MeshInstance3D", true, false):
		(mesh_node as MeshInstance3D).hide()

	for skeleton_node: Node in _fbx_node.find_children("*", "Skeleton3D", true, false):
		_skeleton = skeleton_node as Skeleton3D
		break
	if _skeleton != null:
		_bone_indices = EmoteBlockmanPreview.map_mixamo_bones(_skeleton)

	for animation_node: Node in _fbx_node.find_children("*", "AnimationPlayer", true, false):
		_animation_player = animation_node as AnimationPlayer
		break
	if _animation_player == null:
		return
	var selected_animation: String = EmoteBlockmanPreview.pick_best_emote_animation(_animation_player)
	if selected_animation.is_empty():
		return
	_animation_name = StringName(selected_animation)
	_install_looping_animation(selected_animation)
	_animation_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_animation_player.play(_animation_name)
	_animation_player.advance(0.0)
	_animation_player.pause()


func _install_looping_animation(animation_name: String) -> void:
	var source_animation: Animation = _animation_player.get_animation(animation_name)
	if source_animation == null:
		return
	var looping_animation := source_animation.duplicate(true) as Animation
	if looping_animation == null:
		return
	looping_animation.loop_mode = Animation.LOOP_LINEAR

	var library_name := StringName()
	var clip_name := StringName(animation_name)
	var slash_index: int = animation_name.find("/")
	if slash_index >= 0:
		library_name = StringName(animation_name.left(slash_index))
		clip_name = StringName(animation_name.substr(slash_index + 1))
	var library: AnimationLibrary = _animation_player.get_animation_library(library_name)
	if library != null:
		library.add_animation(clip_name, looping_animation)


func set_player(is_p1: bool) -> void:
	_is_p1 = is_p1
	var game_state := QuizManager.game_state
	if game_state != null:
		var current_hat: int = game_state.p1_hat if is_p1 else game_state.p2_hat
		var cached_hat: int = _p1_hat_id if is_p1 else _p2_hat_id
		var current_toon := ToonPresets.resolve_player_preset(game_state, 1 if is_p1 else 2)
		var cached_toon: int = _p1_toon_preset_id if is_p1 else _p2_toon_preset_id
		if current_hat != cached_hat or current_toon != cached_toon:
			_rebuild_player(is_p1, current_hat, current_toon)
	_apply_player_visibility()
	_apply_current_pose()


func set_active(active: bool) -> void:
	if _active and not active:
		_sync_rotation_to_realtime()
	_active = active
	set_process(active)
	if _sub_viewport != null:
		_sub_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		)
	if _animation_player == null or _animation_name.is_empty():
		return
	if active:
		_ensure_rotation_playback()
		_rotation_clock_offset = _animation_player.current_animation_position
		_rotation_clock_started_usec = Time.get_ticks_usec()
		_sync_rotation_to_realtime()
	else:
		_animation_player.pause()
		_rotation_clock_started_usec = 0


func _process(_delta: float) -> void:
	if _active:
		_ensure_rotation_playback()
		_sync_rotation_to_realtime()
	_apply_current_pose()


func _ensure_rotation_playback() -> void:
	if _animation_player == null or _animation_name.is_empty():
		return
	if _animation_player.assigned_animation != _animation_name:
		_animation_player.play(_animation_name)
		_animation_player.advance(0.0)
	if _animation_player.is_playing():
		# 自動deltaではなく単調実時間でseekする。シーン生成でフレームが飛んでも
		# 次の描画時に正しい回転位置へ追いつき、終端で停止しない。
		_animation_player.pause()


func _sync_rotation_to_realtime() -> void:
	if (
		_animation_player == null
		or _animation_name.is_empty()
		or _rotation_clock_started_usec <= 0
	):
		return
	var animation := _animation_player.get_animation(_animation_name)
	if animation == null or animation.length <= 0.0:
		return
	var elapsed_seconds := (
		float(Time.get_ticks_usec() - _rotation_clock_started_usec) / 1_000_000.0
	)
	var target_position := fposmod(
		_rotation_clock_offset + elapsed_seconds,
		animation.length
	)
	_animation_player.seek(target_position, true)


func _apply_current_pose() -> void:
	if _skeleton == null or _bone_indices.is_empty():
		return
	var parts: Dictionary = _p1_parts if _is_p1 else _p2_parts
	var root_motion: Dictionary = _p1_root_motion if _is_p1 else _p2_root_motion
	if parts.is_empty():
		return
	EmoteBlockmanPreview.apply_skeleton_pose(
		parts,
		_skeleton,
		_bone_indices,
		true,
		null,
		root_motion,
	)


func _apply_player_visibility() -> void:
	if _p1_root != null:
		_p1_root.visible = _is_p1
	if _p2_root != null:
		_p2_root.visible = not _is_p1


## LOADING文字の底辺を合わせるため、描画済みシルエットの下端をこのControl座標で返す。
func get_visual_bottom_y() -> float:
	_apply_current_pose()
	if _sub_viewport == null or size.y <= 0.0:
		return size.y
	var viewport_texture := _sub_viewport.get_texture()
	if viewport_texture != null:
		var image: Image = viewport_texture.get_image()
		if image != null and not image.is_empty():
			var width: int = image.get_width()
			var height: int = image.get_height()
			var step_x: int = maxi(1, int(floor(float(width) / 80.0)))
			for y: int in range(height - 1, -1, -1):
				for x: int in range(0, width, step_x):
					if image.get_pixel(x, y).a > 0.12:
						return clampf(
							(float(y) + 1.0) * size.y / float(height),
							0.0,
							size.y
						)
	return _get_aabb_visual_bottom_y()


func _get_aabb_visual_bottom_y() -> float:
	var player_root: Node3D = _p1_root if _is_p1 else _p2_root
	if player_root == null or _camera == null or size.y <= 0.0:
		return size.y
	var merged_aabb := AABB()
	var has_aabb: bool = false
	for mesh_node: Node in player_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mesh_node as MeshInstance3D
		if mesh_inst == null or not mesh_inst.visible:
			continue
		var mesh_aabb: AABB = mesh_inst.global_transform * mesh_inst.get_aabb()
		if not has_aabb:
			merged_aabb = mesh_aabb
			has_aabb = true
		else:
			merged_aabb = merged_aabb.merge(mesh_aabb)
	if not has_aabb:
		return size.y
	var lowest_viewport_y: float = 0.0
	for corner_index: int in range(8):
		var viewport_pos: Vector2 = _camera.unproject_position(merged_aabb.get_endpoint(corner_index))
		lowest_viewport_y = maxf(lowest_viewport_y, viewport_pos.y)
	var scale_y: float = size.y / float(PREVIEW_SIZE.y)
	return clampf(lowest_viewport_y * scale_y, 0.0, size.y)
