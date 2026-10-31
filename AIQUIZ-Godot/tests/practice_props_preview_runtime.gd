extends Node

## 練習の舞台の小物の見た目の確かめ（docs/new_tutorial/phase4_design.md 3.4、phase5_design.md 4.4）。
## ゲーム画面（scenes/game_world.tscn）を練習のモードで開き、監督（PracticeDirector）は外して、止めたコンベアの上に
## 看板の壁（1-1・1-2・1-6 の中身）、床の印（端の光・ゾーン・矢印・さくの光）、的のマーク、ハテナの新しい動きを
## 順に出して、ゲームと同じカメラ（プレイヤーの後ろ）から撮る。1-6 の実演（端・海）は、監督がカメラを右へ向ける
## （practice_camera_look）のと同じ見え方を、同じ目の位置のカメラで作って撮る。
## 段階5（コース②）：看板の壁（2-1・2-2・2-3 の中身）、ハテナのハイタッチ・雲ですべる・おどる、ハテナの小窓
## （ステージの上・本物のポーズ画面の暗い幕の上・明るい地の上）も撮る（20 番から）。
## 段階6（コース③。phase6_design.md 3.3）：看板の壁の 3-1（P1・P2 のキーの組）と 3-4（押し合う2人・離す → 押す）の中身を、
## 2人のときのカメラ（camera_controller.gd の引きの画角）と近くから撮る（40 番から）。
## 段階9（phase9_design.md 1章）：ライブの Blender で作った練習の動き（両手を広げる・胸をはる・×・首をかしげる・あちゃー・
## うなずく）と、跳ぶ → 着地・雲に乗る動きのつながりを確かめて撮る（18・19 番）。
##   Godot --path . --script tests/practice_props_preview_bootstrap.gd
## 撮った画面は artifacts/practice_props/。最後に {"passed", "checks", "failures"} を出す。

const OUT := "res://artifacts/practice_props/"
const GAME_WORLD := "res://scenes/game_world.tscn"
const QUIZ_WALL := "res://scenes/quiz_wall.tscn"
## 1人のときのゲームのカメラ（camera_controller.gd：目は player + (0, 3.0, −5.6)、注視点は player + (0, 1.0, 8)、画角 50）
const EYE_OFFSET := Vector3(0.0, 3.0, -5.6)
const LOOK_OFFSET := Vector3(0.0, 1.0, 8.0)
const FOV := 50.0
## 看板の壁の置き場（台本①の 1.4：14m 先）と、ハテナの立ち位置（台本①の 1.3：x = +9.5、壁の 1.2m 手前）
const SIGN_Z := 14.0
const HATENA_SPOT := Vector3(9.5, 0.0, SIGN_Z - 1.2)
## 1-6 で海に落ちたハテナが見えるカメラの例（画面の右の端の上、高さ約 11m から見下ろす）
const SEA_EYE := Vector3(-8.5, 9.5, -3.0)
const SEA_LOOK := Vector3(-14.0, -7.5, 8.0)
## 海に浮いたハテナを近くで見るカメラ（床と観客席の間の海の上）
const TRENCH_EYE := Vector3(-13.8, -5.0, -1.5)
const TRENCH_LOOK := Vector3(-15.5, -9.0, 7.0)
## 雲に乗って床の上に浮かせるときの足の高さ（雲は足の裏から 0.83m 下まである）
const CLOUD_FOOT_Y := 0.9
## 2-1 のハイタッチ：ハテナはプレイヤーの3m前、出した手は床から約 2.4m（台本②の 2-1）
const HIGH_FIVE_FRONT := 3.0
const HIGH_FIVE_HAND_Y := 2.4
## ハイタッチの雲の大きさと、跳ぶプレイヤーの置き場（手から手前へ。B の判定は横に 1.0m 以内）
const HIGH_FIVE_CLOUD_SIZE := 0.6
const HIGH_FIVE_PLAYER_GAP := 0.9
## ハイタッチを横から見るカメラ（プレイヤーとハテナの手の高さを比べる）
const SIDE_EYE := Vector3(-7.5, 1.9, 1.6)
const SIDE_LOOK := Vector3(0.6, 1.5, 1.6)
## 本番のジャンプ（game_state.gd の JUMP_FORCE・GRAVITY：高さ約 1.36m、頂点まで約 0.39 秒）
const JUMP_FORCE := 7.0
const JUMP_APEX_SECONDS := 0.39
## ハテナの小窓の層（phase5_design.md 1章：コーチの吹き出しとハテナの小窓は 106）
const PORTRAIT_LAYER := 106
## 2人のときのゲームのカメラ（camera_controller.gd：目は (0, 4.5, 2人の z − 9)、注視点は (0, 1.0, 2人の z + 8)、画角 50）
const DUO_EYE := Vector3(0.0, 4.5, -9.0)
const DUO_LOOK := Vector3(0.0, 1.0, 8.0)

var gs: QuizGameState
var world: Node3D
var failures: Array[String] = []
var checks := 0
var _look_camera: Camera3D = null


func _ready() -> void:
	# 本物のポーズ画面を開いて（木が止まって）も、確かめを進める
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if not await _open_world():
		_finish()
		return
	# 「-- only=course3」で段階6の看板だけ撮る（調べるとき用）
	if "only=course3" in OS.get_cmdline_user_args():
		await _sign_wall_course3()
		_finish()
		return
	await _sign_wall()
	await _floor_marks()
	await _target_mark()
	await _hatena_demo()
	await _hatena_poses()
	await _hatena_practice_moves()
	await _sign_wall_course2()
	await _hatena_high_five()
	await _hatena_dance_and_portrait()
	await _sign_wall_course3()
	_finish()


