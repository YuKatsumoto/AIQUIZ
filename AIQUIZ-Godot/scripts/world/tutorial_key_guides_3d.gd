extends Node3D
class_name TutorialKeyGuides3D

## チュートリアル中の操作キーを3D空間に浮かべる。
## 1P/2Pの3Dガイド（solo_tutorial_guides.gd / duo_tutorial_guides.gd）が子として持ち、毎フレーム update() を呼ぶ。
##
## 表示するキーはチュートリアルのUIモデル（各タスクの "slots"）と、ステップの "key_layout" から決める。
## - "cluster": 頭上に実キーボードと同じ並び（P1 = W/A S D + Space、P2 = ↑/← ↓ → + 右Ctrl）の小さなキーボード片。
## - "sides": 走りながら左右を選ぶステップ用。キャラクターの左右の肩の横に、動く向きのキーを1個ずつ。
## - "ghost": 脱落したプレイヤーが操るゴーストシャークの上にキーボード片。
## 押すべきキーはプレイヤー色で光り、実際の入力でだけ沈み、達成すると緑になる。
## チュートリアルが勝手にキーを押す演出は持たない（開始前のキーボード説明と同じ方針）。
## 2人のキーボード片が重なるときは左右へ押し広げ、画面の外へはみ出す分は内側へ寄せる。

const KeycapScript = preload("res://scripts/world/tutorial_keycap_3d.gd")
const LEGEND_FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")

const LAYOUT_NONE := ""
const LAYOUT_CLUSTER := "cluster"
const LAYOUT_SIDES := "sides"
const LAYOUT_GHOST := "ghost"

const SLOT_LEFT := "left"
const SLOT_RIGHT := "right"
const SLOT_UP := "up"
const SLOT_DOWN := "down"
const SLOT_JUMP := "jump"
const SLOT_EMOTE_1 := "emote_1"
const SLOT_EMOTE_2 := "emote_2"
const SLOT_EMOTE_3 := "emote_3"
const MOVE_SLOTS := [SLOT_LEFT, SLOT_RIGHT, SLOT_UP, SLOT_DOWN]
const EMOTE_SLOTS := [SLOT_EMOTE_1, SLOT_EMOTE_2, SLOT_EMOTE_3]

## 実行時に向きが決まるスロット。
const DYNAMIC_EDGE := "toward_edge"
const DYNAMIC_DOOR := "toward_door"
const DYNAMIC_OPPONENT := "toward_opponent"

const P1_COLOR := Color("ffa440")
const P2_COLOR := Color("51d8ec")

## キーボード片の配置（キー単位。x は画面右、y は画面下）。
const P1_CLUSTER := {
	SLOT_UP: Vector2(0.0, -1.0),
	SLOT_LEFT: Vector2(-1.0, 0.0),
	SLOT_DOWN: Vector2(0.0, 0.0),
	SLOT_RIGHT: Vector2(1.0, 0.0),
	SLOT_JUMP: Vector2(0.0, 1.12),
	SLOT_EMOTE_1: Vector2(-1.0, 0.0),
	SLOT_EMOTE_2: Vector2(0.0, 0.0),
	SLOT_EMOTE_3: Vector2(1.0, 0.0),
}
## 右Ctrlは実キーボードと同じく ← の左隣に置く。
const P2_CLUSTER := {
	SLOT_UP: Vector2(0.0, -1.0),
	SLOT_LEFT: Vector2(-1.0, 0.0),
	SLOT_DOWN: Vector2(0.0, 0.0),
	SLOT_RIGHT: Vector2(1.0, 0.0),
	SLOT_JUMP: Vector2(-2.42, 0.0),
	SLOT_EMOTE_1: Vector2(-1.0, 0.0),
	SLOT_EMOTE_2: Vector2(0.0, 0.0),
	SLOT_EMOTE_3: Vector2(1.0, 0.0),
}
const KEY_PITCH := 1.06

