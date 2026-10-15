// スキン編集で選んだパーツの輪郭を光らせる（PlayerSkinRig.set_outline が next_pass に付ける）。
// 箱人形のパーツは原点中心の箱なので、頂点を各軸の外側へ width だけ押し出した一回り大きい箱の
// 裏面だけを描くと、パーツのまわりに同じ太さのふちが出る。ノードの拡大は打ち消して太さをそろえる。
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 0.86, 0.35, 1.0);
uniform float width = 0.022;
uniform float glow = 1.6;

void vertex() {
	vec3 node_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	VERTEX += sign(VERTEX) * width / max(node_scale, vec3(0.0001));
}

void fragment() {
	// ゆっくり明滅させて「いまここ」を目立たせる（1 より明るい分は画面のグローで光る）
	float pulse = 0.8 + 0.2 * sin(TIME * 5.0);
	ALBEDO = outline_color.rgb * glow * pulse;
}
