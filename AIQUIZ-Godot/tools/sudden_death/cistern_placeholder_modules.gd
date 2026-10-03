extends RefCounted

## 地下神殿の仮の部品（docs/sudden_death_m3_interface.md の取り決めどおりの形・ノード名・材質名・UV）。
## Blenderの本物の部品（assets/environment/underground_temple/）が届くまで、build_cistern_scenes.gd が
## 代わりに使う。単純な形（面取りした柱・梁・床版・壁・配管・照明器具・トンネル・操作室・ハシゴ・通路）を
## 作り、UV0 は繰り返しのテクスチャ用（1UV = 2m）、UV2 は lightmap_unwrap で作る。焼いた光は、照明の位置
## から解析的に求めた直接光（影なし）と粗い間接光・AO で、取り決めと同じ符号化（RGB = (E / light_max)^(1/2.2)、
## A = AO）にする。生成物は scenes/sudden_death/cistern_generated/placeholder/ に置く。

const OUT_DIR := "res://scenes/sudden_death/cistern_generated/placeholder/"

const HALL_W := 45.0
const H := 18.0
const SLAB := 1.0
const BAY_HALF := 7.5
const PILLAR_X: Array[float] = [-38.7, -25.8, -12.9, 12.9, 25.8, 38.7]
const PILLAR_W := 2.0
const PILLAR_D := 7.0
const PILLAR_Z0 := 0.0
const PILLAR_BEVEL := 0.12
const OPENING_R := 7.0
const TUNNEL_R := 5.0
const TUNNEL_Y := 5.0
const UP_FACE_Z := -30.0
const UP_MIN_Z := -30.6
const UP_MAX_Z := -22.5
const DOWN_FACE_Z := 210.0
const DOWN_MIN_Z := 202.5
const DOWN_MAX_Z := 211.2
const TUNNEL_END_Z := -45.0
const LAMP_X := 11.9
const LAMP_Y := 7.0
const LAMP_Z := 3.5
const BALCONY_X := 17.0
const BALCONY_W := 11.0
const BALCONY_Y := 8.0
const ROOM_D := 3.0
const BALCONY_D := 2.6
const LADDER_X := 3.5
const CATWALK_Y := 6.0
const CATWALK_D := 1.6
const SEGMENTS := 48

## Placeholder light units are the shader's irradiance (light_scale 1).
const FLOOD_INTENSITY := 210.0
const FLOOD_COLOR := Color(1.0, 0.93, 0.82)
const AMBER_COLOR := Color(1.0, 0.52, 0.12)
const WINDOW_COLOR := Color(1.0, 0.78, 0.50)
const LIGHTMAP_TEXEL := 0.16
## UV0 of the placeholder geometry repeats every 2 m (the modules' own value is in cistern_layout.json).
const UV_METRES := 2.0
## Floor vertex colour (interface: R = puddle potential, G = damp, B = silt).
const FLOOR_COLOR := Color(0.5, 0.55, 0.0)

const STEEL_COLOR := Color(0.31, 0.37, 0.43)
const SAFETY_YELLOW := Color(0.92, 0.70, 0.12)
const DARK := Color(0.12, 0.12, 0.13)

var log_lines: PackedStringArray = []


## Builds every placeholder module. Returns {module: {"scene", "light", "light_max", "light_scale"}}.
func build_all() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var result := {}
	for module: String in ["cistern_bay_a", "cistern_bay_opening", "cistern_end_upstream", "cistern_end_downstream"]:
		var started := Time.get_ticks_msec()
		result[module] = _build_module(module)
		log_lines.append("%s: %d ms" % [module, Time.get_ticks_msec() - started])
	return result


# ------------------------------------------------------------------ modules

func _build_module(module: String) -> Dictionary:
	var b := Builder.new()
	var lights: Array[Dictionary] = []
	var anchors: Array[Dictionary] = []
	match module:
		"cistern_bay_a":
			_bay(b, false, lights, anchors)
		"cistern_bay_opening":
			_bay(b, true, lights, anchors)
		"cistern_end_upstream":
			_upstream(b, lights, anchors)
		"cistern_end_downstream":
			_downstream(b, lights, anchors)
	var mesh := b.commit()
	var names: PackedStringArray = []
	for surface in range(mesh.get_surface_count()):
		names.append(mesh.surface_get_name(surface))
	var error := mesh.lightmap_unwrap(Transform3D.IDENTITY, LIGHTMAP_TEXEL)
	if error != OK:
		push_error("lightmap_unwrap %s: %s" % [module, error_string(error)])
	# The unwrap rebuilds the surfaces in order but drops their names (the "#Node" tags).
	if mesh.get_surface_count() == names.size():
		for surface in range(names.size()):
			mesh.surface_set_name(surface, names[surface])
	var size := mesh.lightmap_size_hint
	var bake := _bake(mesh, lights, module)
	var light_path := OUT_DIR + module + "_light.res"
	ResourceSaver.save(bake.texture, light_path)
	# Movable parts (gate, hatches) keep their UV2 in the module atlas but get their own node.
	var root := Node3D.new()
	root.name = module
	var movable := _split_movable(mesh)
	var hall := MeshInstance3D.new()
	hall.name = "CIS_Hall"
	hall.mesh = mesh
	root.add_child(hall)
	for node_name: String in movable.keys():
		var part := MeshInstance3D.new()
		part.name = node_name
		part.mesh = movable[node_name]
		root.add_child(part)
	for anchor: Dictionary in anchors:
		var marker := Node3D.new()
		marker.name = anchor.name
		marker.transform = anchor.xform
		root.add_child(marker)
	for child: Node in root.get_children():
		child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	var scene_path := OUT_DIR + module + ".scn"
	ResourceSaver.save(packed, scene_path)
	root.free()
	log_lines.append("%s: lightmap %s, light_max %.2f, %d anchors" % [module, str(size), bake.light_max, anchors.size()])
	return {"scene": scene_path, "light": light_path, "light_max": bake.light_max, "light_scale": 1.0, "size": [size.x, size.y]}