## 1Pコースのカメラは近いので小さめ、2Pは引きのカメラなので大きめにする。
const SOLO_CLUSTER_SCALE := 0.47
const DUO_CLUSTER_SCALE := 0.62
const SOLO_SIDE_SCALE := 0.38
const DUO_SIDE_SCALE := 0.54
const GHOST_CLUSTER_SCALE := 0.80
## 頭頂（原点から約0.9m）より上に置くキーボード片の下端。
const SOLO_CLUSTER_BASE_Y := 1.32
const DUO_CLUSTER_BASE_Y := 1.42
const SOLO_SIDE_OFFSET := Vector3(1.02, 0.42, 0.0)
const DUO_SIDE_OFFSET := Vector3(1.12, 0.55, 0.0)
const GHOST_BASE_Y := 2.6
## 2人のキーボード片の間に空ける最小の隙間（m）。
const CLUSTER_GAP := 0.32
## 画面の縁から空ける余白（px）。2Pは上端にコーチバーがあるので広めに取る。
const SCREEN_MARGIN := 28.0
const DUO_TOP_MARGIN := 128.0
## 天面をカメラへどれだけ向けるか（0 = 真上、1 = カメラ正対）。少し寝かせて立体感を残す。
const FACE_CAMERA := 0.62
const FOLLOW_RATE := 14.0

var game_state: QuizGameState = null
var duo: bool = false

var _rigs: Dictionary = {}
var _right_ctrl_down: bool = false
var _solo_uses_arrows: bool = false


func setup(state: QuizGameState, is_duo: bool) -> void:
	game_state = state
	duo = is_duo
	for player_index: int in ([1, 2] if duo else [1]):
		_rigs[player_index] = _build_rig(player_index)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if (key.keycode == KEY_CTRL or key.physical_keycode == KEY_CTRL) and key.location == KEY_LOCATION_RIGHT:
		_right_ctrl_down = key.pressed


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_right_ctrl_down = false


## model はチュートリアルのUIモデル。show は演出中・死亡演出中などに false。
## ghost_position はゴーストシャークを操作できる間だけ、そのサメの位置（なければ null）。
func update(delta: float, model: Dictionary, show: bool, ghost_position: Variant = null) -> void:
	var camera := get_viewport().get_camera_3d()
	var layout := str(model.get("key_layout", LAYOUT_NONE))
	_update_arrow_mode()
	var plans: Dictionary = {}
	for player_index: int in _rigs.keys():
		var tasks := _player_tasks(model, player_index)
		var player_layout := layout
		if layout == LAYOUT_GHOST and player_index != int(model.get("ghost_player", 0)):
			player_layout = LAYOUT_NONE
		var active := (
			show
			and camera != null
			and not tasks.is_empty()
			and _player_can_show(player_index, player_layout, ghost_position)
		)
		var states := _slot_states(player_index, tasks, player_layout, model) if active else {}
		(_rigs[player_index] as Dictionary)["layout"] = player_layout
		plans[player_index] = _plan(player_index, states, player_layout, camera, ghost_position)
	_separate_clusters(plans)
	for player_index: int in _rigs.keys():
		var plan: Dictionary = plans[player_index]
		if not plan.is_empty() and plan.get("layout", "") != LAYOUT_SIDES:
			plan["anchor"] = _clamp_into_view(plan, camera)
		_apply_rig(_rigs[player_index], player_index, plan, delta, camera)


## 検証用。各プレイヤーのキーの見え方を返す。
func get_evidence() -> Dictionary:
	var result := {}
	for player_index: int in _rigs.keys():
		var rig: Dictionary = _rigs[player_index]
		var keys := {}
		for slot: String in (rig["keys"] as Dictionary).keys():
			var key: TutorialKeycap3D = rig["keys"][slot]
			if key.is_fully_hidden():
				continue
			keys[slot] = {
				"legend": key.legend,
				"look": ["idle", "target", "done"][key.get_look()],
				"pressed": key.is_pressed(),
				"depth": key.press_depth(),
				"position": key.global_position,
				"visible": key.visible,
			}
		result["P%d" % player_index] = {"layout": str(rig.get("layout", "")), "keys": keys}
	return result


