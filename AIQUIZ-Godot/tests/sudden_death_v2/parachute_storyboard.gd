extends Node

## サドンデス「ひらけ！パラシュート」の絵コンテのコマを、本物のプレイヤー（ブロックマン）・ヘリ・ハテナ・海・空・雲で撮る。
## パラシュート・着地台・水柱は本制作の素材（chute.glb・landing_float.glb・splash.glb）。
## 仕様書：docs/sudden_death_v2/parachute.md
##   Godot --path . --resolution 1600x900 --script res://tests/sudden_death_v2/parachute_storyboard_bootstrap.gd [-- only=p01,p05] [key=value]
## 出力：artifacts/sudden_death_v2/parachute/storyboard/raw/<名前>.png（HUD と文字は make_parachute_storyboard.py が重ねる）。

const StageScript = preload("res://scripts/world/stage_environment.gd")
const OUT := "res://artifacts/sudden_death_v2/parachute/storyboard/raw/"
const NAMES := [
	"p01_cabin", "p02_drop", "p03_freefall", "p05_main", "p06_correct", "p07_wrong",
	"p09_final", "p10_open", "p11_splash", "p12_landing", "p13_dance",
	"r1_correct", "r2_wrong", "r3_win",
]
## ルールカードの 3 枚の絵（r1〜r3 のコマから切り抜いて素材に書く）。
const RULE_CARD_DIR := "res://assets/sudden_death/parachute/rule_card/"
const RULE_CARD := {"r1_correct": "rule_correct", "r2_wrong": "rule_wrong", "r3_win": "rule_win"}
## 撮影の場所（海の上、本編の舞台から離れた所）。
const SITE := Vector3(0.0, 0.0, 150.0)
const SEA_Y := StageConstants.OCEAN_SURFACE_Y
## ブロックマンの足の裏は、根から 1.32 m 下。
const PLAYER_FOOT := 1.32
const FLOAT_GLB := "res://assets/sudden_death/parachute/landing_float/landing_float.glb"
## 着地台の着地面の中心（_raft に渡す高さから。喫水線の 0.572 m 上）。
const LAND_ABOVE_RAFT := 0.572 - 0.25
const AXES := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}

