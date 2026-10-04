class_name SuddenDeathDescent
extends RefCounted

## 降下ローディングの時間割（docs/sudden_death_underground.md 第5章）。
## 実時間の経過と準備の状態（進捗・完了・失敗）を受け取り、昇降台の速度・降下距離・
## 表示深度・カメラのショットを決める。表示は持たない。
##
## 降下距離 distance は降下開始からの実際の移動量（下向きが正）。入口と加速の区間は
## 縦穴の口から実際に下がる量そのもので、巡航以降は縦穴の模様を流す量になる。
## 着地（ARRIVAL）は天井（床から HALL_HEIGHT）から床までの降下を arrival_drop() で返す。
## 打ち切り（25秒超え・読み込みの失敗）では止まってから逆向きに上がり、地表へ戻る。
## 地下神殿の準備ができていても、オンラインの問題生成を待っている間（waiting）は降り続ける。
## この待ちでは打ち切らない（生成側に時間の上限がある）。

enum Stage { ENTRY, ACCEL, CRUISE, DECEL, ARRIVAL, LANDED, ABORT_STOP, ABORT_HOLD, ABORT_RISE, ABORT_SURFACE, ABORTED }
enum Shot { ENTRY, CRUISE, DOWN, ARRIVAL }

## 入口：地表の口へ沈み込んで一度止まる（重さを見せる）。
const ENTRY_TIME := 1.4
const ENTRY_DROP := 1.2
## 加速：0から巡航速度へ。
const ACCEL_TIME := 1.0
const CRUISE_SPEED := 10.0
const MIN_CRUISE := 3.0
## 巡航がこれを超えたら遅くし、真下を見下ろすショットへ切り替える。
const SLOW_AFTER := 8.0
const SLOW_SPEED := 6.0
const SLOW_BLEND := 1.0
const DECEL_TIME := 1.2
const DECEL_END_SPEED := 2.0
## 突入：天井の開口から床まで（天井の高さは地下ステージの寸法から）。
const ARRIVAL_TIME := 2.6
const HALL_HEIGHT := SuddenDeathLayout.HALL_HEIGHT
## 準備が終わらないまま、降下開始からこの秒数を超えたら打ち切る。
const TIMEOUT := 25.0
const ABORT_STOP_TIME := 1.2
const ABORT_HOLD_TIME := 0.6
const ABORT_RISE_ACCEL := 1.0
const RISE_SPEED := 10.0
## 帰りの最後は、地表の口の下 SURFACE_DROP から実際に上がって止まる。
const SURFACE_DROP := 6.2
const SURFACE_TIME := 1.4
## 表示深度（第5.3節）。
const DISPLAY_RATE := 10.0
const DISPLAY_SOFT := 60.0
const DISPLAY_PROGRESS := 8.0
const DISPLAY_FINAL := 70.0

var t := 0.0
var stage := Stage.ENTRY
var stage_time := 0.0
var speed := 0.0
## 降下開始からの移動量（下向きが正）。打ち切りの上昇では減っていく。
var distance := 0.0
var display_depth := 0.0
var shot := Shot.ENTRY
var progress := 0.0
var ready := false
var failed := false
## 地下神殿は準備できたが、ほかの準備（オンラインの問題生成）を待っている。
var waiting := false
## 準備が終わった時刻（降下開始から）と、そのときの表示深度。
var ready_at := -1.0
var cruise_time := 0.0

var _decel_from := CRUISE_SPEED
var _decel_start_distance := 0.0
var _ready_display := 0.0
var _abort_from_speed := 0.0
var _abort_distance := 0.0
var _abort_display := 0.0


func reset() -> void:
	t = 0.0
	stage = Stage.ENTRY
	stage_time = 0.0
	speed = 0.0
	distance = 0.0
	display_depth = 0.0
	shot = Shot.ENTRY
	progress = 0.0
	ready = false
	failed = false
	waiting = false
	ready_at = -1.0
	cruise_time = 0.0
	_decel_from = CRUISE_SPEED
	_decel_start_distance = 0.0
	_ready_display = 0.0
	_abort_from_speed = 0.0
	_abort_distance = 0.0
	_abort_display = 0.0


## 準備の状態を渡す。進捗は 0..1、完了と失敗は一度立てたら戻さない。
## is_ready は地下神殿、still_waiting はそれ以外（オンラインの問題生成）がまだ終わっていないこと。
func set_preparation(value: float, is_ready: bool, has_failed: bool, still_waiting := false) -> void:
	progress = clampf(maxf(progress, value), 0.0, 1.0)
	if has_failed and not ready:
		failed = true
	if is_ready and not failed and not ready:
		ready = true
	waiting = still_waiting
	if ready and not waiting:
		progress = 1.0