## カメラから見たキーの画面位置（検証・レイアウト確認用）。
func get_screen_points() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var result := {}
	if camera == null:
		return result
	for player_index: int in _rigs.keys():
		var rig: Dictionary = _rigs[player_index]
		for slot: String in (rig["keys"] as Dictionary).keys():
			var key: TutorialKeycap3D = rig["keys"][slot]
			if not key.visible or key.is_fully_hidden():
				continue
			result["P%d:%s" % [player_index, slot]] = camera.unproject_position(key.global_position)
	return result


# ---------- 構築 ----------

func _build_rig(player_index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "P%dKeys" % player_index
	add_child(root)
	var keys := {}
	var accent := P2_COLOR if player_index == 2 else P1_COLOR
	for slot: String in MOVE_SLOTS + [SLOT_JUMP] + EMOTE_SLOTS:
		var key: TutorialKeycap3D = KeycapScript.new()
		key.name = "%sKey" % slot.capitalize().replace(" ", "")
		root.add_child(key)
		var legend := _legend(player_index, slot)
		key.setup(legend[0], _slot_width(player_index, slot), accent, legend[1])
		key.set_shown(false, true)
		keys[slot] = key
	var tag := Label3D.new()
	tag.name = "PlayerTag"
	tag.font = LEGEND_FONT
	tag.text = "P%d" % player_index
	tag.font_size = 96
	tag.pixel_size = 0.0042
	tag.modulate = accent
	tag.outline_modulate = Color(0.02, 0.03, 0.08, 0.95)
	tag.outline_size = 18
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.render_priority = 3
	tag.visible = false
	root.add_child(tag)
	return {
		"root": root,
		"keys": keys,
		"tag": tag,
		"layout": LAYOUT_NONE,
		"anchor": Vector3.ZERO,
		"anchor_ready": false,
	}


func _legend(player_index: int, slot: String) -> Array:
	if player_index == 2:
		match slot:
			SLOT_LEFT: return ["←", ""]
			SLOT_RIGHT: return ["→", ""]
			SLOT_UP: return ["↑", ""]
			SLOT_DOWN: return ["↓", ""]
			SLOT_JUMP: return ["Ctrl", "右"]
			SLOT_EMOTE_1: return ["8", ""]
			SLOT_EMOTE_2: return ["9", ""]
			SLOT_EMOTE_3: return ["0", ""]
		return ["", ""]
	var arrows := not duo and _solo_uses_arrows
	match slot:
		SLOT_LEFT: return ["←" if arrows else "A", ""]
		SLOT_RIGHT: return ["→" if arrows else "D", ""]
		SLOT_UP: return ["↑" if arrows else "W", ""]
		SLOT_DOWN: return ["↓" if arrows else "S", ""]
		SLOT_JUMP: return ["Space", ""]
		SLOT_EMOTE_1: return ["1", ""]
		SLOT_EMOTE_2: return ["2", ""]
		SLOT_EMOTE_3: return ["3", ""]
	return ["", ""]


func _slot_width(player_index: int, slot: String) -> float:
	if slot != SLOT_JUMP:
		return 1.0
	return 1.5 if player_index == 2 else 3.0


# ---------- 状態 ----------

## 1Pでは矢印キーでも動ける。実際に使ったほうのキーを刻印に出す。
func _update_arrow_mode() -> void:
	if duo:
		return
	var uses_arrows := _solo_uses_arrows
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN):
		uses_arrows = true
	elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S):
		uses_arrows = false
	if uses_arrows == _solo_uses_arrows:
		return
	_solo_uses_arrows = uses_arrows
	var rig: Dictionary = _rigs.get(1, {})
	if rig.is_empty():
		return
	for slot: String in MOVE_SLOTS:
		var legend := _legend(1, slot)
		(rig["keys"][slot] as TutorialKeycap3D).set_legend(legend[0], legend[1])


func is_solo_arrow_mode() -> bool:
	return _solo_uses_arrows


func _player_tasks(model: Dictionary, player_index: int) -> Array:
	for player_variant: Variant in model.get("players", []):
		var player: Dictionary = player_variant
		if int(player.get("player", 0)) == player_index:
			return player.get("tasks", [])
	if player_index == 1:
		return model.get("tasks", [])
	return []


