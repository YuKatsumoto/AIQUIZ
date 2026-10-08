extends SceneTree

## 設定ホールを立ち上げ、講義室の授業の進行役（lecture_director.gd）が動き出してから、近くのカメラで何枚か撮る。
## 引数（-- のあと）:
##   shots=N（既定 6）、every=秒（既定 2）、wait=秒（進行役が動き出してから 1 枚目まで、既定 1）、tag=名前
##   cam=board|mid|left|hand|front|close|class|wide|hall（既定 board）、jump=周:段（例 0:5 = 1 周目の 6 段目から）、speed=倍速（既定 1）
##   view=practice（実習場の視点）、yard_cycle=N（実習場を N 周目の頭から）、mode=lesson|lunch|after_school|night|weekend（時間帯の場面を決め打ち）、calls=秒:メソッド[:引数],...（進行役のメソッドを呼ぶ。例 3:on_sfx_test,6:on_click:lecturer）、early=1（到着の演出を待たずに撮り始める）、trace=1（進行役の段・場面が変わるたびに出力）、ssr=0（画面空間反射を切る、見比べ用）
## 結果: res://artifacts/settings_hall/director/<tag>_NN.png と、各ショットの進行役の状態（標準出力）
## 例: Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/lecture_director_capture.gd -- jump=0:4 shots=8 every=3

const OUT := "res://artifacts/settings_hall/director/"
const HALL := "res://ui/settings_hall.tscn"
## カメラ（講義セットのローカル座標の目・狙い・画角）
const CAMS := {
	"board": [Vector3(-1.2, 2.4, 5.2), Vector3(4.3, 0.95, 8.55), 40.0],
	"mid": [Vector3(5.6, 2.7, 3.0), Vector3(3.4, 1.15, 8.55), 46.0],
	"left": [Vector3(5.4, 2.1, 6.2), Vector3(2.5, 0.9, 8.55), 42.0],
	"hand": [Vector3(1.7, 1.35, 7.3), Vector3(3.25, 1.0, 8.45), 40.0],
	"front": [Vector3(1.0, 2.0, 4.7), Vector3(2.4, 0.95, 8.55), 40.0],
	"close": [Vector3(2.2, 1.35, 6.3), Vector3(2.9, 0.95, 8.55), 38.0],
	"class": [Vector3(5.6, 3.2, -2.6), Vector3(0.6, 0.8, 4.0), 46.0],
	"wide": [Vector3(6.5, 4.5, -5.5), Vector3(0.5, 1.0, 5.0), 48.0],
}

var _args := {"shots": "6", "every": "2", "wait": "1", "tag": "dir", "cam": "board", "jump": "", "speed": "1", "trace": "0", "ssr": "1", "vfog": "1", "envoff": "", "early": "0", "calls": "", "mode": "", "view": "", "yard_cycle": "", "yard_t": "0", "visit": "", "date": ""}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
	if str(_args.mode) != "":
		OS.set_environment("AIQUIZ_LECTURE_MODE", str(_args.mode))
	if str(_args.date) != "":
		OS.set_environment("AIQUIZ_LECTURE_DATE", str(_args.date))
	if str(_args.visit) != "":
		OS.set_environment("AIQUIZ_LECTURE_VISIT", str(_args.visit))
	call_deferred("boot")


