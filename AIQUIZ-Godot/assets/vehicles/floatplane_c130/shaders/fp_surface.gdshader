shader_type spatial;
// 水上機 C-130 の面（SuddenDeathFloatplane が材質の名前ごとに貼る）。
// ・頂点色の R は Blender で焼いた AO（fp_bake.py）。AO は環境光だけを暗くする（AO_LIGHT_AFFECT は小さく）ので、
//   閉じた機内は空の光で白っぽくならず、機内の灯（スポットライト）の当たる所だけ明るい。
// ・テクスチャは UV（機内の断熱材・床・布・ベルト・計器）か、三方向から（外板のパネルの線とリベット。ローカルの座標で貼るので
//   機体が動いても模様は動かない）。
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float albedo_texture_mix : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(0.0, 4.0) = 0.0;          // 0 で法線のテクスチャなし
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float roughness_texture_mix : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float clearcoat : hint_range(0.0, 1.0) = 0.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.2;
uniform vec2 uv_scale = vec2(1.0);
uniform bool triplanar = false;
uniform float triplanar_scale = 0.5;                                // 1 m あたりの枚数
uniform float triplanar_sharpness = 4.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform float ao_light_affect : hint_range(0.0, 1.0) = 0.12;
uniform float albedo_ao : hint_range(0.0, 1.0) = 0.0;              // 直接の光でも少し暗く（すき間の汚れ）
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float emission_from_albedo = 0.0;                           // 計器の盤面：テクスチャの色をそのまま光らせる
uniform float emission_mask_alpha : hint_range(0.0, 1.0) = 0.0;    // 1 でテクスチャのアルファの所だけ光らせる（画面・灯）

// 外板の汚れ（2026-10-22）：ローカルの座標で決める（機体が動いても汚れは動かない）
//   むら：大きな面の色のむら（4〜10 m の波）と、下を向く面の薄いくすみ
//   焼け：排気口のまわり（soot_src の xyz、w が強さ）
//   水線：フロート（|x| 2.5〜4.7、y < 1.1）の水面の少し上の帯
uniform bool exterior_grime = false;
uniform float grime_amount : hint_range(0.0, 0.2) = 0.06;
uniform vec4 soot_src[4];
uniform float soot_radius = 0.42;
uniform float waterline_stain : hint_range(0.0, 1.0) = 0.0;

varying float v_ao;
varying vec3 v_obj_pos;
varying vec3 v_obj_nrm;

void vertex() {
	v_ao = COLOR.r;
	v_obj_pos = VERTEX;
	v_obj_nrm = NORMAL;
}

vec3 unpack_n(vec3 c) {
	return c * 2.0 - 1.0;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

vec3 exterior_dirt(vec3 base, vec3 p, vec3 n) {
	float g = vnoise(p * 0.18) * 0.6 + vnoise(p * 0.75) * 0.4;
	base *= 1.0 - grime_amount * (g - 0.35) - 0.05 * max(-n.y, 0.0);
	float soot = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 s = soot_src[i];
		vec3 d = p - s.xyz;
		float k = exp(-dot(d, d) / (soot_radius * soot_radius)) * step(-0.75, d.z);
		soot = max(soot, k * s.w * (0.75 + 0.25 * vnoise(p * 9.0)));
	}
	base = mix(base, vec3(0.10, 0.09, 0.085), clamp(soot, 0.0, 0.85));
	if (waterline_stain > 0.0) {
		float on_float = step(2.5, abs(p.x)) * step(abs(p.x), 4.7) * step(p.y, 1.1);
		float band = smoothstep(0.34, 0.07, p.y) * smoothstep(-0.06, 0.05, p.y);
		float wob = 0.65 + 0.35 * vnoise(vec3(p.z * 1.6, p.y * 9.0, p.x * 2.0));
		base *= mix(vec3(1.0), vec3(0.80, 0.80, 0.70), on_float * band * wob * waterline_stain);
	}
	return base;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 tex_rgb = vec3(1.0);
	float tex_a = 1.0;
	float rough_tex = 1.0;
	if (triplanar) {
		vec3 p = v_obj_pos * triplanar_scale;
		vec3 n = normalize(v_obj_nrm);
		vec3 w = pow(abs(n), vec3(triplanar_sharpness));
		w /= max(w.x + w.y + w.z, 1e-4);
		if (albedo_texture_mix > 0.0) {
			tex_rgb = texture(albedo_texture, p.zy).rgb * w.x + texture(albedo_texture, p.xz).rgb * w.y + texture(albedo_texture, p.xy).rgb * w.z;
		}
		if (roughness_texture_mix > 0.0) {
			rough_tex = texture(roughness_texture, p.zy).r * w.x + texture(roughness_texture, p.xz).r * w.y + texture(roughness_texture, p.xy).r * w.z;
		}
		if (normal_scale > 0.0) {
			// UDN の混ぜ方（法線を三面で引いて、ローカルの法線へ足す）
			vec3 tx = unpack_n(texture(normal_texture, p.zy).rgb);
			vec3 ty = unpack_n(texture(normal_texture, p.xz).rgb);
			vec3 tz = unpack_n(texture(normal_texture, p.xy).rgb);
			tx.xy *= normal_scale;
			ty.xy *= normal_scale;
			tz.xy *= normal_scale;
			vec3 nx = vec3(n.x, tx.y + n.y, tx.x + n.z);
			vec3 ny = vec3(ty.x + n.x, n.y, ty.y + n.z);
			vec3 nz = vec3(tz.x + n.x, tz.y + n.y, n.z);
			vec3 nb = normalize(nx * w.x + ny * w.y + nz * w.z);
			NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nb, 0.0)).xyz);
		}
	} else {
		if (albedo_texture_mix > 0.0) {
			vec4 t4 = texture(albedo_texture, uv);
			tex_rgb = t4.rgb;
			tex_a = t4.a;
		}
		if (roughness_texture_mix > 0.0) {
			rough_tex = texture(roughness_texture, uv).r;
		}
		if (normal_scale > 0.0) {
			NORMAL_MAP = texture(normal_texture, uv).rgb;
			NORMAL_MAP_DEPTH = normal_scale;
		}
	}
	vec3 base = albedo.rgb * mix(vec3(1.0), tex_rgb, albedo_texture_mix);
	if (exterior_grime) {
		base = exterior_dirt(base, v_obj_pos, normalize(v_obj_nrm));
	}
	float ao = mix(1.0, clamp(v_ao, 0.0, 1.0), ao_strength);
	ALBEDO = base * mix(1.0, ao, albedo_ao);
	ROUGHNESS = mix(roughness, rough_tex, roughness_texture_mix);
	METALLIC = metallic;
	SPECULAR = specular;
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	AO = ao;
	AO_LIGHT_AFFECT = ao_light_affect;
	EMISSION = emission_color * emission_energy + base * emission_from_albedo * mix(1.0, tex_a, emission_mask_alpha);
}
