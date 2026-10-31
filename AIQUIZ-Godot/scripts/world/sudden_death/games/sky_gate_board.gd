class_name SkyGateBoard
extends Node3D

## スカイゲートの問題のボード（docs/sudden_death_v2/skygate_build_plan.md 4.6節、sky_gate.md）。
## 素材は assets/sudden_death/sky_gate/gate_board.glb（17 × 12.2 m の横向きの板・濃紺の枠・問題文の看板（ボードと同じ幅 17 m）・2×2 の紙のパネル・
## 四隅のドローン 4 機と吊りケーブル）。文字は素材に入れず、ここで Label3D で書く。
##
## 原点＝ボードの中心 × 紙の面。+X が右、−Z が奥（問題文の帯の側）、+Y が上。ボードの座標（ルールの m）は
## x＝右、y＝奥なので、ローカルでは (x, 0, −y)。ROUND 3 以降はこのノードの scale で縮める（size() と panel_center() は縮めた値）。
## パネルの番号：0＝奥の左、1＝奥の右、2＝手前の左、3＝手前の右（ルールの選択肢の番号と同じ）。
## 選手の番号：1＝P1（オレンジ）、2＝P2（青）。
##
## 効果（紙吹雪・爆発・人形のブロック）は子の effects（SkyGateEffects）が出す。advance(delta) がドローン・パネル・効果を動かす。

const GLB := "res://assets/sudden_death/sky_gate/gate_board.glb"
const LAYOUT := "res://assets/sudden_death/sky_gate/gate_board_layout.json"
const PAPER_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/gate_paper.gdshader")
const HIGHLIGHT_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/gate_highlight.gdshader")
const FONT_SOURCE := preload("res://resources/fonts/NotoSansJP-Bold.otf")

## ボードの大きさ（m、縮める前）
const BOARD_SIZE := Vector2(17.0, 12.2)
const PANEL_COUNT := 4
## パネル（ボードの座標：x＝右、y＝奥、m、縮める前）。build を呼ばなくても使える（ルールの判定用）。
## 値は gate_board_layout.json（build_gate_board.py が書く）と同じ。
## 2026-10-19 夜：ユーザーの指示で選択肢を大きくした（6.39 × 3.34 → 7.89 × 4.44、ボードの横幅を看板と同じ 17 m に）。
const PANEL_SIZE := Vector2(7.89, 4.44)
const PANEL_CENTERS: Array[Vector2] = [Vector2(-4.095, 1.32), Vector2(4.095, 1.32), Vector2(-4.095, -3.42), Vector2(4.095, -3.42)]
## 問題文の看板 QuestionSign の白い面（ボードの座標の中心・大きさ・上面の高さ）。ボードと同じ幅の 17 × 6 m の看板で、
## ボードの奥の辺から奥へはみ出す（看板とパネルで 1 つの四角。全体は約 17 × 15.8 m）。看板の奥の 2 隅もドローンが吊る。
const SIGN_CENTER := Vector2(0.0, 6.74)
const SIGN_SIZE := Vector2(16.28, 5.28)
const SIGN_OUTER := Vector2(17.0, 6.0)
const SIGN_TOP := 0.388
## 前の版の帯の名前（呼ぶ側の互換のため。今は看板と同じ値）。
const STRIP_CENTER := SIGN_CENTER
const STRIP_SIZE := SIGN_SIZE
## 吊るドローンの数（0・1＝看板の手前の角、2・3＝ボードの手前の角、4・5＝看板の奥の角）。
const DRONE_COUNT := 6
## パネルの色（sRGB）：ミント・水色・レモン・ピンク
const PAPER_COLORS: Array[Color] = [Color("#8FE3B5"), Color("#8CCDF5"), Color("#FBE878"), Color("#F9A9C8")]
## 光る枠の色（P1 オレンジ、P2 青）
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.52, 0.1), Color(0.16, 0.56, 1.0)]
const TEXT_COLOR := Color("#1B1E2B")
## 紙の穴：正解（人が通る大きさ）とまちがい（吹き飛ぶ）。半径 m と開く時間 s
const BURST_RADIUS := 1.2
## このへこみ（m）より深い間は、そのパネルの選択肢の文字を隠す。
const DENT_HIDE_LABEL := 0.12
const BURST_OPEN := 0.14
const BOOM_RADIUS := 2.5
const BOOM_OPEN := 0.09
const ROTOR_SPEED := 30.0
## 光る枠の帯（外のふちからの距離と幅、m）。2 人が同じパネルなら P1 が外、P2 が内
const HIGHLIGHT_INSET := 0.04
const HIGHLIGHT_WIDTH := 0.34
## これより遠いと描かない（m）：小さい部品と文字。文字は列の引きの画（G4_Column）で 4 枚目まで読めるよう遠くまで（2026-10-25：260 → 420 m）
const SMALL_PART_RANGE := 110.0
const CABLE_RANGE := 170.0
const LABEL_RANGE := 420.0

