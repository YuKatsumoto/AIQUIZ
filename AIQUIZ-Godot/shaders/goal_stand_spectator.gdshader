shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Goal stand spectators (assets/goal_stand). Blender stores each face's palette
// role in UV.x = (role + 0.5) / 16; every spectator tints its roles per instance,
// so one material draws the whole crowd.
instance uniform vec4 skin_color : source_color = vec4(0.93, 0.74, 0.60, 1.0);
instance uniform vec4 shirt_color : source_color = vec4(0.94, 0.41, 0.35, 1.0);
instance uniform vec4 pants_color : source_color = vec4(0.20, 0.24, 0.34, 1.0);
instance uniform vec4 hair_color : source_color = vec4(0.23, 0.15, 0.10, 1.0);
instance uniform vec4 shoe_color : source_color = vec4(0.12, 0.12, 0.14, 1.0);
instance uniform vec4 accent_color : source_color = vec4(0.95, 0.55, 0.20, 1.0);
// 0..1: flushes the face red while a spectator rages.
instance uniform float anger = 0.0;

const vec3 DARK = vec3(0.045, 0.045, 0.06);
const vec3 WHITE = vec3(0.95, 0.95, 0.93);
const vec3 BLUSH = vec3(0.96, 0.55, 0.55);
const vec3 EGG = vec3(0.97, 0.93, 0.84);
const vec3 CARTON = vec3(0.72, 0.64, 0.52);
const vec3 WOOD = vec3(0.58, 0.42, 0.26);
const vec3 FURIOUS = vec3(0.93, 0.30, 0.26);

void fragment() {
	int role = int(floor(UV.x * 16.0));
	vec3 skin = mix(skin_color.rgb, FURIOUS, clamp(anger, 0.0, 1.0) * 0.55);
	vec3 color = skin;
	float rough = 0.78;
	if (role == 1) {
		color = shirt_color.rgb;
	} else if (role == 2) {
		color = pants_color.rgb;
	} else if (role == 3) {
		color = hair_color.rgb;
		rough = 0.6;
	} else if (role == 4) {
		color = shoe_color.rgb;
	} else if (role == 5) {
		color = DARK;
		rough = 0.4;
	} else if (role == 6) {
		color = accent_color.rgb;
		rough = 0.55;
	} else if (role == 7) {
		color = WHITE;
	} else if (role == 8) {
		color = mix(BLUSH, FURIOUS, clamp(anger, 0.0, 1.0));
	} else if (role == 9) {
		color = EGG;
		rough = 0.35;
	} else if (role == 10) {
		color = CARTON;
	} else if (role == 11) {
		color = WOOD;
	}
	ALBEDO = color;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
