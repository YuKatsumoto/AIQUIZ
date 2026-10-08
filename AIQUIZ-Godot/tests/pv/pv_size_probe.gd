extends SceneTree

## Prints the window, root viewport and screen sizes Movie Maker sees, then quits.
## ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/pv/pv_size_probe.gd --resolution 1920x1080 --write-movie <dir>/f.png

var _frame := 0


func _initialize() -> void:
	_report("init")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_report("frame3")
	return _frame >= 6


func _report(tag: String) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var texture_size := Vector2i.ZERO
	if tag != "init":
		texture_size = root.get_texture().get_image().get_size()
	print("PV_SIZE_PROBE ", JSON.stringify({
		"texture": texture_size,
		"tag": tag,
		"window": DisplayServer.window_get_size(),
		"root": root.size,
		"root_visible_rect": root.get_visible_rect().size,
		"screen": DisplayServer.screen_get_size(screen),
		"usable": DisplayServer.screen_get_usable_rect(screen).size,
		"scale": DisplayServer.screen_get_scale(screen),
		"cmdline": OS.get_cmdline_args(),
	}))