static var _font: FontFile = null

var quality := "balanced"
## 効果（紙吹雪・爆発・人形のブロック）。ボードの子なので、ボードと一緒に動く。W4 は player_burst もここで呼べる
var effects: SkyGateEffects = null
var question_label: Label3D = null
var choice_labels: Array[Label3D] = []
var rotor_speed := ROTOR_SPEED

var _rig: Node3D = null
var _model: Node3D = null
var _paper: Array[ShaderMaterial] = []
var _strip_material: StandardMaterial3D = null
var _highlight_nodes: Array = []      # [panel] → [外の帯, 内の帯]
var _highlight_on: Array = []         # [panel] → [P1, P2]
var _highlight_materials: Array[ShaderMaterial] = []
var _glow := PackedFloat32Array()
var _holes: Array[Dictionary] = []
var _flash_at := PackedFloat32Array()
var _drones: Array[Node3D] = []
var _drone_rest: Array[Transform3D] = []
var _rotors: Array[Node3D] = []
var _rotor_phase := PackedFloat32Array()
var _cables: Array[Node3D] = []
var _cable_attach: Array[Vector3] = []
var _cable_length := PackedFloat32Array()
var _drone_hook_y := -0.42
var _time := 0.0
var _shake_at := -INF
var _strip_flash_at := -INF
var _last_global := Vector3.INF
var _lean := Vector2.ZERO
var _hole_count := 0
## パネルごとのへこみ [P1, P2]（シェーダーに渡した値。文字を沈めるのに使う）。
var _dents: Array = []
## 消えていく割合（set_fade）と、消す前の材質の透明の設定。
var _fade := 1.0
var _body_material: StandardMaterial3D = null
var _disc_material: StandardMaterial3D = null
var _material_alpha := {}
var _material_transparency := {}


func build(quality_name: String = "") -> bool:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	quality = GraphicsQuality.normalize(quality_name if quality_name != "" else String(GameManager.graphics_quality))
	var scene := load(GLB) as PackedScene
	if scene == null:
		push_warning("[SkyGate] %s not found" % GLB)
		return false
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_model = scene.instantiate() as Node3D
	_model.name = "GateBoardModel"
	_rig.add_child(_model)
	_read_layout()
	_setup_materials()
	_collect_moving_parts()
	_build_labels()
	_build_highlights()
	effects = SkyGateEffects.new()
	effects.name = "Effects"
	effects.seed_base = 20261018 + absi(hash(String(name))) % 100000
	add_child(effects)
	effects.build(quality)
	_holes.clear()
	_dents.clear()
	_glow.resize(PANEL_COUNT)
	_flash_at.resize(PANEL_COUNT)
	for i in range(PANEL_COUNT):
		_holes.append({})
		_dents.append([Vector4.ZERO, Vector4.ZERO])
		_glow[i] = 0.0
		_flash_at[i] = -INF
	_time = 0.0
	_last_global = Vector3.INF
	_pose_drones()
	return true


## 問題文と 4 つの選択肢を書く（choices は 0〜3 の順。Array[String] でも Array でもよい）。帯が一瞬光る。
func set_question(text: String, choices: Array) -> void:
	if question_label == null:
		return
	_fit_label(question_label, text, Vector2(SIGN_SIZE.x - 1.0, SIGN_SIZE.y - 0.7), 0.022)
	for i in range(PANEL_COUNT):
		var choice := String(choices[i]) if i < choices.size() else ""
		# 大きくしたパネルに合わせて文字も大きく（上限 1 px＝0.0155 m、文字の高さ約 2 m）
		_fit_label(choice_labels[i], choice, Vector2(PANEL_SIZE.x - 0.9, PANEL_SIZE.y - 0.8), 0.0155)
		choice_labels[i].visible = _holes.is_empty() or _holes[i].is_empty()
	_strip_flash_at = _time


## 真下のパネルを自分の色の光る枠で光らせる（player は 1＝P1、2＝P2）。2 人が同じパネルなら 2 色（P1 が外）。
func set_highlight(panel: int, player: int, on: bool) -> void:
	if not _valid_panel(panel) or _highlight_on.is_empty():
		return
	if player != 1 and player != 2:
		push_warning("[SkyGate] set_highlight: player は 1 か 2（%d）" % player)
		return
	_highlight_on[panel][player - 1] = on
	_update_highlight(panel)


