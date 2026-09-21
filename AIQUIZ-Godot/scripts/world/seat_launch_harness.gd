extends Node3D

## Two Verlet chains paid out from the seat top, rendered as continuous ribbons.
const RopeScript := preload("res://scripts/world/seat_belt_rope.gd")
const SEGMENTS := 80
const WIDTH := .085
const DEPTH := .008
# Front surface sections measured from the shipped plush GLB via Higgsfield
# Bridge. X=.22/.26/.30/.34; rows Y=1.50..2.05 at 5 cm intervals.
const BODY_FRONT := [
	[.0592,.0949,.1153,.1272,.1332,.1326,.1263,.1147,.0962,.0687,.0317,-.0315],
	[.0200,.0622,.0834,.0966,.1032,.1025,.0963,.0841,.0655,.0363,-.0107,-.0796],
	[-.0329,.0192,.0451,.0610,.0689,.0679,.0603,.0457,.0233,-.0137,-.0691,-.1653],
	[-.1371,-.0448,-.0086,.0111,.0193,.0196,.0122,-.0054,-.0305,-.0693,-.1153,-.20],
]
var contact_curve := Curve3D.new()
var straps: Array[MeshInstance3D] = []
var tips: Array[Node3D] = []
var receivers: Array[Node3D] = []
var lamps: Array[MeshInstance3D] = []
var extension := -1.0
var tension := -1.0
var ropes: Array = []
var physics_active := false

func setup() -> void:
	# A close-fitting route, with a short rounded bridge over the two head tips.
	var route: Array[Vector3] = [
		Vector3(.255,2.17,-.70), Vector3(.255,2.265,-.48),
		Vector3(.255,2.285,-.25), Vector3(.265,2.23,-.12),
		Vector3(.285,2.065,-.055), Vector3(.285,1.99,.025),
		Vector3(.285,1.85,.090), Vector3(.275,1.70,.105),
		Vector3(.265,1.55,.070), Vector3(.255,1.455,-.050),
		Vector3(.255,1.34,-.055),
	]
	contact_curve.bake_interval = .004
	for i in route.size():
		var tangent := (route[mini(i + 1, route.size() - 1)] - route[maxi(0, i - 1)]) / 6.0
		contact_curve.add_point(route[i], -tangent, tangent)
	var dark := _material(Color(.035, .05, .065), .55)
	var steel := _material(Color(.70, .77, .82), .75)
	var web := _material(Color.WHITE, 0.0)
	web.vertex_color_use_as_albedo = true
	web.roughness = .8
	for side in [1.0, -1.0]:
		var suffix := "L" if side > 0.0 else "R"
		var outlet := _box("TopReel" + suffix, Vector3(.16, .14, .15), dark, self)
		outlet.position = point(side, 0.0, 1.0)
		var slot := _box("Outlet", Vector3(.13, .045, .016), steel, outlet)
		slot.position.z = .079
		var receiver := _box("SeatLock" + suffix, Vector3(.17, .11, .15), dark, self)
		receiver.position = point(side, 1.0, 1.0)
		receivers.append(receiver)
		var lamp := _box("LockIndicator", Vector3(.10, .026, .014), _material(Color(.95, .20, .025), .1), receiver)
		lamp.position = Vector3(0.0, .015, .082)
		lamps.append(lamp)
		var tip := _box("FlyingTongue" + suffix, Vector3(.14, .085, .035), steel, self)
		var inset := _box("TongueInset", Vector3(.075, .03, .009), dark, tip)
		inset.position.z = .021
		tips.append(tip)
		var strap := MeshInstance3D.new()
		strap.name = "ShoulderWebbing" + suffix
		strap.mesh = ImmediateMesh.new()
		strap.material_override = web
		add_child(strap)
		straps.append(strap)
		var rope := RopeScript.new()
		var shape := PackedVector3Array()
		for i in RopeScript.COUNT + 1: shape.append(point(side, float(i) / RopeScript.COUNT, 1.0))
		rope.setup(shape, side)
		ropes.append(rope)
	set_extension(0.0)

static func body_front(x: float, y: float) -> float:
	var column := clampf((absf(x) - .22) / .04, 0.0, 3.0)
	var row := clampf((y - 1.5) / .05, 0.0, 11.0)
	var c := mini(int(column), 2)
	var r := mini(int(row), 10)
	return lerpf(lerpf(BODY_FRONT[c][r], BODY_FRONT[c][r + 1], row - r),
		lerpf(BODY_FRONT[c + 1][r], BODY_FRONT[c + 1][r + 1], row - r), column - c)

