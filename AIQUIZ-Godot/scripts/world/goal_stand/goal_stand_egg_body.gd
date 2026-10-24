class_name GoalStandEggBody
extends RefCounted

## What an egg can hit on a body, as simple proxies: raycasts for where it breaks,
## and anchors that keep a splat on the surface while the body moves.
## - A blockman player (PlayerSkinRig parts under its Pelvis): one box per part
##   mesh, the mesh's own AABB in its own frame (the data PlayerSkinRig.pick uses).
## - A skinned rig (the mascot referee): one capsule per deforming bone, its
##   radius fitted once to the skin's vertices.
## Anchors live in the part's (or bone's) frame. frame() hands out a world frame
## that is always right-handed: the finale mirrors its stage when P2 wins, and a
## splat parented through that mirror would be lit inside out.

enum Shape { BOX, CAPSULE }

## Bones thinner than this, or with fewer skin vertices, are not worth a capsule.
const MIN_CAPSULE_RADIUS := 0.035
const MIN_CAPSULE_VERTICES := 24
## Radius = this percentile of the skin's distances from the bone axis.
const CAPSULE_PERCENTILE := 0.7
## A coplanar neighbour (the lower torso under the chest) extends a face when it is
## this close to the face plane and covers its width.
const COPLANAR := 0.02
const COVER := 0.05

static var _capsule_cache := {}

var target: Node3D
var shapes: Array[Dictionary] = []
var _order: Array[int] = []


static func from_target(body: Node3D) -> GoalStandEggBody:
	var proxies := GoalStandEggBody.new()
	proxies.target = body
	if body == null:
		return proxies
	var pelvis := body.get_parent() as Node3D
	if pelvis != null and pelvis.has_meta(PlayerSkinRig.GROUPS_META):
		proxies._add_parts(pelvis)
	else:
		var skeleton := body as Skeleton3D
		if skeleton == null:
			var found := body.find_children("*", "Skeleton3D", true, false)
			skeleton = found[0] as Skeleton3D if not found.is_empty() else null
		if skeleton != null:
			proxies._add_capsules(skeleton)
	return proxies


func _add_parts(pelvis: Node3D) -> void:
	var groups: Dictionary = pelvis.get_meta(PlayerSkinRig.GROUPS_META)
	for part_id: StringName in groups:
		for side: Array in groups[part_id]:
			for mesh_value: Variant in side:
				var mesh := mesh_value as MeshInstance3D
				if mesh == null or mesh.mesh == null:
					continue
				shapes.append({"kind": Shape.BOX, "node": mesh, "aabb": mesh.mesh.get_aabb(), "part": part_id})


func _add_capsules(skeleton: Skeleton3D) -> void:
	var key := skeleton.get_instance_id()
	if not _capsule_cache.has(key):
		_capsule_cache[key] = _fit_capsules(skeleton)
	for capsule: Dictionary in _capsule_cache[key]:
		var entry := capsule.duplicate()
		entry.kind = Shape.CAPSULE
		entry.skeleton = skeleton
		shapes.append(entry)


## Capsules along the deforming bones (+Y in bone space, out to the child bone),
## each radius fitted to the skin vertices that bone moves the most.
static func _fit_capsules(skeleton: Skeleton3D) -> Array[Dictionary]:
	var radial := {}
	var spans := {}
	for bone in range(skeleton.get_bone_count()):
		var length := 0.0
		for child in skeleton.get_bone_children(bone):
			length = maxf(length, skeleton.get_bone_rest(child).origin.length())
		spans[bone] = length
		# A plain Array: appending to a packed array fetched from a dictionary would
		# only change a copy.
		radial[bone] = []
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var skin := mesh_instance.skin
		if mesh_instance.mesh == null or skin == null:
			continue
		var binds := PackedInt32Array()
		for bind in range(skin.get_bind_count()):
			var bone := skin.get_bind_bone(bind)
			binds.append(bone if bone >= 0 else skeleton.find_bone(skin.get_bind_name(bind)))
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: Variant = arrays[Mesh.ARRAY_BONES]
			var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null or vertices.is_empty():
				continue
			var per: int = bones.size() / vertices.size()
			for index in range(vertices.size()):
				var best := 0
				var best_weight := -1.0
				for slot in range(per):
					var w := float(weights[index * per + slot])
					if w > best_weight:
						best_weight = w
						best = int(bones[index * per + slot])
				if best < 0 or best >= binds.size():
					continue
				var bone := binds[best]
				if bone < 0 or not spans.has(bone) or float(spans[bone]) <= 0.0:
					continue
				var local := skin.get_bind_pose(best) * vertices[index]
				if local.y < 0.0 or local.y > float(spans[bone]):
					continue
				(radial[bone] as Array).append(Vector2(local.x, local.z).length())
	var capsules: Array[Dictionary] = []
	for bone: int in radial:
		var distances := PackedFloat32Array(radial[bone])
		if distances.size() < MIN_CAPSULE_VERTICES:
			continue
		distances.sort()
		var radius := distances[int((distances.size() - 1) * CAPSULE_PERCENTILE)]
		if radius < MIN_CAPSULE_RADIUS:
			continue
		capsules.append({"bone": bone, "length": float(spans[bone]), "radius": radius, "name": skeleton.get_bone_name(bone)})
	return capsules


