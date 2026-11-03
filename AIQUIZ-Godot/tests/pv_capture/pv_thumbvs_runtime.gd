extends Node

## 作品ページのサムネイル用：オンライン対戦の VS カットインを、本物のオンラインメニュー（ui/online_menu.tscn）で撮る（2026-11-02）。
## メニューの L キー（デバッグ版：仮の相手とマッチしたことにする）と同じ道筋で動かし、相手の名前と帽子だけを決める。
## 通信はしない（リレーは閉じたアドレス）。カットインが出ているあいだ（CUTIN_IN〜SWAP）の絵を何枚か保存する。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumbvs
## 引数（"--" の後ろ）：
##   quality=low|balanced|high|ultra   画質（既定 ultra）
##   them=<名前>                        相手の名前（既定はサイコロの二つ名の 1 つ「プリン好きの大根」）
##   hat=<番号>                         相手の帽子（HatData。既定 16 = 海賊帽）
##   every=<秒>                         撮る間隔（既定 0.25）
##   tag=<名前>                         出力先 artifacts/pv_capture/<tag>/（既定 thumb_vs）
## 出力：vs_NN_<状態>.png と report.json。自分の名前・帽子・スキンは、この PC の設定のまま。
## 撮影のあいだは user://settings.json を使わない（画質を変えても書き換えない）。

const GraphicsQualityRules := preload("res://scripts/core/graphics_quality.gd")
const OUT_ROOT := "res://artifacts/pv_capture/"
const VIEW := Vector2i(1920, 1080)
const DEAD_RELAY := "ws://127.0.0.1:9"
const CAPTURE_SETTINGS_PATH := "user://pv_capture_settings.json"
const PIN_BUDGET_MS := 100000.0
const SHOT_STATES: Array[String] = ["CUTIN_IN", "CUTIN_HOLD", "SWAP"]

var quality := GraphicsQualityRules.ULTRA
var them := "プリン好きの大根"
var them_hat := HatData.HAT_PIRATE
var every := 0.25
var tag := "thumb_vs"
var out := ""
var report := {}
var failures: Array[String] = []
var _saved_settings_path := ""
var _saved_quality := ""
var _saved_relay := ""
var _settings_digest_before := ""


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("quality="):
			quality = GraphicsQualityRules.normalize(arg.trim_prefix("quality="))
		elif arg.begins_with("them="):
			them = arg.trim_prefix("them=")
		elif arg.begins_with("hat="):
			them_hat = clampi(int(arg.trim_prefix("hat=")), HatData.HAT_NONE, HatData.HAT_COUNT - 1)
		elif arg.begins_with("every="):
			every = maxf(0.05, float(arg.trim_prefix("every=")))
		elif arg.begins_with("tag="):
			tag = arg.trim_prefix("tag=").validate_filename()
	out = OUT_ROOT + tag + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_prepare()
	report["args"] = Array(OS.get_cmdline_user_args())
	report["quality"] = quality
	report["them"] = them
	report["them_hat"] = them_hat

	get_tree().change_scene_to_file(OnlineMenu.SCENE_PATH)
	if not await _wait(func() -> bool: return get_tree().current_scene is OnlineMenu, 20000):
		_finish("online menu did not open")
		return
	var menu := get_tree().current_scene as OnlineMenu
	await _wait(func() -> bool: return not SceneTransition.is_transitioning(), 8000)
	await _seconds(2.0)
	# 「ランダムマッチ」を押したのと同じ：ヘリに乗って飛び立ち、検索中の飛行（CRUISE）まで進める
	menu.set("_search_kind", &"random")
	menu.call("_begin_departure")
	if not await _wait(func() -> bool: return menu.director.state_name() == "CRUISE", 30000):
		_finish("director did not reach CRUISE (%s)" % menu.director.state_name())
		return
	await _seconds(2.0)
	_fake_match(menu)
	report["me"] = OnlineMenu.shown_own_name()
	report["rules"] = menu.rules_text()

	# カットインの入り〜ゲーム画面への切り替え（覆いの上でカットインが動き続ける）まで撮り、中央の線が開いたら終わる
	var shots: Array = []
	var next_ms := 0
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if SceneTransition.versus_split_opening:
			break
		var state := "GONE"
		if is_instance_valid(menu) and is_instance_valid(menu.director):
			state = menu.director.state_name()
		var showing := state in SHOT_STATES or (state == "GONE" and SceneTransition.is_transitioning())
		if not showing:
			if not shots.is_empty() and state == "GONE":
				break
			continue
		if Time.get_ticks_msec() < next_ms:
			continue
		var label := "vs_%02d_%s" % [shots.size(), state.to_lower()]
		var image := get_viewport().get_texture().get_image()
		var err := image.save_png(ProjectSettings.globalize_path(out + label + ".png"))
		if err != OK:
			failures.append("save %s failed (%d)" % [label, err])
		shots.append({"label": label, "state": state, "ms": Time.get_ticks_msec(), "size": [image.get_width(), image.get_height()]})
		next_ms = Time.get_ticks_msec() + int(every * 1000.0)
	report["shots"] = shots
	if shots.is_empty():
		failures.append("no cut-in frame was captured")
	_finish("")


