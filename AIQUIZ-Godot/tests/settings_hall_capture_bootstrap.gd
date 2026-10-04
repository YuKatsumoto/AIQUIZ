extends SceneTree

## 設定ホール（ui/settings_hall.tscn）を単体で立ち上げ、到着して落ち着いた構図を何枚か撮る。
## 引数（-- のあと）:
##   shots=N（枚数、既定 4）、every=秒（間隔、既定 2.5）、wait=秒（最初の 1 枚まで、既定 9）、tag=名前
##   view=practice（実習場の視点で撮る。既定は講義室）
##   times=a,b,c（実習場の時計を各ショットの前にその秒へ合わせる。指定すると shots は times の数）
## 結果: res://artifacts/settings_hall/capture/<tag>_NN.png
## 例: Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/settings_hall_capture_bootstrap.gd -- view=practice times=3,8,16,22 tag=practice

const OUT := "res://artifacts/settings_hall/capture/"
const HALL := "res://ui/settings_hall.tscn"

var _args := {"shots": "4", "every": "2.5", "wait": "9", "tag": "hall", "view": "lecture", "times": ""}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
	call_deferred("boot")


func boot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file(HALL)
	var times: Array[float] = []
	for item: String in str(_args.times).split(",", false):
		times.append(float(item))
	var start := Time.get_ticks_msec()
	var wait_ms := int(float(_args.wait) * 1000.0)
	var every_ms := int(float(_args.every) * 1000.0)
	var shots := times.size() if not times.is_empty() else int(_args.shots)
	var taken := 0
	var view_set := false
	while taken < shots:
		await process_frame
		var hall := current_scene
		if not view_set and hall != null and Time.get_ticks_msec() - start >= wait_ms - 2000:
			if str(_args.view) == "practice" and hall.has_method("set_view_now"):
				# パネルのボタンと同じ道筋（副題とボタンの文字も変わる）で切り替え、カメラだけ即座に寄せる。
				var panel: Node = hall.get("_panel")
				if panel != null:
					panel.call("set_practice_view", true)
				hall.call("set_view_now", 1.0)
			view_set = true
		if Time.get_ticks_msec() - start < wait_ms + every_ms * taken:
			continue
		var yard := hall.get_node_or_null("PracticeYard") if hall != null else null
		if not times.is_empty() and yard != null:
			yard.call("seek", times[taken])
			await process_frame
			yard.call("seek", times[taken])
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := OUT + "%s_%02d.png" % [_args.tag, taken]
		image.save_png(ProjectSettings.globalize_path(path))
		var phase: String = str((yard.get("last_program") as Dictionary).get("phase", "")) if yard != null else ""
		print("CAPTURE ", path, " phase=", phase, " fps=", Engine.get_frames_per_second())
		taken += 1
	quit(0)
