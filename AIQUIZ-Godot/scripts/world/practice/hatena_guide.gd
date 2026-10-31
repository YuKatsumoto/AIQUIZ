class_name HatenaGuide
extends Node3D

## 練習の案内役のハテナ（docs/new_tutorial/foundation_design.md 10章、phase4_design.md 3.3、phase9_design.md 1章）。PracticeDirector が作ってゲーム画面に置く。
## 体は客席のハテナ（StandMascot：mascot_model.glb と mascot_stand.glb）をそのまま使い、足もとに雲
## （mascot_cloud.glb と mascot_cloud.gdshader。読み込み方は LassoCloudRider._setup_cloud と同じ）を出せる。
## 動きは、客席のハテナの動き（手をふる・ばんざい・拍手・おどる・指す）と、ライブの Blender で作った練習の動き
## （mascot_practice.glb。source/build_practice_mascot.py：両手を広げる・胸をはる・×・首をかしげる・あちゃー・うなずく・
## 跳ぶ・着地・雲に乗る）。跳ぶ・雲で飛ぶの道すじは、位置・回転・大きさの動きと重ねる。
## mascot_practice.glb がないときは、練習の動きを客席のハテナの動き（と体を傾けるだけ）で代わりにする。
## 歩く・海に落ちる・じたばた（walk_to・fall_into_sea・set_flailing）は、v0.2 の台本でどのコースも使わなくなった仮のまま。
## このノードの位置はゲーム画面の座標（x、高さ、コンベア上の z）で、高さはプレイヤーの player_y と同じ：
## y = 0 で床に立つ（体は StageConstants.FLOOR_TOP_Y だけ下げて描く。クイズ壁・プレイヤーの体と同じ）、
## y = StageConstants.OCEAN_SURFACE_Y で海に浮く（fall_into_sea のあと。体の玉の半分ほどが水に入り、水面に白い輪が出る）。
## 向きは y 軸まわり（0 で +z、PI でカメラのほう）。
##
##   place_at(pos, facing) / face_toward(point) / hop_to(pos, seconds) / walk_to(pos, speed) / fall_into_sea(pos, seconds)
##   ride_cloud_to(pos, seconds) / glide_to(pos, seconds) / set_flailing(on) / tremble(seconds) / spin() / dodge(side)
##   play(action) / set_cloud(on) / bubble_anchor(camera)
##   offer_hand(on) / hand_point() / high_five() / set_dancing(on) / set_cloud_size(size)（段階5：コース②の 2-1・2-2・2-3）
##   walk_to(pos, speed, duck) / step_to(pos) / sit_to(pos, facing) / sit_here(pos, facing) / stand_up_to(pos) / turn_to(facing)
##   push_door() / pull_door() / leave_cloud_here() / send_cloud_away() / call_cloud(pos) / board_cloud() / skeleton_offset()
##   （段階9：席へ戻る・席を離れる。scripts/practice/menu/practice_seat_moves.gd）
## 道すじの動き（hop_to・walk_to・fall_into_sea・ride_cloud_to・glide_to）は返り値の signal で終わりを待てる（ポーズ中は止まる）。
## 新しい道すじの動きか place_at を呼ぶと、前の道すじの動きは打ち切る（打ち切られた動きの signal も時間どおりに来る）。
## run_while_paused を true にすると（ハテナの小窓 HatenaPortrait が使う）、ポーズ中も動き、道すじの signal も来る。

const Shapes = preload("res://scripts/world/practice/practice_shapes.gd")
const CLOUD_GLB := "res://assets/characters/aiquiz_mascot/mascot_cloud.glb"
const CLOUD_SHADER := preload("res://assets/characters/aiquiz_mascot/mascot_cloud.gdshader")
## 舞台で見えるよう、等倍の 1.3 倍（実機で合わせる）
const BODY_SCALE := 1.3
## 足の裏を、このノードからどれだけ下げて描くか（y = 0 で床の面に立つ）
const FOOT_Y := StageConstants.FLOOR_TOP_Y
## 吹き出しを付ける高さ（等倍のハテナの空間。頭の玉のてっぺんが約 1.58 m）
const BUBBLE_HEIGHT := 1.9
## 体の玉の真ん中の高さ（等倍の空間）。首をかしげる・じたばたはここを中心に回す
const BALL_CENTER := 1.03
## ジャンプの高さ（m）：最低これだけ。遠くへ跳ぶほど高くする
const HOP_MIN_HEIGHT := 1.6
const HOP_HEIGHT_PER_METER := 0.22
## 歩く：1歩の長さ（m）、はずむ高さ
const WALK_STRIDE := 0.55
const WALK_BOUNCE := 0.12
## 海に落ちる：足をすべらせる秒（全体に対する割合と上限）、落ちる前に少し上がる高さ
const SLIP_RATIO := 0.25
const SLIP_MAX_SECONDS := 0.2
const FALL_RISE := 0.7
## 海に浮いているときに沈める深さ（m。体の玉の半分ほどが水に入る）と、水面の白い輪の大きさ・広がる間
const SEA_SINK := 0.25
const SEA_RING_RADIUS := 0.95
const SEA_RIPPLE_SECONDS := 1.1
const SEA_RIPPLE_FLAIL_SECONDS := 0.45
## 雲に乗る：雲が飛んでくる割合、飛んでくる所（このノードから見たゲーム画面の向きの m）、飛ぶ高さ
const CLOUD_ARRIVE_RATIO := 0.35
const CLOUD_FROM := Vector3(-4.0, 6.0, -2.0)
const CLOUD_RIDE_MIN_HEIGHT := 1.6
const CLOUD_RIDE_HEIGHT_PER_METER := 0.12
const CLOUD_SFX := &"sd_cloud_whoosh"
## くるっと回る・よける
const SPIN_SECONDS := 0.5
const DODGE_DISTANCE := 1.8
const DODGE_OUT := 0.2
const DODGE_HOLD := 0.3
const DODGE_BACK := 0.35
## ポーズ（×・首をかしげる）：出る秒と、次の play がなくてもやめるまでの秒
const POSE_IN_SECONDS := 0.2
const POSE_HOLD_SECONDS := 3.0
const TILT_ANGLE := 0.36
## 手を出す（ハイタッチ）：右手（体の −x 側。カメラのほうを向くと画面の左に出る）を、前（向いているほう）へ上げて出す。
## 向きは等倍の体の空間（+z が前）で、上腕・前腕・手の骨の順。腕が短いので、頭より上には届かない（手は肩の少し上）。
## 体の玉にめり込まないよう、少し外へ開く。左手は下ろして（初期姿勢へ）、上げた手だけが目立つようにする。
const HAND_BONES: Array[StringName] = [&"DEF-upper_arm.R", &"DEF-forearm.R", &"DEF-hand.R"]
const HAND_DIRS: Array[Vector3] = [Vector3(-0.40, 0.50, 0.77), Vector3(-0.18, 0.80, 0.57), Vector3(-0.06, 0.92, 0.38)]
const OTHER_ARM_BONES: Array[StringName] = [&"DEF-upper_arm.L", &"DEF-forearm.L", &"DEF-hand.L"]
## 右肩の付け根（等倍の体の空間。骨格の初期姿勢）と、上腕・前腕の長さ、手の骨の根もとから手のひらの真ん中まで
const HAND_SHOULDER := Vector3(-0.52, 0.819, 0.0)
const HAND_LENGTHS: Array[float] = [0.159, 0.137, 0.13]
## 手を上げる・下ろす秒
const HAND_RAISE_SECONDS := 0.22
const HAND_LOWER_SECONDS := 0.3
## 出している手のまわりの「ここ！」の光の輪（m。ゆっくり脈打つ）
const HAND_GLOW_RADIUS := 0.42
const HAND_GLOW_HZ := 1.6
const HAND_GLOW_COLOR := Color(1.0, 0.86, 0.3)
## ハイタッチ：手を引っこめる秒、体がはずむ秒、喜ぶ（ばんざい）秒、キラッの秒と大きさ（m）、「パチン！」の音（tools/audio/make_practice_sfx.py）
const HIGH_FIVE_RECOIL_SECONDS := 0.14
const HIGH_FIVE_POP_SECONDS := 0.4
const HIGH_FIVE_CHEER_SECONDS := 1.3
const SPARKLE_SECONDS := 0.6
const SPARKLE_SIZE := 0.6
const HIGH_FIVE_SFX := &"practice_high_five"
const HIGH_FIVE_SFX_DB := 0.0
const HIGH_FIVE_SFX_PITCH := 1.0
## おどる：はずむ高さ（1秒に2回）、左右のゆれ・ひねり（1秒に1往復）
const DANCE_BOUNCE := 0.1
const DANCE_SWAY := 0.12
const DANCE_TWIST := 0.32
## 雲ですべる：途中で少し浮き上がる高さ、体の傾き、雲のなびき（LassoCloudRider と同じ考え方）
const GLIDE_RISE := 0.18
const GLIDE_LEAN := 0.2
const GLIDE_TRAIL_PER_SPEED := 0.012
const GLIDE_TRAIL_MAX := 0.14
## 練習の動き（ライブの Blender で作った。phase9_design.md 1章）。客席のハテナの AnimationPlayer に PRACTICE_LIBRARY のライブラリで足す
const PRACTICE_ANIM_GLB := "res://assets/characters/aiquiz_mascot/mascot_practice.glb"
const PRACTICE_LIBRARY := &"practice"
## ループしない動き（ほかはくり返す）
const ONE_SHOT_CLIPS: Array[StringName] = [&"Practice_Land", &"Practice_Step", &"Practice_SitDown", &"Practice_StandUp",
	&"Practice_PushUp", &"Practice_PullDown"]
