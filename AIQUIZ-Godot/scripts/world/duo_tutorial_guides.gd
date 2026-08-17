extends Node3D
class_name DuoTutorialGuides

## ローカル2Pチュートリアル専用の3Dガイド。
## 1P版（solo_tutorial_guides.gd）と同じく全パーツを同じ加算発光マテリアル工場から
## 作り、明滅も1つの脈動値で揃える。2Pではこれをプレイヤー色で二重化し、
## どちらの誘導なのかを色で見分けられるようにする。

const DuoFlow = preload("res://scripts/core/tutorial/duo_tutorial_flow.gd")

const P1_COLOR := Color(1.0, 0.48, 0.12, 1.0)
const P2_COLOR := Color(0.18, 0.88, 1.0, 1.0)
const ACCENT := Color(1.0, 0.82, 0.24, 1.0)
const EDGE_COLOR := Color(1.0, 0.32, 0.26, 1.0)
const GOAL_COLOR := Color(0.36, 1.0, 0.62, 1.0)

const EDGE_DASH_COUNT := 16
const EDGE_DASH_SPACING := 3.4
const EDGE_FLOW_SPEED := 7.0
const ROUTE_DASH_COUNT := 10
const CHEVRON_COUNT := 3
const FLOOR_OFFSET := 0.06

var game_state: QuizGameState = null

var _time: float = 0.0
var _materials: Array[StandardMaterial3D] = []
var _edge_dashes: Array[MeshInstance3D] = []
var _rings: Dictionary = {}
var _chevrons: Dictionary = {}
var _route_dashes: Dictionary = {}
var _name_labels: Dictionary = {}
var _door_frame: Node3D = null
var _danger_stripe: MeshInstance3D = null
var _target_ring: MeshInstance3D = null
var _goal_beacon: MeshInstance3D = null
var _label: Label3D = null


func setup(state: QuizGameState) -> void:
	game_state = state
	_build()


func update(delta: float) -> void:
	_time += delta
	if game_state == null or not game_state.is_duo_tutorial():
		visible = false
		return
	visible = game_state.game_state not in [
		Constants.STATE_CLEAR,
		Constants.STATE_GAME_OVER,
		Constants.STATE_PRELOADING,
		Constants.STATE_WAITING_START,
		Constants.STATE_FLYOVER,
		Constants.STATE_COUNTDOWN,
	]
	if not visible:
		return

	var model := game_state.get_tutorial_overlay_model()
	var guide := str(model.get("world_guide", ""))
	var pulse := 0.5 + 0.5 * sin(_time * 4.2)
	for material: StandardMaterial3D in _materials:
		material.emission_energy_multiplier = 1.6 + pulse * 1.4

	_update_edge_lines(guide, pulse)
	for player_index: int in [1, 2]:
		_update_player_guide(player_index, model, guide, pulse)
	_update_name_labels(guide)
	_update_door_guide(model, guide, pulse)
	_update_hazard_guide(guide, pulse)
	_update_ghost_target(guide, pulse)
	_update_goal_guide(guide, pulse)
	_update_label(model, guide)


# ---------- 構築 ----------

