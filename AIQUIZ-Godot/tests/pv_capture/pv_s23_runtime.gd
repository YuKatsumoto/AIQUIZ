extends "res://tests/pv_capture/pv_take_base.gd"

## PV S23「ロゴとキャッチコピー」と S24「作品情報」の背景：本物のメインメニューの港の景色を、UI を全部隠して撮る。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s23 quality=ultra sub=8
## ロゴ（ゲームのタイトルの登場演出）・キャッチコピー・作品情報は After Effects（docs/pv/previz/ae/build_s23_s24.jsx）で重ねる。
##
## 流れ（PV フレーム。1 = S23 の頭、60 fps、128 BPM で 1 拍 = 28.125 フレーム）:
##   S23   1-338  設定の手順のメニュー（S04 と同じ。ベルトが止まり、2 人が立っている）。メニューのカメラのまま、UI・ロゴ・お知らせ・
##                CanvasLayer を全部隠す。モードを選ぶ手順は待ちの演出（キャラがチップソーに巻き込まれる・T ポーズ）が入るので使わない
##   S24 339-563  同じ景色の続き（AE で暗くして作品情報を重ねる）
## メニューの起動演出（タイトルロゴ・初回の案内・保守船の入港）は飛ばす。見た目は撮影用（P1 プロペラ帽子・P2 キツネ帽子。保存しない）。

const S23_FRAMES := 338
const S24_FRAMES := 225
const HANDLE_FRAMES := 4

const P1_HAT := 11
const P1_SKIN_CODE := "035bd66225c92ea51dc325c92e25c92e46d14d46d14da51dc3a51dc3293029293029"
const P2_HAT := 12
const P2_SKIN_CODE := "034dbff2f5f5f0f5f5f01e1e221e1e22f5f5f0f5f5f01e1e221e1e221e1e221e1e22"
const DAY_PHASE := 0.25
const SETTLE_SECONDS := 6.5

var gs: QuizGameState
var menu: Control
var preview: Node
var _saved_skin_path := ""
var _saved_skin_suspended := false


func _init() -> void:
	take_name = "s23"


func _default_frames() -> int:
	return S23_FRAMES + S24_FRAMES + HANDLE_FRAMES


func _setup() -> void:
	QuizManager.set_meta("title_logo_intro_seen", true)
	QuizManager.set_meta("saw_dock_menu_seen", true)
	_saved_skin_path = PlayerSkinStore.path
	_saved_skin_suspended = PlayerSkinStore.suspended
	PlayerSkinStore.path = "user://pv_capture_player_skins.json"
	PlayerSkinStore.suspended = true
	PlayerSkinStore._skins[1] = PlayerSkinStore.normalized(1, PlayerSkin.from_code(P1_SKIN_CODE))
	PlayerSkinStore._hats[1] = P1_HAT
	PlayerSkinStore._skins[2] = PlayerSkinStore.normalized(2, PlayerSkin.from_code(P2_SKIN_CODE))
	PlayerSkinStore._hats[2] = P2_HAT
	gs = QuizManager.game_state
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.menu_step = Constants.MENU_STEP_CONFIG
	gs.subject = "算数"
	gs.grade = 4
	gs.difficulty = "普通"
	# 撮影済みの素材と同じ見た目で撮る：メニュー背景のゴーストライダーは使わない
	MenuGhostRideDirector.globally_enabled = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	while get_tree().current_scene == null or not get_tree().current_scene.is_node_ready():
		await get_tree().process_frame
	menu = get_tree().current_scene as Control
	preview = menu.get("_menu_wall_preview")
	# 待ちの演出の「チップソーに巻き込まれる」抽選（menu_wall_background_preview.gd の SAW_*）を、撮影のあいだだけ止める
	# （ロゴの下でキャラがバラバラになると、ロゴより目立つ）
	preview.set("_saw_accident_cooldown", 1.0e9)
	preview.set("_saw_next_trial", 1.0e9)
	preview.call("sync_menu_player_count", 2)
	await _frames(int(4.0 * FPS) * sub)                # 入場・ベルトが止まるまで
	while menu.get("config_conveyor").is_moving():
		await get_tree().process_frame
	var stage: StageEnvironment = preview.call("get_stage_environment")
	if stage != null and stage.get("weather_cycle") != null:
		stage.get("weather_cycle").call("force_day_phase", DAY_PHASE)
	_hide_ui()
	hide_overlays()
	# 2 人にした直後は、P1 がチップソーに巻き込まれて復帰する流れが入る（約 4 秒）。落ち着いてから撮り始める
	await _frames(int(SETTLE_SECONDS * FPS) * sub)
	report["start"] = {"players": gs.num_players, "menu_step": gs.menu_step}


## 3D の背景（LiveBackground）のほかは全部隠す。メニューがあとから出し直すものもあるので、毎回呼ぶ
func _hide_ui() -> void:
	for child: Node in menu.get_children():
		if child is CanvasItem and child.name != "LiveBackground":
			(child as CanvasItem).visible = false


func _update(_n: int, _t: float, _dt: float) -> void:
	_hide_ui()


func _check() -> void:
	for child: Node in menu.get_children():
		if child is CanvasItem and child.name != "LiveBackground" and (child as CanvasItem).visible:
			failures.append("UI visible: " + String(child.name))


func _cleanup() -> void:
	PlayerSkinStore.path = _saved_skin_path
	PlayerSkinStore.suspended = _saved_skin_suspended