## OnlineMenu._debug_fake_match（L キー）と同じ手順。相手のプロフィールだけ、撮影用に決めたものにする。
func _fake_match(menu: OnlineMenu) -> void:
	menu.set("_fake_match", true)
	menu.set("_matched", true)
	menu.set("_start_sent", false)
	menu.set("_cutin_match_key", "thumb-vs")
	menu.set("_guest_start", {})
	menu.set("_peer_waiting", false)
	var small_cancel := menu.get("_small_cancel") as Button
	if small_cancel != null:
		small_cancel.visible = false
	var profile := {
		"nick": 0,
		"name": them,
		"hat": them_hat,
		"toon": menu.game_state.p1_toon_preset,
		"emotes": [1, 2, 3],
		"skin": "",
	}
	NetworkManager.debug_fake_match(profile, menu.call("_queue_settings"))
	menu.set_status("")
	menu.call("_begin_loading")
	menu.director.on_matched(1, NetworkManager.opponent_profile)


func _prepare() -> void:
	get_tree().root.size = VIEW
	_settings_digest_before = _settings_digest()
	_saved_settings_path = GameManager.settings_path
	_saved_quality = GameManager.graphics_quality
	_saved_relay = NetworkManager.relay_url
	GameManager.settings_path = CAPTURE_SETTINGS_PATH
	GameManager.graphics_quality = quality
	GraphicsQualityRules.adaptive_budget_override_ms = PIN_BUDGET_MS
	GraphicsQualityRules.apply_rendering_server(quality)
	GraphicsQualityRules.apply_text_viewport(get_viewport(), quality)
	if quality == GraphicsQualityRules.ULTRA:
		RenderingServer.directional_shadow_atlas_set_size(16384, true)
	NetworkManager.relay_url = DEAD_RELAY


func _finish(error: String) -> void:
	if error != "":
		failures.append(error)
	NetworkManager.relay_url = _saved_relay
	GameManager.graphics_quality = _saved_quality
	GameManager.settings_path = _saved_settings_path
	report["settings_unchanged"] = _settings_digest() == _settings_digest_before
	if not report["settings_unchanged"]:
		failures.append("user://settings.json changed")
	report["failures"] = failures
	var file := FileAccess.open(out + "report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("[pv_take_thumbvs] %s" % JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)


func _settings_digest() -> String:
	return FileAccess.get_sha256(GameManager.USER_SETTINGS_PATH) if FileAccess.file_exists(GameManager.USER_SETTINGS_PATH) else "absent"


func _seconds(duration: float) -> void:
	var end := Time.get_ticks_msec() + int(duration * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false
