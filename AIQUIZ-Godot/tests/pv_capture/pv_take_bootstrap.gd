extends SceneTree

## PV の撮影テイク（pv_take_base.gd の上に書いたもの）を動かす。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s06_s07 quality=ultra
## 動きのブレ付き（本番）: --fixed-fps 480 ... -- take=<名前> quality=ultra sub=8
## take=<名前> で tests/pv_capture/pv_<名前>_runtime.gd を読む。ほかの引数は pv_take_base.gd。

func _initialize() -> void:
	call_deferred("boot")


func boot() -> void:
	var take := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("take="):
			take = arg.trim_prefix("take=").validate_filename()
	var path := "res://tests/pv_capture/pv_%s_runtime.gd" % take
	var script := load(path) as Script if take != "" and ResourceLoader.exists(path) else null
	if script == null or not script.can_instantiate():
		push_error("PV take not found: %s (pass take=<name>)" % path)
		quit(1)
		return
	root.add_child(script.new())