## 正解：紙が破れて紙吹雪と光の輪。at（ワールド）を渡すと、そこに穴を開ける（パネルの中に収める）。省くとパネルの中心。
func burst(panel: int, at: Vector3 = Vector3.INF) -> void:
	if not _valid_panel(panel) or effects == null:
		return
	var center := _hole_center(panel, at)
	var seed := _open_hole(panel, center, BURST_RADIUS, BURST_OPEN)
	effects.flaps(panel, center + Vector3(0.0, -0.02, 0.0), BURST_RADIUS, BURST_OPEN, seed, PAPER_COLORS[panel].lightened(0.08),
			Vector2(deg_to_rad(80.0), deg_to_rad(98.0)), _panel_rect_local(panel))
	effects.burst_fx(center, PAPER_COLORS[panel])


## 時間切れで体が当たったところのへこみ（skygate_impact.md）。slot は 0＝P1・1＝P2（同じパネルに 2 人でも別々にへこむ）。
## at はワールドの点（紙の上の体の真下）、depth はワールドの m（下が +、負はふくらむ）。0 で平らに戻る。
func set_dent(panel: int, slot: int, at: Vector3, depth: float, radius := SkyGateImpact.DENT_RADIUS) -> void:
	if not _valid_panel(panel):
		return
	var key := "dent_a" if slot == 0 else "dent_b"
	var b := global_transform.basis
	var sy := maxf(b.y.length(), 0.01)
	var sx := maxf(b.x.length(), 0.01)
	var c: Vector2 = PANEL_CENTERS[panel]
	var p := to_local(at)
	var uv := Vector2((p.x - c.x) / PANEL_SIZE.x + 0.5, (p.z + c.y) / PANEL_SIZE.y + 0.5)
	var value := Vector4(uv.x, uv.y, depth / sy, radius / sx)
	_paper[panel].set_shader_parameter(key, value)
	_dents[panel][slot] = value
	_follow_dent(panel)


## へこみを全部平らに戻す。
func clear_dents() -> void:
	for i in range(_paper.size()):
		for key: String in ["dent_a", "dent_b"]:
			_paper[i].set_shader_parameter(key, Vector4(0.5, 0.5, 0.0, SkyGateImpact.DENT_RADIUS))
		_dents[i] = [Vector4.ZERO, Vector4.ZERO]
		_follow_dent(i)
		_paper[i].set_shader_parameter("strain", 0.0)


## まちがいのパネルが体を受け止めて赤く張りつめる（0〜1）。破れない。
func set_strain(panel: int, value: float) -> void:
	if _valid_panel(panel):
		_paper[panel].set_shader_parameter("strain", clampf(value, 0.0, 1.0))


## まちがい：破れずに体をはね返した瞬間。紙がひらめいて、白い輪と小さな星が出る。ボードが少しゆれる。at はワールド。
func bounce(panel: int, at: Vector3 = Vector3.INF) -> void:
	if not _valid_panel(panel) or effects == null:
		return
	var center := _hole_center(panel, at)
	_flash_at[panel] = _time
	effects.ring(center + Vector3(0.0, 0.05, 0.0), 0.5, 2.6, 0.35, Color(1.0, 0.55, 0.45, 0.85))
	effects.stars(center + Vector3(0.0, 0.3, 0.0), 6, 2.4)
	_shake_at = _time


## 通りすぎたボードを消していく（ゲーム中の問題の壁の retire_after_player_pass と同じ考え）：1 より小さくなったら文字と光る枠を
## すぐ消し、枠・看板・紙・ドローンをだんだん透明に（0 で見えない）。reset() で元に戻る。
func set_fade(alpha: float) -> void:
	var a := clampf(alpha, 0.0, 1.0)
	if is_equal_approx(a, _fade):
		return
	_fade = a
	var fading := a < 0.999
	if question_label != null:
		question_label.visible = not fading
	for i in range(choice_labels.size()):
		choice_labels[i].visible = not fading and (_holes.is_empty() or _holes[i].is_empty())
	for pair: Array in _highlight_nodes:
		for mi: MeshInstance3D in pair:
			if fading:
				mi.visible = false
	for mat: StandardMaterial3D in [_body_material, _strip_material, _disc_material]:
		if mat == null:
			continue
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if fading else _material_transparency.get(mat, BaseMaterial3D.TRANSPARENCY_DISABLED)
		var c := mat.albedo_color
		c.a = a * float(_material_alpha.get(mat, 1.0))
		mat.albedo_color = c
	for paper: ShaderMaterial in _paper:
		paper.set_shader_parameter("fade", a)
	if a <= 0.001:
		visible = false


