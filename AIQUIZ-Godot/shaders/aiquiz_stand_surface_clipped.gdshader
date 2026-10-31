shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// aiquiz_stand_surface.gdshader と同じ塗装で、前端のキャップと重なる所を捨てる版（aiquiz_stand_far_clip.gdshaderinc）。
// 側面スタンドの、前端のキャップと重なるブロックだけが使う（AiquizStadiumMaterials.far_clipped()、
// aiquiz_stadium_stand.gd の fit_end()）。discard は深度の前処理を重くするので、共有の塗装には入れない。

#define STAND_FAR_CLIP
#include "res://shaders/aiquiz_stand_surface.gdshaderinc"