func is_empty() -> bool:
	return shapes.is_empty()


## The shape's current world transform, or null when its node is gone.
func shape_transform(index: int) -> Variant:
	var shape: Dictionary = shapes[index]
	var holder: Variant = shape.node if int(shape.kind) == Shape.BOX else shape.skeleton
	# A freed part cannot even be cast, so check before touching it.
	if not is_instance_valid(holder) or not (holder as Node3D).is_inside_tree():
		return null
	if int(shape.kind) == Shape.BOX:
		return (holder as Node3D).global_transform
	var skeleton := holder as Skeleton3D
	return skeleton.global_transform * skeleton.get_bone_global_pose(int(shape.bone))


## First proxy the ray hits within `max_distance`: {shape, point, normal, distance},
## or an empty dictionary.
func raycast(origin: Vector3, dir: Vector3, max_distance: float = 3.0) -> Dictionary:
	var best := {}
	var best_t := max_distance
	dir = dir.normalized()
	for index in range(shapes.size()):
		var xform: Variant = shape_transform(index)
		if xform == null:
			continue
		var shape: Dictionary = shapes[index]
		if int(shape.kind) == Shape.BOX:
			var node := shape.node as MeshInstance3D
			if not node.is_visible_in_tree():
				continue
		var inverse := (xform as Transform3D).affine_inverse()
		var local_origin := inverse * origin
		var local_dir := inverse.basis * dir
		var hit := _ray_box(local_origin, local_dir, shape.aabb) if int(shape.kind) == Shape.BOX \
			else _ray_capsule(local_origin, local_dir, float(shape.length), float(shape.radius))
		if hit.is_empty():
			continue
		var world := (xform as Transform3D) * (hit.point as Vector3)
		var t := origin.distance_to(world)
		if t < best_t:
			best_t = t
			best = {"shape": index, "point": world, "local_point": hit.point, "local_normal": hit.normal, "distance": t,
				"normal": _world_normal(xform as Transform3D, hit.normal)}
	return best


## Where an egg that ended up at `point` (inside or next to the body) breaks when
## the ray from `point - dir` misses: on the nearest shape, approached from outside.
func nearest(point: Vector3, dir: Vector3) -> Dictionary:
	var best_index := -1
	var best_distance := INF
	for index in range(shapes.size()):
		var xform: Variant = shape_transform(index)
		if xform == null:
			continue
		var distance := (xform as Transform3D).origin.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index < 0:
		return {}
	var centre := shape_centre(best_index)
	var from := point - dir.normalized() * 1.5
	var hit := raycast(from, centre - from, 4.0)
	return hit


func shape_centre(index: int) -> Vector3:
	var xform: Variant = shape_transform(index)
	var shape: Dictionary = shapes[index]
	if xform == null:
		return Vector3.ZERO
	if int(shape.kind) == Shape.BOX:
		return (xform as Transform3D) * (shape.aabb as AABB).get_center()
	return (xform as Transform3D) * Vector3(0.0, float(shape.length) * 0.5, 0.0)


## Anchor for a splat at `hit`: the frame in the shape's own space and the face's
## bounds in the splat plane (GoalStandEggSplat extents, depth, wrap).
func anchor_for(hit: Dictionary) -> Dictionary:
	var index := int(hit.shape)
	var shape: Dictionary = shapes[index]
	var local_point: Vector3 = hit.local_point
	var local_normal: Vector3 = hit.local_normal
	var anchor := {"shape": index, "local_point": local_point, "local_normal": local_normal}
	if int(shape.kind) == Shape.BOX:
		var axis := _major_axis(local_normal)
		var u := Vector3.ZERO
		u[(axis + 1) % 3] = 1.0
		anchor.local_u = u
		anchor.wrap = GoalStandEggSplat.Wrap.BOX
		var frame := frame_of(anchor)
		var aabb: AABB = shape.aabb
		var bounds := _project_box(frame, shape_transform(index) as Transform3D, aabb)
		bounds = _extend_coplanar(frame, index, bounds)
		anchor.extents = bounds
		anchor.depth = aabb.size[axis]
	else:
		anchor.local_u = Vector3.UP
		anchor.wrap = GoalStandEggSplat.Wrap.CAPSULE
		var along := local_point.y
		anchor.extents = Vector4(-along, float(shape.length) - along, -PI * float(shape.radius), PI * float(shape.radius))
		anchor.depth = float(shape.radius)
	return anchor


