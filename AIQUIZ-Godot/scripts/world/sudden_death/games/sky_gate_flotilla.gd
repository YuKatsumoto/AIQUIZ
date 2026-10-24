class_name SkyGateFlotilla
extends Node3D

## 着地台のまわりに浮かぶ観客船（docs/sudden_death_v2/sky_gate.md 第9章、assets/sudden_death/sky_gate/spectator_boats/README.md）。
## 観覧船とパーティー船を着地台のまわり 20〜28 m に、横腹を着地台へ向けて並べ、座った観客（SeatedSpectatorKit。ゴールの観客と
## 同じ人と動き）を乗せる。観客は着地台の方（船の +Z）を向く。水上機が着地台に寄って離水する道すじ（FloatplaneStaging.P_DOCK_ANGLE の
## 向きの直線、翼の幅 24 m）は空けておく（corridor_clearance で確かめる）。着地台を回るカメラ（半径 11 m まで）にも掛からない。
## 着地すると観客が歓声をあげてクラッカーを鳴らし、船の打ち上げ筒から花火を上げる（SkyGateFireworks）。決着は勝者のダンスの間
## ずっと上げ続け（stop_show まで）、ROUND の着地は短く 5 発。
## このノードは着地台の中心 × 海面に置く（float_at。回さない）。船は波に合わせて上下・傾く。

const GLB := "res://assets/sudden_death/sky_gate/spectator_boats/spectator_boats.glb"
const LAYOUT := "res://assets/sudden_death/sky_gate/spectator_boats/spectator_boats_layout.json"
const FLAG_SHADER := preload("res://assets/sudden_death/sky_gate/shaders/boat_flags.gdshader")

## 船の並び（着地台の中心から。角度は +Z から +X へ回る度、半径 m）と色帯の色。P1（+X）の側が画面の左。
## 2026-10-21（ユーザーの指示「もっと近づけて」）：34〜40 m から寄せた。横の 4 隻は 20 m、水上機の通り道の脇の前の 2 隻は 26〜28 m。
## 着地の画（着地台の −Z の側から +Z を見る）では、52° と −35° の 2 隻が水上機の待つ所（+Z の少し +X）の左右に映り、
## ダンスの間にカメラが回ると横の船が映る。
const BOATS := [
	{"type": "SB_Launch", "angle": 52.0, "radius": 28.0, "stripe": Color("#1b2d4f")},
	{"type": "SB_Pontoon", "angle": -35.0, "radius": 26.0, "stripe": Color("#8c1c22")},
	{"type": "SB_Launch", "angle": 95.0, "radius": 20.0, "stripe": Color("#0f6b6b")},
	{"type": "SB_Launch", "angle": -62.0, "radius": 21.0, "stripe": Color("#8c1c22")},
	{"type": "SB_Pontoon", "angle": 128.0, "radius": 20.0, "stripe": Color("#1b2d4f")},
	{"type": "SB_Launch", "angle": -108.0, "radius": 21.0, "stripe": Color("#b8860b")},
]
## 水上機の道すじ（着地台を通る直線）から船の四隅まで空ける距離（m）：着地台の先（DOCK_S より先、水上機が待って離水する所）と
## 着地台の手前（低く飛んで来る所）は翼の半分 12 m と余裕 1 m。着地台の真横（その間）はスロープと尾翼の幅 6 m。
const CORRIDOR_HALF := 13.0
const CORRIDOR_SIDE := 6.0
const DOCK_S := 9.0
## 着地台を回るカメラから空ける距離：船の内側のふちは着地台の中心からこれより外（カメラは半径 11 m ＋ 2 人のとき 1.6 m）。
const CAMERA_CLEAR := 15.0

# 観客（GrandstandCrowd と同じ役と見た目の決め方）
const SEAT_DENSITY := 0.9
const P1_SHARE := 0.36
const P2_SHARE := 0.36
const ROLE_CALM := 0
const ROLE_FAN := 1
const ROLE_DANCER := 2
const ROLE_EATER := 4
const ROLE_SELFIE := 5
const ROLE_BINOCULARS := 6
const ROLE_LEADER := 7
const ROLE_TOWEL := 8
const HAIR_WEIGHTS: Array[int] = [0, 0, 1, 2, 3, 4, 5, 6]
## 座る人の腰は座面の中心より後ろ（layout の hip_behind）。手を上げたときの手の位置（腰から。上・前）。
const HAND_UP := Vector3(0.0, 1.35, 0.3)

