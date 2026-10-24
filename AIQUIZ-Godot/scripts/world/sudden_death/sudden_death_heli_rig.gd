class_name SuddenDeathHeliRig
extends Node3D

## 新サドンデスの2機のヘリ（docs/sudden_death_v2/common.md 第5・6・10章）。1人1機の OnlineHeliportHelicopter
## （本編の登場と同じ機体）に、縄ばしご（PhysicalRopeLadder）・操縦士ハテナ・音・ジェットを付けて、監督が
## 決めた位置へ動かす。HelicopterArrivalDirector は試合開始の登場専用なので使わず、同じ部品を組み合わせる。
##
## 機体の置き方は本編の登場と同じ：holder（このノードの子）の原点から HATCH_ANCHOR の位置に床下ハッチの中心が来る
## ように機体を置く。holder の −Z が機首、+Y が上。set_motion() で位置と進む向きを渡すと、加速度から傾きを決める。

const HATCH_ANCHOR := Vector3(0.0, -0.998, 0.0)
const CABIN_WAIT_PELVIS_HEIGHT := 0.53
## 傾き：横の加速度 1 m/s² あたり（度）と上限、機首の上げ下げ。
const BANK_PER_ACCEL := 1.6
const BANK_MAX := 24.0
const PITCH_PER_ACCEL := 1.2
const PITCH_MAX := 12.0
## 向きを変える速さの上限（度/秒）。
const TURN_RATE := 70.0

var helis := {}   # player -> info Dictionary
var _quality := ""


func build(quality: String) -> void:
	_quality = quality
	name = "SuddenDeathHelis"
	for player in [1, 2]:
		if helis.has(player):
			continue
		var info := _create(player)
		if not info.is_empty():
			helis[player] = info


func is_ready() -> bool:
	return helis.size() == 2


func holder(player: int) -> Node3D:
	return helis.get(player, {}).get("holder") as Node3D


func heli(player: int) -> OnlineHeliportHelicopter:
	return helis.get(player, {}).get("heli") as OnlineHeliportHelicopter


func set_shown(player: int, shown: bool) -> void:
	var node := holder(player)
	if node == null:
		return
	node.visible = shown
	var aircraft := heli(player)
	if aircraft != null:
		aircraft.set_sound_enabled(shown)


func hide_all() -> void:
	for player in [1, 2]:
		set_shown(player, false)
		remove_ladder(player)


## 位置をそのまま置く（カットの瞬間。速度と傾きを0に戻す）。forward は機首の向き（水平）。
func place(player: int, position: Vector3, forward: Vector3) -> void:
	var info: Dictionary = helis.get(player, {})
	if info.is_empty():
		return
	var yaw := _yaw_for(forward, float(info.get("yaw", 0.0)))
	info["yaw"] = yaw
	info["velocity"] = Vector3.ZERO
	info["bank"] = 0.0
	info["pitch"] = 0.0
	info["position"] = position
	(info.holder as Node3D).global_transform = Transform3D(Basis(Vector3.UP, yaw), position)


## 動かす（毎フレーム）。forward は機首を向けたい向き（水平。ゼロなら進む向き）。傾きは加速度から決める。
func set_motion(player: int, position: Vector3, forward: Vector3, delta: float) -> void:
	var info: Dictionary = helis.get(player, {})
	if info.is_empty() or delta <= 0.0:
		return
	var previous: Vector3 = info.get("position", position)
	var velocity := (position - previous) / delta
	var last_velocity: Vector3 = info.get("velocity", velocity)
	var accel := (velocity - last_velocity) / delta
	accel = accel.limit_length(25.0)
	var want := forward if forward.length_squared() > 0.0001 else Vector3(velocity.x, 0.0, velocity.z)
	var yaw := float(info.get("yaw", 0.0))
	if want.length_squared() > 0.0001:
		var target_yaw := _yaw_for(want, yaw)
		var step := deg_to_rad(TURN_RATE) * delta
		yaw += clampf(wrapf(target_yaw - yaw, -PI, PI), -step, step)
	var heading := Basis(Vector3.UP, yaw)
	var right := heading.x
	var nose := -heading.z
	var bank_target := clampf(-accel.dot(right) * BANK_PER_ACCEL, -BANK_MAX, BANK_MAX)
	var pitch_target := clampf(-accel.dot(nose) * PITCH_PER_ACCEL, -PITCH_MAX, PITCH_MAX)
	var follow := 1.0 - exp(-6.0 * delta)
	var bank := lerpf(float(info.get("bank", 0.0)), bank_target, follow)
	var pitch := lerpf(float(info.get("pitch", 0.0)), pitch_target, follow)
	info["yaw"] = yaw
	info["bank"] = bank
	info["pitch"] = pitch
	info["velocity"] = velocity
	info["position"] = position
	var basis := heading * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.BACK, deg_to_rad(bank))
	(info.holder as Node3D).global_transform = Transform3D(basis, position)


func velocity(player: int) -> Vector3:
	return helis.get(player, {}).get("velocity", Vector3.ZERO)


## 床下ハッチの中心（ワールド）。
func hatch_center(player: int) -> Vector3:
	var info: Dictionary = helis.get(player, {})
	if info.is_empty():
		return Vector3.ZERO
	var left := info.hatch_left as Node3D
	var right := info.hatch_right as Node3D
	return (left.global_position + right.global_position) * 0.5


## 縄ばしごの一番下の横木がこの位置に来るように置くときの holder の位置（縄が真下へ伸びきったとき）。
func holder_for_rung(rung: Vector3) -> Vector3:
	var length := PhysicalRopeLadder.SEGMENT_COUNT * PhysicalRopeLadder.SEGMENT_LENGTH
	return rung + Vector3(0.0, length + 0.08, 0.0) - HATCH_ANCHOR


