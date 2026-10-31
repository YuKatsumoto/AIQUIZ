extends "res://tests/pv_capture/pv_take_base.gd"

## PV S20「自分だけのキャラ」案 B（帽子と色）：本物のオンライン画面の「スキン設定」を、通信なしで撮る（6 拍）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s20_skin quality=ultra sub=8
## オンライン画面（OnlineMenu）は、開くだけならリレーにつながない（つなぐのは「マッチング開始」「ともだちコード」を押したとき）。
## それでも念のため NetworkManager.relay_url を使えない先（127.0.0.1:9）に差し替えてから開く。
## テロップ「帽子と色で、自分だけのキャラに」は After Effects（レーン 6）で重ねる。
## 引数 cam=<距離>,<注視点の高さ>,<キャラの画面の位置 0〜1>,<画角> でカメラを決め直せる。cam=game ならゲームのスキン設定のカメラのまま。
##
## 流れ（PV フレーム。1 = S20 の頭、60 fps、128 BPM で 1 拍 = 28.125 フレーム）:
##   オンライン画面のトップで、キャラの横の「スキン設定」の看板を押したのと同じ頼みごとをして、スキン設定のページを開く（撮影の前）。
##   STEPS のとおり 1 拍ごとに、帽子（ページの ◀ ▶ と同じ _apply_hat）・色（パレットのマスの pressed）・
##   パーツ選び（3D のキャラのクリックと同じ editor.select_part。その位置のレイがそのパーツに当たることも確かめる）が起きる。
## 本物のマウスの入力は送らない（窓の上の本物のカーソルとぶつかる）。撮影中はマウスをゲームの窓の上で動かさないこと。
## PlayerSkinStore は撮影中だけ別のファイル・書き込み停止（このPCの保存データは読まない・書かない）。

const S20_FRAMES := 169
const HANDLE_FRAMES := 4
const DEAD_RELAY := "ws://127.0.0.1:9"
const PALETTE_COLUMNS := 13                  # 色あい 12 + 無彩色 1（skin_editor.gd の PALETTE_HUES）

## 1 拍ごと：帽子（0・2・4 拍目）と色（1・3・5 拍目）。pick は色の少し前（0.25 拍）にそのパーツを 3D のキャラでクリックする。
## swatch = パレットのマスの番号（行 × 13 + 色あい。行 0 = あざやか、色あい 3 黄・5 緑・8 青・11 ピンク）
const STEPS := [
	{"beat": 0.0, "kind": "hat", "hat": HatData.HAT_SANTA},
	{"beat": 1.0, "kind": "color", "swatch": 8},
	{"beat": 2.0, "kind": "hat", "hat": HatData.HAT_FROG},
	{"beat": 2.75, "kind": "pick", "part": &"chest"},
	{"beat": 3.0, "kind": "color", "swatch": 3},
	{"beat": 4.0, "kind": "hat", "hat": HatData.HAT_PIRATE},
	{"beat": 4.75, "kind": "pick", "part": &"waist"},
	{"beat": 5.0, "kind": "color", "swatch": 11},
]
const START_HAT := HatData.HAT_NONE
const DAY_PHASE := 0.25

## カメラ（スキン設定のカメラの上から、キャラを大きく置き直す）
var cam_game := false
var cam_distance := 3.3
var cam_target_y := 1.0                      # キャラの腰（pelvis）からの高さ
var cam_screen_x := 0.72                     # キャラを置く画面の横位置（左の列にかからない）
var cam_fov := 34.0

var menu: OnlineMenu
var skin_page: OnlineSkinPage
var _steps_by_frame: Dictionary = {}         # PV フレーム → [step, ...]
var _done: Array = []
var _real_skin_hash := ""
var _saved_relay := ""
var _saved_skin_path := ""
var _saved_skin_suspended := false
var _start_hat_applied := false


func _init() -> void:
	take_name = "s20_skin"


func _default_frames() -> int:
	return S20_FRAMES + HANDLE_FRAMES


func _parse_arg(arg: String) -> void:
	if arg == "cam=game":
		cam_game = true
	elif arg.begins_with("cam="):
		var v := arg.trim_prefix("cam=").split(",")
		if v.size() >= 4:
			cam_distance = float(v[0])
			cam_target_y = float(v[1])
			cam_screen_x = float(v[2])
			cam_fov = float(v[3])


