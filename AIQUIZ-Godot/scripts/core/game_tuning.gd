extends RefCounted
class_name GameTuning

## ゲームのチューニングパラメータ (Python版 GameTuning 相当)

var player_speed: float = 7.6
var min_x: float = -6.5
var max_x: float = 6.5
var wall_start_z: float = 22.0
# 壁速度はAI予測解答時間から自動計算。クランプ定数のみ保持。
var wall_speed_min: float = 2.0
var wall_speed_max: float = 7.0
var wall_speed_override: float = 0.0  # 0 = 自動モード, >0 = 手動固定速度
var wall_spacing: float = 30.0
var door_half_width: float = 1.8
# 2-choice door positions
var left_door_x: float = 3.5
var right_door_x: float = -3.5
# 4-choice door positions
var door4_xs: Array[float] = [-5.8, -1.95, 1.95, 5.8]
var door4_half_width: float = 1.45
var coop_p1_door_xs: Array[float] = [4.1, 8.1]
var coop_p2_door_xs: Array[float] = [-8.1, -4.1]
var coop_door_half_width: float = 1.15
var coop_lane_gap_half_width: float = 2.55
var hit_z: float = -6.0
var correct_hold_sec: float = 1.05