## 跳んでいる間・着地・雲で飛んでいる間（と、雲の上で動きを指定していないとき）の動き
const HOP_CLIP := &"practice/Practice_Hop"
const LAND_CLIP := &"practice/Practice_Land"
const RIDE_CLIP := &"practice/Practice_Ride"
## 席へ戻る・席を離れる・ヘリに乗り降りする動き（phase9_design.md 5章）
const WALK_CLIP := &"practice/Practice_Walk"
const DUCK_WALK_CLIP := &"practice/Practice_DuckWalk"
const STEP_CLIP := &"practice/Practice_Step"
const SIT_DOWN_CLIP := &"practice/Practice_SitDown"
const STAND_UP_CLIP := &"practice/Practice_StandUp"
const PUSH_UP_CLIP := &"practice/Practice_PushUp"
const PULL_DOWN_CLIP := &"practice/Practice_PullDown"
## 座った姿：ヘリの操縦士と同じ「ぬいぐるみ座り」（mascot_pilot.glb の Pilot_SitIdle）。席のハテナと入れ替わっても形が変わらない
const PILOT_ANIM_GLB := "res://assets/characters/aiquiz_mascot/mascot_pilot.glb"
const PILOT_LIBRARY := &"pilot"
const SEATED_CLIP := &"pilot/Pilot_SitIdle"
## 着地の動きの長さ（秒。Practice_Land と同じ）と、跳ぶ・着地へ移るときのつなぎ（秒）
const LAND_SECONDS := 0.4
const HOP_BLEND := 0.12
const LAND_BLEND := 0.06
## 段を上がる・座る・立つ・ドアの手の動きの長さ（秒。それぞれの動きと同じ）
const STEP_SECONDS := 0.45
const SIT_SECONDS := 0.55
const STAND_SECONDS := 0.5
const DOOR_SECONDS := 0.8
## 歩く動きの足の速さ（等倍のハテナの空間の m/秒。Practice_Walk の 1 歩 0.24 m を 0.4 秒で送る）。かがんで歩くのは 0.7 倍
const WALK_CLIP_SPEED := 0.6
const DUCK_CLIP_SPEED := 0.42
## 雲を呼ぶ・雲を帰すときに、雲が来る・去る向き（このノードの大きさをかける、親の空間の m）
const CLOUD_CALL_FROM := Vector3(-3.0, 4.0, -1.5)
const CLOUD_LEAVE_TO := Vector3(-2.5, 3.5, 1.0)
## 台本の動きの名前 → 客席のハテナの動き（StandMascot の名前）か、練習の動き（"practice/〜"）。
## ここにない名前は、そのまま StandMascot へ渡す（&"idle" など）。
const ACTIONS := {
	&"wave": &"idle",  # 手をふる
	&"cheer": &"cheer",  # ばんざい
	&"clap": &"clap",  # 拍手
	&"dance": &"dance",  # おどる
	&"point": &"point",  # 指す
	&"proud": &"practice/Practice_Proud",  # 胸をはる（腰に手）
	&"open_arms": &"practice/Practice_OpenArms",  # 両手を広げる
	&"cross": &"practice/Practice_Cross",  # ×のポーズ（両手を前に出して首をふる。赤い × の文字を重ねる）
	&"tilt": &"practice/Practice_Tilt",  # 首をかしげる（ほおに手）
	&"oops": &"practice/Practice_Oops",  # あちゃー（頭の横に手、うなだれる。失敗したとき）
	&"nod": &"practice/Practice_Nod",  # うなずく（2回）
}
## 練習の動きがない（mascot_practice.glb を読めない）ときの代わりの、客席のハテナの動き
const FALLBACK := {&"proud": &"hold_card", &"open_arms": &"hold_card", &"cross": &"hold_card", &"tilt": &"idle",
	&"oops": &"idle", &"nod": &"idle"}

enum Motion { NONE, HOP, WALK, FALL, CLOUD, GLIDE, STEP, SIT, STAND, TURN }

## 練習の動きと操縦士の動きのライブラリ（読み込みは1回だけ。ハテナどうしで共有する）
static var _practice_library: AnimationLibrary = null
static var _pilot_library: AnimationLibrary = null

## true なら、ポーズ中も動き、道すじの動きの signal もポーズ中に来る（ハテナの小窓が process_mode といっしょに入れる）。
var run_while_paused := false
var mascot: StandMascot = null
## 練習の動き（mascot_practice.glb）と、操縦士の座った姿（mascot_pilot.glb）を使える
var _has_practice := false
var _has_pilot := false
## 跳ぶ・着地・雲で飛ぶ・歩く・座るなどの間、台本の動きの代わりに出している動き（&"" でなし）。終わったら台本の動きに戻す（_resume_body）
var _override_clip := &""
## その動きの種類：&"motion"（道すじの動きの間）・&"timed"（着地・ドアの手。_timed_left 秒）・&"seated"（座っている間ずっと）
var _override_kind := &""
## 着地・ドアの手の動きの残りの秒
var _timed_left := 0.0
## 歩く動きの速さの倍率（歩く速さに足を合わせる）
var _walk_rate := 1.0
## 座る・立つ・向きを変える：始めと終わりの向き
var _yaw_from := 0.0
var _yaw_to := 0.0
## 雲を足もとから離している（雲を呼ぶ・雲から降りる・雲を帰す）：雲の置き場（親の空間。このノードの位置と同じ決め方で、
## 雲の上に立つ足の高さ）、向き、動き {from, to, time, seconds, size_from, size_to, hide}
var _cloud_detached := false
var _cloud_anchor := Vector3.ZERO
var _cloud_yaw := 0.0
var _cloud_move := {}
## ride_cloud_to で雲が飛んでくる割合（もう雲に乗っていれば 0）
var _cloud_arrive := CLOUD_ARRIVE_RATIO
## 大きさ（BODY_SCALE）をかける入れ物。ハテナが入る。雲は _cloud_holder（体の傾きに付いていかない）。
var _body: Node3D = null
var _cloud_holder: Node3D = null
var _cloud: MeshInstance3D = null
var _cross_mark: Label3D = null
## 海に浮いているときの水面の白い輪（いつもの輪と、広がって消える波紋）
var _sea_ring: Node3D = null
var _sea_ripple: MeshInstance3D = null
var _sea_ripple_material: StandardMaterial3D = null
var _sea_ripple_time := 0.0

var _motion := Motion.NONE
var _motion_serial := 0
var _motion_from := Vector3.ZERO
var _motion_to := Vector3.ZERO
var _motion_height := 0.0
var _motion_time := 0.0
var _motion_duration := 0.0
var _clock := 0.0
## 海に浮いている（fall_into_sea の着水から、雲に乗る・place_at まで）
var _in_sea := false
var _flailing := false
## じたばたの前の動き（やめたら戻す）
var _action_before_flail := &"idle"
var _tremble_left := 0.0
var _spin_time := -1.0
var _dodge_time := -1.0
var _dodge_side := 0.0
var _pose := &""
var _pose_time := 0.0
## 体の動きのずれ（このノードの空間の m）。吹き出しの位置にも使う
var _offset := Vector3.ZERO
## 動きの名前（ACTIONS の前）を覚えておく
var _action := &"idle"
var _anim_speed := 1.0
## 手を出す（ハイタッチ）：骨格と右腕・左腕の骨、出しているか、上がり具合（0 → 1）、引っこめ始めてからの秒（< 0 で引っこめていない）
var _skeleton: Skeleton3D = null
var _hand_bones := PackedInt32Array()
var _other_arm_bones := PackedInt32Array()
## 出している手のまわりの光の輪（輪と、まんなかのうすい丸）
var _hand_glow: Node3D = null
var _hand_glow_materials: Array[StandardMaterial3D] = []
## 雲の大きさ（1 で等倍。set_cloud_size）と、いまの大きさ（なめらかに寄せる）
var _cloud_size := 1.0
var _cloud_size_shown := 1.0
var _offering := false
var _hand_weight := 0.0
var _recoil_time := -1.0
## ハイタッチのあとに喜んでいる残りの秒（そのあとは _action に戻る）と、体のはずみ（ハイタッチしてからの秒）
var _cheer_left := 0.0
var _pop_time := -1.0
## キラッ（{node, time, parts}）
var _sparkles: Array[Dictionary] = []
## おどる（set_dancing）：おどっているか、おどった秒、おどる前の動き
var _dancing := false
var _dance_time := 0.0
var _action_before_dance := &"idle"
## 雲のなびき（雲の空間の m）と、外から入れたなびき（set_cloud_trail）
var _cloud_trail := Vector3.ZERO
var _external_trail := Vector3.ZERO


