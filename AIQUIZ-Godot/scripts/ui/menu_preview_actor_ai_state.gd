class_name MenuPreviewActorAIState
extends RefCounted


var ai_state: int = 0
var next_action_t: float = 0.0
var emote_end_t: float = 0.0
var dead_end_t: float = 0.0
var state_end_t: float = 0.0
var target_x: float = -3.5
var lane_shift_speed: float = 2.2
var lane_shift_active: bool = false
var target_local_z: float = 0.0
var depth_shift_speed: float = 2.0
var depth_shift_active: bool = false
var jump_trigger_ttl: float = 0.0
var is_emoting: bool = false
var crash_wall: Node3D = null
var blocking_wall: Node3D = null
var accident_cooldown_t: float = 0.0
var last_emote: int = 0
var next_acro_jump_t: float = 0.0
var acro_seed: float = 0.0
var knockback_end_t: float = 0.0
var knockback_vel_x: float = 0.0
var knockback_vel_z: float = 0.0
var door_learner: RefCounted
var learn_approach_wall: Node3D = null
var learn_intended_action: int = -1
var learn_target_x: float = -3.5
var learn_episode_reported: bool = false
var available_emotes: Array[int] = []
var taunt_target_x: float = 0.0
var taunt_target_z: float = 0.0
## 潜伏型事故: 0=なし, 1=壁, 2=マグマ（AI_STATE は NORMAL のまま）
var pending_accident: int = 0
var pending_accident_wall: Node3D = null
