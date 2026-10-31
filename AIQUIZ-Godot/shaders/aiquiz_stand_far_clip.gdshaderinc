// 側面スタンドの、前端のキャップと重なるブロックを切る（aiquiz_stand_surface_clipped.gdshader と
// aiquiz_vertex_glow_clipped.gdshader。値は aiquiz_stadium_stand.gd の fit_end() がインスタンスごとに入れる）。
// ワールド Z が far_clip_z より奥は捨てる。右のスタンドのキャップは手前のブロックの上へ通路（階段）を
// 張り出しているので、その張り出しの幅（ブロックの局所 x が aisle_band の間：通路と座席）だけは
// aisle_clip_z から先を捨てる（内外の壁と床の縁は far_clip_z までつなぐ）。

// 塗装と灯は同じインスタンスで値を共有するので、番号をそろえる（塗装の object_space は 0）。
instance uniform float far_clip_z : instance_index(8) = 1e9;
instance uniform float aisle_clip_z : instance_index(9) = 1e9;
instance uniform vec2 aisle_band : instance_index(10) = vec2(0.0);

varying float v_clip_local_x;

bool far_clipped(float world_z, float local_x) {
	if (world_z > far_clip_z) {
		return true;
	}
	return world_z > aisle_clip_z && local_x > aisle_band.x && local_x < aisle_band.y;
}
