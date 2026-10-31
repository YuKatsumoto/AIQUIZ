class_name PracticeSeatMoves
extends Node

## 案内のハテナ（HatenaGuide）が、席のハテナ（のこぎりの操縦席・ヘリの操縦士）と入れ替わる動き（docs/new_tutorial/phase9_design.md 5章）。
## 席へ戻る：雲で席のそばまで飛び、雲から降りて（ヘリなら、歩いてドアを押し上げ、ステップを上がり、かがんで乗ってドアを閉める）、
## 座ってから席のハテナと入れ替わる。席を離れる：その逆（最後に雲を呼んで跳び乗り、goal へ飛ぶ）。
## 席の近くの動きは、ハテナを席の台（のこぎりの操縦席なら SawOperatorPresentation、ヘリなら OnlineHeliportHelicopter）の子にして、
## その空間で動かす（台が動いても付いていく）。座った姿は、席のハテナの骨格にぴったり重ねる（overlay）。
## 案内（メニュー・オンラインの画面の案内）が子にして使い、終わったら消す。途中で cancel() すると、そこで止まる
## （ハテナは席の台の子のまま残るので、呼ぶ側が片づける）。
##   await saw_return(hatena, saw, camera)         / await saw_leave(hatena, saw, camera, goal, end_scale, seconds)
##   await heli_board(hatena, heli)                / await heli_leave(hatena, heli, goal, end_scale, seconds)
## goal は行き先（ワールドの位置）を返す Callable。end_scale は飛んでいった先のハテナの大きさ（親の空間）。

## のこぎりの操縦席：座面の高さ（等倍のハテナの空間。座った姿の体の玉の下）、雲を浮かべる所（座った位置から、カメラのほうの横へ m・
## 少し後ろへ m）、座面へ跳び降りる・雲へ跳び乗る弧の高さ（m）
const CUSHION := 0.48
const SAW_CLOUD_OUT := 1.35
const SAW_CLOUD_BACK := 0.15
const SAW_HOP_HEIGHT := 0.35
## 席へ飛んでくる・席から飛んでいく秒、雲の弧の高さ（m）
const FLY_SECONDS := 1.0
const FLY_ARC := 0.8
## ヘリ（H 座標。目印は OnlineHeliportHelicopter.marker）：雲を浮かべる所と降りる所（ステップの前 MK_BoardStand から m）、
## 機内でドアを閉める所（ドアの敷居 MK_DoorSill から機内へ m）、右の席の前（MK_SeatFront を左右反転）。
## オンラインの画面では、待っているプレイヤー（MK_IdleSpot）がカメラとドアの間の右寄りに立つ。ステップの前は画面ではプレイヤーの左に
## 見えるが、遠くから歩いてくるとプレイヤーの陰を通るので、雲はステップの前にじかに降ろす
const HELI_CLOUD_FROM_STAND := Vector3(-0.45, 0.75, -0.35)
const HELI_LAND_FROM_STAND := Vector3(-0.1, 0.0, -0.1)
const HELI_INSIDE_FROM_SILL := Vector3(0.6, 0.0, -0.12)
const HELI_DOOR := "L"
const HELI_SEAT_BELT := "R"
## 歩く・かがんで歩く速さ（m/秒。ハテナの大きさ等倍のとき）、ドアが開く・閉まる秒（素材の open_seconds）、手がドアに届く秒
const WALK_SPEED := 1.0
const DUCK_SPEED := 1.0
const DOOR_SECONDS := 0.6
const DOOR_REACH := 0.3
## 呼んだ雲が飛んでくる秒
const CLOUD_CALL_SECONDS := 0.8

var _cancelled := false
var _door_heli: OnlineHeliportHelicopter = null


func cancel() -> void:
	_cancelled = true


func _alive(hatena: HatenaGuide) -> bool:
	return not _cancelled and is_inside_tree() and is_instance_valid(hatena) and hatena.is_inside_tree()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds, 0.0)).timeout


