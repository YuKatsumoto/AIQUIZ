extends SceneTree

## PV のメタ問題の候補が、壁の看板でどう折り返されるかを確かめる（quiz_wall.gd と同じ整形・フォント・折り返し）。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/pv_capture/measure_question.gd -- "候補1" "候補2" ...
## quiz_wall.gd は autoload を参照するので、autoload が揃ってから読む。

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var wall_script: GDScript = load("res://scripts/world/quiz_wall.gd")
	var font: Font = wall_script.call("_wall_label_font")
	var constants := wall_script.get_script_constant_map()
	var base_width: float = constants["QUESTION_LABEL_BASE_WIDTH"]
	var step: float = constants["QUESTION_LABEL_WIDTH_STEP"]
	var max_width: float = constants["QUESTION_LABEL_MAX_WIDTH"]
	var max_lines: int = constants["QUESTION_LABEL_MAX_LINES"]
	var font_size: int = constants["QUESTION_LABEL_FONT_SIZE"]
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	for raw: String in OS.get_cmdline_user_args():
		var text := FractionFormatter.format_question(raw)
		var width := base_width
		while width < max_width and _lines(text, font, font_size, width, flags).size() > max_lines:
			width = minf(width + step, max_width)
		print("[measure] %s -> width %d | %s" % [raw, int(width), " / ".join(_lines(text, font, font_size, width, flags))])
	quit()


func _lines(text: String, font: Font, font_size: int, width: float, flags: int) -> PackedStringArray:
	var tp := TextParagraph.new()
	tp.width = width
	tp.break_flags = flags
	tp.add_string(text, font, font_size)
	var result := PackedStringArray()
	for i in range(tp.get_line_count()):
		var r := tp.get_line_range(i)
		result.append(text.substr(r.x, r.y - r.x))
	return result
