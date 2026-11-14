extends SceneTree

## アップデートの判定のテスト（ヘッドレス実行用）。通信はしない。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/test_game_updater.gd
const GameUpdater = preload("res://scripts/core/game_updater.gd")
const SHA := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const MANIFEST_URL := "https://example.com/testopia/windows.json?t=1"

var _failures := 0


func _initialize() -> void:
	_check(GameUpdater.compare_versions("1.0.10", "1.0.9") == 1, "1.0.10 is newer than 1.0.9")
	_check(GameUpdater.compare_versions("1.0.3", "1.0.3") == 0, "same version")
	_check(GameUpdater.compare_versions("1.0", "1.0.1") == -1, "missing part counts as 0")
	_check(GameUpdater.resolve_url(MANIFEST_URL, "patch.pck") == "https://example.com/testopia/patch.pck",
		"relative patch url resolves next to the manifest")
	_check(GameUpdater.resolve_url(MANIFEST_URL, "https://cdn.example.com/p.pck") == "https://cdn.example.com/p.pck",
		"absolute patch url is kept")
	_check(GameUpdater.format_size(1843200) == "1.8 MB", "size in MB")
	_check(GameUpdater.format_size(300) == "1 KB", "small size rounds up to 1 KB")

	var manifest := {
		"version": "1.0.4", "base": "1.0.3", "required": true, "notes": "n", "page_url": "https://example.com/dl",
		"patch": {"url": "patch_1.0.4_windows.pck", "size": 1843200, "sha256": SHA.to_upper()},
	}
	var offer := GameUpdater.offer_from_manifest(manifest, MANIFEST_URL, "1.0.3", "1.0.3", [])
	_check(offer.get("kind") == GameUpdater.KIND_PATCH, "newer version on the same base is a patch")
	_check(offer.get("url") == "https://example.com/testopia/patch_1.0.4_windows.pck", "patch url is absolute")
	_check(offer.get("sha256") == SHA, "sha256 is lower-cased")
	_check(offer.get("size") == 1843200 and offer.get("required") == true, "size and required are carried")

	_check(GameUpdater.offer_from_manifest(manifest, MANIFEST_URL, "1.0.4", "1.0.3", []).is_empty(),
		"already on the latest patch: nothing to offer")
	_check(GameUpdater.offer_from_manifest(manifest, MANIFEST_URL, "1.0.3", "1.0.3", [SHA]).is_empty(),
		"a patch this PC rejected is not offered again")
	var full := GameUpdater.offer_from_manifest(manifest, MANIFEST_URL, "1.0.2", "1.0.2", [])
	_check(full.get("kind") == GameUpdater.KIND_FULL and not full.has("url"),
		"a patch for another base means a full download")
	var no_patch := {"version": "1.1.0", "base": "1.1.0", "page_url": "https://example.com/dl"}
	_check(GameUpdater.offer_from_manifest(no_patch, MANIFEST_URL, "1.0.4", "1.0.3", []).get("kind") == GameUpdater.KIND_FULL,
		"a new full release without a patch means a full download")
	var broken := manifest.duplicate(true)
	broken["patch"]["sha256"] = "abc"
	_check(GameUpdater.offer_from_manifest(broken, MANIFEST_URL, "1.0.3", "1.0.3", []).is_empty(),
		"a patch entry without a valid sha256 is ignored")
	_check(GameUpdater.offer_from_manifest({}, MANIFEST_URL, "1.0.3", "1.0.3", []).is_empty(), "empty manifest")

	# PatchBoot は一番最初の autoload でないと、ほかの autoload のスクリプトを差し替えられない。
	var first_autoload := ""
	for info: Dictionary in ProjectSettings.get_property_list():
		var key := str(info.get("name", ""))
		if key.begins_with("autoload/") and (first_autoload.is_empty()
				or ProjectSettings.get_order(key) < ProjectSettings.get_order(first_autoload)):
			first_autoload = key
	_check(first_autoload == "autoload/PatchBoot", "PatchBoot is the first autoload (found %s)" % first_autoload)

	print("test_game_updater: %s" % ("OK" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAILED: " + label)
