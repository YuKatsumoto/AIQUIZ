extends "res://tests/pv_capture/pv_take_base.gd"

## PV S20「自分だけのキャラ」案 A（帽子だけ）：本物のメインメニュー → カスタマイズ → スキンのタブを、UI ありで撮る（1 人）。6 拍。
## v1.4（10/21 夜）から、通しでは画面の左半分に切り出し（キャラだけ）、右半分のエモート（pv_s20_emote_runtime.gd）と並べる。
## 左半分（960 px）に海賊帽のつばまで収まるよう、カメラを前の 2.35 m から少し引いた。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s20 quality=ultra sub=8
## テロップ「帽子と色で、自分だけのキャラに」は After Effects（レーン 6）で重ねる。
## 引数 cam=<距離>,<注視点の高さ>,<yaw>,<pitch>,<右へずらす距離> でスキンタブのカメラ（オービット）を決め直せる（構図の確認用）。
## 引数 hatsweep を付けると、選べる帽子を 24 フレームごとに順に見せる（帽子を選ぶための確認用。frames=370 only=22,46,...）。
##
## 流れ（PV フレーム。1 = S20 の頭、60 fps、128 BPM で 1 拍 = 28.125 フレーム）:
##   メインメニューのカスタマイズのボタンを押して開き、スキンのタブを押す（どちらも撮影の前に済ませる）。
##   0・2・4 拍目の頭に帽子が替わる（ゲームの ◀ ▶ と同じ _apply_hat_change_animated：古い帽子が左へ抜け、新しい帽子が右から入る）。
##   最初はなしの頭で、頭の帽子が入ってくる。カメラはスキンタブのオービットを置いたままで、動かさない。
## PlayerSkinStore は撮影中だけ別のファイル・書き込み停止（このPCの保存データは読まない・書かない）。

const S20_FRAMES := 169
const HANDLE_FRAMES := 4

## [拍, 帽子]：S02・S03 で見せているプロペラ帽・キツネ帽は避け、色も輪郭もはっきり違う 3 つ（赤い三角・緑の丸・黒い横長）
const HAT_STEPS := [
	[0.0, HatData.HAT_SANTA],
	[2.0, HatData.HAT_FROG],
	[4.0, HatData.HAT_PIRATE],
]
const START_HAT := HatData.HAT_NONE
const SLIDE_DIRECTION := 1
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const DAY_PHASE := 0.25
const SECTION_SKIN := 1                      # customize_settings.gd の Section.SKIN

## スキンタブのカメラ（右ドラッグ・ホイールと同じ変数）
var cam_distance := 3.0                       # v1.4：左半分に収めるため 2.35 から引いた
var cam_target_y := 0.80
var cam_yaw := 180.0                        # 180 = キャラの正面（ゲームの既定と同じ側）
var cam_pitch := 2.0
var cam_shift := 0.45                        # 注視点を画面の右へずらす距離（m）。大きいほどキャラが左へ寄る（v1.4：左半分の真ん中へ。前は 0.17）
var hat_sweep := false
var _hat_steps: Array = []

var gs: QuizGameState
var menu                                    # main_menu.gd
var customize                               # customize_settings.gd（メニューに埋め込まれたもの）
var _change_frames: Dictionary = {}         # PV フレーム → 帽子
var _applied: Array = []
var _real_skin_hash := ""
var _saved_skin_path := ""
var _saved_skin_suspended := false


func _init() -> void:
	take_name = "s20"


func _default_frames() -> int:
	return S20_FRAMES + HANDLE_FRAMES


func _parse_arg(arg: String) -> void:
	if arg == "hatsweep":
		hat_sweep = true
	elif arg.begins_with("cam="):
		var v := arg.trim_prefix("cam=").split(",")
		if v.size() >= 4:
			cam_distance = float(v[0])
			cam_target_y = float(v[1])
			cam_yaw = float(v[2])
			cam_pitch = float(v[3])
		if v.size() >= 5:
			cam_shift = float(v[4])