func _build() -> void:
	var edge_material := _make_material(EDGE_COLOR)
	for _i: int in range(EDGE_DASH_COUNT * 2):
		var dash := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.34, 0.04, 2.0)
		dash.mesh = mesh
		dash.material_override = edge_material
		add_child(dash)
		_edge_dashes.append(dash)

	for player_index: int in [1, 2]:
		var color := _player_color(player_index)
		var ring := MeshInstance3D.new()
		ring.name = "P%dFloorRing" % player_index
		var torus := TorusMesh.new()
		torus.inner_radius = 0.78
		torus.outer_radius = 0.98
		torus.rings = 32
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = _make_material(color)
		add_child(ring)
		_rings[player_index] = ring

		var chevron_material := _make_material(color)
		var chevrons: Array[MeshInstance3D] = []
		for _i: int in range(CHEVRON_COUNT):
			var chevron := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(1.15, 0.9, 0.05)
			chevron.mesh = prism
			chevron.material_override = chevron_material
			# 三角形を床に寝かせ、頂点が +Z（進行方向）を向くようにする。
			chevron.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			add_child(chevron)
			chevrons.append(chevron)
		_chevrons[player_index] = chevrons

		var route_material := _make_material(color)
		var route: Array[MeshInstance3D] = []
		for _i: int in range(ROUTE_DASH_COUNT):
			var dash := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.22, 0.04, 0.6)
			dash.mesh = mesh
			dash.material_override = route_material
			add_child(dash)
			route.append(dash)
		_route_dashes[player_index] = route

		var name_label := Label3D.new()
		name_label.name = "P%dNameLabel" % player_index
		name_label.text = "P%d" % player_index
		name_label.font_size = 52
		name_label.pixel_size = 0.009
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.modulate = color
		name_label.outline_modulate = Color(0.02, 0.03, 0.08, 0.98)
		name_label.outline_size = 12
		name_label.no_depth_test = true
		add_child(name_label)
		_name_labels[player_index] = name_label

	_door_frame = Node3D.new()
	_door_frame.name = "CorrectDoorFrame"
	add_child(_door_frame)
	var frame_material := _make_material(ACCENT)
	for part_data: Dictionary in [
		{"size": Vector3(0.14, 3.8, 0.14), "position": Vector3(-1.8, 1.9, 0.0)},
		{"size": Vector3(0.14, 3.8, 0.14), "position": Vector3(1.8, 1.9, 0.0)},
		{"size": Vector3(3.74, 0.14, 0.14), "position": Vector3(0.0, 3.72, 0.0)},
	]:
		var part := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part_data["size"]
		part.mesh = box
		part.position = part_data["position"]
		part.material_override = frame_material
		_door_frame.add_child(part)

	_danger_stripe = MeshInstance3D.new()
	_danger_stripe.name = "OceanDangerStripe"
	var stripe := BoxMesh.new()
	stripe.size = Vector3(5.2, 0.05, 1.15)
	_danger_stripe.mesh = stripe
	_danger_stripe.material_override = _make_material(EDGE_COLOR)
	add_child(_danger_stripe)

	_target_ring = MeshInstance3D.new()
	_target_ring.name = "GhostTargetRing"
	var target_torus := TorusMesh.new()
	target_torus.inner_radius = 1.20
	target_torus.outer_radius = 1.52
	target_torus.rings = 32
	target_torus.ring_segments = 6
	_target_ring.mesh = target_torus
	_target_ring.material_override = _make_material(EDGE_COLOR)
	add_child(_target_ring)

	_goal_beacon = MeshInstance3D.new()
	_goal_beacon.name = "GoalBeacon"
	var beacon := CylinderMesh.new()
	beacon.top_radius = 0.10
	beacon.bottom_radius = 0.60
	beacon.height = 7.5
	_goal_beacon.mesh = beacon
	_goal_beacon.material_override = _make_material(GOAL_COLOR)
	add_child(_goal_beacon)

	_label = Label3D.new()
	_label.name = "DuoGuideLabel"
	_label.font_size = 46
	_label.pixel_size = 0.008
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = ACCENT
	_label.outline_modulate = Color(0.02, 0.03, 0.08, 0.96)
	_label.outline_size = 10
	_label.no_depth_test = true
	add_child(_label)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	_materials.append(material)
	return material


# ---------- 更新 ----------