# 歓声（seated_spectator.gdshader の cue_kind：1 ゴール・2 判定・3 カウントダウン）
const CUE_GOAL := 1
const CUE_VERDICT := 2
const CUE_ANTICIPATE := 3
const CUE_FADE := 0.3
## 判定の歓声（勝者のファンは喜び、相手のファンはがっかり）のあと、勝者のファンの歓声とほかの人の拍手へ。
const VERDICT_SECONDS := 4.0
const ROUND_CHEER_SECONDS := 7.0

# クラッカーと花火
const POPPERS_PER_BOAT := 4
const POPPER_STAGGER := 0.6
## 1 回に音を鳴らすクラッカーの数（ほかは音なし。効果音の声は 8 本で、着地の音と歓声も鳴っている）
const POPPER_SOUNDS := 3
## 決着：最初の 3 発、そのあと 1 発ずつの間（秒）、2 発同時の割合、締めの連発の時刻と数。ダンスの途中でもう一度クラッカー。
const FIRST_SALVO_AT := 0.5
const SHELL_GAP := Vector2(0.5, 0.85)
const DOUBLE_CHANCE := 0.3
const FINALE_AT := 5.4
const FINALE_SHELLS := 5
const SECOND_POPPERS_AT := 3.0
const SHOW_LIMIT := 24.0
## ROUND の着地の 5 発（秒）
const ROUND_SHELLS: Array[float] = [0.55, 0.75, 0.95, 1.9, 2.25]
## はじける高さ（海面から m）と、船から外へ離す割合（船が近いので、船の向こうではじけさせて、観客の船の上に花火が開く画にする）
const BURST_HEIGHT := Vector2(9.0, 17.0)
const BURST_OUTWARD := 0.35
const RISE_TIME := Vector2(1.1, 1.4)

var quality := "balanced"
var camera: Camera3D = null
var fireworks: SkyGateFireworks = null
## 船（Node3D）と、その情報：{"type", "angle", "radius", "people": [{"hip", "team"}], "mouths": PackedVector3Array, "phase"}
var boats: Array[Node3D] = []
var boat_info: Array[Dictionary] = []
var spectator_count := 0
var _built := false
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _layout := {}
var _crowd_material: ShaderMaterial = null
var _cue_kind := 0
var _cue_team := 0
var _cue_clock := 0.0
var _cue_weight := 0.0
var _want := {"kind": 0, "team": 0, "weight": 0.0}
## 祝いの段取り（"" なし・"round"・"finale"）と、その時計・次の打ち上げ
var _show := ""
var _show_t := 0.0
var _show_winner := 0
var _next_shell := INF
var _round_index := 0
var _finale_done := false
var _second_poppers := false
## 花火を上げる船を選んだ回数：はじける所がカメラの画に入った／入る所がなくカメラの向こうの船にした
var picks_in_view := 0
var picks_fallback := 0
## 祝いを始めてからの時計（花火が終わっても進む）と、歓声を落ちつかせる時刻
var _cheer_t := 0.0
var _cheer_until := INF


