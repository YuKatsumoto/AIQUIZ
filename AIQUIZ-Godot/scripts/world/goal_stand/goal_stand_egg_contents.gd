class_name GoalStandEggContents
extends Node3D

## Raw egg contents of the goal stand's thrown eggs (GoalStandEggs breaks them;
## this is everything that comes out). Each splat is a GoalStandEggSplat model
## drawn by one white disc and its rivulets (one row of a shared data texture, so
## every splat shares one material), its yolks (with chalazae) and the shell pieces
## stuck in it. Splats on a body ride the part they landed on (GoalStandEggBody
## anchors, de-mirrored); misses lie on the conveyor. Liquid that reaches an edge
## hangs in GoalStandEggDrip drops that neck and fall; falling drops, spray and
## yolks that slid off land on the loser's lift deck (the `support`) or the
## conveyor and pool there, merging into puddles. Shell pieces flying off can stay
## tethered for a moment by a GoalStandEggStrand.
##
## The crowd throws for as long as the verdict holds, so every kind of piece has a
## cap per quality (DETAIL); over a cap the oldest fades out (thinning, never
## popping) and the node goes back to a pool. World space (top_level, held at the
## world origin, so its children's transform is their global transform).

const CONTENTS_SCENE := preload("res://assets/goal_stand/goal_stand_egg_contents.glb")
const WHITE_SHADER := preload("res://shaders/goal_stand_egg_white.gdshader")
const WHITE_LITE_SHADER := preload("res://shaders/goal_stand_egg_white_lite.gdshader")
const RIVULET_SHADER := preload("res://shaders/goal_stand_egg_rivulet.gdshader")
const RIVULET_LITE_SHADER := preload("res://shaders/goal_stand_egg_rivulet_lite.gdshader")
const YOLK_SHADER := preload("res://shaders/goal_stand_egg_yolk.gdshader")
const DRIP_SHADER := preload("res://shaders/goal_stand_egg_drip.gdshader")
const DRIP_LITE_SHADER := preload("res://shaders/goal_stand_egg_drip_lite.gdshader")
const STRAND_SHADER := preload("res://shaders/goal_stand_egg_strand.gdshader")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")

const GRAVITY := Vector3(0.0, -9.8, 0.0)
const FLOOR_Y := StageConstants.FLOOR_TOP_Y
## Rows of the data texture (one per live splat or puddle).
const ROWS := 80
const FADE_TIME := 1.2
## A hit this close to a splat's centre (share of its radius) joins it.
const MERGE_REACH := 0.6
## Hard hits often burst the yolk (19 m/s here is about 8 m/s, 30 km/h, for a real
## egg): more often on a body than on the floor, where the white cushions it less.
const RUPTURE_SPEED := 14.0
const RUPTURE_CHANCE := 0.35
const BODY_RUPTURE_CHANCE := 0.35
const DROP_MAX_LIFE := 3.0
## Rayleigh wobble of a free drop: damping ratio, and the stretch it pinches off with.
const DROP_WOBBLE_ZETA := 0.18
const DROP_PINCH_WOBBLE := 0.35
## A yolk that falls off: landing flattens it, and it bursts on a hard landing.
const YOLK_RESTITUTION := 0.18
const YOLK_LANDING_BURST := 4.5
const YOLK_BURST_CHANCE := 0.4
## Floor splats are stacked this far apart so overlapping ones never z-fight.
const FLOOR_LAYER := 0.0007
const FLOOR_LAYERS := 8
## Chalazae and stuck shell are re-measured on the splat every this many frames.
const CORD_EVERY := 3
## Per quality: caps and extras (Phase 2's GPU fluid adds its own particles).
const DETAIL := {
	QualityRules.LOW: {"body_splats": 5, "floor_splats": 6, "puddles": 8, "drips": 3, "drops": 16, "strands": 0,
		"rivulets": 1, "spray": 4, "chalazae": false, "loose_yolks": 3, "captured": 1},
	QualityRules.BALANCED: {"body_splats": 7, "floor_splats": 10, "puddles": 14, "drips": 6, "drops": 28, "strands": 1,
		"rivulets": 2, "spray": 8, "chalazae": true, "loose_yolks": 5, "captured": 2},
	QualityRules.HIGH: {"body_splats": 10, "floor_splats": 14, "puddles": 24, "drips": 10, "drops": 44, "strands": 3,
		"rivulets": 3, "spray": 12, "chalazae": true, "loose_yolks": 6, "captured": 3},
	QualityRules.ULTRA: {"body_splats": 12, "floor_splats": 16, "puddles": 32, "drips": 14, "drops": 60, "strands": 3,
		"rivulets": 3, "spray": 16, "chalazae": true, "loose_yolks": 8, "captured": 3},
}

var model: GoalStandEggRheology
var detail: Dictionary = DETAIL[QualityRules.BALANCED]
var refract := true
## What drips and fallen yolks land on before the conveyor: {node, top (local y),
## radius} of the loser's lift deck (GoalStandEggs.support), or empty.
var support := {}
## The GPU fluid on HIGH/ULTRA desktop (null elsewhere): it takes the splash and part
## of the runoff of body hits, so those splats shed no CPU spray.
var fluid: GoalStandEggFluid
var splats_made := 0
var merges := 0
var ruptures := 0
var drops_landed := 0
var yolks_fallen := 0
var drips_fallen := 0
## Smoothed cost per part of the update (microseconds): splats, pieces, texture.
var costs := {}

