class_name PracticeYard
extends Node3D

## 1 周の中の出来事（実習の進行役 yard_director.gd が人物の反応に使う）。name: checklist / point_check / start /
## stall / restart / horn / overshoot / overlift / estop / buffer / stop / pass / swap
signal yard_event(name: String)

## 設定画面の地下神殿の「実習場」（ui/settings_hall.tscn。パネルの「実習場を見る」で見に行く）。
## 本編と同じ連結チップソーの台車（linked_saw_carriage.glb）と、操作盤 v3 に座るゴドーくん（SawOperatorPresentation）、
## 走行レール（ConveyorRails）を実寸で置き、生徒が 1 周 CYCLE 秒の操作実習をくり返す:
##   待機（本編の待機しぐさ）→ キーON・保護カバー・START（計器の自己診断、刃が回り出す）→ クラクション 2 回 →
##   前進 → 刃を上げる → 下げる → 後退 → 停止手順（スティックを戻し、キーOFF、カバーを閉める）→ 待機。
## 台車は SawChaseController（本編の見た目の部品。状態は持たない）をそのまま使い、刃の回転・車輪・刃の昇降・
## 操縦の姿勢はすべてこのスクリプトの時計 t から決まる（program()）。
## ローカル座標は台車と同じ: +X が刃の列の向き（操縦席は +X の端）、+Z が前進、原点は走行の中心の床。

const MODEL_PATH := "res://assets/hazards/linked_saw_carriage.glb"
const OPERATOR_PATHS: Array[String] = [
	"res://assets/hazards/saw_operator/saw_operator.glb",
	"res://assets/hazards/saw_operator/godot_console_v3.glb",
]
const SFX_DIR := "res://assets/audio/sfx/"
## 実習場の小道具（停止線・点検表のボード・合格のハンコ・安全柵・見学席。台車と同じローカル座標で Blender から書き出し）。
const PROPS_PATH := "res://assets/settings_hall/practice_yard_props.glb"

## 1 周の秒数と、その中の段取り（秒）。
const CYCLE := 50.0
const T_START := 6.0 # キーを回し始める（ここから操縦の時計 s が進む）
const T_HORN := 10.2 # 発車の合図（本編の捕獲のしぐさ: クラクション 2 回とガッツポーズ）
const T_FORWARD := Vector2(13.0, 19.0)
const T_LIFT_UP := Vector2(19.8, 23.0)
const T_LIFT_DOWN := Vector2(25.4, 28.6)
const T_REVERSE := Vector2(29.6, 35.6)
const T_STOP := 36.4 # 停止手順（SawOperatorPresentation.STOP_SECONDS = 2 秒）
const STOP_HOLD := 2.6 # 停止手順の姿勢を保つ長さ。その後 RELAX 秒でもたれた体を戻して待機へ
const RELAX := 0.9
## 走行（台車のローカル z）と刃の高さ（m）。
const TRAVEL_HALF := 2.4
const LIFT_MAX := 0.75 # 刃の円盤が操縦者の顔の高さより下に収まる
const LIFT_STAGGER := 0.11 # 刃 1 枚ごとの昇降の遅れ（秒）。列が波のように上がる
const DRIVE_PEAK := 0.8 # 走行スティックの最大の倒し量（-1..1）
const LIFT_STICK_PEAK := 4.5 # 昇降の入力（SawOperatorPresentation の lift_speed、6 で全開）
const SPIN_DOWN := 2.4 # 停止で刃が止まるまで
const RAIL_LENGTH := TRAVEL_HALF * 2.0 + 4.2
## 周ごとの出来事（項目 126〜134）: 0 ふつう（合格のハンコ）/ 1 エンスト → かけ直し / 2 停止線を行き過ぎ → 笛で戻す /
## 3 刃を上げすぎ → 警告灯 → 教官が非常停止 / 4 車止めの手前で減速して止まる（合格）。
const VARIANTS := 5
const STALL_DIE := 1.4       # エンスト: キーを回してから止まるまで（s 秒）
const STALL_RETRY := 2.6     # かけ直し
const OVERSHOOT := 0.65      # 行き過ぎる距離（m）
const OVERLIFT := 1.28       # 上げすぎ（LIFT_MAX の倍）
const T_ESTOP := 23.4
const BUFFER_EXTRA := 1.15   # 車止めの手前まで進む距離（m）
## 出来事の時刻（周の中の秒）
const EVENTS := [
	[1.0, "checklist", -1], [4.4, "point_check", -1], [6.0, "start", -1], [7.4, "stall", 1], [8.6, "restart", 1],
	[10.2, "horn", -1], [18.7, "overshoot", 2], [22.6, "overlift", 3], [23.4, "estop", 3], [18.4, "buffer", 4],
	[36.4, "stop", -1], [38.6, "pass", 0], [38.6, "pass", 4], [45.6, "swap", -1],
]

