extends Node

## スカイゲートの人の動き（DropMotion、docs/sudden_death_v2/skygate_build_plan.md 4.4・heli_drop.md 第2章）をヘッドレスで確かめる。
##   Godot --headless --path . --script res://tests/sudden_death_v2/drop/drop_motion_unit_bootstrap.gd
## 出力：artifacts/sudden_death_v2/drop_motion/unit_report.json（降り方ごとの「端を離れてから腹ばいに落ち着くまで」の実測など）。

const UAL_PATH := "res://assets/animations/cc0_quaternius/UAL1_Standard.glb"
const REPORT := "res://artifacts/sudden_death_v2/drop_motion/unit_report.json"
## 腹ばいに「落ち着いた」とみなす差（骨ごとの向きの差の最大、度）。
const SETTLED_DEG := 4.0

var checks := 0
var failures: Array[String] = []
var report := {}


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _run() -> void:
	_test_rig_slot()
	_test_clips_present()
	_test_same_skeleton_as_ual()
	_test_choose_jump()
	_test_settle()
	_test_loops()
	_test_root()
	await _test_pose_doll()
	report["checks"] = checks
	report["failures"] = failures
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT.get_base_dir()))
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	print("DROP_MOTION_UNIT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


# ------------------------------------------------------------------ tests

func _test_rig_slot() -> void:
	check(AnimationRig.SLOT_DROP == 27, "SLOT_DROP is the slot after FallingIdle")
	check(AnimationRig.FBX_PATHS.size() == AnimationRig.SLOT_COUNT, "FBX_PATHS covers every slot")
	check(AnimationRig.SLOT_NAMES.size() == AnimationRig.SLOT_COUNT, "SLOT_NAMES covers every slot")
	check(AnimationRig.FBX_PATHS[AnimationRig.SLOT_DROP] == DropMotion.GLB_PATH, "SLOT_DROP loads drop_moves.glb")
	check(AnimationRig.SLOT_NAMES[AnimationRig.SLOT_DROP] == "Drop", "SLOT_DROP is named Drop")


func _test_clips_present() -> void:
	check(DropMotion.has_assets(), "drop_moves.glb and drop_moves.json exist")
	check(DropMotion.all_clips().size() == 24, "24 clips in the contract table (4.4)")
	var lengths := {}
	for clip: String in DropMotion.all_clips():
		var info := DropMotion.clip_info(clip)
		check(bool(info.found), "json has " + clip)
		check(not DropMotion.sample(clip, 0.0).is_empty(), "glb has " + clip)
		var anim := DropMotion._anims.get(clip) as Animation
		if anim != null:
			check(absf(anim.length - float(info.length)) < 0.02, "%s length json %.3f = glb %.3f" % [clip, float(info.length), anim.length])
			# every bone but the leaf tips keeps its rotation track (nothing dropped as "immutable")
			var tracks: Dictionary = DropMotion._tracks[clip]
			var missing: Array[String] = []
			for bone: String in DropMotion._bone_names:
				if not bone.contains("_leaf") and bone != "root" and int((tracks.get(bone, [-1, -1]) as Array)[1]) < 0:
					missing.append(bone)
			check(missing.is_empty(), "%s has a rotation track for every bone %s" % [clip, missing])
			check(int((tracks.get(DropMotion.HIPS_BONE, [-1, -1]) as Array)[0]) >= 0, clip + " has the pelvis position track")
		lengths[clip] = float(info.length)
	report["lengths"] = lengths


func _test_same_skeleton_as_ual() -> void:
	var scene := load(UAL_PATH) as PackedScene
	var node := scene.instantiate()
	var ual: Skeleton3D = node.find_children("*", "Skeleton3D", true, false)[0]
	DropMotion._load_rig()
	var names := DropMotion._bone_names
	check(names.size() == ual.get_bone_count(), "same bone count as UAL (%d / %d)" % [names.size(), ual.get_bone_count()])
	var worst_pos := 0.0
	var worst_rot := 0.0
	for i in range(names.size()):
		var j := ual.find_bone(names[i])
		check(j >= 0, "UAL has bone " + names[i])
		if j < 0:
			continue
		var parent_name := names[DropMotion._bone_parent[i]] if DropMotion._bone_parent[i] >= 0 else ""
		var ual_parent := ual.get_bone_name(ual.get_bone_parent(j)) if ual.get_bone_parent(j) >= 0 else ""
		check(parent_name == ual_parent, "same parent for " + names[i])
		var a: Transform3D = DropMotion._bone_rest[i]
		var b := ual.get_bone_rest(j)
		worst_pos = maxf(worst_pos, a.origin.distance_to(b.origin))
		worst_rot = maxf(worst_rot, rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())))
	check(worst_pos < 0.002, "rest positions match UAL (worst %.4f m)" % worst_pos)
	check(worst_rot < 0.5, "rest rotations match UAL (worst %.3f deg)" % worst_rot)
	report["rest_vs_ual"] = {"pos_m": worst_pos, "rot_deg": worst_rot}
	node.free()