## 着地へ進んでよいか。
func can_land() -> bool:
	return ready and not waiting


func is_landed() -> bool:
	return stage == Stage.LANDED


func is_aborting() -> bool:
	return stage in [Stage.ABORT_STOP, Stage.ABORT_HOLD, Stage.ABORT_RISE, Stage.ABORT_SURFACE, Stage.ABORTED]


func is_finished() -> bool:
	return stage in [Stage.LANDED, Stage.ABORTED]


## 縦穴の模様を流す区間か（入口・加速・突入・地表での停止は実際に動く）。
func is_scrolling() -> bool:
	return stage in [Stage.CRUISE, Stage.DECEL, Stage.ABORT_STOP, Stage.ABORT_HOLD, Stage.ABORT_RISE]


## 入口と加速の区間で、地表の口から昇降台の天面までの深さ。
func entry_drop() -> float:
	match stage:
		Stage.ENTRY, Stage.ACCEL:
			return distance
		Stage.ABORT_SURFACE:
			return SURFACE_DROP * (1.0 - _surface_curve(stage_time / SURFACE_TIME))
		Stage.ABORTED:
			return 0.0
	return ENTRY_DROP + _accel_distance(ACCEL_TIME)


## 突入の区間で、天井の高さから下がった量（0..HALL_HEIGHT）。
func arrival_drop() -> float:
	if stage == Stage.LANDED:
		return HALL_HEIGHT
	if stage != Stage.ARRIVAL:
		return 0.0
	return _arrival_curve(stage_time / ARRIVAL_TIME) * HALL_HEIGHT


## 減速の区間で進む距離（v0 から DECEL_END_SPEED へ滑らかに）。
static func decel_distance(from_speed: float) -> float:
	return DECEL_TIME * (from_speed + DECEL_END_SPEED) * 0.5


## 入口と加速で地表の口から下がる深さ（巡航はここから縦穴の模様を流す）。
static func entry_total() -> float:
	return ENTRY_DROP + _accel_distance(ACCEL_TIME)


## 減速の残りの距離（減速の区間以外は 0、減速前は減速全体）。
func remaining_decel() -> float:
	match stage:
		Stage.ENTRY, Stage.ACCEL, Stage.CRUISE:
			return decel_distance(speed)
		Stage.DECEL:
			return maxf(0.0, _decel_start_distance + decel_distance(_decel_from) - distance)
	return 0.0


func advance(dt: float) -> void:
	if dt <= 0.0 or stage in [Stage.LANDED, Stage.ABORTED]:
		return
	var remaining := dt
	# Cross every stage boundary inside one long frame (a stalled main thread jumps ahead).
	var guard := 0
	while remaining > 0.0 and guard < 16:
		guard += 1
		remaining = _advance_stage(remaining)
	_update_display(dt)


