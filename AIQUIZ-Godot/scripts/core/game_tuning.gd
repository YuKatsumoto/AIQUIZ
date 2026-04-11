extends RefCounted
class_name GameTuning

## ゲームのチューニングパラメータ (Python版 GameTuning 相当)

var player_speed: float = 7.6
var min_x: float = -6.5
var max_x: float = 6.5
var wall_start_z: float = 22.0
var wall_speed: float = 6.8
var wall_speed_min: float = 3.0
var wall_speed_max: float = 9.0
var wall_spacing: float = 30.0
var door_half_width: float = 1.8
# 2-choice door positions
var left_door_x: float = 2.8
var right_door_x: float = -2.8
# 4-choice door positions
var door4_xs: Array[float] = [-5.8, -1.95, 1.95, 5.8]
var door4_half_width: float = 1.45
var hit_z: float = -6.0
var correct_hold_sec: float = 1.05
