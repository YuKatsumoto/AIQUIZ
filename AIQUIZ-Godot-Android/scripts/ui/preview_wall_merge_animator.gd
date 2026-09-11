extends RefCounted
class_name PreviewWallMergeAnimator

## 問題準備画面・カスタマイズ壁プレビューと同型の合体アニメ（左右スライド→火花→スケール収束）

const SLIDE_START_X: float = 150.0
const INTERVAL_SEC: float = 0.15
const SLIDE_DURATION: float = 0.125
const FLASH_DURATION: float = 0.175

var _left_sils: Array[MeshInstance3D] = []
var _right_sils: Array[MeshInstance3D] = []
var _anims: Array[Dictionary] = []
var _started: Array[bool] = []
var _timer: float = 0.0


func clear() -> void:
	_left_sils.clear()
	_right_sils.clear()
	_anims.clear()
	_started.clear()
	_timer = 0.0


func remove_slot_at(idx: int) -> void:
	if idx < _anims.size():
		_anims.remove_at(idx)
	if idx < _started.size():
		_started.remove_at(idx)
	if idx < _left_sils.size():
		_left_sils.remove_at(idx)
	if idx < _right_sils.size():
		_right_sils.remove_at(idx)


func attach_new_wall(wall: Node3D) -> void:
	wall.visible = false
	wall.scale = Vector3.ONE

	var sil_l := _create_silhouette()
	wall.add_child(sil_l)
	sil_l.position = Vector3(-SLIDE_START_X, 2.75, 0.0)
	sil_l.visible = false

	var sil_r := _create_silhouette()
	wall.add_child(sil_r)
	sil_r.position = Vector3(SLIDE_START_X, 2.75, 0.0)
	sil_r.visible = false

	_left_sils.append(sil_l)
	_right_sils.append(sil_r)
	_anims.append({"phase": 0, "timer": 0.0, "started": false})
	_started.append(false)


func is_wall_ready(wall_index: int) -> bool:
	if wall_index < 0 or wall_index >= _anims.size():
		return true
	return int(_anims[wall_index].get("phase", 0)) >= 3


func process(dt: float, walls: Array, tween_host: Node) -> void:
	var total: int = walls.size()
	if total == 0:
		return

	var all_started := true
	for ms in _started:
		if not ms:
			all_started = false
			break
	if not all_started:
		_timer += dt
		while _timer >= INTERVAL_SEC:
			var found_next := false
			for search_i in range(total):
				if search_i >= _started.size():
					break
				if not _started[search_i]:
					_started[search_i] = true
					if search_i < _anims.size():
						_anims[search_i]["phase"] = 1
						_anims[search_i]["started"] = true
						_anims[search_i]["timer"] = 0.0
					if search_i < _left_sils.size():
						_left_sils[search_i].visible = true
						_right_sils[search_i].visible = true
					found_next = true
					break
			if not found_next:
				break
			_timer -= INTERVAL_SEC

	for i in range(_anims.size()):
		if i >= walls.size():
			continue
		var wall: Node3D = walls[i]
		if not is_instance_valid(wall):
			continue
		var anim: Dictionary = _anims[i]
		if not anim.get("started", false):
			continue

		var phase: int = int(anim.get("phase", 0))
		var t_val: float = float(anim.get("timer", 0.0))
		t_val += dt
		anim["timer"] = t_val

		if phase == 1:
			var prog: float = clampf(t_val / SLIDE_DURATION, 0.0, 1.0)
			var eased: float = 1.0 - pow(1.0 - prog, 5.0)
			var x_offset: float = SLIDE_START_X * (1.0 - eased)
			if i < _left_sils.size():
				_left_sils[i].position.x = -x_offset
				_right_sils[i].position.x = x_offset

			if prog >= 1.0:
				anim["phase"] = 2
				anim["timer"] = 0.0
				if i < _left_sils.size():
					_left_sils[i].visible = false
					_right_sils[i].visible = false
				wall.visible = true
				wall.scale = Vector3(1.15, 1.15, 1.15)
				_spawn_merge_sparks_on_wall(wall, tween_host)

		elif phase == 2:
			var prog2: float = clampf(t_val / FLASH_DURATION, 0.0, 1.0)
			var eased2: float = 1.0 - pow(1.0 - prog2, 2.0)
			var sc: float = lerpf(1.15, 1.0, eased2)
			wall.scale = Vector3(sc, sc, sc)
			if prog2 >= 1.0:
				anim["phase"] = 3
				wall.scale = Vector3.ONE


static func _create_silhouette() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.0, 5.5, 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.5, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = mat
	mi.mesh = box
	mi.visible = false
	return mi


static func _spawn_merge_sparks_on_wall(wall: Node3D, tween_host: Node) -> void:
	if not wall or not is_instance_valid(wall):
		return
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))

	var sparks := CPUParticles3D.new()
	sparks.amount = GraphicsQuality.particle_amount(55, GameManager.graphics_quality)
	sparks.lifetime = 0.75
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.randomness = 1.0
	sparks.local_coords = false
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.5, 2.0, 0.5)
	sparks.direction = Vector3(0.0, 1.0, 0.0)
	sparks.spread = 180.0
	sparks.initial_velocity_min = 7.0
	sparks.initial_velocity_max = 18.0
	sparks.gravity = Vector3(0, -25.0, 0)
	sparks.damping_min = 5.0
	sparks.damping_max = 10.0
	sparks.scale_amount_min = 1.0
	sparks.scale_amount_max = 2.2
	sparks.scale_amount_curve = curve

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = Color(1.5, 1.0, 0.6, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	var mesh := QuadMesh.new()
	mesh.material = mat
	sparks.mesh = mesh
	wall.add_child(sparks)
	sparks.position = Vector3(0.0, 2.5, 0.0)
	sparks.emitting = true

	var flash := CPUParticles3D.new()
	flash.amount = GraphicsQuality.particle_amount(1, GameManager.graphics_quality)
	flash.lifetime = 0.22
	flash.one_shot = true
	flash.gravity = Vector3.ZERO
	flash.local_coords = false
	flash.scale_amount_min = 7.0
	flash.scale_amount_max = 7.0
	flash.scale_amount_curve = curve
	var mat_flash := StandardMaterial3D.new()
	mat_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_flash.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_flash.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat_flash.albedo_color = Color(1.2, 1.0, 0.8, 0.75)
	mat_flash.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mesh_flash := QuadMesh.new()
	mesh_flash.material = mat_flash
	flash.mesh = mesh_flash
	wall.add_child(flash)
	flash.position = Vector3(0.0, 2.5, 0.0)
	flash.emitting = true

	if tween_host and is_instance_valid(tween_host):
		var tw_s := tween_host.create_tween()
		tw_s.tween_callback(func() -> void:
			if is_instance_valid(sparks):
				sparks.queue_free()
		).set_delay(2.4)
		var tw_f := tween_host.create_tween()
		tw_f.tween_callback(func() -> void:
			if is_instance_valid(flash):
				flash.queue_free()
		).set_delay(1.9)