func _bay(b: Builder, opening: bool, lights: Array[Dictionary], anchors: Array[Dictionary]) -> void:
	var z0 := -BAY_HALF
	var z1 := BAY_HALF
	# Floor and the drain channels along the corridor edges.
	b.box("CIS_Floor", Vector3(-HALL_W, -0.4, z0), Vector3(HALL_W, 0.0, z1), Builder.TOP, FLOOR_COLOR)
	for side: float in [-1.0, 1.0]:
		b.box("CIS_Grate", Vector3(side * 9.0 - 0.3, -0.01, z0 + 0.6), Vector3(side * 9.0 + 0.3, 0.012, z1 - 0.6), Builder.TOP, Color(0.6, 0.6, 0.6))
	# Ceiling slab (with the round opening in the opening bay).
	if opening:
		var s := OPENING_R + 0.5
		b.box("CIS_Concrete", Vector3(-HALL_W, H, z0), Vector3(-s, H + SLAB, z1), Builder.BOTTOM)
		b.box("CIS_Concrete", Vector3(s, H, z0), Vector3(HALL_W, H + SLAB, z1), Builder.BOTTOM)
		b.box("CIS_Concrete", Vector3(-s, H, z0), Vector3(s, H + SLAB, -s), Builder.BOTTOM)
		b.box("CIS_Concrete", Vector3(-s, H, s), Vector3(s, H + SLAB, z1), Builder.BOTTOM)
		b.ring_plate("CIS_Concrete", Vector3(0.0, H, 0.0), OPENING_R, s, SLAB)
		# Yellow and black trim on the rim.
		b.ring_band("CIS_SteelPaint", Vector3(0.0, H - 0.25, 0.0), OPENING_R - 0.02, OPENING_R + 0.35, 0.25)
	else:
		b.box("CIS_Concrete", Vector3(-HALL_W, H, z0), Vector3(HALL_W, H + SLAB, z1), Builder.BOTTOM)
	# Outer walls.
	b.box("CIS_Concrete", Vector3(-HALL_W - 1.0, 0.0, z0), Vector3(-HALL_W, H, z1), Builder.POS_X)
	b.box("CIS_Concrete", Vector3(HALL_W, 0.0, z0), Vector3(HALL_W + 1.0, H, z1), Builder.NEG_X)
	# Pillars (chamfered), haunches at the top, longitudinal beams along the columns, cross beams over the row.
	for x: float in PILLAR_X:
		b.pillar("CIS_Concrete", Vector3(x, 0.0, PILLAR_Z0 + PILLAR_D * 0.5), PILLAR_W, PILLAR_D, H - 1.3, PILLAR_BEVEL)
		b.box("CIS_Concrete", Vector3(x - 0.8, H - 1.3, z0), Vector3(x + 0.8, H, z1), Builder.SIDES_AND_BOTTOM)
	var cross_y := H - 1.0
	var columns: Array[float] = [-HALL_W, -38.7, -25.8, -12.9, 12.9, 25.8, 38.7, HALL_W]
	for index in range(columns.size() - 1):
		var a := columns[index] + (0.8 if index > 0 else 0.0)
		var c := columns[index + 1] - (0.8 if index < columns.size() - 2 else 0.0)
		if opening and a < 0.0 and c > 0.0:
			continue
		b.box("CIS_Concrete", Vector3(a, cross_y, PILLAR_Z0 + 2.9), Vector3(c, H, PILLAR_Z0 + 4.1), Builder.SIDES_AND_BOTTOM)
	# Pipes along the outer walls and cable trays along the corridor edge.
	for side: float in [-1.0, 1.0]:
		for y: float in [3.0, 3.8]:
			b.cylinder_z("CIS_Galvanized", Vector3(side * (HALL_W - 0.7), y, 0.0), 0.3, z0, z1)
		b.box("CIS_Galvanized", Vector3(side * 11.55 - 0.3, 10.4, z0), Vector3(side * 11.55 + 0.3, 10.52, z1), Builder.ALL)
		for z: float in [-5.0, 5.0]:
			b.box("CIS_SteelPaint", Vector3(side * (HALL_W - 0.9) - 0.45, 2.55, z - 0.15), Vector3(side * (HALL_W - 0.9) + 0.45, 2.7, z + 0.15), Builder.ALL, Color(0.25, 0.25, 0.27))
		# Painted edge line of the corridor.
		b.box("CIS_SteelPaint", Vector3(side * 11.6 - 0.08, 0.0, z0), Vector3(side * 11.6 + 0.08, 0.006, z1), Builder.TOP, SAFETY_YELLOW)
	# Floodlights on the inner pillar faces (x = +-11.9, y = 7, z = 3.5), aimed across and down.
	var index := 0
	for side: float in [-1.0, 1.0]:
		var origin := Vector3(side * LAMP_X, LAMP_Y, LAMP_Z)
		var target := Vector3(-side * 2.0, 0.0, LAMP_Z + 3.0)
		var aim := Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin + Vector3(-side * 0.42, 0.0, 0.0))
		b.fixture(aim, Vector3(0.62, 0.42, 0.5), Color(1.0, 1.0, 1.0))
		var bracket_x := Vector2(side * LAMP_X, side * (LAMP_X - 0.45))
		b.box("CIS_SteelPaint", Vector3(minf(bracket_x.x, bracket_x.y), LAMP_Y + 0.12, LAMP_Z - 0.06),
			Vector3(maxf(bracket_x.x, bracket_x.y), LAMP_Y + 0.24, LAMP_Z + 0.06), Builder.ALL, DARK)
		anchors.append({"name": "CIS_Light_Flood_%d" % index, "xform": Transform3D(Basis.looking_at(target - origin, Vector3.UP), origin + Vector3(-side * 0.6, 0.0, 0.0))})
		index += 1
	for row_offset: float in [-30.0, -15.0, 0.0, 15.0, 30.0]:
		for side: float in [-1.0, 1.0]:
			var origin := Vector3(side * (LAMP_X - 0.6), LAMP_Y, LAMP_Z + row_offset)
			lights.append(_spot(origin, Vector3(-side * 2.0, 0.0, LAMP_Z + 3.0 + row_offset), FLOOD_COLOR, FLOOD_INTENSITY, 52.0, 30.0))
	# Amber safety lamps on the outer pillars and the walls.
	var amber_index := 0
	for side: float in [-1.0, 1.0]:
		for x: float in [25.8, 38.7]:
			var face := side * (x - 1.0)
			var pos := Vector3(face - side * 0.12, 3.2, LAMP_Z)
			b.box("CIS_LampLens", pos - Vector3(0.1, 0.1, 0.1), pos + Vector3(0.1, 0.1, 0.1), Builder.ALL, AMBER_COLOR)
			anchors.append({"name": "CIS_Light_Amber_%d" % amber_index, "xform": Transform3D(Basis.looking_at(Vector3(-side, 0.0, 0.0), Vector3.UP), pos)})
			amber_index += 1
			for row_offset: float in [-15.0, 0.0, 15.0]:
				lights.append(_omni(pos + Vector3(-side * 0.3, 0.0, row_offset), AMBER_COLOR, 9.0, 14.0))
		var wall_pos := Vector3(side * (HALL_W - 0.15), 3.2, -3.0)
		b.box("CIS_LampLens", wall_pos - Vector3(0.1, 0.1, 0.1), wall_pos + Vector3(0.1, 0.1, 0.1), Builder.ALL, AMBER_COLOR)
		anchors.append({"name": "CIS_Light_Amber_%d" % amber_index, "xform": Transform3D(Basis.looking_at(Vector3(-side, 0.0, 0.0), Vector3.UP), wall_pos)})
		amber_index += 1
		for row_offset: float in [-15.0, 0.0, 15.0]:
			lights.append(_omni(wall_pos + Vector3(-side * 0.3, 0.0, row_offset), AMBER_COLOR, 9.0, 14.0))


