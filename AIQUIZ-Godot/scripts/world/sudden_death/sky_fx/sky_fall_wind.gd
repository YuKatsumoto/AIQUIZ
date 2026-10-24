class_name SkyFallWind
extends Node3D

## スカイゲートの風切り（docs/sudden_death_v2/sky_fx.md 第3章）。SkyFallScenery の子で、原点＝落ちる点。
##   画面の板：速さの線（画面のふち。shaders/sky_fx_screen.gdshader、カメラの子）
##   風の筋 ：手足と頭（track で渡した人形の部位）から後ろへ流れる白い帯。1 フレームごとに作り直す 1 つのメッシュ
##   水滴   ：2 人のまわりを上へ流れる小さな水滴の筋（shaders/sky_fx_droplet.gdshader）
## 雲は出さない（2026-10-19 ユーザー指示）。雲のかけら・雲を抜けるもやは作らない。
## 強さ wind は 0〜1.4（ふだん 1.0、ゲートが近い間 0.5、通過の瞬間 1.4。決めるのは W4）。

const SCREEN_SHADER := preload("res://shaders/sky_fx_screen.gdshader")
const STREAK_SHADER := preload("res://shaders/sky_fx_streak.gdshader")
const DROPLET_SHADER := preload("res://shaders/sky_fx_droplet.gdshader")

## 筋を出す部位（人形・アバターの parts のキー）。頭の筋は見下ろしではカメラへ向かって点に縮むので出さない。
const STREAK_PARTS := ["l_hand", "r_hand", "l_foot", "r_foot"]
const STREAK_POINTS := 11
## 筋の点の間隔（秒）と、空気が流れて筋が伸びる速さ（m/秒、強さ 1 のとき）。
const STREAK_STEP := 0.028
const STREAK_SPEED := 5.0
const STREAK_WIDTH := 0.16
## 水滴の範囲（落ちる点から）。
const BIT_TOP := 14.0
const BIT_BOTTOM := -30.0
const BIT_RADIUS_MIN := 2.5
const BIT_RADIUS_MAX := 24.0

var quality := ""
var low := false
var camera: Camera3D = null
var wind := 1.0

var _screen: MeshInstance3D = null
var _screen_mat: ShaderMaterial = null
var _streak_node: MeshInstance3D = null
var _streak_mesh: ImmediateMesh = null
var _streak_mat: ShaderMaterial = null
var _bits_node: MultiMeshInstance3D = null
var _bits_mat: ShaderMaterial = null
var _bit_pos := PackedVector3Array()
var _bit_speed := PackedFloat32Array()
var _bit_size := PackedFloat32Array()
## player -> {"parts": Dictionary, "history": {part: Array[Vector3]}, "clock": float}
var _bodies := {}
var _time := 0.0
var _streak_verts := 0


func build(p_quality: String) -> void:
	for child: Node in get_children():
		child.queue_free()
	quality = GraphicsQuality.normalize(p_quality)
	low = quality == GraphicsQuality.LOW
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = SCREEN_SHADER
	_screen_mat.render_priority = 120
	_screen = MeshInstance3D.new()
	_screen.name = "SkyFxScreen"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_screen.mesh = quad
	_screen.material_override = _screen_mat
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_screen.extra_cull_margin = 16384.0
	_screen.visible = false
	add_child(_screen)

	_streak_mesh = ImmediateMesh.new()
	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = STREAK_SHADER
	# わずかに見えるくらい（2026-10-19 ユーザー指示）
	_streak_mat.set_shader_parameter("opacity", 0.16)
	_streak_mat.set_shader_parameter("additive", true)
	_streak_mat.render_priority = 10
	_streak_node = MeshInstance3D.new()
	_streak_node.name = "WindStreaks"
	_streak_node.mesh = _streak_mesh
	_streak_node.material_override = _streak_mat
	_streak_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streak_node.top_level = true
	_streak_node.extra_cull_margin = 4096.0
	add_child(_streak_node)

	var count := 20 if low else 40
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	_bit_pos.resize(count)
	_bit_speed.resize(count)
	_bit_size.resize(count)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var bq := QuadMesh.new()
	bq.size = Vector2(1.0, 1.0)
	mm.mesh = bq
	mm.instance_count = count
	_bits_mat = ShaderMaterial.new()
	_bits_mat.shader = DROPLET_SHADER
	_bits_mat.render_priority = 9
	_bits_node = MultiMeshInstance3D.new()
	_bits_node.name = "WindDroplets"
	_bits_node.multimesh = mm
	_bits_node.material_override = _bits_mat
	_bits_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bits_node.custom_aabb = AABB(Vector3(-40, -60, -40), Vector3(80, 100, 80))
	add_child(_bits_node)
	for i in range(count):
		var a := rng.randf_range(0.0, TAU)
		var d := lerpf(BIT_RADIUS_MIN, BIT_RADIUS_MAX, sqrt(rng.randf()))
		_bit_pos[i] = Vector3(cos(a) * d, rng.randf_range(BIT_BOTTOM, BIT_TOP), sin(a) * d)
		_bit_speed[i] = rng.randf_range(1.1, 1.6)
		_bit_size[i] = rng.randf_range(0.05, 0.11)
		mm.set_instance_custom_data(i, Color(0.0, 0.0, rng.randf(), rng.randf_range(2.0, 5.0)))