func fade() -> float:
	return _fade


## 選択肢の文字をへこみに合わせて沈める（文字は平らな板なので、文字の真ん中のへこみの深さだけ下げる）。
func _follow_dent(panel: int) -> void:
	if panel >= choice_labels.size():
		return
	var depth := 0.0
	for value: Vector4 in _dents[panel]:
		if absf(value.z) < 0.0001:
			continue
		var m := (Vector2(0.5, 0.5) - Vector2(value.x, value.y)) * PANEL_SIZE
		var one := value.z * exp(-m.length_squared() * 2.4 / maxf(value.w * value.w, 0.0001))
		# シェーダーと同じく、深い方のへこみ
		if absf(one) > absf(depth):
			depth = one
	# 枠の厚み（約 0.3 m）より深くは沈めない（横から見たとき、文字だけが枠の下へはみ出さないように）
	choice_labels[panel].position.y = 0.03 - clampf(depth, -0.3, 0.3)
	# 大きくへこんでいる間は文字を隠す（平らな文字がへこみの中に浮いて、体のまわりの黒いかたまりに見える）
	var plain := (_holes.is_empty() or _holes[panel].is_empty()) and _fade >= 0.999
	choice_labels[panel].visible = plain and absf(depth) < DENT_HIDE_LABEL


## まちがい：パネルの漫画の爆発（火の玉と白い煙・星・紙のかけら）。ボードが少しゆれる。
func boom(panel: int, at: Vector3 = Vector3.INF) -> void:
	if not _valid_panel(panel) or effects == null:
		return
	var center := _hole_center(panel, at)
	var seed := _open_hole(panel, center, BOOM_RADIUS, BOOM_OPEN)
	effects.flaps(panel, center + Vector3(0.0, -0.02, 0.0), BOOM_RADIUS, BOOM_OPEN, seed, PAPER_COLORS[panel].lightened(0.05),
			Vector2(deg_to_rad(86.0), deg_to_rad(100.0)), _panel_rect_local(panel))
	effects.boom_fx(center, PAPER_COLORS[panel])
	_shake_at = _time


## 時間を進める：ローター・ドローンの浮き沈み・ケーブル・穴・光る枠・ゆれ・効果。スローのときは小さい delta を渡す。
func advance(delta: float) -> void:
	if _model == null:
		return
	_time += delta
	if delta > 0.0:
		var gp := global_position
		if is_finite(_last_global.x):
			var v := global_transform.basis.inverse() * ((gp - _last_global) / delta)
			_lean = _lean.lerp(Vector2(v.x, v.z), 1.0 - exp(-4.0 * delta))
		_last_global = gp
	_pose_drones()
	_pose_panels(delta)
	var pulse := 0.5 + 0.5 * sin(_time * 7.0)
	for mat: ShaderMaterial in _highlight_materials:
		mat.set_shader_parameter("pulse", pulse)
	var since := _time - _shake_at
	if since >= 0.0 and since < 0.7:
		var amp := 0.14 * exp(-since * 7.0)
		_rig.position = Vector3(sin(since * 47.0), sin(since * 61.0) * 0.5, sin(since * 53.0)) * amp
	else:
		_rig.position = Vector3.ZERO
	if _strip_material != null:
		var sf := _time - _strip_flash_at
		_strip_material.emission_energy_multiplier = 0.6 * exp(-sf * 5.0) if sf >= 0.0 else 0.0
	if effects != null:
		effects.advance(delta)


## パネルの中心（ワールド）。
func panel_center(panel: int) -> Vector3:
	var p: Vector2 = PANEL_CENTERS[clampi(panel, 0, PANEL_COUNT - 1)]
	return global_transform * Vector3(p.x, 0.0, -p.y)


## ボードの大きさ（m、このノードの scale で縮めた値）。x＝横、y＝奥行き。
func size() -> Vector2:
	var b := global_transform.basis
	return BOARD_SIZE * Vector2(b.x.length(), b.z.length())