const _HEAD_UP := 64.0
## 腹ばいの落下（ボックスの姿勢）。頭の x は − で頭のてっぺんが後ろへ（顔が前を向く）。関節・軸・角度（体の向きの軸。heli_board_photos.gd と同じ決まり）。
const POSE_BOX := [
	["spine", "x", -16.0], ["head_pivot", "x", -_HEAD_UP],
	["l_shoulder", "z", -82.0], ["l_shoulder", "x", 14.0], ["l_elbow", "z", -78.0],
	["r_shoulder", "z", 82.0], ["r_shoulder", "x", 14.0], ["r_elbow", "z", 78.0],
	["l_hip", "z", -16.0], ["r_hip", "z", 16.0], ["l_hip", "x", 10.0], ["r_hip", "x", 10.0],
	["l_knee", "x", 58.0], ["r_knee", "x", 58.0],
]
## ハッチから落ちた直後（立ったままバンザイ、脚がばたつく）。
const POSE_DROP := [
	["l_shoulder", "z", -150.0], ["r_shoulder", "z", 140.0], ["l_elbow", "z", -20.0], ["r_elbow", "z", 30.0],
	["l_hip", "x", -30.0], ["l_knee", "x", 50.0], ["r_hip", "x", 15.0], ["r_knee", "x", 20.0],
	["head_pivot", "x", 12.0],
]
## きりもみ（腕を振り回す）。
const POSE_SPIN := [
	["spine", "x", -18.0], ["spine", "y", 20.0],
	["l_shoulder", "z", -160.0], ["l_shoulder", "x", -40.0], ["r_shoulder", "z", 35.0], ["r_shoulder", "x", 50.0],
	["r_elbow", "z", 60.0], ["l_hip", "x", -50.0], ["l_knee", "x", 30.0], ["r_hip", "z", 30.0], ["r_knee", "x", 70.0],
	["head_pivot", "z", 18.0],
]
## パラシュートの下（両手でブレークのひもを持つ、脚は少し前）。
const POSE_CANOPY := [
	["l_shoulder", "z", -150.0], ["r_shoulder", "z", 150.0], ["l_elbow", "z", 25.0], ["r_elbow", "z", -25.0],
	["l_hip", "x", -18.0], ["r_hip", "x", -12.0], ["l_knee", "x", 22.0], ["r_knee", "x", 14.0],
	["head_pivot", "x", -8.0],
]
## 敗者のあわてる落下（頭が下がり、手足をばたつかせる）。
const POSE_PANIC := [
	["l_shoulder", "z", -165.0], ["r_shoulder", "z", 120.0], ["r_elbow", "z", 50.0], ["l_elbow", "z", -35.0],
	["l_hip", "x", -45.0], ["l_knee", "x", 80.0], ["r_hip", "x", 25.0], ["r_hip", "z", 20.0],
	["head_pivot", "x", 20.0], ["spine", "x", -10.0],
]
## 浮き台での勝利のポーズ。
const POSE_WIN := [
	["l_shoulder", "z", -160.0], ["r_shoulder", "z", 160.0], ["l_elbow", "z", -12.0], ["r_elbow", "z", 12.0],
	["l_hip", "z", -8.0], ["r_hip", "z", 8.0], ["head_pivot", "x", 10.0],
]
## 座席（ヘリの左の席）。
const POSE_SEAT := [
	["l_hip", "x", -80.0], ["r_hip", "x", -80.0], ["l_knee", "x", 80.0], ["r_knee", "x", 80.0],
	["l_shoulder", "x", -30.0], ["r_shoulder", "x", -30.0], ["l_elbow", "x", -40.0], ["r_elbow", "x", -40.0],
]

var stage: Node3D
var camera: Camera3D
var props: Node3D
var report := {}
var only: PackedStringArray = []
var vars := {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.trim_prefix("only=").split(",")
		elif "=" in arg:
			vars[arg.get_slice("=", 0)] = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build()
	await _frames(20)
	for name: String in NAMES:
		if not only.is_empty() and not only.has(name.get_slice("_", 0)) and not only.has(name):
			continue
		props = Node3D.new()
		props.name = "Shot_" + name
		add_child(props)
		await call("_shot_" + name)
		props.queue_free()
		await get_tree().process_frame
	print("PARACHUTE_STORYBOARD ", JSON.stringify(report))
	get_tree().quit()


func _build() -> void:
	stage = StageScript.new()
	add_child(stage)
	stage.build(stage.gameplay_build_config())
	# 空・太陽・海だけ残す（空のセットと同じく、本編の舞台は隠す）
	for child: Node in stage.get_children():
		if child is Node3D and not (String(child.name) in ["DirectionalLight3D", "Ocean"]):
			(child as Node3D).visible = false
	camera = Camera3D.new()
	camera.far = 4000.0
	add_child(camera)
	camera.make_current()


func _v(key: String, fallback: float) -> float:
	return float(vars[key]) if vars.has(key) else fallback


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _shot(name: String, eye: Vector3, target: Vector3, fov: float, up := Vector3.UP) -> void:
	camera.fov = fov
	camera.look_at_from_position(eye, target, up)
	await _frames(6)
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT + name + ".png")
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	report[name] = path
	if RULE_CARD.has(name):
		# ルールカードの絵：真ん中を 4:3 で切り抜き、960×720 にして素材へ（HUD が角を丸く切り抜いて描く）
		var w := int(round(image.get_height() * 4.0 / 3.0))
		var card := image.get_region(Rect2i((image.get_width() - w) / 2, 0, w, image.get_height()))
		card.resize(960, 720, Image.INTERPOLATE_LANCZOS)
		var card_path := ProjectSettings.globalize_path(RULE_CARD_DIR + String(RULE_CARD[name]) + ".png")
		card.save_png(card_path)
		report[name + "_card"] = card_path