func set_camera(p_camera: Camera3D) -> void:
	camera = p_camera
	if _screen == null:
		return
	if _screen.get_parent() != null:
		_screen.get_parent().remove_child(_screen)
	if camera != null:
		camera.add_child(_screen)
		_screen.position = Vector3(0.0, 0.0, -0.5)
		_screen.visible = true
	else:
		add_child(_screen)
		_screen.visible = false


## 手足と頭から風の筋を出す人形（build_player_skeleton の parts、StagingPuppet.parts() も同じ形）。
func track(player: int, parts: Dictionary) -> void:
	var history := {}
	for key: String in STREAK_PARTS:
		if parts.get(key) is Node3D:
			history[key] = []
	_bodies[player] = {"parts": parts, "history": history, "clock": 0.0}


func untrack(player: int) -> void:
	_bodies.erase(player)


func advance(distance: float, delta: float) -> void:
	_time += delta
	if _screen_mat != null:
		_screen_mat.set_shader_parameter("wind", wind)
	_update_bits(distance, delta)
	_update_streaks(delta)


func _update_bits(distance: float, _delta: float) -> void:
	var mm := _bits_node.multimesh
	var span := BIT_TOP - BIT_BOTTOM
	var amount := clampf(wind / 1.4, 0.0, 1.0)
	_bits_mat.set_shader_parameter("opacity", 0.25 + 0.2 * amount)
	_bits_mat.set_shader_parameter("stretch", 0.6 + 0.8 * amount)
	var count := _bit_pos.size()
	var cam_local := to_local(camera.global_position) if camera != null else Vector3(0.0, 8.0, 0.0)
	for i in range(count):
		var p := _bit_pos[i] + Vector3(0.0, distance * _bit_speed[i], 0.0)
		if p.y > BIT_TOP:
			p.y -= span
		_bit_pos[i] = p
		var shown := 1.0 if float(i) / count < 0.3 + 0.7 * amount else 0.0
		var a := smoothstep(BIT_BOTTOM, BIT_BOTTOM + 8.0, p.y) * (1.0 - smoothstep(BIT_TOP - 6.0, BIT_TOP, p.y)) * shown
		# カメラに近すぎる粒は大きく白く画面をふさぐので薄く
		a *= smoothstep(1.5, 5.0, p.distance_to(cam_local))
		var s := _bit_size[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), p))
		var cd := mm.get_instance_custom_data(i)
		cd.g = a * 0.7
		mm.set_instance_custom_data(i, cd)