## 穴・垂れ・効果・光る枠を消して、次のゲートに使えるようにする。
func reset() -> void:
	if effects != null:
		effects.clear()
	for i in range(_holes.size()):
		_holes[i] = {}
		_paper[i].set_shader_parameter("hole_radius", 0.0)
		_paper[i].set_shader_parameter("flash", 0.0)
		_flash_at[i] = -INF
		if i < choice_labels.size():
			choice_labels[i].visible = true
		_highlight_on[i] = [false, false]
		_update_highlight(i)
	_shake_at = -INF
	if _rig != null:
		_rig.position = Vector3.ZERO
	if not _dents.is_empty():
		clear_dents()
	if _body_material != null:
		set_fade(1.0)
		for i in range(PANEL_COUNT):
			_update_highlight(i)


## ボードの座標（m、縮める前。x＝右、y＝奥）のパネルの四角。
static func panel_rect(panel: int) -> Rect2:
	var c: Vector2 = PANEL_CENTERS[clampi(panel, 0, PANEL_COUNT - 1)]
	return Rect2(c - PANEL_SIZE * 0.5, PANEL_SIZE)


## ボードの座標（m、縮める前）の点の真下（真上）のパネル。どのパネルでもなければ −1（帯・枠・外）。
static func panel_at(p: Vector2) -> int:
	for i in range(PANEL_COUNT):
		if panel_rect(i).has_point(p):
			return i
	return -1


## 問題文の看板の 4 隅（ワールド、縮めた値）。カメラが看板ごと画に入れるときに使う。
func sign_corners() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for sx: float in [-0.5, 0.5]:
		for sy: float in [-0.5, 0.5]:
			var p := SIGN_CENTER + Vector2(SIGN_OUTER.x * sx, SIGN_OUTER.y * sy)
			out.append(global_transform * Vector3(p.x, SIGN_TOP, -p.y))
	return out


## ボードの座標（m、縮める前。x＝右、y＝奥）の点のワールドの位置（紙の面の高さ）。
func board_point(p: Vector2) -> Vector3:
	return global_transform * Vector3(p.x, 0.0, -p.y)


# ---------------------------------------------------------------- 作る

func _read_layout() -> void:
	var text := FileAccess.get_file_as_string(LAYOUT)
	var layout: Variant = JSON.parse_string(text)
	if not layout is Dictionary:
		return
	_drone_hook_y = float((layout as Dictionary).get("drone_hook_y", _drone_hook_y))
	var panels: Dictionary = (layout as Dictionary).get("panels", {})
	for i in range(PANEL_COUNT):
		var info: Dictionary = panels.get("Panel_%d" % i, {})
		var c: Array = info.get("center", [])
		if c.size() == 3 and not Vector2(float(c[0]), -float(c[2])).is_equal_approx(PANEL_CENTERS[i]):
			push_warning("[SkyGate] Panel_%d の位置が gate_board_layout.json とちがう：%s" % [i, str(c)])


func _setup_materials() -> void:
	var shadows := GraphicsQuality.gameplay_shadow_enabled(quality)
	var body := StandardMaterial3D.new()
	body.resource_name = "GB_Body"
	body.vertex_color_use_as_albedo = true
	body.vertex_color_is_srgb = false
	body.roughness = 0.48
	_strip_material = StandardMaterial3D.new()
	_strip_material.resource_name = "GB_Strip"
	_strip_material.albedo_color = Color("#FAFBFC")
	_strip_material.roughness = 0.6
	_strip_material.emission_enabled = true
	_strip_material.emission = Color(1.0, 1.0, 0.95)
	_strip_material.emission_energy_multiplier = 0.0
	var disc := StandardMaterial3D.new()
	disc.resource_name = "GB_RotorBlur"
	disc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.albedo_color = Color(0.92, 0.94, 0.97, 0.18)
	disc.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_body_material = body
	_disc_material = disc
	_material_alpha = {body: 1.0, _strip_material: 1.0, disc: disc.albedo_color.a}
	_material_transparency = {body: body.transparency, _strip_material: _strip_material.transparency, disc: disc.transparency}
	_fade = 1.0
	_paper.clear()
	for i in range(PANEL_COUNT):
		var paper := ShaderMaterial.new()
		paper.shader = PAPER_SHADER
		paper.set_shader_parameter("paper_color", PAPER_COLORS[i])
		paper.set_shader_parameter("panel_size", PANEL_SIZE)
		paper.set_shader_parameter("paper_alpha", 0.9)
		_paper.append(paper)
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if n.begins_with("Panel_"):
			mi.material_override = _paper[int(n.substr(6))]
			# へこみ（頂点を最大 0.8 m ほど下げる）で見える範囲から外れて消えないように
			mi.extra_cull_margin = 1.2
		elif n == "QuestionSign" or n == "QuestionStrip":
			mi.material_override = _strip_material
		elif n.begins_with("RotorDisc_"):
			mi.material_override = disc
			mi.visibility_range_end = SMALL_PART_RANGE
		else:
			mi.material_override = body
			if n.begins_with("Rotor_"):
				mi.visibility_range_end = SMALL_PART_RANGE
			elif n.begins_with("Cable_"):
				mi.visibility_range_end = CABLE_RANGE
			elif shadows and (n == "Frame" or n.begins_with("Drone_")):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _collect_moving_parts() -> void:
	_drones.clear()
	_drone_rest.clear()
	_rotors.clear()
	_cables.clear()
	_cable_attach.clear()
	_rotor_phase = PackedFloat32Array()
	_cable_length = PackedFloat32Array()
	for i in range(DRONE_COUNT):
		var drone := _model.find_child("Drone_%d" % i, true, false) as Node3D
		var cable := _model.find_child("Cable_%d" % i, true, false) as Node3D
		if drone == null or cable == null:
			push_warning("[SkyGate] Drone_%d / Cable_%d が見つからない" % [i, i])
			continue
		_drones.append(drone)
		_drone_rest.append(drone.transform)
		for k in range(4):
			var rotor := drone.find_child("Rotor_%d_%d" % [i, k], true, false) as Node3D
			if rotor != null:
				_rotors.append(rotor)
				# となりのローターは逆に回す
				_rotor_phase.append(float(i * 4 + k) * 1.37)
		_cables.append(cable)
		_cable_attach.append(cable.position)
		var hook := drone.transform * Vector3(0.0, _drone_hook_y, 0.0)
		_cable_length.append(maxf((hook - cable.position).length(), 0.01))