func _init() -> void:
	# ゲーム画面は止めている間も動く（PROCESS_MODE_ALWAYS）ので、ハテナはポーズで止める。
	process_mode = Node.PROCESS_MODE_PAUSABLE


func setup(quality: String) -> bool:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	mascot = StandMascot.new()
	mascot.name = "Mascot"
	_body.add_child(mascot)
	var ok := mascot.setup(quality)
	# 客席のハテナ（StandMascot）は影を落とさない作りだが、案内役は舞台の上で立体に見えるよう、床に影を落とす
	for node: Node in mascot.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_has_practice = mascot.add_library(PRACTICE_LIBRARY, _load_practice_library())
	_has_pilot = _has_practice and mascot.add_library(PILOT_LIBRARY, _load_pilot_library())
	_find_hand_bones()
	_cloud_holder = Node3D.new()
	_cloud_holder.name = "CloudHolder"
	add_child(_cloud_holder)
	_setup_cloud(quality)
	_setup_cross_mark()
	_setup_sea_ring()
	_setup_hand_glow()
	_apply_body(Vector3.ZERO, Vector3.ZERO, Vector3.ONE, Vector3.ZERO)
	return ok


func _setup_cloud(quality: String) -> void:
	if not ResourceLoader.exists(CLOUD_GLB):
		return
	var scene := load(CLOUD_GLB) as PackedScene
	var root := scene.instantiate() as Node3D if scene != null else null
	if root == null:
		return
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		root.free()
		return
	var source := meshes[0] as MeshInstance3D
	_cloud = MeshInstance3D.new()
	_cloud.name = "Cloud"
	_cloud.mesh = source.mesh
	_cloud.transform = _transform_in(root, source)
	root.free()
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	if GraphicsQuality.normalize(quality) == GraphicsQuality.LOW:
		material.set_shader_parameter("puff_amount", 0.0)
	_cloud.material_override = material
	_cloud.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_cloud.visible = false
	_cloud_holder.add_child(_cloud)


## 練習の動きのライブラリ（mascot_practice.glb の動き。ONE_SHOT_CLIPS のほかはくり返す）。ファイルがなければ null。
static func _load_practice_library() -> AnimationLibrary:
	if _practice_library != null:
		return _practice_library
	if not ResourceLoader.exists(PRACTICE_ANIM_GLB):
		return null
	var scene := load(PRACTICE_ANIM_GLB) as PackedScene
	var source := scene.instantiate() if scene != null else null
	if source == null:
		return null
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null:
		source.free()
		return null
	_practice_library = AnimationLibrary.new()
	for clip_name: StringName in source_player.get_animation_list():
		var clip := source_player.get_animation(clip_name).duplicate(true) as Animation
		clip.loop_mode = Animation.LOOP_NONE if clip_name in ONE_SHOT_CLIPS else Animation.LOOP_LINEAR
		_practice_library.add_animation(clip_name, clip)
	source.free()
	return _practice_library


## 操縦士の動きのライブラリ（mascot_pilot.glb。座った姿 Pilot_SitIdle を使う。くり返す）。ファイルがなければ null。
static func _load_pilot_library() -> AnimationLibrary:
	if _pilot_library != null:
		return _pilot_library
	if not ResourceLoader.exists(PILOT_ANIM_GLB):
		return null
	var scene := load(PILOT_ANIM_GLB) as PackedScene
	var source := scene.instantiate() if scene != null else null
	if source == null:
		return null
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null:
		source.free()
		return null
	_pilot_library = AnimationLibrary.new()
	for clip_name: StringName in source_player.get_animation_list():
		var clip := source_player.get_animation(clip_name).duplicate(true) as Animation
		clip.loop_mode = Animation.LOOP_LINEAR
		_pilot_library.add_animation(clip_name, clip)
	source.free()
	return _pilot_library


## 練習の動きを使える（mascot_practice.glb を読めた）。
func has_practice_moves() -> bool:
	return _has_practice


## このノードから見た骨格（Skeleton3D）の置き方（体の動きのずれがないとき）。席のハテナの骨格に重ねるのに使う
## （PracticeSeatMoves.overlay）。骨格がなければ IDENTITY。
func skeleton_offset() -> Transform3D:
	if _skeleton == null or _body == null or not _skeleton.is_inside_tree():
		return Transform3D(Basis.from_scale(Vector3.ONE * BODY_SCALE), Vector3(0.0, FOOT_Y, 0.0))
	var inside := _body.global_transform.affine_inverse() * _skeleton.global_transform
	return Transform3D(Basis.from_scale(Vector3.ONE * BODY_SCALE), Vector3(0.0, FOOT_Y, 0.0)) * inside


## ×のポーズの印：体の玉に重なる赤い ×（いつもカメラを向き、体より手前に描く）。
func _setup_cross_mark() -> void:
	_cross_mark = Label3D.new()
	_cross_mark.name = "CrossMark"
	_cross_mark.font = load("res://resources/fonts/NotoSansJP-Bold.otf") as Font
	_cross_mark.text = "×"
	_cross_mark.font_size = 220
	_cross_mark.pixel_size = 0.006
	_cross_mark.modulate = Color(1.0, 0.18, 0.15)
	_cross_mark.outline_modulate = Color(1.0, 1.0, 1.0)
	_cross_mark.outline_size = 26
	_cross_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cross_mark.no_depth_test = true
	_cross_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cross_mark.render_priority = 20
	_cross_mark.outline_render_priority = 19
	_cross_mark.visible = false
	add_child(_cross_mark)


## 水面の白い輪：体のまわりの輪と、外へ広がって消える波紋。
func _setup_sea_ring() -> void:
	_sea_ring = Node3D.new()
	_sea_ring.name = "SeaRing"
	_sea_ring.visible = false
	add_child(_sea_ring)
	var foam := Shapes.flat_material(Color(1.0, 1.0, 1.0, 0.85), true, false, 3)
	Shapes.add_mesh(_sea_ring, Shapes.ring_mesh(SEA_RING_RADIUS * 0.82, SEA_RING_RADIUS, 40, Shapes.Face.FLOOR), foam)
	_sea_ripple_material = Shapes.flat_material(Color(1.0, 1.0, 1.0, 0.6), true, false, 3, false, true)
	_sea_ripple = Shapes.add_mesh(_sea_ring, Shapes.ring_mesh(SEA_RING_RADIUS * 0.9, SEA_RING_RADIUS, 40, Shapes.Face.FLOOR), _sea_ripple_material)


## 手を出すのに使う骨格と右腕の骨（なければ手は出さない。hand_point は決まった寸法で計算する）。
func _find_hand_bones() -> void:
	if mascot == null:
		return
	var found := mascot.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var skeleton := found[0] as Skeleton3D
	var bones := PackedInt32Array()
	for bone_name: StringName in HAND_BONES + OTHER_ARM_BONES:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			return
		bones.append(bone)
	_skeleton = skeleton
	_hand_bones = bones.slice(0, HAND_BONES.size())
	_other_arm_bones = bones.slice(HAND_BONES.size())


## 出している手のまわりの「ここ！」の光：いつもカメラを向く輪と、まんなかのうすい丸（体より手前に描く）。
func _setup_hand_glow() -> void:
	_hand_glow = Node3D.new()
	_hand_glow.name = "HandGlow"
	_hand_glow.visible = false
	add_child(_hand_glow)
	var parts: Array = [[Shapes.ring_mesh(0.8, 1.0, 40), Color(HAND_GLOW_COLOR, 0.9)], [Shapes.polygon_mesh(Shapes.circle(0.8, 40)), Color(1.0, 0.97, 0.8, 0.28)]]
	for part: Array in parts:
		var material := Shapes.flat_material(part[1], true, false, 38, false, true)
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		material.no_depth_test = true
		Shapes.add_mesh(_hand_glow, part[0], material)
		_hand_glow_materials.append(material)