# ---------------------------------------------------------------- 人物

## ブロックマン。center は腰のあたり（根）、head は頭の向き、front は胸の向き（世界）。
func _player(is_p1: bool, center: Vector3, head: Vector3, front: Vector3, pose: Array = []) -> Dictionary:
	var root := Node3D.new()
	props.add_child(root)
	var y := head.normalized()
	var z := front.slide(y).normalized()
	var x := y.cross(z).normalized()
	root.global_transform = Transform3D(Basis(x, y, z), center)
	var parts: Dictionary = EmoteBlockmanPreview.build_player_skeleton(is_p1, root, HatData.HAT_PROPELLER if is_p1 else HatData.HAT_FOX)
	parts["root"] = root
	for row: Array in pose:
		_turn(parts, String(row[0]), AXES[row[1]], float(row[2]))
	_pack(parts, is_p1)
	return parts


func _turn(parts: Dictionary, joint: String, axis: Vector3, deg: float) -> void:
	if not parts.has(joint):
		return
	var node := parts[joint] as Node3D
	var root := parts["root"] as Node3D
	var a := (root.global_basis * axis).normalized()
	node.global_basis = Basis(a, deg_to_rad(deg)) * node.global_basis


## 背中のコンテナ（本物の素材 chute.glb の Container）。
func _pack(parts: Dictionary, is_p1: bool) -> void:
	var spine := parts["spine"] as Node3D
	var container := _proto(is_p1).container_node()
	if container != null:
		spine.add_child(container)
		container.position = Vector3(0.0, 0.22, -0.12)


## コンテナを写すための、見せないパラシュート（1P / 2P の色ごとに 1 つ）。
var _protos := {}


func _proto(is_p1: bool) -> ParachuteCanopy:
	if not _protos.has(is_p1):
		var c := ParachuteCanopy.new()
		add_child(c)
		c.build(is_p1)
		c.visible = false
		_protos[is_p1] = c
	return _protos[is_p1]


## 肩のあたり（ライザーのつけ根、世界）。
func _shoulders(parts: Dictionary) -> Vector3:
	var spine := parts["spine"] as Node3D
	return spine.global_transform * Vector3(0.0, 0.45, -0.1)


# ---------------------------------------------------------------- 小道具（本物の素材）

## パラシュート（本物の素材 chute.glb、ParachuteCanopy）。stage 3＝全開、2＝半分（しわ）、1＝袋とパイロットシュート。
## up は体の上（ライザーの向き）、side は体の横（翼の幅の向き）。deflate はしぼみかけ（袋の形へ少し寄せる）。
func _canopy(parts: Dictionary, is_p1: bool, stage_level: int, up: Vector3, side: Vector3, deflate := 0.0) -> ParachuteCanopy:
	var c := ParachuteCanopy.new()
	props.add_child(c)
	c.build(is_p1)
	c.set_stage(stage_level)
	c.snap()
	if deflate > 0.0:
		c.pose_weights(0.22 * deflate, 1.0)
	_place(c, parts, up, side)
	return c


func _place(c: ParachuteCanopy, parts: Dictionary, up: Vector3, side: Vector3) -> void:
	up = up.normalized()
	side = side.slide(up).normalized()
	var fwd := side.cross(up).normalized()
	c.place(Transform3D(Basis(side, up, -fwd), _shoulders(parts)), 0.0)


## 着地台（本物の素材 assets/sudden_death/parachute/landing_float/）。at は喫水線の 0.25 m 上（仮の形のときの呼び方のまま）。
func _raft(at: Vector3) -> void:
	var model := (load(FLOAT_GLB) as PackedScene).instantiate() as Node3D
	props.add_child(model)
	model.global_position = Vector3(at.x, at.y - 0.25, at.z)


