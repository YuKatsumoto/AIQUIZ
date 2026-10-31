class_name SkyGateRuleDemo
extends SubViewport

## 図解ルールカードの実演（docs/sudden_death_v2/skygate_impact.md 第5章）。AI の絵は使わず、ゲームと同じボード（SkyGateBoard）・
## プレイヤーの見た目の人形・効果（SkyGateEffects）・つき破る動き（SkyGateImpact）・本戦の空の環境で、ルールの 3 つの場面を
## 小さな別の世界でくり返し見せる。HUD（SkyGateHud）は get_texture() をカードの絵として描く。
##   "steer"  ：動いて正しい答えのパネルの上へ（見下ろし。真下のパネルが自分の色で光る）
##   "burst"  ：正解のパネルは紙を破って抜ける（見下ろしのまま。ボードは体の上を通りすぎながら消える）
##   "bounce" ：まちがいのパネルは破れず、力が抜けて（ラグドール）はね返されて爆散する（カードの小さな絵なので、その人の寄りの画。
##             本戦は 2026-10-25 から画を切り替えず、見下ろしのまま強いスローで見せる）
## カードが出ている間だけ描いて時計を進める（set_playing）。

const LOOP := {"steer": 3.8, "burst": 2.7, "bounce": 2.9}
## 例の問題（文字は選択肢だけ読めれば十分。答えは 1 番の「56」）。
const QUESTION := "7 × 8 = ?"
const CHOICES := ["54", "56", "63", "64"]
const RIGHT_PANEL := 1
const WRONG_PANEL := 2
## 紙に当たるまでの近づき（秒）と、そのはじめの深さ（m）。
const APPROACH := 0.9
const APPROACH_FROM := 9.0
## はね返される場面の寄りの画：体から見た目の位置（外へ・上へ・うしろへ m）と画角（もとの本戦の G6_Death の値）。
const BOUNCE_EYE := Vector3(2.2, 2.0, -4.4)
const BOUNCE_FOV := 50.0
## 見下ろしの場面：ボードの深さ（m）・人形が動く道すじ（ボードの座標）。
const STEER_DEPTH := 4.5
const STEER_FROM := Vector2(-3.6, -3.1)
const STEER_TO := Vector2(3.4, 0.9)
## 実演の世界の太陽（本戦の空のセットと同じ向き）。
const SUN_DIRECTION := Vector3(-0.533, -0.742, 0.407)

var kind := "steer"
var player := 1
var quality := "balanced"

var _camera: Camera3D = null
var _board: SkyGateBoard = null
var _fx: SkyGateEffects = null
var _doll: Dictionary = {}
var _doll_root: Node3D = null
var _doll_shown: Array[Node3D] = []
var _clouds: Array[MeshInstance3D] = []
var _limp: SkyGateLimp = null
## テスト：時計を止める（画は描き続ける。debug_seek した時刻のまま撮れる）。
var debug_freeze := false
var _last_dt := 0.0
var _time := 0.0
var _loop := 0
var _cues := {}
var _playing := false


## kind（"steer" / "burst" / "bounce"）、player（1 / 2：人形の見た目と光る枠の色）。state はプレイヤーの帽子とスキン（null でもよい）。
func build(demo_kind: String, demo_player: int, state: QuizGameState, quality_name: String, pixel_size: Vector2i) -> void:
	kind = demo_kind
	player = clampi(demo_player, 1, 2)
	quality = GraphicsQuality.normalize(quality_name)
	name = "SkyGateRuleDemo_%s" % kind
	size = pixel_size
	own_world_3d = true
	transparent_bg = false
	msaa_3d = Viewport.MSAA_2X if quality != GraphicsQuality.LOW else Viewport.MSAA_DISABLED
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var world := WorldEnvironment.new()
	world.environment = SkyFallScenery.venue_environment(quality)
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.shadow_enabled = false
	add_child(sun)
	sun.transform = Transform3D(Basis.looking_at(SUN_DIRECTION, Vector3.UP), Vector3.ZERO)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.near = 0.1
	_camera.far = 600.0
	add_child(_camera)
	_build_clouds()
	_board = SkyGateBoard.new()
	_board.name = "DemoBoard"
	add_child(_board)
	_board.build(quality)
	_board.set_question(QUESTION, CHOICES)
	_fx = SkyGateEffects.new()
	_fx.name = "DemoFx"
	add_child(_fx)
	_fx.build(quality)
	_doll_root = Node3D.new()
	_doll_root.name = "DemoDoll"
	add_child(_doll_root)
	var hat := 0
	var skin := {}
	if state != null:
		hat = state.p1_hat if player == 1 else state.p2_hat
		skin = state.get_display_skin(player)
	_doll = EmoteBlockmanPreview.build_player_skeleton(player == 1, _doll_root, hat, 0, skin)
	_doll["root"] = _doll_root
	_limp = SkyGateLimp.new(player)
	for node: Node in _doll_root.find_children("*", "MeshInstance3D", true, false):
		if (node as Node3D).visible:
			_doll_shown.append(node as Node3D)
	_restart()
	_pose(0.0)