var _white_mesh: Mesh
var _yolk_mesh: Mesh
var _chalaza_mesh: Mesh
var _drip_mesh: Mesh
var _strand_mesh: Mesh
var _ribbon_mesh: Mesh
var _white_material: ShaderMaterial
var _rivulet_material: ShaderMaterial
var _yolk_material: ShaderMaterial
var _drip_material: ShaderMaterial
var _strand_material: ShaderMaterial
var _chalaza_material: StandardMaterial3D
var _image: Image
var _texture: ImageTexture
var _data := PackedFloat32Array()
var _free_rows: Array[int] = []
var _splats: Array[Dictionary] = []
var _drips: Array[Dictionary] = []
var _drops: Array[Dictionary] = []
var _strands: Array[Dictionary] = []
var _loose_yolks: Array[Dictionary] = []
var _bodies := {}
var _pools := {}
var _floor_layer := 0
var _clock := 0.0
var _tick := 0
var _dirty := false
var _events: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func setup(level: String, egg_scale: float, seed_value: int, mobile: bool = false) -> void:
	name = "EggContents"
	top_level = true
	# Every piece is placed with `transform` as its world transform, so this node
	# must sit at the world origin: the stand that owns it is turned round, and a
	# top_level node keeps the global transform it had when it was switched on.
	global_transform = Transform3D.IDENTITY
	_rng.seed = seed_value
	model = GoalStandEggRheology.new(egg_scale)
	detail = DETAIL.get(level, DETAIL[QualityRules.BALANCED])
	refract = level != QualityRules.LOW and not mobile
	var contents := CONTENTS_SCENE.instantiate()
	_white_mesh = _mesh_of(contents, "GSE_White")
	_yolk_mesh = _mesh_of(contents, "GSE_Yolk")
	_chalaza_mesh = _mesh_of(contents, "GSE_Chalaza")
	_drip_mesh = _mesh_of(contents, "GSE_Drip")
	_strand_mesh = _mesh_of(contents, "GSE_Strand")
	_ribbon_mesh = _mesh_of(contents, "GSE_Ribbon")
	contents.free()
	_image = Image.create_empty(GoalStandEggSplat.ROW_TEXELS, ROWS, false, Image.FORMAT_RGBAF)
	_texture = ImageTexture.create_from_image(_image)
	_data.resize(GoalStandEggSplat.ROW_TEXELS * ROWS * 4)
	_data.fill(0.0)
	_free_rows.clear()
	for row in range(ROWS):
		_free_rows.append(row)
	_white_material = _shader_material(WHITE_SHADER if refract else WHITE_LITE_SHADER, 0)
	_white_material.set_shader_parameter("splat_data", _texture)
	_rivulet_material = _shader_material(RIVULET_SHADER if refract else RIVULET_LITE_SHADER, 1)
	_rivulet_material.set_shader_parameter("splat_data", _texture)
	_yolk_material = _shader_material(YOLK_SHADER, 0)
	_drip_material = _shader_material(DRIP_SHADER if refract else DRIP_LITE_SHADER, 2)
	_strand_material = _shader_material(STRAND_SHADER, 2)
	_chalaza_material = StandardMaterial3D.new()
	# Chalazae are faint: twisted, slightly milky cords inside the clear gel.
	_chalaza_material.albedo_color = Color(0.93, 0.92, 0.85, 0.2)
	_chalaza_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_chalaza_material.roughness = 0.35
	_chalaza_material.metallic_specular = 0.2
	_chalaza_material.render_priority = 1
	if GoalStandEggFluid.wanted(level, mobile):
		fluid = GoalStandEggFluid.new()
		add_child(fluid)
		fluid.setup(level)
		if not fluid.is_supported():
			fluid.queue_free()
			fluid = null


static func _mesh_of(root: Node, mesh_name: String) -> Mesh:
	var node := root.find_child(mesh_name, true, false) as MeshInstance3D
	return node.mesh if node != null else null


static func _shader_material(shader: Shader, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	return material


# ------------------------------------------------------------------ spawning

## An egg broke on `target` near `point`, travelling at `incoming`. `ray` is the
## direction to look for the surface along (the throw, leaned toward the camera).
## Returns the splat entry (with hit point and normal) or {} when the target has no
## surface to hold it.
func spawn_on_body(target: Node3D, point: Vector3, incoming: Vector3, ray: Vector3) -> Dictionary:
	var body := body_for(target)
	if body.is_empty():
		return {}
	ray = ray.normalized()
	var hit := body.raycast(point - ray * 1.2, ray, 2.6)
	if hit.is_empty():
		hit = body.nearest(point, ray)
	if hit.is_empty():
		return {}
	var anchor := body.anchor_for(hit)
	var frame := body.frame_of(anchor)
	var impact := _impact_in(frame, incoming, _rng.randf_range(0.28, 0.36), BODY_RUPTURE_CHANCE)
	impact.wrap = anchor.wrap
	impact.extents = anchor.extents
	impact.depth = anchor.depth
	var group := "body:%d" % target.get_instance_id()
	for entry: Dictionary in _splats:
		if entry.group != group or float(entry.fading) >= 0.0 or int((entry.anchor as Dictionary).get("shape", -1)) != int(anchor.shape):
			continue
		if _try_merge(entry, hit.point, impact):
			_hand_to_fluid(entry, Transform3D(frame.basis, hit.point), impact, body)
			return entry
	var entry := _add_splat(GoalStandEggSplat.create(model, impact), group, frame)
	entry.body = body
	entry.anchor = anchor
	entry.hit = hit.point
	entry.normal = hit.normal
	_hand_to_fluid(entry, frame, impact, body)
	return entry


## On HIGH/ULTRA a share of the thin white leaves the splat as GPU fluid (splash and
## runoff); the splat books it as emitted and sheds no CPU spray of its own.
func _hand_to_fluid(entry: Dictionary, frame: Transform3D, impact: Dictionary, body: GoalStandEggBody) -> void:
	if fluid == null or not fluid.is_simulation_ready():
		return
	var splat := entry.model as GoalStandEggSplat
	fluid.body = body
	var handed := fluid.emit(frame, float(impact.reach), float(impact.normal_speed), impact.tangential,
		model.thin_volume * GoalStandEggFluid.SHARE)
	if handed <= 0.0:
		return
	handed = minf(handed, splat.thin_volume * 0.5)
	splat.thin_volume -= handed
	splat.emitted += handed
	entry.spray = int(detail.spray)


## An egg missed and broke on the conveyor at `point`.
func spawn_on_floor(point: Vector3, incoming: Vector3) -> Dictionary:
	var throw := Vector3(incoming.x, 0.0, incoming.z)
	var x := throw.normalized() if throw.length() > 0.05 else Vector3.RIGHT
	_floor_layer = (_floor_layer + 1) % FLOOR_LAYERS
	var frame := Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), Vector3(point.x, FLOOR_Y + FLOOR_LAYER * _floor_layer, point.z))
	var impact := _impact_in(frame, incoming, _rng.randf_range(0.34, 0.44))
	for entry: Dictionary in _splats:
		if entry.group == "floor" and float(entry.fading) < 0.0 and _try_merge(entry, frame.origin, impact):
			return entry
	var entry := _add_splat(GoalStandEggSplat.create(model, impact), "floor", frame)
	entry.hit = frame.origin
	entry.normal = Vector3.UP
	return entry


func _impact_in(frame: Transform3D, incoming: Vector3, reach: float, rupture_chance: float = RUPTURE_CHANCE) -> Dictionary:
	var local := frame.basis.transposed() * incoming
	var normal_speed := maxf(-local.y, 4.0)
	return {"normal_speed": normal_speed, "tangential": Vector2(local.x, local.z), "reach": reach, "yolks": 1,
		"rupture": normal_speed > RUPTURE_SPEED and _rng.randf() < rupture_chance, "seed": _rng.randi(), "share": 1.0}