func _upstream(b: Builder, lights: Array[Dictionary], anchors: Array[Dictionary]) -> void:
	var z0 := UP_FACE_Z
	var z1 := UP_MAX_Z
	b.box("CIS_Floor", Vector3(-HALL_W, -0.4, z0), Vector3(HALL_W, 0.0, z1), Builder.TOP, FLOOR_COLOR)
	b.box("CIS_Concrete", Vector3(-HALL_W, H, z0), Vector3(HALL_W, H + SLAB, z1), Builder.BOTTOM)
	b.box("CIS_Concrete", Vector3(-HALL_W - 1.0, 0.0, z0), Vector3(-HALL_W, H, z1), Builder.POS_X)
	b.box("CIS_Concrete", Vector3(HALL_W, 0.0, z0), Vector3(HALL_W + 1.0, H, z1), Builder.NEG_X)
	# End wall (inner face z = -30) around the tunnel mouth: a square hole closed down to a circle.
	var t := TUNNEL_R + 1.0
	b.box("CIS_Concrete", Vector3(-HALL_W, 0.0, UP_MIN_Z), Vector3(-t, H, z0), Builder.POS_Z)
	b.box("CIS_Concrete", Vector3(t, 0.0, UP_MIN_Z), Vector3(HALL_W, H, z0), Builder.POS_Z)
	b.box("CIS_Concrete", Vector3(-t, TUNNEL_Y + t, UP_MIN_Z), Vector3(t, H, z0), Builder.POS_Z)
	b.box("CIS_Concrete", Vector3(-t, 0.0, UP_MIN_Z), Vector3(t, TUNNEL_Y - t, z0), Builder.POS_Z)
	b.ring_plate_z("CIS_Concrete", Vector3(0.0, TUNNEL_Y, z0), TUNNEL_R, t)
	# The tunnel (seen from inside) to z = -45, its floor in the dark.
	b.tube_z("CIS_Concrete", Vector3(0.0, TUNNEL_Y, 0.0), TUNNEL_R, TUNNEL_END_Z, UP_MIN_Z)
	b.disc_z("CIS_Concrete", Vector3(0.0, TUNNEL_Y, TUNNEL_END_Z), TUNNEL_R + 0.05, Color(0.05, 0.05, 0.05))
	# Steel frame and gate guides around the mouth, the hoist housing above.
	b.ring_band_z("CIS_SteelPaint", Vector3(0.0, TUNNEL_Y, z0), TUNNEL_R, TUNNEL_R + 0.45, 0.12, DARK)
	for side: float in [-1.0, 1.0]:
		var gx := side * (TUNNEL_R + 0.9)
		b.box("CIS_SteelPaint", Vector3(gx - 0.25, 0.0, z0), Vector3(gx + 0.25, TUNNEL_Y + TUNNEL_R + 1.6, z0 + 0.5), Builder.ALL, DARK)
	b.box("CIS_SteelPaint", Vector3(-t - 0.5, TUNNEL_Y + TUNNEL_R + 1.0, z0), Vector3(t + 0.5, TUNNEL_Y + TUNNEL_R + 2.8, z0 + 1.4), Builder.ALL, STEEL_COLOR)
	b.box("CIS_SteelPaint", Vector3(-t - 0.51, TUNNEL_Y + TUNNEL_R + 1.0, z0 - 0.01), Vector3(t + 0.51, TUNNEL_Y + TUNNEL_R + 1.35, z0 + 1.41), Builder.ALL, SAFETY_YELLOW)
	# The roller gate (closed, in its slot behind the wall face); Godot raises CIS_InflowGate by 11.4 m.
	var span := TUNNEL_R * 2.0 + 1.2
	var gz := z0 - 0.3
	b.box("CIS_SteelPaint#CIS_InflowGate", Vector3(-span * 0.5, TUNNEL_Y - span * 0.5, gz - 0.15), Vector3(span * 0.5, TUNNEL_Y + span * 0.5, gz + 0.15), Builder.ALL, STEEL_COLOR)
	for rib in range(6):
		var ry := TUNNEL_Y - TUNNEL_R + 1.0 + float(rib) * 1.7
		b.box("CIS_SteelPaint#CIS_InflowGate", Vector3(-span * 0.5, ry - 0.14, gz + 0.15), Vector3(span * 0.5, ry + 0.14, gz + 0.28), Builder.ALL, DARK)
	b.box("CIS_SteelPaint#CIS_InflowGate", Vector3(-span * 0.5, TUNNEL_Y - span * 0.5, gz + 0.15), Vector3(span * 0.5, TUNNEL_Y - span * 0.5 + 0.55, gz + 0.3), Builder.ALL, SAFETY_YELLOW)
	# Control room on the wall at x = 17: room, lit window, door, balcony at y = 8 with railing.
	var left := BALCONY_X - BALCONY_W * 0.5
	var right := BALCONY_X + BALCONY_W * 0.5
	var room_front := z0 + ROOM_D
	var edge := room_front + BALCONY_D
	b.box("CIS_Concrete", Vector3(left + 0.5, BALCONY_Y, z0), Vector3(right - 0.5, BALCONY_Y + 3.8, room_front), Builder.ALL_BUT_BACK)
	b.box("CIS_SteelPaint", Vector3(left - 0.2, BALCONY_Y + 3.8, z0), Vector3(right + 0.2, BALCONY_Y + 4.1, edge + 0.2), Builder.ALL_BUT_BACK, DARK)
	b.box("CIS_LampLens", Vector3(BALCONY_X - 2.0, BALCONY_Y + 1.35, room_front), Vector3(BALCONY_X + 4.4, BALCONY_Y + 2.65, room_front + 0.04), Builder.ALL, WINDOW_COLOR * 0.35)
	for index in range(3):
		var mx := BALCONY_X - 2.0 + float(index) * 3.2
		b.box("CIS_SteelPaint", Vector3(mx - 0.05, BALCONY_Y + 1.3, room_front), Vector3(mx + 0.05, BALCONY_Y + 2.7, room_front + 0.08), Builder.ALL, DARK)
	b.box("CIS_SteelPaint", Vector3(left + 0.9, BALCONY_Y, room_front), Vector3(left + 1.9, BALCONY_Y + 2.2, room_front + 0.05), Builder.ALL, STEEL_COLOR)
	b.box("CIS_Concrete", Vector3(left, BALCONY_Y - 0.35, room_front), Vector3(right, BALCONY_Y, edge), Builder.ALL_BUT_BACK)
	b.box("CIS_SteelPaint", Vector3(left - 0.02, BALCONY_Y - 0.41, edge - 0.06), Vector3(right + 0.02, BALCONY_Y - 0.29, edge + 0.06), Builder.ALL, SAFETY_YELLOW)
	for x: float in [left + 1.0, right - 1.0]:
		b.beam("CIS_SteelPaint", Vector3(x, BALCONY_Y - 3.2, z0), Vector3(x, BALCONY_Y - 0.35, edge - 0.4), 0.3, DARK)
	for height: float in [1.1, 0.55]:
		b.box("CIS_SteelPaint", Vector3(left + 0.1, BALCONY_Y + height - 0.03, edge - 0.13), Vector3(right - 0.1, BALCONY_Y + height + 0.03, edge - 0.07), Builder.ALL, SAFETY_YELLOW)
		for x: float in [left + 0.1, right - 0.1]:
			b.box("CIS_SteelPaint", Vector3(x - 0.03, BALCONY_Y + height - 0.03, room_front), Vector3(x + 0.03, BALCONY_Y + height + 0.03, edge - 0.1), Builder.ALL, SAFETY_YELLOW)
	for index in range(10):
		var px := lerpf(left + 0.1, right - 0.1, float(index) / 9.0)
		b.box("CIS_SteelPaint", Vector3(px - 0.035, BALCONY_Y, edge - 0.135), Vector3(px + 0.035, BALCONY_Y + 1.1, edge - 0.065), Builder.ALL, SAFETY_YELLOW)
	# Risers up the wall and some drums in the corner.
	for x: float in [-9.0, -10.2, 30.0, 31.2]:
		b.cylinder_y("CIS_Galvanized", Vector3(x, 0.0, z0 + 0.5), 0.35, 0.0, H)
	for drum: Vector3 in [Vector3(-36.0, 0.0, -27.5), Vector3(-35.3, 0.0, -27.6), Vector3(-35.7, 0.0, -26.9), Vector3(-34.6, 0.0, -27.2)]:
		b.cylinder_y("CIS_SteelPaint", drum, 0.3, 0.0, 0.9, Color(0.20, 0.30, 0.42))
	# Lights: the first floodlight row (bay k = -1 at z = -11.5), wall washers, the control room window.
	for side: float in [-1.0, 1.0]:
		var origin := Vector3(side * (LAMP_X - 0.6), LAMP_Y, -15.0 + LAMP_Z)
		lights.append(_spot(origin, Vector3(-side * 2.0, 0.0, -15.0 + LAMP_Z + 3.0), FLOOD_COLOR, FLOOD_INTENSITY, 62.0, 30.0))
		var wash := Vector3(side * 8.5, 13.0, z0 + 0.8)
		b.fixture(Transform3D(Basis.looking_at(Vector3(side * 5.0, 1.0, z0 + 5.0) - wash, Vector3.UP), wash), Vector3(0.5, 0.35, 0.4), AMBER_COLOR)
		lights.append(_spot(wash, Vector3(side * 5.0, 1.0, z0 + 5.0), AMBER_COLOR, 120.0, 65.0, 26.0))
		anchors.append({"name": "CIS_Light_Amber_%d" % (0 if side < 0.0 else 1), "xform": Transform3D(Basis.looking_at(Vector3(side * 5.0, 1.0, z0 + 5.0) - wash, Vector3.UP), wash)})
	var window_pos := Vector3(BALCONY_X + 1.2, BALCONY_Y + 2.0, room_front + 0.3)
	lights.append(_omni(window_pos, WINDOW_COLOR, 40.0, 12.0))
	anchors.append({"name": "CIS_Light_Window_0", "xform": Transform3D(Basis.looking_at(Vector3(0.0, -0.4, 1.0), Vector3.UP), window_pos)})
	anchors.append({"name": "CIS_RefereeMark", "xform": Transform3D(Basis.IDENTITY, Vector3(BALCONY_X - 1.0, BALCONY_Y, edge - 0.9))})


