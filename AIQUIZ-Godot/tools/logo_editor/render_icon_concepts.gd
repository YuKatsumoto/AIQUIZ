extends SceneTree

## アイコン案の SVG（tools/logo_editor/build_icon_concepts.py が作る）を PNG にする。ロゴの PNG と同じく Godot の SVG 読み込みで描く。
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/logo_editor/render_icon_concepts.gd

const DIR := "res://assets/branding/icon_concepts/"


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	for file_name: String in DirAccess.get_files_at(dir):
		if not file_name.ends_with(".svg"):
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(file_name))
		var image := Image.new()
		var err := image.load_svg_from_string(text, 1.0)
		if err != OK:
			push_error("SVG を読めません: %s (%s)" % [file_name, error_string(err)])
			continue
		var out := dir.path_join(file_name.get_basename() + ".png")
		image.save_png(out)
		print("ICON ", out, " ", image.get_size())
	quit()
