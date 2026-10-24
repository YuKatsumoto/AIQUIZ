shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Raw egg white with the background refracted through it (BALANCED and up on
// desktop). The body is shaders/goal_stand_egg_white.gdshaderinc.

#define EGG_REFRACT
#include "res://shaders/goal_stand_egg_white.gdshaderinc"
