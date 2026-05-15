@tool class_name LineMesh extends ImmediateMesh

static var GRADIENT_DEFAULT: Gradient

static func _static_init() -> void:
	GRADIENT_DEFAULT = Gradient.new()
	GRADIENT_DEFAULT.colors = [Color.WHITE]


@export var points: PackedVector3Array = [Vector3.ZERO, Vector3.FORWARD]:
	set(value):
		points = value
		_update_mesh()


@export var color_gradient: Gradient = GRADIENT_DEFAULT:
	set(value):
		color_gradient = value

		_update_mesh()


@export var material: Material:
	set(value):
		material = value
		_update_mesh()


func _init() -> void:
	_update_mesh()


func _surface_get_material(index: int) -> Material:
	return material


func _surface_set_material(index: int, __material__: Material) -> void:
	material = __material__
	material


func _update_mesh() -> void:
	clear_surfaces()

	if points.size() < 2: return

	surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)

	var segment_lengths := PackedFloat32Array()
	segment_lengths.resize(points.size())
	for i in points.size() - 1:
		segment_lengths[i + 1] = segment_lengths[i] + points[i].distance_to(points[i + 1])

	for i in points.size():
		surface_set_color(color_gradient.sample(segment_lengths[i] / segment_lengths[-1]))
		surface_add_vertex(points[i])

	surface_end()
