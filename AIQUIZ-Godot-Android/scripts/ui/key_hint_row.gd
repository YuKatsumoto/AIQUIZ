class_name KeyHintRow
extends HBoxContainer

## 文章とキーキャップを横並びに組む行。操作ヒントの文字キーを置き換える。
## `text` はデバッグ／既存プローブ互換のスナップショット。

var text: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_CENTER


func reset() -> void:
	text = ""
	for child: Node in get_children():
		remove_child(child)
		child.free()


func add_spec(
	spec: String,
	accent: Color = KeycapChip.DEFAULT_ACCENT,
	size_class: KeycapChip.SizeClass = KeycapChip.SizeClass.SMALL,
	done: bool = false
) -> void:
	var tokens := KeyTokens.split_spec(spec)
	if tokens.is_empty():
		return
	var use_slash := spec.find("/") >= 0 and not KeyTokens.uses_cluster(spec)
	for i: int in range(tokens.size()):
		if use_slash and i > 0:
			add_text("/", Color(0.62, 0.68, 0.78, 1.0), _sep_font_size(size_class))
		add_child(KeycapChip.create(tokens[i], accent, size_class, done))
	_append_snapshot(spec)


func add_any_key(size_class: KeycapChip.SizeClass = KeycapChip.SizeClass.SMALL) -> void:
	add_child(KeycapChip.create("any", KeycapChip.DEFAULT_ACCENT, size_class, false))
	_append_snapshot("[Any]")


func add_text(
	label_text: String,
	color: Color = Color(0.88, 0.92, 1.0, 1.0),
	font_size: int = 13,
	outline: bool = false
) -> Label:
	var label := Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline:
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
		label.add_theme_constant_override("outline_size", 3)
	add_child(label)
	_append_snapshot(label_text)
	return label


func add_player_tag(tag: String, accent: Color, font_size: int = 13) -> void:
	var label := add_text(tag, accent, font_size, true)
	label.custom_minimum_size.x = 28.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _append_snapshot(chunk: String) -> void:
	text += chunk


func _sep_font_size(size_class: KeycapChip.SizeClass) -> int:
	match size_class:
		KeycapChip.SizeClass.TINY:
			return 10
		KeycapChip.SizeClass.LARGE:
			return 16
		KeycapChip.SizeClass.NORMAL:
			return 14
		_:
			return 12
