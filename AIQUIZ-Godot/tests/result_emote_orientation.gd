extends Node

const JOINTS := ["pelvis", "spine", "neck", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist", "l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle", "l_toe", "r_toe"]

## Compare anatomical joints with the customization preview at the same FBX
## sample. Ignore the deliberate camera-facing head and world-space carrier.
static func pose_errors(actor: Node3D, parts: Dictionary, dance: ResultWinnerDance) -> Array[String]:
	var errors: Array[String] = []
	if actor.global_basis.determinant() < 0.99:
		errors.append("dancer inherits a stage reflection")
	var reference := Node3D.new()
	actor.get_tree().root.add_child(reference)
	reference.visible = false
	var expected := EmoteBlockmanPreview.build_player_skeleton(true, reference, HatData.HAT_NONE)
	var local_time := dance.sample_time
	var active: Dictionary = dance.clips.back()
	for clip in dance.clips:
		active = clip
		if local_time < float(clip.duration): break
		local_time -= float(clip.duration)
	EmoteBlockmanPreview.apply_skeleton_pose(expected, active.skeleton, active.bones, true, null, {})
	var inverse := actor.global_transform.affine_inverse()
	for joint in JOINTS:
		var actual: Transform3D = inverse * (parts[joint] as Node3D).global_transform
		var target: Transform3D = (expected[joint] as Node3D).global_transform
		if actual.origin.distance_to(target.origin) > 0.001 or not actual.basis.is_equal_approx(target.basis):
			errors.append("%s differs from customization" % joint)
	reference.free()
	return errors

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var failures: Array[String] = []
	var samples := 0
	var stage := Node3D.new()
	add_child(stage)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(-2.7, 0.16, -3.95)
	for player in [1, 2]:
		stage.basis = Basis(Vector3.UP, PI).scaled(Vector3(-1, 1, 1) if player == 2 else Vector3.ONE)
		for emote in EmoteData.get_playable_emote_ids():
			var actor := Node3D.new()
			stage.add_child(actor)
			var parts := EmoteBlockmanPreview.build_player_skeleton(player == 1, actor, HatData.HAT_NONE)
			var dance := ResultWinnerDance.new()
			dance.setup(stage, emote)
			if dance.clips.is_empty(): failures.append("emote %d failed to load" % emote)
			var offset := 0.0
			for clip in dance.clips:
				for fraction in [0.1, 0.3, 0.6, 0.9]:
					actor.transform = Transform3D.IDENTITY
					# Add a complete cycle so the blend is finished even near frame zero.
					dance.apply(actor, parts, camera, ResultWinnerDance.START + dance.duration + offset + float(clip.duration) * fraction, -1.2)
					for error in pose_errors(actor, parts, dance):
						failures.append("P%d emote %d at %.3f: %s" % [player, emote, dance.sample_time, error])
					samples += 1
				offset += float(clip.duration)
			dance.clear()
			actor.free()
	var result := {"samples": samples, "joints_per_sample": JOINTS.size(), "failures": failures, "passed": failures.is_empty()}
	print("RESULT_EMOTE_ORIENTATION " + JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