func boot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file(HALL)
	var start := Time.get_ticks_msec()
	var director: Node = null
	while director == null:
		await process_frame
		var hall := current_scene
		if hall == null:
			continue
		var lecture: Node = hall.get("_lecture_set")
		if lecture != null:
			director = lecture.get("director")
		if Time.get_ticks_msec() - start > 90000:
			print("DIRECTOR_TIMEOUT")
			quit(1)
			return
	print("DIRECTOR_READY after ", (Time.get_ticks_msec() - start) / 1000.0, " s")
	var hall := current_scene
	# 到着の演出が終わるまで待つ（カメラの上書きは到着後に効く）
	while not bool(hall.get("_settled")) and str(_args.early) != "1":
		await process_frame
	if str(_args.jump) != "":
		var parts := str(_args.jump).split(":")
		director.call("jump_to", int(parts[0]), int(parts[1]))
	if str(_args.view) == "practice":
		var panel: Node = hall.get("_panel")
		if panel != null:
			panel.call("set_practice_view", true)
		hall.call("set_view_now", 1.0)
	if str(_args.yard_cycle) != "":
		var yard: Node = hall.get("_yard")
		yard.set("cycle_count", int(_args.yard_cycle))
		yard.set("variant", int(_args.yard_cycle) % 5)
		yard.call("seek", float(_args.yard_t))
	if str(_args.cam) != "hall":
		var cam: Array = CAMS.get(str(_args.cam), CAMS.board)
		hall.call("set_camera_override", cam[0], cam[1], cam[2])
	Engine.time_scale = float(_args.speed)
	if str(_args.ssr) == "0":
		var env: Environment = (hall.get("_camera") as Camera3D).environment if hall.get("_camera") != null else null
		if env == null:
			env = hall.get_viewport().world_3d.environment
		if env != null:
			env.ssr_enabled = false
			print("SSR off")
	if str(_args.envoff) != "":
		var env3: Environment = (hall.get("_camera") as Camera3D).environment
		for key: String in str(_args.envoff).split(","):
			env3.set(key + "_enabled", false)
			print("ENV off ", key)
	if str(_args.vfog) == "0":
		var env2: Environment = (hall.get("_camera") as Camera3D).environment
		if env2 == null:
			env2 = hall.get_viewport().world_3d.environment
		if env2 != null:
			env2.volumetric_fog_enabled = false
			print("VFOG off")
	var t0 := Time.get_ticks_msec()
	var shots := int(_args.shots)
	var every_ms := int(float(_args.every) * 1000.0 / float(_args.speed))
	var wait_ms := int(float(_args.wait) * 1000.0 / float(_args.speed))
	var taken := 0
	var last_trace := ""
	var calls: Array = []
	for item: String in str(_args.calls).split(",", false):
		var parts := item.split(":")
		calls.append({"t": float(parts[0]), "method": parts[1], "arg": parts[2] if parts.size() > 2 else ""})
	while taken < shots:
		await process_frame
		var now := (Time.get_ticks_msec() - t0) / 1000.0 * float(_args.speed)
		for c: Dictionary in calls:
			if not c.has("done") and now >= float(c.t):
				c.done = true
				if str(c.arg) != "":
					director.call(str(c.method), str(c.arg))
				else:
					director.call(str(c.method))
				print("CALL ", c.method, " ", c.arg)
		if str(_args.trace) == "1":
			var st: Dictionary = director.call("status")
			var line := "%s:%s %s %s %s" % [st.cycle, st.step, st.do, st.phase, st.event]
			if line != last_trace:
				print("TRACE t=%.1f %s" % [(Time.get_ticks_msec() - t0) / 1000.0 * float(_args.speed), line])
				last_trace = line
		if Time.get_ticks_msec() - t0 < wait_ms + every_ms * taken:
			continue
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := OUT + "%s_%02d.png" % [_args.tag, taken]
		image.save_png(ProjectSettings.globalize_path(path))
		var yd: Node = hall.get("_yard_director")
		print("CAPTURE ", path, " ", director.call("status"), " yard=", (yd.get("last_event") if yd != null else "-"), " fps=", Engine.get_frames_per_second())
		if str(_args.get("debug", "0")) == "1":
			var actor = (director.get("actors") as Dictionary).get("lecturer")
			var held = actor.call("holding", "R")
			var tip: Vector3 = actor.call("hand_tip_point")
			var want: Vector3 = actor.get("tip_point")
			print("REACH ik=%.2f gap=%.3f tip=%s want=%s shoulder=%s" % [float(actor.get("ik_weight")), tip.distance_to(want), tip, want, actor.call("shoulder_point")])
			if held != null:
				print("HELD ", held.name, " scale=", (held as Node3D).global_transform.basis.get_scale(), " at=", (held as Node3D).global_position)
			for node: Node in (actor.get("root") as Node).find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				print("MESH ", mi.name, " vis=", mi.is_visible_in_tree(), " scale=", mi.global_transform.basis.get_scale(), " aabb=", mi.get_aabb().size)
		if str(_args.get("canvas", "0")) == "1":
			var boards: Dictionary = director.get("boards")
			for tag: String in boards:
				var img: Image = (boards[tag] as SubViewport).get_texture().get_image()
				img.save_png(ProjectSettings.globalize_path(OUT + "%s_%02d_canvas_%s.png" % [_args.tag, taken, tag]))
		taken += 1
	quit(0)
