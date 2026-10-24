extends "res://tests/pv_capture/pv_s16_runtime.gd"

## PV S17「サメに乗って逆襲」：S16 でチップソーに巻き込まれた P2 が幽霊になってサメに乗り、狙いを付けてチャージし、
## PERFECT の帯で離して突進、端で煽って踊っている P1 を海へ弾き飛ばす（12 拍）。本物の GameWorld・本物のキーイベントで撮る。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s17 quality=ultra sub=8
## テロップ「脱落しても、サメに乗って逆襲」は After Effects（レーン 6）。HUD は P2 のカード（ゴーストシャークのチャージと PERFECT）だけ出す。
##
## 撮る前（撮らない。1/60 秒刻み）: S16 と同じ台本で P2 が巻き込まれる → P1 は止まって左（+x）の端へ寄り、シリーダンスで煽る
##   → ゲームどおり幽霊がサメに乗る長い演出（魂が飛ぶ・サメに乗る・ビーム・登場で約 11 秒）。サメが海から上がってくる途中から撮る。
## 撮る（PV フレーム。1 = S17 の頭）:
##   1-        サメが海から上がり、幽霊を乗せて浮かぶ（ゲームの登場 ENTERING の終わり ENTRY_SHOWN 秒）
##   照準      照準の輪が出る（AIMING）。P2 が ← で輪を P1 へ滑らせる（照準の起点は P2 が脱落したときの P1 の位置）
##   チャージ  右 Ctrl を 0.415 秒押して 0.83（PERFECT の帯 0.72〜0.94）で離す → 構え 0.34 秒 → 突進
##   命中      命中の少し前から SLOW 倍のスロー（命中の時刻は、突進の向きと速さから撮影中に計算する）
##   その後    P1 が端から海へ飛ばされる。カメラはサメを追うのをやめ、P1 を見送る
## カメラ：サメの後ろから追従（サメ → P1 の向きの後ろ・上。なめらかに追う）。命中のあとは止まって P1 を見る。
## 引数（共通のほかに）:
##   measure                                   等速で撮り、出来事の時刻を report に書く（スローなし）
##   follow=<後ろ>,<上>,<横>,<注視の割合>,<画角>  追うカメラを試す
##   hud_dump                                  200 フレーム目に見えている HUD の部品を書き出す

const S17_BEATS := 12.0
const S17_HANDLES := 4
const S17_WALL_AHEAD := 140.0

const P1_EDGE_X := 8.5                  # P1 が寄る位置（後ろから見て左の端の近く。端は 12）
const P1_TAUNT_KEY := KEY_2             # シリーダンス（P1_EMOTES の 2 番目）
const CATCH_SETTLE := 0.5               # 巻き込まれてから P1 が止まるまで（秒）
const ENTRY_SHOWN := 1.4                # サメの登場（ENTERING、2.45 秒）の終わりのこの秒数を撮る

## 幽霊（P2）の操作。照準の開始（AIMING）からの PV 秒
const AIM_FROM := 0.35
const CHARGE_AT := 1.45
const CHARGE_HOLD := 0.415              # 0.415 / 0.5 = 0.83（PERFECT の帯の真ん中）
const AIM_SPEED := 9.0                  # GhostSharkRideController.AIM_SPEED

## スロー（命中の時刻からの game 秒・PV 秒）
const SLOW := 0.25
const SLOW_LEAD := 0.07                 # 命中のこの game 秒前に SLOW になりきる
const SLOW_IN := 0.08                   # PV 秒で SLOW へ
const SLOW_HOLD := 0.6                  # PV 秒
const SLOW_OUT := 0.35                  # PV 秒で AFTER へ
const AFTER := 1.3