## World frame of an anchor: origin on the surface, +Y the surface normal, +X the
## face's first axis (the bone axis on a capsule). Right-handed even when mirrored.
func frame_of(anchor: Dictionary) -> Transform3D:
	var xform: Variant = shape_transform(int(anchor.shape))
	if xform == null:
		return Transform3D()
	var t := xform as Transform3D
	var n := _world_normal(t, anchor.local_normal)
	var u := t.basis * (anchor.local_u as Vector3)
	u = (u - n * u.dot(n))
	u = u.normalized() if u.length() > 0.0001 else _any_tangent(n)
	return Transform3D(Basis(u, n, u.cross(n)), t * (anchor.local_point as Vector3))


func is_live(anchor: Dictionary) -> bool:
	var index := int(anchor.get("shape", -1))
	return index >= 0 and index < shapes.size() and shape_transform(index) != null


## The node a shape follows (its part mesh, or the skeleton), or null once freed.
func shape_node(index: int) -> Node3D:
	var shape: Dictionary = shapes[index]
	var holder: Variant = shape.node if int(shape.kind) == Shape.BOX else shape.skeleton
	return holder as Node3D if is_instance_valid(holder) else null


## Packed for the GPU fluid (GoalStandEggFluid): per shape 4 vec4s, the biggest
## `limit` shapes (the torso and limbs before the finger pieces).
## Box: (centre, kind 0), (axis x * half extent, 0), (axis y * half, 0), (axis z * half, 0).
## Capsule: (a, kind 1), (b, radius), 0, 0.
func pack_for_gpu(limit: int) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	var count := 0
	for index in _by_size():
		if count >= limit:
			break
		var xform: Variant = shape_transform(index)
		if xform == null:
			continue
		var t := xform as Transform3D
		var shape: Dictionary = shapes[index]
		if int(shape.kind) == Shape.BOX:
			if not (shape.node as MeshInstance3D).is_visible_in_tree():
				continue
			var aabb: AABB = shape.aabb
			var centre := t * aabb.get_center()
			var half := aabb.size * 0.5
			data.append_array(PackedFloat32Array([centre.x, centre.y, centre.z, 0.0]))
			for axis in range(3):
				var v := t.basis[axis] * half[axis]
				data.append_array(PackedFloat32Array([v.x, v.y, v.z, 0.0]))
		else:
			var a := t.origin
			var b := t * Vector3(0.0, float(shape.length), 0.0)
			data.append_array(PackedFloat32Array([a.x, a.y, a.z, 1.0, b.x, b.y, b.z, float(shape.radius), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
		count += 1
	return data


# ------------------------------------------------------------------ helpers

## Shape indices, largest first (cached: the proxies never change).
func _by_size() -> Array[int]:
	if _order.size() == shapes.size():
		return _order
	var sized: Array[Vector2] = []
	for index in range(shapes.size()):
		var shape: Dictionary = shapes[index]
		var size := (shape.aabb as AABB).get_volume() if int(shape.kind) == Shape.BOX 			else PI * pow(float(shape.radius), 2.0) * float(shape.length)
		sized.append(Vector2(size, index))
	sized.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	_order.clear()
	for item in sized:
		_order.append(int(item.y))
	return _order


static func _world_normal(t: Transform3D, local_normal: Vector3) -> Vector3:
	var n := t.basis.inverse().transposed() * local_normal
	return n.normalized() if n.length() > 0.00001 else Vector3.UP


static func _major_axis(v: Vector3) -> int:
	var a := v.abs()
	return 0 if a.x >= a.y and a.x >= a.z else (1 if a.y >= a.z else 2)


## Slab test that also reports which face the ray enters through.
static func _ray_box(origin: Vector3, dir: Vector3, box: AABB) -> Dictionary:
	var t_min := -INF
	var t_max := INF
	var axis_in := -1
	for axis in range(3):
		var o := origin[axis]
		var d := dir[axis]
		var lo := box.position[axis]
		var hi := box.end[axis]
		if absf(d) < 0.000001:
			if o < lo or o > hi:
				return {}
			continue
		var t1 := (lo - o) / d
		var t2 := (hi - o) / d
		if minf(t1, t2) > t_min:
			t_min = minf(t1, t2)
			axis_in = axis
		t_max = minf(t_max, maxf(t1, t2))
	if t_max < maxf(t_min, 0.0) or t_min < 0.0 or axis_in < 0:
		return {}
	var normal := Vector3.ZERO
	normal[axis_in] = -signf(dir[axis_in])
	return {"point": origin + dir * t_min, "normal": normal}


## Ray against a capsule from (0, 0, 0) to (0, length, 0) with `radius`.
static func _ray_capsule(origin: Vector3, dir: Vector3, length: float, radius: float) -> Dictionary:
	var best_t := INF
	var best_point := Vector3.ZERO
	var best_normal := Vector3.ZERO
	# The side (infinite cylinder around Y, clipped to the segment).
	var a := dir.x * dir.x + dir.z * dir.z
	if a > 0.0000001:
		var b := 2.0 * (origin.x * dir.x + origin.z * dir.z)
		var c := origin.x * origin.x + origin.z * origin.z - radius * radius
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var t := (-b - sqrt(disc)) / (2.0 * a)
			var p := origin + dir * t
			if t >= 0.0 and p.y >= 0.0 and p.y <= length:
				best_t = t
				best_point = p
				best_normal = Vector3(p.x, 0.0, p.z).normalized()
	# The two end caps.
	for centre: Vector3 in [Vector3.ZERO, Vector3(0.0, length, 0.0)]:
		var oc := origin - centre
		var b := oc.dot(dir)
		var c := oc.length_squared() - radius * radius
		var disc := b * b - c * dir.length_squared()
		if disc < 0.0:
			continue
		var t := (-b - sqrt(disc)) / dir.length_squared()
		if t >= 0.0 and t < best_t:
			var p := origin + dir * t
			if (centre.y == 0.0 and p.y <= 0.0) or (centre.y > 0.0 and p.y >= length):
				best_t = t
				best_point = p
				best_normal = (p - centre).normalized()
	if best_t == INF:
		return {}
	return {"point": best_point, "normal": best_normal}


## Bounds of the box seen in the splat plane of `frame` (x along X, y along Z).
static func _project_box(frame: Transform3D, xform: Transform3D, aabb: AABB) -> Vector4:
	var bounds := Vector4(INF, -INF, INF, -INF)
	var inverse := frame.affine_inverse()
	for corner in range(8):
		var p := inverse * (xform * aabb.get_endpoint(corner))
		bounds = Vector4(minf(bounds.x, p.x), maxf(bounds.y, p.x), minf(bounds.z, p.z), maxf(bounds.w, p.z))
	return bounds


## A neighbour box flush with this face that spans its whole width continues the
## face (the lower torso under the chest), so the white runs on down over it.
func _extend_coplanar(frame: Transform3D, own: int, bounds: Vector4) -> Vector4:
	var inverse := frame.affine_inverse()
	for index in range(shapes.size()):
		var shape: Dictionary = shapes[index]
		if index == own or int(shape.kind) != Shape.BOX:
			continue
		var xform: Variant = shape_transform(index)
		if xform == null:
			continue
		var other := Vector4(INF, -INF, INF, -INF)
		var top := -INF
		for corner in range(8):
			var p := inverse * ((xform as Transform3D) * (shape.aabb as AABB).get_endpoint(corner))
			other = Vector4(minf(other.x, p.x), maxf(other.y, p.x), minf(other.z, p.z), maxf(other.w, p.z))
			top = maxf(top, p.y)
		if absf(top) > COPLANAR:
			continue
		# Spans this face's width along one axis and touches it along the other.
		if other.x <= bounds.x + COVER and other.y >= bounds.y - COVER:
			if other.w >= bounds.z - COVER and other.z < bounds.z:
				bounds.z = minf(bounds.z, other.z)
			if other.z <= bounds.w + COVER and other.w > bounds.w:
				bounds.w = maxf(bounds.w, other.w)
		if other.z <= bounds.z + COVER and other.w >= bounds.w - COVER:
			if other.y >= bounds.x - COVER and other.x < bounds.x:
				bounds.x = minf(bounds.x, other.x)
			if other.x <= bounds.y + COVER and other.y > bounds.y:
				bounds.y = maxf(bounds.y, other.y)
	return bounds


static func _any_tangent(normal: Vector3) -> Vector3:
	var reference := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return reference.cross(normal).normalized()