func _test_choose_jump() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	var last := {}
	var trials := 20000
	var special := {1: 0, 2: 0}
	var seen := {}
	var hesitate_first := 0
	var same_special := 0
	var repeat_special := 0
	var same_basic := 0
	var prev := {}
	for n in range(trials):
		var first := 1 + rng.randi_range(0, 1)
		var pair := DropMotion.choose_pair(rng, last, first)
		for p: int in [1, 2]:
			var clip := String(pair[p])
			if n < 3:
				check(DropMotion.is_jump(clip), "a jump clip: " + clip)
			seen[clip] = int(seen.get(clip, 0)) + 1
			if DropMotion.SPECIAL_JUMPS.has(clip):
				special[p] += 1
				if prev.values().has(clip):
					repeat_special += 1
			if clip == DropMotion.HESITATE and p == first:
				hesitate_first += 1
		if DropMotion.SPECIAL_JUMPS.has(String(pair[1])) and pair[1] == pair[2]:
			same_special += 1
		if DropMotion.BASIC_JUMPS.has(String(pair[1])) and pair[1] == pair[2]:
			same_basic += 1
		prev = pair.duplicate()
	for p: int in [1, 2]:
		var rate := float(special[p]) / trials
		check(absf(rate - DropMotion.SPECIAL_CHANCE) < 0.012, "P%d special rate %.3f is about 15%%" % [p, rate])
	check(same_special == 0, "the two never share a special (%d)" % same_special)
	check(repeat_special == 0, "a special never repeats the previous drop (%d)" % repeat_special)
	check(hesitate_first == 0, "Hesitate only for the second jumper (%d)" % hesitate_first)
	check(same_basic == 0, "two basic jumpers use the two different basics (%d)" % same_basic)
	for clip: String in DropMotion.SPECIAL_JUMPS + DropMotion.BASIC_JUMPS:
		check(int(seen.get(clip, 0)) > 0, "%s comes up" % clip)
	report["choose"] = {"trials": trials, "seen": seen, "special_rate": [float(special[1]) / trials, float(special[2]) / trials]}


## どの降り方も端を離れて 1.2 秒以内に共通の腹ばいに落ち着く（heli_drop.md 2.2）。json の数字だけでなく、姿を測って確かめる。
func _test_settle() -> void:
	var out := {}
	for clip: String in DropMotion.BASIC_JUMPS + DropMotion.SPECIAL_JUMPS:
		var info := DropMotion.clip_info(clip)
		var leave := float(info.leave)
		var settle := float(info.settle)
		var length := float(info.length)
		check(leave > 0.0 and settle > leave, "%s has leave %.2f and settle %.2f" % [clip, leave, settle])
		check(settle - leave <= DropMotion.SETTLE_LIMIT + 0.0001, "%s settles %.2f s after leaving (json)" % [clip, settle - leave])
		check(absf(DropMotion.settle_delay(clip) - (settle - leave)) < 0.0001, "settle_delay matches for " + clip)
		# 姿で測る：端を離れてから、SD_Box_Loop（同じ位相）との差が SETTLED_DEG 未満になって、そのまま最後まで保つ最初の時刻
		var measured := -1.0
		var t := leave
		var worst_after := 0.0
		while t <= length + 0.0001:
			var err := _pose_error(clip, t, DropMotion.BOX_LOOP, t - settle)
			if err < SETTLED_DEG:
				if measured < 0.0:
					measured = t
				worst_after = maxf(worst_after, err)
			else:
				measured = -1.0
				worst_after = 0.0
			t += 1.0 / 60.0
		check(measured >= 0.0, "%s ends in the box" % clip)
		check(measured - leave <= DropMotion.SETTLE_LIMIT + 0.02, "%s is in the box %.2f s after leaving (measured)" % [clip, measured - leave])
		check(_pose_error(clip, settle, DropMotion.BOX_LOOP, 0.0) < 1.0, "%s at settle is SD_Box_Loop at 0" % clip)
		# 腹が下、頭が前（クリップの +Z）
		var body := _body_basis(clip, settle)
		check(body.z.y < -0.9, "%s belly down at settle (front.y %.2f)" % [clip, body.z.y])
		check(body.y.z > 0.9, "%s head forward at settle (head.z %.2f)" % [clip, body.y.z])
		out[clip] = {"leave": leave, "settle": settle, "json_delay": settle - leave, "measured_delay": measured - leave}
	report["settle"] = out