## node の root から見た置き方（root はまだ木に入っていない）。
static func _transform_in(root: Node, node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


# ---------- 置く・向く ----------

## pos に立たせる（y = 0 で床の上）。道すじの動き（跳ぶ・歩く・落ちる・雲で飛ぶ）と海に浮くのはやめる。
## くるっと回る・よける・ふるえる・ポーズはそのまま続く（毎フレーム呼んで壁に付いていってもよい）。
func place_at(pos: Vector3, facing: float = PI) -> void:
	_stop_motion()
	if _in_sea:
		_leave_sea()
	position = pos
	rotation = Vector3(0.0, facing, 0.0)
	visible = true


## point のほうを向く（高さは見ない）。
func face_toward(point: Vector3) -> void:
	var to := point - position
	if Vector2(to.x, to.z).length_squared() < 0.0001:
		return
	rotation.y = atan2(to.x, to.z)


# ---------- 道すじの動き ----------

## 放物線で pos へ跳ぶ（台本①の 1.3：壁から壁へ 0.8 秒）。着地する時刻に返り値の signal が来る。
## height（m。親の空間）を渡すと、その高さの弧にする（雲から降りる・雲へ乗るなどの小さな跳び。ふつうは遠いほど高い）。
func hop_to(pos: Vector3, seconds: float = 0.8, height := -1.0) -> Signal:
	_leave_sea()
	_motion_from = position
	_motion_to = pos
	_motion_height = height if height >= 0.0 else HOP_MIN_HEIGHT + HOP_HEIGHT_PER_METER * _motion_from.distance_to(pos)
	_begin_override(HOP_CLIP, HOP_BLEND, true)
	return _start_motion(Motion.HOP, seconds)


func is_hopping() -> bool:
	return _motion == Motion.HOP


## 床の上を pos まで歩く（speed m/s。進むほうを向く）。練習の動きがあれば足を運んで歩き（duck なら、かがんで歩く）、
## なければ上下にはずむ。着いたら返り値の signal が来る。
func walk_to(pos: Vector3, speed := 2.2, duck := false) -> Signal:
	_leave_sea()
	_motion_from = position
	_motion_to = pos
	var flat := Vector2(pos.x - position.x, pos.z - position.z)
	if flat.length() > 0.01:
		rotation.y = atan2(flat.x, flat.y)
	# 足の運びを歩く速さに合わせる（ハテナの大きさ＝このノードの大きさ × BODY_SCALE）
	var stride := (DUCK_CLIP_SPEED if duck else WALK_CLIP_SPEED) * absf(scale.x) * BODY_SCALE
	_walk_rate = clampf(speed / maxf(stride, 0.01), 0.4, 2.5)
	_begin_override(DUCK_WALK_CLIP if duck else WALK_CLIP, 0.15, false)
	return _start_motion(Motion.WALK, flat.length() / maxf(speed, 0.1))


## 段を上がる・下りる（足から pos へ。右足を上げて置き、左足が追いつく）。着いたら返り値の signal が来る。
func step_to(pos: Vector3, seconds := STEP_SECONDS) -> Signal:
	_leave_sea()
	_motion_from = position
	_motion_to = pos
	var flat := Vector2(pos.x - position.x, pos.z - position.z)
	if flat.length() > 0.05:
		rotation.y = atan2(flat.x, flat.y)
	_motion_height = 0.08 * absf(scale.x) + maxf(pos.y - position.y, 0.0) * 0.4
	_begin_override(STEP_CLIP, 0.08, true)
	return _start_motion(Motion.STEP, seconds)


## 後ろの pos（座った姿の位置）へ座る：かがんで両手を座面へのばし、お尻から座って脚を前へ出す。facing は座った向き。
## 座ったあとは、立つ（stand_up_to）か place_at まで「ぬいぐるみ座り」（操縦士の Pilot_SitIdle）のまま。
## 着いたら返り値の signal が来る。
func sit_to(pos: Vector3, facing: float, seconds := SIT_SECONDS) -> Signal:
	_leave_sea()
	_motion_from = position
	_motion_to = pos
	_yaw_from = rotation.y
	_yaw_to = facing
	_motion_height = 0.12 * absf(scale.x)
	_begin_override(SIT_DOWN_CLIP, 0.1, true)
	return _start_motion(Motion.SIT, seconds)


## pos に、facing を向いて座った姿で置く（席のハテナと入れ替わって、席から立つ前）。
func sit_here(pos: Vector3, facing: float) -> void:
	place_at(pos, facing)
	_seat_down(0.0)


func is_seated() -> bool:
	return _override_kind == &"seated"


## 座った姿から、前の pos（立った位置）へ立ち上がる。着いたら返り値の signal が来る。
func stand_up_to(pos: Vector3, seconds := STAND_SECONDS) -> Signal:
	_motion_from = position
	_motion_to = pos
	_motion_height = 0.06 * absf(scale.x)
	_override_kind = &""
	_begin_override(STAND_UP_CLIP, 0.08, true)
	return _start_motion(Motion.STAND, seconds)


## その場で facing のほうへ向きを変える（足ぶみはしない）。終わったら返り値の signal が来る。
func turn_to(facing: float, seconds := 0.3) -> Signal:
	_motion_from = position
	_motion_to = position
	_yaw_from = rotation.y
	_yaw_to = facing
	return _start_motion(Motion.TURN, seconds)


## 右手でヘリのドア（上へ開くガルウィング）を押し上げる・引き下ろす手の動き。手の動きが終わる時刻に返り値の signal が来る。
## ドアそのものは呼ぶ側が動かす（手がドアに届くのは 0.3 秒ごろ）。
func push_door() -> Signal:
	return _gesture(PUSH_UP_CLIP)


func pull_door() -> Signal:
	return _gesture(PULL_DOWN_CLIP)


func _gesture(clip: StringName) -> Signal:
	_begin_override(clip, 0.12, true, &"timed")
	if _override_clip == clip:
		_timed_left = DOOR_SECONDS
	return (Engine.get_main_loop() as SceneTree).create_timer(DOOR_SECONDS, run_while_paused).timeout


## 足をすべらせ、放物線で海面の pos へ落ちる（pos.y は StageConstants.OCEAN_SURFACE_Y。着水したら海に浮く）。
## 落ちながら、落ちた所（床）のほうへ向き直る。着水の時刻に返り値の signal が来る。
## 水しぶきは出さない（監督が world.practice_splash を呼ぶ）。
func fall_into_sea(pos: Vector3, seconds := 0.7) -> Signal:
	_motion_from = position
	_motion_to = pos
	var flat := Vector2(pos.x - position.x, pos.z - position.z)
	if flat.length() > 0.01:
		rotation.y = atan2(flat.x, flat.y)
	_action_before_flail = _action if not _flailing else _action_before_flail
	_clear_override()
	_play_body(&"cheer")
	return _start_motion(Motion.FALL, seconds)


## 雲が飛んできて足もとに入り、乗って pos へ飛ぶ。着いたら返り値の signal が来る（雲は出たまま。set_cloud(false) で消す）。
## pos の y は雲の上に立つ足の高さ（雲は足の裏から 0.83m 下まであるので、床の上で浮かせるなら 0.9 くらい。0 だと雲が床に沈む）。
## 海でじたばたしていたら、雲が足もとに入ったときにやめる。もう雲に乗っていれば（board_cloud のあとなど）、すぐ飛び立つ。
func ride_cloud_to(pos: Vector3, seconds := 1.4) -> Signal:
	_motion_from = position
	_motion_to = pos
	_motion_height = CLOUD_RIDE_MIN_HEIGHT + CLOUD_RIDE_HEIGHT_PER_METER * Vector2(pos.x - position.x, pos.z - position.z).length()
	_cloud_arrive = 0.0 if has_cloud() else CLOUD_ARRIVE_RATIO
	set_cloud(true)
	_play_sfx(CLOUD_SFX, -4.0)
	_begin_override(RIDE_CLIP, StandMascot.BLEND_SECONDS, false)
	return _start_motion(Motion.CLOUD, seconds)


## 雲に乗って浮かんだまま、pos へすべるように動く（hop_to の雲版。2-1 のハイタッチの場所の移り）。
## 向きは変えず（プレイヤーのほうを向いたまま）、動くほうと逆へ少し体を傾け、雲がうしろへなびく。着いたら返り値の signal が来る。
## pos の y は雲の上に立つ足の高さ（ride_cloud_to と同じ）。雲が出ていなければ出す（ふつうは先に ride_cloud_to で乗せておく）。
func glide_to(pos: Vector3, seconds := 0.8) -> Signal:
	_leave_sea()
	_motion_from = position
	_motion_to = pos
	set_cloud(true)
	if position.distance_to(pos) > 1.5:
		_play_sfx(CLOUD_SFX, -10.0)
	_begin_override(RIDE_CLIP, StandMascot.BLEND_SECONDS, false)
	return _start_motion(Motion.GLIDE, seconds)


func is_moving() -> bool:
	return _motion != Motion.NONE


func is_in_sea() -> bool:
	return _in_sea


func _start_motion(kind: Motion, seconds: float) -> Signal:
	_motion = kind
	_motion_time = 0.0
	_motion_duration = maxf(seconds, 0.01)
	_motion_serial += 1
	visible = true
	var timer := (Engine.get_main_loop() as SceneTree).create_timer(_motion_duration, run_while_paused)
	timer.timeout.connect(_on_motion_timeout.bind(_motion_serial))
	return timer.timeout


## 時間になった動きを終わりの姿にそろえる（待っている流れが続くより先に呼ばれる）。
func _on_motion_timeout(serial: int) -> void:
	if serial != _motion_serial or _motion == Motion.NONE:
		return
	var kind := _motion
	_motion = Motion.NONE
	position = _motion_to
	if kind == Motion.FALL:
		_in_sea = true
		rotation.y = _face_back_angle()
		if not _flailing:
			_play_body(_action_before_flail)
	elif kind == Motion.HOP and _override_clip != &"" and mascot != null:
		# 着地：ひざを曲げて受け止め、LAND_SECONDS のあとに台本の動きへ戻す
		_begin_override(LAND_CLIP, LAND_BLEND, true, &"timed")
		_timed_left = LAND_SECONDS
	elif kind == Motion.SIT:
		rotation.y = _yaw_to
		_seat_down(0.2)
	elif kind == Motion.TURN:
		rotation.y = _yaw_to
	elif kind in [Motion.CLOUD, Motion.GLIDE, Motion.WALK, Motion.STEP, Motion.STAND]:
		_end_override()


## 跳ぶ・雲で飛ぶなどの間の動き（clip）にする。kind は _override_kind。練習の動きがないときは何もしない（台本の動きのまま）。
func _begin_override(clip: StringName, blend: float, restart: bool, kind := &"motion") -> void:
	_timed_left = 0.0
	if not _has_practice or mascot == null:
		return
	_override_clip = clip
	_override_kind = kind
	mascot.play_clip(clip, restart, blend)


## 座った姿にする（立つ・place_at まで続く）。操縦士の動きがなければ、座る動きの終わりの姿のまま。
func _seat_down(blend: float) -> void:
	if not _has_practice or mascot == null:
		return
	_timed_left = 0.0
	_override_kind = &"seated"
	if _has_pilot:
		_override_clip = SEATED_CLIP
		mascot.play_clip(SEATED_CLIP, true, blend)
	else:
		_override_clip = SIT_DOWN_CLIP
		mascot.play_clip(SIT_DOWN_CLIP, true, blend)
		mascot.player.seek(mascot.player.current_animation_length, true)


## 跳ぶ・着地・雲で飛ぶなどの動きをやめて、台本の動きに戻す。
func _end_override() -> void:
	if _override_clip == &"":
		return
	_clear_override()
	_resume_body()


func _clear_override() -> void:
	_override_clip = &""
	_override_kind = &""
	_timed_left = 0.0


## 台本の動き（おどっている・ハイタッチのあとに喜んでいる・じたばたならそれ）に戻す。
func _resume_body() -> void:
	if _flailing:
		_play_body(&"cheer")
	elif _dancing:
		_play_body(&"dance", true)
	elif _cheer_left > 0.0:
		_play_body(&"cheer")
	else:
		_play_body(_action)


## 台本の動きの名前（ACTIONS）で体を動かす。雲の上で動きを指定していない（&"idle"）ときは雲に乗る動き。
## 練習の動きがないときは FALLBACK の客席のハテナの動きにする。
func _play_body(action: StringName, restart := false) -> void:
	if mascot == null:
		return
	var target: StringName = ACTIONS.get(action, action)
	if _has_practice and action == &"idle" and has_cloud():
		target = RIDE_CLIP
	if String(target).begins_with(String(PRACTICE_LIBRARY) + "/"):
		if _has_practice:
			mascot.play_clip(target, restart)
			return
		target = FALLBACK.get(action, &"idle")
	mascot.play(target, restart)


## 道すじの動きの始めの所のほうを向く角度。
func _face_back_angle() -> float:
	var back := Vector2(_motion_from.x - _motion_to.x, _motion_from.z - _motion_to.z)
	return atan2(back.x, back.y) if back.length() > 0.01 else rotation.y


## 道すじの動きを打ち切る（跳ぶ・雲で飛ぶ・歩くなどの間の動きもやめる。着地・ドアの手・座った姿はそのまま）。
func _stop_motion() -> void:
	var stopped := _motion != Motion.NONE
	_motion = Motion.NONE
	_motion_serial += 1
	if stopped and _override_kind == &"motion":
		_end_override()


func _leave_sea() -> void:
	_in_sea = false
	if _flailing:
		set_flailing(false)


# ---------- 重ねる動き ----------

## 海でじたばたする（体をゆらし、ばんざいの動きを速く）。
func set_flailing(on: bool) -> void:
	if on == _flailing:
		return
	_flailing = on
	if on:
		_action_before_flail = _action
		_play_body(&"cheer")
	else:
		_play_body(_action_before_flail)


## ぶるぶるふるえる（雲の上で）。
func tremble(seconds := 1.2) -> void:
	_tremble_left = maxf(seconds, 0.0)


## くるっと1回転（0.5秒）。
func spin() -> void:
	_spin_time = 0.0


## 横へひょいとよけて戻る（side は +1 で画面の左＝+x、−1 で右）。
func dodge(side: float) -> void:
	_dodge_side = signf(side) if side != 0.0 else 1.0
	_dodge_time = 0.0


## 台本の動きの名前（ACTIONS）か、StandMascot の動きの名前。&"cross"（×のポーズ）の赤い × の文字と、
## 練習の動きがないときの &"tilt"（体を横に傾ける）は、次の play か POSE_HOLD_SECONDS 秒でやめる。じたばた中は、やめたあとの動きとして覚えておく。
## おどっている（set_dancing）ときと、ハイタッチのあとに喜んでいるときは、それをやめてこの動きにする。
## 跳ぶ・着地・雲で飛ぶの間は、それが終わってからこの動きにする。
func play(action: StringName) -> void:
	_action = action
	_dancing = false
	_cheer_left = 0.0
	if action == &"cross" or action == &"tilt":
		_pose = action
		_pose_time = 0.0
	else:
		_pose = &""
	if _flailing:
		_action_before_flail = action
		return
	if _override_clip != &"":
		return
	_play_body(action)


## いまの台本の動きの名前（play で渡した名前）。
func current_action() -> StringName:
	return _action


## 足もとに雲を出す（1-6 で海から戻るときなど）。雲に乗る・降りると、動きを指定していないときの動き（雲に乗る動き）も変わる。
## 雲を離していたら（leave_cloud_here など）、足もとに戻す。
func set_cloud(on: bool) -> void:
	if _cloud == null:
		return
	if _cloud_detached:
		_attach_cloud()
	if _cloud.visible == on:
		return
	_cloud.visible = on
	if _action == &"idle" and _override_clip == &"" and not _flailing and not _dancing and _cheer_left <= 0.0:
		_play_body(_action)


## 雲に乗っている（足もとに雲がある。離した雲は数えない）。
func has_cloud() -> bool:
	return _cloud != null and _cloud.visible and not _cloud_detached


# ---------- 雲を離す・呼ぶ・帰す（席へ戻る・席を離れる。phase9_design.md 5章） ----------

## 雲から降りる前：雲をいまの所（足もと）に残す。このあと跳んで降りても、雲はそこに浮かんだまま。
func leave_cloud_here() -> void:
	if _cloud == null or not has_cloud():
		return
	_detach_cloud(position, rotation.y)


## 離した雲を、ふわっと上の遠くへ帰す（小さくなって消え、足もとへ戻る）。消えた時刻に返り値の signal が来る。
func send_cloud_away(seconds := 0.9) -> Signal:
	if _cloud_detached and _cloud != null and _cloud.visible:
		var to := _cloud_anchor + CLOUD_LEAVE_TO * absf(scale.x)
		_cloud_move = {"from": _cloud_anchor, "to": to, "time": 0.0, "seconds": maxf(seconds, 0.01),
			"size_from": 1.0, "size_to": 0.15, "hide": true}
		_play_sfx(CLOUD_SFX, -10.0)
	return (Engine.get_main_loop() as SceneTree).create_timer(maxf(seconds, 0.01), run_while_paused).timeout


## 雲を呼ぶ：雲が遠くから飛んできて、pos（雲の上に立つ足の高さ。このノードの位置と同じ決め方）に浮かぶ。
## 着いた時刻に返り値の signal が来る。そのあと hop_to(pos) で跳び乗り、board_cloud() で乗る。
func call_cloud(pos: Vector3, seconds := 0.8) -> Signal:
	if _cloud != null:
		_detach_cloud(pos, rotation.y)
		_cloud.visible = true
		_cloud_move = {"from": pos + CLOUD_CALL_FROM * absf(scale.x), "to": pos, "time": 0.0, "seconds": maxf(seconds, 0.01),
			"size_from": 0.35, "size_to": 1.0, "hide": false}
		_play_sfx(CLOUD_SFX, -6.0)
	return (Engine.get_main_loop() as SceneTree).create_timer(maxf(seconds, 0.01), run_while_paused).timeout


## 呼んだ雲に乗った（雲を足もとへ戻す）。
func board_cloud() -> void:
	if _cloud == null:
		return
	if _cloud_detached:
		_attach_cloud()
	_cloud.visible = true


func _detach_cloud(anchor: Vector3, yaw: float) -> void:
	_cloud_detached = true
	_cloud_anchor = anchor
	_cloud_yaw = yaw
	_cloud_move = {}
	_cloud_holder.top_level = true


func _attach_cloud() -> void:
	_cloud_detached = false
	_cloud_move = {}
	_cloud_holder.top_level = false


## 離した雲の置き方（毎フレーム）：飛んでくる・帰る動きと、ふわふわの上下。
func _update_detached_cloud(delta: float) -> void:
	if not _cloud_detached or _cloud_holder == null:
		return
	var anchor := _cloud_anchor
	var size := 1.0
	if not _cloud_move.is_empty():
		_cloud_move.time = float(_cloud_move.time) + delta
		var k := clampf(float(_cloud_move.time) / float(_cloud_move.seconds), 0.0, 1.0)
		var leaving := bool(_cloud_move.hide)
		var eased := k * k if leaving else 1.0 - pow(1.0 - k, 3.0)
		anchor = (_cloud_move.from as Vector3).lerp(_cloud_move.to, eased)
		size = lerpf(float(_cloud_move.size_from), float(_cloud_move.size_to), eased)
		if k >= 1.0:
			_cloud_anchor = _cloud_move.to
			_cloud_move = {}
			if leaving:
				_cloud.visible = false
				_attach_cloud()
				return
	else:
		anchor += Vector3.UP * sin(_clock * 2.4) * 0.06 * absf(scale.x)
	var parent_xf := (get_parent() as Node3D).global_transform if get_parent() is Node3D else Transform3D.IDENTITY
	var node_xf := Transform3D(Basis(Vector3.UP, _cloud_yaw).scaled(scale), anchor)
	var holder := Transform3D(Basis.from_scale(Vector3.ONE * BODY_SCALE * _cloud_size_shown * size), Vector3(0.0, FOOT_Y, 0.0))
	_cloud_holder.global_transform = parent_xf * node_xf * holder


## 雲の大きさ（1 で等倍）。2-1 のハイタッチでは、プレイヤーが出した手の近くへ来ても雲に埋まらないよう、小さく（0.6 くらい）する。
## 雲が出ていれば 0.3 秒ほどでなめらかに変わる。雲は足の裏を中心に縮む（足の高さ・hand_point は変わらない）。
func set_cloud_size(size: float) -> void:
	_cloud_size = clampf(size, 0.3, 1.5)
	if not has_cloud():
		_cloud_size_shown = _cloud_size


func cloud_size() -> float:
	return _cloud_size


# ---------- 手を出す・ハイタッチ・おどる（段階5） ----------

## 右手を上に出して待つ（ハイタッチ。2-1）。false で下ろす。体の動き（play）はそのまま。
func offer_hand(on: bool) -> void:
	_offering = on
	if on:
		_recoil_time = -1.0


func is_offering_hand() -> bool:
	return _offering


## 出している手（手のひらの真ん中）の位置。ゲーム画面の座標（position と同じ：x、y = 0 が床、z）で、雲の高さ・体の向き・
## ふわふわの上下も入る。手を出していないときも、出したときの位置を返す（手を出す前に、手の高さに合わせて置くのに使える）。
func hand_point() -> Vector3:
	var tip := HAND_SHOULDER
	for i: int in range(HAND_DIRS.size()):
		tip += HAND_DIRS[i].normalized() * HAND_LENGTHS[i]
	var body := _body.transform if _body != null else Transform3D(Basis.from_scale(Vector3.ONE * BODY_SCALE), Vector3(0.0, FOOT_Y, 0.0))
	return transform * (body * tip) - Vector3(0.0, FOOT_Y, 0.0)


## ハイタッチ：「パチン！」の音と手の所のキラッ。手を引っこめて、少しのあいだ喜ぶ（ばんざい）。
## 喜んだあとは前の動きに戻る（そのあいだに play を呼べば、そちらにする）。手は下ろした状態になる（offer_hand(false)）。
func high_five() -> void:
	_spawn_sparkle(_palm_local())
	_play_sfx(HIGH_FIVE_SFX, HIGH_FIVE_SFX_DB, HIGH_FIVE_SFX_PITCH)
	_offering = false
	_recoil_time = 0.0
	_pop_time = 0.0
	_cheer_left = HIGH_FIVE_CHEER_SECONDS
	_dancing = false
	# 雲ですべっている途中でも、すぐ喜ぶ
	_clear_override()
	if not _flailing:
		_play_body(&"cheer", true)


## おどりをくり返す（止めるまで。2-2・2-3）。客席のハテナのおどりに、体のはずみ・ゆれ・ひねりを重ねる。
## ハテナはポーズで止まる（PROCESS_MODE_PAUSABLE）ので、Esc でポーズ画面を開くと、その場でぴたっと止まる。
## false で、おどる前の動きに戻る。play を呼んでもやめる。
func set_dancing(on: bool) -> void:
	if on == _dancing:
		return
	if on:
		_action_before_dance = _action
		_cheer_left = 0.0
		_dancing = true
		_dance_time = 0.0
		if not _flailing and _override_clip == &"":
			_play_body(&"dance", true)
		return
	_dancing = false
	if not _flailing and _override_clip == &"":
		_play_body(_action_before_dance)


func is_dancing() -> bool:
	return _dancing


## 頭の上（吹き出しを付ける所）の画面位置。カメラの後ろにいるときは Vector2.INF。
func bubble_anchor(camera: Camera3D) -> Vector2:
	var head := bubble_point()
	if camera == null or camera.is_position_behind(head):
		return Vector2.INF
	return camera.unproject_position(head)


## 頭の上の点（グローバルな位置。体の動きのずれも入る）。height は等倍のハテナの空間の、足の裏からの高さ。
func bubble_point(height: float = BUBBLE_HEIGHT) -> Vector3:
	return global_transform * (Vector3(0.0, FOOT_Y, 0.0) + _offset + Vector3.UP * height * BODY_SCALE)


func _play_sfx(cue: StringName, volume_db: float, pitch_scale: float = 1.0) -> void:
	var audio := get_node_or_null(^"/root/AudioManager")
	if audio != null and audio.has_method("play_sfx"):
		audio.play_sfx(cue, volume_db, pitch_scale)


# ---------- 毎フレーム ----------

func _process(delta: float) -> void:
	_clock += delta
	# offset：このノードの空間のずれ（m）、rot：体の玉を中心にした回転、squash：大きさ、cloud：雲のずれ
	var offset := Vector3.ZERO
	var rot := Vector3.ZERO
	var squash := Vector3.ONE
	var cloud := Vector3.ZERO
	var cloud_scale := 1.0
	var glide_trail := Vector3.ZERO
	_anim_speed = 1.0
	_cloud_size_shown = move_toward(_cloud_size_shown, _cloud_size, delta * 2.0)
	if _motion != Motion.NONE:
		_motion_time = minf(_motion_time + delta, _motion_duration)
		var t := _motion_time / _motion_duration
		match _motion:
			Motion.HOP:
				position = _motion_from.lerp(_motion_to, t) + Vector3.UP * (4.0 * _motion_height * t * (1.0 - t))
			Motion.WALK:
				position = _motion_from.lerp(_motion_to, t)
				if _override_clip == WALK_CLIP or _override_clip == DUCK_WALK_CLIP:
					# 足を運ぶ動き：足の速さを歩く速さに合わせる
					_anim_speed = _walk_rate
				else:
					var walked := _motion_from.distance_to(position)
					var step := walked / WALK_STRIDE * PI
					offset.y += absf(sin(step)) * WALK_BOUNCE
					rot.z += sin(step) * 0.09
					_anim_speed = 1.4
			Motion.STEP:
				# 段の上り下り：前の足を置くまでに高さの大半を移す
				var eased := t * t * (3.0 - 2.0 * t)
				var flat := _motion_from.lerp(_motion_to, eased)
				var rise := lerpf(_motion_from.y, _motion_to.y, sqrt(eased))
				position = Vector3(flat.x, rise + _motion_height * sin(t * PI), flat.z)
			Motion.SIT:
				# かがむまではその場（前の 30%）、そのあとお尻から座面へ（後ろへ小さく弧をえがく）。向きは前半で座る向きへ
				var m := clampf((t - 0.3) / 0.7, 0.0, 1.0)
				m = m * m * (3.0 - 2.0 * m)
				position = _motion_from.lerp(_motion_to, m) + Vector3.UP * _motion_height * sin(m * PI)
				var turn := clampf(t / 0.5, 0.0, 1.0)
				rotation.y = lerp_angle(_yaw_from, _yaw_to, turn * turn * (3.0 - 2.0 * turn))
			Motion.STAND:
				# 座面を押して立つ：はじめの 20% はその場、そのあと前の立つ所へ
				var m := clampf((t - 0.2) / 0.8, 0.0, 1.0)
				m = m * m * (3.0 - 2.0 * m)
				position = _motion_from.lerp(_motion_to, m) + Vector3.UP * _motion_height * sin(m * PI)
			Motion.TURN:
				var turn := t * t * (3.0 - 2.0 * t)
				rotation.y = lerp_angle(_yaw_from, _yaw_to, turn)
			Motion.FALL:
				var slip := minf(_motion_duration * SLIP_RATIO, SLIP_MAX_SECONDS) / _motion_duration
				if t < slip:
					# 足がすべって、うしろへのけぞる（足もとは少し前へ）
					var k := t / slip
					var ahead := Vector3(_motion_to.x - _motion_from.x, 0.0, _motion_to.z - _motion_from.z).normalized()
					position = _motion_from + ahead * 0.35 * k
					rot.x = -0.5 * sin(k * PI * 0.5)
				else:
					var k := (t - slip) / (1.0 - slip)
					var start := _motion_from + Vector3(_motion_to.x - _motion_from.x, 0.0, _motion_to.z - _motion_from.z).normalized() * 0.35
					var flat := start.lerp(_motion_to, k)
					position = Vector3(flat.x, lerpf(start.y, _motion_to.y, k * k) + 4.0 * FALL_RISE * k * (1.0 - k), flat.z)
					rot.x = lerpf(-0.5, 0.0, k) + sin(k * PI) * 1.1
					rot.z = sin(k * TAU * 2.0) * 0.3
					squash = Vector3(0.92, 1.12, 0.92)
					if k > 0.5:
						rotation.y = lerp_angle(rotation.y, _face_back_angle(), minf(1.0, delta * 10.0))
				_anim_speed = 2.2
			Motion.CLOUD:
				var arrive := _cloud_arrive
				if t < arrive:
					# 雲がゲーム画面の左上のほうから飛んできて、足もとに入る
					var k := t / arrive
					var eased := 1.0 - pow(1.0 - k, 3.0)
					cloud = basis.inverse() * CLOUD_FROM * (1.0 - eased)
					cloud_scale = lerpf(0.35, 1.0, eased)
					position = _motion_from
				else:
					if _flailing:
						set_flailing(false)
					_in_sea = false
					var k := (t - arrive) / (1.0 - arrive)
					var eased := k * k * (3.0 - 2.0 * k)
					var flat := _motion_from.lerp(_motion_to, eased)
					position = Vector3(flat.x, lerpf(_motion_from.y, _motion_to.y, eased) + 4.0 * _motion_height * k * (1.0 - k), flat.z)
					var travel := Vector2(_motion_to.x - _motion_from.x, _motion_to.z - _motion_from.z)
					if travel.length() > 0.5:
						rotation.y = lerp_angle(rotation.y, atan2(travel.x, travel.y), minf(1.0, delta * 8.0))
			Motion.GLIDE:
				# すっと出て、すっと止まる。途中で少し浮き上がり、動くほうと逆へ体を傾ける（雲に引っぱられる）
				var eased := t * t * (3.0 - 2.0 * t)
				position = _motion_from.lerp(_motion_to, eased) + Vector3.UP * sin(t * PI) * GLIDE_RISE
				var local_travel := basis.inverse() * (_motion_to - _motion_from)
				if absf(local_travel.x) > 0.05:
					rot.z += signf(local_travel.x) * sin(t * PI) * GLIDE_LEAN
				# 雲のなびき：速さ（なめらかな動きの微分）の逆向き
				var speed := 6.0 * t * (1.0 - t) / _motion_duration
				glide_trail = -local_travel * speed * GLIDE_TRAIL_PER_SPEED
	if _in_sea:
		offset.y += sin(_clock * 2.0) * 0.07 - SEA_SINK
		rot.z += sin(_clock * 1.6) * 0.06
	if _flailing:
		offset.y += absf(sin(_clock * 8.0)) * 0.16
		rot.z += sin(_clock * 10.0) * 0.22
		rot.x += sin(_clock * 7.0) * 0.12
		_anim_speed = 2.2
	if has_cloud() and _motion == Motion.NONE:
		# 雲の上でふわふわ
		var hover := sin(_clock * 2.4) * 0.06
		offset.y += hover
		cloud.y += hover
	if _tremble_left > 0.0:
		_tremble_left = maxf(_tremble_left - delta, 0.0)
		var k := minf(1.0, _tremble_left / 0.2)
		offset.x += sin(_clock * 71.0) * 0.035 * k
		offset.z += cos(_clock * 57.0) * 0.03 * k
		rot.z += sin(_clock * 63.0) * 0.06 * k
		squash.y *= 1.0 - 0.03 * k
	if _spin_time >= 0.0:
		_spin_time += delta
		var p := clampf(_spin_time / SPIN_SECONDS, 0.0, 1.0)
		rot.y += TAU * p * p * (3.0 - 2.0 * p)
		offset.y += sin(p * PI) * 0.3
		if p >= 1.0:
			_spin_time = -1.0
	if _dodge_time >= 0.0:
		_dodge_time += delta
		var away := 0.0
		var lift := 0.0
		if _dodge_time < DODGE_OUT:
			var p := _dodge_time / DODGE_OUT
			away = 1.0 - pow(1.0 - p, 2.0)
			lift = sin(p * PI) * 0.35
		elif _dodge_time < DODGE_OUT + DODGE_HOLD:
			away = 1.0
		elif _dodge_time < DODGE_OUT + DODGE_HOLD + DODGE_BACK:
			var p := (_dodge_time - DODGE_OUT - DODGE_HOLD) / DODGE_BACK
			away = 1.0 - p * p * (3.0 - 2.0 * p)
			lift = sin(p * PI) * 0.22
		else:
			_dodge_time = -1.0
		offset += basis.inverse() * Vector3(_dodge_side * DODGE_DISTANCE * away, 0.0, 0.0) + Vector3.UP * lift
	if _dancing:
		# おどり：1秒に2回はずみ、1秒に1往復、左右にゆれてひねる
		_dance_time += delta
		var beat := _dance_time * TAU
		offset.y += absf(sin(beat)) * DANCE_BOUNCE
		rot.z += sin(beat * 0.5) * DANCE_SWAY
		rot.y += sin(beat * 0.5) * DANCE_TWIST
	if _pop_time >= 0.0:
		# ハイタッチ：ぴょんとはずむ
		_pop_time += delta
		var p := clampf(_pop_time / HIGH_FIVE_POP_SECONDS, 0.0, 1.0)
		offset.y += sin(p * PI) * 0.28
		var k := sin(p * PI) * (1.0 - p)
		squash *= Vector3(1.0 - 0.1 * k, 1.0 + 0.16 * k, 1.0 - 0.1 * k)
		if p >= 1.0:
			_pop_time = -1.0
	if _cheer_left > 0.0:
		_cheer_left = maxf(_cheer_left - delta, 0.0)
		if _cheer_left <= 0.0 and not _flailing and not _dancing and _override_clip == &"":
			_play_body(_action)
	if _timed_left > 0.0:
		_timed_left = maxf(_timed_left - delta, 0.0)
		if _timed_left <= 0.0:
			_end_override()
	var pose_weight := 0.0
	if _pose != &"":
		_pose_time += delta
		if _pose_time >= POSE_HOLD_SECONDS + POSE_IN_SECONDS:
			_pose = &""
		else:
			pose_weight = minf(_pose_time / POSE_IN_SECONDS, 1.0)
			if _pose_time > POSE_HOLD_SECONDS:
				pose_weight = 1.0 - (_pose_time - POSE_HOLD_SECONDS) / POSE_IN_SECONDS
	if _pose == &"tilt" and not _has_practice:
		# 練習の動きがないときだけ、体ごと傾けて首をかしげる代わりにする
		rot.z += TILT_ANGLE * pose_weight * pose_weight * (3.0 - 2.0 * pose_weight)
	_update_cross_mark(pose_weight if _pose == &"cross" else 0.0, offset)
	_update_sea_ring(delta, offset)
	_apply_body(offset, rot, squash, cloud, cloud_scale)
	_update_detached_cloud(delta)
	if mascot != null and visible:
		mascot.advance(delta * _anim_speed)
		# 動きを進めたあとに、出している手で腕の骨を上書きする（次の advance で動きの姿勢に戻るので、毎フレーム）
		_apply_hand_pose(delta)
	_update_hand_glow()
	_update_sparkles(delta)
	_update_cloud_trail(delta, glide_trail)


## 腕の骨を、手を出した姿勢へ寄せる（_hand_weight：0 で動きのまま、1 で HAND_DIRS の向き）。
## ハイタッチの直後は、手首が後ろへ反ってから下りる。
func _apply_hand_pose(delta: float) -> void:
	if _skeleton == null:
		return
	var recoil := 0.0
	if _recoil_time >= 0.0:
		_recoil_time += delta
		var p := _recoil_time / HIGH_FIVE_RECOIL_SECONDS
		if p >= 1.0:
			_recoil_time = -1.0
		else:
			recoil = sin(p * PI)
	if _offering:
		_hand_weight = minf(1.0, _hand_weight + delta / HAND_RAISE_SECONDS)
	elif _recoil_time < 0.0:
		_hand_weight = maxf(0.0, _hand_weight - delta / HAND_LOWER_SECONDS)
	if _hand_weight <= 0.0:
		return
	var w := _hand_weight * _hand_weight * (3.0 - 2.0 * _hand_weight)
	# 左手は下ろす（初期姿勢の腕）。上げた右手だけが目立つように
	for bone: int in _other_arm_bones:
		var rest := _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_pose_rotation(bone).slerp(rest, w * 0.85))
	for i: int in range(_hand_bones.size()):
		var bone := _hand_bones[i]
		var dir := HAND_DIRS[i].normalized()
		if i == HAND_DIRS.size() - 1 and recoil > 0.0:
			# パチン：手首が後ろ（−z）へ反る
			dir = (dir + Vector3(0.0, 0.0, -1.1) * recoil).normalized()
		# 初期姿勢の骨を、いちばん小さな回転で dir へ向けた向き（体の空間）→ 親の骨から見た回転
		var rest := _skeleton.get_bone_global_rest(bone).basis.orthonormalized()
		var target := Basis(Quaternion(rest.y.normalized(), dir)) * rest
		var parent := _skeleton.get_bone_parent(bone)
		var parent_basis := _skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		var local := (parent_basis.inverse() * target).get_rotation_quaternion()
		_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_pose_rotation(bone).slerp(local, w))


