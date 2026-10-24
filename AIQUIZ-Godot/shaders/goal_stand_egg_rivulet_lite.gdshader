shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Rivulet of raw egg without the screen texture (LOW, mobile). Body:
// shaders/goal_stand_egg_rivulet.gdshaderinc.

#include "res://shaders/goal_stand_egg_rivulet.gdshaderinc"