func _test_loops() -> void:
	for clip: String in [DropMotion.BENCH_SIT, DropMotion.RAMP_RUN_UP, DropMotion.RAMP_WALK, DropMotion.RAMP_RUN_OUT] + DropMotion.BOX_CLIPS:
		var info := DropMotion.clip_info(clip)
		check(bool(info.loop), clip + " loops")
		var length := float(info.length)
		check(_pose_error(clip, 0.0, clip, length - 0.0005) < 2.0, clip + " closes its loop")
	for clip: String in DropMotion.BOX_CLIPS:
		check(is_equal_approx(float(DropMotion.clip_info(clip).length), float(DropMotion.clip_info(DropMotion.BOX_LOOP).length)), clip + " has the box length (phase-locked)")
	# 傾きは腹ばいとはっきり違う
	for clip: String in [DropMotion.BOX_LEAN_LEFT, DropMotion.BOX_LEAN_RIGHT, DropMotion.BOX_LEAN_FORWARD, DropMotion.BOX_LEAN_BACK]:
		check(_pose_error(clip, 0.3, DropMotion.BOX_LOOP, 0.3) > 8.0, clip + " differs from the box")
	var left := _body_basis(DropMotion.BOX_LEAN_LEFT, 0.0)
	var right := _body_basis(DropMotion.BOX_LEAN_RIGHT, 0.0)
	# 左へ動く：体の左（+X）が下がる
	check(left.x.y < -0.15 and right.x.y > 0.15, "lean left drops the left side (%.2f), right the right (%.2f)" % [left.x.y, right.x.y])


func _test_root() -> void:
	for clip: String in DropMotion.all_clips():
		var info := DropMotion.clip_info(clip)
		var root: Array = info.root
		var frames := int(roundf(float(info.length) * float(info.fps)))
		check(root.size() == frames + 1, "%s root has a sample per frame" % clip)
		var worst := 0.0
		for i in range(1, root.size()):
			worst = maxf(worst, DropMotion._vec(root[i]).distance_to(DropMotion._vec(root[i - 1])))
		check(worst < 0.5, "%s root moves smoothly (largest step %.2f m)" % [clip, worst])
		check(DropMotion.root_offset(clip, 0.0).length() < 0.001, clip + " root starts at the origin")
	for clip: String in DropMotion.BASIC_JUMPS + DropMotion.SPECIAL_JUMPS:
		var info := DropMotion.clip_info(clip)
		var leave := float(info.leave)
		check(absf(DropMotion.root_offset(clip, leave).y) < 0.001, clip + " is on the floor when it leaves")
		check(DropMotion.root_offset(clip, float(info.settle)).y < -0.5, clip + " has fallen by the time it settles")
		check(float(info.edge) > 0.8, "%s takes off %.2f m ahead of its start" % [clip, float(info.edge)])
		check(DropMotion.is_grounded(clip, leave - 0.05) and not DropMotion.is_grounded(clip, leave + 0.05), clip + " contact ends at leave")
	for clip: String in DropMotion.LANDINGS:
		var info := DropMotion.clip_info(clip)
		check(float(info.land) > float(info.leave), clip + " lands after leaving")
		check(absf(DropMotion.root_offset(clip, float(info.land)).y + float(info.drop)) < 0.01, clip + " lands drop m below the ramp")
		check(DropMotion.is_grounded(clip, float(info.land) + 0.1), clip + " is on the floor after landing")
	var run: Dictionary = DropMotion.clip_info(DropMotion.RAMP_RUN_OUT)
	var cycle := float(run.length)
	check(absf(DropMotion.root_offset(DropMotion.RAMP_RUN_OUT, cycle * 2.5).z - float(run.speed) * cycle * 2.5) < 0.15, "the run's root keeps going loop after loop")