## 実習場の明かり（ホールの舞台のレイヤー 11 は照らさない）。台車のローカル座標。
const HALL_LAYER_MASK := 1 << 10
const LIGHTS := [
	# name, from, aim, energy, range, angle, color
	["StationKey", Vector3(15.5, 6.5, -4.5), Vector3(11.5, 1.0, 0.0), 22.0, 14.0, 34.0, Color(1.0, 0.93, 0.82)],
	["RowFill", Vector3(2.0, 9.0, -7.0), Vector3(2.0, 0.3, 0.0), 26.0, 18.0, 52.0, Color(0.82, 0.88, 1.0)],
	["FarFill", Vector3(-8.0, 8.0, -6.0), Vector3(-8.0, 0.3, 0.0), 14.0, 16.0, 46.0, Color(0.82, 0.88, 1.0)],
]

var carriage: SawChaseController = null
var operator: SawOperatorPresentation = null
var rails: ConveyorRails = null
## 実習の時計（秒、CYCLE で回る）。外から seek() で位置を決められる（テストの撮影用）。
var clock := 0.0
var last_program: Dictionary = {}
## 何周目か（0 から）と、その周の出来事（cycle_count % VARIANTS）。
var cycle_count := 0
var variant := 0
var _spin_seconds := 0.0
var _idle_clock := 0.0
var _beacon_time := 0.0
var _lights: Array[SpotLight3D] = []
var _light_energy: Array[float] = []
var _lit := 0.0
var _spindle: AudioStreamPlayer3D = null
var _servo: AudioStreamPlayer3D = null
var _built := false
## path -> PackedScene。キャッシュは参照が切れると消えるので、組み立てるまで（中の同期 load が当たるまで）持っておく。
var _held: Dictionary = {}


## 読み込み役（settings_hall.gd）が別スレッドで読む資産（台車は講義セットの模型と共用）。
static func asset_paths() -> Array[String]:
	var paths: Array[String] = [MODEL_PATH]
	paths.append_array(OPERATOR_PATHS)
	if ResourceLoader.exists(PROPS_PATH):
		paths.append(PROPS_PATH)
	return paths


## 読み込み役から別スレッドで読み終えた資産を受け取る。全部そろったら true。
func hold_asset(path: String, packed: PackedScene) -> bool:
	if packed != null and asset_paths().has(path):
		_held[path] = packed
	return has_all_assets()


func has_all_assets() -> bool:
	for path: String in asset_paths():
		if not _held.has(path) and not ResourceLoader.has_cached(path):
			return false
	return true


## 資産がそろってから 1 回だけ組み立てる（中の同期の load は持っている資産のキャッシュに当たる）。
func build() -> void:
	if _built:
		return
	_built = true
	rails = ConveyorRails.new()
	rails.name = "Rails"
	add_child(rails)
	rails.build(0.0, RAIL_LENGTH, 0.0)
	var props_scene := _held.get(PROPS_PATH) as PackedScene
	if props_scene == null and ResourceLoader.exists(PROPS_PATH):
		props_scene = load(PROPS_PATH) as PackedScene
	if props_scene != null:
		var props := props_scene.instantiate() as Node3D
		props.name = "YardProps"
		add_child(props)
		for node: Node in props.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for node: Node in props.find_children("*", "CollisionObject3D", true, false):
			(node as CollisionObject3D).collision_layer = 0
			(node as CollisionObject3D).collision_mask = 0
	carriage = SawChaseController.new()
	carriage.name = "Carriage"
	add_child(carriage)
	carriage.preload_model()
	operator = carriage.operator_seat
	# 本編（非メニュー）と同じ取り付け: 刃の列の +X の端、列の向きを見て、前進は操縦者の左。
	operator.position = SawOperatorPresentation.MOUNT
	operator.rotation.y = SawOperatorPresentation.FACING_YAW
	operator.audio_enabled = true
	for item: Array in LIGHTS:
		_add_light(item)
	_spindle = _loop_audio("BladeMotor", "dock_spindle.wav", -26.0)
	_servo = _loop_audio("Hydraulics", "dock_servo.wav", -24.0)
	set_lit(_lit)
	_apply(program(clock, variant), 0.0)
	_held.clear()


