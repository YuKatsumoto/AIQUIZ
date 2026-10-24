class_name CutinActors
extends Node

## VS カットインの左右のキャラ（仕様書 7「キャラ」、D13）。
## 1 つの 3D の世界（SubViewport A が持つ）に箱の人形を 2 体置き、左右それぞれのカメラの SubViewport で描く。
## テクスチャは left_texture() / right_texture()。
## 色はスロットで決まる（人形 1＝オレンジ、2＝ブルー）。左＝じぶん、右＝あいて（D6）。
## 右のキャラはカメラと体の向きで真ん中（左）を向かせる。縮尺をマイナスにして裏返さない。
## 動き：それぞれが付けているエモートを踊る（どれを踊るかは OnlineStagingTimeline.cutin_emote）。エモートの FBX はスレッドで
## 読み、読み終えるまでと、エモートが無いときは CUTIN_POSES のポーズで止める。踊りは毎フレームは描かず DANCE_FPS で描き直す
## （2 つの SubViewport を毎フレーム描かない：計画書「危ないところ」）。
## 枠：帽子と踊りの手足が切れないよう、体と帽子の全部（踊りは 1 回分を見渡した分）が入るまで、足もとを中心にカメラを引く。
## 倍率は 2 人で同じにする（frame_scale。1＝仕様書の枠）。

const PlayerControllerScript = preload("res://scripts/world/player_controller.gd")
## 絵の大きさ。カットインの画面では 936×905（基準の大きさで、足もとから画面の上まで）に置く
const VIEW_SIZE := Vector2i(1034, 1000)
const SPACING := 6.0
const TURN_DEG := 32.0
## 倍率 1 の枠。人形 1 m が画面で同じ大きさになるよう、最初の枠（絵 900×1000 を 720×800 に置き、距離 5.2・高さ 0.75・
## 注視 1.05）を足もとを中心に 905/800 倍に引いたもの
const CAMERA_FOV := 30.0
const CAMERA_DISTANCE := 5.88
const CAMERA_HEIGHT := 0.85
const LOOK_HEIGHT := 1.19
## 踊りを描き直す回数（毎秒）
const DANCE_FPS := 30.0
## 枠の余白（絵の高さ・幅に対する割合）
const FRAME_MARGIN := 0.035
## カメラを引く倍率の上限
const MAX_FRAME_SCALE := 1.8
## 枠を決めるときに踊りを見る点の数と、1 フレームに見る数（読み終えたフレームを重くしない）
const FIT_SAMPLES := 24
const FIT_SAMPLES_PER_FRAME := 6
## 踊りの横のずれを残す幅（m。ResultWinnerDance と同じ）
const SWAY_X := 0.16
const SWAY_Z := 0.12

var view_left: SubViewport
var view_right: SubViewport
var players: PlayerController
## 足もとを中心にカメラを引いた倍率（1＝仕様書の枠）
var frame_scale := 1.0
var _world_root: Node3D
var _cam_left: Camera3D
var _cam_right: Camera3D
var _rims: Array[OmniLight3D] = []
var _puppets: Array[StagingPuppet] = []
var _gs: QuizGameState
var _ready_to_render := false
## 人形（1 / 2）ごとの置き場所：{x, yaw, left, pose（CUTIN_POSES の 1 つ）}
var _spots := {}
## 人形ごとの踊り：ResultWinnerDance.make_clip ＋ {emote, path}
var _dances := {}
## 読み終えるのを待っている踊り：人形 → {emote, path}
var _wanted := {}
## スレッドで読んでいる FBX（path → true）と、読み終えたもの（path → PackedScene）
var _requested := {}
var _scenes := {}
## 枠を決めるために見る点 [人形, 踊りの時刻（-1＝止めたポーズ）]。空なら決め終えている
var _fit_queue: Array = []
var _fit_scale := 1.0
var _dancing := false
var _clock := 0.0
var _since_draw := 0.0


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


func _exit_tree() -> void:
	# 読みかけの FBX は受け取っておく（受け取らないと読み込みの側に残る）
	for path: String in _requested.keys():
		ResourceLoader.load_threaded_get(path)
	_requested.clear()


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


