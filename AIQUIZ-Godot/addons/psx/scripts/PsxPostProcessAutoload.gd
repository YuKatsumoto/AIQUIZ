@tool extends CanvasLayer

const POST_PROCESS_LAYER: int = 128
const POST_PROCESS_MATERIAL: ShaderMaterial = preload("res://addons/psx/materials/psx_post_process.tres")


func _init() -> void:
	layer = POST_PROCESS_LAYER if not Engine.is_editor_hint() else -128

	var color_rect := ColorRect.new()
	color_rect.color = Color.BLACK
	color_rect.material = POST_PROCESS_MATERIAL
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.focus_mode = Control.FOCUS_NONE
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	add_child(color_rect)