## カードが出ている間だけ描く。止めると最後の画のまま。
func set_playing(on: bool) -> void:
	if on == _playing:
		return
	_playing = on
	if on:
		_time = 0.0
		_loop = 0
		_restart()
		_pose(0.0)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func is_playing() -> bool:
	return _playing


## テスト：時計を進めて、その時刻の画にする。
func debug_seek(seconds: float) -> void:
	_time = 0.0
	_loop = 0
	_restart()
	var step := 1.0 / 60.0
	var t := 0.0
	while t < seconds:
		_advance(step)
		t += step


func _process(delta: float) -> void:
	if _playing and not debug_freeze:
		_advance(delta)


func _advance(delta: float) -> void:
	var length := float(LOOP[kind])
	_last_dt = delta
	_time += delta
	if _time >= length:
		_time -= length
		_loop += 1
		_restart()
	var t := _time
	var scale := 1.0
	if kind != "steer":
		scale = SkyGateImpact.time_scale(t - APPROACH, SkyGateImpact.ALL_BURST if kind == "burst" else SkyGateImpact.ALL_BOOM)
	_pose(delta * scale)


## 1 回分の初めへ：穴・へこみ・効果を消して、人形を戻す。
func _restart() -> void:
	_cues.clear()
	if _limp != null:
		_limp.reset()
	if _board != null:
		_board.reset()
		_board.set_question(QUESTION, CHOICES)
	if _fx != null:
		_fx.clear()
	for node: Node3D in _doll_shown:
		node.visible = true
	var pelvis := _doll.get("pelvis") as Node3D
	if pelvis != null:
		pelvis.visible = true


func _pose(sd: float) -> void:
	match kind:
		"steer":
			_pose_steer(sd)
		_:
			_pose_impact(sd, kind == "burst")
	_drift_clouds(sd)
	if _board != null:
		_board.advance(sd)
	if _fx != null:
		_fx.advance(sd)


## 見下ろし：はじめは手前の左（まちがい）の上、そこから奥の右（正解）へ動いて止まる。真下のパネルが光る。ボードはゆっくり寄る。
func _pose_steer(_sd: float) -> void:
	var t := _time
	var u := smoothstep(0.7, 2.2, t)
	var local := STEER_FROM.lerp(STEER_TO, u)
	# 少しだけ弧を描いて動く
	local.y += sin(u * PI) * 0.8
	var depth := lerpf(STEER_DEPTH + 2.0, STEER_DEPTH, smoothstep(0.0, float(LOOP.steer), t))
	_board.global_transform = Transform3D(_board_basis(), Vector3(0.0, -depth, 0.0))
	var panel := SkyGateGame.panel_for_local(local)
	for i in range(SkyGateBoard.PANEL_COUNT):
		_board.set_highlight(i, player, i == panel)
	var velocity := (STEER_TO - STEER_FROM) * (smoothstep(0.7, 2.2, t + 0.05) - u) / 0.05
	var lean := Vector2(velocity.x, velocity.y) / SkyGateGame.MOVE_SPEED
	_place_doll(_air_point(local), lean.limit_length(1.0), Basis.IDENTITY)
	# 2人の上・少しうしろから見下ろす（本戦の G2 と同じく、ほぼ真上から。人形がどのパネルの上かが遠近でずれて見えない）
	var aim := Vector3(0.0, -depth * 0.8, 1.9)
	var pitch := deg_to_rad(76.0)
	var forward := Vector3(0.0, -sin(pitch), cos(pitch))
	_camera.fov = 46.0
	_camera.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), aim - forward * 23.0)


