extends Node3D
class_name SoloTutorialGuides

## 1Pチュートリアル専用の3Dガイド。
## リング・板ポリ矢印・円柱が寄せ集めだった従来版に対し、
## ここでは全パーツを同じ加算発光マテリアル工場から作り、
## 明滅も1つの脈動値で揃える。
## ローカル2Pコースは res://scripts/world/duo_tutorial_guides.gd が担当する。

const SoloFlow = preload("res://scripts/core/tutorial/solo_tutorial_flow.gd")

const ACCENT := Color(1.0, 0.82, 0.24, 1.0)
const EDGE_COLOR := Color(1.0, 0.32, 0.26, 1.0)
const GOAL_COLOR := Color(0.36, 1.0, 0.62, 1.0)

const EDGE_DASH_COUNT := 16
const EDGE_DASH_SPACING := 3.4
const EDGE_FLOW_SPEED := 7.0
const ROUTE_DASH_COUNT := 12
const CHEVRON_COUNT := 3
const FLOOR_OFFSET := 0.06

var game_state: QuizGameState = null

var _time: float = 0.0
var _materials: Array[StandardMaterial3D] = []
var _edge_dashes: Array[MeshInstance3D] = []
var _ring: MeshInstance3D = null
var _chevrons: Array[MeshInstance3D] = []
var _route_dashes: Array[MeshInstance3D] = []
var _door_frame: Node3D = null
var _goal_beacon: MeshInstance3D = null
var _label: Label3D = null


func setup(state: QuizGameState) -> void:
	game_state = state
	_build()


func update(delta: float) -> void:
	_time += delta
	if game_state == null or not game_state.is_solo_tutorial():
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
	_update_player_guide(model, guide, pulse)
	_update_door_guide(model, guide, pulse)
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

	_ring = MeshInstance3D.new()
	_ring.name = "PlayerFloorRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.78
	torus.outer_radius = 0.98
	torus.rings = 32
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.material_override = _make_material(ACCENT)
	add_child(_ring)

	var chevron_material := _make_material(ACCENT)
	for _i: int in range(CHEVRON_COUNT):
		var chevron := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(1.15, 0.9, 0.05)
		chevron.mesh = prism
		chevron.material_override = chevron_material
		# 三角形を床に寝かせ、頂点が +Z（進行方向）を向くようにする。
		chevron.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		add_child(chevron)
		_chevrons.append(chevron)

	var route_material := _make_material(ACCENT)
	for _i: int in range(ROUTE_DASH_COUNT):
		var dash := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.22, 0.04, 0.6)
		dash.mesh = mesh
		dash.material_override = route_material
		add_child(dash)
		_route_dashes.append(dash)

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
	_label.name = "SoloGuideLabel"
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
	var strong := guide == SoloFlow.GUIDE_OCEAN
	var base_y := StageConstants.FLOOR_TOP_Y + FLOOR_OFFSET
	var half_width := StageConstants.FLOOR_HALF_WIDTH
	var span := float(EDGE_DASH_COUNT) * EDGE_DASH_SPACING
	var flow := fmod(_time * EDGE_FLOW_SPEED, EDGE_DASH_SPACING)
	var origin_z := game_state.player_local_z - span * 0.32
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


## 足元のリングと、進むべき方向を指すシェブロン3枚。
func _update_player_guide(model: Dictionary, guide: String, pulse: float) -> void:
	var show_player_guide := guide in [
		SoloFlow.GUIDE_LANE,
		SoloFlow.GUIDE_AIR,
		SoloFlow.GUIDE_OCEAN,
		SoloFlow.GUIDE_COMPLETE,
	]
	_ring.visible = show_player_guide
	if not show_player_guide:
		for chevron: MeshInstance3D in _chevrons:
			chevron.visible = false
		return
	var base_y := StageConstants.FLOOR_TOP_Y + FLOOR_OFFSET
	var player_x := game_state.player_x
	var player_z := game_state.player_local_z
	_ring.position = Vector3(player_x, base_y, player_z)
	_ring.scale = Vector3.ONE * (1.0 + pulse * 0.08)

	var yaw := _pending_direction_yaw(model, guide)
	var direction := Vector3(sin(yaw), 0.0, cos(yaw))
	for i: int in range(_chevrons.size()):
		var chevron := _chevrons[i]
		chevron.visible = true
		chevron.position = (
			Vector3(player_x, base_y, player_z) + direction * (1.7 + float(i) * 1.05)
		)
		chevron.rotation = Vector3(PI * 0.5, yaw, 0.0)
		# 手前から奥へ順に光らせて進行方向を伝える。
		var wave := fmod(_time * 2.2 - float(i) * 0.28, 1.0)
		chevron.scale = Vector3.ONE * (0.85 + 0.3 * (1.0 - absf(wave * 2.0 - 1.0)))