func build(quality_name: String = "") -> bool:
	quality = GraphicsQuality.normalize(quality_name if quality_name != "" else String(GameManager.graphics_quality))
	_rng.seed = 20261021
	var scene := load(GLB) as PackedScene
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if scene == null or not (parsed is Dictionary):
		push_warning("[SkyGateFlotilla] spectator boats are missing (%s)" % GLB)
		return false
	_layout = parsed
	var source := scene.instantiate() as Node3D
	_crowd_material = SeatedSpectatorKit.material().duplicate() as ShaderMaterial
	# 船は 30〜50 m 先：焼いた 20fps のコマを飛ばさず、なめらかに混ぜる距離を広げる
	_crowd_material.set_shader_parameter("smooth_distance", 160.0)
	var flags := ShaderMaterial.new()
	flags.shader = FLAG_SHADER
	for i in range(BOATS.size()):
		var spec: Dictionary = BOATS[i]
		var proto := source.find_child(str(spec["type"]), true, false) as Node3D
		if proto == null:
			continue
		var boat := proto.duplicate() as Node3D
		boat.name = "Boat%d_%s" % [i + 1, str(spec["type"]).trim_prefix("SB_")]
		add_child(boat)
		boat.transform = boat_transform(spec, 0.0, 0.0)
		_paint(boat, spec["stripe"] as Color, flags)
		var layout: Dictionary = (_layout.get("boats", {}) as Dictionary).get(str(spec["type"]), {})
		var mouths := PackedVector3Array()
		for p: Array in layout.get("launch", []):
			mouths.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		var info := {"type": spec["type"], "angle": spec["angle"], "radius": spec["radius"], "phase": float(i) * 1.37,
				"people": [], "mouths": mouths}
		_seat_people(boat, info, layout, i)
		boats.append(boat)
		boat_info.append(info)
	source.free()
	fireworks = SkyGateFireworks.new()
	fireworks.name = "Fireworks"
	add_child(fireworks)
	fireworks.build(quality)
	_built = not boats.is_empty()
	return _built


## 船の置き方（このノードから見て）：着地台から angle の向きへ radius、横腹（+Z）を着地台へ。t は波の時計、phase は船ごとのずれ。
static func boat_transform(spec: Dictionary, t: float, phase: float) -> Transform3D:
	var a := deg_to_rad(float(spec["angle"]))
	var out := Vector3(sin(a), 0.0, cos(a))
	var heave := 0.07 * sin(t * 0.8 + phase) + 0.03 * sin(t * 1.9 + phase * 2.1)
	var pitch := deg_to_rad(0.7) * sin(t * 0.6 + phase * 1.3)
	var roll := deg_to_rad(1.1) * sin(t * 0.75 + phase * 0.7)
	var yaw := deg_to_rad(1.2) * sin(t * 0.13 + phase)
	var basis := Basis.looking_at(out, Vector3.UP).rotated(Vector3.UP, yaw)
	basis = basis * Basis(Vector3.RIGHT, roll) * Basis(Vector3.BACK, pitch)
	return Transform3D(basis, out * float(spec["radius"]) + Vector3(0.0, heave, 0.0))


## 水上機の道すじ（着地台を通る P_DOCK_ANGLE の向きの直線）から空ける距離に対する、すべての船の四隅の余裕（m）。0 以上なら空いている。
## 着地台の先（DOCK_S より先）と手前は CORRIDOR_HALF、着地台の真横は CORRIDOR_SIDE を空ける。
static func corridor_clearance(layout: Dictionary) -> float:
	var dock := Vector3(cos(FloatplaneStaging.P_DOCK_ANGLE), 0.0, sin(FloatplaneStaging.P_DOCK_ANGLE))
	var normal := Vector3(dock.z, 0.0, -dock.x)
	var best := INF
	for corner: Vector3 in _corners(layout):
		var along := corner.dot(dock)
		var need := CORRIDOR_SIDE if along > 0.0 and along < DOCK_S else CORRIDOR_HALF
		best = minf(best, absf(corner.dot(normal)) - need)
	return best


## 着地台の中心から一番近い船のふち（m）。CAMERA_CLEAR 以上なら、着地台を回るカメラに掛からない。
static func nearest_edge(layout: Dictionary) -> float:
	var best := INF
	for corner: Vector3 in _corners(layout):
		best = minf(best, Vector2(corner.x, corner.z).length())
	return best