func _setup() -> void:
	_hat_steps = HAT_STEPS.duplicate()
	if hat_sweep:
		_hat_steps.clear()
		var hat := HatData.HAT_NONE
		for i in range(15):
			hat = HatData.step_hat(hat, 1)
			_hat_steps.append([float(i) * 24.0 / (BEAT * FPS), hat])
	for e: Array in _hat_steps:
		_change_frames[bf(float(e[0]))] = int(e[1])
	_real_skin_hash = FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH) if FileAccess.file_exists(PlayerSkinStore.DEFAULT_PATH) else "absent"
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	_saved_skin_path = PlayerSkinStore.path
	_saved_skin_suspended = PlayerSkinStore.suspended
	PlayerSkinStore.path = "user://pv_capture_player_skins.json"
	PlayerSkinStore.suspended = true
	PlayerSkinStore._skins[1] = PlayerSkinStore.normalized(1, PlayerSkin.from_code(P1_SKIN_CODE))
	PlayerSkinStore._hats[1] = START_HAT
	gs = QuizManager.game_state
	gs.num_players = 1
	gs.mode = Constants.MODE_TEN
	gs.menu_step = Constants.MENU_STEP_CONFIG
	gs.subject = "算数"
	gs.grade = 4
	gs.difficulty = "普通"
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene == null or not get_tree().current_scene.is_node_ready():
		await get_tree().process_frame
	menu = get_tree().current_scene
	var preview: Node = menu.get("_menu_wall_preview")
	preview.call("sync_menu_player_count", 1)
	await _frames(int(4.0 * FPS) * sub)                # 入場・ベルトが止まるまで
	while menu.config_conveyor.is_moving():
		await get_tree().process_frame
	var stage: StageEnvironment = preview.call("get_stage_environment")
	if stage != null and stage.get("weather_cycle") != null:
		stage.get("weather_cycle").call("force_day_phase", DAY_PHASE)
	_hide_menu_extras()
	# カスタマイズを開き、スキンのタブへ（本物のボタン）
	menu.customize_btn.pressed.emit()
	await _frames(int(1.0 * FPS) * sub)
	customize = menu.get("_embedded_customize")
	if customize == null or not bool(menu.get("_embedded_customize_open")):
		failures.append("customize did not open")
		return
	var skin_button: Button = (customize.get("_section_buttons") as Dictionary)[SECTION_SKIN]
	skin_button.pressed.emit()
	customize.set("_skin_cam_distance", cam_distance)
	# 正面（yaw 180）のカメラは −z 側から +z を向くので、画面の右は世界の −x
	customize.set("_skin_cam_target", Vector3(float(customize.call("_preview_editing_lane_x")) - cam_shift, cam_target_y, 0.0))
	customize.set("_skin_cam_yaw", cam_yaw)
	customize.set("_skin_cam_pitch", cam_pitch)
	await _frames(int(3.0 * FPS) * sub)                # タブの切り替え・カメラが落ち着くまで
	_hide_menu_extras()
	report["start"] = {"hat": gs.p1_hat, "section": int(customize.get("_active_section")), "cam": [cam_distance, cam_target_y, cam_yaw, cam_pitch, cam_shift]}


## 撮らないもの：「設定 / API状態」、お知らせ、スキップの案内
func _hide_menu_extras() -> void:
	if menu.settings_btn != null:
		menu.settings_btn.visible = false
	var note := menu.find_child("AnnouncementLabel", true, false) as Control
	if note != null:
		note.visible = false


func _before_update(_n: int) -> void:
	_hide_menu_extras()


func _update(n: int, _t: float, _dt: float) -> void:
	if (_step - 1) % sub == 0 and _change_frames.has(n):
		var hat: int = _change_frames[n]
		customize.call("_apply_hat_change_animated", hat, SLIDE_DIRECTION)
		AudioManager.play_sfx(&"ui_click")                  # ゲームの ◀ ▶ のボタンと同じ音
		_applied.append({"frame": n, "hat": hat})


func _check() -> void:
	report["applied"] = _applied
	report["end_hat"] = gs.p1_hat
	if _applied.size() != _change_frames.size():
		failures.append("hat changes applied %d of %d" % [_applied.size(), _change_frames.size()])
	if gs.p1_hat != int(_hat_steps[_hat_steps.size() - 1][1]):
		failures.append("S20: ended with hat %d" % gs.p1_hat)
	if int(customize.get("_active_section")) != SECTION_SKIN:
		failures.append("S20: not on the skin tab")
	var now := FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH) if FileAccess.file_exists(PlayerSkinStore.DEFAULT_PATH) else "absent"
	report["real_skin_file_unchanged"] = now == _real_skin_hash
	if now != _real_skin_hash:
		failures.append("user://player_skins.json changed")
	if not PlayerSkinStore.suspended:
		failures.append("PlayerSkinStore not suspended")


func _cleanup() -> void:
	# 保留中の保存タイマー（SAVE_DELAY_SEC）が、戻したあとの本当のファイルへ書かないように、先に捨てる
	PlayerSkinStore.reset_memory()
	PlayerSkinStore.path = _saved_skin_path
	PlayerSkinStore.suspended = _saved_skin_suspended