func _try_merge(entry: Dictionary, point: Vector3, impact: Dictionary) -> bool:
	var splat := entry.model as GoalStandEggSplat
	var local := (entry.frame as Transform3D).affine_inverse() * point
	var at := Vector2(local.x, local.z)
	if absf(local.y) > 0.06 or at.length() > splat.mean_radius() * MERGE_REACH:
		return false
	var torn_before := _torn_yolks(splat)
	splat.absorb(at, impact)
	ruptures += maxi(0, _torn_yolks(splat) - torn_before)
	merges += 1
	entry.hit = point
	entry.normal = (entry.frame as Transform3D).basis.y
	entry.dirty = true
	entry.spray = 0
	return true


static func _torn_yolks(splat: GoalStandEggSplat) -> int:
	var torn := 0
	for yolk: Dictionary in splat.yolks:
		torn += 1 if float(yolk.tear) >= 0.0 else 0
	return torn


func _add_splat(splat: GoalStandEggSplat, group: String, frame: Transform3D) -> Dictionary:
	_enforce_cap(group, 1)
	if _free_rows.is_empty():
		_remove_splat(_oldest_splat(""))
	var row: int = _free_rows.pop_front()
	var node := _take("white", _white_mesh, _white_material)
	node.set_instance_shader_parameter(&"row", row)
	var entry := {"model": splat, "group": group, "frame": frame, "row": row, "node": node, "born": _clock,
		"fading": -1.0, "rivulets": [], "yolks": [], "chalazae": [], "captured": [], "dirty": true, "spray": 0,
		"anchor": {}, "body": null, "support_node": null, "support_local": Vector3.ZERO, "hit": frame.origin, "normal": frame.basis.y}
	node.transform = frame
	_splats.append(entry)
	splats_made += 1
	ruptures += _torn_yolks(splat)
	_sync_yolk_nodes(entry)
	return entry


## Room for `adding` more in `group`: the oldest start fading; past the hard cap the
## oldest fading one goes at once.
func _enforce_cap(group: String, adding: int) -> void:
	var cap := _cap_of(group)
	var live: Array[Dictionary] = []
	var fading: Array[Dictionary] = []
	for entry: Dictionary in _splats:
		if entry.group == group:
			(fading if float(entry.fading) >= 0.0 else live).append(entry)
	var over := live.size() + adding - cap
	for index in range(maxi(over, 0)):
		_begin_fade(live[index])
		fading.append(live[index])
	while live.size() - maxi(over, 0) + fading.size() + adding > cap + 2 and not fading.is_empty():
		_remove_splat(fading.pop_front())


func _cap_of(group: String) -> int:
	if group.begins_with("body:"):
		return int(detail.body_splats)
	if group.begins_with("puddle"):
		return int(detail.puddles)
	return int(detail.floor_splats)


func _oldest_splat(group: String) -> Dictionary:
	for entry: Dictionary in _splats:
		if group == "" or entry.group == group:
			return entry
	return {}


func _begin_fade(entry: Dictionary) -> void:
	if float(entry.fading) < 0.0:
		entry.fading = 0.0


## A tether from the splat to a shell piece flying off (`shard` is GoalStandEggs'
## live shard dictionary: its velocity takes the strand's pull).
func tether(entry: Dictionary, shard: Dictionary) -> bool:
	if _strands.size() >= int(detail.strands) * 3 or int(detail.strands) <= 0 or entry.is_empty():
		return false
	var splat := entry.model as GoalStandEggSplat
	var at := Vector2.from_angle(_rng.randf() * TAU) * splat.thick_rest * _rng.randf_range(0.2, 0.7)
	var from := _surface_world(entry, at, splat.film + splat.thick_height * 0.5)
	var node := _take("strand", _strand_mesh, _strand_material)
	var strand := GoalStandEggStrand.create(from, (shard.node as Node3D).global_position,
		_rng.randf_range(0.0025, 0.005), _rng.randf_range(0.18, 0.45), _rng.randf())
	_strands.append({"model": strand, "node": node, "splat": entry, "at": at, "shard": shard})
	return true


## A shell piece that stays stuck in the white instead of flying off.
func capture(entry: Dictionary, mesh: Mesh, material: Material) -> bool:
	if entry.is_empty() or (entry.captured as Array).size() >= int(detail.captured):
		return false
	var splat := entry.model as GoalStandEggSplat
	var node := _take("shell:%d" % mesh.get_rid().get_id(), mesh, material)
	var at := Vector2.from_angle(_rng.randf() * TAU) * splat.thick_rest * _rng.randf_range(0.35, 1.1)
	var tilt := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(0.25, 0.9) * (1.0 if _rng.randf() < 0.5 else -1.0))
	(entry.captured as Array).append({"node": node, "at": at, "tilt": tilt, "sink": _rng.randf_range(0.2, 0.7)})
	return true


func body_for(target: Node3D) -> GoalStandEggBody:
	var key := target.get_instance_id()
	var body: GoalStandEggBody = _bodies.get(key)
	if body == null or body.is_empty() or not body.is_live({"shape": 0}):
		body = GoalStandEggBody.from_target(target)
		_bodies[key] = body
	return body


# ------------------------------------------------------------------ per frame

func update(delta: float, camera: Camera3D) -> void:
	_clock += delta
	_tick += 1
	var t0 := Time.get_ticks_usec()
	for index in range(_splats.size() - 1, -1, -1):
		if index < _splats.size():
			_update_splat(_splats[index], delta)
	var t1 := Time.get_ticks_usec()
	_update_drips(delta)
	_update_drops(delta)
	_update_strands(delta)
	_update_loose_yolks(delta)
	if fluid != null:
		fluid.support = support
		fluid.update(delta)
	var t2 := Time.get_ticks_usec()
	if _dirty:
		_image.set_data(GoalStandEggSplat.ROW_TEXELS, ROWS, false, Image.FORMAT_RGBAF, _data.to_byte_array())
		_texture.update(_image)
		_dirty = false
	var t3 := Time.get_ticks_usec()
	for pair: Array in [["splats", t1 - t0], ["pieces", t2 - t1], ["texture", t3 - t2]]:
		costs[pair[0]] = lerpf(float(costs.get(pair[0], 0.0)), float(pair[1]), 0.1)