## 帽子・肌・踊るエモートを決めて、左右を 1 回ずつ描く。my_slot：自分のスロット（左に置く人形）。
## my_pose / their_pose は CUTIN_POSES の番号（踊れないときのポーズ）。my_skin / their_skin は PlayerSkin 形式（{} はスロットの標準色）。
## my_emote / their_emote は踊るエモート（EMOTE_NONE ならポーズで止める）。FBX はスレッドで読み、読み終えたら描き直す。
func prepare(
	my_slot: int, my_hat: int, their_hat: int, my_pose: int, their_pose: int,
	my_skin: Dictionary = {}, their_skin: Dictionary = {},
	my_emote: int = EmoteData.EMOTE_NONE, their_emote: int = EmoteData.EMOTE_NONE,
) -> void:
	if not _ready_to_render:
		return
	var left_index := 2 if my_slot == 2 else 1
	var right_index := 3 - left_index
	var hats := {left_index: my_hat, right_index: their_hat}
	var poses := {left_index: my_pose, right_index: their_pose}
	var skins := {left_index: my_skin, right_index: their_skin}
	var emotes := {left_index: my_emote, right_index: their_emote}
	_dancing = false
	_clock = 0.0
	for index: int in [1, 2]:
		var puppet := _puppets[index - 1]
		puppet.set_visible(true)
		puppet.set_hat(clampi(int(hats[index]), 0, HatData.HAT_COUNT - 1))
		puppet.set_skin(skins[index])
		var is_left := index == left_index
		var x := -SPACING * 0.5 if is_left else SPACING * 0.5
		# 体を真ん中（画面の内側）へ向ける：左のキャラは右へ、右のキャラは左へ
		_spots[index] = {
			"x": x, "yaw": deg_to_rad(TURN_DEG if is_left else -TURN_DEG), "left": is_left,
			"pose": OnlineStagingTimeline.CUTIN_POSES[clampi(int(poses[index]), 0, OnlineStagingTimeline.CUTIN_POSES.size() - 1)],
		}
		var rim := _rims[index - 1]
		rim.light_color = OnlineHeliportStage.slot_color(index).lightened(0.2)
		rim.position = Vector3(x + (-0.9 if is_left else 0.9), 1.9, -1.4)
		_want_dance(index, int(emotes[index]))
	_poll_loads()
	_begin_fit()
	# 止めたポーズだけなら軽いので、すぐ枠を決める（踊りは _process で何フレームかに分けて見る）
	if _dances.is_empty():
		_step_fit(_fit_queue.size())
	else:
		_pose_all(0.0)
		_draw()


## 踊りを読み終え、枠も決め終えたか。
func is_ready() -> bool:
	return _requested.is_empty() and _wanted.is_empty() and _fit_queue.is_empty()


## 左右が踊るエモート（踊っていない人形は EMOTE_NONE）。[左, 右]
func dance_emotes() -> Array[int]:
	var out: Array[int] = []
	for left: bool in [true, false]:
		var emote := EmoteData.EMOTE_NONE
		for index: int in _spots:
			if bool(_spots[index].left) == left:
				var dance: Dictionary = _dances.get(index, {})
				var want: Dictionary = _wanted.get(index, {})
				emote = int(dance.get("emote", want.get("emote", EmoteData.EMOTE_NONE)))
		out.append(emote)
	return out


## カットインが始まるときに呼ぶ：読みかけの踊りを待ち（ふつうは合流のあいだに済んでいる）、最初から踊らせる。
func start_dance() -> void:
	for path: String in _requested.keys():
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		if scene != null:
			_scenes[path] = scene
	_requested.clear()
	_poll_loads()
	if not _fit_queue.is_empty():
		_step_fit(_fit_queue.size())
	_clock = 0.0
	_since_draw = 0.0
	_dancing = not _dances.is_empty()
	_pose_all(0.0)
	_draw()