func _advance_stage(dt: float) -> float:
	match stage:
		Stage.ENTRY:
			var step := minf(dt, ENTRY_TIME - stage_time)
			_tick(step)
			distance = ENTRY_DROP * smoothstep(0.0, 1.0, stage_time / ENTRY_TIME)
			speed = ENTRY_DROP * _smoothstep_slope(stage_time / ENTRY_TIME) / ENTRY_TIME
			if stage_time >= ENTRY_TIME - 0.000001:
				_enter(Stage.ACCEL)
			return dt - step
		Stage.ACCEL:
			var step := minf(dt, ACCEL_TIME - stage_time)
			_tick(step)
			speed = CRUISE_SPEED * smoothstep(0.0, 1.0, stage_time / ACCEL_TIME)
			distance = ENTRY_DROP + _accel_distance(stage_time)
			if stage_time >= ACCEL_TIME - 0.000001:
				_enter(Stage.CRUISE)
				shot = Shot.CRUISE
			return dt - step
		Stage.CRUISE:
			if failed or (not ready and t >= TIMEOUT):
				_begin_abort()
				return dt
			if can_land() and cruise_time >= MIN_CRUISE:
				_begin_decel()
				return dt
			# Stop exactly where the minimum cruise or the timeout falls due.
			var step := dt
			if can_land():
				step = minf(step, MIN_CRUISE - cruise_time)
			elif not ready:
				step = minf(step, TIMEOUT - t)
			step = maxf(step, 0.0)
			_tick(step)
			cruise_time += step
			var slow := smoothstep(SLOW_AFTER, SLOW_AFTER + SLOW_BLEND, cruise_time)
			speed = lerpf(CRUISE_SPEED, SLOW_SPEED, slow)
			distance += speed * step
			if cruise_time > SLOW_AFTER and not can_land():
				shot = Shot.DOWN
			return dt - step
		Stage.DECEL:
			var step := minf(dt, DECEL_TIME - stage_time)
			var before := _decel_travel(stage_time)
			_tick(step)
			speed = lerpf(_decel_from, DECEL_END_SPEED, smoothstep(0.0, 1.0, stage_time / DECEL_TIME))
			distance += _decel_travel(stage_time) - before
			if stage_time >= DECEL_TIME - 0.000001:
				_enter(Stage.ARRIVAL)
				shot = Shot.ARRIVAL
			return dt - step
		Stage.ARRIVAL:
			var step := minf(dt, ARRIVAL_TIME - stage_time)
			var before := arrival_drop()
			_tick(step)
			distance += arrival_drop() - before
			speed = HALL_HEIGHT * _arrival_slope(stage_time / ARRIVAL_TIME) / ARRIVAL_TIME
			if stage_time >= ARRIVAL_TIME - 0.000001:
				_enter(Stage.LANDED)
				speed = 0.0
				return 0.0
			return dt - step
		Stage.ABORT_STOP:
			var step := minf(dt, ABORT_STOP_TIME - stage_time)
			var before := _stop_travel(stage_time)
			_tick(step)
			speed = _abort_from_speed * (1.0 - smoothstep(0.0, 1.0, stage_time / ABORT_STOP_TIME))
			distance += _stop_travel(stage_time) - before
			if stage_time >= ABORT_STOP_TIME - 0.000001:
				_abort_distance = distance
				_enter(Stage.ABORT_HOLD)
				speed = 0.0
			return dt - step
		Stage.ABORT_HOLD:
			var step := minf(dt, ABORT_HOLD_TIME - stage_time)
			_tick(step)
			if stage_time >= ABORT_HOLD_TIME - 0.000001:
				_enter(Stage.ABORT_RISE)
				shot = Shot.CRUISE
			return dt - step
		Stage.ABORT_RISE:
			# Up the loop until only the real stretch below the mouth is left.
			var rise_total := maxf(0.0, _abort_distance - SURFACE_DROP)
			var accel_travel := RISE_SPEED * ABORT_RISE_ACCEL * 0.5
			var duration := ABORT_RISE_ACCEL + maxf(0.0, rise_total - accel_travel) / RISE_SPEED
			if rise_total < accel_travel:
				duration = sqrt(maxf(rise_total, 0.0) * 2.0 * ABORT_RISE_ACCEL / RISE_SPEED)
			var step := minf(dt, duration - stage_time)
			_tick(step)
			var risen := minf(_rise_travel(stage_time), rise_total)
			distance = _abort_distance - risen
			speed = -RISE_SPEED * smoothstep(0.0, 1.0, stage_time / ABORT_RISE_ACCEL)
			if stage_time >= duration - 0.000001:
				distance = SURFACE_DROP
				_enter(Stage.ABORT_SURFACE)
				shot = Shot.ENTRY
			return dt - step
		Stage.ABORT_SURFACE:
			var step := minf(dt, SURFACE_TIME - stage_time)
			_tick(step)
			distance = entry_drop()
			speed = -SURFACE_DROP * _surface_slope(stage_time / SURFACE_TIME) / SURFACE_TIME
			if stage_time >= SURFACE_TIME - 0.000001:
				_enter(Stage.ABORTED)
				distance = 0.0
				speed = 0.0
				return 0.0
			return dt - step
	return 0.0


func _tick(step: float) -> void:
	t += step
	stage_time += step


func _enter(next: Stage) -> void:
	stage = next
	stage_time = 0.0


func _begin_decel() -> void:
	_decel_from = speed
	_decel_start_distance = distance
	_ready_display = display_depth
	if ready_at < 0.0:
		ready_at = t
	_enter(Stage.DECEL)
	# The long wait looks straight down; the arrival starts from the over-the-heads shot.
	shot = Shot.CRUISE


func _begin_abort() -> void:
	_abort_from_speed = speed
	_abort_display = display_depth
	_enter(Stage.ABORT_STOP)
	shot = Shot.CRUISE


