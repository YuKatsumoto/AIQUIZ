extends SceneTree

## The mascot GLB must carry the same 16-bone skeleton (names, parents, rests) as every rig
## it is put on: the helicopter pilot is posed by absolute bone rotations, and MascotDresser
## binds the mascot mesh straight onto the referee's and the saw operator's Skeleton3D.
## The old plush body must no longer be imported in those GLBs (skip_import).
## ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/mascot_rig_check.gd

const MASCOT := "res://assets/characters/aiquiz_mascot/mascot_model.glb"
const RIGS := ["res://assets/result_finale/referee_finale.glb", "res://assets/hazards/saw_operator/saw_operator.glb"]
const OLD_BODIES := ["HERO_GodotPlush", "GodotPlushMesh"]


func _initialize() -> void:
	var report := {"passed": true, "rigs": {}, "problems": []}
	var mascot := _instance(MASCOT)
	var mascot_skeleton := mascot.find_child("Skeleton3D", true, false) as Skeleton3D
	if mascot_skeleton == null or mascot.find_child("HERO_Mascot", true, false) == null:
		report.problems.append("mascot GLB lacks Skeleton3D or HERO_Mascot")
	else:
		report["mascot_bones"] = mascot_skeleton.get_bone_count()
		for path: String in RIGS:
			var rig := _instance(path)
			var skeleton := rig.find_child("Skeleton3D", true, false) as Skeleton3D
			var entry := {"bones": skeleton.get_bone_count() if skeleton != null else 0, "worst_origin": 0.0, "worst_basis": 0.0}
			if skeleton == null:
				report.problems.append(path + ": no skeleton")
			else:
				for index in range(mascot_skeleton.get_bone_count()):
					var bone := mascot_skeleton.get_bone_name(index)
					var other := skeleton.find_bone(bone)
					if other < 0:
						report.problems.append("%s: missing %s" % [path, bone])
						continue
					var origin_error := mascot_skeleton.get_bone_global_rest(index).origin.distance_to(skeleton.get_bone_global_rest(other).origin)
					var basis_error := _basis_error(mascot_skeleton.get_bone_rest(index).basis, skeleton.get_bone_rest(other).basis)
					var parent_a := mascot_skeleton.get_bone_parent(index)
					var parent_b := skeleton.get_bone_parent(other)
					var same_parent := (parent_a < 0 and parent_b < 0) or (parent_a >= 0 and parent_b >= 0
						and mascot_skeleton.get_bone_name(parent_a) == skeleton.get_bone_name(parent_b))
					entry.worst_origin = maxf(entry.worst_origin, origin_error)
					entry.worst_basis = maxf(entry.worst_basis, basis_error)
					if origin_error > 0.002 or basis_error > 0.002 or not same_parent:
						report.problems.append("%s: %s differs" % [path, bone])
			for old: String in OLD_BODIES:
				if rig.find_child(old, true, false) != null:
					report.problems.append("%s: old body %s is still imported" % [path, old])
			var dressed := MascotDresser.dress(rig)
			entry["dressed"] = dressed
			if dressed != 1 or rig.find_child(MascotDresser.BODY_NAME, true, false) == null:
				report.problems.append("%s: MascotDresser dressed %d rigs" % [path, dressed])
			report.rigs[path] = entry
			rig.free()
	mascot.free()
	report.passed = report.problems.is_empty()
	print("MASCOT_RIG_CHECK ", JSON.stringify(report))
	quit(0 if report.passed else 1)


func _instance(path: String) -> Node:
	return (load(path) as PackedScene).instantiate()


func _basis_error(a: Basis, b: Basis) -> float:
	var error := 0.0
	for axis in range(3):
		error = maxf(error, (a[axis] - b[axis]).length())
	return error
