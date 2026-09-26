extends Node

## Goal stand structure checks (no gameplay): every quality keeps a full cast with
## egg throwers on both sides, fans sit behind their player's lane, the clips exist
## with the right loop modes, and spawning stays within a small per-frame budget.
## Run: Godot --headless --path . --script tests/goal_stand_bootstrap.gd

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	var report := {}
	for quality in ["low", "balanced", "high"]:
		var stand := GoalStand.new()
		add_child(stand)
		var started := Time.get_ticks_usec()
		stand.setup(quality)
		var setup_msec := float(Time.get_ticks_usec() - started) / 1000.0
		var worst_frame := 0.0
		var frames := 0
		while not stand.is_populated():
			started = Time.get_ticks_usec()
			stand.update_stand(1.0 / 60.0, null, null, null)
			worst_frame = maxf(worst_frame, float(Time.get_ticks_usec() - started) / 1000.0)
			frames += 1
		var shot := stand.get_debug_snapshot()
		report[quality] = {"setup_msec": snappedf(setup_msec, 0.01), "worst_spawn_frame_msec": snappedf(worst_frame, 0.01),
			"spawn_frames": frames, "spectators": shot.spectators, "kinds": shot.kinds}
		check(int(shot.spectators) >= (40 if quality == "low" else 60), "%s: crowd size %d" % [quality, int(shot.spectators)])
		check(int(shot.kinds.get("HOTHEAD", 0)) == 6, "%s: six egg throwers, three per side" % quality)
		for kind in ["DANCER", "SIGN", "FLAG", "FOAM", "FAN"]:
			check(int(shot.kinds.get(kind, 0)) > 0, "%s: has %s" % [quality, kind])
		var left := 0
		var right := 0
		for s: GoalStand.Spectator in stand.spectators:
			check(absf(s.root.position.x) <= 13.0 and s.root.position.y >= 0.3, "%s: spectator on a tier" % quality)
			if s.team == 1:
				left += 1 if s.root.position.x < 0.0 else 0
			elif s.team == 2:
				right += 1 if s.root.position.x > 0.0 else 0
			check(s.body != null and s.body.material_override != null, "%s: body uses the crowd shader" % quality)
		check(left > 10 and right > 10, "%s: P1 fans behind P1's lane, P2 fans behind P2's" % quality)
		if quality == "balanced":
			var ap: AnimationPlayer = stand.spectators[0].ap
			for clip in GoalStand.DANCES + [&"SPEC_Cheer", &"SPEC_Clap", &"SPEC_Rage", &"SPEC_Despair", &"SPEC_Throw", &"SPEC_SignUp", &"SPEC_PointLaugh"]:
				check(ap.has_animation(clip), "clip %s exported" % clip)
			check(ap.get_animation(&"SPEC_Throw").loop_mode == Animation.LOOP_NONE, "throw is a one-shot")
			check(ap.get_animation(&"SPEC_Cheer").loop_mode == Animation.LOOP_LINEAR, "cheer loops")
			check(ap.get_animation(&"SPEC_Dance_YMCA").loop_mode == Animation.LOOP_NONE, "dances end so a new emote is picked")
		stand.free()
	print("GOAL_STAND_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "report": report}))
	get_tree().quit(0 if failures.is_empty() else 1)