func _pending_direction_yaw(model: Dictionary, guide: String) -> float:
	if guide == SoloFlow.GUIDE_OCEAN:
		# 近い方の端へ誘導する。左右どちらから落ちてもよい。
		return PI * 0.5 if game_state.player_x >= 0.0 else -PI * 0.5
	match _first_pending_task(model):
		"left":
			return PI * 0.5
		"right":
			return -PI * 0.5
		"back":
			return PI
	return 0.0


## 正解ドアの枠と、そこへ繋がる床のルートライン。
func _update_door_guide(model: Dictionary, guide: String, pulse: float) -> void:
	var answer := int(model.get("highlight_answer", -1))
	var show_door := guide == SoloFlow.GUIDE_GUIDED_DOOR and answer in [0, 1]
	_door_frame.visible = show_door
	if not show_door:
		for dash: MeshInstance3D in _route_dashes:
			dash.visible = false
		return
	var door_x: float = (
		game_state.tuning.left_door_x if answer == 0 else game_state.tuning.right_door_x
	)
	var wall_local_z := game_state.wall_z - game_state.world_scroll_z
	var base_y := StageConstants.FLOOR_TOP_Y + FLOOR_OFFSET
	_door_frame.position = Vector3(door_x, StageConstants.FLOOR_TOP_Y, wall_local_z - 0.5)
	_door_frame.scale = Vector3.ONE * (1.0 + pulse * 0.04)

	var start := Vector3(game_state.player_x, base_y, game_state.player_local_z + 0.6)
	var end := Vector3(door_x, base_y, wall_local_z - 0.6)
	var delta := end - start
	var distance := delta.length()
	if distance < 0.5:
		for dash: MeshInstance3D in _route_dashes:
			dash.visible = false
		return
	var yaw := atan2(delta.x, delta.z)
	for i: int in range(_route_dashes.size()):
		var dash := _route_dashes[i]
		var t := (float(i) + 0.5) / float(_route_dashes.size())
		dash.visible = true
		dash.position = start.lerp(end, t)
		dash.rotation = Vector3(0.0, yaw, 0.0)
		# 手前から奥へ流れる明滅でドアまでの経路を示す。
		var wave := fmod(_time * 1.6 - t, 1.0)
		dash.scale = Vector3.ONE * (0.7 + 0.6 * (1.0 - absf(wave * 2.0 - 1.0)))


func _update_goal_guide(guide: String, pulse: float) -> void:
	_goal_beacon.visible = guide == SoloFlow.GUIDE_GOAL
	if not _goal_beacon.visible:
		return
	var goal_z := game_state.goal_z - game_state.world_scroll_z
	_goal_beacon.position = Vector3(0.0, 2.5 + pulse * 0.35, goal_z)
	_goal_beacon.scale = Vector3(1.0 + pulse * 0.10, 1.0, 1.0 + pulse * 0.10)


func _update_label(model: Dictionary, guide: String) -> void:
	var base_y := StageConstants.FLOOR_TOP_Y
	match guide:
		SoloFlow.GUIDE_OCEAN:
			var side := 1.0 if game_state.player_x >= 0.0 else -1.0
			_label.text = "この先は海"
			_label.modulate = EDGE_COLOR
			_label.position = Vector3(
				side * StageConstants.FLOOR_HALF_WIDTH,
				base_y + 2.6,
				game_state.player_local_z + 2.0
			)
		SoloFlow.GUIDE_GUIDED_DOOR:
			if int(model.get("highlight_answer", -1)) not in [0, 1]:
				_label.visible = false
				return
			_label.text = "正解ドア"
			_label.modulate = ACCENT
			_label.position = _door_frame.position + Vector3(0.0, 4.6, 0.0)
		SoloFlow.GUIDE_GOAL:
			_label.text = "GOAL"
			_label.modulate = GOAL_COLOR
			_label.position = Vector3(0.0, 6.1, game_state.goal_z - game_state.world_scroll_z)
		_:
			_label.visible = false
			return
	_label.visible = true


func _first_pending_task(model: Dictionary) -> String:
	for task_variant: Variant in model.get("tasks", []):
		var task: Dictionary = task_variant
		if not bool(task.get("done", false)):
			return str(task.get("id", ""))
	return ""