## カメラ（サメの斜め後ろ・上。真後ろだとサメの体で幽霊と P1 が隠れる）
const FOLLOW_BACK := 6.0                # サメの後ろ
const FOLLOW_UP := 3.0                  # サメの上
const FOLLOW_SIDE := 3.5                # 横へずらす（スタート側。幽霊が背中に乗っているのが見える）
const LOOK_SHARE := 0.4                 # 注視点：P1 からサメへの割合
const FOLLOW_FOV := 44.0
const TAU_EYE := 0.16                   # なめらかに追う時定数（PV 秒）
const TAU_LOOK := 0.1

var ride: Node
var shark: Node3D
var hud_layer: CanvasLayer
var measure := false
var _phase_frames := {}
var _last_phase := -1
var _aim_t := -1.0                      # AIMING になった PV 秒
var _aim_hold := 0.0
var _charging_t := -1.0                 # 突進（CHARGING）になった PV 秒
var _anchor_p := -1.0
var _anchor_g := 0.0
var _profile: Array = []                # [[PV 秒, 速さの始め, 速さの終わり], ...]
var _hit_frame := -1
var _hit_t := -1.0
var _eta := 0.0
var _perfect := false
var _charge_power := 0.0
var _eye := Vector3.ZERO
var _look := Vector3.ZERO
var _cam_ready := false
var _cam_freeze := Vector3.ZERO
var _p1_sea_frame := -1
var _trace17: Array = []
var _hide_hud: Array[CanvasItem] = []
var follow_back := FOLLOW_BACK
var follow_up := FOLLOW_UP
var follow_side := FOLLOW_SIDE
var look_share := LOOK_SHARE
var follow_fov := FOLLOW_FOV


func _init() -> void:
	take_name = "s17"


func _default_frames() -> int:
	return bf(S17_BEATS) - 1 + S17_HANDLES


func _parse_arg(arg: String) -> void:
	if arg == "measure":
		measure = true
	elif arg.begins_with("follow="):
		var v := arg.trim_prefix("follow=").split(",")
		follow_back = float(v[0])
		if v.size() > 1: follow_up = float(v[1])
		if v.size() > 2: follow_side = float(v[2])
		if v.size() > 3: look_share = float(v[3])
		if v.size() > 4: follow_fov = float(v[4])
	else:
		super._parse_arg(arg)


func _setup() -> void:
	wall_ahead = S17_WALL_AHEAD
	_build_keys()
	await _build_world()
	_set_station()
	ride = world.get("_ghost_shark_ride_controller")
	hud_layer = world.get_node_or_null("GameplayHUD") as CanvasLayer
	var keep: Array[CanvasLayer] = []
	if hud_layer != null:
		keep.append(hud_layer)
	hide_overlays(keep)
	# HUD は P2 のカード（ゴーストシャークのチャージのメーター）だけ。P1 のカードとコースの進み具合のバーは隠す
	for path: String in ["PlayerHealthHUD/P1StatusCard", "ProgressBar"]:
		var item := hud_layer.get_node_or_null(path) as CanvasItem if hud_layer != null else null
		if item != null:
			_hide_hud.append(item)
	await _pre_roll_s17()
	report["plan"] = {"wall_ahead": wall_ahead, "p1_edge_x": P1_EDGE_X, "entry_shown": ENTRY_SHOWN, "aim_from": AIM_FROM,
		"charge_at": CHARGE_AT, "charge_hold": CHARGE_HOLD, "slow": SLOW, "slow_hold": SLOW_HOLD, "after": AFTER, "measure": measure,
		"aim_origin_x": snappedf(ride.get("_aim_origin").x, 0.01), "hover_side": ride.get("_hover_side"),
		"camera": {"back": follow_back, "up": follow_up, "side": follow_side, "look_share": look_share, "fov": follow_fov}}