## Accel stage travel after `time` seconds (speed = CRUISE * smoothstep).
static func _accel_distance(time: float) -> float:
	var u := clampf(time / ACCEL_TIME, 0.0, 1.0)
	# Integral of smoothstep(u) = u^3 - u^4 / 2.
	return CRUISE_SPEED * ACCEL_TIME * (u * u * u - u * u * u * u * 0.5)


func _decel_travel(time: float) -> float:
	var u := clampf(time / DECEL_TIME, 0.0, 1.0)
	var integral := u * u * u - u * u * u * u * 0.5
	return DECEL_TIME * (_decel_from * u + (DECEL_END_SPEED - _decel_from) * integral)


func _stop_travel(time: float) -> float:
	var u := clampf(time / ABORT_STOP_TIME, 0.0, 1.0)
	var integral := u * u * u - u * u * u * u * 0.5
	return ABORT_STOP_TIME * _abort_from_speed * (u - integral)


static func _rise_travel(time: float) -> float:
	if time <= ABORT_RISE_ACCEL:
		var u := time / ABORT_RISE_ACCEL
		return RISE_SPEED * ABORT_RISE_ACCEL * (u * u * u - u * u * u * u * 0.5)
	return RISE_SPEED * ABORT_RISE_ACCEL * 0.5 + RISE_SPEED * (time - ABORT_RISE_ACCEL)


static func _smoothstep_slope(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return 6.0 * x * (1.0 - x)


## Cubic from the ceiling to the floor: enters at DECEL_END_SPEED, lands at rest.
static func _arrival_curve(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	var start_slope := DECEL_END_SPEED * ARRIVAL_TIME / HALL_HEIGHT
	var h10 := x * x * x - 2.0 * x * x + x
	var h01 := -2.0 * x * x * x + 3.0 * x * x
	return h10 * start_slope + h01


static func _arrival_slope(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	var start_slope := DECEL_END_SPEED * ARRIVAL_TIME / HALL_HEIGHT
	return (3.0 * x * x - 4.0 * x + 1.0) * start_slope + (-6.0 * x * x + 6.0 * x)


## Rising out of the mouth: arrives with RISE_SPEED and stops at the surface.
static func _surface_curve(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	var start_slope := RISE_SPEED * SURFACE_TIME / SURFACE_DROP
	var h10 := x * x * x - 2.0 * x * x + x
	var h01 := -2.0 * x * x * x + 3.0 * x * x
	return minf(1.0, h10 * start_slope + h01)


static func _surface_slope(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	var start_slope := RISE_SPEED * SURFACE_TIME / SURFACE_DROP
	return (3.0 * x * x - 4.0 * x + 1.0) * start_slope + (-6.0 * x * x + 6.0 * x)


## 第5.3節：準備完了前は min(秒数×10, 60＋8×進捗)、完了後は減速と突入の3.8秒で70mへ。
func _update_display(_dt: float) -> void:
	match stage:
		Stage.ENTRY, Stage.ACCEL, Stage.CRUISE:
			display_depth = minf(t * DISPLAY_RATE, DISPLAY_SOFT + DISPLAY_PROGRESS * progress)
		Stage.DECEL, Stage.ARRIVAL:
			var since := stage_time if stage == Stage.DECEL else DECEL_TIME + stage_time
			var u := smoothstep(0.0, 1.0, since / (DECEL_TIME + ARRIVAL_TIME))
			display_depth = lerpf(_ready_display, DISPLAY_FINAL, u)
		Stage.LANDED:
			display_depth = DISPLAY_FINAL
		Stage.ABORT_STOP, Stage.ABORT_HOLD:
			display_depth = _abort_display
		Stage.ABORT_RISE, Stage.ABORT_SURFACE, Stage.ABORTED:
			# Back up in proportion to the way risen.
			var span := maxf(_abort_distance, 0.001)
			display_depth = _abort_display * clampf(distance / span, 0.0, 1.0)


func get_debug_snapshot() -> Dictionary:
	return {
		"t": snappedf(t, 0.001), "stage": Stage.keys()[stage], "stage_time": snappedf(stage_time, 0.001),
		"speed": snappedf(speed, 0.01), "distance": snappedf(distance, 0.01),
		"display_depth": snappedf(display_depth, 0.01), "shot": Shot.keys()[shot],
		"progress": snappedf(progress, 0.01), "ready": ready, "waiting": waiting, "failed": failed,
		"ready_at": snappedf(ready_at, 0.001), "cruise_time": snappedf(cruise_time, 0.001),
	}
