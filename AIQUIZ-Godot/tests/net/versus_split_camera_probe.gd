extends Node

## 中央の線が開く遷移（仕様書 S10 v1.6）で、ゲーム画面のカメラが開くのと同時に寄るかを見る。
## 灰色の静止画で覆ってから本物のゲーム画面へ切り替え、ゲーム画面が覆いを開く（reveal_current）あいだ、
## カメラの位置・画角・SceneTransition.get_reveal_camera_pull() を記録し、決めた時刻で撮る。
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/versus_split_camera_probe.gd [out=フォルダ]

const GAME_WORLD_PATH := "res://scenes/game_world.tscn"
const SHOT_TIMES := [0.70, 1.10, 1.60, 2.10, 2.60, 3.10, 3.40]
const TIMEOUT := 60.0

var _sim := 0.0


func _ready() -> void:
	call_deferred("run")


func _process(delta: float) -> void:
	_sim += delta


func run() -> void:
	var out := "user://versus_split_camera_probe"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.trim_prefix("out=")
	DirAccess.make_dir_recursive_absolute(out)
	var cover := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	cover.fill(Color(0.25, 0.27, 0.32))
	SceneTransition.hold_versus_split(ImageTexture.create_from_image(cover), OnlineStagingTimeline.SEAM_POINTS, SceneTransition.VERSUS_SPLIT_DURATION)
	get_tree().change_scene_to_file(GAME_WORLD_PATH)
	# ゲーム画面が覆いを開きはじめる（カメラの引きが 1 から下がりはじめる）まで待つ
	var deadline := _sim + TIMEOUT
	var start := -1.0
	while _sim < deadline:
		await get_tree().process_frame
		if not SceneTransition.is_transitioning():
			break
		if start < 0.0 and SceneTransition.get_reveal_camera_pull() < 0.999:
			start = _sim
			break
	if start < 0.0:
		print("VERSUS_SPLIT_CAMERA_PROBE fail: reveal did not start (transitioning=%s)" % SceneTransition.is_transitioning())
		get_tree().quit(1)
		return
	# 割れる（BURST）時刻は開く長さの 0.234。そこから少し前を 0 秒として並べる
	var burst := float(SceneTransition.VERSUS_SPLIT_FX.burst) * SceneTransition.VERSUS_SPLIT_DURATION
	var t0 := start - burst
	var next_shot := 0
	var last_log := -1.0
	var eyes: Array[Vector3] = []
	while _sim - t0 < SceneTransition.VERSUS_SPLIT_DURATION + 0.6:
		await get_tree().process_frame
		var t := _sim - t0
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			continue
		var pull := SceneTransition.get_reveal_camera_pull()
		if SceneTransition.is_transitioning():
			eyes.append(cam.global_position)
		if t - last_log >= 0.2:
			last_log = t
			print("VERSUS_SPLIT_CAMERA t=%.2f pull=%.3f fov=%.1f eye=%s" % [t, pull, cam.fov, cam.global_position])
		if next_shot < SHOT_TIMES.size() and t >= float(SHOT_TIMES[next_shot]):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/cam_%04d.png" % [out, int(round(float(SHOT_TIMES[next_shot]) * 1000.0))])
			next_shot += 1
	# 覆いが開いているあいだ、カメラが最後の位置へ近づき続けたか（戻らなかったか）
	var final_eye: Vector3 = get_viewport().get_camera_3d().global_position
	var monotonic := true
	for i in range(1, eyes.size()):
		if eyes[i].distance_to(final_eye) > eyes[i - 1].distance_to(final_eye) + 0.02:
			monotonic = false
	var moved := eyes[0].distance_to(final_eye) if not eyes.is_empty() else 0.0
	print("VERSUS_SPLIT_CAMERA_PROBE done moved=%.2f m approach_monotonic=%s transitioning=%s" % [moved, monotonic, SceneTransition.is_transitioning()])
	get_tree().quit(0 if moved > 1.0 and monotonic else 1)
