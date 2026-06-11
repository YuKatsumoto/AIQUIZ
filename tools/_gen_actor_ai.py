from pathlib import Path

p = Path(r"c:/AIQUIZ/AIQUIZ-Godot/scripts/ui/menu_wall_background_preview.gd")
text = p.read_text(encoding="utf-8")
start = text.index("func _update_preview_actor_ai(dt: float) -> void:")
end = text.index("func _separate_blocking_wall_from_player() -> void:")
chunk = text[start:end]
out = chunk.replace(
    "func _update_preview_actor_ai(dt: float) -> void:",
    "func _update_actor_ai(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:",
)
out = out.replace("\n\t_ai_time += dt\n", "\n")
out = out.replace("_p1_ai.", "bundle.")
out = out.replace("_update_door_learning_approach(bundle, is_p1)", "_update_door_learning_approach(bundle, is_p1)")
repls = [
    ("_preview_gs.p1_alive", "_actor_alive(is_p1)"),
    ("_preview_gs.p1_emote", "_actor_emote(is_p1)"),
    ("_preview_gs.p1_jump_trigger", "_actor_jump_trigger(is_p1)"),
    ("_preview_gs.p1_moving_back", "_actor_moving_back(is_p1)"),
    ("_preview_gs.player_x", "_actor_x(is_p1)"),
    ("_preview_gs.player_y", "_actor_y(is_p1)"),
    ("_preview_gs.player_vel_y", "_actor_vel_y(is_p1)"),
    ("_preview_gs.player_local_z", "_actor_local_z(is_p1)"),
    ("_preview_gs.game_over_timer", "_actor_game_over_timer(is_p1)"),
    ("_update_jump_trigger_ttl(dt)", "_update_jump_trigger_ttl(dt, bundle, is_p1)"),
    ("_update_lane_shift(dt)", "_update_lane_shift(dt, bundle, is_p1)"),
    ("_update_depth_shift(dt)", "_update_depth_shift(dt, bundle, is_p1)"),
    ("_update_ground_movement(dt)", "_update_ground_movement(dt, bundle, is_p1)"),
    ("_start_ai_dash_move(false)", "_start_ai_dash_move(false, bundle, is_p1)"),
    ("_start_ai_dash_move(true)", "_start_ai_dash_move(true, bundle, is_p1)"),
    ("_roll_next_action()", "_roll_next_action(bundle, is_p1)"),
    ("_update_emote_timer()", "_update_emote_timer(bundle, is_p1)"),
    ("_stop_ai_emote_if_needed()", "_stop_ai_emote_if_needed(bundle, is_p1)"),
    ("_update_acrobatic_action(dt)", "_update_acrobatic_action(dt, bundle, is_p1)"),
    ("_update_knockback_motion(dt)", "_update_knockback_motion(dt, bundle, is_p1)"),
    ("_update_magma_fall(dt)", "_update_magma_fall(dt, bundle, is_p1)"),
    ("_start_respawn()", "_start_respawn(bundle, is_p1)"),
    ("_update_respawn_drop(dt)", "_update_respawn_drop(dt, bundle, is_p1)"),
    ("_enforce_floor_support()", "_enforce_floor_support(bundle, is_p1)"),
    ("_allows_below_floor()", "_allows_below_floor(bundle, is_p1)"),
    ("_is_past_belt_edge()", "_is_past_belt_edge(is_p1)"),
]
for a, b in repls:
    out = out.replace(a, b)
out = out.replace('_trigger_preview_death("magma", bundle, true)', '_trigger_preview_death("magma", bundle, is_p1)')
out = out.replace('_trigger_preview_death("crash", bundle, true)', '_trigger_preview_death("crash", bundle, is_p1)')
wrapper = """func _update_preview_actor_ai(dt: float) -> void:
\tif not _preview_gs:
\t\treturn
\t_ai_time += dt
\t_update_jump_trigger_ttl(dt, _p1_ai, true)
\t_update_actor_ai(dt, _p1_ai, true)
\t_enforce_floor_support(_p1_ai, true)


func _update_preview_actor2_ai(dt: float) -> void:
\tif not _preview_gs or not _is_local_2p_active():
\t\treturn
\t_update_jump_trigger_ttl(dt, _p2_ai, false)
\t_update_actor_ai(dt, _p2_ai, false)
\t_enforce_floor_support(_p2_ai, false)


"""
new_text = text[:start] + wrapper + out + text[end:]
p.write_text(new_text, encoding="utf-8")
print("ok", len(out))
