extends SceneTree

## タイトルの登場演出（TitleLogoIntro）だけを窓で再生し、決まった秒の画面を artifacts/title_logo_intro/ に保存する。
## メニューの 3D は作らない（演出の絵と時間の確認用）。TitleLogo は 3 倍に拡大して描く。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/title_logo_intro_capture.gd -- 0.5,1.0,2.0

const OUT := "res://artifacts/title_logo_intro"
const ZOOM := 3.0

var _intro: TitleLogoIntro
var _times: Array[float] = []
var _index := 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		for part: String in arg.split(","):
			if part.is_valid_float():
				_times.append(float(part))
	DisplayServer.window_set_size(Vector2i(1100, 520))
	root.size = Vector2i(1100, 520)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.36, 0.52)
	bg.size = Vector2(1100, 520)
	root.add_child(bg)
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/ui/branding/aiquiz_logo.png"))
	var logo_size := Vector2(56.0 * image.get_width() / image.get_height(), 56.0)
	var holder := Control.new()
	holder.position = Vector2(150, 250)
	holder.scale = Vector2.ONE * ZOOM
	holder.size = logo_size
	root.add_child(holder)
	_intro = TitleLogoIntro.new()
	holder.add_child(_intro)
	if not _intro.setup(logo_size, [], null):
		push_error("intro setup failed")
		quit(1)
		return
	if _times.is_empty():
		var t := 0.0
		while t <= _intro.duration() + 0.001:
			_times.append(t)
			t += 0.25
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for f: String in DirAccess.get_files_at(ProjectSettings.globalize_path(OUT)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT).path_join(f))
	_intro.start(TitleLogoIntro.DEFAULT_BAR_RECT)
	_intro.set_process(false)
	_capture.call_deferred()


func _capture() -> void:
	for t: float in _times:
		_intro._t = t
		_intro._apply_frame()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.save_png(ProjectSettings.globalize_path(OUT).path_join("t%05d.png" % int(round(t * 1000.0))))
	print("TITLE_LOGO_CAPTURE ", _times.size(), " frames")
	quit()
