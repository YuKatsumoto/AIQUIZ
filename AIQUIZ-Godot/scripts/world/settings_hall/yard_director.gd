extends Node

## 実習場の人物（教官・次の操縦者・見学の生徒 2 人）と、1 周ごとの出来事への反応（docs/lecture_hall_plan.md の項目 126〜135）。
## PracticeYard の子。実習場の yard_event（checklist / point_check / stall / overshoot / overlift / estop / pass / swap …）を
## 受けて、教官が点検表を読み上げ（操縦者が復唱）、指差し確認、行き過ぎに笛、上げすぎに非常停止、合格のハンコを押し、
## 見学の生徒はメモを取り、拍手し、びっくりする。操縦者は本編の SawOperatorPresentation（交代のときは隠して、
## ぬいぐるみが席を降りて次の生徒と入れ替わる）。座標は実習場（台車）のローカル、yaw は度で 0 = +Z。

const PlushActorScript := preload("res://scripts/world/settings_hall/plush_actor.gd")
const INSTRUCTOR_GLB := "res://assets/settings_hall/godotkun_lecturer.glb"
const QUEUE_GLB := "res://assets/settings_hall/godotkun_student_hand.glb"
const WATCHER_GLBS := ["res://assets/settings_hall/godotkun_student_notes.glb",
	"res://assets/settings_hall/godotkun_student_doze.glb"]
const FX_GLB := "res://assets/settings_hall/lecture_fx.glb"
const SFX_DIR := "res://assets/audio/sfx/lecture/"

const CHECKLIST := Vector3(15.3, 0.0, -1.4)
const INSTRUCTOR_HOME := Vector3(13.4, 0.0, -1.5)
const STAMP_TABLE := Vector3(15.4, 0.0, 0.45)
const QUEUE := [Vector3(12.6, 0.0, 1.9), Vector3(13.4, 0.0, 2.6)]
const BENCH := [Vector3(3.8, 0.0, 6.6), Vector3(5.6, 0.0, 6.6)]
const EMOTES := {"!": "FX_Exclaim", "?": "FX_Question", "anger": "FX_Anger", "sweat": "FX_Sweat",
	"dots": "FX_Dots", "note": "FX_Note", "bulb": "FX_Bulb"}
const EMOTE_SCALE := 3.0

var yard: Node3D = null
var instructor = null
var queue: Array = []          # [次の操縦者, 降りてきた操縦者]
var watchers: Array = []
var last_event := ""

var _rng := RandomNumberGenerator.new()
var _emote_meshes: Dictionary = {}
var _emotes: Array = []
var _jobs: Array = []          # [{t, secs, fn}]
var _phase := ""
var _stamp_node: Node3D = null
var _stamp_home := Transform3D.IDENTITY
var _stamp_marks: Array = []
var _warning: OmniLight3D = null
var _warning_t := -1.0


func setup(yard_node: Node3D) -> bool:
	yard = yard_node
	_rng.seed = 0x7A4D
	var instr = _spawn(INSTRUCTOR_GLB, "YardInstructor", INSTRUCTOR_HOME, -64.0)
	if instr == null:
		return false
	instructor = instr
	instructor.setup_hand_ik()
	instructor.setup_pointer()
	instructor.loop("T_Idle", 0.0)
	for k in range(2):
		var q = _spawn(QUEUE_GLB, "YardQueue%d" % k, QUEUE[k], -90.0)
		if q != null:
			q.loop("G_Idle", 0.0)
			queue.append(q)
	queue[1].root.visible = false
	for k in range(WATCHER_GLBS.size()):
		var w = _spawn(WATCHER_GLBS[k], "YardWatcher%d" % k, BENCH[k], 180.0)
		if w != null:
			w.loop("S_CopyNotes" if k == 0 else "S_LookBoard", 0.0)
			watchers.append(w)
	var props := yard.get_node_or_null("YardProps")
	if props != null:
		_stamp_node = props.find_child("PRP_Yard_Stamp", true, false) as Node3D
		if _stamp_node != null:
			_stamp_home = _stamp_node.transform
	_load_emotes()
	_warning = OmniLight3D.new()
	_warning.name = "WarningLight"
	_warning.light_color = Color(1.0, 0.15, 0.08)
	_warning.omni_range = 4.0
	_warning.light_energy = 0.0
	_warning.visible = false
	yard.add_child(_warning)
	yard.connect("yard_event", _on_event)
	return true