## 体の右手のひらの真ん中（このノードの空間）。骨格がなければ、出したときの手の位置。
func _palm_local() -> Vector3:
	if _skeleton == null or _hand_bones.is_empty():
		return transform.affine_inverse() * (hand_point() + Vector3(0.0, FOOT_Y, 0.0))
	# 骨格の空間は体（_body）の空間と同じ（StandMascot・模型・Rig は動かさない）
	var pose := _skeleton.get_bone_global_pose(_hand_bones[_hand_bones.size() - 1])
	var palm := pose.origin + pose.basis.y.normalized() * HAND_LENGTHS[HAND_LENGTHS.size() - 1]
	return _body.transform * palm


## 出している手のまわりの光：手が上がりきるころに出て、ゆっくり脈打つ。手を下ろす・ハイタッチで消える。
func _update_hand_glow() -> void:
	if _hand_glow == null:
		return
	var weight := clampf((_hand_weight - 0.6) / 0.4, 0.0, 1.0) if _offering else 0.0
	_hand_glow.visible = weight > 0.0 and visible
	if not _hand_glow.visible:
		return
	_hand_glow.position = _palm_local()
	var pulse := 0.5 + 0.5 * sin(_clock * TAU * HAND_GLOW_HZ)
	_hand_glow.scale = Vector3.ONE * HAND_GLOW_RADIUS * (0.92 + 0.16 * pulse)
	_hand_glow_materials[0].albedo_color.a = (0.55 + 0.4 * pulse) * weight
	_hand_glow_materials[1].albedo_color.a = (0.12 + 0.18 * pulse) * weight


