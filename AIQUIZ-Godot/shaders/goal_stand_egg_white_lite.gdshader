shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Raw egg white without the screen texture (LOW, mobile): a glossy, lightly milky
// transparent layer. The body is shaders/goal_stand_egg_white.gdshaderinc.

#include "res://shaders/goal_stand_egg_white.gdshaderinc"