## 水柱（本物の素材 splash.glb、WaterSplash）。at は水面の 0.25 m 上（仮の形のときの呼び方のまま）。height は使わない。
func _splash(at: Vector3, _height := 9.0, time := -1.0) -> void:
	var splash := WaterSplash.new()
	props.add_child(splash)
	splash.build()
	splash.global_position = Vector3(at.x, at.y - 0.25, at.z)
	splash.pose_at(time if time >= 0.0 else _v("splash_t", 0.55))


## 敗者の「ハンカチ」（予備のパラシュートのつもりが小さな布。本物の素材）。
func _hanky(parts: Dictionary, up: Vector3) -> void:
	var c := ParachuteCanopy.new()
	props.add_child(c)
	c.build(false)
	c.show_hanky(true)
	c.snap()
	_place(c, parts, up, Vector3(-1, 0, 0))


func _heli(is_p1: bool, at: Vector3, forward: Vector3) -> OnlineHeliportHelicopter:
	var heli := OnlineHeliportHelicopter.new()
	props.add_child(heli)
	heli.setup(PlayerController.P1_BODY if is_p1 else PlayerController.P2_BODY, true, false)
	heli.global_position = at
	heli.look_at(at + forward, Vector3.UP)
	return heli


func _clouds(at: Vector3) -> void:
	var clouds := StagingClouds.new()
	props.add_child(clouds)
	clouds.build("high", Vector3(0, 0, -1))
	clouds.global_position = at


# ---------------------------------------------------------------- コマ

## 機内（並んで飛ぶ2機の正面）。
func _shot_p01_cabin() -> void:
	var y := 160.0
	var h1 := _heli(true, SITE + Vector3(6.0, y, 0.0), Vector3(0, 0, -1))
	var h2 := _heli(false, SITE + Vector3(-6.0, y, 0.0), Vector3(0, 0, -1))
	_clouds(SITE + Vector3(0, y, 0))
	for pair: Array in [[h1, true], [h2, false]]:
		var heli := pair[0] as OnlineHeliportHelicopter
		await get_tree().process_frame
		var seat := heli.global_transform * heli.marker("MK_SeatPassenger")
		var fwd := -seat.basis.z
		_player(pair[1], seat.origin + Vector3(0, _v("seat_y", 0.45), 0), Vector3.UP, Vector3(fwd.x, 0, fwd.z), POSE_SEAT)
		heli.set_belt("L", 1.0)
	await _shot("p01_cabin", SITE + Vector3(_v("c1x", 0.0), y + _v("c1y", 1.0), _v("c1z", -13.0)), SITE + Vector3(0, y - 0.6, 0), _v("fov", 50.0))


## 床のハッチが開いて落ちる（ヘリの真下から見上げる）。
func _shot_p02_drop() -> void:
	var y := 160.0
	var h1 := _heli(true, SITE + Vector3(6.0, y, 0.0), Vector3(0, 0, -1))
	var h2 := _heli(false, SITE + Vector3(-6.0, y, 0.0), Vector3(0, 0, -1))
	h1.set_hatch(1.0)
	h2.set_hatch(1.0)
	_clouds(SITE + Vector3(0, y + 10.0, 0))
	await get_tree().process_frame
	for pair: Array in [[h1, true], [h2, false]]:
		var heli := pair[0] as OnlineHeliportHelicopter
		var hatch := heli.global_position + Vector3(0, -_v("drop_y", 7.0), 0)
		_player(pair[1], hatch, Vector3.UP, Vector3(0, 0, 1), POSE_DROP)
	await _shot("p02_drop", SITE + Vector3(0.0, y - _v("c2d", 15.0), _v("c2z", -11.0)), SITE + Vector3(0, y - 3.0, 0), _v("fov", 62.0))


