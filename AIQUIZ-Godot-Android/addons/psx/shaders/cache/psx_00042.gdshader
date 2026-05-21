shader_type spatial;
render_mode blend_mix, diffuse_lambert, specular_occlusion_disabled, specular_disabled, shadows_disabled, cull_back, depth_test_default, unshaded, fog_disabled;
#define ALPHA_DISABLED;
#define VERTEX_FOG_ENABLED;
#define BILLBOARD_DISABLED;

#include "res://addons/psx/shaders/psx.gdshaderinc"
