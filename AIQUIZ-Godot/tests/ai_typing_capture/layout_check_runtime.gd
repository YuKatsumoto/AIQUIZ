extends Node3D

## layout_check.gd から起動する。壁と同じ向き（Y 軸まわりに 180 度）の Label3D を、壁の文字と同じ設定で作り、
## 元のラベルだけ・1 文字ずつのラベルだけの 2 枚を撮って並べる。

const OUT := "res://artifacts/ai_typing_capture/layout_check/"
const QuizWallScript := preload("res://scripts/world/quiz_wall.gd")
const TEXTS := ["Q1 このゲームのもんだいを\nつくっているのはだれ？", "せんせい", "【かけ算】7 × 8 ＝ ？"]
const ROWS_Y := [1.5, -0.9, -2.0]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.09, 0.17, 0.36)
	add_child(env)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.3, -6.0)
	add_child(camera)
	camera.look_at(Vector3(0, 0.3, 0))
	camera.current = true
	var labels: Array[Label3D] = []
	for i: int in range(TEXTS.size()):
		var label := _make_label(TEXTS[i])
		label.position = Vector3(0, ROWS_Y[i], 0)
		add_child(label)
		labels.append(label)
	await _frames(4)
	_save("source.png")
	var report := []
	for label: Label3D in labels:
		var clusters := WallAiTextReveal.layout_clusters(label)
		report.append({"text": label.text, "aabb": str(label.get_aabb()), "clusters": clusters.map(func(c: Dictionary) -> Dictionary:
			return {"text": c.text, "line": c.line, "x": snappedf(c.position.x, 0.0001), "y": snappedf(c.position.y, 0.0001), "left": snappedf(c.left, 0.0001)})})
		var reveal := WallAiTextReveal.new()
		for cluster: Dictionary in clusters:
			var glyph: Label3D = reveal.call("_make_glyph", label, cluster)
			label.add_child(glyph)
		reveal.free()
		label.layers = 0
	await _frames(4)
	_save("glyphs.png")
	var file := FileAccess.open(OUT + "clusters.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	get_tree().quit()


func _make_label(text: String) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.render_priority = 20
	label.outline_render_priority = 19
	label.pixel_size = 0.008
	label.width = 640.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.02, 0.05, 0.08, 0.95)
	label.outline_size = 8
	label.font_size = 64
	label.text = text
	label.rotation.y = PI
	label.font = QuizWallScript._wall_label_font()
	return label


func _frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().process_frame


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name))