func _spawn(path: String, node_name: String, at: Vector3, yaw: float):
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	root.name = node_name
	root.position = at
	root.rotation.y = deg_to_rad(yaw)
	yard.add_child(root)
	for node: Node in root.find_children("*", "CollisionObject3D", true, false):
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	var actor = PlushActorScript.new(node_name, root, yard, hash(node_name))
	actor.face(yaw)
	return actor


func _process(delta: float) -> void:
	if instructor == null or not yard.is_visible_in_tree():
		return
	var keep: Array = []
	for job: Dictionary in _jobs:
		job.t = float(job.t) + delta
		if float(job.t) >= float(job.secs):
			(job.fn as Callable).call()
		else:
			keep.append(job)
	_jobs = keep
	for actor in [instructor] + queue + watchers:
		actor.update(delta)
	_tick_emotes(delta)
	if _warning_t >= 0.0:
		_warning_t += delta
		_warning.visible = true
		_warning.light_energy = 3.5 * pow(maxf(0.0, sin(_warning_t * TAU * 2.0)), 2.0)
		var operator: Node3D = yard.get("operator")
		if operator != null:
			_warning.global_position = operator.global_position + Vector3(0.0, 2.0, 0.0)


func _later(secs: float, fn: Callable) -> void:
	_jobs.append({"t": 0.0, "secs": secs, "fn": fn})


## 操縦者（本編の SawOperatorPresentation）の頭の上の点（実習場のローカル）。
func _operator_head() -> Vector3:
	var operator: Node3D = yard.get("operator")
	if operator == null:
		return Vector3(10.7, 1.8, 0.0)
	return yard.to_local(operator.global_position) + Vector3(0.0, 1.75, 0.0)


func _console_point() -> Vector3:
	var operator: Node3D = yard.get("operator")
	if operator == null:
		return Vector3(10.7, 0.0, 0.0)
	var p := yard.to_local(operator.global_position)
	return Vector3(p.x, 0.0, p.z)


# ------------------------------------------------------------------ events

func _on_event(name: String) -> void:
	last_event = name
	match name:
		"checklist":
			# 教官が点検表を読み上げ、操縦者が復唱する（項目 128）
			instructor.walk_to(CHECKLIST + Vector3(-0.75, 0.0, 0.35), 105.0, "T_Explain")
			_later(1.4, func() -> void: emote(instructor, "dots", 1.6))
			_later(2.2, func() -> void: _emote_at(_operator_head(), "!", 1.0))
			_later(2.8, func() -> void:
				instructor.walk_to(INSTRUCTOR_HOME, -64.0, "T_Idle"))
		"point_check":
			# 指差し確認「刃よし！線路よし！」（項目 127）
			var next = queue[0]
			next.once("G_PointCheck", "G_Idle")
			_later(0.6, func() -> void: emote(next, "!", 1.0))
			instructor.once("T_PointTap", "T_Idle")
			_later(0.4, func() -> void: _emote_at(_operator_head(), "!", 1.0))
		"start":
			for w in watchers:
				w.loop("S_LookBoard", 0.3)
		"stall":
			# エンスト（項目 131）
			_emote_at(_operator_head(), "sweat", 1.6)
			instructor.once("T_HeadTilt", "T_Idle")
			emote(instructor, "?", 1.4)
			for w in watchers:
				emote(w, "!", 0.9)
		"restart":
			_emote_at(_operator_head(), "!", 1.0)
			instructor.once("T_Nod", "T_Idle")
		"horn":
			for w in watchers:
				w.kick(0.2)
		"overshoot":
			# 停止線を行き過ぎ → 笛（項目 129・130）
			instructor.face_point(_console_point())
			_later(0.3, func() -> void:
				instructor.once("T_Whistle", "T_Idle")
				_sfx("whistle", instructor.root.position + Vector3(0, 1.2, 0), -4.0)
				emote(instructor, "anger", 1.6))
			_later(0.8, func() -> void: _emote_at(_operator_head(), "sweat", 1.6))
			for w in watchers:
				_later(0.6, func() -> void: emote(w, "!", 0.9))
		"overlift":
			# 刃を上げすぎ → 警告灯 → 教官が走って非常停止（項目 130）
			_warning_t = 0.0
			emote(instructor, "!", 1.0)
			var console := _console_point()
			instructor.walk_to(console + Vector3(1.0, 0.0, -0.9), NAN, "T_Idle", "G_Run", 2.2)
			for w in watchers:
				emote(w, "!", 1.0)
		"estop":
			instructor.face_point(_console_point())
			instructor.once("T_PointTap", "T_Idle", 0.08)
			_sfx("chalk_hit", _console_point() + Vector3(0, 1.0, 0), -2.0, 0.55)
			_later(0.3, func() -> void: emote(instructor, "!", 1.2))
			_later(2.4, func() -> void:
				_warning_t = -1.0
				_warning.visible = false
				instructor.walk_to(INSTRUCTOR_HOME, -64.0, "T_Idle"))
			for w in watchers:
				_later(0.5, func() -> void: emote(w, "sweat", 1.4))
		"buffer":
			# 車止めの手前で止まる（項目 134）
			for w in watchers:
				w.once("S_PeekLeft", "S_LookBoard")
		"stop":
			# 見学の生徒はメモを取る（項目 135）
			for w in watchers:
				w.loop("S_CopyNotes", 0.3)
		"pass":
			_stamp_pass()
		"swap":
			_swap_operator()


