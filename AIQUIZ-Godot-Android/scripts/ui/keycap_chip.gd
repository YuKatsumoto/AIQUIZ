class_name KeycapChip
extends TextureRect

## Kenney Input Prompts 1.5A のキーボードアイコンを表示する。
## https://kenney.nl/assets/input-prompts

enum SizeClass { TINY, SMALL, NORMAL, LARGE }

const DEFAULT_ACCENT := Color(0.22, 0.26, 0.36, 1.0)
const DONE_TINT := Color(0.72, 1.0, 0.82, 1.0)
const TEX_DIR := "res://assets/ui/kenney_input_prompts/keyboard/"

var _token: String = ""
var _size_class: SizeClass = SizeClass.SMALL
var _done: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	clip_contents = true


static func create(
	token: String,
	_accent: Color = DEFAULT_ACCENT,
	size_class: SizeClass = SizeClass.SMALL,
	done: bool = false
) -> KeycapChip:
	var chip := KeycapChip.new()
	chip.configure(token, _accent, size_class, done)
	return chip


func configure(
	token: String,
	_accent: Color = DEFAULT_ACCENT,
	size_class: SizeClass = SizeClass.SMALL,
	done: bool = false
) -> void:
	_token = token
	_size_class = size_class
	_done = done
	_apply_look()


func _apply_look() -> void:
	var edge := _edge_size()
	custom_minimum_size = Vector2(edge, edge)
	size = Vector2(edge, edge)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var path := "%s%s.png" % [TEX_DIR, KeyTokens.texture_stem(_token)]
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	else:
		texture = load("%skeyboard_any.png" % TEX_DIR) as Texture2D
	modulate = DONE_TINT if _done else Color.WHITE


func _edge_size() -> float:
	match _size_class:
		SizeClass.TINY:
			return 22.0
		SizeClass.SMALL:
			return 30.0
		SizeClass.LARGE:
			return 52.0
		_:
			return 38.0
