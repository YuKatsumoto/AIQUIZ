extends Node

## 2P の HP・スコア・ゴーストライダーの HUD カードをやめ、ゲーム画面に溶け込ませる 4 案の見比べ用モック。
## 実際の game_world に試作の 3D 表示を重ね、案ごとに「2 人とも生存」と「P2 がゴーストライダー」を撮影する。
## 本番コードには組み込まない。
## 実行: Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --script res://tests/hud_diegetic_mock/mock_bootstrap.gd

const OUT := "res://artifacts/hud_diegetic_mock/"
const P1_COLOR := Color(0.95, 0.55, 0.20)
const P2_COLOR := Color(0.20, 0.65, 0.90)
const GHOST_COLOR := Color(0.55, 0.95, 1.0)
const PERFECT_COLOR := Color(1.0, 0.84, 0.3)
const EMPTY_HEART := Color(0.13, 0.15, 0.19, 0.8)
const NAVY := Color(0.09, 0.17, 0.36)
const PLATE := Color(0.196, 0.243, 0.282)
const BIB := Color(0.97, 0.96, 0.92)
const OUTLINE := Color(0.02, 0.03, 0.08, 0.95)
const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const OPTIONS: Array[String] = ["a_back", "b_overhead", "c_led", "d_floor"]
## モックで見せるチャージ量（PERFECT 帯 0.72〜0.94 の中）とコンボ数。
const CHARGE_SHOWN := 0.8
const COMBO_SHOWN := 3
const LED_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D board : source_color, filter_linear, repeat_disable;
uniform vec2 leds = vec2(720.0, 104.0);
uniform float energy = 1.35;
void fragment() {
	vec2 grid = UV * leds;
	float footprint = max(length(dFdx(grid)), length(dFdy(grid)));
	float far_mix = clamp((footprint - 0.35) / 0.6, 0.0, 1.0);
	float dots = smoothstep(0.5, 0.3, length(fract(grid) - 0.5));
	vec3 lit = mix(texture(board, (floor(grid) + 0.5) / leds).rgb, texture(board, UV).rgb, far_mix);
	ALBEDO = lit * mix(dots, 0.62, far_mix) * energy + vec3(0.006);
}
"""

var gs: QuizGameState
var world: Node3D
var player: Node3D
var ghost: GhostSharkRideController
var helper: Node
var health: Control
var camera: Camera3D
var hide_hud := false
var mock_nodes: Array[Node] = []
var followers: Array[Callable] = []
var led_side := {1: 1.0, 2: -1.0}
var _heart_points := PackedVector2Array()

func _ready() -> void:
	# ゲーム側の HUD は毎フレーム visible を戻すので、その後に処理する。
	process_priority = 1000
	for k in range(48):
		var t := TAU * float(k) / 48.0
		_heart_points.append(Vector2(16.0 * pow(sin(t), 3), 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)) / 16.0)
	call_deferred("run")

func run() -> void:
	await setup_world()
	remember_led_sides()
	await shoot_all("alive")
	if not await enter_ghost_aiming():
		return
	await shoot_all("ghost")
	print("HUD_DIEGETIC_MOCK done")
	get_tree().quit(0)

func setup_world() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	helper = load("res://tests/hp_unit.gd").new()
	gs = helper.fixture(2, Constants.MODE_ENDLESS)
	QuizManager.player_analytics = null
	QuizManager.game_state = gs
	gs.skip_start_helicopter_arrival = true
	gs._active_wall_speed = 0.15
	gs.score = 4
	gs.player2_score = 6
	gs.current_quiz.q = "3 ＋ 2 は？"
	gs.current_quiz.c = PackedStringArray(["5", "6"])
	world = load("res://scenes/game_world.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	player = world.get_node("Player")
	player.prepare_for_loading(gs)
	player.reveal_without_intro_arrival()
	ghost = world.get("_ghost_shark_ride_controller")
	health = world.get_node("GameplayHUD/PlayerHealthHUD")
	await frames(45)
	gs._set_player_hp(2, 2)
	await frames(30)

## P2 を壁で脱落させ、ゴーストライダーの照準操作に入るまで進める。
func enter_ghost_aiming() -> bool:
	gs._set_player_hp(2, 1)
	gs.player2_x = helper.door(gs, false)
	gs.resolve_collision(false, true)
	var reached := false
	for i in range(2400):
		await frames(1)
		if ghost.phase == ghost.Phase.AIMING:
			reached = true
			break
	if not reached:
		push_error("HUD_DIEGETIC_MOCK ghost aiming not reached")
		get_tree().quit(1)
		return false
	ghost.set("_combo", COMBO_SHOWN)
	await frames(40)
	return true

func shoot_all(tag: String) -> void:
	hide_hud = false
	clear_mock()
	await frames(4)
	await capture("current_" + tag)
	hide_hud = true
	for option in OPTIONS:
		clear_mock()
		camera = get_viewport().get_camera_3d()
		call("build_" + option)
		await frames(6)
		await capture(option + "_" + tag)

func _process(_delta: float) -> void:
	if health == null:
		return
	health.visible = health.visible and not hide_hud
	var layer := ghost.get("_hud_layer") as CanvasLayer
	if layer != null:
		layer.visible = not hide_hud
	for follow in followers:
		follow.call()

# --- 案A: 背中のゼッケン（正解数）＋こしのハートベルト（HP） ---

func build_a_back() -> void:
	for i in [1, 2]:
		if alive(i):
			back_kit(parts_of(i), i, false)
		else:
			back_kit(rider_parts(), i, true)
	if ghost_active():
		ghost_common(true)

func back_kit(parts: Dictionary, i: int, as_ghost: bool) -> void:
	var torso := parts.get("upper_torso") as Node3D
	if torso == null:
		return
	var side := camera_side_z(torso)
	var bib := Node3D.new()
	bib.position = Vector3(0.0, -0.01, 0.226 * side)
	bib.rotation.y = 0.0 if side > 0.0 else PI
	track(bib, torso)
	# ゼッケン 1 枚に正解数（上）と HP のハート（下）をまとめる。腕振りやこしに隠れないよう、むねの背中いっぱいに貼る。
	var cloth := glow_material(Color(0.78, 0.97, 1.0, 0.6), 0.8) if as_ghost else plain_material(BIB)
	bib.add_child(box(Vector3(0.66, 0.48, 0.012), cloth))
	var edge := box(Vector3(0.66, 0.035, 0.016), glow_material(GHOST_COLOR if as_ghost else color_of(i), 0.25))
	edge.position.y = 0.222
	bib.add_child(edge)
	var number := label(str(score_of(i)), 200, 0.0017, NAVY)
	number.position = Vector3(0.0, 0.06, 0.01)
	bib.add_child(number)
	if as_ghost:
		return
	var row := Node3D.new()
	row.position = Vector3(0.0, -0.15, 0.012)
	bib.add_child(row)
	heart_row(row, i, gs.get_player_hp(i), 0.088, 0.205, 0.02, 0.25)

# --- 案B: 頭上に浮かぶハートと数字 ---

func build_b_overhead() -> void:
	for i in [1, 2]:
		# 脱落した側は騎手が遠く小さいので、正解数はサメの横の HAUNT 表示にまとめる（ghost_common）。
		if not alive(i):
			continue
		var mount := parts_of(i).get("hat_mount") as Node3D
		if mount == null:
			continue
		var root := Node3D.new()
		track(root, world)
		var number := label(str(score_of(i)), 160, 0.003, color_of(i), 30)
		number.position = Vector3(0.36, 0.02, 0.0)
		root.add_child(number)
		var row := Node3D.new()
		row.position = Vector3(-0.3, 0.0, 0.0)
		root.add_child(row)
		heart_row(row, i, gs.get_player_hp(i), 0.11, 0.27, 0.04, 1.8)
		followers.append(func() -> void:
			if is_instance_valid(mount) and is_instance_valid(root):
				root.global_transform = Transform3D(camera.global_basis, mount.global_position + Vector3(0.0, 0.62, 0.0)))
	if ghost_active():
		ghost_common(true)

# --- 案C: コース脇の電光掲示板 ---

func remember_led_sides() -> void:
	for i in [1, 2]:
		var torso := parts_of(i).get("upper_torso") as Node3D
		if torso != null:
			led_side[i] = 1.0 if torso.global_position.x >= 0.0 else -1.0
	if led_side[1] == led_side[2]:
		led_side[2] = -led_side[1]

func build_c_led() -> void:
	for i in [1, 2]:
		led_board(i)
	if ghost_active():
		ghost_common()

func led_board(i: int) -> void:
	var s: float = led_side[i]
	var length := 9.0
	var height := 1.3
	var root := Node3D.new()
	track(root, world)
	root.global_position = Vector3(s * 11.8, StageConstants.FLOOR_TOP_Y + height * 0.5 + 0.12, camera.global_position.z + 14.0 + length * 0.5)
	root.rotation.y = -s * PI * 0.5
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1800, 260)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var face := LedFace.new()
	face.font = FONT
	face.player_index = i
	face.score = score_of(i)
	face.hp = gs.get_player_hp(i)
	face.as_ghost = not alive(i)
	face.combo = COMBO_SHOWN
	face.tint = GHOST_COLOR if face.as_ghost else color_of(i)
	face.points = _heart_points
	# 画面左の板は手前→奥が左→右になるので並びを左右反転し、どちらの板も P バッジを内側（奥）、数字を外側（手前）にそろえる。
	face.mirrored = s > 0.0
	face.size = Vector2(viewport.size)
	viewport.add_child(face)
	var housing := box(Vector3(length + 0.24, height + 0.24, 0.18), plain_material(PLATE, 0.5))
	housing.position.z = -0.1
	root.add_child(housing)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(length, height)
	screen.mesh = quad
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = LED_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("board", viewport.get_texture())
	screen.material_override = material
	root.add_child(screen)

class LedFace extends Control:
	var font: Font
	var player_index := 1
	var score := 0
	var hp := 3
	var as_ghost := false
	var combo := 0
	var tint := Color.WHITE
	var points := PackedVector2Array()
	var mirrored := false

	func _draw() -> void:
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.02))
		# 左から [P バッジ][ハート or GHOST][数字 正解][×コンボ]。mirrored は [数字 正解][×コンボ][ハート or GHOST][P バッジ]。
		var badge_x := 1510.0 if mirrored else 60.0
		var hearts_x := 900.0 if mirrored else 430.0
		var number_x := 60.0 if mirrored else 940.0
		var combo_x := 560.0 if mirrored else 1440.0
		draw_rect(Rect2(badge_x, 40.0, 230.0, h - 80.0), tint)
		draw_string(font, Vector2(badge_x, h * 0.5 + 55.0), "P%d" % player_index, HORIZONTAL_ALIGNMENT_CENTER, 230.0, 150, Color(0.02, 0.03, 0.06))
		if as_ghost:
			draw_string(font, Vector2(hearts_x - 90.0, h * 0.5 + 45.0), "GHOST", HORIZONTAL_ALIGNMENT_LEFT, -1, 130, tint)
			draw_string(font, Vector2(combo_x, h * 0.5 + 45.0), "×%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 130, PERFECT_COLOR)
		else:
			for slot in range(3):
				_draw_heart(Vector2(hearts_x + slot * 190.0, h * 0.5 + 6.0), 78.0, tint if slot < hp else Color(0.16, 0.18, 0.22))
		draw_string(font, Vector2(number_x, h * 0.5 + 76.0), str(score), HORIZONTAL_ALIGNMENT_RIGHT, 250.0, 210, Color.WHITE)
		draw_string(font, Vector2(number_x + 270.0, h * 0.5 + 76.0), "正解", HORIZONTAL_ALIGNMENT_LEFT, -1, 100, Color(0.8, 0.85, 0.9))

	func _draw_heart(center: Vector2, radius: float, color: Color) -> void:
		var shape := PackedVector2Array()
		for p in points:
			shape.append(center + Vector2(p.x, -p.y) * radius)
		draw_colored_polygon(shape, color)

# --- 案D: 足元のリング（HP）と床の数字 ---

func build_d_floor() -> void:
	for i in [1, 2]:
		if alive(i):
			floor_kit(i)
	if not ghost_active():
		return
	ghost_common()
	# 脱落した側の正解数は、ゴーストの床の分身である照準リングの横に描く。
	var dead := 1 if not gs.p1_alive else 2
	var survivor_pelvis := parts_of(3 - dead).get("pelvis") as Node3D
	var ring := ghost.get("_aim_ring") as Node3D
	var number := floor_label(str(score_of(dead)), GHOST_COLOR)
	track(number, world)
	followers.append(func() -> void:
		if is_instance_valid(ring) and is_instance_valid(number) and is_instance_valid(survivor_pelvis):
			# 生存側の数字は外側にあるので、ゴーストの数字はリングの内側に描いて重ならないようにする。
			var survivor_out := 1.0 if survivor_pelvis.global_position.x >= 0.0 else -1.0
			number.global_position = Vector3(ring.global_position.x - survivor_out * 2.2, StageConstants.FLOOR_TOP_Y + 0.03, ring.global_position.z))

func floor_kit(i: int, show_number := true) -> void:
	var pelvis := parts_of(i).get("pelvis") as Node3D
	if pelvis == null:
		return
	var root := Node3D.new()
	track(root, world)
	followers.append(func() -> void:
		if is_instance_valid(pelvis) and is_instance_valid(root):
			root.global_position = Vector3(pelvis.global_position.x, StageConstants.FLOOR_TOP_Y + 0.03, pelvis.global_position.z))
	var hp := gs.get_player_hp(i)
	var centers := [105.0, 0.0, -105.0]
	for slot in range(3):
		var segment := MeshInstance3D.new()
		segment.mesh = arc_mesh(0.78, 1.0, deg_to_rad(centers[slot] - 45.0), deg_to_rad(centers[slot] + 45.0))
		segment.material_override = glow_material(color_of(i), 1.6, true) if slot < hp else glow_material(Color(0.1, 0.12, 0.16, 0.55), 0.0, true)
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(segment)
	if not show_number:
		return
	var number := floor_label(str(score_of(i)), color_of(i))
	root.add_child(number)
	var out := 1.0 if pelvis.global_position.x >= 0.0 else -1.0
	number.position = Vector3(out * 1.6, 0.0, 0.15)

func floor_label(text: String, color: Color) -> Label3D:
	var l := label(text, 220, 0.004, color, 26)
	# 床に寝かせ、カメラ（-Z 側）から正しく読める向きにする。
	l.basis = Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0))
	l.double_sided = false
	return l

# --- ゴースト共通（決定済み）: 照準リングのチャージ弧と、サメの横の HAUNT コンボ ---

func ghost_active() -> bool:
	return ghost.phase in [ghost.Phase.AIMING, ghost.Phase.WINDUP, ghost.Phase.CHARGING, ghost.Phase.COOLDOWN]

## with_score: 脱落した側の正解数も、サメの横の霊火表示に並べる（案A・案B）。
func ghost_common(with_score := false, charge := CHARGE_SHOWN) -> void:
	ring_gauge(charge)
	haunt_label(with_score)

## 照準リングの外輪をそのままチャージゲージにする想定。画面の上（奥）から時計回りに満ち、PERFECT 帯は外側の金の弧。
func ring_gauge(charge: float) -> void:
	var ring := ghost.get("_aim_ring") as Node3D
	var outer := ghost.get("_aim_outer_ring") as Node3D
	var gauge := Node3D.new()
	track(gauge, world)
	var start := PI
	add_arc(gauge, 1.2, 1.42, start, start + TAU, glow_material(Color(0.08, 0.12, 0.18, 0.55), 0.0, true))
	if charge > 0.0:
		add_arc(gauge, 1.2, 1.42, start, start + TAU * charge, glow_material(GHOST_COLOR, 2.4, true), 0.004)
	add_arc(gauge, 1.47, 1.6, start + TAU * 0.72, start + TAU * 0.94, glow_material(PERFECT_COLOR, 2.4, true), 0.006)
	followers.append(func() -> void:
		if is_instance_valid(outer):
			outer.visible = false
		if is_instance_valid(ring) and is_instance_valid(gauge):
			gauge.global_position = Vector3(ring.global_position.x, StageConstants.FLOOR_TOP_Y + 0.045, ring.global_position.z))

func haunt_label(with_score := false) -> void:
	var shark := ghost.get("_shark") as Node3D
	var haunt := Node3D.new()
	track(haunt, world)
	var stack_x := 0.0
	if with_score:
		var dead := 1 if not gs.p1_alive else 2
		var number := label(str(score_of(dead)), 170, 0.009, GHOST_COLOR, 30)
		number.outline_modulate = Color(0.0, 0.1, 0.2, 0.9)
		number.position = Vector3(-0.95, 0.12, 0.0)
		haunt.add_child(number)
		var unit := label("正解", 60, 0.009, Color(0.8, 0.95, 1.0), 18)
		unit.outline_modulate = Color(0.0, 0.1, 0.2, 0.9)
		unit.position = Vector3(-0.95, -0.82, 0.0)
		haunt.add_child(unit)
		stack_x = 0.75
	var title := label("HAUNT", 70, 0.009, GHOST_COLOR, 20)
	title.position = Vector3(stack_x, 0.62, 0.0)
	title.outline_modulate = Color(0.0, 0.1, 0.2, 0.9)
	haunt.add_child(title)
	var combo := label("×%d" % COMBO_SHOWN, 130, 0.009, Color(0.85, 1.0, 1.0), 28)
	combo.outline_modulate = Color(0.0, 0.35, 0.55, 0.85)
	combo.position = Vector3(stack_x, -0.15, 0.0)
	haunt.add_child(combo)
	followers.append(func() -> void:
		if is_instance_valid(shark) and is_instance_valid(haunt):
			haunt.global_transform = Transform3D(camera.global_basis, shark.global_position + Vector3(0.0, 3.0, 0.0)))

func add_arc(parent: Node3D, r0: float, r1: float, a0: float, a1: float, material: Material, lift := 0.0) -> void:
	var arc := MeshInstance3D.new()
	arc.mesh = arc_mesh(r0, r1, a0, a1)
	arc.material_override = material
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc.position.y = lift
	parent.add_child(arc)

## XZ 平面の扇形の帯。角度 0 がカメラ側（-Z）、正の向きが +X（画面の左）。
func arc_mesh(r0: float, r1: float, a0: float, a1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := maxi(4, int(absf(a1 - a0) / deg_to_rad(4.0)))
	for k in range(steps):
		var t0 := lerpf(a0, a1, float(k) / steps)
		var t1 := lerpf(a0, a1, float(k + 1) / steps)
		var d0 := Vector3(sin(t0), 0.0, -cos(t0))
		var d1 := Vector3(sin(t1), 0.0, -cos(t1))
		for v in [d0 * r0, d0 * r1, d1 * r1, d0 * r0, d1 * r1, d1 * r0]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()

# --- 共通の部品 ---

func heart_row(parent: Node3D, i: int, hp: int, radius: float, spacing: float, depth: float, energy := 1.4) -> void:
	var mesh := heart_mesh(radius, depth)
	for slot in range(3):
		var heart := MeshInstance3D.new()
		heart.mesh = mesh
		heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		heart.position = Vector3((slot - 1) * spacing, 0.0, 0.0)
		heart.material_override = glow_material(color_of(i), energy) if slot < hp else glow_material(EMPTY_HEART, 0.0)
		parent.add_child(heart)

func heart_mesh(radius: float, depth: float) -> ArrayMesh:
	var pts := PackedVector2Array()
	for p in _heart_points:
		pts.append(p * radius)
	var tris := Geometry2D.triangulate_polygon(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := depth * 0.5
	for k in range(0, tris.size(), 3):
		for side in [1.0, -1.0]:
			for j in range(3):
				var p := pts[tris[k + j]]
				st.set_normal(Vector3(0.0, 0.0, side))
				st.add_vertex(Vector3(p.x, p.y, hz * side))
	for k in range(pts.size()):
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		var n := Vector3(b.y - a.y, a.x - b.x, 0.0).normalized()
		for v in [Vector3(a.x, a.y, hz), Vector3(b.x, b.y, hz), Vector3(b.x, b.y, -hz), Vector3(a.x, a.y, hz), Vector3(b.x, b.y, -hz), Vector3(a.x, a.y, -hz)]:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()

func label(text: String, font_size: int, pixel: float, color: Color, outline := 0) -> Label3D:
	var l := Label3D.new()
	l.font = FONT
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = outline
	l.outline_modulate = OUTLINE
	l.shaded = false
	return l

func box(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance

func glow_material(color: Color, energy := 1.2, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = energy > 0.0
	m.emission = Color(color.r, color.g, color.b)
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func plain_material(color: Color, roughness := 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

func camera_side_z(node: Node3D) -> float:
	var local := node.global_transform.affine_inverse() * camera.global_position
	return 1.0 if local.z >= 0.0 else -1.0

func color_of(i: int) -> Color:
	return P1_COLOR if i == 1 else P2_COLOR

func score_of(i: int) -> int:
	return gs.score if i == 1 else gs.player2_score

func alive(i: int) -> bool:
	return gs.p1_alive if i == 1 else gs.p2_alive

func parts_of(i: int) -> Dictionary:
	return player.p1_parts if i == 1 else player.p2_parts

func rider_parts() -> Dictionary:
	var rider := ghost.get("_rider") as Node3D
	if rider == null or not is_instance_valid(rider):
		return {}
	return rider.get_meta("ghost_mount_parts", {})

func track(node: Node, parent: Node) -> void:
	parent.add_child(node)
	mock_nodes.append(node)

func clear_mock() -> void:
	for node in mock_nodes:
		if is_instance_valid(node):
			node.queue_free()
	mock_nodes.clear()
	followers.clear()

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")
	print("HUD_DIEGETIC_MOCK captured " + tag)