## カットインのあいだ（OnlineCutin._process）に呼ぶ：踊りを進め、DANCE_FPS ごとに描き直す。draw_now は今すぐ描く。
func advance(delta: float, draw_now: bool = false) -> void:
	if not _dancing:
		return
	_clock += delta
	_since_draw += delta
	if not draw_now and _since_draw < 1.0 / DANCE_FPS:
		return
	_since_draw = 0.0
	_pose_all(_clock)
	_draw()


func _process(_delta: float) -> void:
	if not _requested.is_empty() or not _wanted.is_empty():
		_poll_loads()
	if not _fit_queue.is_empty():
		_step_fit(FIT_SAMPLES_PER_FRAME)


## index の人形に emote を踊らせる。同じ FBX の踊りなら作り直さない。
func _want_dance(index: int, emote: int) -> void:
	var id := EmoteData.normalize_emote_id(emote)
	var path := EmoteData.get_emote_fbx(id) if id > EmoteData.EMOTE_NONE and id < EmoteData.EMOTE_COUNT else ""
	var current: Dictionary = _dances.get(index, {})
	if not current.is_empty() and str(current.path) == path:
		current["emote"] = id
		return
	_drop_dance(index)
	_wanted.erase(index)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_wanted[index] = {"emote": id, "path": path}
	if _scenes.has(path) or _requested.has(path):
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_requested[path] = true
	else:
		_wanted.erase(index)


func _drop_dance(index: int) -> void:
	var dance: Dictionary = _dances.get(index, {})
	if not dance.is_empty() and is_instance_valid(dance.source):
		(dance.source as Node).queue_free()
	_dances.erase(index)


## 読み終えた FBX を受け取り、待っている人形の踊りを作る。作ったら枠を決め直す。
func _poll_loads() -> void:
	for path: String in _requested.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_requested.erase(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED and status != ResourceLoader.THREAD_LOAD_FAILED:
			continue
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		if scene != null:
			_scenes[path] = scene
	var made := false
	for index: int in _wanted.keys():
		var want: Dictionary = _wanted[index]
		if _requested.has(want.path):
			continue
		_wanted.erase(index)
		if _scenes.has(want.path):
			made = _make_dance(index, want) or made
	if made:
		_begin_fit()


func _make_dance(index: int, want: Dictionary) -> bool:
	var source := (_scenes[want.path] as PackedScene).instantiate() as Node3D
	if source == null:
		return false
	source.name = "Dance%d" % index
	source.visible = false
	source.process_mode = Node.PROCESS_MODE_DISABLED
	_world_root.add_child(source)
	var clip := ResultWinnerDance.make_clip(source)
	if clip.is_empty():
		source.queue_free()
		return false
	clip["emote"] = want.emote
	clip["path"] = want.path
	_dances[index] = clip
	return true


## 枠を決め直す：止めたポーズか、踊りの 1 回分を FIT_SAMPLES 点で見る。
func _begin_fit() -> void:
	_fit_queue.clear()
	_fit_scale = 1.0
	for index: int in _spots:
		var dance: Dictionary = _dances.get(index, {})
		if dance.is_empty():
			_fit_queue.append([index, -1.0])
			continue
		for k in range(FIT_SAMPLES):
			_fit_queue.append([index, float(dance.duration) * float(k) / float(FIT_SAMPLES)])


## 枠を決める点を budget 個だけ見て、今の時刻の姿に戻す。見終えたらカメラを置き直して描く。
func _step_fit(budget: int) -> void:
	var count := 0
	while not _fit_queue.is_empty() and count < budget:
		var item: Array = _fit_queue.pop_front()
		_pose_one(int(item[0]), float(item[1]))
		_fit_scale = maxf(_fit_scale, _needed_scale(int(item[0])))
		count += 1
	_pose_all(_clock)
	if _fit_queue.is_empty():
		frame_scale = minf(_fit_scale, MAX_FRAME_SCALE)
		_place_cameras()
		_draw()


func _pose_all(t: float) -> void:
	for index: int in _spots:
		_pose_one(index, t)


## index の人形を時刻 t の踊り（踊りが無いか t < 0 なら止めたポーズ）にして立たせる。
func _pose_one(index: int, t: float) -> void:
	var puppet := _puppets[index - 1]
	var spot: Dictionary = _spots[index]
	var at := Vector3(float(spot.x), 0.0, 0.0)
	var dance: Dictionary = _dances.get(index, {})
	if dance.is_empty() or t < 0.0:
		var pose: Array = spot.pose
		if not puppet.pose(str(pose[0]), float(pose[2]), int(pose[1])):
			puppet.pose("Idle_Loop", 0.3)
		puppet.stand_at(at, float(spot.yaw), 0.0)
		return
	var skeleton := dance.skeleton as Skeleton3D
	(dance.ap as AnimationPlayer).seek(fposmod(t, float(dance.duration)), true)
	skeleton.force_update_all_bone_transforms()
	puppet.pose_skeleton(skeleton, dance.bones)
	var drift: Vector3 = skeleton.get_bone_global_pose(dance.bones.hips).origin - (dance.origin as Vector3)
	var sway := Vector3(clampf(-drift.x, -SWAY_X, SWAY_X), 0.0, clampf(drift.z, -SWAY_Z, SWAY_Z))
	puppet.stand_dancing(at, float(spot.yaw), 0.0, sway, ResultWinnerDance.contact_lift(skeleton, dance.bones, int(dance.emote)))


## 仕様書の枠のカメラ（倍率 1）。
static func _base_camera(x: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, CAMERA_HEIGHT, CAMERA_DISTANCE)).looking_at(Vector3(x, LOOK_HEIGHT, 0.0), Vector3.UP)


