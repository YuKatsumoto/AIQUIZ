extends Node3D
## Four preallocated impact/heel-dust bursts. All ages follow the original hit event.
const POOL_SIZE := 4
const FLASH_TIME := 0.04
const STREAK_TIME := 0.12
const DUST_TIME := 0.22
var slots: Array[Dictionary] = []
var cursor := 0

func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = false
	return material

func _piece(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(piece)
	return piece

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Move toward the game camera so the contact mark sits on the shoulder surface.
	position.z = -0.38
	var streak_mesh := BoxMesh.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radial_segments = 4
	flash_mesh.rings = 1
	var dust_mesh := SphereMesh.new()
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 2
	for i in range(POOL_SIZE):
		var root := Node3D.new()
		root.name = "PushBurst%d" % i
		add_child(root)
		var material := _material()
		var flash_material := _material()
		var dust_material := _material()
		var pieces: Array[MeshInstance3D] = []
		var dust: Array[MeshInstance3D] = []
		for j in range(8):
			pieces.append(_piece(root, streak_mesh, material))
		for j in range(8):
			dust.append(_piece(root, dust_mesh, dust_material))
		var flash := _piece(root, flash_mesh, flash_material)
		root.visible = false
		slots.append({"root": root, "pieces": pieces, "flash": flash, "dust_pieces": dust,
			"material": material, "flash_material": flash_material, "dust_material": dust_material,
			"age": 1.0, "life": DUST_TIME, "feet": []})

func spawn(event: Dictionary) -> void:
	var slot: Dictionary = slots[cursor]
	cursor = (cursor + 1) % POOL_SIZE
	slot.age = float(event.get("age", 0.0))
	slot["spawn_frame"] = Engine.get_process_frames()
	slot.root.position = event.position
	slot["strength"] = 0.45 if event.kind == "contact" else 1.0
	slot["direction"] = float(event.get("direction", 0.0))
	slot.feet = []
	for foot: Vector3 in event.get("feet", []):
		slot.feet.append(foot - Vector3(event.position))
	var color := Color.WHITE
	if event.kind == "hit":
		color = color.lerp(Color(1.0, 0.48, 0.12) if event.player == 1 else Color(0.18, 0.88, 1.0), 0.35)
	slot["color"] = color
	_update_slot(slot)

func _process(delta: float) -> void:
	for slot: Dictionary in slots:
		if slot.root.visible and int(slot.get("spawn_frame", -1)) != Engine.get_process_frames():
			slot.age += delta
			_update_slot(slot)

func _update_slot(slot: Dictionary) -> void:
	var age: float = slot.age
	var strength: float = slot.strength
	slot.root.visible = age < DUST_TIME
	var t := clampf(age / STREAK_TIME, 0.0, 1.0)
	var color: Color = slot.color
	color.a = (1.0 - t * t) * (0.75 if strength < 1.0 else 1.0)
	slot.material.albedo_color = color
	for j in range(8):
		var piece: MeshInstance3D = slot.pieces[j]
		piece.visible = age < STREAK_TIME and (strength >= 1.0 or j % 2 == 0)
		var angle := TAU * float(j) / 8.0 + PI / 8.0
		var direction := Vector3(cos(angle), sin(angle), 0.0)
		piece.position = direction * (0.12 + 0.20 * (1.0 - pow(1.0 - t, 2.0))) * strength
		piece.position.x += float(slot.direction) * 0.06 * t
		piece.rotation.z = angle
		piece.scale = Vector3((0.19 if j % 2 == 0 else 0.14) * (1.0 - 0.6 * t), 0.035 * (1.0 - 0.65 * t), 0.018) * strength
	var flash_t := clampf(age / FLASH_TIME, 0.0, 1.0)
	slot.flash.visible = age < FLASH_TIME
	slot.flash.scale = Vector3(0.19, 0.15, 0.06) * strength * (1.0 + flash_t * 0.3)
	slot.flash_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0 - flash_t)
	var dust_t := clampf(age / DUST_TIME, 0.0, 1.0)
	slot.dust_material.albedo_color = Color(0.79, 0.78, 0.72, 0.65 * (1.0 - dust_t * dust_t))
	for j in range(8):
		var puff: MeshInstance3D = slot.dust_pieces[j]
		var foot_index := floori(float(j) / 4.0)
		puff.visible = foot_index < slot.feet.size() and age < DUST_TIME
		if not puff.visible:
			continue
		var angle := TAU * float(j % 4) / 4.0 + PI / 4.0
		var radius := (0.08 + 0.24 * dust_t) * strength
		puff.position = slot.feet[foot_index] + Vector3(cos(angle) * radius - float(slot.direction) * 0.10 * dust_t, sin(dust_t * PI) * 0.065, sin(angle) * radius)
		puff.scale = Vector3(0.18, 0.08, 0.14) * (0.7 + dust_t * 0.9) * strength
