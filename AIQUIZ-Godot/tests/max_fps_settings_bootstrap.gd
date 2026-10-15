extends SceneTree

## The settings hall's FPS cap row: GameManager.max_fps persists in the settings file,
## reaches Engine.max_fps, and the row sits under the resolution row.
## Storage goes to user://test_max_fps_settings/ (never the player's own files).
## Results: res://artifacts/max_fps_settings/ (report.json, settings.png).
## Run: Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/max_fps_settings_bootstrap.gd

const OUT := "res://artifacts/max_fps_settings/"
const STORE := "user://test_max_fps_settings"

var checks: Dictionary = {}
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, ok: bool, detail: Variant = "") -> void:
	checks[label] = {"pass": ok, "detail": str(detail)}
	if not ok:
		failures.append("%s: %s" % [label, str(detail)])
		push_error("%s: %s" % [label, str(detail)])


func _read_settings_file(game_manager: Node) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(game_manager.settings_path))
	return parsed if parsed is Dictionary else {}


func run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STORE))
	var gm: Node = root.get_node("GameManager")
	var real_settings: String = gm.settings_path
	var real_cap := Engine.max_fps
	gm.settings_path = STORE + "/settings.json"
	if FileAccess.file_exists(gm.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.settings_path))
	gm._load_user_settings()
	check("default: no cap without a file", int(gm.max_fps) == 0, gm.max_fps)
	gm.set_max_fps(60)
	check("set 60: engine capped", Engine.max_fps == 60, Engine.max_fps)
	check("set 60: saved", int(_read_settings_file(gm).get("max_fps", -1)) == 60, _read_settings_file(gm))
	gm.max_fps = 0
	gm._load_user_settings()
	check("set 60: read back", int(gm.max_fps) == 60, gm.max_fps)
	gm.set_max_fps(75)
	check("unknown value falls back to no cap", int(gm.max_fps) == 0 and Engine.max_fps == 0, [gm.max_fps, Engine.max_fps])

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	gm.set_max_fps(144)
	var panel: Control = load("res://scripts/ui/settings_hall_panel.gd").new()
	root.add_child(panel)
	for _frame in range(10):
		await process_frame
	var vbox := panel.call("display_rows") as VBoxContainer
	var row := vbox.get_node_or_null("MaxFpsBox") as HBoxContainer
	var res_row := vbox.get_node_or_null("ResolutionBox")
	check("row under the resolution row", row != null and res_row != null and row.get_index() == res_row.get_index() + 1)
	if row != null:
		var option := row.get_node("MaxFpsOption") as OptionButton
		var texts: Array[String] = []
		for i in range(option.item_count):
			texts.append(option.get_item_text(i))
		check("choices", texts == ["30 FPS", "60 FPS", "120 FPS", "144 FPS", "240 FPS", "制限なし"], texts)
		check("shows the saved value", option.get_selected_id() == 144, option.get_selected_id())
		var idx := option.get_item_index(30)
		option.select(idx)
		option.item_selected.emit(idx)
		check("choosing 30 caps the engine and saves", Engine.max_fps == 30 and int(gm.max_fps) == 30
			and int(_read_settings_file(gm).get("max_fps", -1)) == 30, [Engine.max_fps, gm.max_fps])
		var column_bottom := (panel.get_node("Column") as Control).get_combined_minimum_size().y \
			+ float((panel.get_script() as GDScript).get_script_constant_map()["PANEL_TOP"])
		check("column fits 720p", column_bottom <= 708.0, column_bottom)
	for _frame in range(3):
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "settings.png"))
	panel.queue_free()
	bg.queue_free()
	gm.settings_path = real_settings
	gm._load_user_settings()
	Engine.max_fps = real_cap

	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("MAX_FPS_SETTINGS " + JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