## 合格: 教官がハンコを取りに行き、操作盤に押す → 赤い「合格」の印。見学の生徒は拍手（項目 133・135）。
func _stamp_pass() -> void:
	instructor.walk_to(STAMP_TABLE + Vector3(-0.55, 0.0, -0.1), 90.0, "T_Idle")
	_later(2.2, func() -> void:
		if _stamp_node != null:
			_stamp_node.visible = false
		var stamp := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.028
		mesh.bottom_radius = 0.03
		mesh.height = 0.14
		stamp.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.3, 0.16)
		mat.roughness = 0.6
		stamp.material_override = mat
		instructor.hold("R", stamp)
		var console := _console_point()
		instructor.walk_to(console + Vector3(0.9, 0.0, -0.75), -50.0, "T_Idle"))
	_later(5.0, func() -> void:
		instructor.once("T_Stamp", "T_Idle")
		_later(0.75, func() -> void:
			_place_mark()
			_sfx("chalk_tap", _console_point() + Vector3(0, 1.0, 0), -6.0, 0.7)
			emote(instructor, "note", 1.4)
			for w in watchers:
				w.loop_for("S_Clap", 2.5, "S_LookBoard")
				emote(w, "note", 1.2)
			if not queue.is_empty():
				(queue[0]).once("G_Clap", "G_Idle")))
	_later(7.0, func() -> void:
		instructor.walk_to(STAMP_TABLE + Vector3(-0.55, 0.0, -0.1), 90.0, "T_Idle"))
	_later(9.4, func() -> void:
		var item: Node3D = instructor.drop("R")
		if item != null:
			item.queue_free()
		if _stamp_node != null:
			_stamp_node.visible = true
		instructor.walk_to(INSTRUCTOR_HOME, -64.0, "T_Idle"))


## 操作盤の横に貼る赤い「合格」の印（押すたびに少しずつずれて増える、最大 6 個）。
func _place_mark() -> void:
	var operator: Node3D = yard.get("operator")
	if operator == null:
		return
	var mark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.11, 0.11)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.08, 0.08, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _ring_texture()
	mat.roughness = 0.7
	quad.material = mat
	mark.mesh = quad
	operator.add_child(mark)
	var k := _stamp_marks.size()
	mark.position = Vector3(0.38 + 0.12 * (k % 3), 0.86 + 0.012 * k, 0.32 - 0.12 * (k / 3))
	mark.rotation = Vector3(-PI * 0.5, _rng.randf_range(-0.4, 0.4), 0.0)
	_stamp_marks.append(mark)
	if _stamp_marks.size() > 6:
		(_stamp_marks.pop_front() as Node).queue_free()