# ---------- ゲーム画面 ----------

func _open_world() -> bool:
	gs = QuizManager.game_state
	QuizManager.player_analytics = null
	gs.mode = Constants.MODE_PRACTICE
	gs.num_players = 1
	world = load(GAME_WORLD).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	# 監督は外す（台本を進めず、小物だけを並べる）。監督のハテナとオーバーレイもいっしょに外す。
	var director := world.get("practice_director") as Node
	if director != null:
		world.remove_child(director)
		director.free()
	var stray := world.get_node_or_null("HatenaGuide")
	if stray != null:
		world.remove_child(stray)
		stray.free()
	var rules := MatchRules.new()
	rules.world_speed = 0.0
	rules.input_locked = true
	rules.record_results = false
	var none: Array[QuizItem] = []
	gs.start_practice_round(none, 1, rules)
	gs.practice_place_player(1, 0.0, 0.0)
	await frames(40)
	check(gs.game_state == Constants.STATE_PLAYING, "the practice round is playing (%s)" % gs.game_state)
	return true


# ---------- 看板の壁 ----------

func _sign_wall() -> void:
	var sign := PracticeSignWall.new()
	sign.name = "PreviewSignWall"
	world.add_child(sign)
	sign.setup(GameManager.graphics_quality)
	sign.position = Vector3(0.0, 0.0, SIGN_Z)
	sign.set_title(PackedStringArray(["テストピアへ ようこそ！"]))
	sign.set_panels([{"key": &"q1", "picture": &"question"}, {"key": &"q2", "picture": &"question"}])
	var hatena := _new_hatena("SignHatena")
	hatena.place_at(HATENA_SPOT)
	hatena.play(&"wave")
	var events := {"landed": false, "flown": false}
	sign.landed.connect(func() -> void: events.landed = true, CONNECT_ONE_SHOT)
	var drop := sign.drop_in(0.55)
	await seconds(0.42)
	check(sign.position.y > 1.0, "the sign wall comes down from the sky (y %.1f)" % sign.position.y)
	await capture("01a_sign_dropping")
	await drop
	check(bool(events.landed) and is_equal_approx(sign.position.y, 0.0), "the sign wall lands on its spot")
	await seconds(0.5)
	check(is_equal_approx(sign.scale.y, 1.0), "the landing squash settles")
	await capture("01_sign_welcome")

	# 1-2 ステップA：← → の大きなキーと A D。左を ✓
	sign.set_title(PackedStringArray(["← → で よこに うごこう"]))
	sign.set_panels([{"key": &"left", "glyph": "←", "sub": "A"}, {"key": &"right", "glyph": "→", "sub": "D"}])
	check(not sign.is_panel_done(&"left"), "new panels start without a tick")
	sign.tick_panel(&"left")
	check(sign.is_panel_done(&"left") and not sign.is_panel_done(&"right"), "tick_panel ticks only that panel")
	await seconds(0.1)
	await capture("02a_sign_tick_flash")
	await seconds(0.6)
	await capture("02_sign_keys_lr")

	# 1-2 ステップB：↑ ↓ と W S。点滅（「キーを おして みて」）
	sign.set_title(PackedStringArray(["↑ ↓ で まえと うしろ"]))
	sign.set_panels([{"key": &"up", "glyph": "↑", "sub": "W"}, {"key": &"down", "glyph": "↓", "sub": "S"}])
	check(not sign.is_panel_done(&"left"), "old keys are gone after set_panels")
	sign.blink_panels()
	await seconds(0.05)
	await capture("03_sign_keys_fb_blink")
	sign.tick_panel(&"up")
	sign.tick_panel(&"down")
	await seconds(1.2)
	await capture("03b_sign_keys_fb_done")

	# 1-6：波とサメ。1行と2行の看板
	sign.set_title(PackedStringArray(["ゆかの そとは うみ"]))
	sign.set_panels([{"key": &"wave", "picture": &"wave"}, {"key": &"shark", "picture": &"shark"}])
	await seconds(0.2)
	await capture("04_sign_edge")
	sign.set_title(PackedStringArray(["うみに おちたら", "ハートが あっても アウト"]))
	await seconds(0.2)
	await capture("04b_sign_edge_two_lines")
	_save_closeup("04c_sign_closeup", Vector3(0.0, 2.2, SIGN_Z - 9.0), Vector3(0.0, 1.8, SIGN_Z))
	await seconds(0.1)
	await capture("04c_sign_closeup")
	_release_look()

	# 空へ戻る
	sign.flew_away.connect(func() -> void: events.flown = true, CONNECT_ONE_SHOT)
	var away := sign.fly_away(0.6)
	await seconds(0.3)
	await capture("05_sign_fly_away")
	await away
	check(bool(events.flown) and not sign.visible, "the sign wall flies away and hides")
	check(is_equal_approx(sign.position.y, 0.0), "after flying away the sign waits on its spot (hidden)")
	sign.queue_free()
	hatena.queue_free()
	await frames(2)


# ---------- 床の印 ----------

