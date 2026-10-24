extends Node
## メニュー背景ランナーの行動選択（MenuActorActionPicker）の単体テスト。
## 以前は重みの合計がちょうど 1.0 で事故の分岐に届かなかったので、事故が重みどおり選ばれることを確かめる。
const Picker = preload("res://scripts/ui/menu_preview/menu_actor_action_picker.gd")
const PICKS := 20000
var failures: Array[String] = []
var checks := 0
var report := {}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 240923
	for is_2p: bool in [false, true]:
		for skill: float in [0.0, 1.0]:
			var ctx := Picker.Context.new()
			ctx.skill = skill
			ctx.is_2p = is_2p
			ctx.accident_allowed = true
			var counts := _count(ctx, rng)
			var acc := Picker.accident_weight(skill, is_2p)
			var expected := acc / (1.0 + acc)
			var share := float(counts[Picker.Action.ACCIDENT]) / PICKS
			report["accident_share_%s_%d" % ["2p" if is_2p else "1p", int(skill)]] = share
			check(absf(share - expected) < 0.015, "accident share %.3f vs %.3f (2p=%s skill=%.0f)" % [share, expected, is_2p, skill])
			check(counts[Picker.Action.HOLD] > 0 and counts[Picker.Action.ACROBATICS] > 0, "every action reachable")
	var ctx := Picker.Context.new()
	ctx.accident_allowed = false
	check(_count(ctx, rng)[Picker.Action.ACCIDENT] == 0, "no accident when not allowed")
	ctx = Picker.Context.new()
	ctx.accident_allowed = true
	ctx.ghost_alert = true
	var alert := _count(ctx, rng)
	check(alert[Picker.Action.ACCIDENT] == 0 and alert[Picker.Action.ACROBATICS] == 0, "ghost alert excludes accident and acrobatics")
	var calm := _count(Picker.Context.new(), rng)
	check(alert[Picker.Action.JUMP] > calm[Picker.Action.JUMP], "ghost alert jumps more")
	ctx = Picker.Context.new()
	ctx.grounded = false
	var airborne := _count(ctx, rng)
	check(airborne[Picker.Action.JUMP] == 0 and airborne[Picker.Action.ACROBATICS] == 0, "airborne excludes jump and acrobatics")
	ctx = Picker.Context.new()
	ctx.conveyor_paused = true
	var paused := _count(ctx, rng)
	check(paused[Picker.Action.HOLD] > calm[Picker.Action.HOLD] and paused[Picker.Action.DASH] < calm[Picker.Action.DASH], "paused conveyor holds more")
	for w: float in Picker.weights(Picker.Context.new()):
		check(w >= 0.0, "weights non-negative")
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "report": report}
	print("MENU_ACTION_PICKER ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)


func _count(ctx, rng: RandomNumberGenerator) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(Picker.Action.size())
	counts.fill(0)
	for i in PICKS:
		counts[Picker.pick(ctx, rng)] += 1
	return counts