func _update_splat(entry: Dictionary, delta: float) -> void:
	var resting := not (entry.model as GoalStandEggSplat).awake and float(entry.fading) < 0.0 and not bool(entry.dirty)
	if resting and entry.body == null:
		# Asleep on the conveyor: nothing to do; on the lift deck it only rides along.
		if entry.support_node != null:
			var carried: Variant = _frame_of(entry)
			if carried == null:
				_remove_splat(entry)
				return
			entry.frame = carried
			(entry.node as Node3D).transform = carried
			_place_yolks(entry, true)
		return
	var frame: Variant = _frame_of(entry)
	if frame == null:
		_remove_splat(entry)
		return
	# How fast the splat is carried (the body moving): what lets go keeps it.
	entry.point_velocity = ((frame as Transform3D).origin - (entry.frame as Transform3D).origin) / maxf(delta, 0.001)
	entry.frame = frame
	var splat := entry.model as GoalStandEggSplat
	var visible_now := _anchor_visible(entry)
	(entry.node as Node3D).visible = visible_now
	if float(entry.fading) >= 0.0:
		entry.fading = float(entry.fading) + delta
		splat.alpha = clampf(1.0 - float(entry.fading) / FADE_TIME, 0.0, 1.0)
		entry.dirty = true
		if float(entry.fading) >= FADE_TIME:
			_remove_splat(entry)
			return
	var gravity := (frame as Transform3D).basis.transposed() * GRAVITY
	var awake_before := splat.awake
	_events.clear()
	# Past the impact the model runs at half rate (two frames at once, alternating
	# splats); the splat still follows its body every frame.
	entry.pending = float(entry.get("pending", 0.0)) + delta
	if splat.age < GoalStandEggSplat.FINE_STEPS_UNTIL or float(entry.fading) >= 0.0 or (_tick + int(entry.row)) % 2 == 0:
		splat.step(float(entry.pending), Vector2(gravity.x, gravity.z), _events)
		entry.pending = 0.0
	for event: Dictionary in _events:
		_handle_event(entry, event)
	if splat.awake or awake_before or bool(entry.dirty):
		splat.write_row(_data, int(entry.row))
		entry.dirty = false
		_dirty = true
	(entry.node as Node3D).transform = frame
	_sync_rivulet_nodes(entry, visible_now)
	_sync_yolk_nodes(entry)
	_place_yolks(entry, visible_now)
	_place_captured(entry, visible_now)


## The splat's world frame now: on its body part, on the lift deck, or fixed.
func _frame_of(entry: Dictionary) -> Variant:
	var body := entry.body as GoalStandEggBody
	if body != null:
		if not body.is_live(entry.anchor):
			return null
		return body.frame_of(entry.anchor)
	var holder := entry.support_node as Node3D
	if entry.support_node != null:
		if not is_instance_valid(holder) or not holder.is_inside_tree():
			return null
		var frame: Transform3D = entry.frame
		return Transform3D(frame.basis, holder.global_transform * (entry.support_local as Vector3))
	return entry.frame


func _anchor_visible(entry: Dictionary) -> bool:
	var body := entry.body as GoalStandEggBody
	if body == null:
		return true
	var node := body.shape_node(int(entry.anchor.shape))
	return node != null and node.is_visible_in_tree()


func _handle_event(entry: Dictionary, event: Dictionary) -> void:
	var splat := entry.model as GoalStandEggSplat
	var frame: Transform3D = entry.frame
	match String(event.type):
		"spray":
			if int(entry.spray) >= int(detail.spray):
				return
			entry.spray = int(entry.spray) + 1
			var point := _surface_world(entry, event.q, splat.film)
			var dir2: Vector2 = event.dir
			var along := frame.basis * Vector3(dir2.x, 0.0, dir2.y)
			var velocity := along * float(event.speed) * _rng.randf_range(0.3, 0.65) + frame.basis.y * _rng.randf_range(0.4, 1.6)
			_add_drop(point, velocity, _rng.randf_range(0.009, 0.022), GoalStandEggDrip.Kind.THIN, DROP_PINCH_WOBBLE * 0.5)
		"edge":
			_feed_drip(entry, event)
		"yolk":
			_release_yolk(entry, event)


func _surface_world(entry: Dictionary, q: Vector2, h: float) -> Vector3:
	return (entry.frame as Transform3D) * (entry.model as GoalStandEggSplat).surface_position(q, h)


func _sync_rivulet_nodes(entry: Dictionary, visible_now: bool) -> void:
	var splat := entry.model as GoalStandEggSplat
	var nodes: Array = entry.rivulets
	var wanted := mini(splat.rivulets.size(), mini(int(detail.rivulets), GoalStandEggSplat.MAX_RIVULETS))
	while nodes.size() < wanted:
		var node := _take("rivulet", _ribbon_mesh, _rivulet_material)
		node.set_instance_shader_parameter(&"row", int(entry.row))
		node.set_instance_shader_parameter(&"index", nodes.size())
		nodes.append(node)
	for node: MeshInstance3D in nodes:
		node.transform = entry.frame
		node.visible = visible_now


## One node per yolk still in the splat (with its chalazae), kept in step with the model.
func _sync_yolk_nodes(entry: Dictionary) -> void:
	var splat := entry.model as GoalStandEggSplat
	var nodes: Array = entry.yolks
	while nodes.size() < splat.yolks.size():
		var node := _take("yolk", _yolk_mesh, _yolk_material)
		nodes.append(node)
		if bool(detail.chalazae):
			for _side in range(2):
				(entry.chalazae as Array).append(_take("chalaza", _chalaza_mesh, _chalaza_material))
	while nodes.size() > splat.yolks.size():
		_give(nodes.pop_back())
		if bool(detail.chalazae):
			for _side in range(2):
				if not (entry.chalazae as Array).is_empty():
					_give((entry.chalazae as Array).pop_back())


