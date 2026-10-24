shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// A raw egg drop that refracts the background. Body: shaders/goal_stand_egg_drip.gdshaderinc.

#define EGG_REFRACT
#include "res://shaders/goal_stand_egg_drip.gdshaderinc"
