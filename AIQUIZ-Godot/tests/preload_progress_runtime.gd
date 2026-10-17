extends Node

## 「問題を準備中」パネルの生成待ちの演出（GameplayHUD._show_generation_progress）を素の場面で動かす実機テスト。
## 本物の gameplay_hud.tscn に問題を少しずつ渡し、タイトル・回転アイコン・弾む数字・
## キャラクター到着待ちの「問題ができました！」・Enter待ちで元に戻ることを確かめて画像を撮る。
## Godot --path . --fixed-fps 60 --script res://tests/preload_progress_bootstrap.gd

const OUT := "res://artifacts/preload_progress/"
## 以前の実機の画像（artifacts/ はコミットしない）。なければグラデーション。
const BACKDROP_SHOT := "res://artifacts/helicopter_audio/arrival_p1.png"

var checks := 0
var failures: Array[String] = []
var shots: Array[Dictionary] = []
var hud: CanvasLayer
var gs: QuizGameState
## GameplayHUD は親の is_start_presentation_locked() でキャラクター到着待ちを知る。
var arrival_locked := false


func is_start_presentation_locked() -> bool:
	return arrival_locked


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# Keep the editor from importing the screenshots.
	FileAccess.open(OUT + ".gdignore", FileAccess.WRITE)
	_add_backdrop()
	await hud_pass()
	finish()


func hud_pass() -> void:
	gs = QuizManager.game_state
	gs.mode = Constants.MODE_TEN
	gs.target_count = 10
	gs.subject = "算数"
	gs.grade = 3
	gs.llm_mode = "ONLINE"
	gs.use_english_ui = false
	gs.net_online = false
	gs.sudden_death_preparing_panel = ""
	gs.quiz_list.clear()
	gs.game_state = Constants.STATE_PRELOADING
	gs.refresh_status_text()
	hud = (load("res://ui/gameplay_hud.tscn") as PackedScene).instantiate() as CanvasLayer
	add_child(hud)
	await frames(24)
	var panel := hud.get_node("PreloadPanel") as Control
	var title := hud.get_node("PreloadPanel/Title") as Label
	var status := hud.get_node("PreloadPanel/Status") as Label
	var count := hud.get_node("PreloadPanel/GenerationCount") as Label
	var decor := hud.get_node("PreloadPanel/GenerationTitleDecor") as GenerationTitleDecor
	var plain_bar := hud.get_node("PreloadPanel/ProgressBar") as ProgressBar
	check(not hud.has_node("PreloadPanel/GenerationFeed"), "hud: no step box or log")
	check(panel.visible and panel.size.is_equal_approx(Vector2(600.0, 240.0)), "hud: panel keeps 600x240 (%s)" % panel.size)
	check(title.text == "AIが問題をつくっています", "hud: title (%s)" % title.text)
	check((hud.get_node("PreloadPanel/Subtitle") as Label).text == "算数・3年 の問題", "hud: subtitle")
	check(status.text == gs.status_text, "hud: Status keeps the game status text (%s)" % status.text)
	check(count.visible and count.text == "0/10", "hud: count 0/10 (%s)" % count.text)
	check(decor.visible and decor.mode == "busy" and decor.text_width > 200.0, "hud: spinner and dots around the title")
	check(plain_bar.visible and plain_bar.get_child_count() == 0, "hud: the plain bar, nothing drawn over it")
	await capture("01_waiting")

	_add_quizzes(3)
	await frames(4)
	check(count.text == "3/10" and count.scale.x > 1.05, "hud: count pops on arrival (%s, %.2f)" % [count.text, count.scale.x])
	await capture("02_count_pop")
	await frames(40)
	check(is_equal_approx(plain_bar.value, 3.0), "hud: the bar reaches 3/10 (%.2f)" % plain_bar.value)
	check(is_equal_approx(count.scale.x, 1.0), "hud: count settles back")
	for _i: int in range(6):
		_add_quizzes(1)
		await frames(30)
	check(count.text == "9/10", "hud: count 9/10 (%s)" % count.text)
	check(absf(plain_bar.value - 9.0) < 0.01, "hud: bar at 9/10")
	check(panel.get_global_rect().encloses(count.get_global_rect()), "hud: count stays inside the panel")
	await capture("03_nine_of_ten")
	await aspect_shot(Vector2i(1024, 768), "03b_4x3", panel)
	await aspect_shot(Vector2i(1680, 720), "03c_21x9", panel)
	get_tree().root.size = Vector2i(1280, 720)
	await frames(4)

	# Last one in: the game moves to WAITING_START while the characters arrive.
	_add_quizzes(1)
	arrival_locked = true
	gs.game_state = Constants.STATE_WAITING_START
	await frames(20)
	check(is_equal_approx(plain_bar.value, 10.0), "hud: full bar")
	check(title.text == "問題ができました！" and decor.mode == "done", "hud: title turns to ready (%s)" % title.text)
	check(status.text == "キャラクター到着中...", "hud: arrival status (%s)" % status.text)
	check(count.visible and count.text == "10/10", "hud: full count during the arrival")
	await capture("04_ready_arrival")

	arrival_locked = false
	await frames(6)
	check(not count.visible and not decor.visible and not plain_bar.visible, "hud: decor hides at the start prompt")
	check(title.text == "準備完了！" and title.vertical_alignment == VERTICAL_ALIGNMENT_TOP, "hud: start prompt title (%s)" % title.text)
	await capture("05_start_prompt")

	# English, and a fresh round starts from zero.
	gs.use_english_ui = true
	gs.game_state = Constants.STATE_MENU
	await frames(2)
	gs.quiz_list.clear()
	gs.game_state = Constants.STATE_PRELOADING
	gs.refresh_status_text()
	_add_quizzes(4)
	await frames(40)
	check(title.text == "AI is writing your quizzes" and count.text == "4/10", "hud: english fresh round (%s, %s)" % [title.text, count.text])
	await capture("06_english")

	# A guest receives the list with holes (null): only real questions count.
	gs.use_english_ui = false
	gs.quiz_list.append(null)
	gs.quiz_list.append(null)
	await frames(4)
	check(count.text == "4/10", "hud: holes in the list are not counted (%s)" % count.text)