func _floor_marks() -> void:
	var marks := PracticeFloorMarks.new()
	world.add_child(marks)
	# 1-6 タスクA：左右の端とギリギリ ゾーン（x = ±9.5〜±12）
	marks.show_edge_glow([&"left", &"right"])
	marks.show_zones([Rect2(9.5, StageConstants.FLOOR_BACK_Z, 2.5, 80.0), Rect2(-12.0, StageConstants.FLOOR_BACK_Z, 2.5, 80.0)])
	gs.practice_place_player(1, 0.0, 0.0)
	await seconds(0.45)
	await capture("06_floor_side_edges")
	gs.practice_place_player(1, 10.3, 2.0)
	marks.flash_zone(0)
	await seconds(0.08)
	await capture("06b_floor_zone_flash")
	# 1-6 タスクB：うしろの端（遊ぶカメラでは足もとより後ろは映らないので、振り向いたカメラで見る）
	marks.show_edge_glow([&"back"])
	marks.show_zones([Rect2(-12.0, StageConstants.FLOOR_BACK_Z, 24.0, 2.5)])
	gs.practice_place_player(1, 0.0, -9.0)
	await seconds(0.4)
	await capture("07a_floor_back_game_camera")
	_save_closeup("07_floor_back", Vector3(0.0, 4.5, -2.0), Vector3(0.0, -1.2, -12.5))
	await seconds(0.4)
	await capture("07_floor_back")
	_release_look()
	# 正解のドアへの矢印（2回失敗）：プレイヤーの所から、x = +3.5（青）のドアへ。12m 先にクイズ壁
	marks.clear_all()
	gs.practice_place_player(1, 0.0, 0.0)
	var wall := _quiz_wall(12.0, "1 + 1 = ?", ["3", "2"])
	marks.show_arrow(Vector2(0.0, 0.0), -3.5)
	check(marks.has_arrow(), "show_arrow makes an arrow")
	await seconds(0.5)
	await capture("08_floor_arrow")
	marks.show_arrow(Vector2(-6.0, 0.0), 3.5)
	gs.practice_place_player(1, -6.0, 0.0)
	await seconds(0.3)
	await capture("08b_floor_arrow_far")
	marks.hide_arrow()
	check(not marks.has_arrow(), "hide_arrow removes it")
	# 見えないさく：横（x = +10）と前（z = +8）
	gs.practice_place_player(1, 9.7, 3.0)
	marks.flash_fence(Vector3(10.0, 0.0, 3.0))
	marks.flash_fence(Vector3(2.0, 0.0, 8.0))
	await seconds(0.08)
	await capture("09_floor_fence_flash")
	await seconds(0.6)
	check(marks.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("FenceFlash") and not n.is_queued_for_deletion()).is_empty(),
		"fence flashes fade out")
	marks.clear_all()
	wall.queue_free()
	marks.queue_free()
	gs.practice_place_player(1, 0.0, 0.0)
	await frames(2)


# ---------- 的のマーク ----------

func _target_mark() -> void:
	var wall := _quiz_wall(11.0, "ドアの あいだの かべに\nぶつかって みよう", ["×", "×"])
	var mark := PracticeFloorMarks.attach_target_mark(wall)
	check(mark != null and mark.get_parent() == wall, "attach_target_mark puts the mark on the wall")
	await seconds(0.5)
	await capture("10_target_mark")
	wall.queue_free()
	await frames(2)


# ---------- ハテナ：1-6 の実演 ----------

func _hatena_demo() -> void:
	var hatena := _new_hatena("DemoHatena")
	hatena.place_at(HATENA_SPOT)
	var cloud := hatena.get("_cloud") as MeshInstance3D
	if cloud != null:
		var box: AABB = cloud.transform * cloud.get_aabb()
		print("cloud bounds (hatena space, before BODY_SCALE): ", box, " lowest below the feet: %.2f m" % (-box.position.y * HatenaGuide.BODY_SCALE))
	# 床へ飛び降りて、画面の右の端（x = −10.5、z = +6）へ歩く
	await hatena.hop_to(Vector3(6.0, 0.0, 9.0), 0.6)
	var walk := hatena.walk_to(Vector3(-10.5, 0.0, 6.0))
	await seconds(1.2)
	check(hatena.is_moving(), "walk_to moves along")
	await capture("11_hatena_walk")
	_save_closeup("", Vector3(0.0, 3.0, -5.6), Vector3(-7.5, 0.0, 7.0))
	await walk
	check(Vector2(hatena.position.x, hatena.position.z).distance_to(Vector2(-10.5, 6.0)) < 0.01, "walk_to arrives")
	await seconds(0.3)
	await capture("12_hatena_at_edge")
	# 海に落ちる所：端（x = −12）から 3.5m 外。端のすぐ外だと、床の土台（海底まで続く箱）に隠れて
	# どのカメラからもほとんど見えない。海の中は、端の上の高い所からのカメラ（SEA_EYE）で撮る。
	var sea := Vector3(-15.5, StageConstants.OCEAN_SURFACE_Y, 7.0)
	var fall := hatena.fall_into_sea(sea, 0.7)
	await seconds(0.12)
	await capture("13a_hatena_slip")
	_save_closeup("", SEA_EYE, SEA_LOOK)
	await seconds(0.25)
	await capture("13b_hatena_falling")
	await fall
	check(hatena.is_in_sea() and is_equal_approx(hatena.position.y, StageConstants.OCEAN_SURFACE_Y), "fall_into_sea ends floating in the sea")
	hatena.set_flailing(true)
	await seconds(0.5)
	await capture("14_hatena_flailing")
	_save_closeup("", TRENCH_EYE, TRENCH_LOOK)
	await seconds(0.1)
	await capture("14b_hatena_flailing_close")
	_save_closeup("", Vector3(0.0, 3.0, -5.6), Vector3(-7.5, 0.0, 7.0))
	await seconds(0.05)
	await capture("14x_hatena_sea_from_game_eye")
	_save_closeup("", SEA_EYE, SEA_LOOK)
	_save_closeup("", TRENCH_EYE, TRENCH_LOOK)
	var ride := hatena.ride_cloud_to(HATENA_SPOT + Vector3(0.0, CLOUD_FOOT_Y, 0.0), 1.4)
	await seconds(0.3)
	await capture("15a_hatena_cloud_arriving")
	_save_closeup("", SEA_EYE, SEA_LOOK)
	await seconds(0.3)
	check(not hatena.is_in_sea(), "riding the cloud leaves the sea")
	await capture("15b_hatena_cloud_rising")
	_release_look()
	await ride
	check(hatena.has_cloud() and hatena.position.distance_to(HATENA_SPOT + Vector3(0.0, CLOUD_FOOT_Y, 0.0)) < 0.01, "ride_cloud_to arrives with the cloud")
	hatena.face_toward(Vector3(0.0, 0.0, 0.0))
	hatena.tremble(1.2)
	await seconds(0.3)
	await capture("16_hatena_tremble_on_cloud")
	hatena.queue_free()
	await frames(2)