## 走路の左右エッジを流れるラインで示す。ここから外は海、という境界を常時可視化する。
func _update_edge_lines(guide: String, pulse: float) -> void:
	var strong := guide == DuoFlow.GUIDE_OCEAN
	var base_y := StageConstants.FLOOR_TOP_Y + FLOOR_OFFSET
	var half_width := StageConstants.FLOOR_HALF_WIDTH
	var span := float(EDGE_DASH_COUNT) * EDGE_DASH_SPACING
	var flow := fmod(_time * EDGE_FLOW_SPEED, EDGE_DASH_SPACING)
	var origin_z := _view_center_z() - span * 0.32
	var width_scale := 1.6 if strong else 1.0
	var length_scale := 1.0 + (pulse * 0.35 if strong else 0.0)
	for i: int in range(_edge_dashes.size()):
		var dash := _edge_dashes[i]
		var side := 1.0 if i < EDGE_DASH_COUNT else -1.0
		var slot := i % EDGE_DASH_COUNT
		dash.visible = true
		dash.position = Vector3(
			side * half_width,
			base_y,
			origin_z + float(slot) * EDGE_DASH_SPACING + flow
		)
		dash.scale = Vector3(width_scale, 1.0, length_scale)


## 足元のリングと、進むべき方向を指すシェブロン3枚をプレイヤー別に出す。
func _update_player_guide(
		player_index: int, model: Dictionary, guide: String, pulse: float) -> void:
	var ring: MeshInstance3D = _rings[player_index]
	var chevrons: Array = _chevrons[player_index]
	var show_player_guide := (
		_is_player_active(player_index)
		and guide in [
			DuoFlow.GUIDE_LANE,
			DuoFlow.GUIDE_AIR,
			DuoFlow.GUIDE_EMOTE,
			DuoFlow.GUIDE_OCEAN,
			DuoFlow.GUIDE_GOAL,
		]
	)
	ring.visible = show_player_guide
	if not show_player_guide:
		for chevron_variant: Variant in chevrons:
			(chevron_variant as MeshInstance3D).visible = false
		return
	var base_y := StageConstants.FLOOR_TOP_Y + FLOOR_OFFSET
	var player_position := _player_position(player_index)
	ring.position = Vector3(player_position.x, base_y, player_position.z)
	ring.scale = Vector3.ONE * (1.0 + pulse * 0.08)

	# 誘導が必要ないステップではシェブロンを出さず、足元リングだけで所在を示す。
	var pending := _first_pending_task(model, player_index)
	var show_chevrons := guide != DuoFlow.GUIDE_EMOTE and (
		guide != DuoFlow.GUIDE_OCEAN or _hazard_player() == player_index
	)
	var yaw := _pending_direction_yaw(player_index, pending, guide)
	for i: int in range(chevrons.size()):
		var chevron := chevrons[i] as MeshInstance3D
		chevron.visible = show_chevrons
		if not show_chevrons:
			continue
		var direction := Vector3(sin(yaw), 0.0, cos(yaw))
		chevron.position = (
			Vector3(player_position.x, base_y, player_position.z)
			+ direction * (1.7 + float(i) * 1.05)
		)
		chevron.rotation = Vector3(PI * 0.5, yaw, 0.0)
		# 手前から奥へ順に光らせて進行方向を伝える。
		var wave := fmod(_time * 2.2 - float(i) * 0.28, 1.0)
		chevron.scale = Vector3.ONE * (0.85 + 0.3 * (1.0 - absf(wave * 2.0 - 1.0)))


func _pending_direction_yaw(player_index: int, pending_task: String, guide: String) -> float:
	if guide == DuoFlow.GUIDE_OCEAN:
		# 近い方の端へ誘導する。左右どちらから落ちてもよい。
		return PI * 0.5 if _player_position(player_index).x >= 0.0 else -PI * 0.5
	match pending_task:
		"left":
			return PI * 0.5
		"right":
			return -PI * 0.5
		"back":
			return PI
	return 0.0


## どちらがP1でどちらがP2かを覚えてもらうため、操作練習中は頭上に名前を出す。
func _update_name_labels(guide: String) -> void:
	var show_names := guide in [DuoFlow.GUIDE_LANE, DuoFlow.GUIDE_AIR, DuoFlow.GUIDE_EMOTE]
	for player_index: int in [1, 2]:
		var label: Label3D = _name_labels[player_index]
		label.visible = show_names and _is_player_active(player_index)
		if not label.visible:
			continue
		label.position = _player_position(player_index) + Vector3(0.0, 2.75, 0.0)