func _player_can_show(player_index: int, layout: String, ghost_position: Variant) -> bool:
	if layout == LAYOUT_NONE:
		return false
	if layout == LAYOUT_GHOST:
		return ghost_position is Vector3
	if player_index == 2:
		return game_state.p2_alive and not game_state.p2_waiting_for_shark and not game_state.p2_fall_committed
	return game_state.p1_alive and not game_state.p1_waiting_for_shark and not game_state.p1_fall_committed


## スロット → {"look", "pressed"}。表示しないスロットは含めない。
func _slot_states(player_index: int, tasks: Array, layout: String, model: Dictionary) -> Dictionary:
	var target_slots := {}
	var waiting_slots := {}
	var done_slots := {}
	var any_move := false
	# 順番があるステップ（踏ん張り→押す、後退→前進）では、最初の未達成タスクのキーだけを光らせる。
	var ordered := bool(model.get("ordered_tasks", false))
	var first_pending_seen := false
	for task_variant: Variant in tasks:
		var task: Dictionary = task_variant
		var done := bool(task.get("done", false))
		var waiting := false
		if not done:
			waiting = ordered and first_pending_seen
			first_pending_seen = true
		for slot: String in _resolve_slots(player_index, task, model):
			if slot in MOVE_SLOTS:
				any_move = true
			if done:
				done_slots[slot] = true
			elif waiting:
				waiting_slots[slot] = true
			else:
				target_slots[slot] = true
	var shown := {}
	for slot: String in target_slots.keys():
		shown[slot] = TutorialKeycap3D.Look.TARGET
	for slot: String in done_slots.keys():
		if not shown.has(slot):
			shown[slot] = TutorialKeycap3D.Look.DONE
	for slot: String in waiting_slots.keys():
		if not shown.has(slot):
			shown[slot] = TutorialKeycap3D.Look.IDLE
	# 移動キーはキーボードの並び（W / A S D）が分かるよう4個そろえて出す。
	if any_move and layout in [LAYOUT_CLUSTER, LAYOUT_GHOST]:
		for slot: String in MOVE_SLOTS:
			if not shown.has(slot):
				shown[slot] = TutorialKeycap3D.Look.IDLE
	if layout == LAYOUT_SIDES:
		# 肩の横には左右キーだけを置く。押す向きが無いときも左右の対応は見せておく。
		for slot: String in shown.keys():
			if slot not in [SLOT_LEFT, SLOT_RIGHT]:
				shown.erase(slot)
		for slot: String in [SLOT_LEFT, SLOT_RIGHT]:
			if not shown.has(slot):
				shown[slot] = TutorialKeycap3D.Look.IDLE
	var result := {}
	for slot: String in shown.keys():
		result[slot] = {"look": shown[slot], "pressed": _is_slot_pressed(player_index, slot)}
	return result


