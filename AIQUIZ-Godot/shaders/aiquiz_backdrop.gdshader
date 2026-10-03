shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// AIQUIZ STADIUM の遠景（島・街）。assets/aiquiz_stadium の AQS_BG_Painted と AQS_CityFacade_* を置き換える。
// 色：頂点色。外壁は昼のテクスチャを掛け、夜は窓明かりのテクスチャを光らせる（night_energy）。
// かすみ：ゲームは霧を使わないので、ここで距離に応じて空の地平線の色へ寄せる（FOG）。地平線の色は
// 空のシェーダー（aiquiz_day_night_sky.gdshader）と同じ式で、太陽の高さ・向きから昼／夕焼け／夜を混ぜる。
// 量 = min(haze_max, (1 - exp(-距離 / haze_distance)) × (1 - haze_height_clear × 海面からの高さの smoothstep))
// Blender の確認シーン（aqs_review.haze_review_material）も同じ式と値。
// 水面下（島のまわりの浅瀬）はかすませない。ゲームの海はかすまないので、海越しに見える色を海とそろえる。
// 沖の海（AQS_BG_Sea、fade_from_ocean_edge）：ゲームの海の板の外を埋める。縁ではかすみ 0 で海の色とそろえ、
// 縁から ocean_haze_fade m 外へ離れるまでに、ほかの遠景と同じかすみになる。

uniform bool use_facade = false;
uniform sampler2D facade : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D facade_night : source_color, filter_linear_mipmap, repeat_enable;
uniform float night_energy : hint_range(0.0, 8.0) = 0.0;
// 夜は外壁を暗くする（ガラスは暗い夜空を映す）。ゲームの夜の環境光は強いので、窓明かりが暗い輪郭に浮かぶように
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform float facade_night_dim : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.88;
uniform float specular_val : hint_range(0.0, 1.0) = 0.5;

group_uniforms Haze;
uniform vec3 haze_day : source_color = vec3(0.64, 0.88, 1.0);
uniform vec3 haze_sunset : source_color = vec3(1.0, 0.42, 0.16);
uniform vec3 haze_night : source_color = vec3(0.075, 0.15, 0.34);
uniform vec3 sun_direction = vec3(0.0, 0.77, 0.64);
uniform float haze_energy : hint_range(0.0, 2.0) = 0.95;
uniform float haze_distance = 10000.0;
uniform float haze_max : hint_range(0.0, 1.0) = 0.6;
uniform float haze_height = 350.0;
uniform float haze_height_clear : hint_range(0.0, 1.0) = 0.3;
uniform float sea_level = -9.2;
uniform bool fade_from_ocean_edge = false;
uniform vec2 ocean_half = vec2(2000.0, 2000.0);
uniform float ocean_center_z = 150.0;
uniform float ocean_haze_fade = 900.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 horizon_colour(vec3 view_flat) {
	vec3 sun = normalize(sun_direction);
	float day_amount = smoothstep(-0.16, 0.28, sun.y);
	float twilight = exp(-pow(abs(sun.y) / 0.23, 2.0));
	vec3 sun_flat = vec3(sun.x, 0.0, sun.z);
	sun_flat /= max(length(sun_flat), 0.001);
	float facing = pow(max(dot(view_flat, sun_flat), 0.0), 1.6);
	vec3 colour = mix(haze_night, haze_day, day_amount);
	return mix(colour, haze_sunset, clamp(twilight * mix(0.28, 1.0, facing), 0.0, 1.0));
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	if (use_facade) {
		albedo *= texture(facade, UV).rgb * (1.0 - facade_night_dim * night_amount);
		EMISSION = texture(facade_night, UV).rgb * night_energy;
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;

	vec3 to_frag = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(to_frag);
	vec3 view_flat = vec3(to_frag.x, 0.0, to_frag.z);
	view_flat /= max(length(view_flat), 0.001);
	float height = world_pos.y - sea_level;
	float clear = 1.0 - haze_height_clear * smoothstep(0.0, haze_height, height);
	float amount = min(haze_max, (1.0 - exp(-dist / haze_distance)) * clear);
	if (fade_from_ocean_edge) {
		vec2 outside = abs(vec2(world_pos.x, world_pos.z - ocean_center_z)) - ocean_half;
		amount *= smoothstep(0.0, ocean_haze_fade, max(max(outside.x, outside.y), 0.0));
	} else {
		amount *= smoothstep(-1.2, 0.2, height);
	}
	FOG = vec4(horizon_colour(view_flat) * haze_energy, amount);
}
