extends SceneTree

## PV のロゴ（ゲームのタイトルの登場演出 TitleLogoIntro そのもの）を、透明な背景の連番 PNG に書き出す。
## After Effects で撮影の上に重ねる（S03・S23・S24）。ゲームと同じ形・色・ベルト・縁取り・超解像で描く。
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --script res://tests/pv_capture/pv_logo_capture.gd -- tag=s03 zoom=4 top=120 t0=0.35 speed=1.92 frames=225
##
##   tag=<名前>        出力先 artifacts/pv_capture/logo_<tag>/（l_0001.png〜 と report.json）
##   zoom=<倍>         ロゴの大きさ（論理ピクセル × zoom = 画面のピクセル。メニューのロゴは高さ 56 論理ピクセル）
##   cx=<px>           ロゴの中心の x（既定は画面の中央）
##   top=<px>          文字の上の端の y
##   t0=<秒>           1 フレーム目の演出の時刻（DEPLOY は 0.35）
##   speed=<倍>        演出の速さ（PV の 1 フレーム = 1/60 秒 × speed だけ演出が進む）
##   frames=<N>        書き出すフレーム数（演出の終わりを過ぎたら最後の姿のまま）
##   only=<f>,<f>      そのフレームだけ書き出す（構図の確認用）
##   bg=<r,g,b>        透明にせずこの色で塗る（確認用）
## 透明な所の色は、ゲームの画面と同じく不透明度を掛けた色（AE では「合成チャンネル：プリマルチプライ - 黒」で読む）。

const OUT_ROOT := "res://artifacts/pv_capture"
const FPS := 60.0
const LOGO_HEIGHT := 56.0

var _intro: TitleLogoIntro
var _tag := "logo"
var _zoom := 4.0
var _cx := -1.0
var _top := 120.0
var _t0 := 0.35
var _speed := 1.0
var _frames := 1
var _only: Array[int] = []
var _bg := Color(0, 0, 0, 0)
var _out := ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"tag": _tag = kv[1]
			"zoom": _zoom = float(kv[1])
			"cx": _cx = float(kv[1])
			"top": _top = float(kv[1])
			"t0": _t0 = float(kv[1])
			"speed": _speed = float(kv[1])
			"frames": _frames = maxi(1, int(kv[1]))
			"only":
				for f: String in kv[1].split(",", false):
					_only.append(int(f))
			"bg":
				var c := kv[1].split(",")
				if c.size() >= 3:
					_bg = Color(float(c[0]), float(c[1]), float(c[2]), 1.0)
	_boot.call_deferred()


func _boot() -> void:
	var size := DisplayServer.window_get_size()
	# 画面の 1 単位 = 1 ピクセルにする（プロジェクトの拡大の設定を使わない）
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.transparent_bg = _bg.a < 1.0
	if _bg.a >= 1.0:
		var rect := ColorRect.new()
		rect.color = _bg
		rect.size = Vector2(size)
		root.add_child(rect)
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/ui/branding/testopia_logo.png"))
	var logo_size := Vector2(LOGO_HEIGHT * image.get_width() / image.get_height(), LOGO_HEIGHT)
	var holder := Control.new()
	holder.size = logo_size * _zoom
	var cx := _cx if _cx >= 0.0 else size.x * 0.5
	holder.position = Vector2(cx - holder.size.x * 0.5, _top)
	root.add_child(holder)
	_intro = TitleLogoIntro.new()
	holder.add_child(_intro)
	if not _intro.setup(logo_size, _zoom):
		push_error("TitleLogoIntro.setup failed")
		quit(1)
		return
	_out = ProjectSettings.globalize_path(OUT_ROOT).path_join("logo_" + _tag)
	DirAccess.make_dir_recursive_absolute(_out)
	for f: String in DirAccess.get_files_at(_out):
		if f.begins_with("l_") and f.ends_with(".png"):
			DirAccess.remove_absolute(_out.path_join(f))
	_intro.start()
	_intro.set_process(false)
	# 超解像の SubViewport の大きさは木に入った次のフレームで決まるので、1 フレーム待つ
	await process_frame
	await RenderingServer.frame_post_draw
	var times: Array = []
	for i: int in _frames:
		var n := i + 1
		var t := minf(_t0 + float(i) / FPS * _speed, _intro.duration())
		times.append(t)
		if not _only.is_empty() and not _only.has(n):
			continue
		_intro._t = t
		_intro._apply_frame()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.save_png(_out.path_join("l_%04d.png" % n))
	var markers := {}
	for m: String in ["DEPLOY", "ALL SEATED", "SHAKE", "BURST", "END"]:
		var at := _intro.marker_time(m)
		markers[m] = {"time": at, "pv_frame": 1.0 + (at - _t0) / _speed * FPS}
	var report := {
		"tag": _tag, "size": [size.x, size.y], "zoom": _zoom, "holder_rect": [holder.position.x, holder.position.y, holder.size.x, holder.size.y],
		"belt_rect_logical": [_intro._belt_rect.position.x, _intro._belt_rect.position.y, _intro._belt_rect.size.x, _intro._belt_rect.size.y],
		"t0": _t0, "speed": _speed, "frames": _frames, "duration": _intro.duration(), "markers": markers,
		"transparent": _bg.a < 1.0,
	}
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("PV_LOGO_CAPTURE ", _out, " ", _frames, " frames")
	quit()
