class_name ParachuteCanopy
extends Node3D

## 「ひらけ！パラシュート」のパラシュート一式（docs/sudden_death_v2/parachute.md 6.4節）。素材は
## assets/sudden_death/parachute/chute/chute.glb（ライブの Blender で作った。作り方は同じフォルダの README.md）。
## このノードのローカル：原点＝肩のライザーのつけ根、+Y＝体の上、+X＝体の横、+Z＝前。毎フレーム place() で肩に合わせる。
##
## 段：0＝背中のコンテナだけ（何も出ていない）、1＝袋とパイロットシュート（布は袋の中＝形の切り替え Packed）、
## 2＝半分ふくらんだしわの形（Half）、3＝全開（基本形）。段が変わると、形の切り替えの重みを少し行き過ぎながら新しい段へ寄せる
## （全開になる瞬間は「スナッチ」：0.35 秒で一気にふくらみ、行き過ぎてから形が決まる）。しぼむときはまっすぐ戻す。
## 2 段目は Breath を揺らしてばたつかせ、3 段目も少しだけ呼吸させる。着地のあとは collapse（0〜1）で後ろへつぶれる。
## drop_to() で床の置き場所を渡してあれば、collapse は「床に落ちる」になる：形は Grounded（布は後ろに小さく山、つり索・
## スライダー・ライザーも床に寝る）へ、置き場所は肩から床へ移る（ライザーのつけ根が体にめり込まない）。
## 色：材質 PC_Accent をプレイヤーの色に塗り替える（P1 オレンジ、P2 青）。敗者の「ハンカチ」も持つ。

const GLB := "res://assets/sudden_death/parachute/chute/chute.glb"
const LAYOUT := "res://assets/sudden_death/parachute/chute/chute_layout.json"
const P1_COLORS := [Color(0.98, 0.55, 0.16), Color(0.99, 0.95, 0.88)]
const P2_COLORS := [Color(0.18, 0.58, 0.92), Color(0.97, 0.97, 0.99)]
## 段ごとの開く長さ（秒）としぼむ長さ。
const OPEN_TIME := [0.25, 0.3, 0.45, 0.35]
const CLOSE_TIME := 0.3
## 段ごとの形の切り替えの重み [Packed, Half]。
const STAGE_WEIGHTS := [[1.0, 0.0], [1.0, 0.0], [0.0, 1.0], [0.0, 0.0]]
## 布の上面の中心の高さ（全開・半分・袋）。半分はライザーのつけ根から 0.74 倍に縮めた形。
const BAG_TOP := 1.55
## ハンカチのひものつけ根（肩から少し上・横。頭に隠れないように）。
const HANKY_OFFSET := Vector3(0.22, 0.3, 0.05)

var is_p1 := true
## 見えている段（0〜3）。
var stage := 0
## 着地のあと、布が後ろへつぶれる（0〜1）。drop_to() のあとは床に落ちる。
var collapse := 0.0

var _model: Node3D = null
var _morphs: Array[MeshInstance3D] = []
var _canopy_parts: Array[Node3D] = []
var _pilot: Node3D = null
var _bridle: Node3D = null
var _bag: Node3D = null
var _hanky: Node3D = null
var _container_mesh: MeshInstance3D = null
var _canopy_top := 6.718
var _link_height := 0.55
var _bag_center := Vector3(0.0, 1.3, 0.0)
## 今の重み（Packed, Half）と、段が変わったときの重み・経過。
var _weights := Vector2(1.0, 0.0)
## 撮影用に重みを決め打ちしたとき（x < 0 は決め打ちなし）。
var _override := Vector2(-1.0, -1.0)
var _from := Vector2(1.0, 0.0)
var _change_t := 0.0
var _change_len := 0.3
var _opening := true
## 段 0 のとき全体を隠す見え方（0〜1）と、ハンカチ。
var _shown := 0.0
var _hanky_amount := 0.0
var _hanky_on := false
var _time := 0.0
var _accent: StandardMaterial3D = null
## 床に落ちたときの置き場所（原点＝床、+Z＝前）。
var _ground := Transform3D.IDENTITY
var _to_ground := false