## index の人形の今の姿（体と帽子の全部）が余白の内側に入る、足もとを中心にカメラを引く倍率（1 より小さくしない）。
## 足もと g を中心に倍率 s で引いた絵は、点 p を g + (p - g) / s に置いて倍率 1 のカメラで撮った絵と同じなので、
## 上下左右の端それぞれについて s の下限が 1 次式で解ける（カメラの座標。前は -Z）。
func _needed_scale(index: int) -> float:
	var x := float(_spots[index].x)
	var view := _base_camera(x).affine_inverse()
	var g := view * Vector3(x, 0.0, 0.0)
	var ty := tan(deg_to_rad(CAMERA_FOV) * 0.5) * (1.0 - 2.0 * FRAME_MARGIN)
	var tx := ty * float(VIEW_SIZE.x) / float(VIEW_SIZE.y)
	var top := -(g.y + ty * g.z)
	var bottom := g.y - ty * g.z
	var right := -(g.x + tx * g.z)
	var left := g.x - tx * g.z
	var need := 1.0
	var parts := _puppets[index - 1].parts()
	for list: Array in [parts.get("meshes", []), parts.get("hat_meshes", [])]:
		for item: Variant in list:
			if not is_instance_valid(item):
				continue
			var mesh := item as MeshInstance3D
			if mesh == null or not mesh.is_visible_in_tree():
				continue
			var xf := view * mesh.global_transform
			var aabb := mesh.get_aabb()
			for corner in range(8):
				var d := xf * aabb.get_endpoint(corner) - g
				need = maxf(need, maxf(maxf((d.y + ty * d.z) / top, (ty * d.z - d.y) / bottom),
					maxf((d.x + tx * d.z) / right, (tx * d.z - d.x) / left)))
	return need


func _place_cameras() -> void:
	for index: int in _spots:
		var spot: Dictionary = _spots[index]
		var x := float(spot.x)
		var ground := Vector3(x, 0.0, 0.0)
		var cam := _cam_left if bool(spot.left) else _cam_right
		cam.global_position = ground + (Vector3(x, CAMERA_HEIGHT, CAMERA_DISTANCE) - ground) * frame_scale
		cam.look_at(ground + (Vector3(x, LOOK_HEIGHT, 0.0) - ground) * frame_scale, Vector3.UP)


func _draw() -> void:
	view_left.render_target_update_mode = SubViewport.UPDATE_ONCE
	view_right.render_target_update_mode = SubViewport.UPDATE_ONCE


func left_texture() -> Texture2D:
	return view_left.get_texture()


func right_texture() -> Texture2D:
	return view_right.get_texture()