## すべての船の箱の四隅（このノードから見て、水面の高さ）。
static func _corners(layout: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for spec: Dictionary in BOATS:
		var box: Array = ((layout.get("boats", {}) as Dictionary).get(str(spec["type"]), {}) as Dictionary).get("aabb", [])
		if box.size() < 2:
			continue
		var lo := Vector3(float(box[0][0]), 0.0, float(box[0][2]))
		var hi := Vector3(float(box[1][0]), 0.0, float(box[1][2]))
		var xf := boat_transform(spec, 0.0, 0.0)
		for corner: Vector3 in [Vector3(lo.x, 0, lo.z), Vector3(hi.x, 0, lo.z), Vector3(hi.x, 0, hi.z), Vector3(lo.x, 0, hi.z)]:
			var p := xf * corner
			out.append(Vector3(p.x, 0.0, p.z))
	return out


func layout() -> Dictionary:
	return _layout


## 色帯を船ごとの色に塗り替え、小旗をはためかせる。
func _paint(boat: Node3D, stripe: Color, flags: ShaderMaterial) -> void:
	var tint: StandardMaterial3D = null
	for node: Node in boat.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if String(mi.name).ends_with("_Flags"):
			mi.material_override = flags
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		for s in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(s)
			if m == null or m.resource_name != "SB_Stripe":
				continue
			if tint == null:
				tint = (m.duplicate() as StandardMaterial3D) if m is StandardMaterial3D else StandardMaterial3D.new()
				tint.albedo_color = stripe
			mi.set_surface_override_material(s, tint)


# ------------------------------------------------------------------ the spectators

## 座席に観客を座らせる（ほぼ満席）。前の列の真ん中に応援団長（メガホンか太鼓）。見た目と役は GrandstandCrowd と同じ決め方。
func _seat_people(boat: Node3D, info: Dictionary, layout: Dictionary, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (index + 3) + 104729
	var hip_behind := float(_layout.get("hip_behind", 0.06))
	var seats: Array = layout.get("seats", [])
	var leader := -1
	var best := INF
	for i in range(seats.size()):
		var s: Array = seats[i]
		if int(s[3]) == 1 and absf(float(s[0])) < best:
			best = absf(float(s[0]))
			leader = i
	var plain: Array[Dictionary] = []
	var holders: Array[Dictionary] = []
	for i in range(seats.size()):
		var s: Array = seats[i]
		if i != leader and rng.randf() > SEAT_DENSITY:
			continue
		var hip := Vector3(float(s[0]), float(s[1]), float(s[2]) - hip_behind)
		var person := _person(rng, hip, ROLE_LEADER if i == leader else -1)
		(info["people"] as Array).append({"hip": hip, "team": person["team"]})
		if int(person["prop"]) == 0:
			plain.append(person)
		else:
			holders.append(person)
	var box: Array = layout.get("aabb", [[-6, -1, -3], [6, 5, 3]])
	var bounds := AABB(Vector3(float(box[0][0]), float(box[0][1]), float(box[0][2])) - Vector3(0.5, 0.0, 0.5),
			Vector3(float(box[1][0]) - float(box[0][0]) + 1.0, float(box[1][1]) - float(box[0][1]) + 1.5, float(box[1][2]) - float(box[0][2]) + 1.0))
	_add_batch(boat, "Spectators", plain, SeatedSpectatorKit.mesh(), bounds)
	_add_batch(boat, "SpectatorsProps", holders, SeatedSpectatorKit.prop_mesh(), bounds)
	spectator_count += plain.size() + holders.size()


func _add_batch(boat: Node3D, batch_name: String, people: Array[Dictionary], mesh: Mesh, bounds: AABB) -> void:
	if people.is_empty():
		return
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	instances.mesh = mesh
	instances.instance_count = people.size()
	for i in range(people.size()):
		instances.set_instance_transform(i, people[i]["transform"])
		instances.set_instance_color(i, people[i]["shirt"])
		instances.set_instance_custom_data(i, people[i]["custom"])
	instances.custom_aabb = bounds
	var batch := MultiMeshInstance3D.new()
	batch.name = batch_name
	batch.multimesh = instances
	batch.material_override = _crowd_material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	boat.add_child(batch)


## 1 人の見た目と役（GrandstandCrowd._person と同じ符号：look = 髪 + 7×肌 + 42×髪の色 + 252×ズボン + 1260×靴 + 5040×持ち物、
## habit = 休みの動き + 8×役 + 128×チーム）。観客は +Z（着地台）を向く。
func _person(rng: RandomNumberGenerator, hip: Vector3, forced_role: int) -> Dictionary:
	var roll := rng.randf()
	var team := 1 if roll < P1_SHARE else (2 if roll < P1_SHARE + P2_SHARE else 0)
	var role := ROLE_FAN if team != 0 else ROLE_CALM
	var prop := 0
	if forced_role == ROLE_LEADER:
		role = ROLE_LEADER
		team = 1 + rng.randi_range(0, 1)
	elif team == 0:
		var pick := rng.randf()
		if pick < 0.22:
			role = ROLE_DANCER
		elif pick < 0.34:
			role = ROLE_SELFIE
		elif pick < 0.44:
			role = ROLE_BINOCULARS
		elif pick < 0.56:
			role = ROLE_EATER
	elif rng.randf() < 0.15:
		role = ROLE_TOWEL
	match role:
		ROLE_EATER:
			prop = SeatedSpectatorKit.PROP_POPCORN if rng.randf() < 0.6 else SeatedSpectatorKit.PROP_HOTDOG
		ROLE_SELFIE:
			prop = SeatedSpectatorKit.PROP_PHONE
		ROLE_BINOCULARS:
			prop = SeatedSpectatorKit.PROP_BINOCULARS
		ROLE_LEADER:
			prop = SeatedSpectatorKit.PROP_MEGAPHONE if rng.randf() < 0.5 else SeatedSpectatorKit.PROP_DRUM
		ROLE_TOWEL:
			prop = SeatedSpectatorKit.PROP_TOWEL
	var shirts: Array[Color] = GoalStand.P1_SHIRTS if team == 1 else (GoalStand.P2_SHIRTS if team == 2 else GoalStand.NEUTRAL_SHIRTS)
	var hair := HAIR_WEIGHTS[rng.randi_range(0, HAIR_WEIGHTS.size() - 1)]
	if role == ROLE_LEADER:
		hair = 6
	var look := hair \
		+ 7 * rng.randi_range(0, GoalStand.SKINS.size() - 1) \
		+ 42 * rng.randi_range(0, GoalStand.HAIR_COLORS.size() - 1) \
		+ 252 * rng.randi_range(0, GoalStand.PANTS.size() - 1) \
		+ 1260 * rng.randi_range(0, GoalStand.SHOES.size() - 1) \
		+ 5040 * prop
	var idle := SeatedSpectatorKit.clip_index(&"SPEC_Idle") if rng.randf() < 0.65 else SeatedSpectatorKit.clip_index(&"SPEC_FoldArms")
	var habit := idle + 8 * role + 128 * team
	var size := rng.randf_range(0.93, 1.03)
	return {
		"transform": Transform3D(Basis.from_scale(Vector3.ONE * size), hip),
		"shirt": shirts[rng.randi_range(0, shirts.size() - 1)],
		"custom": Color(rng.randf(), float(look), float(habit), rng.randf_range(0.9, 1.12)),
		"prop": prop,
		"team": team,
	}


# ------------------------------------------------------------------ every frame

## 着地台の中心（ワールドの x, z）と海面の高さに合わせる。
func float_at(center: Vector3, sea_height: float, _delta: float) -> void:
	global_position = Vector3(center.x, sea_height, center.z)


## 波・観客の歓声・祝いの段取り・花火を進める。
func advance(delta: float) -> void:
	if not _built:
		return
	_time += delta
	_cheer_t += delta
	for i in range(boats.size()):
		boats[i].transform = boat_transform(BOATS[i], _time, float(boat_info[i]["phase"]))
	_update_show(delta)
	_update_cue(delta)
	if fireworks != null:
		fireworks.camera = camera
		fireworks.advance(delta)


## 降りてくる人を見上げて身を乗り出す（着地の少し前）。
func anticipate() -> void:
	if _show == "":
		_request(CUE_ANTICIPATE, 0, 1.0)


## 着地した：歓声とクラッカー、花火。finale なら決着（winner の勝ち。stop_show まで上げ続ける）、でなければ ROUND の着地（短く）。
func celebrate(winner: int, finale: bool) -> void:
	if not _built:
		return
	_show = "finale" if finale else "round"
	_show_t = 0.0
	_cheer_t = 0.0
	_show_winner = winner if finale else 0
	_round_index = 0
	_finale_done = false
	_second_poppers = false
	_next_shell = FIRST_SALVO_AT
	_request(CUE_VERDICT, _show_winner, 1.0)
	_cheer_until = INF if finale else ROUND_CHEER_SECONDS
	_popper_wave(POPPERS_PER_BOAT, 0.12)
	if finale:
		AudioManager.play_sfx(&"crowd_win_cheer", -3.0)
	else:
		AudioManager.play_sfx(&"crowd_goal_cheer", -4.0)


## 新しい花火は上げない（上がっているものは最後まで）。観客の歓声もゆっくり落ちつく。
func stop_show() -> void:
	_show = ""
	_next_shell = INF
	_cheer_until = 0.0


## すべてを止めて消す（見せ方の片づけ・次のラウンド）。
func reset_show() -> void:
	stop_show()
	_want = {"kind": 0, "team": 0, "weight": 0.0}
	_cue_weight = 0.0
	if fireworks != null:
		fireworks.clear()


func is_showing() -> bool:
	return _show != ""


func _update_show(delta: float) -> void:
	if _show == "":
		return
	_show_t += delta
	if _show == "round":
		while _round_index < ROUND_SHELLS.size() and _show_t >= ROUND_SHELLS[_round_index]:
			_launch(0.0)
			_round_index += 1
		if _round_index >= ROUND_SHELLS.size():
			_show = ""
		return
	if _show_t >= _next_shell:
		if _show_t < FIRST_SALVO_AT + 0.1:
			for k in range(3):
				_launch(0.15 * float(k))
		else:
			_launch(0.0)
			if _rng.randf() < DOUBLE_CHANCE:
				_launch(0.18)
		_next_shell = _show_t + _rng.randf_range(SHELL_GAP.x, SHELL_GAP.y)
	if not _finale_done and _show_t >= FINALE_AT:
		_finale_done = true
		for k in range(FINALE_SHELLS):
			_launch(0.13 * float(k))
	if not _second_poppers and _show_t >= SECOND_POPPERS_AT:
		_second_poppers = true
		_popper_wave(2, 0.0)
	if _show_t >= SHOW_LIMIT:
		stop_show()


## 船ごとに count 人がクラッカーを鳴らす（勝者のファンから。着地台の方の上へ向けて、少しずつずらす）。
func _popper_wave(count: int, delay: float) -> void:
	var sounds := POPPER_SOUNDS
	for i in range(boats.size()):
		var people: Array = (boat_info[i]["people"] as Array).duplicate()
		people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["team"] == _show_winner and _show_winner != 0) > int(b["team"] == _show_winner and _show_winner != 0))
		var xf := boats[i].transform
		for k in range(mini(count, people.size())):
			var pick: Dictionary = people[k if k < 2 else _rng.randi_range(0, people.size() - 1)]
			var hand := xf * ((pick["hip"] as Vector3) + HAND_UP)
			var aim := (xf.basis * Vector3(_rng.randf_range(-0.3, 0.3), 0.85, 1.0)).normalized()
			fireworks.popper(hand, aim, delay + _rng.randf_range(0.0, POPPER_STAGGER), sounds > 0)
			sounds -= 1