## 落下の追いかけ（腹ばい、下から見上げる。頭は画面の上＝-Z）。
func _freefall_pair(y: float, p1_lift := 0.0, p2_lift := 0.0, p2_pose: Array = POSE_BOX, p2_roll := 0.0) -> Array:
	# 頭を少し上げた腹ばい（カメラマンと向き合う）
	var head := Vector3(0, _v("head_up", 0.35), -1).normalized()
	var front := Vector3(0, -1, 0)
	var p1 := _player(true, SITE + Vector3(1.7, y + p1_lift, 0), head, front, POSE_BOX)
	var p2_head := head.rotated(Vector3.UP, p2_roll)
	var p2 := _player(false, SITE + Vector3(-1.7, y + p2_lift, 0), p2_head, front.rotated(p2_head, p2_roll * 0.5), p2_pose)
	return [p1, p2]


func _look_up(name: String, y: float, distance: float, fov: float, z := 0.0) -> void:
	await _shot(name, SITE + Vector3(0, y - distance, z), SITE + Vector3(0, y, z), fov, Vector3(0, 0, -1))


## 本戦の画：2人の頭の前（-Z）、少し上から。背景は下の海と水平線。
func _face(name: String, y: float, distance: float, fov: float, lift := 1.6, aim := 1.2) -> void:
	await _shot(name, SITE + Vector3(0, y + lift + _v("lift", 0.0), -distance), SITE + Vector3(0, y + aim + _v("aim", 0.0), 0.6), fov)


func _shot_p03_freefall() -> void:
	var y := 120.0
	_freefall_pair(y)
	_heli(true, SITE + Vector3(10.0, y + 70.0, -10.0), Vector3(0, 0, -1))
	_heli(false, SITE + Vector3(-10.0, y + 70.0, -10.0), Vector3(0, 0, -1))
	_clouds(SITE + Vector3(0, y + 5.0, 0))
	await _shot("p03_freefall", SITE + Vector3(0, y - _v("d3", 6.0), -_v("z3", 8.0)), SITE + Vector3(0, y + 6.0, 0), _v("fov", 64.0))


func _shot_p05_main() -> void:
	var y := SEA_Y + 420.0
	_freefall_pair(y)
	_clouds(SITE + Vector3(0, y - 120.0, 0))
	await _face("p05_main", y, _v("d5", 7.2), _v("fov", 50.0), 1.1)


func _shot_p06_correct() -> void:
	var y := SEA_Y + 380.0
	var pair := _freefall_pair(y, 1.2)
	_canopy(pair[0], true, 1, Vector3(0, 1, 0.25), Vector3(-1, 0, 0))
	_clouds(SITE + Vector3(0, y - 120.0, 0))
	await _face("p06_correct", y, _v("d6", 8.6), _v("fov", 52.0), 1.8, 2.0)


func _shot_p07_wrong() -> void:
	var y := SEA_Y + 340.0
	var pair := _freefall_pair(y, 2.4, 0.0, POSE_SPIN, deg_to_rad(70.0))
	_canopy(pair[0], true, 2, Vector3(0, 1, 0.2), Vector3(-1, 0, 0))
	_canopy(pair[1], false, 2, Vector3(0.3, 1, 0.1), Vector3(-1, 0, 0.3), 0.7)
	_clouds(SITE + Vector3(0, y - 120.0, 0))
	await _face("p07_wrong", y, _v("d7", 12.5), _v("fov", 54.0), 2.6, 3.6)


## 高度150m の最後の1問（浮き台から見上げる。スローモーション）。
func _shot_p09_final() -> void:
	var y := SEA_Y + 20.0
	_raft(Vector3(SITE.x, SEA_Y + 0.25, SITE.z))
	var head := Vector3(0, 0, -1)
	var p1 := _player(true, SITE + Vector3(2.4, y + 3.0, -1.0), head, Vector3.DOWN, POSE_BOX)
	_canopy(p1, true, 2, Vector3(0, 1, 0.2), Vector3(-1, 0, 0))
	var p2 := _player(false, SITE + Vector3(-2.4, y, -1.0), head, Vector3.DOWN, POSE_BOX)
	_canopy(p2, false, 2, Vector3(0, 1, 0.2), Vector3(-1, 0, 0))
	await _shot("p09_final", SITE + Vector3(_v("c9x", 0.0), SEA_Y + _v("c9y", 1.6), _v("c9z", 4.2)), SITE + Vector3(0, y, -1.0), _v("fov", 48.0))