func _add_quizzes(amount: int) -> void:
	for _i: int in range(amount):
		var index := gs.quiz_list.size()
		gs.quiz_list.append(QuizItem.create("Q%d" % (index + 1), PackedStringArray(["1", "2"]), 0, "", "GEMINI_STREAM"))
	gs.refresh_status_text()


func aspect_shot(window: Vector2i, tag: String, panel: Control) -> void:
	get_tree().root.size = window
	await frames(4)
	var view := get_viewport().get_visible_rect()
	check(view.grow(1.0).encloses(panel.get_global_rect()), "%s: panel inside the view (%s in %s)" % [tag, panel.get_global_rect(), view])
	await capture(tag)


func frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().process_frame


func capture(tag: String) -> void:
	await frames(1)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OUT + tag + ".png")
	shots.append({"tag": tag, "size": [image.get_width(), image.get_height()],
		"title": (hud.get_node("PreloadPanel/Title") as Label).text,
		"count": (hud.get_node("PreloadPanel/GenerationCount") as Label).text})


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func _add_backdrop() -> void:
	var image: Image = null
	if FileAccess.file_exists(BACKDROP_SHOT):
		image = Image.load_from_file(ProjectSettings.globalize_path(BACKDROP_SHOT))
	if image != null:
		image.convert(Image.FORMAT_RGBA8)
		# Paint out the old preparing panel captured in that frame.
		image.fill_rect(Rect2i(336, 236, 608, 248), Color(0.16, 0.2, 0.28))
	else:
		image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y: int in range(64):
			image.fill_rect(Rect2i(0, y, 64, 1), Color(0.45, 0.65, 0.9).lerp(Color(0.3, 0.32, 0.36), float(y) / 63.0))
	var backdrop := TextureRect.new()
	backdrop.texture = ImageTexture.create_from_image(image)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)


func finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "shots": shots}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PRELOAD_PROGRESS_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