## Yolks, their chalazae and the shell stuck in the white are placed in the splat's
## own frame, re-measured only while the splat moves (the cords and the shell, which
## barely move, every few frames); each frame they just follow the frame.
func _place_yolks(entry: Dictionary, visible_now: bool) -> void:
	var splat := entry.model as GoalStandEggSplat
	var frame: Transform3D = entry.frame
	var fade := clampf(float(entry.fading) / FADE_TIME, 0.0, 1.0) if float(entry.fading) >= 0.0 else 0.0
	# A sleeping yolk only follows its body; its shape needs no update.
	var reshape := splat.awake or fade > 0.0 or bool(entry.get("reshape", true))
	entry.reshape = splat.awake
	var locals: Array = entry.get("yolk_locals", [])
	if locals.size() != splat.yolks.size():
		locals.resize(splat.yolks.size())
		reshape = true
	var cords_due := reshape and (_tick + int(entry.row)) % CORD_EVERY == 0 or not entry.has("cord_locals")
	for index in range(splat.yolks.size()):
		var yolk: Dictionary = splat.yolks[index]
		var node := (entry.yolks as Array)[index] as MeshInstance3D
		if reshape or locals[index] == null:
			var surface := splat.surface(yolk.pos, splat.film * 0.35)
			locals[index] = Transform3D(_tilt(surface.normal) * Basis.from_scale(Vector3.ONE * float(yolk.radius)), surface.position)
		node.transform = frame * (locals[index] as Transform3D)
		node.visible = visible_now
		if reshape:
			_send_yolk(node, yolk, fade)
	entry.yolk_locals = locals
	if bool(detail.chalazae):
		_place_chalazae(entry, cords_due, visible_now and fade < 0.9)
		# The cords of a burst yolk sink into what ran out of it.
		for index in range(splat.yolks.size()):
			if float(splat.yolks[index].deflate) > 0.3 and index * 2 + 1 < (entry.chalazae as Array).size():
				((entry.chalazae as Array)[index * 2] as Node3D).visible = false
				((entry.chalazae as Array)[index * 2 + 1] as Node3D).visible = false


## The yolk shader's parameters, sent only when they visibly changed.
func _send_yolk(node: MeshInstance3D, yolk: Dictionary, fade: float) -> void:
	var sag: Vector2 = yolk.sag
	var tear_angle := sag.angle() if sag.length() > 0.01 else float(yolk.axis) + PI * 0.5
	var shape := Vector4(float(yolk.flatten), float(yolk.stretch), float(yolk.axis), float(yolk.deflate))
	var lean := Vector4(sag.x, sag.y, float(yolk.tear), tear_angle)
	var sent: Array = yolk.get("sent", [])
	if sent.size() == 3 and _close(sent[0], shape) and _close(sent[1], lean) and is_equal_approx(float(sent[2]), fade):
		return
	node.set_instance_shader_parameter(&"shape", shape)
	node.set_instance_shader_parameter(&"lean", lean)
	node.set_instance_shader_parameter(&"look", Vector4(float(yolk.seed), fade, 0.0, 0.0))
	yolk.sent = [shape, lean, fade]


static func _close(a: Vector4, b: Vector4) -> bool:
	var d := (a - b).abs()
	return maxf(maxf(d.x, d.y), maxf(d.z, d.w)) < 0.002


## Two twisted cords from opposite poles of each yolk out into the thick white,
## dragged along when the yolk slides.
func _place_chalazae(entry: Dictionary, remeasure: bool, visible_now: bool) -> void:
	var splat := entry.model as GoalStandEggSplat
	var cords: Array = entry.chalazae
	var locals: Array = entry.get("cord_locals", [])
	if locals.size() != cords.size():
		locals.resize(cords.size())
		remeasure = true
	if remeasure:
		for index in range(splat.yolks.size()):
			var yolk: Dictionary = splat.yolks[index]
			var axis := Vector2.from_angle(float(yolk.axis) + float(yolk.seed) * 2.0)
			if not yolk.has("chalaza_ends"):
				yolk.chalaza_ends = [(yolk.pos as Vector2) + axis * float(yolk.radius) * 2.1, (yolk.pos as Vector2) - axis * float(yolk.radius) * 1.9]
			for side in range(2):
				if index * 2 + side >= cords.size():
					break
				var pole := (yolk.pos as Vector2) + axis * (1.0 if side == 0 else -1.0) * float(yolk.radius) * 0.85
				var end: Vector2 = (yolk.chalaza_ends as Array)[side]
				# The cord is anchored in gel that gives: stretched far, its end drags along.
				var longest := float(yolk.radius) * 1.6
				if end.distance_to(pole) > longest:
					end = pole + (end - pole).normalized() * longest
					(yolk.chalaza_ends as Array)[side] = end
				var a := splat.surface_position(pole, splat.film + splat.thick_height * 0.3)
				var span := splat.surface_position(end, splat.film + splat.thick_height * 0.2) - a
				if span.length() < 0.005:
					locals[index * 2 + side] = null
					continue
				var y := span.normalized()
				var x := y.cross(Vector3.UP)
				x = x.normalized() if x.length() > 0.001 else GoalStandEggBody._any_tangent(y)
				var thickness := 0.013 * (1.0 - 0.3 * clampf(span.length() / float(yolk.radius) - 1.0, 0.0, 1.0))
				locals[index * 2 + side] = Transform3D(Basis(x * thickness, y * span.length(), x.cross(y) * thickness * 0.5), a)
		entry.cord_locals = locals
	var frame: Transform3D = entry.frame
	for index in range(cords.size()):
		var node := cords[index] as MeshInstance3D
		var local: Variant = locals[index]
		node.visible = visible_now and local != null
		if local != null:
			node.transform = frame * (local as Transform3D)


func _place_captured(entry: Dictionary, visible_now: bool) -> void:
	var splat := entry.model as GoalStandEggSplat
	var frame: Transform3D = entry.frame
	var fade := clampf(float(entry.fading) / FADE_TIME, 0.0, 1.0) if float(entry.fading) >= 0.0 else 0.0
	var remeasure := fade > 0.0 or (splat.awake and (_tick + int(entry.row)) % CORD_EVERY == 0)
	for shard: Dictionary in entry.captured:
		if remeasure or not shard.has("local"):
			var surface := splat.surface(shard.at, (splat.film + splat.thick_height * 0.4) * float(shard.sink))
			shard.local = Transform3D(_tilt(surface.normal) * (shard.tilt as Basis) * (1.0 - fade), surface.position)
		var node := shard.node as MeshInstance3D
		node.transform = frame * (shard.local as Transform3D)
		node.visible = visible_now


## Basis turning +Y onto `normal` (the shortest way).
static func _tilt(normal: Vector3) -> Basis:
	var n := normal.normalized()
	var axis := Vector3.UP.cross(n)
	if axis.length() < 0.00001:
		return Basis.IDENTITY if n.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(axis.normalized(), acos(clampf(n.y, -1.0, 1.0)))