func build(p1: bool) -> void:
	is_p1 = p1
	for child: Node in get_children():
		child.queue_free()
	_morphs.clear()
	_canopy_parts.clear()
	var scene := load(GLB) as PackedScene
	if scene == null:
		push_warning("[Parachute] %s not found" % GLB)
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Chute"
	add_child(_model)
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if layout is Dictionary:
		_canopy_top = float(layout.get("canopy_top", _canopy_top))
		_link_height = float(layout.get("link_height", _link_height))
		var bag: Array = layout.get("bag_center", [0.0, 1.3, 0.0])
		_bag_center = Vector3(float(bag[0]), float(bag[1]), float(bag[2]))
	_accent = StandardMaterial3D.new()
	_accent.albedo_color = (P1_COLORS if p1 else P2_COLORS)[0]
	_accent.roughness = 0.55
	_accent.cull_mode = BaseMaterial3D.CULL_DISABLED
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_paint(mi)
		match String(mi.name):
			"Canopy", "Lines", "Slider", "Risers":
				_morphs.append(mi)
				_canopy_parts.append(mi)
			"PilotChute":
				_pilot = mi
			"Bridle":
				_bridle = mi
			"DeployBag":
				_bag = mi
			"Hanky":
				_hanky = mi
			"Container":
				_container_mesh = mi
				mi.visible = false   # 背中のコンテナは人形の背骨に付ける（container_node()）
	stage = 0
	collapse = 0.0
	_to_ground = false
	_weights = Vector2(1.0, 0.0)
	_from = _weights
	_shown = 0.0
	_hanky_amount = 0.0
	_hanky_on = false
	_apply(0.0)


## 背中のコンテナ（人形の背骨に付ける）。原点＝背中に当たる面の中心、本体は −Z（後ろ）へ。
func container_node() -> MeshInstance3D:
	if _container_mesh == null:
		return null
	var copy := _container_mesh.duplicate() as MeshInstance3D
	copy.visible = true
	copy.name = "ChuteContainer"
	return copy


