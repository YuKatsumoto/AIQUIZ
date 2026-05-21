shader_type spatial;
render_mode blend_mix, diffuse_lambert, specular_occlusion_disabled, specular_disabled, shadows_disabled, depth_draw_always, cull_back, depth_test_default, vertex_lighting, fog_disabled;
#define VERTEX_FOG_ENABLED;
#define BILLBOARD_DISABLED;

#include "res://addons/psx/shaders/psx.gdshaderinc"