# ---------- ハテナ：ポーズ・よける・回る ----------

func _hatena_poses() -> void:
	var names := ["cross", "tilt", "spin", "dodge", "walk"]
	var hatenas: Array[HatenaGuide] = []
	for i: int in range(names.size()):
		var hatena := _new_hatena("Pose_%s" % names[i])
		hatena.place_at(Vector3(5.6 - i * 2.8, 0.0, 6.0))
		hatenas.append(hatena)
	hatenas[0].play(&"cross")
	hatenas[1].play(&"tilt")
	await seconds(0.3)
	hatenas[2].spin()
	hatenas[3].dodge(1.0)
	hatenas[4].walk_to(Vector3(-5.6, 0.0, 9.0), 1.0)
	await seconds(0.22)
	await capture("17_hatena_poses")
	await seconds(1.0)
	check(hatenas[3].position.distance_to(Vector3(5.6 - 3 * 2.8, 0.0, 6.0)) < 0.01, "dodge keeps the hatena's spot")
	hatenas[0].play(&"wave")
	await seconds(0.3)
	check(not (hatenas[0].get_node("CrossMark") as Node3D).visible, "the next play ends the cross pose")
	# ハテナの頭の上（吹き出しの所）が画面に入る
	var anchor := hatenas[1].bubble_anchor(get_viewport().get_camera_3d())
	check(anchor.is_finite() and Rect2(Vector2.ZERO, Vector2(1280, 720)).has_point(anchor), "bubble anchor is on screen (%s)" % anchor)
	for hatena: HatenaGuide in hatenas:
		hatena.queue_free()
	await frames(2)


# ---------- 段階9：ライブの Blender で作った練習の動き（phase9_design.md 1章） ----------

