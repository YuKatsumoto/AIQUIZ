extends "res://tests/hud_diegetic_mock/overlap_runtime.gd"

## 改善3（ロックオン枠）を実際のゴーストの状態（照準位置・溜め量・フェーズ・コンボ）に連動させ、
## 照準→ロックオン→溜め→PERFECT で発射→回避→2 回目で命中、までを実ゲームで流すイメージ映像用モック。
## Movie Maker で全フレームを書き出し、ログの RECORD_START / RECORD_END で切り出す。
## 実行: Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --write-movie <out.avi> --script res://tests/hud_diegetic_mock/lockon_video_bootstrap.gd

const STEP := 1.0 / 60.0
const AIM_GLIDE_SPEED := 6.5
## 枠の半幅・半高さ。溜め 0 → 1 で締まる。
const WIDE := Vector2(1.15, 1.3)
const TIGHT := Vector2(0.68, 0.92)
## 照準が体から外れているときは枠を少し広げて薄くし、重なった瞬間に「カチッ」と締める。
const UNLOCKED_SPREAD := 1.16
const LOCK_DISTANCE := 0.8

var survivor := 1
var frame_root: Node3D
var frame_bars: Array[MeshInstance3D] = []
var guide_bars: Array[MeshInstance3D] = []
var frame_material: StandardMaterial3D
var guide_material: StandardMaterial3D
var dot_root: Node3D
var dot_material: StandardMaterial3D
var haunt_root: Node3D
var combo_label: Label3D
var hp_segments: Array[MeshInstance3D] = []
var hp_root: Node3D
var last_phase := -1
var phase_age := 0.0
var lock_amount := 0.0
var shown_combo := 0
var combo_pop := 0.0

func run() -> void:
	await setup_world()
	if not await enter_ghost_aiming():
		return
	ghost.set("_combo", 0)
	survivor = 1 if gs.p1_alive else 2
	hide_hud = true
	clear_mock()
	camera = get_viewport().get_camera_3d()
	hide_original_aim()
	build_live_hp_ring()
	build_live_lockon()
	await frames(2)
	event("RECORD_START")
	await choreography()
	event("RECORD_END")
	get_tree().quit(0)

# --- 流れ ---

func choreography() -> void:
	# 照準を生存プレイヤーから外す: 枠は床の一点（突進の着地点）の上に立つ。
	await glide_aim(func() -> Vector2: return survivor_offset() + Vector2(-3.4, 2.6), 80)
	await hold_aim(30)
	event("AIM_BACK")
	# 照準を戻す: 体に重なった瞬間に枠が締まる（ロックオン）。
	await glide_aim(survivor_offset, 70)
	await hold_aim(24)
	# 長押しで溜める → PERFECT 帯（0.72〜0.94）で離す。
	event("CHARGE_1")
	key(KEY_CTRL, true)
	await charge_until(0.82)
	key(KEY_CTRL, false)
	# 離したことはゲーム側が次のフレームで受け取るので、確定した溜め量はその後に読む。
	await frames(2)
	event("RELEASE_1 power=%.2f perfect=%s" % [float(ghost.get("_last_charge_power")), str(ghost.get("_perfect_charge"))])
	# 生存側は中央へ回避する。
	await frames(1)
	await dodge(26)
	await wait_phase(ghost.Phase.COOLDOWN, 300)
	event("COOLDOWN")
	await wait_phase(ghost.Phase.AIMING, 900)
	event("AIMING_AGAIN")
	# 命中で後ろへ飛ばされても後端（のこぎり側）まで行かないよう、先に前へ歩いておく。
	key(KEY_W, true)
	await hold_aim(90)
	key(KEY_W, false)
	# 2 回目: 照準を合わせ、半分ほど溜めて（PERFECT 外）発射。生存側は動かない。
	await glide_aim(survivor_offset, 60)
	await hold_aim(16)
	event("CHARGE_2")
	key(KEY_CTRL, true)
	await charge_until(0.5)
	key(KEY_CTRL, false)
	await frames(2)
	event("RELEASE_2 power=%.2f perfect=%s" % [float(ghost.get("_last_charge_power")), str(ghost.get("_perfect_charge"))])
	var combo_before := int(ghost.get("_combo"))
	for i in range(240):
		await frames(1)
		if int(ghost.get("_combo")) > combo_before:
			event("HIT combo=%d" % int(ghost.get("_combo")))
			break
	await frames(150)

func glide_aim(target: Callable, count: int) -> void:
	for i in range(count):
		if ghost.phase == ghost.Phase.AIMING:
			var offset: Vector2 = ghost.get("_aim_offset")
			ghost.set("_aim_offset", offset.move_toward(target.call(), AIM_GLIDE_SPEED * STEP))
		await frames(1)

func hold_aim(count: int) -> void:
	await glide_aim(func() -> Vector2: return ghost.get("_aim_offset"), count)

