shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// AIQUIZ STADIUM の塗装（取り込んだ材質 AQS_Painted を置き換える。aiquiz_stadium_materials.gd の painted()）。
// 側面スタンド・GOAL ゲート・ゴール観客席・沖のヨットが共有する。
// 土台は頂点色（Blender で AO・水際の汚れ・低周波のムラを焼き込み済み）。線形の値をそのまま ALBEDO にする
// （StandardMaterial3D の vertex_color_use_as_albedo、vertex_color_is_srgb = false と同じ）。粗さ 0.74。
// その上に、頂点の少ない面（柱は上下の端にしか頂点がない）でも出る細かさを、テクスチャを読まずに ALU だけで足す：
//   ムラ   低周波の値ノイズで明るさ ±6 % と、わずかな色温度の揺れ（面ごとの単調さを崩す。平均は変えない）
//   濡れ   海面から上へ wet_height（1.6 m）まで暗く・艶を出す（粗さを下げる）。水際には薄い緑茶の汚れ。
//          水面下は濡れたまま、さらに深さとともに少し暗く（海越しに見える杭の根元が沈んで見える）
//   雨だれ 縦の面に、縦に伸ばしたノイズの薄い筋。遠くて筋が画素より細くなると消す（ちらつかせない）
//   粗さ   0.74 を中心に小さく揺らす
// 焼き込みの汚れも水面からの指数で頂点に乗っているが、柱は上下の端にしか頂点がなく、下端は海底（-129 m）まで
// 伸ばされる（santorini_waterfront.gd）ので、その汚れは柱の全長に薄く伸びて水際には出ない。ここの濡れは水際の
// 1.6 m だけで、明るさの平均はほとんど変えない（画面のスタンドの白い面の平均で -1 % 前後）。
// detail = 0 で頂点色だけ（低画質。従来の StandardMaterial3D と同じ見た目）。
// 座標：側面スタンドは静止しているので、ムラと筋はワールド座標（20 m のブロックごとに繰り返さない）。
// 走路とともに動く物（GOAL ゲート・ゴール観客席）は AiquizStadiumMaterials.apply() が
// インスタンスの object_space = 1 にするので、ムラと筋はその物の局所座標に付いて動く（流れて見えない）。
// 濡れは常にワールドの高さ（物は水平にしか動かない）。夜の発光はない（夜の灯は aiquiz_vertex_glow.gdshader）。
// 本体は aiquiz_stand_surface.gdshaderinc（奥を切る版 aiquiz_stand_surface_clipped.gdshader と共有）。

#include "res://shaders/aiquiz_stand_surface.gdshaderinc"
