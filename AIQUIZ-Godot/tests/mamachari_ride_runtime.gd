extends Node

## ママチャリ（シークレットの乗り物）に乗った姿を、本番の試合の画面で確かめる。
##   乗る → コンベアの速さで車輪とクランクが回る → 足がペダル・手がグリップに付いたまま
##   → 横へ動くとハンドルが切れて車体が傾く → 前へ押すと立ちこぎ → 跳ぶと前輪が上がり、着地で沈む
##   → 止まると左足をつく → 動き出すとこぎ出す → エモート・脱落で降りる
## 解放の記録とスキンの保存先はテスト用に差し替え、終わったら元に戻す。ウィンドウありで流す：
##   Godot --path . --resolution 1280x720 --script tests/mamachari_ride_bootstrap.gd --fixed-fps 60
## 撮った画像は artifacts/mamachari_ride/。
##
## 本番の res://scenes/game_world.tscn を tests/hp_unit.gd の fixture(1, ENDLESS) で PLAYING のまま組み、
## _replay_mode=true で状態を止める（endless_horizon_runtime.gd と同じ組み方）。状態はテストが手で動かす。

const OUT := "res://artifacts/mamachari_ride/"
const SIZE := Vector2i(1280, 720)
const UNLOCKS := "user://mamachari_ride_unlocks.json"
const SKINS := "user://mamachari_ride_skins.json"
const SETTINGS := "user://mamachari_ride_settings.json"

var _failures: Array[String] = []
var _saved := {}
var gs: QuizGameState
var world: Node
var player: PlayerController