func _remove_splat(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	_splats.erase(entry)
	_give(entry.node)
	for list_name in ["rivulets", "yolks", "chalazae"]:
		for node: Variant in entry[list_name]:
			_give(node)
	for shard: Dictionary in entry.captured:
		_give(shard.node)
	var row := int(entry.row)
	var base := row * GoalStandEggSplat.ROW_TEXELS * 4
	for index in range(GoalStandEggSplat.ROW_TEXELS * 4):
		_data[base + index] = 0.0
	_dirty = true
	_free_rows.append(row)
	for drip: Dictionary in _drips:
		if drip.splat == entry:
			drip.orphan = true
	for strand: Dictionary in _strands:
		if strand.splat == entry:
			(strand.model as GoalStandEggStrand).broken = true


# ------------------------------------------------------------------ drips

func _feed_drip(entry: Dictionary, event: Dictionary) -> void:
	var q: Vector2 = event.q
	for drip: Dictionary in _drips:
		if drip.splat == entry and (drip.q as Vector2).distance_to(q) < 0.06 and int((drip.model as GoalStandEggDrip).kind) == int(event.kind):
			(drip.model as GoalStandEggDrip).add_supply(float(event.supply), float(event.flux))
			return
	if _drips.size() >= int(detail.drips):
		return
	var frame: Transform3D = entry.frame
	var gravity := frame.basis.transposed() * GRAVITY
	var down := Vector2(gravity.x, gravity.z).normalized()
	# Hang just under the rounded edge.
	var under := q + down * GoalStandEggSplat.EDGE_ROUND * 1.7
	var at := _surface_world(entry, under, 0.0)
	var drip := GoalStandEggDrip.create(model, int(event.kind) as GoalStandEggDrip.Kind, at, float(event.supply), float(event.flux), _rng.randi())
	var node := _take("drip", _drip_mesh, _drip_material)
	_drips.append({"model": drip, "node": node, "splat": entry, "q": q, "under": under, "orphan": false, "seed": _rng.randf()})


func _update_drips(delta: float) -> void:
	for index in range(_drips.size() - 1, -1, -1):
		var entry: Dictionary = _drips[index]
		var drip := entry.model as GoalStandEggDrip
		if bool(entry.orphan):
			# Its splat is gone: what hangs there lets go now.
			if drip.phase == GoalStandEggDrip.Phase.GROW or drip.phase == GoalStandEggDrip.Phase.NECK:
				if drip.volume > 1.0e-6:
					_add_drop(drip.bulb, drip.bulb_velocity, drip.bulb_radius(), drip.kind, 0.2)
			_give(entry.node)
			_drips.remove_at(index)
			continue
		var edge := _surface_world(entry.splat, entry.under, 0.0)
		_events.clear()
		drip.step(delta, edge, _events)
		for event: Dictionary in _events:
			_add_drop(event.position, event.velocity, float(event.radius), int(event.kind), DROP_PINCH_WOBBLE)
			drips_fallen += 1
		if drip.is_done():
			_give(entry.node)
			_drips.remove_at(index)
			continue
		var node := entry.node as MeshInstance3D
		var axis := drip.axis()
		var y := -axis
		var x := GoalStandEggBody._any_tangent(y)
		node.transform = Transform3D(Basis(x, y, x.cross(y)), drip.anchor)
		node.set_instance_shader_parameter(&"shape", drip.shape())
		node.set_instance_shader_parameter(&"look", Vector4(float(drip.kind), 0.0, 1.0, float(entry.seed)))
		node.visible = _anchor_visible(entry.splat)


# ------------------------------------------------------------------ free drops and puddles

func _add_drop(position: Vector3, velocity: Vector3, radius: float, kind: int, wobble: float) -> void:
	if _drops.size() >= int(detail.drops):
		var oldest: Dictionary = _drops.pop_front()
		_give(oldest.node)
	var node := _take("drop", _drip_mesh, _drip_material)
	var omega := sqrt(8.0 * model.gamma_rho / pow(maxf(radius, 0.002), 3.0))
	_drops.append({"node": node, "position": position, "velocity": velocity, "radius": radius, "kind": kind,
		"wobble": wobble, "wobble_velocity": 0.0, "omega": minf(omega, 90.0), "age": 0.0})
	_place_drop(_drops.back())


func _update_drops(delta: float) -> void:
	for index in range(_drops.size() - 1, -1, -1):
		var drop: Dictionary = _drops[index]
		drop.age = float(drop.age) + delta
		var velocity: Vector3 = drop.velocity
		velocity += GRAVITY * delta
		velocity -= velocity * velocity.length() * 0.02 * delta
		var position: Vector3 = drop.position + velocity * delta
		var w := GoalStandEggRheology.oscillator_step(float(drop.wobble), float(drop.wobble_velocity), 0.0, float(drop.omega), DROP_WOBBLE_ZETA, delta)
		drop.wobble = w.x
		drop.wobble_velocity = w.y
		drop.velocity = velocity
		drop.position = position
		var ground := _ground_at(position)
		if position.y - float(drop.radius) <= float(ground.y) and velocity.y < 0.0:
			var volume := 4.0 / 3.0 * PI * pow(float(drop.radius), 3.0)
			_deposit(Vector3(position.x, float(ground.y), position.z), volume, int(drop.kind), velocity, ground)
			drops_landed += 1
			_give(drop.node)
			_drops.remove_at(index)
			continue
		if float(drop.age) > DROP_MAX_LIFE:
			_give(drop.node)
			_drops.remove_at(index)
			continue
		_place_drop(drop)


func _place_drop(drop: Dictionary) -> void:
	var node := drop.node as MeshInstance3D
	var velocity: Vector3 = drop.velocity
	var y := -velocity.normalized() if velocity.length() > 0.5 else Vector3.UP
	var x := GoalStandEggBody._any_tangent(y)
	var r := float(drop.radius)
	node.transform = Transform3D(Basis(x, y, x.cross(y)), (drop.position as Vector3) + y * r)
	node.set_instance_shader_parameter(&"shape", Vector4(0.0, 0.0, r, 0.0))
	node.set_instance_shader_parameter(&"look", Vector4(float(drop.kind), float(drop.wobble), 1.0, 0.0))


## Where something falling at `position` lands: the lift deck under it, else the conveyor.
func _ground_at(position: Vector3) -> Dictionary:
	var holder := support.get("node") as Node3D
	if holder != null and is_instance_valid(holder) and holder.is_inside_tree():
		var top := holder.global_transform * Vector3(0.0, float(support.get("top", 0.0)), 0.0)
		var flat := Vector2(position.x - top.x, position.z - top.z)
		if flat.length() <= float(support.get("radius", 0.0)) and position.y >= top.y - 0.3:
			return {"y": top.y, "node": holder}
	return {"y": FLOOR_Y, "node": null}


## Liquid landed: it joins a puddle or splat it fell into, or starts a puddle.
func _deposit(point: Vector3, volume: float, kind: int, velocity: Vector3, ground: Dictionary) -> void:
	var yolk := kind == GoalStandEggDrip.Kind.YOLK
	var holder: Variant = ground.node
	for entry: Dictionary in _splats:
		if float(entry.fading) >= 0.0 or entry.body != null:
			continue
		if entry.support_node != holder:
			continue
		var splat := entry.model as GoalStandEggSplat
		var local := (entry.frame as Transform3D).affine_inverse() * point
		var at := Vector2(local.x, local.z)
		if absf(local.y) > 0.05 or at.length() > splat.rim_at(at.angle()) + 0.015:
			continue
		if splat.kind == GoalStandEggSplat.Kind.PUDDLE and bool(entry.get("yolk", false)) == yolk:
			splat.absorb(at, {"volume": volume, "normal_speed": absf(velocity.y) * 0.3})
			entry.dirty = true
			return
		if splat.kind == GoalStandEggSplat.Kind.SPLAT and not yolk:
			splat.thin_volume += volume
			entry.dirty = true
			return
	var group := "puddle"
	var frame := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), point + Vector3.UP * FLOOR_LAYER * float(_rng.randi_range(0, FLOOR_LAYERS - 1)))
	var puddle := GoalStandEggSplat.create(model, {"volume": volume, "normal_speed": absf(velocity.y), "seed": _rng.randi()}, GoalStandEggSplat.Kind.PUDDLE)
	puddle.yolk_pool = yolk
	var entry := _add_splat(puddle, group, frame)
	entry.yolk = yolk
	if holder != null:
		entry.support_node = holder
		entry.support_local = (holder as Node3D).global_transform.affine_inverse() * frame.origin