func _downstream(b: Builder, lights: Array[Dictionary], anchors: Array[Dictionary]) -> void:
	var z0 := DOWN_MIN_Z
	var z1 := DOWN_FACE_Z
	b.box("CIS_Floor", Vector3(-HALL_W, -0.4, z0), Vector3(HALL_W, 0.0, z1), Builder.TOP, FLOOR_COLOR)
	b.box("CIS_Concrete", Vector3(-HALL_W, H, z0), Vector3(HALL_W, H + SLAB, z1), Builder.BOTTOM)
	b.box("CIS_Concrete", Vector3(-HALL_W - 1.0, 0.0, z0), Vector3(-HALL_W, H, z1), Builder.POS_X)
	b.box("CIS_Concrete", Vector3(HALL_W, 0.0, z0), Vector3(HALL_W + 1.0, H, z1), Builder.NEG_X)
	b.box("CIS_Concrete", Vector3(-HALL_W, 0.0, z1), Vector3(HALL_W, H, DOWN_MAX_Z), Builder.NEG_Z)
	# Ladders with cages (P1 +X, P2 -X) up to the catwalk at 6 m.
	for side: float in [-1.0, 1.0]:
		var x := side * LADDER_X
		for rail_side: float in [-1.0, 1.0]:
			b.box("CIS_SteelPaint", Vector3(x + rail_side * 0.27 - 0.035, 0.0, z1 - 0.25), Vector3(x + rail_side * 0.27 + 0.035, CATWALK_Y + 1.1, z1 - 0.18), Builder.ALL, SAFETY_YELLOW)
		var y := 0.3
		while y < CATWALK_Y:
			b.box("CIS_SteelPaint", Vector3(x - 0.25, y - 0.025, z1 - 0.23), Vector3(x + 0.25, y + 0.025, z1 - 0.2), Builder.ALL, SAFETY_YELLOW)
			y += 0.3
		var hoop_y := 2.4
		while hoop_y <= CATWALK_Y + 1.0:
			b.box("CIS_SteelPaint", Vector3(x - 0.4, hoop_y - 0.03, z1 - 0.95), Vector3(x + 0.4, hoop_y + 0.03, z1 - 0.89), Builder.ALL, SAFETY_YELLOW)
			for hoop_side: float in [-1.0, 1.0]:
				b.box("CIS_SteelPaint", Vector3(x + hoop_side * 0.4 - 0.03, hoop_y - 0.03, z1 - 0.95), Vector3(x + hoop_side * 0.4 + 0.03, hoop_y + 0.03, z1 - 0.2), Builder.ALL, SAFETY_YELLOW)
			hoop_y += 0.8
		for strap in range(5):
			var sx := x + lerpf(-0.4, 0.4, float(strap) / 4.0)
			var sz := z1 - 0.95 if strap in [1, 2, 3] else z1 - 0.6
			b.box("CIS_SteelPaint", Vector3(sx - 0.02, 2.4, sz - 0.02), Vector3(sx + 0.02, CATWALK_Y + 1.0, sz + 0.02), Builder.ALL, SAFETY_YELLOW)
		# Escape hatch above the catwalk (separate node), its frame and the green exit lamp.
		b.box("CIS_SteelPaint", Vector3(x - 0.8, CATWALK_Y, z1 - 0.08), Vector3(x + 0.8, CATWALK_Y + 2.4, z1), Builder.ALL, SAFETY_YELLOW)
		var hatch := "CIS_SteelPaint#CIS_Hatch_%s" % ("R" if side > 0.0 else "L")
		b.box(hatch, Vector3(x - 0.65, CATWALK_Y + 0.05, z1 - 0.18), Vector3(x + 0.65, CATWALK_Y + 2.2, z1 - 0.08), Builder.ALL, STEEL_COLOR)
		b.box("CIS_LampLens", Vector3(x - 0.25, CATWALK_Y + 2.55, z1 - 0.14), Vector3(x + 0.25, CATWALK_Y + 2.73, z1 - 0.02), Builder.ALL, Color(0.25, 1.0, 0.45))
	# Catwalk at 6 m (24 m wide, 1.6 m deep), open where the ladders come through, with a handrail.
	var gap := 0.7
	var spans: Array[Vector2] = [Vector2(-12.0, -LADDER_X - gap), Vector2(-LADDER_X + gap, LADDER_X - gap), Vector2(LADDER_X + gap, 12.0)]
	for span: Vector2 in spans:
		b.box("CIS_Grate", Vector3(span.x, CATWALK_Y - 0.2, z1 - CATWALK_D), Vector3(span.y, CATWALK_Y, z1), Builder.ALL, Color(0.6, 0.6, 0.6))
		b.box("CIS_SteelPaint", Vector3(span.x, CATWALK_Y, z1 - CATWALK_D - 0.03), Vector3(span.y, CATWALK_Y + 0.15, z1 - CATWALK_D + 0.03), Builder.ALL, SAFETY_YELLOW)
		for height: float in [1.1, 0.55]:
			b.box("CIS_SteelPaint", Vector3(span.x, CATWALK_Y + height - 0.03, z1 - CATWALK_D - 0.03), Vector3(span.y, CATWALK_Y + height + 0.03, z1 - CATWALK_D + 0.03), Builder.ALL, SAFETY_YELLOW)
		var x := span.x
		while x <= span.y + 0.01:
			b.box("CIS_SteelPaint", Vector3(x - 0.035, CATWALK_Y, z1 - CATWALK_D - 0.035), Vector3(x + 0.035, CATWALK_Y + 1.1, z1 - CATWALK_D + 0.035), Builder.ALL, SAFETY_YELLOW)
			x += maxf(1.0, (span.y - span.x) / ceilf((span.y - span.x) / 2.2))
	for x: float in [-10.0, 0.0, 10.0]:
		b.beam("CIS_SteelPaint", Vector3(x, CATWALK_Y - 1.6, z1), Vector3(x, CATWALK_Y - 0.2, z1 - CATWALK_D + 0.2), 0.2, DARK)
	# Pump intake grilles low on the end wall.
	for side: float in [-1.0, 1.0]:
		var cx := side * 18.0
		b.box("CIS_Concrete", Vector3(cx - 4.5, 0.0, z1 - 0.02), Vector3(cx + 4.5, 5.0, z1 - 0.01), Builder.NEG_Z, Color(0.05, 0.05, 0.05))
		for y: float in [0.0, 4.7]:
			b.box("CIS_SteelPaint", Vector3(cx - 4.7, y, z1 - 0.32), Vector3(cx + 4.7, y + 0.3, z1), Builder.ALL_BUT_BACK, DARK)
		for index in range(21):
			var bx := cx - 4.5 + float(index) * 0.45
			b.box("CIS_Galvanized", Vector3(bx - 0.07, 0.3, z1 - 0.25), Vector3(bx + 0.07, 4.7, z1 - 0.05), Builder.ALL_BUT_BACK)
	# The sign (fictional) above the catwalk.
	b.box("CIS_Sign", Vector3(-7.0, 10.5, z1 - 0.06), Vector3(7.0, 12.3, z1 - 0.01), Builder.NEG_Z, Color(0.85, 0.85, 0.80))
	# Lights: the last floodlight row (bay k = 13 at z = 198.5), wall washers, exit lamps.
	for side: float in [-1.0, 1.0]:
		var origin := Vector3(side * (LAMP_X - 0.6), LAMP_Y, 195.0 + LAMP_Z)
		lights.append(_spot(origin, Vector3(-side * 2.0, 0.0, 195.0 + LAMP_Z + 3.0), FLOOD_COLOR, FLOOD_INTENSITY, 62.0, 30.0))
		var wash := Vector3(side * 9.0, 12.0, z1 - 0.8)
		b.fixture(Transform3D(Basis.looking_at(Vector3(side * 3.6, 2.0, z1 - 6.0) - wash, Vector3.UP), wash), Vector3(0.5, 0.35, 0.4), AMBER_COLOR)
		lights.append(_spot(wash, Vector3(side * 3.6, 2.0, z1 - 6.0), AMBER_COLOR, 120.0, 65.0, 26.0))
		anchors.append({"name": "CIS_Light_Amber_%d" % (0 if side < 0.0 else 1), "xform": Transform3D(Basis.looking_at(Vector3(side * 3.6, 2.0, z1 - 6.0) - wash, Vector3.UP), wash)})
		lights.append(_omni(Vector3(side * LADDER_X, CATWALK_Y + 2.6, z1 - 0.4), Color(0.25, 1.0, 0.45), 3.0, 5.0))


