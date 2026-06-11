from pathlib import Path
import re

p = Path(r"c:/AIQUIZ/AIQUIZ-Godot/scripts/ui/menu_wall_background_preview.gd")
text = p.read_text(encoding="utf-8")
text = text.replace("_update_door_learning_approach(_p1_ai, true)", "_update_door_learning_approach(bundle, is_p1)")
text = text.replace("\n\t_update_jump_trigger_ttl(dt, bundle, is_p1)\n\n\tmatch bundle.ai_state:", "\n\tmatch bundle.ai_state:")
repls = [
    ("_actor_x(is_p1) = ", "_set_actor_x(is_p1, "),
    ("_actor_y(is_p1) = ", "_set_actor_y(is_p1, "),
    ("_actor_vel_y(is_p1) = ", "_set_actor_vel_y(is_p1, "),
    ("_actor_local_z(is_p1) = ", "_set_actor_local_z(is_p1, "),
    ("_actor_emote(is_p1) = ", "_set_actor_emote(is_p1, "),
    ("_actor_jump_trigger(is_p1) = ", "_set_actor_jump_trigger(is_p1, "),
    ("_actor_moving_back(is_p1) = ", "_set_actor_moving_back(is_p1, "),
    ("_actor_game_over_timer(is_p1) += dt", "_add_actor_game_over_timer(is_p1, dt)"),
]
for a, b in repls:
    text = text.replace(a, b)
# function signatures
sig_fixes = [
    ("func _update_jump_trigger_ttl(dt: float) -> void:", "func _update_jump_trigger_ttl(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _roll_next_action(bundle, is_p1) -> void:", "func _roll_next_action(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _start_ai_lane_shift() -> void:", "func _start_ai_lane_shift(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _start_ai_dash_move(is_acro: bool = false) -> void:", "func _start_ai_dash_move(is_acro: bool, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _update_lane_shift(dt: float) -> void:", "func _update_lane_shift(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _update_depth_shift(dt: float) -> void:", "func _update_depth_shift(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _start_ai_jump() -> bool:", "func _start_ai_jump(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:"),
    ("func _update_ground_movement(dt: float) -> void:", "func _update_ground_movement(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _start_ai_emote() -> bool:", "func _start_ai_emote(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:"),
    ("func _update_emote_timer(bundle, is_p1) -> void:", "func _update_emote_timer(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _stop_ai_emote_if_needed(bundle, is_p1) -> void:", "func _stop_ai_emote_if_needed(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _start_ai_acrobatics() -> bool:", "func _start_ai_acrobatics(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:"),
    ("func _update_acrobatic_action(dt: float) -> void:", "func _update_acrobatic_action(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
    ("func _is_past_belt_edge(is_p1) -> bool:", "func _is_past_belt_edge(is_p1: bool) -> bool:"),
    ("func _allows_below_floor(bundle, is_p1) -> bool:", "func _allows_below_floor(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:"),
    ("func _enforce_floor_support(bundle, is_p1) -> void:", "func _enforce_floor_support(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:"),
]
for a, b in sig_fixes:
    text = text.replace(a, b)
text = text.replace("var skill := _get_door_learning_skill()", "var skill := _get_door_learning_skill(bundle)")
text = text.replace("_get_door_learning_skill()\n", "_get_door_learning_skill(bundle)\n")
text = text.replace("_pick_ai_dash_target_x()", "_pick_ai_dash_target_x(bundle)")
text = text.replace("_is_learning_commit_active()", "_is_learning_commit_active(bundle)")
text = text.replace("_start_ai_lane_shift()", "_start_ai_lane_shift(bundle, is_p1)")
text = text.replace("if not _start_ai_jump():", "if not _start_ai_jump(bundle, is_p1):")
text = text.replace("if not _start_ai_emote():", "if not _start_ai_emote(bundle, is_p1):")
text = text.replace("if not _start_ai_acrobatics():", "if not _start_ai_acrobatics(bundle, is_p1):")
text = text.replace("if not _start_ai_collision_accident():", "if not _start_ai_collision_accident(bundle, is_p1):")
text = text.replace("if not _start_ai_magma_accident():", "if not _start_ai_magma_accident(bundle, is_p1):")
text = text.replace("func _start_ai_collision_accident() -> bool:", "func _start_ai_collision_accident(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:")
text = text.replace("func _start_ai_magma_accident() -> bool:", "func _start_ai_magma_accident(bundle: MenuPreviewActorAIState, is_p1: bool) -> bool:")
text = text.replace("func _update_magma_fall(dt: float) -> void:", "func _update_magma_fall(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:")
text = text.replace("func _update_knockback_motion(dt: float) -> void:", "func _update_knockback_motion(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:")
text = text.replace("func _start_respawn() -> void:", "func _start_respawn(bundle: MenuPreviewActorAIState, is_p1: bool) -> void:")
text = text.replace("func _update_respawn_drop(dt: float) -> void:", "func _update_respawn_drop(dt: float, bundle: MenuPreviewActorAIState, is_p1: bool) -> void:")
# knockback sx uses player x
text = text.replace("signf(_preview_gs.player_x - PREVIEW_PLAYER_X)", "signf(_actor_x(is_p1) - (PREVIEW_PLAYER_X if is_p1 else PREVIEW_PLAYER2_X))")
p.write_text(text, encoding="utf-8")
print("fixed")