func _setup() -> void:
	for step: Dictionary in STEPS:
		var f := bf(float(step["beat"]))
		if not _steps_by_frame.has(f):
			_steps_by_frame[f] = []
		(_steps_by_frame[f] as Array).append(step)
	_real_skin_hash = FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH) if FileAccess.file_exists(PlayerSkinStore.DEFAULT_PATH) else "absent"
	_saved_relay = NetworkManager.relay_url
	NetworkManager.relay_url = DEAD_RELAY
	_saved_skin_path = PlayerSkinStore.path
	_saved_skin_suspended = PlayerSkinStore.suspended
	PlayerSkinStore.path = "user://pv_capture_player_skins.json"
	PlayerSkinStore.suspended = true
	PlayerSkinStore.reset_memory()                         # 標準の色・帽子なしから（S02・S03 の P1 と同じオレンジ）
	QuizManager.game_state.p1_hat = START_HAT
	QuizManager.game_state.set_player_skin(1, {})
	get_tree().change_scene_to_file(OnlineMenu.SCENE_PATH)
	var ready := false
	var waited := 0.0
	while waited < 60.0 and not ready:
		await get_tree().process_frame
		waited += 1.0 / FPS
		var scene := get_tree().current_scene
		ready = scene is OnlineMenu and (scene as OnlineMenu).current_id() == OnlineMenu.HOME and (scene as OnlineMenu).stage != null and (scene as OnlineMenu).stage.me().is_ready()
	if not ready:
		failures.append("online menu not ready")
		return
	menu = get_tree().current_scene as OnlineMenu
	if menu.stage.skin_sign == null:
		failures.append("no skin sign")
		return
	if menu.stage.weather != null:
		menu.stage.weather.force_day_phase(DAY_PHASE)
	await _frames(int(3.0 * FPS) * sub)                    # 立ち上がり・看板が立つまで
	# 看板を押したときと同じ頼みごと（看板のクリックは OnlineMenu._input → _on_page_action(&"skin")）。
	# 本物のマウスの入力は送らない：撮影中の窓の上に本物のカーソルがあると、そちらの位置とぶつかる（光り方もぶれる）
	menu.call("_on_page_action", &"skin", {})
	await _frames(int(1.0 * FPS) * sub)
	if menu.current_id() != OnlineMenu.SKIN:
		failures.append("skin page did not open")
		return
	skin_page = menu.page(OnlineMenu.SKIN) as OnlineSkinPage
	await _frames(int(2.0 * FPS) * sub)                    # カメラが寄りきる・光り方が落ち着く
	report["start"] = {"hat": QuizManager.game_state.p1_hat, "page": String(menu.current_id()), "cam_game": cam_game, "cam": [cam_distance, cam_target_y, cam_screen_x, cam_fov], "relay": NetworkManager.relay_url}


## 画面（1920×1080）の位置 ← 3D の点
func _screen_of(world: Vector3) -> Vector2:
	var stage_scale: Vector2 = menu.get("_stage_view").scale
	return menu.stage.camera.unproject_position(world) * stage_scale


func _update(n: int, _t: float, _dt: float) -> void:
	if menu == null or skin_page == null:
		return
	(menu.get("_link") as Control).visible = false          # 右上の「● オフライン」（通信の状態の表示）は、PV の絵には要らない
	menu.set("_skin_hover_3d", &"")                         # 本物のカーソルが乗っても、パーツを光らせない
	menu.set("_skin_hover_map", &"")
	if not cam_game:
		_apply_camera()
	if (_step - 1) % sub != 0 or not _steps_by_frame.has(n):
		return
	for step: Dictionary in _steps_by_frame[n]:
		_run_step(n, step)


func _run_step(n: int, step: Dictionary) -> void:
	var entry := {"frame": n, "kind": step["kind"]}
	match String(step["kind"]):
		"hat":
			var old_hat := QuizManager.game_state.p1_hat
			skin_page.editor.record_hat_change(OnlineSkinPage.PLAYER, old_hat)
			skin_page.call("_apply_hat", int(step["hat"]))
			AudioManager.play_sfx(&"ui_click")                 # ページの ◀ ▶ のボタンと同じ音
			entry["hat"] = int(step["hat"])
		"pick":
			var part: StringName = step["part"]
			var puppet := menu.stage.me()
			var node := _part_node(puppet, part)
			var at := _screen_of(node.global_position)
			var hit: StringName = menu.call("_skin_part_at", at)       # その位置をクリックしたら当たるパーツ
			skin_page.editor.select_part(part)
			entry["part"] = String(part)
			entry["at"] = [snappedf(at.x, 1.0), snappedf(at.y, 1.0)]
			entry["ray_hits"] = String(hit)
			entry["selected"] = String(skin_page.editor.target)
			if skin_page.editor.target != part:
				failures.append("pick %s: selected %s" % [part, skin_page.editor.target])
		"color":
			var swatch: SkinPaletteSwatch = skin_page.editor.get("_palette")[int(step["swatch"])]
			swatch.pressed.emit()                              # パレットのマスを押す（クリック音も鳴る）
			entry["swatch"] = int(step["swatch"])
			entry["target"] = String(skin_page.editor.target)
	_done.append(entry)


