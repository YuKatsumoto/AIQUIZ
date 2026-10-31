shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// aiquiz_vertex_glow.gdshader と同じ夜の灯で、前端のキャップと重なる所を捨てる版
// （aiquiz_stand_surface_clipped.gdshader と対で使う）。
#define STAND_FAR_CLIP
#include "res://shaders/aiquiz_vertex_glow.gdshaderinc"