## 決着：勝者のパラシュートが全開で上へ抜け、敗者はハンカチ。
func _shot_p10_open() -> void:
	var y := 90.0
	var p1 := _player(true, SITE + Vector3(1.4, y + 8.0, -0.5), Vector3.UP, Vector3(0, 0, 1), POSE_CANOPY)
	_canopy(p1, true, 3, Vector3.UP, Vector3(-1, 0, 0))
	var p2 := _player(false, SITE + Vector3(-1.4, y, 0.0), Vector3(0, 0.4, -1), Vector3.DOWN, POSE_PANIC)
	_hanky(p2, Vector3(0.2, 1, -0.6))
	_clouds(SITE + Vector3(0, y + 5.0, 0))
	await _shot("p10_open", SITE + Vector3(_v("c10x", -1.0), y - _v("c10d", 4.0), _v("c10z", 7.5)), SITE + Vector3(0, y + 3.0, 0), _v("fov", 66.0))


## 敗者が海へ（水柱）。勝者は浮き台へ降りてくる。
func _shot_p11_splash() -> void:
	var raft := Vector3(SITE.x, SEA_Y + 0.25, SITE.z)
	_raft(raft)
	_splash(raft + Vector3(-9.0, 0, 3.0), 11.0)
	var p1 := _player(true, raft + Vector3(2.0, 14.0, 1.0), Vector3.UP, Vector3(0, 0, 1), POSE_CANOPY)
	_canopy(p1, true, 3, Vector3.UP, Vector3(-1, 0, 0))
	await _shot("p11_splash", raft + Vector3(_v("c11x", -2.0), _v("c11y", 3.0), _v("c11z", 24.0)), raft + Vector3(-2.5, 7.0, 0), _v("fov", 55.0))


## 勝者が浮き台に着地してポーズ（パラシュートは後ろの床に落ちる）。
func _shot_p12_landing() -> void:
	var raft := Vector3(SITE.x, SEA_Y + 0.25, SITE.z)
	_raft(raft)
	var p1 := _player(true, raft + Vector3(0, LAND_ABOVE_RAFT + PLAYER_FOOT, 0), Vector3.UP, Vector3(0, 0, 1), POSE_WIN)
	var landed := _canopy(p1, true, 3, Vector3.UP, Vector3(-1, 0, 0))
	# 着地のあと：パラシュートは人の後ろの床へ落ちる（ParachutePresenter と同じ）
	landed.drop_to(Transform3D(Basis.IDENTITY, raft + Vector3(0.0, LAND_ABOVE_RAFT, -0.45)))
	landed.collapse = 1.0
	_place(landed, p1, Vector3.UP, Vector3(-1, 0, 0))
	await _shot("p12_landing", raft + Vector3(_v("c12x", 3.0), _v("c12y", 1.8), _v("c12z", 7.5)), raft + Vector3(0, 1.6, -1.0), _v("fov", 52.0))