# ------------------------------------------------------------------ bake

static func _spot(origin: Vector3, target: Vector3, color: Color, intensity: float, angle: float, reach: float) -> Dictionary:
	return {"pos": origin, "dir": (target - origin).normalized(), "cos_outer": cos(deg_to_rad(angle)),
		"cos_inner": cos(deg_to_rad(angle * 0.55)), "color": color, "intensity": intensity, "range": reach}


static func _omni(origin: Vector3, color: Color, intensity: float, reach: float) -> Dictionary:
	return {"pos": origin, "dir": Vector3.ZERO, "cos_outer": -2.0, "cos_inner": -1.0, "color": color, "intensity": intensity, "range": reach}


## Rasterises every triangle into its UV2 texels and evaluates the lights there (no shadows), a soft
## bounce and a heuristic AO, then encodes the result like the Blender bakes.
func _bake(mesh: ArrayMesh, lights: Array[Dictionary], module: String) -> Dictionary:
	var size := mesh.lightmap_size_hint
	var w := clampi(size.x, 64, 1024)
	var h := clampi(size.y, 64, 1024)
	var energy := PackedFloat32Array()
	energy.resize(w * h * 3)
	var ao := PackedFloat32Array()
	ao.resize(w * h)
	ao.fill(1.0)
	var filled := PackedByteArray()
	filled.resize(w * h)
	var is_bay := module.begins_with("cistern_bay")
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var emissive := mesh.surface_get_name(surface).begins_with("CIS_LampLens")
		var count := indices.size() if not indices.is_empty() else verts.size()
		for tri in range(0, count, 3):
			var i0 := indices[tri] if not indices.is_empty() else tri
			var i1 := indices[tri + 1] if not indices.is_empty() else tri + 1
			var i2 := indices[tri + 2] if not indices.is_empty() else tri + 2
			var t0 := uv2s[i0] * Vector2(w, h)
			var t1 := uv2s[i1] * Vector2(w, h)
			var t2 := uv2s[i2] * Vector2(w, h)
			var area := (t1 - t0).cross(t2 - t0)
			if absf(area) < 1e-8:
				continue
			var min_x := maxi(int(floor(minf(t0.x, minf(t1.x, t2.x)) - 1.0)), 0)
			var max_x := mini(int(ceil(maxf(t0.x, maxf(t1.x, t2.x)) + 1.0)), w - 1)
			var min_y := maxi(int(floor(minf(t0.y, minf(t1.y, t2.y)) - 1.0)), 0)
			var max_y := mini(int(ceil(maxf(t0.y, maxf(t1.y, t2.y)) + 1.0)), h - 1)
			for py in range(min_y, max_y + 1):
				for px in range(min_x, max_x + 1):
					var p := Vector2(px + 0.5, py + 0.5)
					var b1 := (p - t0).cross(t2 - t0) / area
					var b2 := (t1 - t0).cross(p - t0) / area
					var b0 := 1.0 - b1 - b2
					# Conservative: half a texel outside the edges still counts.
					var tol := 0.6 / sqrt(absf(area))
					if b0 < -tol or b1 < -tol or b2 < -tol:
						continue
					var index := py * w + px
					var inside := b0 >= 0.0 and b1 >= 0.0 and b2 >= 0.0
					if filled[index] == 2 and not inside:
						continue
					var c0 := clampf(b0, 0.0, 1.0)
					var c1 := clampf(b1, 0.0, 1.0)
					var c2 := clampf(b2, 0.0, 1.0)
					var s := c0 + c1 + c2
					var pos := (verts[i0] * c0 + verts[i1] * c1 + verts[i2] * c2) / s
					var nor := (normals[i0] * c0 + normals[i1] * c1 + normals[i2] * c2).normalized()
					var e := _irradiance(pos, nor, lights, is_bay)
					if emissive:
						e = Color(1.0, 1.0, 1.0) * 2.0
					energy[index * 3] = e.r
					energy[index * 3 + 1] = e.g
					energy[index * 3 + 2] = e.b
					ao[index] = _ao(pos, nor, module)
					filled[index] = 2 if inside else 1
	# Light max: a high percentile, so a few hot texels next to the lamps do not flatten the rest.
	var samples := PackedFloat32Array()
	for index in range(w * h):
		if filled[index] > 0:
			samples.append(maxf(energy[index * 3], maxf(energy[index * 3 + 1], energy[index * 3 + 2])))
	samples.sort()
	var light_max := maxf(samples[int(samples.size() * 0.995)] if not samples.is_empty() else 1.0, 0.01)
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for index in range(w * h):
		if filled[index] == 0:
			continue
		var r := pow(clampf(energy[index * 3] / light_max, 0.0, 1.0), 1.0 / 2.2)
		var g := pow(clampf(energy[index * 3 + 1] / light_max, 0.0, 1.0), 1.0 / 2.2)
		var bb := pow(clampf(energy[index * 3 + 2] / light_max, 0.0, 1.0), 1.0 / 2.2)
		image.set_pixel(index % w, index / w, Color(r, g, bb, ao[index]))
	_dilate(image, filled, 6)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	return {"texture": texture, "light_max": light_max}


