extends MeshInstance3D
class_name MenuJetContrail

## A thin vapour trail behind one jet nozzle for the menu Start departure
## (HelicopterArrivalDirector): a camera-facing ribbon through the points the nozzle has
## passed. It lives in world space, so it stays where the aircraft has been, widens and fades
## with age, and frees itself once its last point has faded after stop().

const LIFETIME := 1.8
const MIN_STEP := 0.3
const MAX_POINTS := 160
const HEAD_WIDTH := 0.14
const TAIL_WIDTH := 1.7
## Metres behind the nozzle over which the trail fades in, so it grows out of the flame.
const HEAD_FADE := 3.0
const HOT_COLOR := Color(1.0, 0.86, 0.66)
const VAPOUR_COLOR := Color(0.97, 0.98, 1.0)

## The nozzle to follow (a HelicopterBoostExhaust). Cleared by stop().
var source: Node3D = null
var opacity := 0.62
var _points: Array[Vector3] = []
var _times: Array[float] = []
var _clock := 0.0
var _ribbon := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _ribbon
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _make_material()


## No new points; the trail already drawn fades out where it is.
func stop() -> void:
	source = null


func _make_material() -> StandardMaterial3D:
	# Soft edges across the ribbon (UV.x 0 → 1).
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var edges := GradientTexture2D.new()
	edges.gradient = gradient
	edges.width = 64
	edges.height = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = edges
	# After the sea, like the jet smoke (HelicopterBoostSmoke): a trail far over the water
	# would otherwise sort behind the ocean plane.
	material.render_priority = 1
	return material


func _process(delta: float) -> void:
	_clock += delta
	if is_instance_valid(source):
		var head := source.global_position
		if _points.size() >= 2 and _points[-2].distance_to(head) < MIN_STEP:
			# Keep the newest point on the nozzle until it has moved far enough for a new one.
			_points[-1] = head
			_times[-1] = _clock
		else:
			_points.append(head)
			_times.append(_clock)
	else:
		source = null
	while not _times.is_empty() and (_clock - _times[0] > LIFETIME or _points.size() > MAX_POINTS):
		_points.pop_front()
		_times.pop_front()
	if source == null and _points.size() < 2:
		queue_free()
		return
	_rebuild()


func _rebuild() -> void:
	_ribbon.clear_surfaces()
	var count := _points.size()
	var camera := get_viewport().get_camera_3d()
	if count < 2 or camera == null:
		return
	var eye := camera.global_position
	# Distance from the head, for the fade-in behind the nozzle.
	var from_head := PackedFloat32Array()
	from_head.resize(count)
	from_head[count - 1] = 0.0
	for index: int in range(count - 2, -1, -1):
		from_head[index] = from_head[index + 1] + _points[index].distance_to(_points[index + 1])
	_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index: int in range(count):
		var point := _points[index]
		var tangent := _points[mini(index + 1, count - 1)] - _points[maxi(index - 1, 0)]
		var side := tangent.cross(eye - point)
		if side.length_squared() <= 0.000001:
			side = Vector3.UP
		side = side.normalized()
		var age := clampf((_clock - _times[index]) / LIFETIME, 0.0, 1.0)
		var half_width := lerpf(HEAD_WIDTH, TAIL_WIDTH, sqrt(age)) * 0.5
		var color := HOT_COLOR.lerp(VAPOUR_COLOR, smoothstep(0.0, 0.12, age))
		color.a = opacity * pow(1.0 - age, 1.5) * smoothstep(0.0, HEAD_FADE, from_head[index])
		_ribbon.surface_set_color(color)
		_ribbon.surface_set_uv(Vector2(0.0, age))
		_ribbon.surface_add_vertex(point - side * half_width)
		_ribbon.surface_set_color(color)
		_ribbon.surface_set_uv(Vector2(1.0, age))
		_ribbon.surface_add_vertex(point + side * half_width)
	_ribbon.surface_end()