func point(side: float, u: float, taut: float, across: float = 0.0) -> Vector3:
	var p := contact_curve.sample_baked(clampf(u, 0.0, 1.0) * contact_curve.get_baked_length(), true)
	p.x = p.x * side + across
	# Fit the full ribbon width to the rounded body, not just its centerline.
	var contact := smoothstep(1.42, 1.55, p.y) * (1.0 - smoothstep(1.95, 2.18, p.y)) if u > .40 else 0.0
	p.z = lerpf(p.z, body_front(p.x, p.y) + .012, contact)
	return p

func rendered_point(side: float, u: float, across: float = 0.0) -> Vector3:
	if not physics_active: return point(side, u * extension, 1.0, across)
	var rope = ropes[0 if side > 0.0 else 1]
	var p: Vector3 = rope.sample(u)
	p.x += across
	# The flexible strip conforms across its width as the winch seats it.
	var fit: Vector3 = point(side, u, 1.0, across) - point(side, u, 1.0)
	p.z += fit.z * tension
	return p

func set_extension(amount: float, taut: float = 1.0, simulation_time: float = -1.0) -> void:
	amount = clampf(amount, 0.0, 1.0)
	taut = clampf(taut, 0.0, 1.0)
	var simulating := simulation_time >= 0.0
	if not simulating and not physics_active and is_equal_approx(amount, extension) and is_equal_approx(taut, tension): return
	physics_active = simulating
	if simulating:
		for rope in ropes: rope.seek(simulation_time)
	elif amount <= .001:
		for rope in ropes: rope.reset()
	extension = amount
	tension = taut
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var tip := tips[i]
		tip.position = rendered_point(side, 1.0)
		var direction := rendered_point(side, 1.0) - rendered_point(side, .999)
		if direction.length_squared() < .00000001: direction = Vector3.BACK
		var across := Vector3.RIGHT
		var along := -direction.normalized()
		var normal := across.cross(along).normalized()
		tip.basis = Basis(along.cross(normal).normalized(), along, normal)
		tip.visible = amount > .001
		var mat := lamps[i].material_override as StandardMaterial3D
		var latched: bool = ropes[i].locked if physics_active else amount >= .999
		mat.albedo_color = Color(.15, 1.0, .44) if latched else Color(.95, .20, .025)
		var mesh := straps[i].mesh as ImmediateMesh
		mesh.clear_surfaces()
		straps[i].visible = amount > .001
		if amount <= .001: continue
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var rows: Array[PackedVector3Array] = []
		var normals := PackedVector3Array()
		for j in SEGMENTS + 1:
			var u := float(j) / SEGMENTS
			var tangent := rendered_point(side, minf(1.0, u + .001)) - rendered_point(side, maxf(0.0, u - .001))
			var n := tangent.cross(Vector3.RIGHT).normalized()
			normals.append(n)
			var row := PackedVector3Array()
			for width in [-1.0, -.76, .76, 1.0]:
				row.append(rendered_point(side, u, width * WIDTH * .5))
			rows.append(row)
		for j in SEGMENTS:
			var p := rows[j]
			var q := rows[j + 1]
			var n := normals[j] * DEPTH * .5
			var m := normals[j + 1] * DEPTH * .5
			for band in 3:
				var color := Color(.94, .55, .065) if band == 1 else Color(.94, .86, .59)
				_quad(mesh, p[band] + n, q[band] + m, q[band + 1] + m, p[band + 1] + n, color, normals[j], normals[j + 1])
			_quad(mesh, p[0] - n, p[3] - n, q[3] - m, q[0] - m, Color(.76, .40, .025))
			_quad(mesh, p[0] - n, q[0] - m, q[0] + m, p[0] + n, Color(.28, .17, .025))
			_quad(mesh, p[3] + n, q[3] + m, q[3] - m, p[3] - n, Color(.28, .17, .025))
		mesh.surface_end()

func _quad(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal_a := Vector3.ZERO, normal_b := Vector3.ZERO) -> void:
	mesh.surface_set_color(color)
	if normal_a == Vector3.ZERO:
		normal_a = (c - a).cross(b - a).normalized()
		normal_b = normal_a
	var vertices := [a, b, c, a, c, d]
	for i in 6:
		mesh.surface_set_normal(normal_a if i in [0,3,5] else normal_b)
		mesh.surface_add_vertex(vertices[i])

func _material(color: Color, metal: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = .38
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _box(label: String, size: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	node.material_override = mat
	parent.add_child(node)
	return node