## 人形：根が回っていても、根から見た姿は同じ（pose_doll）。place で足の裏が床に着く。
func _test_pose_doll() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var a_root := Node3D.new()
	holder.add_child(a_root)
	var b_root := Node3D.new()
	b_root.rotation_degrees = Vector3(0.0, 70.0, 25.0)
	b_root.position = Vector3(3.0, 1.0, -2.0)
	holder.add_child(b_root)
	var a := EmoteBlockmanPreview.build_player_skeleton(true, a_root, HatData.HAT_NONE)
	var b := EmoteBlockmanPreview.build_player_skeleton(false, b_root, HatData.HAT_NONE)
	await get_tree().process_frame
	for clip: String in ["SD_Jump_Backflip", DropMotion.BOX_LOOP, "SD_Land_Hero"]:
		check(DropMotion.pose_doll(a, clip, 0.9), "pose_doll " + clip)
		check(DropMotion.pose_doll(b, clip, 0.9), "pose_doll rotated " + clip)
		var worst := 0.0
		for key: String in ["spine", "head_pivot", "l_elbow", "r_knee", "l_ankle", "r_wrist"]:
			var qa := ((a[key] as Node3D).global_basis).get_rotation_quaternion()
			var qb := (b_root.global_basis.inverse() * (b[key] as Node3D).global_basis).get_rotation_quaternion()
			worst = maxf(worst, rad_to_deg(qa.angle_to(qb)))
		check(worst < 0.5, "%s: same pose under a turned root (%.3f deg)" % [clip, worst])
	# 立って走るクリップを床（y = 0.5）に置くと、足の裏が床に着く
	var frame := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 0.5, 2.0))
	DropMotion.place_doll(a, DropMotion.RAMP_WALK, 0.2, frame)
	var lowest := DropMotion._lowest_along(a, Vector3.UP)
	check(absf(lowest - (0.5 + DropMotion.FOOT_CLEARANCE)) < 0.005, "place puts the feet on the floor (%.3f)" % lowest)
	var pelvis := a["pelvis"] as Node3D
	var expected := frame * DropMotion.root_offset(DropMotion.RAMP_WALK, 0.2)
	check(Vector2(pelvis.global_position.x - expected.x, pelvis.global_position.z - expected.z).length() < 0.01, "place puts the pelvis over the root")
	holder.queue_free()


# ------------------------------------------------------------------ helpers

## 2 つの姿の差：人形に当てる骨（PART_BONES と腰）のスケルトン空間での向きの差の最大（度）。
func _pose_error(clip_a: String, t_a: float, clip_b: String, t_b: float) -> float:
	var ga := DropMotion.globals(DropMotion.sample(clip_a, t_a))
	var gb := DropMotion.globals(DropMotion.sample(clip_b, t_b))
	var worst := 0.0
	var bones: Array[String] = [DropMotion.HIPS_BONE]
	for row: Array in DropMotion.PART_BONES:
		if not String(row[0]).contains("_prox") and not String(row[0]).contains("_mid") and not String(row[0]).contains("_dist"):
			bones.append(String(row[1]))
	for bone: String in bones:
		var qa := (ga[bone] as Transform3D).basis.get_rotation_quaternion()
		var qb := (gb[bone] as Transform3D).basis.get_rotation_quaternion()
		worst = maxf(worst, rad_to_deg(qa.angle_to(qb)))
	return worst


## 体の向き（クリップの座標）：休みの姿からの腰の回り。x＝体の左、y＝頭の向き、z＝体の前。
func _body_basis(clip: String, t: float) -> Basis:
	var g := DropMotion.globals(DropMotion.sample(clip, t))
	var rest := DropMotion._bone_rest.duplicate()
	var rest_pose: Array[Transform3D] = []
	for r in rest:
		rest_pose.append(r)
	var g0 := DropMotion.globals(rest_pose)
	var turn := (g[DropMotion.HIPS_BONE] as Transform3D).basis.orthonormalized() * (g0[DropMotion.HIPS_BONE] as Transform3D).basis.orthonormalized().inverse()
	return turn
