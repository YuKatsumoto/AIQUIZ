extends SceneTree

## ChalkCanvas（scripts/world/settings_hall/chalk_canvas.gd）を単体で動かし、線・円・消し・何度も消した跡を描いて保存する。
## 例: Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/chalk_canvas_preview.gd
## 結果: res://artifacts/settings_hall/chalk/canvas.png

const ChalkCanvasScript := preload("res://scripts/world/settings_hall/chalk_canvas.gd")
const OUT := "res://artifacts/settings_hall/chalk/"
const BASE := "res://assets/settings_hall/source/baked/PRP_BoardSurface_F_albedo.png"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var base: Texture2D = null
	if FileAccess.file_exists(BASE):
		base = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(BASE)))
	else:
		var img := Image.create(64, 16, false, Image.FORMAT_RGB8)
		img.fill(Color(0.11, 0.23, 0.18))
		base = ImageTexture.create_from_image(img)
	var canvas: SubViewport = ChalkCanvasScript.new()
	root.add_child(canvas)
	canvas.setup(base, Vector2(7.53, 1.71), 2048)
	for _i in range(4):
		await process_frame
	# 横線（強い筆圧）、弱い筆圧の線、円（白）、黄色の矢印、赤の丸囲み
	var id := 1
	for k in range(41):
		canvas.stroke_to(id, Vector2(0.3 + 2.2 * k / 40.0, 1.35), "white", 0.022, 1.0)
		if k % 8 == 0:
			await process_frame
	canvas.end_stroke(id)
	id += 1
	for k in range(41):
		canvas.stroke_to(id, Vector2(0.3 + 2.2 * k / 40.0, 1.15), "white", 0.022, 0.45)
	canvas.end_stroke(id)
	id += 1
	for k in range(61):
		var a := TAU * k / 60.0
		canvas.stroke_to(id, Vector2(3.2 + 0.35 * cos(a), 0.9 + 0.35 * sin(a)), "white", 0.02, 0.9)
	canvas.end_stroke(id)
	id += 1
	for k in range(31):
		canvas.stroke_to(id, Vector2(4.0 + 1.0 * k / 30.0, 0.9), "yellow", 0.02, 0.9)
	canvas.end_stroke(id)
	id += 1
	for k in range(61):
		var a := TAU * k / 60.0
		canvas.stroke_to(id, Vector2(1.4 + 0.9 * cos(a), 0.5 + 0.22 * sin(a)), "red", 0.018, 0.8)
	canvas.end_stroke(id)
	for _i in range(3):
		await process_frame
	# 消し: 右半分の横線の上を 1 回だけ（跡が残る）、左の方は 4 回
	for k in range(10):
		canvas.erase_at(Vector2(1.5 + k * 0.12, 1.35), Vector2(0.22, 0.09), 0.35)
	await process_frame
	for rep in range(4):
		for k in range(8):
			canvas.erase_at(Vector2(0.4 + k * 0.12, 1.15), Vector2(0.22, 0.09), 0.35)
		await process_frame
	for _i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = canvas.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + "canvas.png"))
	print("CHALK_CANVAS ", image.get_size())
	quit(0)