func is_built() -> bool:
	return _built


## 「実習場を見る」のカメラが操作の手元に寄る量（0..1、項目 135）。3 周に 1 回、前進と刃の昇降の間だけ。
func closeup() -> float:
	if not _built or cycle_count % 3 != 1:
		return 0.0
	return _ease(T_FORWARD.x - 0.5, T_FORWARD.x + 1.5, clock) - _ease(T_LIFT_DOWN.y - 1.0, T_LIFT_DOWN.y + 1.0, clock)


## 寄るときに見る点（操縦者の手元、ワールド）と、カメラを置く向き（ワールド）。
func closeup_target() -> Vector3:
	if operator == null:
		return global_position
	return operator.global_position + Vector3(0.0, 0.95, 0.0)


func closeup_eye() -> Vector3:
	return closeup_target() + global_basis * Vector3(2.0, 1.1, -2.6)


## 台車が走行の中心からずれている量（ワールドの向き）。見学のカメラがついていくのに使う。
func travel_offset() -> Vector3:
	if carriage == null:
		return Vector3.ZERO
	return global_basis * Vector3(0.0, 0.0, carriage.position.z)


func _add_light(item: Array) -> void:
	var light := SpotLight3D.new()
	light.name = str(item[0])
	var from: Vector3 = item[1]
	var aim: Vector3 = item[2]
	light.transform = Transform3D(Basis.looking_at(aim - from, Vector3.UP), from)
	light.light_color = item[6]
	light.spot_range = float(item[4])
	light.spot_angle = float(item[5])
	light.spot_angle_attenuation = 1.1
	light.light_specular = 0.5
	light.shadow_enabled = false
	light.light_cull_mask = 0xFFFFF & ~HALL_LAYER_MASK
	add_child(light)
	_lights.append(light)
	_light_energy.append(float(item[3]))


