shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Rivulet of raw egg with the background refracted through it. Body:
// shaders/goal_stand_egg_rivulet.gdshaderinc.

#define EGG_REFRACT
#include "res://shaders/goal_stand_egg_rivulet.gdshaderinc"