var _ring: Texture2D = null


func _ring_texture() -> Texture2D:
	if _ring != null:
		return _ring
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var ring := clampf(1.0 - absf(d - 0.82) / 0.1, 0.0, 1.0)
			var dot := clampf(1.0 - d / 0.45, 0.0, 1.0) * (0.7 + 0.3 * float((x / 4 + y / 4) % 2))
			image.set_pixel(x, y, Color(1, 1, 1, maxf(ring, dot)))
	_ring = ImageTexture.create_from_image(image)
	return _ring


## 操縦の交代（項目 132）: 操縦者が席を降りて列の後ろへ、次の生徒が席に着く。
func _swap_operator() -> void:
	var operator: Node3D = yard.get("operator")
	if operator == null or queue.size() < 2:
		return
	var leaving = queue[1]
	var next = queue[0]
	var seat := _console_point()
	operator.visible = false
	leaving.root.visible = true
	leaving.root.position = seat + Vector3(0.6, 0.0, 0.2)
	leaving.root.rotation.y = deg_to_rad(90.0)
	leaving.once("G_Stretch", "G_Idle")
	_later(2.0, func() -> void:
		leaving.walk_to(QUEUE[0], -90.0, "G_Idle")
		emote(leaving, "note", 1.2))
	next.walk_to(seat + Vector3(0.6, 0.0, 0.2), -90.0, "G_Idle")
	_later(4.0, func() -> void:
		next.root.visible = false
		operator.visible = true
		_emote_at(_operator_head(), "!", 1.0)
		queue = [leaving, next]
		next.root.position = QUEUE[1])


# ------------------------------------------------------------------ emotes & sound

func _load_emotes() -> void:
	var packed := load(FX_GLB) as PackedScene
	if packed == null:
		return
	var root := packed.instantiate()
	for kind: String in EMOTES:
		var node := root.find_child(str(EMOTES[kind]), true, false) as MeshInstance3D
		if node != null:
			var copy := node.duplicate() as MeshInstance3D
			copy.transform = Transform3D.IDENTITY
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_emote_meshes[kind] = copy
	root.free()


func emote(actor, kind: String, secs := 1.4) -> void:
	if actor == null:
		return
	_emote_at(actor.head_point() + Vector3(0.0, 0.12, 0.0), kind, secs)


func _emote_at(at: Vector3, kind: String, secs := 1.4) -> void:
	if not _emote_meshes.has(kind):
		return
	var node := (_emote_meshes[kind] as MeshInstance3D).duplicate() as MeshInstance3D
	node.position = at
	node.scale = Vector3.ONE * 0.001
	yard.add_child(node)
	_emotes.append({"node": node, "t": 0.0, "secs": secs, "at": at})


func _tick_emotes(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var keep: Array = []
	for item: Dictionary in _emotes:
		var node: MeshInstance3D = item.node
		item.t = float(item.t) + delta
		var t := float(item.t)
		if not is_instance_valid(node) or t >= float(item.secs):
			if is_instance_valid(node):
				node.queue_free()
			continue
		node.position = (item.at as Vector3) + Vector3(0.0, 0.025 * sin(t * 7.0), 0.0)
		if camera != null:
			node.look_at(Vector3(camera.global_position.x, node.global_position.y, camera.global_position.z), Vector3.UP)
		var pop := lerpf(0.0, 1.22, t / 0.18) if t < 0.18 else (lerpf(1.22, 1.0, (t - 0.18) / 0.1) if t < 0.28 else 1.0)
		if t > float(item.secs) - 0.2:
			pop *= clampf((float(item.secs) - t) / 0.2, 0.0, 1.0)
		node.scale = Vector3.ONE * maxf(0.001, pop * EMOTE_SCALE)
		keep.append(item)
	_emotes = keep


func _sfx(name: String, at: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var path := SFX_DIR + name + ".wav"
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path)
	player.bus = &"SFX"
	player.position = at
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.unit_size = 8.0
	player.max_distance = 80.0
	yard.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _exit_tree() -> void:
	for node: Node in _emote_meshes.values():
		if is_instance_valid(node):
			node.free()
	_emote_meshes.clear()