## キラッ：手の所（このノードの空間の点）に、黄色い大きな星・白い星・広がる輪・飛び散る小さな星。いつもカメラを向く。
func _spawn_sparkle(local_point: Vector3) -> void:
	var root := Node3D.new()
	root.name = "HighFiveSparkle"
	root.position = local_point
	add_child(root)
	var parts: Array[MeshInstance3D] = []
	parts.append(_sparkle_part(root, Shapes.polygon_mesh(Shapes.star(1.0, 0.2, 4)), Color(1.0, 0.84, 0.22)))
	parts.append(_sparkle_part(root, Shapes.polygon_mesh(Shapes.star(0.55, 0.13, 4)), Color(1.0, 1.0, 0.94), 1))
	parts.append(_sparkle_part(root, Shapes.ring_mesh(0.86, 1.0, 40), Color(1.0, 0.95, 0.6)))
	for i: int in range(8):
		var color := Color(1.0, 0.9, 0.35) if i % 2 == 0 else Color(0.62, 0.92, 1.0)
		parts.append(_sparkle_part(root, Shapes.polygon_mesh(Shapes.star(0.32, 0.08, 4)), color))
	_sparkles.append({"node": root, "time": 0.0, "parts": parts})


func _sparkle_part(root: Node3D, mesh: Mesh, color: Color, priority_step: int = 0) -> MeshInstance3D:
	var material := Shapes.flat_material(color, true, false, 40 + priority_step, false, true)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	var part := Shapes.add_mesh(root, mesh, material)
	part.scale = Vector3.ONE * 0.01
	return part