func _hatena_practice_moves() -> void:
	var moves: Array[StringName] = [&"open_arms", &"proud", &"cross", &"tilt", &"oops", &"nod"]
	var hatenas: Array[HatenaGuide] = []
	for i: int in range(moves.size()):
		var hatena := _new_hatena("Move_%s" % moves[i])
		hatena.place_at(Vector3(7.0 - i * 2.8, 0.0, 6.0))
		hatenas.append(hatena)
	check(hatenas[0].has_practice_moves(), "the practice moves (mascot_practice.glb) are loaded")
	var body_meshes := hatenas[0].mascot.find_children("*", "MeshInstance3D", true, false)
	check(not body_meshes.is_empty() and body_meshes.all(func(m: Node) -> bool:
		return (m as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON), "the guide hatena casts a shadow on the floor")
	for i: int in range(moves.size()):
		hatenas[i].play(moves[i])
	await seconds(0.5)
	for i: int in range(moves.size()):
		var clip: StringName = HatenaGuide.ACTIONS[moves[i]]
		check(hatenas[i].mascot.action == clip and hatenas[i].mascot.player.current_animation == String(clip),
			"%s plays %s (%s)" % [moves[i], clip, hatenas[i].mascot.player.current_animation])
	_save_closeup("", Vector3(0.0, 2.4, -4.5), Vector3(0.0, 1.0, 6.0))
	await seconds(0.05)
	await capture("18_hatena_practice_moves")
	await seconds(0.7)
	await capture("18b_hatena_practice_moves_later")
	_release_look()
	for hatena: HatenaGuide in hatenas:
		hatena.queue_free()
	await frames(2)
	# 跳ぶ → 着地 → 台本の動き。跳んでいる間に play しても、着地のあとに変わる
	var hopper := _new_hatena("HopHatena")
	hopper.place_at(Vector3(3.0, 0.0, 8.0))
	hopper.play(&"wave")
	await seconds(0.3)
	var hop := hopper.hop_to(Vector3(-3.0, 0.0, 8.0), 0.8)
	await seconds(0.3)
	check(hopper.mascot.action == HatenaGuide.HOP_CLIP, "hop_to plays the hop move (%s)" % hopper.mascot.action)
	hopper.play(&"clap")
	check(hopper.mascot.action == HatenaGuide.HOP_CLIP, "play during the hop waits for the landing")
	await capture("19_hatena_hop")
	await hop
	await frames(1)
	check(hopper.mascot.action == HatenaGuide.LAND_CLIP, "the hop ends with the landing move (%s)" % hopper.mascot.action)
	await seconds(0.05)
	await capture("19b_hatena_land")
	await seconds(HatenaGuide.LAND_SECONDS + 0.1)
	check(hopper.mascot.action == &"clap", "after the landing the hatena does the move given during the hop (%s)" % hopper.mascot.action)
	# 雲で飛ぶ間は雲に乗る動き。着いたら台本の動き。雲の上で動きを指定していないときも雲に乗る動き
	var ride := hopper.ride_cloud_to(Vector3(0.0, CLOUD_FOOT_Y, 8.0), 1.0)
	await seconds(0.5)
	check(hopper.mascot.action == HatenaGuide.RIDE_CLIP, "ride_cloud_to plays the ride move (%s)" % hopper.mascot.action)
	await capture("19c_hatena_ride")
	await ride
	await frames(1)
	check(hopper.mascot.action == &"clap", "after the cloud ride the hatena goes back to its move (%s)" % hopper.mascot.action)
	hopper.play(&"idle")
	await frames(1)
	check(hopper.mascot.action == HatenaGuide.RIDE_CLIP, "idle on the cloud is the ride move (%s)" % hopper.mascot.action)
	hopper.set_cloud(false)
	await frames(1)
	check(hopper.mascot.action == &"idle", "idle off the cloud is the stand idle (%s)" % hopper.mascot.action)
	# 跳んでいる途中で place_at（レッスンが変わったときなど）：跳ぶ動きをやめて台本の動きへ
	hopper.play(&"point")
	hopper.hop_to(Vector3(3.0, 0.0, 8.0), 0.8)
	await seconds(0.2)
	hopper.place_at(Vector3(3.0, 0.0, 8.0))
	await frames(1)
	check(hopper.mascot.action == &"point", "place_at during a hop goes back to the move (%s)" % hopper.mascot.action)
	hopper.queue_free()
	await frames(2)


# ---------- 段階5：看板の壁（2-1・2-2・2-3） ----------

func _sign_wall_course2() -> void:
	gs.practice_place_player(1, 0.0, 0.0)
	var sign := PracticeSignWall.new()
	sign.name = "PreviewSignWall2"
	world.add_child(sign)
	sign.setup(GameManager.graphics_quality)
	sign.position = Vector3(0.0, 0.0, SIGN_Z)
	# 2-1：横長の「スペース」キーと、雲に乗ったハテナ
	sign.set_title(PackedStringArray(["スペースで ジャンプ"]))
	sign.set_panels([{"key": &"space", "picture": &"space"}, {"key": &"hatena", "picture": &"hatena_cloud"}])
	await seconds(0.3)
	await capture("20_sign_space")
	_save_closeup("", Vector3(0.0, 2.2, SIGN_Z - 9.0), Vector3(0.0, 1.8, SIGN_Z))
	await seconds(0.1)
	await capture("20b_sign_space_closeup")
	# 6秒スペースなし：「スペース」のパネルだけ点滅
	sign.blink_panel(&"space")
	await seconds(0.05)
	check(_panel_border(sign, 0).is_equal_approx(PracticeSignWall.BLINK_COLOR)
		and _panel_border(sign, 1).is_equal_approx(PracticeSignWall.STEEL), "blink_panel blinks only that panel")
	await capture("20c_sign_space_blink")
	await seconds(1.1)
	sign.tick_panel(&"space")
	await seconds(0.7)
	await capture("20d_sign_space_done")
	_release_look()

	# 2-2：「1」「2」「3」の小さなキーと、おどるハテナ。押した数字に ✓
	sign.set_title(PackedStringArray(["1 2 3 で おどろう"]))
	sign.set_panels([{"key": &"digits", "keys": ["1", "2", "3"]}, {"key": &"dance", "picture": &"hatena_dance"}])
	check(not sign.is_panel_key_done(&"digits", 0) and not sign.is_panel_done(&"digits"), "new key panels start without ticks")
	await seconds(0.3)
	await capture("21_sign_digits")
	sign.tick_panel_key(&"digits", 0)
	check(sign.is_panel_key_done(&"digits", 0) and not sign.is_panel_key_done(&"digits", 1) and not sign.is_panel_done(&"digits"),
		"tick_panel_key ticks only that key")
	await seconds(0.1)
	_save_closeup("", Vector3(0.0, 2.2, SIGN_Z - 9.0), Vector3(0.0, 1.8, SIGN_Z))
	await seconds(0.02)
	await capture("21a_sign_digit_tick_flash")
	sign.tick_panel_key(&"digits", 2)
	sign.tick_panel_key(&"digits", 7)
	await seconds(0.7)
	await capture("21b_sign_digits_two_closeup")
	sign.tick_panel_key(&"digits", 1)
	check(sign.is_panel_done(&"digits"), "ticking all three keys ticks the panel")
	await seconds(0.7)
	await capture("21c_sign_digits_done_closeup")
	_release_look()
	await seconds(0.1)
	await capture("21d_sign_digits_done")

	# 2-3：「Esc」のキー（文字が収まる大きさ）と「II」
	sign.set_title(PackedStringArray(["Esc で ひとやすみ"]))
	sign.set_panels([{"key": &"esc", "glyph": "Esc"}, {"key": &"pause", "picture": &"pause"}])
	var esc := _find_label(sign, "Esc")
	var esc_width := _label_width(esc) if esc != null else INF
	check(esc_width <= 2.1 * PracticeSignWall.KEY_GLYPH_FIT + 0.01, "the Esc glyph fits the key (%.2f m)" % esc_width)
	await seconds(0.3)
	await capture("22_sign_esc")
	_save_closeup("", Vector3(0.0, 2.2, SIGN_Z - 9.0), Vector3(0.0, 1.8, SIGN_Z))
	await seconds(0.1)
	await capture("22b_sign_esc_closeup")
	_release_look()
	sign.queue_free()
	await frames(2)


func _panel_border(sign: PracticeSignWall, index: int) -> Color:
	var panels: Array = sign.get("_panels")
	return (panels[index].border as StandardMaterial3D).albedo_color


func _find_label(root: Node, text: String) -> Label3D:
	for node: Node in root.find_children("*", "Label3D", true, false):
		if (node as Label3D).text == text:
			return node as Label3D
	return null


func _label_width(label: Label3D) -> float:
	return label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size


# ---------- 段階5：ハイタッチ・雲ですべる（2-1） ----------

func _hatena_high_five() -> void:
	gs.practice_place_player(1, 0.0, 0.0)
	var hatena := _new_hatena("HighFiveHatena")
	# プレイヤーが手の近くへ来ても雲に埋まらないよう、雲を小さくする
	hatena.set_cloud_size(HIGH_FIVE_CLOUD_SIZE)
	# 手が床から 2.4m になる足の高さ（手の高さと足の高さの差は、体の向きと大きさで決まる）
	hatena.place_at(Vector3(0.0, CLOUD_FOOT_Y, HIGH_FIVE_FRONT))
	var foot_y := HIGH_FIVE_HAND_Y - (hatena.hand_point().y - hatena.position.y)
	print("high five: feet on the cloud at y %.2f for the hand at %.2f" % [foot_y, HIGH_FIVE_HAND_Y])
	hatena.place_at(Vector3(-6.0, 0.0, 9.0))
	await hatena.ride_cloud_to(Vector3(0.0, foot_y, HIGH_FIVE_FRONT), 1.0)
	hatena.rotation.y = PI
	hatena.offer_hand(true)
	check(hatena.is_offering_hand(), "offer_hand raises the hand")
	await seconds(0.45)
	var hand := hatena.hand_point()
	check(absf(hand.y - HIGH_FIVE_HAND_Y) < 0.12, "hand_point is about 2.4 m above the floor (%.2f)" % hand.y)
	var bone_hand := _bone_hand_point(hatena)
	check(bone_hand.distance_to(hand) < 0.2, "the raised hand on the body matches hand_point (%.2f m apart)" % bone_hand.distance_to(hand))
	check((hatena.get_node("HandGlow") as Node3D).visible, "the offered hand glows")
	await capture("23_hatena_offer_hand")
	_save_closeup("", SIDE_EYE, SIDE_LOOK)
	await seconds(0.05)
	await capture("23b_hatena_offer_hand_side")
	# プレイヤーを手の手前（横に 1.0m 以内。雲の前）へ置いて跳ぶ（本番のジャンプ）。頂点で手に届くかを横から見る
	gs.practice_place_player(1, hand.x, hand.z - HIGH_FIVE_PLAYER_GAP)
	await seconds(0.2)
	await capture("23c_hatena_stand_side")
	gs.player_vel_y = JUMP_FORCE
	await seconds(JUMP_APEX_SECONDS)
	check(gs.player_y > 1.0, "the player jumps (y %.2f)" % gs.player_y)
	await capture("23d_hatena_jump_reach_side")
	_release_look()
	# ハイタッチ：パチン・キラッ・手を引っこめて喜ぶ（ゲームのカメラ）
	gs.practice_place_player(1, hand.x, hand.z - HIGH_FIVE_PLAYER_GAP)
	await seconds(0.25)
	gs.player_vel_y = JUMP_FORCE
	await seconds(JUMP_APEX_SECONDS - 0.05)
	hatena.high_five()
	check(not hatena.is_offering_hand(), "high_five lowers the hand")
	check(hatena.find_child("HighFiveSparkle", false, false) != null, "high_five makes a sparkle")
	await seconds(0.08)
	check(not (hatena.get_node("HandGlow") as Node3D).visible, "the hand glow goes away on the high five")
	await capture("24_hatena_high_five")
	await seconds(0.22)
	await capture("24b_hatena_high_five_after")
	await seconds(1.4)
	check(hatena.find_child("HighFiveSparkle", false, false) == null, "the sparkle goes away")
	# 動きを指定していない（idle）ので、雲の上では雲に乗る動き（練習の動きがあるとき）
	var resting := HatenaGuide.RIDE_CLIP if hatena.has_practice_moves() and hatena.has_cloud() else &"idle"
	check(hatena.mascot.action == resting, "after cheering the hatena goes back to its move (%s)" % hatena.mascot.action)
	# 雲で横へすべる（2回目の場所 x = +4）
	gs.practice_place_player(1, 0.0, 0.0)
	var target := Vector3(4.0, foot_y, HIGH_FIVE_FRONT)
	var glide := hatena.glide_to(target, 0.8)
	await seconds(0.32)
	check(hatena.is_moving(), "glide_to moves along")
	await capture("25_hatena_glide")
	await glide
	check(hatena.position.distance_to(target) < 0.01 and hatena.has_cloud(), "glide_to arrives on the cloud")
	check(absf(angle_difference(hatena.rotation.y, PI)) < 0.01, "glide_to keeps facing the player")
	hatena.offer_hand(true)
	await seconds(0.4)
	await capture("25b_hatena_offer_hand_left")
	hatena.queue_free()
	await frames(2)


## 体の右手の骨（手のひらの真ん中）の位置（ゲーム画面の座標）。hand_point と見た目がそろっているかを比べる。
func _bone_hand_point(hatena: HatenaGuide) -> Vector3:
	var skeleton := hatena.mascot.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := skeleton.find_bone(&"DEF-hand.R")
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var palm := pose.origin + pose.basis.y.normalized() * HatenaGuide.HAND_LENGTHS[2] * HatenaGuide.BODY_SCALE
	return world.global_transform.affine_inverse() * palm - Vector3(0.0, StageConstants.FLOOR_TOP_Y, 0.0)


# ---------- 段階5：おどる・ハテナの小窓（2-2・2-3・2-5） ----------

func _hatena_dance_and_portrait() -> void:
	gs.practice_place_player(1, 0.0, 0.0)
	# ステージのハテナ：看板の前でおどりつづける
	var dancer := _new_hatena("DanceHatena")
	dancer.place_at(Vector3(2.6, 0.0, 6.5))
	dancer.set_dancing(true)
	check(dancer.is_dancing() and dancer.mascot.action == &"dance", "set_dancing starts the dance")
	await seconds(0.45)
	await capture("26_hatena_dance")
	await seconds(0.5)
	await capture("26b_hatena_dance_later")
	# 小窓：コーチの層（106）の子にして、右下の角へ雲ですべり込む
	var layer := CanvasLayer.new()
	layer.name = "PreviewCoachLayer"
	layer.layer = PORTRAIT_LAYER
	world.add_child(layer)
	var portrait := HatenaPortrait.new()
	portrait.name = "PreviewPortrait"
	layer.add_child(portrait)
	portrait.setup(GameManager.graphics_quality)
	check(portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the portrait lets clicks through")
	var slide := portrait.slide_in(&"bottom_right", 0.4)
	await seconds(0.12)
	await capture("30a_portrait_sliding_in")
	await slide
	var canvas := portrait.get_viewport_rect().size
	check(portrait.position.distance_to(portrait.home_position(&"bottom_right")) < 1.0, "slide_in ends in the bottom right corner")
	check(absf(portrait.size.y - canvas.y * HatenaPortrait.HEIGHT_RATIO) < 1.5, "the portrait is about 1/4 of the screen height (%s)" % portrait.size)
	await seconds(0.3)
	await capture("30_portrait_on_stage")
	# 本物のポーズ画面（黒の 75% の幕・layer 100）を開く。ステージのおどるハテナはぴたっと止まり、小窓は動きつづける
	var dance_before := float(dancer.get("_dance_time"))
	var guide := portrait.guide()
	var anim_before := guide.mascot.player.current_animation_position
	world.call("_toggle_pause")
	check(get_tree().paused, "the real pause screen is open")
	await seconds(0.6)
	check(is_equal_approx(float(dancer.get("_dance_time")), dance_before), "the dancing hatena on the stage freezes while paused")
	check(not is_equal_approx(guide.mascot.player.current_animation_position, anim_before), "the portrait hatena keeps moving while paused")
	var anchor := portrait.bubble_anchor()
	check(anchor.is_finite() and Rect2(portrait.position - Vector2(0.0, 40.0), portrait.size + Vector2(0.0, 40.0)).has_point(anchor),
		"bubble_anchor is just above the head in the portrait (%s)" % anchor)
	var marker := _bubble_marker(layer, anchor, "とまったね！")
	await seconds(0.05)
	await capture("31_portrait_pause")
	marker.queue_free()
	portrait.play(&"point")
	await seconds(0.6)
	await capture("31b_portrait_pause_point")
	# ポーズ中も出し入れできる（返り値の signal も来る）
	await portrait.slide_out(0.3)
	check(not portrait.visible and not portrait.is_shown(), "slide_out hides the portrait (while paused)")
	await portrait.slide_in(&"bottom_left", 0.4)
	check(portrait.position.distance_to(portrait.home_position(&"bottom_left")) < 1.0, "slide_in works while paused")
	portrait.play(&"cheer")
	await seconds(0.3)
	await capture("31c_portrait_pause_bottom_left")
	await portrait.move_to(portrait.home_position(&"bottom_right"), 0.35)
	check(portrait.position.distance_to(portrait.home_position(&"bottom_right")) < 1.0, "move_to slides to the new spot")
	world.call("_toggle_pause")
	check(not get_tree().paused, "the pause screen closes")
	await seconds(0.3)
	check(float(dancer.get("_dance_time")) > dance_before + 0.1, "the stage hatena dances again after the pause")
	# 明るい地（明るいカードの上を想定）の上の小窓
	var card_layer := CanvasLayer.new()
	card_layer.layer = PORTRAIT_LAYER - 1
	world.add_child(card_layer)
	var card := ColorRect.new()
	card.color = Color(0.94, 0.95, 0.97)
	card.position = Vector2(canvas.x * 0.45, canvas.y * 0.45)
	card.size = canvas * 0.55
	card_layer.add_child(card)
	portrait.play(&"wave")
	await seconds(0.4)
	await capture("32_portrait_light_bg")
	card_layer.queue_free()
	await portrait.slide_out(0.3)
	layer.queue_free()
	dancer.queue_free()
	await frames(2)


## 吹き出しの代わりの印：付け根に赤い点、その上に白い吹き出し（付け根が頭の上に来るかを見る）。
func _bubble_marker(layer: CanvasLayer, anchor: Vector2, text: String) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.1, 0.12, 0.25))
	box.add_child(label)
	root.add_child(box)
	box.reset_size()
	box.position = anchor - Vector2(box.size.x * 0.75, box.size.y + 16.0)
	var tail := Polygon2D.new()
	tail.color = Color.WHITE
	tail.polygon = PackedVector2Array([anchor + Vector2(-10.0, -18.0), anchor + Vector2(10.0, -18.0), anchor + Vector2(0.0, -2.0)])
	root.add_child(tail)
	var dot := ColorRect.new()
	dot.color = Color(1.0, 0.2, 0.2)
	dot.size = Vector2(6.0, 6.0)
	dot.position = anchor - Vector2(3.0, 3.0)
	root.add_child(dot)
	return root