func _irradiance(p: Vector3, n: Vector3, lights: Array[Dictionary], is_bay: bool) -> Color:
	var sum := Color(0.0, 0.0, 0.0)
	for light: Dictionary in lights:
		var d: Vector3 = light.pos - p
		var d2 := d.length_squared()
		var reach: float = light.range
		if d2 > reach * reach:
			continue
		var l := d / sqrt(d2)
		var ndl := n.dot(l)
		if ndl <= 0.0:
			continue
		var cone := 1.0
		if light.dir != Vector3.ZERO:
			var c := (-l).dot(light.dir)
			cone = clampf((c - float(light.cos_outer)) / maxf(float(light.cos_inner) - float(light.cos_outer), 0.001), 0.0, 1.0)
			cone = cone * cone * (3.0 - 2.0 * cone)
			if cone <= 0.0:
				continue
		var window := clampf(1.0 - pow(sqrt(d2) / reach, 4.0), 0.0, 1.0)
		var amount := float(light.intensity) * ndl * cone * window / maxf(d2, 2.0)
		sum += (light.color as Color) * amount
	# One soft bounce: the lit corridor floor fills the hall dimly, warmest near the corridor.
	var corridor := clampf(1.0 - (absf(p.x) - 10.0) / 30.0, 0.0, 1.0)
	var up := 0.5 + 0.5 * n.y
	var down := 0.5 - 0.5 * n.y
	var bounce := (0.25 + 0.75 * corridor) * (0.035 + 0.09 * down + 0.02 * up)
	if not is_bay:
		bounce *= 0.8
	sum += Color(1.0, 0.92, 0.8) * bounce
	return sum


## Contact darkening where the floor meets walls and pillars, and in the ceiling corners.
func _ao(p: Vector3, n: Vector3, module: String) -> float:
	var occlusion := 1.0
	if n.y > 0.5:
		var dist := 99.0
		dist = minf(dist, HALL_W - absf(p.x))
		if module.begins_with("cistern_bay"):
			for x: float in PILLAR_X:
				var dx := maxf(absf(p.x - x) - PILLAR_W * 0.5, 0.0)
				var dz := maxf(absf(p.z - (PILLAR_Z0 + PILLAR_D * 0.5)) - PILLAR_D * 0.5, 0.0)
				dist = minf(dist, sqrt(dx * dx + dz * dz))
		if module == "cistern_end_upstream":
			dist = minf(dist, p.z - UP_FACE_Z)
		if module == "cistern_end_downstream":
			dist = minf(dist, DOWN_FACE_Z - p.z)
		occlusion *= lerpf(0.45, 1.0, clampf(dist / 1.4, 0.0, 1.0))
	elif absf(n.y) < 0.5:
		occlusion *= lerpf(0.5, 1.0, clampf(p.y / 1.2, 0.0, 1.0))
		occlusion *= lerpf(0.6, 1.0, clampf((H - p.y) / 1.5, 0.0, 1.0))
	else:
		occlusion *= 0.9
	return occlusion


## Grows the charts into the padding so bilinear filtering and mipmaps do not pull in black.
static func _dilate(image: Image, filled: PackedByteArray, passes: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var mask := filled.duplicate()
	for _pass in range(passes):
		var next := mask.duplicate()
		for y in range(h):
			for x in range(w):
				var index := y * w + x
				if mask[index] != 0:
					continue
				var sum := Color(0.0, 0.0, 0.0, 0.0)
				var count := 0
				for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := x + offset.x
					var ny := y + offset.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h or mask[ny * w + nx] == 0:
						continue
					sum += image.get_pixel(nx, ny)
					count += 1
				if count > 0:
					image.set_pixel(x, y, sum / float(count))
					next[index] = 1
		mask = next


## Pulls the surfaces tagged "<material>#<node>" out of the hall mesh into their own meshes (UV2 kept).
static func _split_movable(mesh: ArrayMesh) -> Dictionary:
	var parts := {}
	var surface := mesh.get_surface_count() - 1
	while surface >= 0:
		var surface_name := mesh.surface_get_name(surface)
		if "#" in surface_name:
			var node_name := surface_name.get_slice("#", 1)
			if not parts.has(node_name):
				parts[node_name] = ArrayMesh.new()
			var part: ArrayMesh = parts[node_name]
			part.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface))
			var material := mesh.surface_get_material(surface)
			part.surface_set_material(part.get_surface_count() - 1, material)
			part.surface_set_name(part.get_surface_count() - 1, surface_name.get_slice("#", 0))
			mesh.surface_remove(surface)
		surface -= 1
	return parts


# ------------------------------------------------------------------ geometry