func _ready() -> void:
	call_deferred("run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func run() -> void:
	get_tree().root.size = SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	AudioServer.set_bus_mute(0, true)
	_saved = {"settings": GameManager.settings_path, "unlocks": UnlockStore.path, "skins": PlayerSkinStore.path,
		"state": QuizManager.game_state, "analytics": QuizManager.player_analytics}
	GameManager.settings_path = SETTINGS
	UnlockStore.path = UNLOCKS
	PlayerSkinStore.path = SKINS
	UnlockStore.reset_memory()
	PlayerSkinStore.reset_memory()
	QuizManager.player_analytics = null

	var helper: Node = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(1, Constants.MODE_ENDLESS)
	gs.current_index = 3
	gs.current_wall_index = 3
	gs.load_current_quiz()
	gs.skip_start_helicopter_arrival = true
	QuizManager.game_state = gs
	world = (load("res://scenes/game_world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("_replay_mode", true)
	player = world.get_node("Player") as PlayerController
	player.prepare_for_loading(gs)
	gs.game_state = Constants.STATE_FLYOVER
	gs.flyover_total_walls = 25
	await _frames(90)
	gs.game_state = Constants.STATE_PLAYING
	gs.world_scroll_z = 100.0
	gs.player_z = 100.0
	gs.player_x = 0.0
	gs.player_y = 0.0
	gs.player_vel_y = 0.0
	await _frames(30)

	# 乗り物なし：自転車は作られない
	_check(_rig() == null, "no ride selected: no bike is created")
	await _shot("0_on_foot")

	# 未解放のままでは選べない
	PlayerSkinStore.set_ride(1, RideData.RIDE_MAMACHARI)
	PlayerSkinStore.apply_to_state(gs)
	_check(gs.p1_ride == RideData.RIDE_NONE, "a locked ride cannot be selected")

	# 解放して乗る
	UnlockStore.unlock(UnlockStore.MAMACHARI)
	PlayerSkinStore.set_ride(1, RideData.RIDE_MAMACHARI)
	PlayerSkinStore.apply_to_state(gs)
	_check(gs.p1_ride == RideData.RIDE_MAMACHARI, "the unlocked ride is selected")
	await _frames(20)
	var rig := _rig()
	_check(rig != null and rig.visible, "the bike appears when the ride is selected")
	if rig == null:
		_finish()
		return
	_check(is_equal_approx(rig.global_position.y, player.global_position.y + PlayerController.BASE_Y), "the bike stands on the floor")

	# コンベアの速さで車輪とクランクが回る
	var wheel_before := rig.wheel_angle
	var crank_before := rig.crank_angle
	await _frames(12)
	var wheel_turn := wrapf(rig.wheel_angle - wheel_before, 0.0, TAU)
	var crank_turn := wrapf(rig.crank_angle - crank_before, 0.0, TAU)
	var expected := gs._active_wall_speed * (12.0 / 60.0) / MamachariRig.WHEEL_RADIUS
	_check(absf(wheel_turn - expected) < 0.1 * expected + 0.02, "wheels roll at the conveyor speed (%.3f vs %.3f rad)" % [wheel_turn, expected])
	_check(absf(crank_turn - wheel_turn / MamachariRig.GEAR_RATIO) < 0.02, "the crank turns at the gear ratio")
	_check(rig.stand < 0.01, "the stand stays up while riding")
	var ride := _ride()
	_check(ride != null and ride.standing < 0.01 and ride.foot_down < 0.01, "plain riding is seated pedalling")

	# 1回転のあいだ、足はペダルに・手はグリップに付いたまま
	var worst_foot := 0.0
	var worst_hand := 0.0
	var knee_low := INF
	var knee_high := -INF
	for i: int in range(150):
		await get_tree().process_frame
		for prefix: String in ["l_", "r_"]:
			var right := prefix == "l_"
			var side := -1.0 if right else 1.0
			var ankle := player.p1_parts[prefix + "ankle"] as Node3D
			var pedal := player.to_global(rig.pedal_position(right))
			var want_ankle := pedal + Vector3(side * MamachariRider.FOOT_SIDE - (pedal.x - rig.global_position.x), 0.0, 0.0) + _ankle_offset(MamachariRider.FOOT_PITCH_SEATED)
			worst_foot = maxf(worst_foot, ankle.global_position.distance_to(want_ankle))
			var wrist := player.p1_parts[prefix + "wrist"] as Node3D
			var grip := player.to_global(rig.grip_position(right))
			worst_hand = maxf(worst_hand, absf(wrist.global_position.distance_to(grip) - _wrist_offset(rig)))
			var knee := player.p1_parts[prefix + "knee"] as Node3D
			knee_low = minf(knee_low, knee.global_position.y)
			knee_high = maxf(knee_high, knee.global_position.y)
	_check(worst_foot < 0.02, "feet stay on the pedals through a full turn (worst %.3f m)" % worst_foot)
	_check(worst_hand < 0.02, "hands stay on the grips (worst %.3f m)" % worst_hand)
	_check(knee_high - knee_low > 0.2, "the knees move up and down while pedalling")
	var pelvis := player.p1_parts["pelvis"] as Node3D
	var seat := player.to_global(rig.seat_position())
	_check(absf(pelvis.global_position.y - seat.y - MamachariRider.HIP_ABOVE_SEAT) < 0.01, "the hips sit on the saddle")
	await _shot("1_riding")

	# 横へ動く：ハンドルが切れて車体が傾く（+X = 乗り手の左）
	for i: int in range(40):
		gs.player_x += 3.0 / 60.0
		await get_tree().process_frame
	_check(rig.steer > deg_to_rad(5.0), "moving left steers left")
	_check(rig.rotation.z < -deg_to_rad(2.0), "the bike leans into the turn")
	await _shot("2_steering_left")
	for i: int in range(60):
		await get_tree().process_frame
	_check(absf(rig.steer) < deg_to_rad(1.0), "the bars straighten when the sideways motion stops")

	# 前へ押す：立ちこぎ（腰が浮いて前へ出て、車体が左右に振れる）
	var seated_pelvis := pelvis.global_position
	var sway_left := 0.0
	var sway_right := 0.0
	var worst_reach := 0.0
	for i: int in range(150):
		gs.player_z += 1.5 / 60.0
		await get_tree().process_frame
		sway_left = minf(sway_left, rig.rotation.z)
		sway_right = maxf(sway_right, rig.rotation.z)
		if i >= 30:
			for prefix: String in ["l_", "r_"]:
				var hip := player.p1_parts[prefix + "hip"] as Node3D
				var ankle := player.p1_parts[prefix + "ankle"] as Node3D
				worst_reach = maxf(worst_reach, hip.global_position.distance_to(ankle.global_position))
				var pedal := player.to_global(rig.pedal_position(prefix == "l_"))
				_check(absf(ankle.global_position.distance_to(pedal) - _ankle_offset(MamachariRider.FOOT_PITCH_STANDING).length()) < 0.16, "feet stay over the pedals while standing")
	_check(ride.standing > 0.99, "pushing forward stands up on the pedals")
	_check(pelvis.global_position.y > seated_pelvis.y + 0.03, "the hips rise off the saddle (%.3f -> %.3f)" % [seated_pelvis.y, pelvis.global_position.y])
	_check(pelvis.global_position.z - player.global_position.z > seated_pelvis.z - (player.global_position.z - 1.5 * 150.0 / 60.0) + 0.2, "the hips move forward over the pedals")
	_check(sway_left < -deg_to_rad(4.0) and sway_right > deg_to_rad(4.0), "the bike rocks side to side while standing")
	_check(worst_reach <= MamachariRider.THIGH + MamachariRider.CALF, "the legs are never over-stretched while standing (%.3f m)" % worst_reach)
	await _shot("3_standing")
	await _frames(40)
	_check(ride.standing < 0.01, "sitting down again when the push stops")

	# 跳ぶ：上がるあいだは前輪が上がり、ペダルを水平にそろえて立つ。着地で沈んで、すぐ戻る
	gs.player_y = 0.8
	gs.player_vel_y = 6.0
	await _frames(20)
	_check(rig.rotation.x < -0.05, "the front wheel lifts while rising")
	_check(ride.air > 0.99, "airborne")
	_check(absf(angle_difference(rig.crank_angle, 0.0)) < 0.02 or absf(angle_difference(rig.crank_angle, PI)) < 0.02, "the pedals are level in the air")
	await _shot("4_jump")
	gs.player_vel_y = -6.0
	await _frames(3)
	gs.player_y = 0.0
	gs.player_vel_y = 0.0
	await _frames(2)
	_check(ride.land > 0.3, "landing compresses the bike and rider")
	_check(rig.position.y < PlayerController.BASE_Y - 0.003, "the bike sinks a little on landing")
	await _frames(60)
	_check(ride.land < 0.02 and absf(rig.rotation.x) < 0.001, "the bike is level and settled after landing")

	# 止まる：ブレーキを握り、サドルの前へ降りて左足をつく。右のペダルはこぎ出しの位置
	gs.game_state = Constants.STATE_COUNTDOWN
	await _frames(90)
	_check(rig.visible and ride.foot_down > 0.99, "stopping puts a foot down")
	_check(rig.stand < 0.01, "the kickstand stays up (the rider holds the bike)")
	_check(rig.brake_left > 0.99 and rig.brake_right > 0.99, "the brakes are held when stopped")
	_check(rig.rotation.z < -deg_to_rad(5.0), "the bike leans toward the planted foot")
	var floor_y := player.global_position.y + PlayerController.BASE_Y
	var left_ankle := player.p1_parts["r_ankle"] as Node3D
	_check(absf(left_ankle.global_position.y - floor_y - MamachariRider.GROUND_ANKLE_HEIGHT) < 0.01, "the left sole rests on the floor")
	_check(left_ankle.global_position.x - player.global_position.x > 0.35, "the planted foot is out to the rider's left")
	var right_ankle := player.p1_parts["l_ankle"] as Node3D
	var right_pedal := player.to_global(rig.pedal_position(true))
	_check(absf(right_ankle.global_position.distance_to(right_pedal) - _ankle_offset(MamachariRider.FOOT_PITCH_SEATED).length()) < 0.16, "the right foot stays on its pedal")
	_check(absf(angle_difference(rig.crank_angle, MamachariRide.READY_CRANK)) < 0.02, "the right pedal is brought round to the push-off position")
	var wheel_stopped := rig.wheel_angle
	await _frames(10)
	_check(is_equal_approx(rig.wheel_angle, wheel_stopped), "the wheels do not turn when stopped")
	await _shot("5_stopped_foot_down")

	# 動き出す：足をペダルへ戻して、こぎ出す
	gs.game_state = Constants.STATE_PLAYING
	await _frames(12)
	await _shot("6_push_off")
	await _frames(60)
	_check(ride.foot_down < 0.01, "the foot returns to the pedal when moving again")
	_check(absf(rig.rotation.z) < deg_to_rad(1.0), "the bike stands upright again")

	# 特殊な場面では降りる（エモート・サメ待ち・脱落）
	gs.p1_emote = 18
	await _frames(5)
	_check(not rig.visible, "an emote gets off the bike")
	await _shot("7_emote_on_foot")
	gs.p1_emote = 0
	await _frames(5)
	_check(rig.visible, "the bike comes back after the emote")
	gs.game_state = Constants.STATE_RESULT_CEREMONY
	await _frames(5)
	_check(not rig.visible, "the result ceremony is on foot")
	gs.game_state = Constants.STATE_PLAYING
	gs.net_online = true
	await _frames(5)
	_check(not rig.visible, "online matches do not show the ride yet")
	gs.net_online = false
	gs.p1_ride = RideData.RIDE_NONE
	await _frames(5)
	_check(not rig.visible, "taking the ride off hides the bike")
	_finish()


func _rig() -> MamachariRig:
	for child: Node in player.get_children():
		if child is MamachariRig:
			return child as MamachariRig
	return null


func _ride() -> MamachariRide:
	return (player.get("_ride_controls") as Dictionary).get(1) as MamachariRide


## 足首がペダルの軸から離れているはずの位置（母指球がペダルの上。かかとを pitch_deg 上げたとき）。
func _ankle_offset(pitch_deg: float) -> Vector3:
	var pitch := deg_to_rad(pitch_deg)
	return Vector3(
		0.0,
		MamachariRider.ANKLE_ABOVE_PEDAL * cos(pitch) + MamachariRider.ANKLE_BEHIND_PEDAL * sin(pitch),
		-(MamachariRider.ANKLE_BEHIND_PEDAL * cos(pitch) - MamachariRider.ANKLE_ABOVE_PEDAL * sin(pitch)),
	)


## 手首がグリップの中心から離れているはずの距離（上と外へずらしてある）。
func _wrist_offset(rig: MamachariRig) -> float:
	return Vector2(MamachariRider.WRIST_ABOVE_GRIP, rig.grip_radius() + MamachariRider.WRIST_OUTSIDE_GRIP).length()


func _frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().process_frame


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != SIZE:
		image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	image.save_png(ProjectSettings.globalize_path(OUT + label + ".png"))


func _finish() -> void:
	QuizManager.game_state = _saved.state
	QuizManager.player_analytics = _saved.analytics
	GameManager.settings_path = str(_saved.settings)
	UnlockStore.path = str(_saved.unlocks)
	PlayerSkinStore.path = str(_saved.skins)
	UnlockStore.load_from_disk()
	PlayerSkinStore.load_from_disk()
	for user_path: String in [UNLOCKS, SKINS, SETTINGS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(user_path))
	print("MAMACHARI_RIDE " + JSON.stringify({"passed": _failures.is_empty(), "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