## 撮る前：S16 の台本で P2 が巻き込まれる → P1 が端へ寄って煽る → 幽霊の長い演出 → サメの登場の途中まで。1/60 秒刻みで回す
func _pre_roll_s17() -> void:
	world.set("_replay_mode", false)
	Engine.time_scale = float(sub)
	var n := -PRE_ROLL + 1
	var caught_at := -1
	var caught_clock := 0.0
	var entering_at := -1.0
	var clock := 0.0
	for i in range(60 * 40):
		var want := {}
		if caught_at < 0:
			want = _keys_at(n)                  # S16 と同じ（P1 は走り、P2 は止まって踊る）
		elif clock < caught_clock + CATCH_SETTLE:
			want = {KEY_W: true}
		elif gs.player_x < P1_EDGE_X - 0.08:
			want = {KEY_A: true}               # 左（+x）の端へ
		elif gs.p1_emote == 0:
			want = {P1_TAUNT_KEY: true}
		hold_keys(want)
		world.set("_push_focus_lost", false)
		await get_tree().process_frame
		clock += 1.0 / FPS
		n += 1
		if caught_at < 0 and gs.p2_saw_killed:
			caught_at = n
			caught_clock = clock
		var phase := int(ride.get("phase"))
		if phase != _last_phase:
			_phase_frames["pre_%d" % phase] = snappedf(clock, 0.001)
			_last_phase = phase
		if phase == GhostSharkRideController.Phase.ENTERING:
			if entering_at < 0.0:
				entering_at = clock
			if clock - entering_at >= GhostSharkRideController.ENTRY_SECONDS - ENTRY_SHOWN - 0.5 / FPS:
				break
	hold_keys({})
	Engine.time_scale = 1.0
	await get_tree().process_frame          # 速いままの最後の更新を流す
	shark = ride.get("_shark") as Node3D
	report["pre_roll"] = {"caught_frame": caught_at, "entering_at": snappedf(entering_at, 0.001), "clock": snappedf(clock, 0.001),
		"phase": int(ride.get("phase")), "p1": [snappedf(gs.player_x, 0.01), snappedf(gs.player_local_z, 0.01)], "p1_emote": gs.p1_emote}
	if int(ride.get("phase")) != GhostSharkRideController.Phase.ENTERING or shark == null:
		failures.append("撮り始めでサメが登場の途中にいない（phase %d）" % int(ride.get("phase")))


## 幽霊（P2）のキー：照準の開始から、← で輪を P1 へ、右 Ctrl でチャージ
func _keys_at(n: int) -> Dictionary:
	if not _running:
		return super._keys_at(n)
	var want := {}
	if _aim_t < 0.0:
		return want
	var t0 := float(_step) / (FPS * sub)        # 次の更新の始まりの PV 秒
	var u := t0 - _aim_t
	if u >= AIM_FROM and u < AIM_FROM + _aim_hold:
		want[KEY_LEFT] = true
	if u >= CHARGE_AT and u < CHARGE_AT + CHARGE_HOLD:
		want[KEY_CTRL] = true
	return want


func _before_update(n: int) -> void:
	hold_keys(_keys_at(n))
	world.set("_push_focus_lost", false)


func _update(n: int, t: float, dt: float) -> void:
	var phase := int(ride.get("phase"))
	if phase != _last_phase:
		_phase_frames[str(phase)] = n
		_last_phase = phase
	if phase == GhostSharkRideController.Phase.AIMING and _aim_t < 0.0:
		_aim_t = t
		var origin: Vector3 = ride.get("_aim_origin")
		_aim_hold = maxf(0.0, (gs.player_x - origin.x) / AIM_SPEED)
	if phase == GhostSharkRideController.Phase.CHARGING and _charging_t < 0.0:
		_charging_t = t
		_perfect = bool(ride.get("_perfect_charge"))
		_charge_power = float(ride.get("_last_charge_power"))
		_plan_slow(t)
	if _hit_frame < 0 and bool(ride.get("_hit_this_charge")):
		_hit_frame = n
		_hit_t = t
	if _p1_sea_frame < 0 and gs.p1_waiting_for_shark:
		_p1_sea_frame = n
	_apply_follow_camera(n, t)
	for item: CanvasItem in _hide_hud:
		if is_instance_valid(item):
			item.visible = false
	if OS.get_cmdline_user_args().has("hud_dump") and n == 200 and (_step % sub) == 0:
		_dump_hud(hud_layer, 0)
	if (_step % sub) == 0 and (n % 2 == 1 or (_hit_frame >= 0 and n <= _hit_frame + 3)):
		var s_pos := shark.global_position if shark != null and is_instance_valid(shark) else Vector3.ZERO
		_trace17.append({"f": n, "t": snappedf(t, 0.0001), "g": snappedf(_game_time_at(t), 0.0001), "phase": phase,
			"shark": [snappedf(s_pos.x, 0.01), snappedf(s_pos.y, 0.01), snappedf(s_pos.z, 0.01)],
			"p1": [snappedf(gs.player_x, 0.01), snappedf(gs.player_y, 0.01), snappedf(gs.player_local_z, 0.01)],
			"aim": [snappedf(ride.get("_aim_offset").x, 0.01), snappedf(ride.get("_aim_offset").y, 0.01)],
			"charge": snappedf(float(ride.get("_charge_amount")), 0.001), "ts": snappedf(Engine.time_scale, 0.001),
			"p1_alive": gs.p1_alive, "p1_sea": gs.p1_waiting_for_shark})