## 本編の登場の「ハッチの上で待つ姿」の置き場所（pelvis）。
func cabin_wait_transform(player: int) -> Transform3D:
	var node := holder(player)
	if node == null:
		return Transform3D.IDENTITY
	var cabin_basis := node.global_basis.orthonormalized()
	var height := float(helis[player].get("cabin_wait_height", CABIN_WAIT_PELVIS_HEIGHT))
	return Transform3D(cabin_basis, hatch_center(player) + cabin_basis.y.normalized() * height)


## 左の座席（pelvis の置き場所。StagingPuppet.sit_at に渡す）。
func seat_transform(player: int) -> Transform3D:
	var aircraft := heli(player)
	if aircraft == null:
		return Transform3D.IDENTITY
	return aircraft.global_transform * aircraft.marker("MK_SeatPassenger")


# ------------------------------------------------------------------ rope ladder

## 縄ばしごを作る（mode "pickup" は地上から飛びつく、"drop" は本編の登場と同じく降ろす）。
func ensure_ladder(player: int, mode: String) -> PhysicalRopeLadder:
	var info: Dictionary = helis.get(player, {})
	if info.is_empty():
		return null
	var existing := info.get("ladder") as PhysicalRopeLadder
	if existing != null and is_instance_valid(existing) and str(info.get("ladder_mode", "")) == mode:
		return existing
	remove_ladder(player)
	var holder_node := info.holder as Node3D
	var mount := Node3D.new()
	mount.name = "P%dLadderMount" % player
	holder_node.add_child(mount)
	mount.position = HATCH_ANCHOR - Vector3(0.0, 0.08, 0.0)
	var ladder := PhysicalRopeLadder.new()
	ladder.name = "P%dRopeLadder" % player
	if mode == "pickup":
		ladder.deploy_throw_speed = 9.5
		ladder.deploy_damping = 0.994
		ladder.deploy_recoil_scale = 0.18
	else:
		ladder.deploy_throw_speed = 3.8
		ladder.deploy_lateral_scale = 0.18
		ladder.deploy_recoil_scale = 0.12
		ladder.inherit_carrier_velocity = true
	add_child(ladder)
	ladder.configure(mount, player)
	info["ladder"] = ladder
	info["ladder_mount"] = mount
	info["ladder_mode"] = mode
	return ladder


func ladder(player: int) -> PhysicalRopeLadder:
	var found := helis.get(player, {}).get("ladder") as PhysicalRopeLadder
	return found if found != null and is_instance_valid(found) else null


func remove_ladder(player: int) -> void:
	var info: Dictionary = helis.get(player, {})
	if info.is_empty():
		return
	for key: String in ["ladder", "ladder_mount"]:
		var node := info.get(key) as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
		info.erase(key)
	info.erase("ladder_mode")


## PlayerController の縄ばしごの関数に渡す横木の情報。inward は体を寄せる向き、with_carrier なら
## 「機内から降りる」動き（本編の登場と同じ）。
func grip(player: int, inward: Vector3, with_carrier: bool) -> Dictionary:
	var found := ladder(player)
	if found == null:
		return {"valid": false}
	var data := found.get_grip_data()
	if not bool(data.get("valid", false)):
		return data
	data["inward"] = inward
	if with_carrier:
		data["carrier_transform"] = (helis[player].holder as Node3D).global_transform
	return data


# ------------------------------------------------------------------ build

func _create(player: int) -> Dictionary:
	var holder_node := Node3D.new()
	holder_node.name = "P%dHelicopter" % player
	add_child(holder_node)
	var aircraft := OnlineHeliportHelicopter.new()
	aircraft.name = "Model"
	holder_node.add_child(aircraft)
	var low := GraphicsQuality.normalize(_quality) == GraphicsQuality.LOW
	var tint := PlayerController.P1_BODY if player == 1 else PlayerController.P2_BODY
	if not aircraft.setup(tint, true, low):
		holder_node.queue_free()
		return {}
	aircraft.set_livery_slot(player)
	var hatch_left := aircraft.model.find_child("DropHatchLeft", true, false) as Node3D
	var hatch_right := aircraft.model.find_child("DropHatchRight", true, false) as Node3D
	if hatch_left == null or hatch_right == null:
		holder_node.queue_free()
		return {}
	var hatch_mid := (_transform_in(hatch_left, aircraft).origin + _transform_in(hatch_right, aircraft).origin) * 0.5
	aircraft.position = HATCH_ANCHOR - hatch_mid
	var cabin_wait_height := CABIN_WAIT_PELVIS_HEIGHT
	if aircraft.has_marker("MK_CabinWait"):
		cabin_wait_height = aircraft.marker_position("MK_CabinWait").y - hatch_mid.y
	aircraft.spool = 1.0
	aircraft.spool_target = 1.0
	if aircraft.pilot != null:
		aircraft.pilot.play(&"steer")
	if aircraft.has_jets():
		aircraft.enable_jets()
	holder_node.visible = false
	return {
		"player": player,
		"holder": holder_node,
		"heli": aircraft,
		"hatch_left": hatch_left,
		"hatch_right": hatch_right,
		"cabin_wait_height": cabin_wait_height,
		"yaw": 0.0,
		"bank": 0.0,
		"pitch": 0.0,
		"velocity": Vector3.ZERO,
	}


## The yaw that points the nose (−Z) along `forward` (horizontal).
static func _yaw_for(forward: Vector3, fallback: float) -> float:
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() <= 0.000001:
		return fallback
	return atan2(-flat.x, -flat.z)


static func _transform_in(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != ancestor:
		xf = current.transform * xf
		current = current.get_parent() as Node3D
	return xf