func _update_sparkles(delta: float) -> void:
	for i: int in range(_sparkles.size() - 1, -1, -1):
		var sparkle: Dictionary = _sparkles[i]
		var node := sparkle.node as Node3D
		sparkle.time = float(sparkle.time) + delta
		var p := float(sparkle.time) / SPARKLE_SECONDS
		if p >= 1.0 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_sparkles.remove_at(i)
			continue
		var parts: Array = sparkle.parts
		# 大きな星：ポンと出て（はじめの 25%）、回りながら小さくなる
		var grow := 1.0 - pow(1.0 - minf(p / 0.25, 1.0), 3.0)
		var shrink := 1.0 if p < 0.25 else 1.0 - (p - 0.25) / 0.75
		var fade := 1.0 - maxf(0.0, (p - 0.6) / 0.4)
		for k: int in range(2):
			var star := parts[k] as MeshInstance3D
			star.scale = Vector3.ONE * maxf(SPARKLE_SIZE * grow * shrink * (1.0 if k == 0 else 1.15), 0.01)
			star.rotation.z = p * 1.2
		var ring := parts[2] as MeshInstance3D
		ring.scale = Vector3.ONE * SPARKLE_SIZE * lerpf(0.4, 2.0, 1.0 - pow(1.0 - p, 2.0))
		(ring.material_override as StandardMaterial3D).albedo_color.a = 0.85 * (1.0 - p)
		for k: int in range(3, parts.size()):
			var bit := parts[k] as MeshInstance3D
			var angle := TAU * float(k - 3) / float(parts.size() - 3) + 0.4
			var reach := SPARKLE_SIZE * 1.9 * (1.0 - pow(1.0 - p, 2.5))
			bit.position = Vector3(cos(angle), sin(angle), 0.0) * reach
			bit.scale = Vector3.ONE * maxf(SPARKLE_SIZE * 0.9 * grow * (1.0 - p * 0.6), 0.01)
			(bit.material_override as StandardMaterial3D).albedo_color.a = fade