class Builder:
	const TOP := 1
	const BOTTOM := 2
	const POS_X := 4
	const NEG_X := 8
	const POS_Z := 16
	const NEG_Z := 32
	const ALL := 63
	const SIDES := 60
	const SIDES_AND_BOTTOM := 62
	const ALL_BUT_BACK := 47

	## surface key ("CIS_Name" or "CIS_Name#Node") -> SurfaceTool
	var tools := {}

	func _st(key: String) -> SurfaceTool:
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
		return tools[key]

	## Concrete UVs repeat every 2 m in the plane the face lies in.
	static func planar_uv(p: Vector3, n: Vector3) -> Vector2:
		var a := n.abs()
		if a.y >= a.x and a.y >= a.z:
			return Vector2(p.x, p.z) / UV_METRES
		if a.x >= a.z:
			return Vector2(p.z, -p.y) / UV_METRES
		return Vector2(p.x, -p.y) / UV_METRES

	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color) -> void:
		# Godot's front faces wind clockwise: order the corners so the face looks along the normals.
		if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
			var swap := b
			b = c
			c = swap
			var swap_n := nb
			nb = nc
			nc = swap_n
		var st := _st(key)
		var face_n := (na + nb + nc).normalized()
		for vertex: Array in [[a, na], [b, nb], [c, nc]]:
			st.set_color(color)
			st.set_normal(vertex[1])
			st.set_uv(planar_uv(vertex[0], face_n))
			st.add_vertex(vertex[0])

	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color := Color.WHITE) -> void:
		tri(key, a, b, c, n, n, n, color)
		tri(key, a, c, d, n, n, n, color)

	func box(key: String, lo: Vector3, hi: Vector3, faces: int, color := Color.WHITE) -> void:
		if faces & TOP:
			quad(key, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, color)
		if faces & BOTTOM:
			quad(key, Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.DOWN, color)
		if faces & POS_X:
			quad(key, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3.RIGHT, color)
		if faces & NEG_X:
			quad(key, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.LEFT, color)
		if faces & POS_Z:
			quad(key, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.BACK, color)
		if faces & NEG_Z:
			quad(key, Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3.FORWARD, color)

	## Pillar with chamfered vertical edges, base at center.y, height h.
	func pillar(key: String, center: Vector3, width: float, depth: float, height: float, bevel: float) -> void:
		var hw := width * 0.5
		var hd := depth * 0.5
		var ring: Array[Vector2] = [Vector2(-hw + bevel, -hd), Vector2(hw - bevel, -hd), Vector2(hw, -hd + bevel), Vector2(hw, hd - bevel),
			Vector2(hw - bevel, hd), Vector2(-hw + bevel, hd), Vector2(-hw, hd - bevel), Vector2(-hw, -hd + bevel)]
		for index in range(ring.size()):
			var p0 := ring[index]
			var p1 := ring[(index + 1) % ring.size()]
			var edge := p1 - p0
			var n := Vector3(edge.y, 0.0, -edge.x).normalized()
			if n.dot(Vector3(p0.x + p1.x, 0.0, p0.y + p1.y)) < 0.0:
				n = -n
			var a := center + Vector3(p0.x, 0.0, p0.y)
			var b := center + Vector3(p1.x, 0.0, p1.y)
			quad(key, a, b, b + Vector3(0.0, height, 0.0), a + Vector3(0.0, height, 0.0), n)

	## Square beam from a to b with its own local axis along the segment.
	func beam(key: String, a: Vector3, b: Vector3, thickness: float, color := Color.WHITE) -> void:
		var axis := (b - a).normalized()
		var reference := Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
		var u := axis.cross(reference).normalized() * thickness * 0.5
		var v := axis.cross(u).normalized() * thickness * 0.5
		var corners: Array[Vector3] = [u + v, -u + v, -u - v, u - v]
		for index in range(4):
			var c0 := corners[index]
			var c1 := corners[(index + 1) % 4]
			var n := (c0 + c1).normalized()
			quad(key, a + c0, a + c1, b + c1, b + c0, n, color)

	func cylinder_z(key: String, center: Vector3, radius: float, z0: float, z1: float, color := Color.WHITE) -> void:
		var segments := 12
		for index in range(segments):
			var d0 := Vector2.from_angle(TAU * float(index) / float(segments))
			var d1 := Vector2.from_angle(TAU * float(index + 1) / float(segments))
			var n0 := Vector3(d0.x, d0.y, 0.0)
			var n1 := Vector3(d1.x, d1.y, 0.0)
			var a := center + n0 * radius
			var b := center + n1 * radius
			tri(key, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), n0, n1, n1, color)
			tri(key, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1), n0, n1, n0, color)

	func cylinder_y(key: String, base: Vector3, radius: float, y0: float, y1: float, color := Color.WHITE) -> void:
		var segments := 12
		for index in range(segments):
			var d0 := Vector2.from_angle(TAU * float(index) / float(segments))
			var d1 := Vector2.from_angle(TAU * float(index + 1) / float(segments))
			var n0 := Vector3(d0.x, 0.0, d0.y)
			var n1 := Vector3(d1.x, 0.0, d1.y)
			var a := base + n0 * radius
			var b := base + n1 * radius
			tri(key, Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3(b.x, y1, b.z), n0, n1, n1, color)
			tri(key, Vector3(a.x, y0, a.z), Vector3(b.x, y1, b.z), Vector3(a.x, y1, a.z), n0, n1, n0, color)
			tri(key, Vector3(base.x, y1, base.z), Vector3(a.x, y1, a.z), Vector3(b.x, y1, b.z), Vector3.UP, Vector3.UP, Vector3.UP, color)

	## Square plate (2 * half per side) at y .. y + thickness with a round hole of `radius` and its lining.
	func ring_plate(key: String, center: Vector3, radius: float, half: float, thickness: float) -> void:
		for index in range(SEGMENTS):
			var d0 := Vector2.from_angle(TAU * float(index) / float(SEGMENTS))
			var d1 := Vector2.from_angle(TAU * float(index + 1) / float(SEGMENTS))
			var p0 := d0 * radius
			var p1 := d1 * radius
			var q0 := d0 * (half / maxf(absf(d0.x), absf(d0.y)))
			var q1 := d1 * (half / maxf(absf(d1.x), absf(d1.y)))
			var y := center.y
			tri(key, center + Vector3(p0.x, 0.0, p0.y), center + Vector3(q0.x, 0.0, q0.y), center + Vector3(q1.x, 0.0, q1.y), Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Color.WHITE)
			tri(key, center + Vector3(p0.x, 0.0, p0.y), center + Vector3(q1.x, 0.0, q1.y), center + Vector3(p1.x, 0.0, p1.y), Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Color.WHITE)
			var n0 := Vector3(-d0.x, 0.0, -d0.y)
			var n1 := Vector3(-d1.x, 0.0, -d1.y)
			var a0 := Vector3(center.x + p0.x, y, center.z + p0.y)
			var a1 := Vector3(center.x + p1.x, y, center.z + p1.y)
			tri(key, a0, a1, a1 + Vector3(0.0, thickness, 0.0), n0, n1, n1, Color.WHITE)
			tri(key, a0, a1 + Vector3(0.0, thickness, 0.0), a0 + Vector3(0.0, thickness, 0.0), n0, n1, n0, Color.WHITE)

	## A flat horizontal band (r0 .. r1) facing down plus its inner rim, striped yellow and black.
	func ring_band(key: String, center: Vector3, r0: float, r1: float, height: float) -> void:
		for index in range(SEGMENTS):
			var d0 := Vector2.from_angle(TAU * float(index) / float(SEGMENTS))
			var d1 := Vector2.from_angle(TAU * float(index + 1) / float(SEGMENTS))
			var color := SAFETY_YELLOW if index % 2 == 0 else DARK
			var a := center + Vector3(d0.x * r0, 0.0, d0.y * r0)
			var b := center + Vector3(d1.x * r0, 0.0, d1.y * r0)
			var c := center + Vector3(d1.x * r1, 0.0, d1.y * r1)
			var d := center + Vector3(d0.x * r1, 0.0, d0.y * r1)
			quad(key, a, b, c, d, Vector3.DOWN, color)
			var n0 := Vector3(-d0.x, 0.0, -d0.y)
			var n1 := Vector3(-d1.x, 0.0, -d1.y)
			tri(key, a, b, b + Vector3(0.0, height, 0.0), n0, n1, n1, color)
			tri(key, a, b + Vector3(0.0, height, 0.0), a + Vector3(0.0, height, 0.0), n0, n1, n0, color)

	## Wall plate in the xy plane at z = center.z (facing +z) with a round hole, filling a square of 2 * half.
	func ring_plate_z(key: String, center: Vector3, radius: float, half: float) -> void:
		for index in range(SEGMENTS):
			var d0 := Vector2.from_angle(TAU * float(index) / float(SEGMENTS))
			var d1 := Vector2.from_angle(TAU * float(index + 1) / float(SEGMENTS))
			var p0 := d0 * radius
			var p1 := d1 * radius
			var q0 := d0 * (half / maxf(absf(d0.x), absf(d0.y)))
			var q1 := d1 * (half / maxf(absf(d1.x), absf(d1.y)))
			var n := Vector3.BACK
			tri(key, center + Vector3(p0.x, p0.y, 0.0), center + Vector3(q0.x, q0.y, 0.0), center + Vector3(q1.x, q1.y, 0.0), n, n, n, Color.WHITE)
			tri(key, center + Vector3(p0.x, p0.y, 0.0), center + Vector3(q1.x, q1.y, 0.0), center + Vector3(p1.x, p1.y, 0.0), n, n, n, Color.WHITE)

	func ring_band_z(key: String, center: Vector3, r0: float, r1: float, depth: float, color: Color) -> void:
		for index in range(SEGMENTS):
			var d0 := Vector2.from_angle(TAU * float(index) / float(SEGMENTS))
			var d1 := Vector2.from_angle(TAU * float(index + 1) / float(SEGMENTS))
			var front := center + Vector3(0.0, 0.0, depth)
			quad(key, front + Vector3(d0.x * r0, d0.y * r0, 0.0), front + Vector3(d1.x * r0, d1.y * r0, 0.0),
				front + Vector3(d1.x * r1, d1.y * r1, 0.0), front + Vector3(d0.x * r1, d0.y * r1, 0.0), Vector3.BACK, color)
			var n0 := Vector3(-d0.x, -d0.y, 0.0)
			var n1 := Vector3(-d1.x, -d1.y, 0.0)
			var a := center + Vector3(d0.x * r0, d0.y * r0, 0.0)
			var b := center + Vector3(d1.x * r0, d1.y * r0, 0.0)
			tri(key, a, b, b + Vector3(0.0, 0.0, depth), n0, n1, n1, color)
			tri(key, a, b + Vector3(0.0, 0.0, depth), a + Vector3(0.0, 0.0, depth), n0, n1, n0, color)

	## Open tube along z (z0 .. z1) seen from inside.
	func tube_z(key: String, axis: Vector3, radius: float, z0: float, z1: float) -> void:
		for index in range(SEGMENTS):
			var d0 := Vector2.from_angle(TAU * float(index) / float(SEGMENTS))
			var d1 := Vector2.from_angle(TAU * float(index + 1) / float(SEGMENTS))
			var n0 := Vector3(-d0.x, -d0.y, 0.0)
			var n1 := Vector3(-d1.x, -d1.y, 0.0)
			var a := axis + Vector3(d0.x * radius, d0.y * radius, 0.0)
			var b := axis + Vector3(d1.x * radius, d1.y * radius, 0.0)
			tri(key, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), n0, n1, n1, Color(0.7, 0.7, 0.7))
			tri(key, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1), n0, n1, n0, Color(0.7, 0.7, 0.7))

	func disc_z(key: String, center: Vector3, radius: float, color: Color) -> void:
		for index in range(SEGMENTS):
			var d0 := Vector2.from_angle(TAU * float(index) / float(SEGMENTS))
			var d1 := Vector2.from_angle(TAU * float(index + 1) / float(SEGMENTS))
			tri(key, center, center + Vector3(d0.x * radius, d0.y * radius, 0.0), center + Vector3(d1.x * radius, d1.y * radius, 0.0),
				Vector3.BACK, Vector3.BACK, Vector3.BACK, color)

	## Floodlight: painted housing and a glowing lens on its -Z face (the light's direction).
	func fixture(xform: Transform3D, size: Vector3, lens_color: Color) -> void:
		var half := size * 0.5
		var corners: Array[Vector3] = []
		for corner in range(8):
			corners.append(Vector3(half.x * (1.0 if corner & 1 else -1.0), half.y * (1.0 if corner & 2 else -1.0), half.z * (1.0 if corner & 4 else -1.0)))
		var faces: Array = [[[0, 1, 3, 2], Vector3.FORWARD], [[4, 5, 7, 6], Vector3.BACK], [[0, 2, 6, 4], Vector3.LEFT],
			[[1, 3, 7, 5], Vector3.RIGHT], [[2, 3, 7, 6], Vector3.UP], [[0, 1, 5, 4], Vector3.DOWN]]
		for face: Array in faces:
			var ids: Array = face[0]
			var n: Vector3 = xform.basis * (face[1] as Vector3)
			var pts: Array[Vector3] = []
			for id: int in ids:
				pts.append(xform * corners[id])
			quad("CIS_SteelPaint", pts[0], pts[1], pts[2], pts[3], n.normalized(), DARK)
		# The lens, just in front of the -Z face.
		var lens_half := Vector3(half.x * 0.85, half.y * 0.8, 0.02)
		var front := -half.z - 0.021
		var l: Array[Vector3] = [Vector3(-lens_half.x, -lens_half.y, front), Vector3(lens_half.x, -lens_half.y, front),
			Vector3(lens_half.x, lens_half.y, front), Vector3(-lens_half.x, lens_half.y, front)]
		var ln: Vector3 = (xform.basis * Vector3.FORWARD).normalized()
		quad("CIS_LampLens", xform * l[0], xform * l[1], xform * l[2], xform * l[3], ln, lens_color)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var keys: Array = tools.keys()
		keys.sort()
		for key: String in keys:
			var st: SurfaceTool = tools[key]
			st.index()
			st.generate_tangents()
			st.commit(mesh)
			var surface := mesh.get_surface_count() - 1
			mesh.surface_set_name(surface, key)
			var material := StandardMaterial3D.new()
			material.resource_name = key.get_slice("#", 0)
			mesh.surface_set_material(surface, material)
		return mesh