## 本戦と同じ：ボードが下から寄って APPROACH 秒で届き、SkyGateImpact のとおりに動く。
##   正解：見下ろしのまま、紙を破って抜け、ボードは体の上を通りすぎながら消える。
##   まちがい：その人の寄りの画（外の側の少しうしろの上から）で、力が抜けて（ラグドール）はね返されて爆散。
func _pose_impact(_sd: float, burst: bool) -> void:
	var t := _time
	var it := t - APPROACH
	var mode := SkyGateImpact.ALL_BURST if burst else SkyGateImpact.ALL_BOOM
	var panel := RIGHT_PANEL if burst else WRONG_PANEL
	var local: Vector2 = SkyGateBoard.PANEL_CENTERS[panel] + Vector2(0.4 if burst else -0.3, -0.2)
	var board_y: float
	var body_y := 0.0
	if it < 0.0:
		var u := clampf(t / APPROACH, 0.0, 1.0)
		# 近づき：はじめ速く、届く前にスローへ入る（カードの短い絵の中で届くように）
		board_y = -lerpf(APPROACH_FROM, SkyGateImpact.CONTACT, 1.0 - pow(1.0 - u, 2.2))
	else:
		board_y = SkyGateImpact.board_height(mode, it)
		body_y = SkyGateImpact.body_height(burst, mode, it)
		if not burst and SkyGateImpact.exploded(it):
			body_y = SkyGateImpact.body_height(false, mode, SkyGateImpact.EXPLODE_AT)
	# ボードは、人形（原点）の真下にパネルの local の点が来るように置く
	var basis := _board_basis()
	_board.global_transform = Transform3D(basis, Vector3(0.0, board_y, 0.0) - basis * Vector3(local.x, 0.0, -local.y))
	_board.set_fade(SkyGateImpact.board_alpha(mode, it) if it >= 0.0 else 1.0)
	_board.set_highlight(panel, player, it < SkyGateImpact.fade_start(mode))
	var center := Vector3(0.0, body_y, 0.0)
	var at := _board.board_point(local)
	if it >= 0.0:
		_board.set_dent(panel, 0, at, SkyGateImpact.dent(burst, it))
		if burst:
			if SkyGateImpact.torn(it) and _cue("tear"):
				_board.burst(panel, at)
		else:
			if _cue("limp"):
				_limp.start()
			_board.set_strain(panel, smoothstep(0.04, 0.26, it) * (1.0 - smoothstep(SkyGateImpact.EXPLODE_AT, SkyGateImpact.EXPLODE_AT + 0.4, it)))
			if it >= SkyGateImpact.STRETCH_END and _cue("bounce"):
				_board.bounce(panel, at)
			if SkyGateImpact.exploded(it) and _cue("explode"):
				_limp.reset()
				_fx.player_burst(_doll, center)
				_fx.puffs(center, 1.25, 12, true, 0.6)
				_fx.stars(center, 8, 3.4)
	var spin := Basis.IDENTITY
	if not burst and it >= 0.0 and not SkyGateImpact.exploded(it):
		spin = Basis(Vector3(1, 0, 0), SkyGateImpact.tumble(it))
	if burst or it < SkyGateImpact.EXPLODE_AT:
		_place_doll(center, Vector2.ZERO, spin)
		if not burst and SkyGateImpact.limp(it):
			var h := 1.0 / 120.0
			var v := (SkyGateImpact.body_height(false, mode, it) - SkyGateImpact.body_height(false, mode, it - h)) / h
			_limp.step(_last_dt, v)
			_limp.apply(_doll)
			var pelvis := _doll.get("pelvis") as Node3D
			if pelvis != null:
				_doll_root.global_position += center - pelvis.global_position
	if burst:
		# 見下ろし（本戦の G2 と同じく、ほぼ真上から少しうしろ）
		var aim := Vector3(0.0, -1.5, 1.2)
		var pitch := deg_to_rad(74.0)
		var forward := Vector3(0.0, -sin(pitch), cos(pitch))
		_camera.fov = 46.0
		_camera.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), aim - forward * 15.0)
	else:
		# 寄りの画（外の側の少しうしろの上から、体を追う）
		var out := 1.0 if player == 1 else -1.0
		var off := BOUNCE_EYE
		var eye := Vector3(off.x * out, off.y + body_y * 0.45, off.z)
		_camera.fov = BOUNCE_FOV
		_camera.global_transform = Transform3D(Basis.looking_at(Vector3(0.0, body_y + 0.35, 0.0) - eye, Vector3.UP), eye)


## ボードのノードの向き（本戦と同じ：ボードの x＝右がワールドの −X、y＝前が +Z）。
func _board_basis() -> Basis:
	return Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))


## ボードの座標（m）の、落ちる高さ（y = 0）の点。
func _air_point(local: Vector2) -> Vector3:
	return Vector3(-local.x, 0.0, local.y)


func _place_doll(center: Vector3, lean: Vector2, spin: Basis) -> void:
	_doll_root.global_transform = Transform3D(spin, center)
	if DropMotion.pose_box(_doll, lean, _time + float(player) * 0.37):
		var pelvis := _doll.get("pelvis") as Node3D
		if pelvis != null:
			_doll_root.global_position += center - pelvis.global_position


func _cue(cue_name: String) -> bool:
	if _cues.has(cue_name):
		return false
	_cues[cue_name] = true
	return true


## 落ちている感じ：うすい雲のかたまりが下から上へ流れる。
func _build_clouds() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.85))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 7341 + hash(kind)
	for i in range(7):
		var quad := QuadMesh.new()
		var s := rng.randf_range(6.0, 11.0)
		quad.size = Vector2(s, s * 0.6)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 文字や人形にかからないよう、見下ろしはボードの下、横からの画はうしろの遠くに置く
		if kind == "steer":
			mi.position = Vector3(rng.randf_range(-20.0, 20.0), rng.randf_range(-44.0, -18.0), rng.randf_range(-8.0, 14.0))
		else:
			mi.position = Vector3(rng.randf_range(-22.0, 22.0), rng.randf_range(-26.0, 14.0), rng.randf_range(26.0, 40.0))
		add_child(mi)
		_clouds.append(mi)


func _drift_clouds(sd: float) -> void:
	for mi: MeshInstance3D in _clouds:
		mi.position.y += 18.0 * sd
		var top := -14.0 if kind == "steer" else 16.0
		if mi.position.y > top:
			mi.position.y -= 42.0