## 正解ドアの枠と、各プレイヤーからそこへ繋がる床のルートライン。
func _update_door_guide(model: Dictionary, guide: String, pulse: float) -> void:
	var answer := int(model.get("highlight_answer", -1))
	var show_door := guide == DuoFlow.GUIDE_GUIDED_DOOR and answer in [0, 1]
	_door_frame.visible = show_door
	if not show_door:
		for player_index: int in [1, 2]:
			_hide_route(player_index)
		return
	var door_x: float = (
		game_state.tuning.left_door_x if answer == 0 else game_state.tuning.right_door_x
	)
	var wall_local_z := game_state.wall_z - game_state.world_scroll_z
	var base_y := StageConstants.FLOOR_TOP_Y + FLOOR_OFFSET
	_door_frame.position = Vector3(door_x, StageConstants.FLOOR_TOP_Y, wall_local_z - 0.5)
	_door_frame.scale = Vector3.ONE * (1.0 + pulse * 0.04)

	for player_index: int in [1, 2]:
		if not _is_player_active(player_index):
			_hide_route(player_index)
			continue
		var player_position := _player_position(player_index)
		var start := Vector3(player_position.x, base_y, player_position.z + 0.6)
		var end := Vector3(door_x, base_y, wall_local_z - 0.6)
		var delta := end - start
		if delta.length() < 0.5:
			_hide_route(player_index)
			continue
		var yaw := atan2(delta.x, delta.z)
		var dashes: Array = _route_dashes[player_index]
		for i: int in range(dashes.size()):
			var dash := dashes[i] as MeshInstance3D
			var t := (float(i) + 0.5) / float(dashes.size())
			dash.visible = true
			dash.position = start.lerp(end, t)
			dash.rotation = Vector3(0.0, yaw, 0.0)
			# 手前から奥へ流れる明滅でドアまでの経路を示す。
			var wave := fmod(_time * 1.6 - t, 1.0)
			dash.scale = Vector3.ONE * (0.7 + 0.6 * (1.0 - absf(wave * 2.0 - 1.0)))


func _hide_route(player_index: int) -> void:
	for dash_variant: Variant in _route_dashes[player_index]:
		(dash_variant as MeshInstance3D).visible = false


## 海へ落ちるステップでは、指定プレイヤー側の端に危険ストライプを敷く。
func _update_hazard_guide(guide: String, pulse: float) -> void:
	_danger_stripe.visible = guide == DuoFlow.GUIDE_OCEAN
	if not _danger_stripe.visible:
		return
	var hazard_player := maxi(1, _hazard_player())
	var player_position := _player_position(hazard_player)
	var side := 1.0 if player_position.x >= 0.0 else -1.0
	_danger_stripe.position = Vector3(
		side * StageConstants.FLOOR_HALF_WIDTH,
		StageConstants.FLOOR_TOP_Y + 0.05,
		player_position.z + 1.6
	)
	_danger_stripe.rotation.y = PI * 0.5
	_danger_stripe.scale = Vector3.ONE * (1.0 + pulse * 0.07)


## ゴーストシャークの狙う相手を足元リングで示す。
func _update_ghost_target(guide: String, pulse: float) -> void:
	var ghost_player := int(game_state.get_tutorial_ghost_player())
	var target_player := 2 if ghost_player == 1 else 1
	_target_ring.visible = (
		guide == DuoFlow.GUIDE_GHOST
		and ghost_player > 0
		and _is_player_active(target_player)
	)
	if not _target_ring.visible:
		return
	var target_position := _player_position(target_player)
	_target_ring.position = Vector3(
		target_position.x,
		StageConstants.FLOOR_TOP_Y + FLOOR_OFFSET,
		target_position.z
	)
	_target_ring.scale = Vector3.ONE * (1.0 + pulse * 0.16)