func _dump_hud(node: Node, depth: int) -> void:
	if depth > 7:
		return
	for child: Node in node.get_children():
		if child is CanvasItem and (child as CanvasItem).is_visible_in_tree():
			var rect := (child as Control).get_global_rect() if child is Control else Rect2()
			print("HUD %s%s [%s] %s" % ["  ".repeat(depth), child.name, child.get_class(), str(rect)])
			_dump_hud(child, depth + 1)


## 突進の向きと速さから、P1 に当たる（横の距離が 1.45 m 以内になる）までの game 秒を出し、その少し前でスローになりきるよう決める
func _plan_slow(t: float) -> void:
	var dir: Vector3 = ride.get("_locked_direction")
	var speed := lerpf(GhostSharkRideController.MIN_CHARGE_SPEED, GhostSharkRideController.MAX_CHARGE_SPEED, _charge_power) + (3.0 if _perfect else 0.0)
	var target: Vector3 = ride.call("_player_position", 1) + Vector3.UP * 0.85
	var from := shark.global_position
	var rel := Vector2(from.x - target.x, from.z - target.z)
	var v := Vector2(dir.x, dir.z) * speed
	# |rel + v t| = 1.45 の小さいほうの t
	var a := v.dot(v)
	var b := 2.0 * rel.dot(v)
	var c := rel.dot(rel) - 1.45 * 1.45
	var disc := b * b - 4.0 * a * c
	_eta = (-b - sqrt(disc)) / (2.0 * a) if disc >= 0.0 and a > 0.0 else 0.3
	if measure:
		return
	# 速さの並び（PV 秒）：等速 → SLOW_IN で SLOW へ → SLOW_HOLD → SLOW_OUT で AFTER へ → AFTER
	var lead_pv := maxf(0.0, _eta - SLOW_LEAD - SLOW_IN * (1.0 + SLOW) * 0.5)
	_anchor_p = t
	_anchor_g = _game_time_at(t)
	_profile = [[lead_pv, 1.0, 1.0], [SLOW_IN, 1.0, SLOW], [SLOW_HOLD, SLOW, SLOW], [SLOW_OUT, SLOW, AFTER]]


## PV の秒 → game 秒。突進が始まるまでは等速、そのあとは _profile（なめらかな折れ線の速さ）を積む
func _game_time_at(pv: float) -> float:
	if _anchor_p < 0.0 or pv <= _anchor_p:
		return pv
	var u := pv - _anchor_p
	var g := _anchor_g
	var last := 1.0
	for seg: Array in _profile:
		var d: float = seg[0]
		var v0: float = seg[1]
		var v1: float = seg[2]
		if u <= d:
			return g + v0 * u + (v1 - v0) * u * u / (2.0 * maxf(d, 0.000001))
		g += (v0 + v1) * 0.5 * d
		u -= d
		last = v1
	return g + last * u