## 1 発：カメラに映る船を選び（はじける所がカメラの画に入る船。なければ着地台の向こうの船）、その打ち上げ筒から上げる。
func _launch(delay: float) -> void:
	var order: Array = range(boats.size())
	order.shuffle()
	var pick := -1
	var burst := Vector3.ZERO
	for attempt in range(4):
		# 高い所から順に、はじける所（とその上 3.5 m）がカメラの画に入る船を探す。最後は真ん中だけ入ればよい
		var height := lerpf(BURST_HEIGHT.y, BURST_HEIGHT.x, float(attempt) / 3.0)
		for i: int in order:
			var p := _burst_point(i, height)
			if _in_view(p) and (attempt == 3 or _in_view(p + Vector3.UP * 3.5)):
				pick = i
				burst = p
				break
		if pick >= 0:
			break
	if pick >= 0:
		picks_in_view += 1
	else:
		picks_fallback += 1
		# 画に入る所がない：カメラの向こう側の船（カメラから一番遠い船）
		var far := -INF
		var eye := to_local(camera.global_position) if camera != null and camera.is_inside_tree() else Vector3(0.0, 3.0, -10.0)
		for i in range(boats.size()):
			var d := eye.distance_to(boats[i].position)
			if d > far:
				far = d
				pick = i
		burst = _burst_point(pick, BURST_HEIGHT.x)
	var mouths: PackedVector3Array = boat_info[pick]["mouths"]
	var from := boats[pick].transform * (mouths[_rng.randi_range(0, mouths.size() - 1)] if not mouths.is_empty() else Vector3(0.0, 1.2, 0.0))
	var pattern: String = SkyGateFireworks.PATTERN_NAMES[_rng.randi_range(0, SkyGateFireworks.PATTERN_NAMES.size() - 1)]
	var a: Color = SkyGateFireworks.SHELL_COLORS[_rng.randi_range(0, SkyGateFireworks.SHELL_COLORS.size() - 1)]
	if _show_winner > 0 and _rng.randf() < 0.5:
		a = SkyGateFireworks.PLAYER_COLORS[_show_winner - 1]
	var b: Color = SkyGateFireworks.SHELL_COLORS[_rng.randi_range(0, SkyGateFireworks.SHELL_COLORS.size() - 1)]
	fireworks.shell(from, burst, pattern, a, b, _rng.randf_range(RISE_TIME.x, RISE_TIME.y), delay)


