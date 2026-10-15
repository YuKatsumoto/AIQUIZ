extends Node

## 中央の線が開く遷移（仕様書 S10 v1.6）だけを見る。カットインの静止画で覆い、読み込みが終わった合図（reveal_current）から
## 稲妻 → 溜め → 割れて火花を散らし、震えながらゆっくり開くまでを、決めた時刻で撮る。
##   Godot --path . --resolution 1280x720 --fixed-fps 60 --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/versus_split_probe.gd
##     hold=画像（カットインの画面） under=画像（下に見える次の画面） out=フォルダ [duration=秒] [guest=1]

const TIMES := [0.0, 0.25, 0.50, 0.70, 0.76, 0.85, 1.00, 1.30, 1.70, 2.10, 2.50, 2.80, 3.10]

var _sim := 0.0


func _ready() -> void:
	call_deferred("run")


func _process(delta: float) -> void:
	_sim += delta


func run() -> void:
	var hold := ""
	var under := ""
	var out := "user://versus_split_probe"
	var duration := SceneTransition.VERSUS_SPLIT_DURATION
	var guest := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("hold="):
			hold = arg.trim_prefix("hold=")
		elif arg.begins_with("under="):
			under = arg.trim_prefix("under=")
		elif arg.begins_with("out="):
			out = arg.trim_prefix("out=")
		elif arg.begins_with("duration="):
			duration = float(arg.trim_prefix("duration="))
		elif arg == "guest=1":
			guest = true
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var back := TextureRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.texture = _load(under)
	layer.add_child(back)
	await get_tree().process_frame
	var colors := [PlayerController.P2_BODY, PlayerController.P1_BODY] if guest else [PlayerController.P1_BODY, PlayerController.P2_BODY]
	SceneTransition.hold_versus_split(_load(hold), OnlineStagingTimeline.SEAM_POINTS, duration, colors)
	await _frames(5)
	DirAccess.make_dir_recursive_absolute(out)
	var start := _sim
	SceneTransition.reveal_current()
	for t: float in TIMES:
		while _sim - start < t - 0.0001:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/split_%04d.png" % [out, int(round(t * 1000.0))])
	await _frames(10)
	print("VERSUS_SPLIT_PROBE done transitioning=%s" % SceneTransition.is_transitioning())
	get_tree().quit(0)


func _load(path: String) -> Texture2D:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		var fallback := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
		fallback.fill(Color(0.3, 0.3, 0.35))
		return ImageTexture.create_from_image(fallback)
	return ImageTexture.create_from_image(image)


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame
