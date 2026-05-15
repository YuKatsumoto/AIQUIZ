@tool class_name PsxConversionDialogOption extends HBoxContainer

@export var label_text: String:
	set(value):
		label_text = value
		if not is_node_ready(): return

		$label.text = value

func _ready() -> void:
	$label.text = label_text

func get_option_value() -> Variant:
	var value_holder: Control = find_child("value")
	if value_holder is OptionButton: return value_holder.selected
	if value_holder is BaseButton: return value_holder.button_pressed
	return null
