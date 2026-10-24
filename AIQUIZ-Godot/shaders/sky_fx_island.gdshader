shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// スカイゲートの見下ろしの島（SkyFallIslands、sky_fx_islands.glb の SFI_Painted）。色は頂点色（線形）。
// 高い所から見ると遠いので、カメラからの距離で空の色へかすませる（スタジアムの遠景 aiquiz_backdrop.gdshader と同じ考え）。
// 水面より下（礁湖の砂・サンゴ）はかすませない（ゲームの海越しに見える色を海とそろえる）。
// 原点＝海面なので、島の中の高さはモデルの y。

uniform vec3 haze_color : source_color = vec3(0.62, 0.80, 0.98);
uniform float haze_distance = 2600.0;
uniform float haze_max : hint_range(0.0, 1.0) = 0.38;
uniform float saturation = 1.08;
uniform float brightness = 1.0;
// 水面より下：浅い所は礁湖の水色に、深い所は沖の青へ（礁の外の崖が海越しに見えないように）
uniform vec3 lagoon_tint : source_color = vec3(0.34, 0.84, 0.82);
uniform vec3 deep_tint : source_color = vec3(0.02, 0.24, 0.36);
uniform float water_tint = 0.8;
// これより深い面は描かない（m）。ゲームの海は「水面とその奥の面の高さの差」で透け方を決めるので、
// 礁の外の深い斜面が残ると、海面近くの低い視点（着地台の画）から斜面と面の切れ目が海越しにまっすぐな線に見える。
// 描かなければ海は底なしの深い色になり、浅瀬のふちはこの深さの等高線（礁の形に沿った曲線）になる
uniform float deep_discard = 7.0;

varying vec3 world_pos;
varying float local_y;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_y = VERTEX.y;
}

void fragment() {
	if (local_y < -deep_discard) {
		discard;
	}
	vec3 c = COLOR.rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(g), c, saturation) * brightness;
	float depth = max(-local_y, 0.0);
	vec3 water = mix(c * lagoon_tint * 1.1, deep_tint, smoothstep(1.2, 8.0, depth));
	c = mix(c, water, smoothstep(0.1, 0.9, depth) * water_tint);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float amount = min(haze_max, 1.0 - exp(-dist / haze_distance)) * smoothstep(-1.2, 0.3, local_y);
	FOG = vec4(haze_color, amount);
}
