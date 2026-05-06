import sys

file_path = r'c:\AIQUIZ\AIQUIZ-Godot\scripts\ui\main_menu.gd'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

target = '''		var p_text: String
		if game_state.num_players == 1:
			p_text = "👤 1人プレイ"
		elif game_state.num_players == 2:
			if game_state.mode == Constants.MODE_COOP:
				p_text = "🤝 2人協力"
			else:
				p_text = "👥 2人プレイ"
		else:
			p_text = "🌐 オンライン対戦"
		players_btn.text = p_text

		var llm_text: String = "🌐 ONLINE (AI生成)" if QuizManager.provider.llm_mode == "ONLINE" else "📦 OFFLINE (内蔵問題)"
		llm_toggle_btn.text = llm_text

		# Show skin & emote button for all modes (emotes usable in 1P too)
		if hat_select_btn:
			hat_select_btn.visible = true

		# Update wall speed button label
		if wall_speed_btn:
			if game_state.tuning.wall_speed_override > 0:
				wall_speed_btn.text = "⚡ 壁速度: %.1f（手動）" % game_state.tuning.wall_speed_override
			else:
				wall_speed_btn.text = "⚡ 壁速度設定（自動）"'''

replacement = '''		var p_text: String
		var p_icon: Texture2D
		if game_state.num_players == 1:
			p_text = " 1人プレイ"
			p_icon = TEX_1P
		elif game_state.num_players == 2:
			if game_state.mode == Constants.MODE_COOP:
				p_text = " 2人協力"
			else:
				p_text = " 2人プレイ"
			p_icon = TEX_2P
		else:
			p_text = " オンライン対戦"
			p_icon = TEX_ONLINE
		players_btn.icon = p_icon
		players_btn.text = p_text
		players_btn.expand_icon = true

		var llm_text: String = " ONLINE (AI生成)" if QuizManager.provider.llm_mode == "ONLINE" else " OFFLINE (内蔵問題)"
		llm_toggle_btn.icon = TEX_ONLINE
		llm_toggle_btn.text = llm_text
		llm_toggle_btn.expand_icon = true

		# Show skin & emote button for all modes (emotes usable in 1P too)
		if hat_select_btn:
			hat_select_btn.visible = true
			hat_select_btn.icon = TEX_SKIN
			hat_select_btn.text = " スキン設定"
			hat_select_btn.expand_icon = true
			
		if get_node_or_null("%EmoteSelectBtn"):
			var btn = get_node("%EmoteSelectBtn")
			btn.icon = TEX_EMOTE
			btn.text = " エモート設定"
			btn.expand_icon = true

		# Update wall speed button label
		if wall_speed_btn:
			wall_speed_btn.icon = TEX_SPEED
			if game_state.tuning.wall_speed_override > 0:
				wall_speed_btn.text = " 壁速度: %.1f（手動）" % game_state.tuning.wall_speed_override
			else:
				wall_speed_btn.text = " 壁速度設定（自動）"
			wall_speed_btn.expand_icon = true'''

if target.replace('\n', '\r\n') in content:
    content = content.replace(target.replace('\n', '\r\n'), replacement.replace('\n', '\r\n'))
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Replaced successfully (CRLF)')
elif target in content:
    content = content.replace(target, replacement)
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Replaced successfully (LF)')
else:
    print('Target not found')
