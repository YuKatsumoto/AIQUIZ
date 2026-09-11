extends CanvasLayer

var game_state: Object

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed() and not event.is_echo():
		if game_state and game_state.game_state in ["playing", "goal_race"]: # Using raw strings to avoid Constants dependency if not needed, but wait
			toggle_pause()

func toggle_pause() -> void:
	var new_paused = !get_tree().paused
	get_tree().paused = new_paused
	visible = new_paused
	if new_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if game_state.num_players == 1:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