## 溜めている間も照準は生存プレイヤーに付いていく。
func charge_until(target: float) -> void:
	for i in range(120):
		await glide_aim(survivor_offset, 1)
		if float(ghost.get("_charge_amount")) >= target:
			return

func dodge(count: int) -> void:
	var pelvis := survivor_pelvis()
	# D は -X（画面の右）、A は +X（画面の左）。中央へ向かう側を押す。
	var code := KEY_D if pelvis.global_position.x > 0.0 else KEY_A
	event("DODGE")
	key(code, true)
	await frames(count)
	key(code, false)

func wait_phase(target: int, limit: int) -> void:
	for i in range(limit):
		await frames(1)
		if ghost.phase == target:
			return

func survivor_pelvis() -> Node3D:
	return parts_of(survivor).get("pelvis") as Node3D

func survivor_offset() -> Vector2:
	var pelvis := survivor_pelvis()
	var origin: Vector3 = ghost.get("_aim_origin")
	return Vector2(pelvis.global_position.x - origin.x, pelvis.global_position.z - origin.z)

func key(code: int, pressed: bool) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.physical_keycode = code
	input.location = KEY_LOCATION_RIGHT if code == KEY_CTRL else KEY_LOCATION_UNSPECIFIED
	input.pressed = pressed
	Input.parse_input_event(input)

func event(label_text: String) -> void:
	print("LOCKON_VIDEO %s frame=%d" % [label_text, Engine.get_frames_drawn()])

# --- 実状態に連動するロックオン枠 ---

func build_live_lockon() -> void:
	frame_material = live_material(GHOST_COLOR, 2.4)
	guide_material = live_material(Color(PERFECT_COLOR, 0.45), 1.0)
	frame_root = Node3D.new()
	track(frame_root, world)
	frame_bars = make_bracket_bars(frame_material)
	guide_bars = make_bracket_bars(guide_material)
	dot_material = live_material(Color(GHOST_COLOR, 0.9), 1.6)
	dot_material.no_depth_test = false
	dot_root = Node3D.new()
	track(dot_root, world)
	add_arc(dot_root, 0.1, 0.2, 0.0, TAU, dot_material)
	haunt_root = Node3D.new()
	track(haunt_root, world)
	var title := label("HAUNT", 70, 0.009, GHOST_COLOR, 20)
	title.position = Vector3(0.0, 0.62, 0.0)
	title.outline_modulate = Color(0.0, 0.1, 0.2, 0.9)
	haunt_root.add_child(title)
	combo_label = label("×1", 130, 0.009, Color(0.85, 1.0, 1.0), 28)
	combo_label.outline_modulate = Color(0.0, 0.35, 0.55, 0.85)
	combo_label.position = Vector3(0.0, -0.15, 0.0)
	haunt_root.add_child(combo_label)
	haunt_root.visible = false
	followers.append(update_live_lockon)