## 雲のなびき（雲の shader の trail）：すべる速さからのなびきと、外から入れたなびき（set_cloud_trail）をなめらかに。
func _update_cloud_trail(delta: float, glide_trail: Vector3) -> void:
	if _cloud == null:
		return
	var target := (glide_trail + _external_trail).limit_length(GLIDE_TRAIL_MAX)
	if target.is_zero_approx() and _cloud_trail.is_zero_approx():
		return
	_cloud_trail = _cloud_trail.lerp(target, minf(1.0, delta * 8.0))
	if _cloud_trail.length() < 0.001 and target.is_zero_approx():
		_cloud_trail = Vector3.ZERO
	var material := _cloud.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("trail", _cloud_trail)


## 雲を外から動かしているとき（ハテナの小窓が画面の上をすべるなど）のなびき（このノードの空間の向き・m。0 で止める）。
func set_cloud_trail(trail: Vector3) -> void:
	_external_trail = trail


## 体（と雲）の置き方を決める。回転は体の玉の真ん中を中心にする。
func _apply_body(offset: Vector3, rot: Vector3, squash: Vector3, cloud: Vector3, cloud_scale: float = 1.0) -> void:
	_offset = offset
	if _body == null:
		return
	var turn := Basis.from_euler(rot)
	var pivot := Vector3.UP * BALL_CENTER * BODY_SCALE
	var base := Vector3(0.0, FOOT_Y, 0.0) + offset
	_body.transform = Transform3D(turn * Basis.from_scale(squash * BODY_SCALE), base + pivot - turn * pivot)
	if _cloud_holder != null and not _cloud_detached:
		_cloud_holder.transform = Transform3D(Basis.from_scale(Vector3.ONE * BODY_SCALE * cloud_scale * _cloud_size_shown),
			Vector3(0.0, FOOT_Y, 0.0) + cloud + Vector3(offset.x, 0.0, offset.z))


## 水面の輪：海に浮いている間だけ、水面（StageConstants.OCEAN_SURFACE_Y）に出す。じたばた中は波紋が速い。
func _update_sea_ring(delta: float, offset: Vector3) -> void:
	if _sea_ring == null:
		return
	_sea_ring.visible = _in_sea and visible
	if not _sea_ring.visible:
		return
	_sea_ring.position = Vector3(offset.x, StageConstants.OCEAN_SURFACE_Y + 0.04 - position.y, offset.z)
	var period := SEA_RIPPLE_FLAIL_SECONDS if _flailing else SEA_RIPPLE_SECONDS
	_sea_ripple_time = fmod(_sea_ripple_time + delta, period)
	var p := _sea_ripple_time / period
	_sea_ripple.scale = Vector3.ONE * lerpf(1.0, 2.1, p)
	_sea_ripple_material.albedo_color = Color(1.0, 1.0, 1.0, 0.65 * (1.0 - p))


## ×の印：ポンと出て、少しゆれる。体の玉の真ん中に重ねる。
func _update_cross_mark(weight: float, offset: Vector3) -> void:
	if _cross_mark == null:
		return
	_cross_mark.visible = weight > 0.01
	if not _cross_mark.visible:
		return
	var pop := 1.0 + 0.25 * sin(minf(weight, 1.0) * PI)
	_cross_mark.scale = Vector3.ONE * maxf(weight, 0.01) * pop
	_cross_mark.position = Vector3(0.0, FOOT_Y + BALL_CENTER * BODY_SCALE, 0.0) + offset
	_cross_mark.rotation = Vector3(0.0, 0.0, sin(_clock * 9.0) * 0.08)