func _update_streaks(delta: float) -> void:
	_streak_mesh.clear_surfaces()
	_streak_verts = 0
	if _bodies.is_empty() or wind <= 0.02:
		return
	var cam_pos := camera.global_position if camera != null else global_position + Vector3(0.0, 8.0, 4.0)
	var strength := clampf(wind, 0.0, 1.4)
	var opened := false
	for player: int in _bodies:
		var body: Dictionary = _bodies[player]
		var parts: Dictionary = body.parts
		var pelvis := parts.get("pelvis") as Node3D
		if pelvis == null or not is_instance_valid(pelvis) or not pelvis.is_visible_in_tree():
			continue
		var center := (parts.get("spine") as Node3D).global_position if parts.get("spine") is Node3D else pelvis.global_position
		# 体の前（頭の向き）。筋は上（空気の流れ）と後ろへ流す
		var head_dir := Vector3.FORWARD
		if parts.get("head") is Node3D:
			head_dir = ((parts.head as Node3D).global_position - center)
			head_dir.y = 0.0
			head_dir = head_dir.normalized() if head_dir.length() > 0.05 else Vector3.FORWARD
		body.clock = float(body.clock) + delta
		var record := float(body.clock) >= STREAK_STEP
		if record:
			body.clock = fmod(float(body.clock), STREAK_STEP)
		var k := 0
		for key: String in body.history:
			var node := parts.get(key) as Node3D
			if node == null or not is_instance_valid(node):
				continue
			var hist: Array = body.history[key]
			var here := node.global_position
			if key.ends_with("hand"):
				here = node.global_transform * Vector3(0.0, -0.12, 0.0)
			if record or hist.is_empty():
				hist.push_front(here)
				if hist.size() > STREAK_POINTS:
					hist.resize(STREAK_POINTS)
			else:
				hist[0] = here
			if hist.size() < 3:
				continue
			var outward := here - center
			outward.y = 0.0
			outward = outward.normalized() if outward.length() > 0.05 else Vector3.ZERO
			# 流れ：体の外へ・後ろへ・少し上へ（見下ろしで画面の外へ広がる）。先へ行くほど外へ曲がる
			var flow := (Vector3.UP * 0.25 - head_dir * 0.5 + outward * 0.8).normalized()
			var pts: Array[Vector3] = []
			for j in range(hist.size()):
				var age := float(j) * STREAK_STEP
				var reach := STREAK_SPEED * age * (0.55 + 0.45 * strength)
				var curl := outward * reach * reach * 0.12 + Vector3.UP * sin(_time * 6.0 + float(k) * 1.7 + float(j) * 0.35) * 0.012 * float(j)
				pts.append((hist[j] as Vector3) + flow * reach + curl)
			if not opened:
				_streak_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				opened = true
			var width := STREAK_WIDTH * (0.7 + 0.3 * strength)
			_emit_ribbon(pts, width, cam_pos, float(player * 7 + k) * 0.13, clampf(strength / 1.0, 0.0, 1.0))
			k += 1
	if opened:
		_streak_mesh.surface_end()


func _emit_ribbon(pts: Array[Vector3], width: float, cam_pos: Vector3, seed: float, alpha: float) -> void:
	var n := pts.size()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	left.resize(n)
	right.resize(n)
	for i in range(n):
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var along := (b - a).normalized()
		var to_cam := (cam_pos - pts[i]).normalized()
		var side := along.cross(to_cam)
		side = side.normalized() if side.length() > 1e-4 else Vector3.RIGHT
		var t := float(i) / float(n - 1)
		var w := width * (0.15 + 0.85 * sin(PI * pow(t, 0.6))) * (1.0 + t * 0.6)
		left[i] = pts[i] - side * w * 0.5
		right[i] = pts[i] + side * w * 0.5
	for i in range(n - 1):
		var u0 := float(i) / float(n - 1)
		var u1 := float(i + 1) / float(n - 1)
		var col := Color(seed, 0.0, 0.0, alpha)
		for v: Array in [[left[i], u0, 0.0], [right[i], u0, 1.0], [right[i + 1], u1, 1.0], [left[i], u0, 0.0], [right[i + 1], u1, 1.0], [left[i + 1], u1, 0.0]]:
			_streak_mesh.surface_set_color(col)
			_streak_mesh.surface_set_uv(Vector2(float(v[1]), float(v[2])))
			_streak_mesh.surface_add_vertex(v[0] as Vector3)
			_streak_verts += 1


func stats() -> Dictionary:
	var draws := 0
	for node: GeometryInstance3D in [_screen, _bits_node]:
		if node != null and node.visible:
			draws += 1
	if _streak_verts > 0:
		draws += 1
	var trails := 0
	for player: int in _bodies:
		trails += (_bodies[player].history as Dictionary).size()
	return {"draws": draws, "bits": _bit_pos.size(), "trails": trails, "trail_points": STREAK_POINTS, "trail_vertices": _streak_verts}