func live_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := glow_material(color, energy, true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 10
	return m

func make_bracket_bars(material: StandardMaterial3D) -> Array[MeshInstance3D]:
	var bars: Array[MeshInstance3D] = []
	for k in range(8):
		var bar := box(Vector3.ONE, material)
		frame_root.add_child(bar)
		bars.append(bar)
	return bars

## 四隅のカギ（角ごとに横棒と縦棒）を、半幅・半高さに合わせて並べ直す。
func layout_brackets(bars: Array[MeshInstance3D], half: Vector2, thickness: float) -> void:
	var arm := 0.34
	var k := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			bars[k].scale = Vector3(arm, thickness, 0.01)
			bars[k].position = Vector3(sx * (half.x - arm * 0.5), sy * half.y, 0.0)
			bars[k + 1].scale = Vector3(thickness, arm, 0.01)
			bars[k + 1].position = Vector3(sx * half.x, sy * (half.y - arm * 0.5), 0.0)
			k += 2

func in_band(power: float) -> bool:
	return power >= PERFECT_MIN and power <= PERFECT_MAX

func update_live_lockon() -> void:
	camera = get_viewport().get_camera_3d()
	var current: int = ghost.phase
	if current != last_phase:
		last_phase = current
		phase_age = 0.0
	else:
		phase_age += STEP
	var charging := bool(ghost.get("_charging_input"))
	var released_power := float(ghost.get("_last_charge_power"))
	var released_perfect := bool(ghost.get("_perfect_charge"))
	var power := 0.0
	var color := GHOST_COLOR
	var alpha := 1.0
	var show_guide := false
	var show_dot := false
	if current == ghost.Phase.AIMING:
		show_dot = true
		if charging:
			power = float(ghost.get("_charge_amount"))
			show_guide = not in_band(power)
			color = PERFECT_COLOR if in_band(power) else GHOST_COLOR.lerp(Color.WHITE, power * 0.6)
	elif current == ghost.Phase.WINDUP:
		# 離した瞬間の大きさで止め、点滅して「発射」を知らせる。
		show_dot = true
		power = released_power
		color = PERFECT_COLOR if released_perfect else Color.WHITE
		alpha = 1.0 if int(phase_age / 0.06) % 2 == 0 else 0.3
	elif current == ghost.Phase.CHARGING:
		power = released_power
		color = PERFECT_COLOR if released_perfect else Color.WHITE
		alpha = clampf(1.0 - phase_age / 0.25, 0.0, 1.0)
	else:
		# サメが戻るまで（クールダウン）は枠を消し、撃てるようになった瞬間に現れて知らせる。
		alpha = 0.0
	if current == ghost.Phase.AIMING and phase_age < 0.25:
		alpha *= phase_age / 0.25
	var aim := aim_point()
	var pelvis := survivor_pelvis()
	var locked := current == ghost.Phase.AIMING and pelvis != null and Vector2(aim.x - pelvis.global_position.x, aim.z - pelvis.global_position.z).length() < LOCK_DISTANCE
	lock_amount = move_toward(lock_amount, 1.0 if locked or current != ghost.Phase.AIMING else 0.0, STEP / 0.08)
	var appear := 1.0 + 0.35 * clampf(1.0 - phase_age / 0.25, 0.0, 1.0) if current == ghost.Phase.AIMING else 1.0
	var spread := lerpf(UNLOCKED_SPREAD, 1.0, lock_amount) * appear
	alpha *= lerpf(0.7, 1.0, lock_amount)
	apply_frame(aim, power, spread, color, alpha, show_guide, current)
	dot_root.visible = show_dot
	dot_root.global_position = aim + Vector3(0.0, 0.05, 0.0)
	update_live_hp_ring()
	update_combo()

## 枠の見た目。power は溜め量（0 で広く 1 で締まる）、spread はロックオン前の広がりと出現時の拡大。
func apply_frame(aim: Vector3, power: float, spread: float, color: Color, alpha: float, show_guide: bool, _phase: int) -> void:
	layout_brackets(frame_bars, WIDE.lerp(TIGHT, power) * spread, 0.07)
	layout_brackets(guide_bars, WIDE.lerp(TIGHT, (PERFECT_MIN + PERFECT_MAX) * 0.5), 0.035)
	for bar in guide_bars:
		bar.visible = show_guide
	frame_material.albedo_color = Color(color, alpha)
	frame_material.emission = color
	frame_root.global_transform = Transform3D(camera.global_basis, aim + Vector3(0.0, 1.1, 0.0))

func update_combo() -> void:
	var combo := int(ghost.get("_combo"))
	var shark := ghost.get("_shark") as Node3D
	if combo != shown_combo:
		shown_combo = combo
		combo_pop = 1.0
		combo_label.text = "×%d" % combo
	haunt_root.visible = combo > 0 and shark != null and is_instance_valid(shark)
	if not haunt_root.visible:
		return
	combo_pop = move_toward(combo_pop, 0.0, STEP / 0.3)
	var pop := 1.0 + 0.25 * combo_pop * combo_pop
	var anchor := shark.global_position + Vector3(0.0, 3.0, 0.0)
	# 突進でサメがカメラの近くに来ても画面いっぱいにならないよう、近いほど縮める（遠くでは等倍）。
	var near := clampf(camera.global_position.distance_to(anchor) / 24.0, 0.3, 1.0)
	haunt_root.global_transform = Transform3D(camera.global_basis.scaled(Vector3.ONE * pop * near), anchor)

# --- 生存側の足元 HP リング（HP の増減に追従） ---

func build_live_hp_ring() -> void:
	hp_root = Node3D.new()
	track(hp_root, world)
	var centers := [105.0, 0.0, -105.0]
	for slot in range(3):
		var segment := MeshInstance3D.new()
		segment.mesh = arc_mesh(0.78, 1.0, deg_to_rad(centers[slot] - 45.0), deg_to_rad(centers[slot] + 45.0))
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hp_root.add_child(segment)
		hp_segments.append(segment)

func update_live_hp_ring() -> void:
	var pelvis := survivor_pelvis()
	if pelvis == null or not is_instance_valid(pelvis):
		hp_root.visible = false
		return
	hp_root.global_position = Vector3(pelvis.global_position.x, StageConstants.FLOOR_TOP_Y + 0.03, pelvis.global_position.z)
	var hp := gs.get_player_hp(survivor)
	for slot in range(3):
		var filled := slot < hp
		if int(hp_segments[slot].get_meta("filled", -1)) != int(filled):
			hp_segments[slot].set_meta("filled", int(filled))
			hp_segments[slot].material_override = glow_material(color_of(survivor), 1.6, true) if filled else glow_material(Color(0.1, 0.12, 0.16, 0.55), 0.0, true)