func _resolve_slots(player_index: int, task: Dictionary, model: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in task.get("slots", []):
		var slot := str(raw)
		match slot:
			DYNAMIC_EDGE:
				var x := _player_position(player_index).x
				# 画面左（+X）側の端に近ければ左移動キー。
				out.append(SLOT_LEFT if x >= 0.0 else SLOT_RIGHT)
			DYNAMIC_DOOR:
				# 目標のドア（誘導中の正解ドア、ハート体験の不正解ドア）があれば、その向きのキーだけを光らせる。
				var target_door := int(model.get("target_door", -1))
				if target_door < 0:
					continue
				var dx := _door_x(target_door) - _player_position(player_index).x
				if absf(dx) > 0.45:
					out.append(SLOT_LEFT if dx > 0.0 else SLOT_RIGHT)
			DYNAMIC_OPPONENT:
				var other := 3 - player_index
				out.append(SLOT_LEFT if _player_position(other).x > _player_position(player_index).x else SLOT_RIGHT)
			_:
				out.append(slot)
	return out


func _is_slot_pressed(player_index: int, slot: String) -> bool:
	if player_index == 2:
		match slot:
			SLOT_LEFT: return Input.is_key_pressed(KEY_LEFT)
			SLOT_RIGHT: return Input.is_key_pressed(KEY_RIGHT)
			SLOT_UP: return Input.is_key_pressed(KEY_UP)
			SLOT_DOWN: return Input.is_key_pressed(KEY_DOWN)
			SLOT_JUMP: return _right_ctrl_down and Input.is_key_pressed(KEY_CTRL)
			SLOT_EMOTE_1: return Input.is_key_pressed(KEY_8) or Input.is_key_pressed(KEY_KP_7)
			SLOT_EMOTE_2: return Input.is_key_pressed(KEY_9) or Input.is_key_pressed(KEY_KP_8)
			SLOT_EMOTE_3: return Input.is_key_pressed(KEY_0) or Input.is_key_pressed(KEY_KP_9)
		return false
	var solo := not duo
	match slot:
		SLOT_LEFT: return Input.is_key_pressed(KEY_A) or (solo and Input.is_key_pressed(KEY_LEFT))
		SLOT_RIGHT: return Input.is_key_pressed(KEY_D) or (solo and Input.is_key_pressed(KEY_RIGHT))
		SLOT_UP: return Input.is_key_pressed(KEY_W) or (solo and Input.is_key_pressed(KEY_UP))
		SLOT_DOWN: return Input.is_key_pressed(KEY_S) or (solo and Input.is_key_pressed(KEY_DOWN))
		SLOT_JUMP: return Input.is_key_pressed(KEY_SPACE)
		SLOT_EMOTE_1: return Input.is_key_pressed(KEY_1)
		SLOT_EMOTE_2: return Input.is_key_pressed(KEY_2)
		SLOT_EMOTE_3: return Input.is_key_pressed(KEY_3)
	return false


# ---------- 配置 ----------

## 1人分の配置案。表示しないときは空。
## anchor はキーボード片の下端中央（肩の横に並べるときはキャラクターの立ち位置）。
func _plan(player_index: int, states: Dictionary, layout: String, camera: Camera3D, ghost_position: Variant) -> Dictionary:
	if states.is_empty() or camera == null:
		return {}
	# ジャンプで上下しないよう、走路上の立ち位置（原点の高さ）を基準にする。
	var standing := _player_position(player_index)
	var base := Vector3(standing.x, 0.0, standing.z)
	if layout == LAYOUT_GHOST and ghost_position is Vector3:
		base = ghost_position
	var scale_factor := _layout_scale(layout)
	var plan := {
		"layout": layout,
		"states": states,
		"anchor": _layout_anchor(base, layout),
		"scale": scale_factor,
		"bounds": Rect2(),
	}
	if layout == LAYOUT_SIDES:
		return plan
	var keys: Dictionary = (_rigs[player_index] as Dictionary)["keys"]
	var cells := P2_CLUSTER if player_index == 2 else P1_CLUSTER
	var bounds := Rect2()
	var first := true
	for slot: String in states.keys():
		var key: TutorialKeycap3D = keys[slot]
		var center: Vector2 = cells[slot]
		var half := Vector2(key.footprint_width() * 0.5, 0.5)
		var rect := Rect2(center - half, half * 2.0)
		bounds = rect if first else bounds.merge(rect)
		first = false
	plan["bounds"] = bounds
	return plan


## 2人のキーボード片が横に重なるなら、中点を保ったまま左右へ押し広げる。
## カメラは +Z を向くので、ワールドの +X が画面の左になる。
func _separate_clusters(plans: Dictionary) -> void:
	if not duo:
		return
	var p1: Dictionary = plans.get(1, {})
	var p2: Dictionary = plans.get(2, {})
	if p1.is_empty() or p2.is_empty():
		return
	if p1.get("layout", "") != LAYOUT_CLUSTER or p2.get("layout", "") != LAYOUT_CLUSTER:
		return
	var a1: Vector3 = p1["anchor"]
	var a2: Vector3 = p2["anchor"]
	var half1 := _cluster_half_width(p1)
	var half2 := _cluster_half_width(p2)
	var needed := half1 + half2 + CLUSTER_GAP
	var gap := absf(a1.x - a2.x)
	if gap >= needed:
		return
	var middle := (a1.x + a2.x) * 0.5
	# 同じ位置に重なったときは、本来の立ち位置（P1が画面左）を保つ。
	var p1_on_left := a1.x > a2.x or (is_equal_approx(a1.x, a2.x) and game_state.player_x >= game_state.player2_x)
	var offset := needed * 0.5
	a1.x = middle + (offset if p1_on_left else -offset)
	a2.x = middle - (offset if p1_on_left else -offset)
	p1["anchor"] = a1
	p2["anchor"] = a2


func _cluster_half_width(plan: Dictionary) -> float:
	var bounds: Rect2 = plan.get("bounds", Rect2())
	# プレイヤー名の札がキーボード片の左上へはみ出す分も含める。
	return (bounds.size.x * 0.5 + 0.35) * KEY_PITCH * float(plan.get("scale", 1.0))


## キーボード片が画面の外へはみ出さないよう、カメラ平面上で内側へ寄せる。
func _clamp_into_view(plan: Dictionary, camera: Camera3D) -> Vector3:
	var anchor: Vector3 = plan["anchor"]
	if camera == null or camera.is_position_behind(anchor):
		return anchor
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return anchor
	# 透視投影の拡大率は直線距離ではなく、視線方向の奥行きで決まる（画面端ほど差が大きい）。
	var depth := maxf(0.5, (anchor - camera.global_position).dot(-camera.global_basis.z))
	var world_per_px := 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / viewport_size.y
	var bounds: Rect2 = plan.get("bounds", Rect2())
	var scale_factor := float(plan.get("scale", 1.0))
	var half_width_px := (bounds.size.x * 0.5 + 0.35) * KEY_PITCH * scale_factor / world_per_px
	var height_px := (bounds.size.y + 0.6) * KEY_PITCH * scale_factor / world_per_px
	var point := camera.unproject_position(anchor)
	var top_margin := DUO_TOP_MARGIN if duo else SCREEN_MARGIN
	var shift := Vector2.ZERO
	if point.x - half_width_px < SCREEN_MARGIN:
		shift.x = SCREEN_MARGIN - (point.x - half_width_px)
	elif point.x + half_width_px > viewport_size.x - SCREEN_MARGIN:
		shift.x = (viewport_size.x - SCREEN_MARGIN) - (point.x + half_width_px)
	if point.y - height_px < top_margin:
		shift.y = top_margin - (point.y - height_px)
	elif point.y > viewport_size.y - SCREEN_MARGIN:
		shift.y = (viewport_size.y - SCREEN_MARGIN) - point.y
	if shift == Vector2.ZERO:
		return anchor
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	return anchor + (right * shift.x - up * shift.y) * world_per_px


func _apply_rig(rig: Dictionary, player_index: int, plan: Dictionary, delta: float, camera: Camera3D) -> void:
	var keys: Dictionary = rig["keys"]
	var tag: Label3D = rig["tag"]
	if plan.is_empty() or camera == null:
		for key_variant: Variant in keys.values():
			var hidden_key := key_variant as TutorialKeycap3D
			hidden_key.set_shown(false)
			hidden_key.set_pressed(false)
			hidden_key.advance(delta)
		tag.visible = false
		rig["anchor_ready"] = false
		return
	var anchor: Vector3 = plan["anchor"]
	if not bool(rig.get("anchor_ready", false)):
		rig["anchor"] = anchor
		rig["anchor_ready"] = true
	else:
		var follow := 1.0 - exp(-FOLLOW_RATE * maxf(delta, 0.0))
		rig["anchor"] = (rig["anchor"] as Vector3).lerp(anchor, follow)
	var smoothed: Vector3 = rig["anchor"]
	var eye := camera.global_position
	var states: Dictionary = plan["states"]
	var scale_factor := float(plan["scale"])
	var layout := str(plan["layout"])

	if layout == LAYOUT_SIDES:
		for slot: String in keys.keys():
			var key: TutorialKeycap3D = keys[slot]
			if not states.has(slot):
				_hide_key(key, delta)
				continue
			var side := 1.0 if slot == SLOT_LEFT else -1.0
			var offset := DUO_SIDE_OFFSET if duo else SOLO_SIDE_OFFSET
			var at := smoothed + Vector3(offset.x * side, offset.y, offset.z)
			_place_key(key, at, _facing_basis(at, eye), scale_factor, states[slot], delta)
		tag.visible = false
		return

	# キーボード片。表示するキーの外接枠の下端を基準点に、横は中央へそろえる。
	var cells := P2_CLUSTER if player_index == 2 else P1_CLUSTER
	var bounds: Rect2 = plan["bounds"]
	var basis := _facing_basis(smoothed, eye)
	# カメラは +Z を向くので basis.x（ワールド-X寄り）が画面右、basis.z が画面下になる。
	var screen_right := basis.x
	var screen_down := basis.z
	var origin_shift := Vector2(bounds.get_center().x, bounds.end.y)
	for slot: String in keys.keys():
		var key: TutorialKeycap3D = keys[slot]
		if not states.has(slot):
			_hide_key(key, delta)
			continue
		var cell: Vector2 = cells[slot]
		var local := (cell - origin_shift) * KEY_PITCH
		var at := smoothed + (screen_right * local.x + screen_down * local.y) * scale_factor
		_place_key(key, at, basis, scale_factor, states[slot], delta)
	# プレイヤー名はキーボード片の左上に添える（2Pのみ）。
	tag.visible = duo
	if tag.visible:
		var tag_local := Vector2(
			bounds.position.x - origin_shift.x - 0.15,
			bounds.position.y - origin_shift.y - 0.35
		) * KEY_PITCH
		tag.global_position = smoothed + (screen_right * tag_local.x + screen_down * tag_local.y) * scale_factor
		tag.pixel_size = 0.0042 * scale_factor / DUO_CLUSTER_SCALE


func _hide_key(key: TutorialKeycap3D, delta: float) -> void:
	key.set_shown(false)
	key.set_pressed(false)
	key.advance(delta)


func _place_key(key: TutorialKeycap3D, at: Vector3, basis: Basis, scale_factor: float, state: Dictionary, delta: float) -> void:
	key.global_position = at
	key.global_basis = basis
	key.set_look(int(state.get("look", TutorialKeycap3D.Look.IDLE)))
	key.set_pressed(bool(state.get("pressed", false)))
	key.set_shown(true)
	key.advance(delta)
	# advance() がポップ用の scale を毎フレーム決めるので、配置用の倍率はその後に掛ける。
	key.scale *= scale_factor


func _layout_anchor(base: Vector3, layout: String) -> Vector3:
	match layout:
		LAYOUT_SIDES:
			return base
		LAYOUT_GHOST:
			return base + Vector3(0.0, GHOST_BASE_Y, 0.0)
	return base + Vector3(0.0, DUO_CLUSTER_BASE_Y if duo else SOLO_CLUSTER_BASE_Y, 0.0)


func _layout_scale(layout: String) -> float:
	match layout:
		LAYOUT_SIDES:
			return DUO_SIDE_SCALE if duo else SOLO_SIDE_SCALE
		LAYOUT_GHOST:
			return GHOST_CLUSTER_SCALE
	return DUO_CLUSTER_SCALE if duo else SOLO_CLUSTER_SCALE


## 天面（+Y）をカメラ寄りの斜め上へ向け、刻印の上（-Z）を世界の上方向にそろえる。
static func _facing_basis(at: Vector3, eye: Vector3) -> Basis:
	var to_eye := eye - at
	if to_eye.length_squared() < 0.0001:
		return Basis.IDENTITY
	var normal := Vector3.UP.lerp(to_eye.normalized(), FACE_CAMERA).normalized()
	var legend_up := Vector3.UP - normal * Vector3.UP.dot(normal)
	if legend_up.length_squared() < 0.0001:
		legend_up = Vector3.FORWARD
	var z_axis := -legend_up.normalized()
	var x_axis := normal.cross(z_axis).normalized()
	return Basis(x_axis, normal, z_axis)


func _door_x(door: int) -> float:
	var choices := game_state.num_choices
	if choices == 4:
		return float(game_state.tuning.door4_xs[clampi(door, 0, 3)])
	return game_state.tuning.left_door_x if door == 0 else game_state.tuning.right_door_x


func _player_position(player_index: int) -> Vector3:
	if player_index == 2:
		return Vector3(game_state.player2_x, game_state.player2_y, game_state.player2_local_z)
	return Vector3(game_state.player_x, game_state.player_y, game_state.player_local_z)
