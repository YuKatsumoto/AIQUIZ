extends SceneTree

## TESTOPIA のロゴの SVG（build_testopia_logo.mjs が作る）を、白・透過の PNG にする。
##   assets/branding/logo/testopia_logo.png  元の大きさ（字の外接矩形で切り抜き、横 MASTER_WIDTH 前後）
##   assets/ui/branding/testopia_logo.png    メニューのタイトルの予備（演出が作れないときの 2D のロゴ、横 UI_WIDTH）
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/logo_editor/render_logo_png.gd

const SVG := "res://assets/branding/logo/testopia_logo.svg"
const MASTER := "res://assets/branding/logo/testopia_logo.png"
const UI := "res://assets/ui/branding/testopia_logo.png"
const SVG_SCALE := 3.5
const UI_WIDTH := 1200


func _init() -> void:
	var image := Image.new()
	var err := image.load_svg_from_string(FileAccess.get_file_as_string(SVG), SVG_SCALE)
	if err != OK:
		push_error("cannot rasterize %s (%s)" % [SVG, error_string(err)])
		quit(1)
		return
	image = image.get_region(image.get_used_rect())
	image.save_png(ProjectSettings.globalize_path(MASTER))
	var ui := image.duplicate() as Image
	ui.resize(UI_WIDTH, roundi(ui.get_height() * float(UI_WIDTH) / ui.get_width()), Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UI).get_base_dir())
	ui.save_png(ProjectSettings.globalize_path(UI))
	print("wrote ", MASTER, " ", image.get_size(), " / ", UI, " ", ui.get_size())
	quit()