func _loop_audio(label: String, file: String, gain: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = label
	var stream := load(SFX_DIR + file).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = gain
	player.unit_size = 12.0
	player.max_distance = 60.0
	carriage.add_child(player)
	player.position = Vector3(0.0, 0.6, 0.0)
	return player


## 明かりの強さ 0〜1（講義セットの set_lit と同じ時に呼ぶ）。
func set_lit(amount: float) -> void:
	_lit = clampf(amount, 0.0, 1.0)
	for index in range(_lights.size()):
		_lights[index].light_energy = _light_energy[index] * _lit
		_lights[index].visible = _lit > 0.001


## 時計を t 秒へ（撮影用）。刃の回転は 1 周の中の位置から積分し直す。
func seek(t: float) -> void:
	clock = fposmod(t, CYCLE)
	_spin_seconds = 0.0
	var step := 1.0 / 30.0
	var u := 0.0
	while u < clock:
		_spin_seconds += step * float(program(u, variant).rpm)
		u += step
	if _built:
		_apply(program(clock, variant), 0.0)


func advance(dt: float) -> void:
	if not _built or dt <= 0.0:
		return
	var before := clock
	clock = fposmod(clock + dt, CYCLE)
	if clock < before:
		cycle_count += 1
		variant = cycle_count % VARIANTS
	for item: Array in EVENTS:
		var at := float(item[0])
		var only := int(item[2])
		if (only < 0 or only == variant) and ((before < at and clock >= at) or (clock < before and at <= clock)):
			if str(item[1]) == "swap" and cycle_count % 2 == 0:
				continue
			yard_event.emit(str(item[1]))
	var p := program(clock, variant)
	_spin_seconds += dt * float(p.rpm)
	if float(p.s) <= 0.0:
		_idle_clock += dt
	_apply(p, dt)


# ------------------------------------------------------------------ program

static func _ease(a: float, b: float, t: float) -> float:
	var u := clampf((t - a) / (b - a), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## 区間 a..b を smoothstep で進むときの速さの割合（区間の中央で 1）。
static func _ease_speed(a: float, b: float, t: float) -> float:
	if t <= a or t >= b:
		return 0.0
	var u := (t - a) / (b - a)
	return 4.0 * u * (1.0 - u)


## 刃 1 枚の高さ（index 0..7、列の端から順に少し遅れる）。
static func blade_lift(t: float, index: int) -> float:
	var delay := LIFT_STAGGER * float(index)
	var up := _ease(T_LIFT_UP.x + delay, T_LIFT_UP.y - (LIFT_STAGGER * 7.0 - delay), t)
	var down := _ease(T_LIFT_DOWN.x + delay, T_LIFT_DOWN.y - (LIFT_STAGGER * 7.0 - delay), t)
	return LIFT_MAX * (up - down)


## 時刻 t（0..CYCLE）の段取り: 操縦の時計 s、走行の位置と入力、刃の高さと入力、停止・合図の経過、回転数。
## variant: 周ごとの出来事（VARIANTS）。
static func program(t: float, variant := 0) -> Dictionary:
	var running := t >= T_START and t < T_STOP + STOP_HOLD
	var s := t - T_START if running else 0.0
	var travel := -TRAVEL_HALF + 2.0 * TRAVEL_HALF * (_ease(T_FORWARD.x, T_FORWARD.y, t) - _ease(T_REVERSE.x, T_REVERSE.y, t))
	var drive := DRIVE_PEAK * (_ease_speed(T_FORWARD.x, T_FORWARD.y, t) - _ease_speed(T_REVERSE.x, T_REVERSE.y, t))
	var lift_peak := LIFT_MAX * (OVERLIFT if variant == 3 else 1.0)
	var lift := lift_peak * (_ease(T_LIFT_UP.x, T_LIFT_UP.y, t) - _ease(T_LIFT_DOWN.x, T_LIFT_DOWN.y, t))
	var lift_rate := LIFT_STICK_PEAK * (_ease_speed(T_LIFT_UP.x, T_LIFT_UP.y, t) - _ease_speed(T_LIFT_DOWN.x, T_LIFT_DOWN.y, t))
	if variant == 2:
		# 停止線を行き過ぎて、笛で少し戻す
		travel += OVERSHOOT * (_ease(16.8, T_FORWARD.y, t) - _ease(19.1, 19.75, t))
		drive += DRIVE_PEAK * 0.5 * (_ease_speed(16.8, T_FORWARD.y, t) - _ease_speed(19.1, 19.75, t))
	elif variant == 4:
		# 車止めの手前まで、ゆっくり進んで止まる（戻りも同じだけ長い）
		travel += BUFFER_EXTRA * (_ease(17.0, 19.6, t) - _ease(T_REVERSE.x, T_REVERSE.y, t))
		drive += DRIVE_PEAK * 0.35 * _ease_speed(17.0, 19.6, t)
	var stop := t - T_STOP if running and t >= T_STOP else -1.0
	var catch_age := t - T_HORN if running and t >= T_HORN and t < T_HORN + SawOperatorPresentation.CATCH_SECONDS else -1.0
	var rpm := smoothstep(0.0, SawChaseState.SPINUP_SECONDS, s) if running else 0.0
	if variant == 1 and running:
		# エンスト: 回りかけて止まり、キーをかけ直す
		var first := smoothstep(0.0, 0.7, s) * (1.0 - smoothstep(STALL_DIE - 0.5, STALL_DIE, s))
		var second := smoothstep(STALL_RETRY, STALL_RETRY + SawChaseState.SPINUP_SECONDS, s)
		rpm = maxf(first * 0.6, second)
	if variant == 3 and t >= T_ESTOP and running:
		# 非常停止: 刃がすぐ止まる
		rpm *= 1.0 - smoothstep(T_ESTOP, T_ESTOP + 0.8, t)
	if stop >= 0.0:
		rpm *= 1.0 - smoothstep(0.0, SPIN_DOWN, stop)
	# 停止のあと、背もたれに寄った体を待機の姿勢へ戻す量（1 → 0）。
	var relax := 0.0
	if not running and t >= T_STOP + STOP_HOLD:
		relax = 1.0 - _ease(T_STOP + STOP_HOLD, T_STOP + STOP_HOLD + RELAX, t)
	var phase := "idle"
	if running:
		phase = "start"
		if t >= T_HORN: phase = "horn"
		if t >= T_FORWARD.x: phase = "forward"
		if t >= T_LIFT_UP.x: phase = "lift_up"
		if t >= T_LIFT_DOWN.x: phase = "lift_down"
		if t >= T_REVERSE.x: phase = "reverse"
		if t >= T_STOP: phase = "stop"
	var warning := variant == 3 and t >= T_LIFT_UP.y - 0.6 and t < T_ESTOP + 3.0
	return {"t": t, "s": s, "travel": travel, "drive": drive, "lift": lift, "lift_rate": lift_rate,
		"stop": stop, "catch": catch_age, "rpm": rpm, "relax": relax, "phase": phase, "variant": variant,
		"warning": warning}


# ------------------------------------------------------------------ apply

func _apply(p: Dictionary, dt: float) -> void:
	last_program = p
	carriage.position = Vector3(0.0, 0.0, float(p.travel))
	carriage._apply_spin(_spin_seconds, float(p.travel) + TRAVEL_HALF)
	var t := float(p.t)
	var lift_scale := OVERLIFT if variant == 3 else 1.0
	for index in range(carriage.spin_bones.size()):
		carriage._set_lift(index, blade_lift(t, index) * lift_scale)
	carriage.skeleton.force_update_all_bone_transforms()
	_update_beacons(dt, absf(float(p.drive)) > 0.02 or absf(float(p.lift_rate)) > 0.05 or bool(p.get("warning", false)))
	var extra := {"catch": float(p.catch)}
	if float(p.stop) >= 0.0:
		extra.stop = float(p.stop)
		extra.rpm = float(p.rpm)
	var sample := SawOperatorPresentation.sample(SawDockPresentation.FINISH_TIME, float(p.s), float(p.drive),
		float(p.lift), true, float(p.lift_rate), _idle_clock, extra)
	var relax := float(p.relax)
	if relax > 0.0:
		# SawOperatorPresentation の停止の最後（relax = 1）と同じもたれ方から戻す。
		sample.pitch = float(sample.pitch) - 0.06 * relax
		sample.head_pitch = float(sample.head_pitch) - 0.04 * relax
		sample.bob = float(sample.bob) - 0.008 * relax
	operator.apply_sample(sample)
	_update_audio(p)


func _update_beacons(dt: float, working: bool) -> void:
	_beacon_time = _beacon_time + dt if working else 0.0
	var energy := 7.0 * pow(maxf(0.0, cos(TAU * 1.5 * _beacon_time)), 8.0) if working else 0.0
	for beacon: Array in carriage._beacons:
		(beacon[2] as BaseMaterial3D).emission_energy_multiplier = energy


func _update_audio(p: Dictionary) -> void:
	if _spindle == null:
		return
	var rpm := float(p.rpm)
	_set_loop(_spindle, rpm > 0.01)
	_spindle.pitch_scale = lerpf(0.5, 1.5, rpm)
	_spindle.volume_db = lerpf(-40.0, -24.0, rpm)
	var hydraulic := clampf(absf(float(p.lift_rate)) / LIFT_STICK_PEAK, 0.0, 1.0)
	var travel := clampf(absf(float(p.drive)) / DRIVE_PEAK, 0.0, 1.0)
	var moving := maxf(hydraulic, travel)
	_set_loop(_servo, moving > 0.02)
	_servo.pitch_scale = 0.7 + 0.35 * hydraulic + 0.15 * travel
	_servo.volume_db = lerpf(-34.0, -20.0, moving)


func _set_loop(player: AudioStreamPlayer3D, on: bool) -> void:
	if on and not player.playing and player.is_inside_tree():
		player.play()
	elif not on and player.playing:
		player.stop()