## 勝者が着地台の上でエモートを踊る（本物のエモートの FBX を ResultWinnerDance で当てる）。
func _shot_p13_dance() -> void:
	var raft := Vector3(SITE.x, SEA_Y + 0.25, SITE.z)
	_raft(raft)
	var floor_y := raft.y + LAND_ABOVE_RAFT - 0.01
	var root := Node3D.new()
	props.add_child(root)
	root.global_position = raft + Vector3(0.3, floor_y - raft.y + PLAYER_FOOT, 0.2)
	var parts: Dictionary = EmoteBlockmanPreview.build_player_skeleton(true, root, HatData.HAT_PROPELLER)
	_pack(parts.merged({"root": root}), true)
	var eye := raft + Vector3(_v("c13x", 4.2), _v("c13y", 2.1), _v("c13z", 6.4))
	camera.fov = _v("fov", 44.0)
	camera.look_at_from_position(eye, raft + Vector3(0.0, 1.45, 0.0))
	var dance := ResultWinnerDance.new()
	dance.setup(props, int(_v("emote", EmoteData.EMOTE_GANGNAM)))
	await get_tree().process_frame
	dance.apply(root, parts, camera, ResultWinnerDance.BLEND_END + _v("dance_t", 1.35), floor_y)
	await _shot("p13_dance", eye, raft + Vector3(0.0, 1.45, 0.0), _v("fov", 44.0))
	dance.clear()


# ---------------------------------------------------------------- ルールカードの図（真ん中を 4:3 に切り抜いて使う）
# 3 枚とも同じ 1P（オレンジ）で「正解で開く → まちがえるとしぼむ → 全開で着地」の話にする。どれも水平線を下に入れて、
# 色の体が空に埋もれないようにする。1 枚目の右上は HUD が段の印（3 つのパラシュート）を重ねるので空けておく。

func _shot_r1_correct() -> void:
	var y := 120.0
	var p1 := _player(true, SITE + Vector3(0, y, 0), Vector3.UP, Vector3(0, 0, 1), POSE_CANOPY)
	_canopy(p1, true, 3, Vector3.UP, Vector3(-1, 0, 0))
	await _shot("r1_correct", SITE + Vector3(_v("r1x", 0.6), y + _v("r1y", 0.6), _v("r1z", 14.6)), SITE + Vector3(0, y + _v("r1t", 3.8), 0), _v("fov", 44.0))


## まちがえた：半分にしぼんだパラシュート（しわ・ばたつき）の下で、体が傾いてきりもみ。
func _shot_r2_wrong() -> void:
	var y := 120.0
	var head := Vector3(0.55, 1.0, -0.15).normalized()
	var p1 := _player(true, SITE + Vector3(0, y, 0), head, Vector3(-0.35, 0.2, 1.0), POSE_SPIN)
	_canopy(p1, true, 2, Vector3(0.42, 1.0, 0.05), Vector3(-1, 0.4, 0.15))
	await _shot("r2_wrong", SITE + Vector3(_v("r2x", -0.6), y + _v("r2y", 0.2), _v("r2z", 12.5)), SITE + Vector3(_v("r2tx", 0.8), y + _v("r2t", 2.7), 0), _v("fov", 44.0))


## 勝った：着地台の上でバンザイ。パラシュートは後ろの床に落ち、奥で相手の水柱。
func _shot_r3_win() -> void:
	var raft := Vector3(SITE.x, SEA_Y + 0.25, SITE.z)
	_raft(raft)
	var p1 := _player(true, raft + Vector3(0, LAND_ABOVE_RAFT + PLAYER_FOOT, 0), Vector3.UP, Vector3(0, 0, 1), POSE_WIN)
	var landed := _canopy(p1, true, 3, Vector3.UP, Vector3(-1, 0, 0))
	landed.drop_to(Transform3D(Basis.IDENTITY, raft + Vector3(0.0, LAND_ABOVE_RAFT, -0.45)))
	landed.collapse = 1.0
	_place(landed, p1, Vector3.UP, Vector3(-1, 0, 0))
	_splash(raft + Vector3(_v("r3sx", -10.0), 0, _v("r3sz", -9.0)), 8.0, _v("r3st", 1.0))
	await _shot("r3_win", raft + Vector3(_v("r3x", 3.6), _v("r3y", 3.9), _v("r3z", 8.6)), raft + Vector3(_v("r3tx", -0.5), _v("r3t", 2.6), -1.0), _v("fov", 46.0))