## プレイヤーの色の材質（PC_Accent）を塗り替え、布は両面にする。
func _paint(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for s in range(mi.mesh.get_surface_count()):
		var mat := mi.mesh.surface_get_material(s)
		if mat == null:
			continue
		if mat.resource_name == "PC_Accent":
			mi.set_surface_override_material(s, _accent)


## 段を変える（0〜3）。上がるときは開き、下がるときはしぼむ。
func set_stage(next: int) -> void:
	next = clampi(next, 0, 3)
	if next == stage:
		return
	_opening = next > stage
	stage = next
	_override = Vector2(-1.0, -1.0)
	_from = _weights
	_change_t = 0.0
	_change_len = float(OPEN_TIME[next]) if _opening else CLOSE_TIME


## 今の段の形へすぐに合わせる（絵コンテ・ルールカードの撮影用）。
func snap() -> void:
	var w: Array = STAGE_WEIGHTS[stage]
	_weights = Vector2(float(w[0]), float(w[1]))
	_from = _weights
	_change_t = _change_len
	_shown = 1.0 if stage > 0 else 0.0
	_hanky_amount = 1.0 if _hanky_on else 0.0
	_apply(0.0)


func show_hanky(on: bool) -> void:
	_hanky_on = on


## 形の切り替えの重みをそのまま置く（撮影用。Packed・Half）。段の動きは止まる。
func pose_weights(packed: float, half: float) -> void:
	_override = Vector2(packed, half)
	_weights = _override
	_from = _weights
	_shown = 1.0


## 毎フレーム：肩のライザーの位置と向き（basis の列：x＝体の横、y＝上、z＝前）。
## drop_to() のあとは collapse に合わせて、肩から床の置き場所へ移す。
func place(shoulder: Transform3D, delta: float) -> void:
	var at := shoulder.orthonormalized()
	if _to_ground:
		at = at.interpolate_with(_ground.orthonormalized(), clampf(collapse, 0.0, 1.0))
	global_transform = at
	_apply(delta)


## 着地：床に落ちる置き場所（原点＝床の上、着地した人の少し後ろ。+Y＝上、+Z＝人の前）。
## このあとは collapse（0〜1）で床へ落ちる。
func drop_to(ground: Transform3D) -> void:
	_ground = ground
	_to_ground = true


func _apply(delta: float) -> void:
	_time += delta
	_change_t += delta
	var target_w: Array = STAGE_WEIGHTS[stage]
	var target := Vector2(float(target_w[0]), float(target_w[1]))
	var u := clampf(_change_t / maxf(_change_len, 0.01), 0.0, 1.0)
	var k := _back_out(u) if _opening else u * u * (3.0 - 2.0 * u)
	_weights = _from.lerp(target, k) if _override.x < 0.0 else _override
	if _override.x < 0.0:
		_shown = clampf(_shown + (delta / 0.2 if stage > 0 else -delta / 0.25), 0.0, 1.0)
	_hanky_amount = clampf(_hanky_amount + (delta / 0.18 if _hanky_on else -delta / 0.2), 0.0, 1.0)
	# ばたつき：半分のときは大きく、全開は少しだけ呼吸する
	var flutter := 0.0
	if stage == 2:
		flutter = 0.55 + 0.45 * sin(_time * 9.0) * sin(_time * 3.1 + 0.7)
	elif stage == 3:
		flutter = 0.2 + 0.2 * sin(_time * 1.7)
	flutter *= 1.0 - collapse
	for mi: MeshInstance3D in _morphs:
		_set_weight(mi, "Packed", clampf(_weights.x, -0.2, 1.0))
		_set_weight(mi, "Half", _weights.y)
		_set_weight(mi, "Collapsed", 0.0 if _to_ground else collapse)
		_set_weight(mi, "Grounded", collapse if _to_ground else 0.0)
		_set_weight(mi, "Breath", flutter)
	var visible_all := _shown > 0.001
	for node: Node3D in _canopy_parts:
		node.visible = visible_all
	# 布の上面の中心の高さ（袋・半分・全開の重みから）
	var half_top := _link_height + (_canopy_top - _link_height) * 0.74
	var top := _canopy_top + _weights.y * (half_top - _canopy_top) + clampf(_weights.x, 0.0, 1.0) * (BAG_TOP - _canopy_top)
	top = lerpf(top, -1.5, collapse)
	var bag_at := Vector3(0.0, maxf(top + 0.45, _bag_center.y) if _weights.x < 0.5 else _bag_center.y, 0.0)
	var pilot_at := bag_at + Vector3(0.0, 1.5 if _weights.x >= 0.5 else 0.7, 0.0)
	var sway := Vector3(sin(_time * 2.3) * 0.12, 0.0, cos(_time * 1.9) * 0.1)
	var gone := 1.0 - collapse
	var s := _back_out(_shown) * gone
	if _bag != null:
		_bag.visible = visible_all and gone > 0.05
		_bag.transform = Transform3D(Basis.from_scale(Vector3.ONE * maxf(s, 0.01)), bag_at)
	if _pilot != null:
		_pilot.visible = visible_all and gone > 0.05
		_pilot.transform = Transform3D(Basis(Vector3.FORWARD, sway.x * 0.4) * Basis.from_scale(Vector3.ONE * maxf(s, 0.01)), pilot_at + sway)
	if _bridle != null:
		_bridle.visible = visible_all and gone > 0.05
		var from := Vector3(0.0, (bag_at.y + 0.25) if _weights.x >= 0.5 else top, 0.0)
		var to := pilot_at + sway
		var dir := to - from
		var length := maxf(dir.length(), 0.01)
		var y := dir / length
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		_bridle.transform = Transform3D(Basis(x, y * length, x.cross(y)), from)
	if _hanky != null:
		_hanky.visible = _hanky_amount > 0.001
		var hs := _back_out(_hanky_amount)
		_hanky.transform = Transform3D(Basis(Vector3.RIGHT, sin(_time * 18.0) * 0.25) * Basis(Vector3.UP, sin(_time * 7.0) * 0.4)
			* Basis.from_scale(Vector3.ONE * maxf(hs, 0.01)), HANKY_OFFSET)


## カメラの収め方（parachute.md 7.1節）：いま見えている一番上の点（ワールド）。パイロットシュートが出ていればドームの頂点、
## 出ていなければ布の上面。段 0 で何も出ていなければ肩の位置。
func top_point() -> Vector3:
	if _shown <= 0.001 or stage == 0:
		return global_position
	if _pilot != null and _pilot.visible:
		# ドームの頂点はパイロットシュートの原点の 1.08 m 上（chute_layout：ドーム 0.6 m 上、高さ 0.48 m）
		return _pilot.global_transform * Vector3(0.0, 1.08, 0.0)
	var half_top := _link_height + (_canopy_top - _link_height) * 0.74
	var top := _canopy_top + _weights.y * (half_top - _canopy_top) + clampf(_weights.x, 0.0, 1.0) * (BAG_TOP - _canopy_top)
	return global_transform * Vector3(0.0, top, 0.0)


## いま見えている布の横の半分の幅（m）。袋だけなら 0.3。
func half_span() -> float:
	if _shown <= 0.001 or stage == 0:
		return 0.0
	var full := 3.6
	return lerpf(lerpf(full, full * 0.53, clampf(_weights.y, 0.0, 1.0)), 0.3, clampf(_weights.x, 0.0, 1.0))


func _set_weight(mi: MeshInstance3D, shape: String, value: float) -> void:
	var index := mi.find_blend_shape_by_name(shape)
	if index >= 0:
		mi.set_blend_shape_value(index, value)


func _back_out(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var x := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + c3 * x * x * x + c1 * x * x


func get_debug_snapshot() -> Dictionary:
	var weights := {}
	if not _morphs.is_empty():
		var mi := _morphs[0]
		for shape: String in ["Packed", "Half", "Collapsed", "Breath", "Grounded"]:
			var index := mi.find_blend_shape_by_name(shape)
			weights[shape] = snappedf(mi.get_blend_shape_value(index), 0.001) if index >= 0 else -1.0
	return {"stage": stage, "weights": weights, "shown": snappedf(_shown, 0.01), "collapse": snappedf(collapse, 0.01), "grounded": _to_ground,
		"morph_meshes": _morphs.size(), "hanky": snappedf(_hanky_amount, 0.01)}
