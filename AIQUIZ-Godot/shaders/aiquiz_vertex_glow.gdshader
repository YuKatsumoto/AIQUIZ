shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// AIQUIZ STADIUM の夜の灯（AQS_NightGlow を置き換える）。頂点色の灯の色を、夜の強さに合わせて光らせる。
#include "res://shaders/aiquiz_vertex_glow.gdshaderinc"