# ------------------------------------------------------------------ strands

func _update_strands(delta: float) -> void:
	for index in range(_strands.size() - 1, -1, -1):
		var entry: Dictionary = _strands[index]
		var strand := entry.model as GoalStandEggStrand
		var shard: Dictionary = entry.shard
		var raw: Variant = shard.get("node")
		var shard_node: Node3D = raw as Node3D if is_instance_valid(raw) else null
		var from := strand.a
		if _splats.has(entry.splat):
			var splat := (entry.splat as Dictionary).model as GoalStandEggSplat
			from = _surface_world(entry.splat, entry.at, splat.film + splat.thick_height * 0.5)
		if shard_node == null or not is_instance_valid(shard_node) or float(shard.get("rested", -1.0)) >= 0.0:
			strand.broken = true
		var pull := strand.step(delta, from, shard_node.global_position if shard_node != null else strand.b)
		if pull != Vector3.ZERO and shard.has("velocity"):
			shard.velocity = (shard.velocity as Vector3) + pull * delta
		if strand.is_done():
			_give(entry.node)
			_strands.remove_at(index)
			continue
		var shape := strand.shape()
		var node := entry.node as MeshInstance3D
		var p0: Vector3 = shape.p0
		var p1: Vector3 = shape.p1
		var p2: Vector3 = shape.p2
		var low := p0.min(p1).min(p2) - Vector3.ONE * 0.05
		var high := p0.max(p1).max(p2) + Vector3.ONE * 0.05
		node.custom_aabb = AABB(low, high - low)
		node.set_instance_shader_parameter(&"p0", Vector4(p0.x, p0.y, p0.z, float(shape.radius)))
		node.set_instance_shader_parameter(&"p1", Vector4(p1.x, p1.y, p1.z, float(shape.beading)))
		node.set_instance_shader_parameter(&"p2", Vector4(p2.x, p2.y, p2.z, strand.seed))


# ------------------------------------------------------------------ yolks that fall off

func _release_yolk(entry: Dictionary, event: Dictionary) -> void:
	var yolk: Dictionary = event.yolk
	var frame: Transform3D = entry.frame
	var splat := entry.model as GoalStandEggSplat
	var nodes: Array = entry.yolks
	var node: MeshInstance3D = null
	if not nodes.is_empty():
		node = nodes.pop_back()
		if bool(detail.chalazae):
			for _side in range(2):
				if not (entry.chalazae as Array).is_empty():
					_give((entry.chalazae as Array).pop_back())
	if node == null:
		node = _take("yolk", _yolk_mesh, _yolk_material)
	yolks_fallen += 1
	# Over the cap the oldest fade out; past one more the oldest fading one goes now.
	var steady := 0
	for loose: Dictionary in _loose_yolks:
		steady += 1 if float(loose.fading) < 0.0 else 0
	for loose: Dictionary in _loose_yolks:
		if steady < int(detail.loose_yolks):
			break
		if float(loose.fading) < 0.0:
			loose.fading = 0.0
			steady -= 1
	while _loose_yolks.size() >= int(detail.loose_yolks) + 1:
		_give(_loose_yolks.pop_front().node)
	var surface := splat.surface(event.q, splat.film * 0.35)
	var slide: Vector2 = event.vel
	var velocity := frame.basis * Vector3(slide.x, 0.0, slide.y) + frame.basis * (surface.normal as Vector3) * 0.25
	velocity += entry.get("point_velocity", Vector3.ZERO)
	_loose_yolks.append({"node": node, "position": frame * (surface.position as Vector3), "velocity": velocity, "yolk": yolk,
		"up": (frame.basis * (surface.normal as Vector3)).normalized(), "landed": false, "support_node": null,
		"support_local": Vector3.ZERO, "fading": -1.0})


