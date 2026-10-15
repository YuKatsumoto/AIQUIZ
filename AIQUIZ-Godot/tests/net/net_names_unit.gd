extends SceneTree

## Name filter and 二つ名 dice: every combination the dice can produce must be safe to show.
##   Godot --headless --path . --script res://tests/net/net_names_unit.gd

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_filter_rules()
	_epithets()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	print("NET_NAMES " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _filter_rules() -> void:
	for good in ["たろう", "でんせつのパンダ", "九九マスター★", "ＡＢＣ１２", "  はなこ  ", "Sora"]:
		check(NetNameFilter.is_ok(good), "accepts %s" % good)
	var cases := {
		"": NetNameFilter.Result.EMPTY,
		"あいうえおかきくけこさしす": NetNameFilter.Result.TOO_LONG,
		"た ろう": NetNameFilter.Result.BAD_CHAR,
		"<b>": NetNameFilter.Result.BAD_CHAR,
		"たろう😀": NetNameFilter.Result.BAD_CHAR,
		"0901234": NetNameFilter.Result.TOO_MANY_DIGITS,
		"ばか": NetNameFilter.Result.NG_WORD,
		"バカ": NetNameFilter.Result.NG_WORD,
		"しーね": NetNameFilter.Result.NG_WORD,
		"シネ": NetNameFilter.Result.NG_WORD,
		"FUCK": NetNameFilter.Result.NG_WORD,
		"さくら小学校": NetNameFilter.Result.NG_WORD,
	}
	for name: String in cases:
		check(NetNameFilter.check(name) == cases[name], "%s -> %d (got %d)" % [name, cases[name], NetNameFilter.check(name)])
	check(NetNameFilter.normalize("ＡＢＣ１２") == "ABC12", "full-width normalised")


func _epithets() -> void:
	var too_long := 0
	for title in NetEpithets.TITLES:
		for noun in NetEpithets.NAMES:
			var result := NetNameFilter.check(title + noun)
			if result == NetNameFilter.Result.TOO_LONG:
				too_long += 1
			elif result != NetNameFilter.Result.OK:
				failures.append("combination rejected: %s%s (%d)" % [title, noun, result])
			checks += 1
	for rare in NetEpithets.RARE:
		check(NetNameFilter.is_ok(rare), "rare rejected: %s" % rare)
	var total := NetEpithets.TITLES.size() * NetEpithets.NAMES.size()
	check(too_long * 10 < total, "too many combinations exceed %d characters: %d/%d" % [NetNameFilter.MAX_LENGTH, too_long, total])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in range(500):
		var name := NetEpithets.roll(rng)
		check(NetNameFilter.is_ok(name), "roll produced unsafe %s" % name)
		seen[name] = true
	check(seen.size() > 400, "dice variety %d/500" % seen.size())
	print("epithets: %d combinations (+%d rare), %d skipped as too long, 500 rolls -> %d distinct" % [total, NetEpithets.RARE.size(), too_long, seen.size()])
