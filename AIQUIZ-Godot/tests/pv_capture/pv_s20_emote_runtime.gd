extends "res://tests/pv_capture/pv_s20_runtime.gd"

## PV S20「自分だけのキャラ」の右半分（v1.4、10/21 夜）：同じカスタマイズ画面のエモートのタブで、P1 が踊る（1 テイクに 1 つのエモート、2 拍）。
## 通しでは画面を左右に分け、左に帽子（pv_s20_runtime.gd の 6 拍）、右にこのテイクを 2 拍ずつ 3 本つなぐ（帽子と同じ 0・2・4 拍目に替わる）：
## ヒップホップ（既定、tag=s20_emote_sub8）→ ハウスダンス（emote=14 tag=s20_emote_b_sub8）→ ヘッドスピン（emote=16 tag=s20_emote_c_sub8）。
## 右半分にはキャラのまわりだけを切り出す（右のエモートの一覧のパネルは映らない）。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s20_emote quality=ultra sub=8 tag=s20_emote_sub8
## 前半 3 拍（帽子）は pv_s20_runtime.gd。準備（メニュー → カスタマイズ）はそちらと同じで、スキンのタブのあとエモートのタブを本物のボタンで押し、
## ゲームでグリッドのエモートを選んだときと同じく、閲覧中のエモートを決めてレーンのプレビューを作る。
## 踊りは撮り始めの PRE_ROLL 秒前から流して、撮るところでは踊りの盛り上がった所が映るようにする（頭は動き出しのゆっくりした所で、
## 途中でエモートを替えると、1.5 拍の間ずっと構えの途中になる。ヘッドスピンなど）。
## P2 のレーンはパネルの裏（7 m 右）で映らないので、P1 だけを大きく映す。P1 は前半の最後の帽子（海賊帽）のまま。
## S09 で踊るエモート（ホースダンス・シリーダンス・YMCA・ランニングマン・ウェーブ）とは別のものを見せる。
## 引数 ecam=<距離>,<注視点の高さ>,<yaw>,<pitch>,<注視点を +x へずらす距離> でエモートタブのカメラ（オービット）を決め直せる
## （構図の確認用。ずらす距離を正にするとキャラが画面の左へ寄る）。引数 emote=<番号（EmoteData）>・preroll=<秒>。

const S20E_FRAMES := 57                      # 2 拍（56.25 フレーム）
const SECTION_EMOTE := 2                     # customize_settings.gd の Section.EMOTE
const DANCE := EmoteData.EMOTE_HIP_HOP
const P2_DANCE := EmoteData.EMOTE_FLAIR      # P2 のレーン（映らない）
const P2_HAT := HatData.HAT_FROG
## カメラの既定（ゲームの初期値は 5.2 m・注視点の高さ 0.2・yaw 0・pitch −8 で、キャラが画面の左下に寄って足が切れる）
const ECAM := [5.6, -0.2, 0.0, 4.0, 0.4]
const PRE_ROLL := 1.0                        # 撮り始めのこの秒数前から踊らせておく

var ecam: Array = ECAM.duplicate()
var dance := DANCE
var pre_roll := PRE_ROLL
var _emote_report: Dictionary = {}


func _init() -> void:
	take_name = "s20_emote"


func _default_frames() -> int:
	return S20E_FRAMES + HANDLE_FRAMES


func _parse_arg(arg: String) -> void:
	if arg.begins_with("ecam="):
		ecam = Array(arg.trim_prefix("ecam=").split(",")).map(func(v: String) -> float: return float(v))
	elif arg.begins_with("emote="):
		dance = int(arg.trim_prefix("emote="))
	elif arg.begins_with("preroll="):
		pre_roll = float(arg.trim_prefix("preroll="))
	else:
		super._parse_arg(arg)


func _setup() -> void:
	await super._setup()
	if customize == null:
		return
	_hat_steps = []
	_change_frames.clear()
	# 前半の最後の帽子のまま。P2 のレーンはカエル帽
	PlayerSkinStore._hats[1] = HatData.HAT_PIRATE
	gs.p1_hat = HatData.HAT_PIRATE
	gs.p2_hat = P2_HAT
	customize.call("_sync_preview_hat")
	# 踊るエモート：P1 のレーンは閲覧中のエモート、P2 のレーンは P2 のスロット 0（_lane_preview_emote_id_for_player）
	var p2_slots: Array[int] = gs.p2_emote_slots.duplicate()
	p2_slots[0] = P2_DANCE
	gs.p2_emote_slots = p2_slots
	var emote_button: Button = (customize.get("_section_buttons") as Dictionary)[SECTION_EMOTE]
	emote_button.pressed.emit()
	await _frames(int(0.2 * FPS) * sub)
	if ecam.size() >= 4:
		customize.set("_emote_cam_distance", float(ecam[0]))
		var tx := float(customize.call("_preview_editing_lane_x")) + (float(ecam[4]) if ecam.size() >= 5 else 0.0)
		customize.set("_emote_cam_target", Vector3(tx, float(ecam[1]), 0.0))
		customize.set("_emote_cam_yaw", float(ecam[2]))
		customize.set("_emote_cam_pitch", float(ecam[3]))
	await _frames(int(maxf(2.0 - pre_roll, 0.5) * FPS) * sub)   # タブの切り替え・カメラが落ち着くまで
	customize.set("_browsing_emote_id", EmoteData.normalize_emote_id(dance))
	customize.call("_refresh_emote_grid_cards")
	customize.call("_refresh_emote_lane_previews")
	await _frames(int(pre_roll * FPS) * sub)
	_hide_menu_extras()
	var lanes: Array = customize.get("_emote_lane_previews")
	_emote_report = {"section": int(customize.get("_active_section")), "dance": dance, "name": EmoteData.get_emote_name(dance),
		"p2": P2_DANCE, "pre_roll": pre_roll,
		"lanes": lanes.map(func(e: Dictionary) -> Array: return [int(e.get("preview_emote_id", 0)),
			e.get("ap") != null and (e.get("ap") as AnimationPlayer).is_playing()]),
		"cam": [customize.get("_emote_cam_distance"), customize.get("_emote_cam_target"), customize.get("_emote_cam_yaw"), customize.get("_emote_cam_pitch")]}
	report["start"] = _emote_report


func _update(_n: int, _t: float, _dt: float) -> void:
	pass


func _check() -> void:
	report["emote"] = _emote_report
	if customize == null:
		return
	if int(customize.get("_active_section")) != SECTION_EMOTE:
		failures.append("S20 emote: not on the emote tab")
	if int(customize.get("_browsing_emote_id")) != EmoteData.normalize_emote_id(dance):
		failures.append("S20 emote: browsing emote %d (wanted %d)" % [int(customize.get("_browsing_emote_id")), dance])
	var lanes: Array = customize.get("_emote_lane_previews")
	var p1_playing := false
	for e: Dictionary in lanes:
		var ap := e.get("ap") as AnimationPlayer
		if int(e.get("preview_emote_id", 0)) == EmoteData.normalize_emote_id(dance) and ap != null and ap.is_playing():
			p1_playing = true
	if not p1_playing:
		failures.append("S20 emote: P1 is not dancing %d" % dance)
	var now := FileAccess.get_sha256(PlayerSkinStore.DEFAULT_PATH) if FileAccess.file_exists(PlayerSkinStore.DEFAULT_PATH) else "absent"
	report["real_skin_file_unchanged"] = now == _real_skin_hash
	if now != _real_skin_hash:
		failures.append("user://player_skins.json changed")
	if not PlayerSkinStore.suspended:
		failures.append("PlayerSkinStore not suspended")