func _build_labels() -> void:
	question_label = _make_label("QuestionLabel")
	question_label.position = Vector3(SIGN_CENTER.x, SIGN_TOP + 0.012, -SIGN_CENTER.y)
	_rig.add_child(question_label)
	choice_labels.clear()
	for i in range(PANEL_COUNT):
		var label := _make_label("ChoiceLabel_%d" % i)
		label.position = Vector3(PANEL_CENTERS[i].x, 0.03, -PANEL_CENTERS[i].y)
		_rig.add_child(label)
		choice_labels.append(label)


func _make_label(label_name: String) -> Label3D:
	var label := Label3D.new()
	label.name = label_name
	label.font = _label_font()
	label.font_size = 128
	label.outline_size = 0
	label.modulate = TEXT_COLOR
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.shaded = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end = LABEL_RANGE
	# 上を向けて、文字の上を奥（−Z）へ
	label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	label.text = ""
	return label


## 文字を枠（m）に収める。1 行で小さくなりすぎるときは 2 行に折り返す。max_px は 1 px の大きさ（m）の上限。
func _fit_label(label: Label3D, text: String, box: Vector2, max_px: float) -> void:
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if text.is_empty():
		return
	var font := label.font
	var fs := label.font_size
	var one := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var line_h := font.get_height(fs)
	var px := minf(max_px, minf(box.x / maxf(one.x, 1.0), box.y / maxf(line_h, 1.0)))
	if px < max_px * 0.62 and text.length() >= 6:
		# 2 行に分ける（真ん中に近い区切り。Label3D の折り返しに任せると 3 行になって枠からはみ出すことがあった）
		var lines := _split_two(text)
		var w2 := maxf(font.get_string_size(lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
				font.get_string_size(lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var px2 := minf(max_px, minf(box.x / maxf(w2, 1.0), box.y / maxf(line_h * 2.0, 1.0)))
		if px2 > px:
			label.text = lines[0] + "\n" + lines[1]
			px = px2
	label.pixel_size = px


## 文を 2 行に分ける。真ん中に近い区切り（空白・読点・かっこの後・「は」「を」の後）を選び、無ければ英数字の途中を避けて真ん中で切る。
static func _split_two(text: String) -> PackedStringArray:
	var n := text.length()
	var best := -1
	var best_score := INF
	for i in range(1, n):
		var prev := text[i - 1]
		var cur := text[i]
		var score := absf(float(i) - float(n) * 0.5)
		if cur == " " or cur == "　":
			score -= 0.5
		elif prev in ["、", "。", "]", "）", ")", "」", "：", ":", "？", "?"]:
			score -= 1.0
		elif prev in ["は", "を", "が", "の", "に", "で"] and not _is_word_char(cur):
			score -= 0.6
		elif _is_word_char(prev) and _is_word_char(cur):
			continue
		else:
			score += 2.0
		if float(i) < float(n) * 0.25 or float(i) > float(n) * 0.75:
			continue
		if score < best_score:
			best_score = score
			best = i
	if best < 0:
		best = int(float(n) * 0.5)
	return PackedStringArray([text.substr(0, best).strip_edges(), text.substr(best).strip_edges()])


static func _is_word_char(c: String) -> bool:
	var code := c.unicode_at(0)
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or c in ["+", "-", "×", "÷", "=", ".", ","]


static func _label_font() -> FontFile:
	if _font == null:
		var source := FONT_SOURCE as FontFile
		_font = FontFile.new()
		_font.data = source.data
		_font.multichannel_signed_distance_field = true
		_font.msdf_size = 64
		_font.msdf_pixel_range = 16
		_font.generate_mipmaps = true
		_font.allow_system_fallback = source.allow_system_fallback
	return _font


func _build_highlights() -> void:
	_highlight_materials.clear()
	for c: Color in PLAYER_COLORS:
		var mat := ShaderMaterial.new()
		mat.shader = HIGHLIGHT_SHADER
		mat.set_shader_parameter("color", c)
		mat.set_shader_parameter("intensity", 1.0)
		mat.render_priority = 2
		_highlight_materials.append(mat)
	var meshes: Array[Mesh] = [_ribbon_mesh(HIGHLIGHT_INSET), _ribbon_mesh(HIGHLIGHT_INSET + HIGHLIGHT_WIDTH + 0.02)]
	_highlight_nodes.clear()
	_highlight_on.clear()
	for i in range(PANEL_COUNT):
		var pair: Array[MeshInstance3D] = []
		for slot in range(2):
			var mi := MeshInstance3D.new()
			mi.name = "Highlight_%d_%d" % [i, slot]
			mi.mesh = meshes[slot]
			mi.position = Vector3(PANEL_CENTERS[i].x, 0.035 + 0.004 * slot, -PANEL_CENTERS[i].y)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			_rig.add_child(mi)
			pair.append(mi)
		_highlight_nodes.append(pair)
		_highlight_on.append([false, false])


## パネルのふちに沿った四角い帯（XZ の面）。UV.y は 0＝外のふち、1＝内のふち。
func _ribbon_mesh(inset: float) -> Mesh:
	var ox := PANEL_SIZE.x * 0.5 - inset
	var oz := PANEL_SIZE.y * 0.5 - inset
	var ix := ox - HIGHLIGHT_WIDTH
	var iz := oz - HIGHLIGHT_WIDTH
	var outer: Array[Vector3] = [Vector3(-ox, 0, -oz), Vector3(ox, 0, -oz), Vector3(ox, 0, oz), Vector3(-ox, 0, oz)]
	var inner: Array[Vector3] = [Vector3(-ix, 0, -iz), Vector3(ix, 0, -iz), Vector3(ix, 0, iz), Vector3(-ix, 0, iz)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in range(4):
		var k2 := (k + 1) % 4
		for v: Array in [[outer[k], 0.0], [outer[k2], 0.0], [inner[k2], 1.0], [outer[k], 0.0], [inner[k2], 1.0], [inner[k], 1.0]]:
			st.set_uv(Vector2(0.0, float(v[1])))
			st.add_vertex(v[0] as Vector3)
	return st.commit()


# ---------------------------------------------------------------- 動き

func _update_highlight(panel: int) -> void:
	var on: Array = _highlight_on[panel]
	var pair: Array = _highlight_nodes[panel]
	var players: Array[int] = []
	for p in range(2):
		if bool(on[p]):
			players.append(p)
	for slot in range(2):
		var mi := pair[slot] as MeshInstance3D
		mi.visible = slot < players.size()
		if mi.visible:
			mi.material_override = _highlight_materials[players[slot]]
	# 2 人のときは、ふちのにじみを白にする（2 色を混ぜると濁る）
	var glow_color := PLAYER_COLORS[players[0]] if players.size() == 1 else Color(1.0, 1.0, 1.0)
	_paper[panel].set_shader_parameter("glow_color", glow_color)


func _pose_panels(delta: float) -> void:
	for i in range(PANEL_COUNT):
		var any := bool(_highlight_on[i][0]) or bool(_highlight_on[i][1])
		var g := move_toward(_glow[i], 1.0 if any else 0.0, delta * 8.0)
		if g != _glow[i]:
			_glow[i] = g
			_paper[i].set_shader_parameter("glow", g)
		var hole := _holes[i]
		if not hole.is_empty():
			var t := _time - float(hole["t0"])
			_paper[i].set_shader_parameter("hole_radius", SkyGateEffects.hole_radius(float(hole["radius"]), float(hole["open"]), t))
		var since := _time - _flash_at[i]
		if since >= 0.0 and since < 1.0:
			_paper[i].set_shader_parameter("flash", exp(-since * 9.0))


func _pose_drones() -> void:
	var lean := Vector2(clampf(_lean.x * 0.03, -0.25, 0.25), clampf(_lean.y * 0.03, -0.25, 0.25))
	var tilt := Basis(Vector3.BACK, -lean.x) * Basis(Vector3.RIGHT, lean.y)
	for i in range(_drones.size()):
		var rest := _drone_rest[i]
		var bob := Vector3(0.03 * sin(_time * 1.3 + float(i) * 2.1), 0.07 * sin(_time * 2.1 + float(i) * 1.7), 0.03 * sin(_time * 1.1 + float(i)))
		var wobble := Basis(Vector3.RIGHT, 0.03 * sin(_time * 1.9 + float(i))) * Basis(Vector3.BACK, 0.03 * sin(_time * 1.6 + float(i) * 0.7))
		_drones[i].transform = Transform3D(tilt * wobble * rest.basis, rest.origin + bob)
		var hook := _drones[i].transform * Vector3(0.0, _drone_hook_y, 0.0)
		var attach := _cable_attach[i]
		var d := hook - attach
		var length := d.length()
		var y := d / maxf(length, 0.001)
		var x := (Vector3.RIGHT - y * y.dot(Vector3.RIGHT)).normalized()
		var z := x.cross(y)
		_cables[i].transform = Transform3D(Basis(x, y * (length / _cable_length[i]), z), attach)
	for r in range(_rotors.size()):
		var dir := 1.0 if r % 2 == 0 else -1.0
		_rotors[r].basis = Basis(Vector3.UP, dir * rotor_speed * _time + _rotor_phase[r])


# ---------------------------------------------------------------- 穴

func _valid_panel(panel: int) -> bool:
	return panel >= 0 and panel < PANEL_COUNT and _paper.size() == PANEL_COUNT


## パネルの見える範囲（ローカルの XZ）。
func _panel_rect_local(panel: int) -> Rect2:
	var c: Vector2 = PANEL_CENTERS[panel]
	return Rect2(Vector2(c.x - PANEL_SIZE.x * 0.5, -c.y - PANEL_SIZE.y * 0.5), PANEL_SIZE)


## 穴の中心（ローカル）。at がなければパネルの中心。パネルの中に収める。
func _hole_center(panel: int, at: Vector3) -> Vector3:
	var c: Vector2 = PANEL_CENTERS[panel]
	var local := Vector3(c.x, 0.0, -c.y)
	if is_finite(at.x):
		var p := to_local(at)
		var hx := PANEL_SIZE.x * 0.5 - 0.7
		var hz := PANEL_SIZE.y * 0.5 - 0.7
		local.x = clampf(p.x, c.x - hx, c.x + hx)
		local.z = clampf(p.z, -c.y - hz, -c.y + hz)
	return local


## 穴を開ける（すでに開いていれば大きい方の半径にする）。返り値はぎざぎざの種。
func _open_hole(panel: int, center: Vector3, radius: float, open_time: float) -> float:
	_hole_count += 1
	var hole := _holes[panel]
	_flash_at[panel] = _time
	if choice_labels.size() > panel:
		choice_labels[panel].visible = false
	if not hole.is_empty():
		var t := _time - float(hole["t0"])
		var now_r := SkyGateEffects.hole_radius(float(hole["radius"]), float(hole["open"]), t)
		if radius > now_r:
			hole["radius"] = radius
			hole["open"] = open_time
			hole["t0"] = _time - open_time * (now_r / radius)
		return float(hole["seed"])
	var seed := fmod(float(_hole_count) * 12.9898 + float(panel) * 78.233, 100.0)
	var c: Vector2 = PANEL_CENTERS[panel]
	# UV：x は左から右、y は奥から手前（gate_paper.gdshader）
	var uv := Vector2((center.x - (c.x - PANEL_SIZE.x * 0.5)) / PANEL_SIZE.x, (center.z - (-c.y - PANEL_SIZE.y * 0.5)) / PANEL_SIZE.y)
	_holes[panel] = {"t0": _time, "radius": radius, "open": open_time, "seed": seed}
	_paper[panel].set_shader_parameter("hole_center", uv)
	_paper[panel].set_shader_parameter("hole_seed", seed)
	_paper[panel].set_shader_parameter("hole_radius", 0.0)
	return seed
