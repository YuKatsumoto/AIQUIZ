shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// A raw egg drop without the screen texture (LOW, mobile). Body:
// shaders/goal_stand_egg_drip.gdshaderinc.

#include "res://shaders/goal_stand_egg_drip.gdshaderinc"