## 船 i の花火がはじける所（このノードから見て）：船の少し向こう（着地台から離れる向き）の海の上、高さ height のまわり。
func _burst_point(i: int, height: float) -> Vector3:
	var at := boats[i].position * (1.0 + BURST_OUTWARD)
	return Vector3(at.x + _rng.randf_range(-3.0, 3.0), _rng.randf_range(height - 2.0, height), at.z + _rng.randf_range(-3.0, 3.0))


func _in_view(local_point: Vector3) -> bool:
	if camera == null or not camera.is_inside_tree():
		return true
	return camera.is_position_in_frustum(to_global(local_point))


# ------------------------------------------------------------------ the crowd's cue

func _request(kind: int, team: int, weight: float) -> void:
	_want = {"kind": kind, "team": team, "weight": weight}


## 歓声の切り替え：違う種類へは一度 0 へ落としてから替える（動きが飛ばないように）。判定の歓声は VERDICT_SECONDS で
## 勝者のファンの歓声とほかの人の拍手へ、ROUND の歓声は ROUND_CHEER_SECONDS で落ちつく。
func _update_cue(delta: float) -> void:
	_cue_clock += delta
	if int(_want["kind"]) == CUE_VERDICT and _cue_kind == CUE_VERDICT and _cue_clock >= VERDICT_SECONDS:
		_request(CUE_GOAL, _show_winner, 1.0)
	if _cheer_t >= _cheer_until and float(_want["weight"]) > 0.0 and int(_want["kind"]) != CUE_ANTICIPATE:
		_request(int(_want["kind"]), int(_want["team"]), 0.0)
	var same := int(_want["kind"]) == _cue_kind and int(_want["team"]) == _cue_team
	var target := float(_want["weight"]) if same else 0.0
	_cue_weight = move_toward(_cue_weight, target, delta / CUE_FADE)
	if not same and _cue_weight <= 0.001:
		_cue_kind = int(_want["kind"])
		_cue_team = int(_want["team"])
		_cue_clock = 0.0
	var m := _crowd_material
	m.set_shader_parameter("cue_kind", _cue_kind)
	m.set_shader_parameter("cue_team", _cue_team)
	m.set_shader_parameter("cue_time", _cue_clock)
	m.set_shader_parameter("cue_weight", _cue_weight)
	m.set_shader_parameter("rivals_react", true)
	m.set_shader_parameter("shock_time", -1.0)
	m.set_shader_parameter("wave_time", -1.0)
	m.set_shader_parameter("chant_weight", 0.0)
	m.set_shader_parameter("sync_weight", 0.0)


func cue_state() -> Dictionary:
	return {"kind": _cue_kind, "team": _cue_team, "weight": snappedf(_cue_weight, 0.01)}


func get_debug_snapshot() -> Dictionary:
	return {"boats": boats.size(), "spectators": spectator_count, "show": _show, "show_t": snappedf(_show_t, 0.01),
		"cue": cue_state(), "shells": fireworks.shells_launched if fireworks != null else 0,
		"poppers": fireworks.poppers_fired if fireworks != null else 0, "in_view": picks_in_view, "fallback": picks_fallback,
		"fx": fireworks.live_counts() if fireworks != null else {}}