## サメの後ろ・上から追う（サメ → P1 の向き）。命中のあとは追うのをやめ、飛ばされる P1 を見る
func _apply_follow_camera(n: int, t: float) -> void:
	var p1: Vector3 = ride.call("_player_position", 1)
	var p1_body := Vector3(p1.x, FLOOR_Y + 1.0 + p1.y, p1.z)
	var s_pos := shark.global_position if shark != null and is_instance_valid(shark) else p1_body
	var desired_eye: Vector3
	var desired_look: Vector3
	if _hit_frame < 0:
		var back := Vector3(s_pos.x - p1_body.x, 0.0, s_pos.z - p1_body.z)
		back = back.normalized() if back.length() > 0.01 else Vector3.LEFT
		var side := back.cross(Vector3.UP)
		desired_eye = s_pos + back * follow_back + Vector3.UP * follow_up + side * follow_side
		desired_look = p1_body.lerp(s_pos, look_share)
		_cam_freeze = desired_eye
	else:
		desired_eye = _cam_freeze.lerp(p1_body, 0.15)
		desired_look = p1_body
	var dt := 1.0 / (FPS * sub)
	if not _cam_ready:
		_eye = desired_eye
		_look = desired_look
		_cam_ready = true
	else:
		_eye = _eye.lerp(desired_eye, 1.0 - exp(-dt / TAU_EYE))
		_look = _look.lerp(desired_look, 1.0 - exp(-dt / TAU_LOOK))
	var eye := _eye
	var look := _look
	var shake := gs.camera_shake
	if shake > 0.001:
		var k := 0.07 * shake
		eye += Vector3(sin(t * 57.0) * k, cos(t * 43.0) * k, 0.0)
		look += Vector3(sin(t * 61.0) * k * 0.6, cos(t * 47.0) * k * 0.6, 0.0)
	var pose := Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	camera_controller.call("set_director_pose", pose, follow_fov)
	if cam != null:
		cam.h_offset = 0.0
		cam.fov = follow_fov
		cam.global_transform = pose
		cam.attributes = null


func _check() -> void:
	report["cut_in_frame"] = 1                 # レーン 6 はここからカットの長さを使う（テイクの頭 = カットの頭）
	report["phases"] = _phase_frames
	report["aim_start"] = snappedf(_aim_t, 0.0001)
	report["aim_hold"] = snappedf(_aim_hold, 0.0001)
	report["charging_start"] = snappedf(_charging_t, 0.0001)
	report["eta"] = snappedf(_eta, 0.0001)
	report["perfect"] = _perfect
	report["charge_power"] = snappedf(_charge_power, 0.001)
	report["hit_frame"] = _hit_frame
	report["p1_sea_frame"] = _p1_sea_frame
	report["trace"] = _trace17
	report["highlights"] = {"aim_ring": _phase_frames.get(str(GhostSharkRideController.Phase.AIMING), -1),
		"charge_press": _frame_at(_aim_t + CHARGE_AT) if _aim_t >= 0.0 else -1,
		"perfect_release": _frame_at(_aim_t + CHARGE_AT + CHARGE_HOLD) if _aim_t >= 0.0 else -1,
		"dash": _phase_frames.get(str(GhostSharkRideController.Phase.CHARGING), -1), "hit": _hit_frame, "p1_in_sea": _p1_sea_frame}
	if _aim_t < 0.0:
		failures.append("照準（AIMING）にならない")
	if not _perfect:
		failures.append("PERFECT にならない（%.3f）" % _charge_power)
	if _hit_frame < 0:
		failures.append("突進が P1 に当たらない")
	elif not measure and absf(gs.player_x) <= StageConstants.FLOOR_HALF_WIDTH and not gs.p1_waiting_for_shark:
		failures.append("P1 が海へ飛ばされていない（x = %.2f）" % gs.player_x)


## PV 秒 → その時刻を含む PV フレーム
static func _frame_at(sec: float) -> int:
	return int(floor(sec * FPS + 0.0001)) + 1
