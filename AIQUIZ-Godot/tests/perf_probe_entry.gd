extends Node

## Entry of the runtime performance harness inside an EXPORTED build (export templates ignore
## --script). A measurement-only export lists this file as an extra autoload through an
## override.cfg next to the executable:
##   [autoload]
##   PerfProbeEntry="*res://tests/perf_probe_entry.gd"
## The game then boots exactly as a player's copy does (ui/startup_loading.tscn is the main
## scene) and tests/perf_runtime.gd takes over from there with --boot=running, so it waits for
## the menu instead of restarting the boot. Harness arguments come after "--" as usual.
## Network: the measurement folder carries its own .env pointing every service at a closed
## local port (EnvFile prefers the .env next to the executable).

const Util := preload("res://tests/perf_util.gd")


func _ready() -> void:
	if OS.get_cmdline_user_args().is_empty():
		queue_free()
		return
	call_deferred("_start")


func _start() -> void:
	var args := Util.parse_args()
	args["boot"] = "running"
	var info := {"measure": String(args.get("measure", "endless")), "entry": "exported_autoload"}
	var script := load("res://tests/perf_runtime.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("[perf] tests/perf_runtime.gd failed to load")
		get_tree().quit(1)
		return
	var runtime: Node = script.new()
	runtime.name = "PerfHarness"
	runtime.call("configure", info, args)
	get_tree().root.add_child(runtime)