func _update_loose_yolks(delta: float) -> void:
	for index in range(_loose_yolks.size() - 1, -1, -1):
		var loose: Dictionary = _loose_yolks[index]
		var yolk: Dictionary = loose.yolk
		var node := loose.node as MeshInstance3D
		if float(loose.fading) >= 0.0:
			loose.fading = float(loose.fading) + delta
			if float(loose.fading) >= FADE_TIME:
				_give(node)
				_loose_yolks.remove_at(index)
				continue
		var omega := model.yolk_omega
		var f := GoalStandEggRheology.oscillator_step(float(yolk.flatten), float(yolk.flatten_vel), -0.55 * float(yolk.deflate), omega, GoalStandEggRheology.YOLK_DAMPING_RATIO, delta)
		yolk.flatten = f.x
		yolk.flatten_vel = f.y
		var s := GoalStandEggRheology.oscillator_step(float(yolk.stretch), float(yolk.stretch_vel), 0.0, omega * 1.3, GoalStandEggRheology.YOLK_DAMPING_RATIO, delta)
		yolk.stretch = s.x
		yolk.stretch_vel = s.y
		yolk.sag = (yolk.sag as Vector2).lerp(Vector2.ZERO, 1.0 - exp(-4.0 * delta))
		if float(yolk.tear) >= 0.0:
			yolk.tear = minf(1.0, float(yolk.tear) + delta / GoalStandEggSplat.YOLK_TEAR_TIME)
			yolk.deflate = minf(1.0, float(yolk.deflate) + delta / 0.6)
		var position: Vector3 = loose.position
		var velocity: Vector3 = loose.velocity
		if not bool(loose.landed):
			velocity += GRAVITY * delta
			position += velocity * delta
			# Surface tension pulls it round and it turns upright as it falls.
			loose.up = (loose.up as Vector3).slerp(Vector3.UP, 1.0 - exp(-delta * 4.0)).normalized()
			yolk.flatten = lerpf(float(yolk.flatten), 0.08, 1.0 - exp(-delta * 6.0))
			var ground := _ground_at(position)
			if position.y <= float(ground.y) and velocity.y < 0.0:
				_land_yolk(loose, Vector3(position.x, float(ground.y), position.z), velocity, ground)
				position = loose.position
				velocity = loose.velocity
		else:
			velocity *= exp(-6.0 * delta)
			position += velocity * delta
			var holder := loose.support_node as Node3D
			if holder != null and is_instance_valid(holder):
				loose.support_local = (loose.support_local as Vector3) + holder.global_transform.basis.inverse() * (velocity * delta)
				position = holder.global_transform * (loose.support_local as Vector3)
		loose.position = position
		loose.velocity = velocity
		var fade := clampf(float(loose.fading) / FADE_TIME, 0.0, 1.0) if float(loose.fading) >= 0.0 else 0.0
		node.transform = Transform3D(_tilt(loose.up) * Basis.from_scale(Vector3.ONE * float(yolk.radius)), position)
		node.set_instance_shader_parameter(&"shape", Vector4(float(yolk.flatten), float(yolk.stretch), float(yolk.axis), float(yolk.deflate)))
		var sag: Vector2 = yolk.sag
		node.set_instance_shader_parameter(&"lean", Vector4(sag.x, sag.y, float(yolk.tear), float(yolk.axis)))
		node.set_instance_shader_parameter(&"look", Vector4(float(yolk.seed), fade, 0.0, 0.0))


## The membrane holds: it splats flat, bounces a little and wobbles; on a hard
## landing it can burst and spill. It lands in a little of the white it carried.
func _land_yolk(loose: Dictionary, point: Vector3, velocity: Vector3, ground: Dictionary) -> void:
	var yolk: Dictionary = loose.yolk
	var speed := absf(velocity.y)
	yolk.flatten = -clampf(speed / 9.0, 0.2, 0.55)
	yolk.flatten_vel = 0.0
	yolk.stretch = clampf(Vector2(velocity.x, velocity.z).length() * 0.06, 0.0, 0.3)
	yolk.axis = Vector2(velocity.x, -velocity.z).angle()
	loose.up = Vector3.UP
	var bounce := speed * YOLK_RESTITUTION
	if bounce > 0.6:
		loose.velocity = Vector3(velocity.x * 0.3, bounce, velocity.z * 0.3)
		loose.position = point + Vector3.UP * 0.001
		return
	loose.landed = true
	loose.velocity = Vector3(velocity.x * 0.25, 0.0, velocity.z * 0.25)
	loose.position = point
	var holder: Variant = ground.node
	if holder != null:
		loose.support_node = holder
		loose.support_local = (holder as Node3D).global_transform.affine_inverse() * point
	if float(yolk.tear) < 0.0 and speed > YOLK_LANDING_BURST and _rng.randf() < YOLK_BURST_CHANCE:
		yolk.tear = 0.0
		ruptures += 1
		_deposit(point, float(yolk.volume) * 0.45, GoalStandEggDrip.Kind.YOLK, velocity * 0.2, ground)
	_deposit(point + Vector3(_rng.randf_range(-0.03, 0.03), 0.0, _rng.randf_range(-0.03, 0.03)), model.thin_volume * 0.05,
		GoalStandEggDrip.Kind.THIN, velocity * 0.2, ground)


# ------------------------------------------------------------------ pools, inspection

func _take(kind: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var pool: Array = _pools.get(kind, [])
	var node: MeshInstance3D
	if not pool.is_empty():
		node = pool.pop_back()
		node.visible = true
	else:
		node = MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		node.extra_cull_margin = 1.0
		node.set_meta(&"egg_pool", kind)
		add_child(node)
	return node


func _give(node: Variant) -> void:
	if node == null or not is_instance_valid(node):
		return
	var instance := node as MeshInstance3D
	instance.visible = false
	var kind := String(instance.get_meta(&"egg_pool", ""))
	var pool: Array = _pools.get(kind, [])
	pool.append(instance)
	_pools[kind] = pool


func counts() -> Dictionary:
	var groups := {"body_splats": 0, "floor_splats": 0, "puddles": 0}
	var awake := 0
	var yolks := 0
	var captured := 0
	for entry: Dictionary in _splats:
		var key := "body_splats" if String(entry.group).begins_with("body:") else ("puddles" if entry.group == "puddle" else "floor_splats")
		groups[key] = int(groups[key]) + 1
		awake += 1 if (entry.model as GoalStandEggSplat).awake else 0
		yolks += (entry.yolks as Array).size()
		captured += (entry.captured as Array).size()
	var nodes := 0
	for child in get_children():
		nodes += 1 if (child as Node3D).visible else 0
	groups.merge({"drips": _drips.size(), "drops": _drops.size(), "strands": _strands.size(), "loose_yolks": _loose_yolks.size(),
		"yolks": yolks, "captured": captured, "awake": awake, "rows_used": ROWS - _free_rows.size(), "visible_nodes": nodes,
		"splats_made": splats_made, "merges": merges, "ruptures": ruptures, "drops_landed": drops_landed,
		"yolks_fallen": yolks_fallen, "drips_fallen": drips_fallen,
		"fluid": fluid.get_debug_snapshot() if fluid != null else {}})
	return groups


## Live splat entries, oldest first (tests and debugging).
func splats() -> Array[Dictionary]:
	return _splats


func clear() -> void:
	for entry: Dictionary in _splats.duplicate():
		_remove_splat(entry)
	for list: Array in [_drips, _drops, _strands, _loose_yolks]:
		for entry: Dictionary in list:
			_give(entry.node)
		list.clear()
	for child in get_children():
		if child != fluid:
			child.queue_free()
	if fluid != null:
		fluid.clear()
	_pools.clear()
	_bodies.clear()
	_data.fill(0.0)
	_dirty = true
	splats_made = 0
	merges = 0
	ruptures = 0
	drops_landed = 0
	yolks_fallen = 0
	drips_fallen = 0