func _update_goal_guide(guide: String, pulse: float) -> void:
	_goal_beacon.visible = guide in [DuoFlow.GUIDE_GOAL, DuoFlow.GUIDE_COMPLETE]
	if not _goal_beacon.visible:
		return
	var goal_z := game_state.goal_z - game_state.world_scroll_z
	_goal_beacon.position = Vector3(0.0, 2.5 + pulse * 0.35, goal_z)
	_goal_beacon.scale = Vector3(1.0 + pulse * 0.10, 1.0, 1.0 + pulse * 0.10)


func _update_label(model: Dictionary, guide: String) -> void:
	var base_y := StageConstants.FLOOR_TOP_Y
	match guide:
		DuoFlow.GUIDE_OCEAN:
			var hazard_player := maxi(1, _hazard_player())
			var hazard_position := _player_position(hazard_player)
			var side := 1.0 if hazard_position.x >= 0.0 else -1.0
			_label.text = "この先は海"
			_label.modulate = EDGE_COLOR
			_label.position = Vector3(
				side * StageConstants.FLOOR_HALF_WIDTH,
				base_y + 2.6,
				hazard_position.z + 2.0
			)
		DuoFlow.GUIDE_GHOST:
			if not _target_ring.visible:
				_label.visible = false
				return
			_label.text = "この相手を狙う"
			_label.modulate = EDGE_COLOR
			_label.position = _target_ring.position + Vector3(0.0, 3.4, 0.0)
		DuoFlow.GUIDE_GUIDED_DOOR:
			if int(model.get("highlight_answer", -1)) not in [0, 1]:
				_label.visible = false
				return
			_label.text = "正解ドア"
			_label.modulate = ACCENT
			_label.position = _door_frame.position + Vector3(0.0, 4.6, 0.0)
		DuoFlow.GUIDE_GOAL, DuoFlow.GUIDE_COMPLETE:
			_label.text = "GOAL"
			_label.modulate = GOAL_COLOR
			_label.position = Vector3(0.0, 6.1, game_state.goal_z - game_state.world_scroll_z)
		_:
			_label.visible = false
			return
	_label.visible = true


# ---------- 参照ヘルパー ----------

func _player_color(player_index: int) -> Color:
	return P1_COLOR if player_index == 1 else P2_COLOR


func _player_position(player_index: int) -> Vector3:
	if player_index == 2:
		return Vector3(game_state.player2_x, game_state.player2_y, game_state.player2_local_z)
	return Vector3(game_state.player_x, game_state.player_y, game_state.player_local_z)


## 脱落中や海で待機中のプレイヤーには床ガイドを出さない。
func _is_player_active(player_index: int) -> bool:
	if player_index == 2:
		return game_state.p2_alive and not game_state.p2_waiting_for_shark
	return game_state.p1_alive and not game_state.p1_waiting_for_shark


func _hazard_player() -> int:
	if game_state.tutorial_flow == null:
		return 0
	return int(game_state.tutorial_flow.designated_hazard_player())


## エッジラインの基準。2人の中間を使い、片方が脱落しても生存側に寄せる。
func _view_center_z() -> float:
	var p1_active := _is_player_active(1)
	var p2_active := _is_player_active(2)
	if p1_active and p2_active:
		return (game_state.player_local_z + game_state.player2_local_z) * 0.5
	if p2_active:
		return game_state.player2_local_z
	return game_state.player_local_z


func _first_pending_task(model: Dictionary, player_index: int) -> String:
	for player_variant: Variant in model.get("players", []):
		var player: Dictionary = player_variant
		if int(player.get("player", 0)) != player_index:
			continue
		for task_variant: Variant in player.get("tasks", []):
			var task: Dictionary = task_variant
			if not bool(task.get("done", false)):
				return str(task.get("id", ""))
	return ""