## パーツ名 → 3D のキャラの体のノード（クリックする位置）
func _part_node(puppet: StagingPuppet, part: StringName) -> Node3D:
	var parts: Dictionary = puppet.parts()
	var key: String = {
		&"head": "head", &"chest": "upper_torso", &"waist": "pelvis",
		&"l_arm": "l_upp_arm", &"r_arm": "r_upp_arm", &"l_hand": "l_hand", &"r_hand": "r_hand",
		&"l_leg": "l_thigh", &"r_leg": "r_thigh", &"l_foot": "l_foot", &"r_foot": "r_foot",
	}.get(part, "pelvis")
	return parts.get(key, parts.get("pelvis")) as Node3D


## ゲームのスキン設定のカメラ（OnlineSkinCloseup、process_priority 100）は 5.2 m 離れた全身寄り。その上から、胸〜帽子のバストアップに置き直す
## （撮影のテイクは process_priority 1000 でそのあとに動く）。
func _apply_camera() -> void:
	if menu == null or menu.stage == null or menu.stage.camera == null:
		return
	var closeup := menu.get("_skin_closeup") as OnlineSkinCloseup
	if closeup == null or closeup.weight() < 0.999:
		return
	var me := menu.stage.me()
	var pelvis := me.parts().get("pelvis") as Node3D
	var camera := menu.stage.camera
	var away := camera.global_position - pelvis.global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.BACK
	var look := pelvis.global_position + Vector3.UP * cam_target_y
	var eye := look + away * cam_distance
	var forward := (look - eye).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var view := camera.get_viewport().get_visible_rect().size
	var aspect := view.x / maxf(view.y, 1.0)
	var half_width := tan(deg_to_rad(cam_fov) * 0.5) * aspect * eye.distance_to(look)
	var aim := look - right * (cam_screen_x - 0.5) * 2.0 * half_width       # 注視点を左へずらすと、キャラは画面の右寄りに映る
	camera.global_transform = Transform3D(Basis.looking_at(aim - eye, Vector3.UP), eye)
	camera.fov = cam_fov
	camera.h_offset = 0.0
	camera.v_offset = 0.0


func _check() -> void:
	report["done"] = _done
	var gs := QuizManager.game_state
	report["end_hat"] = gs.p1_hat
	if _done.size() != STEPS.size():
		failures.append("steps done %d of %d" % [_done.size(), STEPS.size()])
	if gs.p1_hat != HatData.HAT_PIRATE:
		failures.append("S20: ended with hat %d" % gs.p1_hat)
	if menu == null or menu.current_id() != OnlineMenu.SKIN:
		failures.append("S20: not on the skin page")
	var skin := PlayerSkinStore.get_skin(1)
	report["end_skin"] = PlayerSkinStore.get_skin_code(1)
	if skin.is_empty():
		failures.append("S20: skin was not changed")
	var now := FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH) if FileAccess.file_exists(PlayerSkinStore.DEFAULT_PATH) else "absent"
	report["real_skin_file_unchanged"] = now == _real_skin_hash
	if now != _real_skin_hash:
		failures.append("user://player_skins.json changed")
	if not PlayerSkinStore.suspended:
		failures.append("PlayerSkinStore not suspended")
	report["network_state"] = NetworkManager.state
	if NetworkManager.state != NetworkManager.State.OFFLINE and NetworkManager.state != NetworkManager.State.IDLE:
		failures.append("network not idle: %d" % NetworkManager.state)


func _cleanup() -> void:
	# 保留中の保存タイマーが、戻したあとの本当のファイルへ書かないように、先に捨てる
	PlayerSkinStore.reset_memory()
	PlayerSkinStore.path = _saved_skin_path
	PlayerSkinStore.suspended = _saved_skin_suspended
	NetworkManager.relay_url = _saved_relay