# ---------- 段階6：看板の壁（3-1・3-4） ----------

func _sign_wall_course3() -> void:
	gs.practice_place_player(1, 0.0, 0.0)
	var sign := PracticeSignWall.new()
	sign.name = "PreviewSignWall3"
	world.add_child(sign)
	sign.setup(GameManager.graphics_quality)
	sign.position = Vector3(0.0, 0.0, SIGN_Z)
	# 3-1：2人のときの操作。左（P1）は W A S D とスペース、右（P2）は ↑ ↓ ← → と右 Ctrl（台本の順で渡しても、キーボードと同じ並びになる）
	sign.set_title(PackedStringArray([PracticeTexts.get_text("c3.keys.sign")]))
	sign.set_panels([
		{"key": &"p1_keys", "keys": ["W", "A", "S", "D"], "sub": "スペース", "player": 1},
		{"key": &"p2_keys", "keys": ["↑", "↓", "←", "→"], "sub": "右 Ctrl", "player": 2},
	])
	check(not sign.is_panel_done(&"p1_keys") and not sign.is_panel_key_done(&"p1_keys", 4), "key sets start without ticks")
	check(_find_label(sign, "スペース") != null and _find_label(sign, "右 Ctrl") != null and _find_label(sign, "P2") != null,
		"the key sets show the wide keys and the P1 / P2 tags")
	check(_find_label(sign, "←") == null, "arrow keys are drawn as arrows (not as text)")
	_save_closeup("", DUO_EYE, DUO_LOOK)
	await seconds(0.3)
	await capture("40_sign_keys_duo")
	_save_closeup("", Vector3(0.0, 2.2, SIGN_Z - 9.0), Vector3(0.0, 1.8, SIGN_Z))
	await seconds(0.1)
	await capture("40b_sign_keys_closeup")
	# 押したキーに1つずつ ✓（A と スペース）。左のパネルだけ点滅（「2人のときP1はWASDで動く」）
	sign.tick_panel_key(&"p1_keys", 1)
	sign.tick_panel_key(&"p1_keys", 4)
	check(sign.is_panel_key_done(&"p1_keys", 1) and sign.is_panel_key_done(&"p1_keys", 4) and not sign.is_panel_done(&"p1_keys"),
		"tick_panel_key ticks a key and the wide key (index 4)")
	sign.blink_panel(&"p1_keys")
	await seconds(0.05)
	check(_panel_border(sign, 0).is_equal_approx(PracticeSignWall.BLINK_COLOR), "blink_panel blinks the P1 key set")
	await capture("40c_sign_keys_tick_blink")
	# 右のパネルは全部 ✓（tick_panel はキーにも全部付ける）
	sign.tick_panel(&"p2_keys")
	check(sign.is_panel_done(&"p2_keys") and sign.is_panel_key_done(&"p2_keys", 4), "tick_panel ticks every key of the set")
	for index: int in [0, 2, 3]:
		sign.tick_panel_key(&"p1_keys", index)
	check(sign.is_panel_done(&"p1_keys"), "ticking all five keys ticks the P1 panel")
	await seconds(1.1)
	await capture("40d_sign_keys_done_closeup")
	_save_closeup("", DUO_EYE, DUO_LOOK)
	await seconds(0.05)
	await capture("40e_sign_keys_done_duo")
	# 3-4：押し合う2人と「離す → 押す」
	sign.set_title(PackedStringArray([PracticeTexts.get_text("c3.push.sign")]))
	sign.set_panels([{"key": &"push", "picture": &"push"}, {"key": &"again", "picture": &"push_again"}])
	check(not sign.is_panel_done(&"push") and _find_label(sign, "離す") == null, "push pictures start without ticks and captions")
	await seconds(0.3)
	await capture("41_sign_push_duo")
	_save_closeup("", Vector3(0.0, 2.2, SIGN_Z - 9.0), Vector3(0.0, 1.8, SIGN_Z))
	await seconds(0.1)
	await capture("41b_sign_push_closeup")
	sign.tick_panel(&"push")
	await seconds(0.7)
	await capture("41c_sign_push_tick_closeup")
	# 文字を添えた「離す → 押す」
	sign.set_panels([{"key": &"push", "picture": &"push"}, {"key": &"again", "picture": &"push_again", "captions": ["離す", "押す"]}])
	check(_find_label(sign, "離す") != null and _find_label(sign, "押す") != null, "push_again shows its captions")
	await seconds(0.2)
	await capture("41d_sign_push_again_captions_closeup")
	_release_look()
	sign.queue_free()
	await frames(2)


