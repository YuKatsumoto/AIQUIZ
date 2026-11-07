extends SceneTree

## Shared bootstrap of the runtime performance harness. tests/perf_endless_bootstrap.gd and
## tests/perf_multimatch_bootstrap.gd extend it and only name their measure.
##
## _initialize() runs before the autoloads' _ready(), so the safety setup happens first:
##  - GameManager.settings_path -> user://perf_harness_settings.json (a copy of the player's
##    settings with the harness quality / FPS cap); the player's settings.json is only read.
##  - PROXY_URL / FIREBASE_DB_URL / RELAY_SERVER_URL point at a closed local port, so nothing
##    (quiz APIs, telemetry, rating uploads) leaves the machine. GameManager._ready re-reads
##    .env into the environment, so the override is applied again right after it.
##  - user:// files a match writes are backed up and restored at the end (perf_user_data_guard).

const Util := preload("res://tests/perf_util.gd")
const Guard := preload("res://tests/perf_user_data_guard.gd")
const SETTINGS_PATH := "user://perf_harness_settings.json"
const PLAYER_SETTINGS_PATH := "user://settings.json"
const BLOCKED := {
	"PROXY_URL": "http://127.0.0.1:9",
	"FIREBASE_DB_URL": "http://127.0.0.1:9",
	"RELAY_SERVER_URL": "ws://127.0.0.1:9",
}

var _guard: RefCounted
var _args: Dictionary = {}
var _info: Dictionary = {}
var _finished := false


func _measure() -> String:
	return ""


func _initialize() -> void:
	_args = Util.parse_args()
	var measure := _measure()
	if measure.is_empty():
		measure = String(_args.get("measure", "endless"))
	_info["measure"] = measure
	_guard = Guard.new()
	_guard.begin()
	_info["user_data_leftover_moved_to"] = _guard.leftover_moved_to
	_block_network()
	var gm := root.get_node_or_null("GameManager")
	_info["settings_hooked_before_ready"] = gm != null
	if gm != null:
		_prepare_settings(gm)
		gm.ready.connect(_block_network, CONNECT_ONE_SHOT)
	call_deferred("_boot")


func _block_network() -> void:
	for key: String in BLOCKED.keys():
		OS.set_environment(key, String(BLOCKED[key]))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _prepare_settings(gm: Node) -> void:
	var player := _read_json(PLAYER_SETTINGS_PATH)
	var player_fps := int(player.get("max_fps", 60)) if bool(player.get("max_fps_chosen", false)) else 60
	var quality := String(_args.get("quality", String(player.get("graphics_quality", "balanced"))))
	var fps := Util.arg_int(_args, "max_fps", player_fps)
	var harness := player.duplicate(true)
	harness["graphics_quality"] = quality
	harness["max_fps"] = fps
	harness["max_fps_chosen"] = true
	var consts: Dictionary = (gm.get_script() as Script).get_script_constant_map() if gm.get_script() != null else {}
	var tutorial_version := int(consts.get("CURRENT_TUTORIAL_VERSION", 0))
	harness["tutorial_prompt_seen_version"] = maxi(int(player.get("tutorial_prompt_seen_version", 0)), tutorial_version)
	harness["practice_intro_seen"] = true
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(harness, "  "))
		f.close()
	gm.set("settings_path", SETTINGS_PATH)
	_info["player_settings"] = {
		"graphics_quality": player.get("graphics_quality", null),
		"max_fps": player.get("max_fps", null),
		"max_fps_chosen": player.get("max_fps_chosen", null),
	}
	_info["harness_settings"] = {"graphics_quality": quality, "max_fps": fps}


func _boot() -> void:
	var gm := root.get_node_or_null("GameManager")
	if gm != null and String(gm.get("settings_path")) != SETTINGS_PATH:
		# Fallback when the autoload was not reachable from _initialize().
		_prepare_settings(gm)
		gm.call("_load_user_settings")
		# Autoload names are not identifiers yet when this SceneTree script compiles.
		var quality_script: Script = load("res://scripts/core/graphics_quality.gd")
		quality_script.call("apply_rendering_server", String(gm.get("graphics_quality")))
		Engine.max_fps = int(gm.call("effective_max_fps"))
	_block_network()
	var script := load("res://tests/perf_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("[perf] tests/perf_runtime.gd failed to load")
		perf_finish(1)
		return
	var runtime: Node = script.new()
	runtime.name = "PerfHarness"
	runtime.call("configure", _info, _args)
	root.add_child(runtime)


## Called by the runtime when it is done (or by a fatal error).
func perf_finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	var report: Dictionary = _guard.restore(false)
	print("[perf] user data restore: ", JSON.stringify(report))
	quit(code)


func _finalize() -> void:
	# The scene tree has exited by now: catch anything written on the way out.
	if _guard != null:
		var report: Dictionary = _guard.restore(true)
		if not (report["restored"] as Array).is_empty() or not (report["removed"] as Array).is_empty():
			print("[perf] user data restore (final): ", JSON.stringify(report))
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
