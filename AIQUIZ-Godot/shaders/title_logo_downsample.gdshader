shader_type canvas_item;

// タイトルロゴのスーパーサンプリング（scripts/ui/title_logo/title_logo_intro.gd の SupersampleView）。
// SubViewport に画面の factor 倍の解像度で描いた文字の絵を、画面の 1 画素ごとに factor × factor の画素の平均にして縮める。
// SubViewport の透明な所の色はあてにならないので、色は不透明度で重みを付けて平均する。

uniform int factor = 4;

void fragment() {
	ivec2 tex_size = textureSize(TEXTURE, 0);
	// この画面の画素の中心（SubViewport の画素の単位）と、平均する factor × factor の区画の左上
	vec2 center = UV * vec2(tex_size);
	ivec2 start = ivec2(floor(center - float(factor) * 0.5 + 0.5));
	vec3 rgb = vec3(0.0);
	float alpha = 0.0;
	for (int y = 0; y < factor; y++) {
		for (int x = 0; x < factor; x++) {
			vec4 t = texelFetch(TEXTURE, clamp(start + ivec2(x, y), ivec2(0), tex_size - 1), 0);
			rgb += t.rgb * t.a;
			alpha += t.a;
		}
	}
	COLOR = alpha > 0.0001 ? vec4(rgb / alpha, alpha / float(factor * factor)) : vec4(0.0);
}
