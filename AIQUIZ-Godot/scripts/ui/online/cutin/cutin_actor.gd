class_name CutinActors
extends Node

## VS カットインの左右のキャラ（仕様書 7「キャラ」、D13）。
## 1 つの 3D の世界（SubViewport A が持つ）に箱の人形を 2 体置き、左右それぞれのカメラの SubViewport で 1 回だけ描く
## （UPDATE_ONCE。息の動きは 2D の縮尺で出す：計画書「危ないところ」）。テクスチャは left_texture() / right_texture()。
## 色はスロットで決まる（人形 1＝オレンジ、2＝ブルー）。左＝じぶん、右＝あいて（D6）。
## 右のキャラはカメラと体の向きで真ん中（左）を向かせる。縮尺をマイナスにして裏返さない。

const PlayerControllerScript = preload("res://scripts/world/player_controller.gd")
const VIEW_SIZE := Vector2i(900, 1000)
const SPACING := 6.0
const TURN_DEG := 32.0
const CAMERA_FOV := 30.0
const CAMERA_DISTANCE := 5.2
const CAMERA_HEIGHT := 0.75
const LOOK_HEIGHT := 1.05

var view_left: SubViewport
var view_right: SubViewport
var players: PlayerController
var _world_root: Node3D
var _cam_left: Camera3D
var _cam_right: Camera3D
var _rims: Array[OmniLight3D] = []
var _puppets: Array[StagingPuppet] = []
var _gs: QuizGameState
var _ready_to_render := false


func _ready() -> void:
	view_left = _make_view("CutinLeft")
	add_child(view_left)
	view_right = _make_view("CutinRight")
	add_child(view_right)
	_world_root = Node3D.new()
	_world_root.name = "CutinWorld"
	view_left.add_child(_world_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.82, 0.92)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_world_root.add_child(env)
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-38.0, 0.0, 0.0)
	key.light_energy = 1.25
	_world_root.add_child(key)
	_gs = QuizGameState.new()
	_gs.num_players = 2
	_gs.mode = Constants.MODE_TEN
	_gs.game_state = Constants.STATE_MENU
	_gs.p1_alive = true
	_gs.p2_alive = true
	var holder := Node3D.new()
	holder.set_script(PlayerControllerScript)
	holder.name = "CutinPlayers"
	_world_root.add_child(holder)
	players = holder as PlayerController
	players.call("_sync_player_model_count", _gs)
	if players.p2_container != null:
		players.p2_container.position = Vector3.ZERO
	_puppets = [StagingPuppet.new(players, 1), StagingPuppet.new(players, 2)]
	for i in range(2):
		var rim := OmniLight3D.new()
		rim.name = "Rim%d" % (i + 1)
		rim.omni_range = 4.5
		rim.light_energy = 2.4
		_world_root.add_child(rim)
		_rims.append(rim)
	_cam_left = Camera3D.new()
	_cam_left.fov = CAMERA_FOV
	view_left.add_child(_cam_left)
	_cam_left.current = true
	_cam_right = Camera3D.new()
	_cam_right.fov = CAMERA_FOV
	view_right.add_child(_cam_right)
	view_right.world_3d = view_left.find_world_3d()
	_cam_right.current = true
	_ready_to_render = true


func _make_view(view_name: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.size = VIEW_SIZE
	view.transparent_bg = true
	view.own_world_3d = view_name == "CutinLeft"
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return view


## 品質「低」は描く大きさを 0.7 倍にする（仕様書 15）。
func set_low_quality(low: bool) -> void:
	var size := Vector2i(Vector2(VIEW_SIZE) * (0.7 if low else 1.0))
	view_left.size = size
	view_right.size = size


## ポーズと帽子を決めて、左右を 1 回ずつ描く。my_slot：自分のスロット（左に置く人形）。
## my_skin / their_skin は PlayerSkin 形式（{} はスロットの標準色）。
func prepare(
	my_slot: int, my_hat: int, their_hat: int, my_pose: int, their_pose: int,
	my_skin: Dictionary = {}, their_skin: Dictionary = {},
) -> void:
	if not _ready_to_render:
		return
	var left_index := 2 if my_slot == 2 else 1
	var right_index := 3 - left_index
	var hats := {left_index: my_hat, right_index: their_hat}
	var poses := {left_index: my_pose, right_index: their_pose}
	var skins := {left_index: my_skin, right_index: their_skin}
	for index: int in [1, 2]:
		var puppet := _puppets[index - 1]
		puppet.set_visible(true)
		puppet.set_hat(clampi(int(hats[index]), 0, HatData.HAT_COUNT - 1))
		puppet.set_skin(skins[index])
		var pose: Array = OnlineStagingTimeline.CUTIN_POSES[clampi(int(poses[index]), 0, OnlineStagingTimeline.CUTIN_POSES.size() - 1)]
		if not puppet.pose(str(pose[0]), float(pose[2]), int(pose[1])):
			puppet.pose("Idle_Loop", 0.3)
		var is_left := index == left_index
		var x := -SPACING * 0.5 if is_left else SPACING * 0.5
		# 体を真ん中（画面の内側）へ向ける：左のキャラは右へ、右のキャラは左へ
		var yaw := deg_to_rad(TURN_DEG if is_left else -TURN_DEG)
		puppet.stand_at(Vector3(x, 0.0, 0.0), yaw, 0.0)
		var rim := _rims[index - 1]
		rim.light_color = OnlineHeliportStage.slot_color(index).lightened(0.2)
		rim.position = Vector3(x + (-0.9 if is_left else 0.9), 1.9, -1.4)
		var cam := _cam_left if is_left else _cam_right
		cam.global_position = Vector3(x, CAMERA_HEIGHT, CAMERA_DISTANCE)
		cam.look_at(Vector3(x, LOOK_HEIGHT, 0.0), Vector3.UP)
	view_left.render_target_update_mode = SubViewport.UPDATE_ONCE
	view_right.render_target_update_mode = SubViewport.UPDATE_ONCE


func left_texture() -> Texture2D:
	return view_left.get_texture()


func right_texture() -> Texture2D:
	return view_right.get_texture()