## 雲を呼ぶ（CLOUD_CALL_SECONDS で着く）。着く時刻（Time.get_ticks_msec）を返す。待つときは _until_time
## （返り値の signal を後で待つと、先に時間が来たときにタイマーが消えていて待てない）。
func _call_cloud(hatena: HatenaGuide, at: Vector3) -> int:
	hatena.call_cloud(at, CLOUD_CALL_SECONDS)
	return Time.get_ticks_msec() + int(CLOUD_CALL_SECONDS * 1000.0)


func _until_time(ticks_msec: int) -> void:
	var left := float(ticks_msec - Time.get_ticks_msec()) / 1000.0
	if left > 0.0:
		await _wait(left)


# ---------- 共通 ----------

## hatena の骨格を skeleton（席のハテナ）にぴったり重ねる置き方（parent の空間：{position, yaw, scale}）。
static func overlay(hatena: HatenaGuide, skeleton: Skeleton3D, parent: Node3D) -> Dictionary:
	var node_global := skeleton.global_transform * hatena.skeleton_offset().affine_inverse()
	var local := parent.global_transform.affine_inverse() * node_global
	var forward := local.basis.z
	return {"position": local.origin, "yaw": atan2(forward.x, forward.z), "scale": local.basis.get_scale().x}


## from から to のほうを向く角度（HatenaGuide.place_at の facing）。
static func yaw_toward(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(d.x, d.z) if Vector2(d.x, d.z).length() > 0.001 else 0.0


## parent の空間の大きさ s を、hatena のいまの親の空間の大きさにする。
static func _scale_in(hatena: HatenaGuide, parent: Node3D, s: float) -> float:
	var here := hatena.get_parent() as Node3D
	var outer := here.global_basis.get_scale().x if here != null else 1.0
	return s * parent.global_basis.get_scale().x / maxf(outer, 0.0001)


## 雲に乗って、goal（ワールドの位置を返す Callable。毎フレーム見る）へ弧をえがいて飛ぶ。大きさは end_scale（いまの親の空間）へ。
func _fly(hatena: HatenaGuide, goal: Callable, seconds: float, end_scale: float) -> void:
	var parent := hatena.get_parent() as Node3D
	var from := hatena.global_position
	var scale_from := hatena.scale.x
	hatena.set_cloud(true)
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		if not _alive(hatena):
			return
		t += get_process_delta_time()
		var k := clampf(t / seconds, 0.0, 1.0)
		var eased := k * k * (3.0 - 2.0 * k)
		var to: Vector3 = goal.call()
		var world := from.lerp(to, eased) + Vector3.UP * FLY_ARC * 4.0 * k * (1.0 - k)
		var local := parent.to_local(world) if parent != null else world
		var ahead := parent.to_local(to) if parent != null else to
		hatena.place_at(local, yaw_toward(local, ahead) if local.distance_to(ahead) > 0.2 else hatena.rotation.y)
		hatena.scale = Vector3.ONE * lerpf(scale_from, end_scale, eased)


# ---------- のこぎりの操縦席 ----------

## 席のハテナの骨格（のこぎりの操縦席）。なければ null。
static func _saw_skeleton(saw: SawChaseController) -> Skeleton3D:
	if saw == null or saw.operator_seat == null:
		return null
	return saw.operator_seat.skeleton


## カメラのほうの横（操縦席の空間の x の向き。+1 か −1）。
static func _camera_side(op: Node3D, camera_world: Vector3) -> float:
	var local := op.to_local(camera_world)
	return -1.0 if local.x < 0.0 else 1.0


## 操縦席での置き場（操縦席の空間）：座った姿、座面の上に立つ所、雲の所、座った向き、大きさ。
static func _saw_spots(hatena: HatenaGuide, saw: SawChaseController, camera_world: Vector3) -> Dictionary:
	var op := saw.operator_seat
	var seat := overlay(hatena, _saw_skeleton(saw), op)
	var s: float = seat.scale
	var cushion := Vector3.UP * CUSHION * s * HatenaGuide.BODY_SCALE
	var side := _camera_side(op, camera_world)
	var stand: Vector3 = seat.position + cushion
	var back := Vector3(sin(seat.yaw), 0.0, cos(seat.yaw)) * -SAW_CLOUD_BACK
	return {"seat": seat.position, "yaw": seat.yaw, "scale": s, "stand": stand,
		"cloud": stand + Vector3(side * SAW_CLOUD_OUT, 0.04, 0.0) + back}


## 席へ戻る（のこぎりの操縦席）：雲で座面の横へ → 雲を残して座面へ跳び降りる（雲は帰る）→ 前を向いて座る → 席のハテナと入れ替わる。
func saw_return(hatena: HatenaGuide, saw: SawChaseController, camera_world: Vector3) -> void:
	var skeleton := _saw_skeleton(saw)
	if skeleton == null or not _alive(hatena):
		return
	var op := saw.operator_seat
	var world_parent := hatena.get_parent()
	var spots := _saw_spots(hatena, saw, camera_world)
	await _fly(hatena, func() -> Vector3: return op.to_global(spots.cloud), FLY_SECONDS, _scale_in(hatena, op, spots.scale))
	if not _alive(hatena):
		return
	hatena.reparent(op, true)
	hatena.scale = Vector3.ONE * float(spots.scale)
	hatena.place_at(spots.cloud, yaw_toward(spots.cloud, spots.stand))
	# 雲を残して、座面へ跳び降りる（雲は空へ帰る）
	hatena.leave_cloud_here()
	await _wait(0.15)
	if not _alive(hatena):
		return
	await hatena.hop_to(spots.stand, 0.5, SAW_HOP_HEIGHT)
	if not _alive(hatena):
		return
	hatena.send_cloud_away(1.0)
	await _wait(HatenaGuide.LAND_SECONDS)
	if not _alive(hatena):
		return
	# 前を向いて、お尻から座る
	await hatena.sit_to(spots.seat, spots.yaw)
	await _wait(0.35)
	if not _alive(hatena):
		return
	saw.set_operator_hidden(false)
	hatena.visible = false
	hatena.reparent(world_parent, true)


## 席を離れる（のこぎりの操縦席）：席のハテナと入れ替わって立ち上がり、呼んだ雲へ跳び乗って goal へ飛ぶ。
func saw_leave(hatena: HatenaGuide, saw: SawChaseController, camera_world: Vector3, goal: Callable, end_scale: float,
		seconds: float) -> void:
	var skeleton := _saw_skeleton(saw)
	if skeleton == null or not _alive(hatena):
		return
	var op := saw.operator_seat
	var world_parent := hatena.get_parent()
	hatena.reparent(op, true)
	var spots := _saw_spots(hatena, saw, camera_world)
	hatena.scale = Vector3.ONE * float(spots.scale)
	hatena.set_cloud(false)
	hatena.sit_here(spots.seat, spots.yaw)
	hatena.visible = true
	saw.set_operator_hidden(true)
	await _wait(0.25)
	if not _alive(hatena):
		return
	var cloud_at := _call_cloud(hatena, spots.cloud)
	await hatena.stand_up_to(spots.stand)
	if not _alive(hatena):
		return
	await hatena.turn_to(yaw_toward(spots.stand, spots.cloud), 0.25)
	await _until_time(cloud_at)
	if not _alive(hatena):
		return
	await hatena.hop_to(spots.cloud, 0.5, SAW_HOP_HEIGHT)
	if not _alive(hatena):
		return
	hatena.board_cloud()
	hatena.play(&"wave")
	await _wait(0.3)
	if not _alive(hatena):
		return
	hatena.reparent(world_parent, true)
	await _fly(hatena, goal, seconds, end_scale)


# ---------- ヘリ（オンラインの画面） ----------

## 操縦士の骨格（ヘリの右の席）。なければ null。
static func _pilot_skeleton(heli: OnlineHeliportHelicopter) -> Skeleton3D:
	if heli == null or heli.pilot == null:
		return null
	return heli.pilot.find_child("Skeleton3D", true, false) as Skeleton3D


## ヘリでの置き場（H 座標）。
static func _heli_spots(hatena: HatenaGuide, heli: OnlineHeliportHelicopter) -> Dictionary:
	var seat := overlay(hatena, _pilot_skeleton(heli), heli)
	var stand := heli.marker_position("MK_BoardStand")
	var sill := heli.marker_position("MK_DoorSill")
	var front := heli.marker_position("MK_SeatFront")
	var lift := Vector3.DOWN * HatenaGuide.FOOT_Y * float(seat.scale)
	return {"seat": seat.position, "yaw": seat.yaw, "scale": seat.scale,
		"stand": stand + lift, "step": heli.marker_position("MK_Step") + lift, "sill": sill + lift,
		"inside": sill + HELI_INSIDE_FROM_SILL + lift, "front": Vector3(-front.x, front.y, front.z) + lift,
		"land": stand + HELI_LAND_FROM_STAND + lift, "cloud": stand + HELI_CLOUD_FROM_STAND + lift}


## ドアの開き具合（オンラインの演出が毎フレーム閉じるので、ヘリの practice_doors に入れて優先させる）。
func _set_door(openness: float) -> void:
	if is_instance_valid(_door_heli):
		_door_heli.practice_doors[HELI_DOOR] = openness
		_door_heli.set_door(HELI_DOOR, openness)


## 手で動かすのをやめる（閉じたあと。演出の値に戻す）。
func _release_door() -> void:
	if is_instance_valid(_door_heli):
		_door_heli.practice_doors.erase(HELI_DOOR)


func _exit_tree() -> void:
	_release_door()


## ドアを手で押し上げる（open = true）・引き下ろす。手が届いたらドアが動き始める。手の動きが終わるまで待つ。
func _door(hatena: HatenaGuide, heli: OnlineHeliportHelicopter, open: bool) -> void:
	_door_heli = heli
	if open:
		hatena.push_door()
	else:
		hatena.pull_door()
	var hand_done := Time.get_ticks_msec() + int(HatenaGuide.DOOR_SECONDS * 1000.0)
	await _wait(DOOR_REACH)
	if not _alive(hatena):
		return
	var tween := create_tween()
	tween.tween_method(_set_door, heli.door_openness(HELI_DOOR), 1.0 if open else 0.0, DOOR_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	await _until_time(maxi(hand_done, Time.get_ticks_msec() + int(DOOR_SECONDS * 1000.0)))
	if not open:
		_release_door()


## 席へ戻る（ヘリ）：雲でステップの近くへ → 雲を残して跳び降りる → ステップの前まで歩く → ドアを押し上げる → ステップ・敷居を上がる
## → かがんで機内へ → ドアを引き下ろして閉める → かがんで右の席の前へ → 座る → ベルトが出て、操縦士と入れ替わる。
func heli_board(hatena: HatenaGuide, heli: OnlineHeliportHelicopter) -> void:
	if _pilot_skeleton(heli) == null or not _alive(hatena):
		return
	var world_parent := hatena.get_parent()
	var spots := _heli_spots(hatena, heli)
	var s: float = spots.scale
	await _fly(hatena, func() -> Vector3: return heli.to_global(spots.cloud), FLY_SECONDS, _scale_in(hatena, heli, s))
	if not _alive(hatena):
		return
	hatena.reparent(heli, true)
	hatena.scale = Vector3.ONE * s
	hatena.place_at(spots.cloud, yaw_toward(spots.cloud, spots.land))
	# 雲を残して地面へ跳び降りる（雲は空へ帰る）
	hatena.leave_cloud_here()
	await _wait(0.1)
	if not _alive(hatena):
		return
	await hatena.hop_to(spots.land, 0.45, 0.3 * s)
	if not _alive(hatena):
		return
	hatena.send_cloud_away(1.0)
	await _wait(HatenaGuide.LAND_SECONDS)
	if not _alive(hatena):
		return
	# ステップの前まで歩いて、ヘリのほうを向き、ドアを押し上げる
	await _walk(hatena, spots.stand, WALK_SPEED * s, false)
	if not _alive(hatena):
		return
	await hatena.turn_to(yaw_toward(spots.stand, spots.step), 0.25)
	await _door(hatena, heli, true)
	if not _alive(hatena):
		return
	# ステップ → 敷居
	await hatena.step_to(spots.step)
	if not _alive(hatena):
		return
	await hatena.step_to(spots.sill)
	if not _alive(hatena):
		return
	# かがんで機内へ入り、振り返ってドアを引き下ろす
	await _walk(hatena, spots.inside, DUCK_SPEED * s, true)
	if not _alive(hatena):
		return
	await hatena.turn_to(yaw_toward(spots.inside, spots.sill), 0.3)
	await _door(hatena, heli, false)
	if not _alive(hatena):
		return
	# かがんで右の席の前へ。機首を向いて座る
	await _walk(hatena, spots.front, DUCK_SPEED * s, true)
	if not _alive(hatena):
		return
	await hatena.sit_to(spots.seat, spots.yaw)
	if not _alive(hatena):
		return
	heli.set_belt(HELI_SEAT_BELT, 1.0)
	await _wait(0.35)
	if not _alive(hatena):
		return
	if heli.pilot != null:
		heli.pilot.visible = true
	hatena.visible = false
	hatena.reparent(world_parent, true)


## 席を離れる（ヘリ）：操縦士と入れ替わって立ち上がり → かがんでドアの前へ → ドアを押し上げる → 敷居・ステップを下りる
## → 振り返ってドアを引き下ろす → 雲を呼んで跳び乗り、goal へ飛ぶ。
func heli_leave(hatena: HatenaGuide, heli: OnlineHeliportHelicopter, goal: Callable, end_scale: float, seconds: float) -> void:
	if _pilot_skeleton(heli) == null or not _alive(hatena):
		return
	var world_parent := hatena.get_parent()
	hatena.reparent(heli, true)
	var spots := _heli_spots(hatena, heli)
	var s: float = spots.scale
	hatena.scale = Vector3.ONE * s
	hatena.set_cloud(false)
	hatena.sit_here(spots.seat, spots.yaw)
	hatena.visible = true
	if heli.pilot != null:
		heli.pilot.visible = false
	heli.set_belt(HELI_SEAT_BELT, 0.0)
	await _wait(0.25)
	if not _alive(hatena):
		return
	await hatena.stand_up_to(spots.front)
	if not _alive(hatena):
		return
	await _walk(hatena, spots.inside, DUCK_SPEED * s, true)
	if not _alive(hatena):
		return
	await hatena.turn_to(yaw_toward(spots.inside, spots.sill), 0.25)
	await _door(hatena, heli, true)
	if not _alive(hatena):
		return
	await _walk(hatena, spots.sill, DUCK_SPEED * s, true)
	if not _alive(hatena):
		return
	await hatena.step_to(spots.step)
	if not _alive(hatena):
		return
	await hatena.step_to(spots.stand)
	if not _alive(hatena):
		return
	# 振り返ってドアを引き下ろす
	await hatena.turn_to(yaw_toward(spots.stand, spots.step), 0.3)
	await _door(hatena, heli, false)
	if not _alive(hatena):
		return
	# 雲を呼んで、跳び乗る
	var cloud_at := _call_cloud(hatena, spots.cloud)
	await _walk(hatena, spots.land, WALK_SPEED * s, false)
	if not _alive(hatena):
		return
	await hatena.turn_to(yaw_toward(spots.land, spots.cloud), 0.2)
	await _until_time(cloud_at)
	if not _alive(hatena):
		return
	await hatena.hop_to(spots.cloud, 0.45, 0.3 * s)
	if not _alive(hatena):
		return
	hatena.board_cloud()
	hatena.play(&"wave")
	await _wait(0.3)
	if not _alive(hatena):
		return
	hatena.reparent(world_parent, true)
	await _fly(hatena, goal, seconds, end_scale)


## to へ歩く（duck ならかがんで）。着いたら返る。
func _walk(hatena: HatenaGuide, to: Vector3, speed: float, duck: bool) -> void:
	if hatena.position.distance_to(to) < 0.02:
		return
	await hatena.walk_to(to, speed, duck)
