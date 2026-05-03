		explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(explain_label)
	
	# --- Rating buttons ---
	var rate_container := HBoxContainer.new()
	rate_container.alignment = BoxContainer.ALIGNMENT_END
	rate_container.add_theme_constant_override("separation", 12)
	vbox.add_child(rate_container)
	
	var entry: Dictionary = game_state.quiz_history[index]
	var player_rated: bool = entry.get("player_rated", false)
	if not player_rated:
		# Show rating buttons, optionally mentioning AI's rating if any
		var rate_label := Label.new()
		if rated == "good":
			rate_label.text = "AI隧穂ｾ｡:濶ｯ縺・| 縺ゅ↑縺溘・隧穂ｾ｡:"
		elif rated == "bad":
			rate_label.text = "AI隧穂ｾ｡:謔ｪ縺・| 縺ゅ↑縺溘・隧穂ｾ｡:"
		else:
			rate_label.text = "縺薙・蝠城｡後・隧穂ｾ｡:"
		rate_label.add_theme_font_size_override("font_size", 15)
		rate_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
		rate_container.add_child(rate_label)
		
		var good_btn := Button.new()
		good_btn.text = "笳ｯ 濶ｯ縺・
		good_btn.custom_minimum_size = Vector2(100, 36)
		good_btn.add_theme_font_size_override("font_size", 16)
		good_btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		rate_container.add_child(good_btn)
		
		var bad_btn := Button.new()
		bad_btn.text = "ﾃ・謔ｪ縺・
		bad_btn.custom_minimum_size = Vector2(100, 36)
		bad_btn.add_theme_font_size_override("font_size", 16)
		bad_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		rate_container.add_child(bad_btn)
		
		# Capture index for closure
		var idx := index
		good_btn.pressed.connect(func():
			game_state.rate_quiz_at(idx, true)
			_replace_rate_buttons(rate_container, true)
		)
		bad_btn.pressed.connect(func():
			game_state.rate_quiz_at(idx, false)
			_replace_rate_buttons(rate_container, false)
		)
	else:
		# Already rated by player manually 窶・show feedback
		var feedback := Label.new()
		if rated == "good":
			feedback.text = "笳ｯ 濶ｯ縺・撫鬘後→縺励※隧穂ｾ｡縺励∪縺励◆"
			feedback.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		else:
			feedback.text = "ﾃ・謔ｪ縺・撫鬘後→縺励※隧穂ｾ｡縺励∪縺励◆"
			feedback.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		feedback.add_theme_font_size_override("font_size", 15)
		rate_container.add_child(feedback)
	
	return card

func _replace_rate_buttons(container: HBoxContainer, good: bool) -> void:
	# Remove all children
	for child in container.get_children():
		child.queue_free()
	
	# Add feedback label
	var feedback := Label.new()
	if good:
		feedback.text = "笳ｯ 濶ｯ縺・撫鬘後→縺励※隧穂ｾ｡縺励∪縺励◆"
		feedback.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	else:
		feedback.text = "ﾃ・謔ｪ縺・撫鬘後→縺励※隧穂ｾ｡縺励∪縺励◆"
		feedback.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	feedback.add_theme_font_size_override("font_size", 15)
	container.add_child(feedback)