# ---------- 道具 ----------

func _new_hatena(node_name: String) -> HatenaGuide:
	var hatena := HatenaGuide.new()
	hatena.name = node_name
	world.add_child(hatena)
	hatena.setup(GameManager.graphics_quality)
	return hatena


## 本番のクイズ壁を1枚、P1 から distance m 先に置く（矢印・的のマークの見え方の確かめ用。台本の壁と同じ見た目）。
func _quiz_wall(distance: float, question: String, choices: Array) -> Node3D:
	var wall: Node3D = load(QUIZ_WALL).instantiate()
	world.get_node("WallContainer").add_child(wall)
	wall.position = Vector3(0.0, 0.0, distance)
	var quiz := QuizItem.create(question, PackedStringArray(choices), 1, "", "OFFLINE")
	wall.call("set_quiz", quiz, 2)
	wall.call("set_gameplay_question", question, true)
	return wall


## 遊ぶカメラの代わりに、eye から look を見るカメラにする（1-6 の右を向くカメラ・近くから見る確かめ用）。
func _save_closeup(_tag: String, eye: Vector3, look: Vector3) -> void:
	if _look_camera == null:
		_look_camera = Camera3D.new()
		_look_camera.name = "PreviewLookCamera"
		world.add_child(_look_camera)
	_look_camera.fov = FOV
	_look_camera.global_position = eye
	_look_camera.look_at(look, Vector3.UP)
	_look_camera.make_current()


func _release_look() -> void:
	if _look_camera != null:
		_look_camera.clear_current(false)
		var game_camera := world.get_node_or_null("CameraController/Camera3D") as Camera3D
		if game_camera != null:
			game_camera.make_current()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func seconds(value: float) -> void:
	await get_tree().create_timer(value).timeout


func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")


func _finish() -> void:
	print("PRACTICE_PROPS_PREVIEW " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
