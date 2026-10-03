extends Node

## SuddenDeathHud（scripts/ui/sudden_death_hud.gd）を素の場面で動かす実機テスト。
## 全要素を決まった時間割で再生し、デバッグ情報と画像を確かめる。画像の瞬間を
## 固定するため、時計は debug_step で手動に進める。最後に、実時間の時計が
## Engine.time_scale（0.5倍のスロー）に影響されないことと、HUDがマウス入力を
## 奪わないことを、手動の時計を切って確かめる。
## Godot --path . --script res://tests/sudden_death_hud_bootstrap.gd

const OUT := "res://artifacts/sudden_death/hud/"
const HudScript := preload("res://scripts/ui/sudden_death_hud.gd")
## Earlier real-game captures, used as backdrops when present (artifacts/ is not committed).
const CISTERN_SHOT := "res://artifacts/sudden_death/runtime/gate/10_row1_approach.png"
const DRAW_SHOT := "res://artifacts/sudden_death/runtime/gate/01_draw_verdict.png"
const STEP := 1.0 / 60.0
const GREEN := Color(0.45, 1.0, 0.55)
const WRONG := Color(1.0, 0.4, 0.3)
const BLUE := Color(0.6, 0.85, 1.0)
const YELLOW := Color(0.95, 0.72, 0.10)
const OUT_RED := Color(1.0, 0.35, 0.3)

var hud: HudScript
var backdrop: TextureRect
var textures := {}
var checks := 0
var failures: Array[String] = []
var shots: Array[Dictionary] = []
var extra := {}
var button_presses := 0


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# Keep the editor from importing the screenshots.
	FileAccess.open(OUT + ".gdignore", FileAccess.WRITE)
	_build_backdrops()
	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	hud = HudScript.new()
	add_child(hud)
	hud.debug_manual_clock = true
	await frames(3)
	check(hud.layer == 8, "HUD sits on canvas layer 8")
	check(bool(hud.get_debug_snapshot().mouse_ignored), "every HUD control ignores the mouse")
	await language_pass(false)
	await motion_strip()
	await language_pass(true)
	await aspect_pass(Vector2i(1024, 768), "4x3")
	await aspect_pass(Vector2i(1680, 720), "21x9")
	get_tree().root.size = Vector2i(1280, 720)
	await frames(6)
	await check_real_time()
	await check_mouse_passthrough()
	await check_hide_all()
	finish()


# ------------------------------------------------------------------ passes

func language_pass(english: bool) -> void:
	var tag := "en" if english else "ja"
	hud.setup(english)
	hud.hide_all(true)
	# 2.1: the cut-in slams over the DRAW verdict.
	use_backdrop("draw")
	hud.show_cut_in()
	await advance(0.30)
	var snap := hud.get_debug_snapshot()
	check(snap.cut_in.visible and snap.cut_in.text == "SUDDEN DEATH!", "%s: cut-in visible mid-slam" % tag)
	check(snap.cut_in.phase == "hold", "%s: cut-in past impact at 0.30 s" % tag)
	check(float(snap.flash) > 0.05, "%s: white flash at the slam" % tag)
	await capture("01_cut_in_slam_" + tag)
	await advance(0.9)
	snap = hud.get_debug_snapshot()
	check(snap.cut_in.phase == "hold" and float(snap.flash) == 0.0, "%s: cut-in holds after the flash" % tag)
	check_inside(snap, "cut_in")
	await capture("02_cut_in_hold_" + tag)
	await advance(1.1)
	check(not hud.get_debug_snapshot().cut_in.visible, "%s: cut-in wiped out by 2.3 s" % tag)
	# 5.3: depth meter slides in during the descent.
	use_backdrop("shaft")
	hud.set_depth_meter(0.4, 12.0, true)
	await advance(0.05)
	var half_in: Rect2 = hud.get_debug_snapshot().rects.get("depth_meter", Rect2())
	var depth := 58.0 if english else 34.0
	hud.set_depth_meter(1.0, depth, true)
	await advance(0.6)
	snap = hud.get_debug_snapshot()
	var meter: Rect2 = snap.rects.get("depth_meter", Rect2())
	check(snap.depth_meter.visible and snap.depth_meter.readout == "−%dm" % int(depth), "%s: depth readout −%dm" % [tag, int(depth)])
	check(snap.depth_meter.loading and snap.depth_meter.status == ("LOADING" if english else "準備中"), "%s: loading pulse text" % tag)
	check(half_in.position.x > meter.position.x + 20.0, "%s: depth meter slides with visible_amount" % tag)
	check(meter.end.x > viewport_size().x - 40.0 and meter.position.x > viewport_size().x * 0.75, "%s: depth meter on the right edge" % tag)
	check_inside(snap, "depth_meter")
	await capture("03_depth_loading_" + tag)
	hud.set_depth_meter(1.0, 70.0, false)
	await advance(0.1)
	snap = hud.get_debug_snapshot()
	check(snap.depth_meter.readout == "−70m" and snap.depth_meter.status == ("ARRIVED" if english else "到着"), "%s: depth meter arrives at −70m" % tag)
	hud.set_depth_meter(0.0, 70.0, false)
	await advance(0.1)
	check(not hud.get_debug_snapshot().depth_meter.visible, "%s: depth meter slides out" % tag)
	# 2.2: landing in letterbox, the referee's shout, rule card, countdown.
	use_backdrop("cistern")
	hud.set_letterbox(1.0)
	await advance(0.3)
	snap = hud.get_debug_snapshot()
	check(snap.letterbox.visible and absf(float(snap.letterbox.bar_px) - 91.9) < 1.5, "%s: letterbox bars at 2.39:1 (%s px)" % [tag, snap.letterbox.bar_px])
	hud.show_shout("SUDDEN DEATH!" if english else "サドンデス！")
	await advance(0.36)
	snap = hud.get_debug_snapshot()
	check(snap.shout.visible and snap.shout.text == ("SUDDEN DEATH!" if english else "サドンデス！"), "%s: shout caption" % tag)
	check_inside(snap, "shout")
	check(not (snap.rects.shout as Rect2).intersects(snap.rects.letterbox_top), "%s: shout clears the top bar" % tag)
	await capture("04_shout_letterbox_" + tag)
	await advance(0.6)
	hud.show_rule_card(2.0)
	await advance(1.0)
	snap = hud.get_debug_snapshot()
	check(snap.rule_card.visible and not snap.rule_card.short and snap.rule_card.lines.size() == 4, "%s: long rule card with four rules" % tag)
	check(String(snap.rule_card.lines[0]).begins_with("JUMP to buzz in" if english else "ジャンプキーで早押し"), "%s: rule text language" % tag)
	check(not snap.shout.visible, "%s: shout clears away for the rule card" % tag)
	check_inside(snap, "rule_card")
	check(not (snap.rects.rule_card as Rect2).intersects(snap.rects.letterbox_bottom), "%s: rule card clears the bottom bar" % tag)
	await capture("05_rule_card_" + tag)
	await advance(1.05)
	check(not hud.get_debug_snapshot().rule_card.visible, "%s: rule card gone after 2.0 s" % tag)
	hud.show_rule_card(1.0)
	await advance(0.5)
	snap = hud.get_debug_snapshot()
	check(snap.rule_card.visible and snap.rule_card.short, "%s: short rule card" % tag)
	await advance(0.55)
	check(not hud.get_debug_snapshot().rule_card.visible, "%s: short rule card gone after 1.0 s" % tag)
	# A held card (the rules wait for Enter) stays as long as it likes, carries the prompt, and leaves on dismiss.
	hud.show_rule_card(INF)
	await advance(8.0)
	snap = hud.get_debug_snapshot()
	check(snap.rule_card.visible and snap.rule_card.hold and not snap.rule_card.short, "%s: held rule card is still up after 8 s" % tag)
	check_inside(snap, "rule_card")
	check(not (snap.rects.rule_card as Rect2).intersects(snap.rects.letterbox_bottom), "%s: held rule card (with the Enter prompt) clears the bottom bar" % tag)
	await capture("05b_rule_card_hold_" + tag)
	hud.dismiss_rule_card()
	await advance(0.1)
	snap = hud.get_debug_snapshot()
	check(snap.rule_card.visible and not snap.rule_card.hold, "%s: dismissed card is no longer held but still sliding out" % tag)
	await advance(0.4)
	check(not hud.get_debug_snapshot().rule_card.visible, "%s: dismissed card slides out" % tag)
	hud.set_letterbox(0.0)
	hud.set_countdown("3")
	await advance(0.6)
	# Called every frame with the same text: must not restart the slam.
	for index in range(12):
		hud.set_countdown("2")
		await advance(STEP)
	snap = hud.get_debug_snapshot()
	check(snap.countdown.visible and snap.countdown.text == "2", "%s: countdown shows 2" % tag)
	check_inside(snap, "countdown")
	await capture("06_countdown_2_" + tag)
	hud.set_countdown("1")
	await advance(0.6)
	hud.set_countdown("GO!")
	await advance(0.24)
	snap = hud.get_debug_snapshot()
	check(snap.countdown.text == "GO!" and snap.countdown.visible, "%s: GO! slam" % tag)
	await capture("07_countdown_go_" + tag)
	await advance(1.2)
	check(not hud.get_debug_snapshot().countdown.visible, "%s: GO! clears itself" % tag)
	# 8: callouts, danger. Nothing runs along the top but the duel's question panel (set_quiz).
	snap = hud.get_debug_snapshot()
	check(not snap.has("run_band"), "%s: no run band over the question board" % tag)
	hud.callout("P1 SAFE!", GREEN)
	await advance(0.35)
	hud.callout("P2 WRONG!" if english else "P2 不正解！", WRONG)
	hud.set_danger(0.8)
	await advance(0.3)
	snap = hud.get_debug_snapshot()
	check(snap.callouts.size() == 2 and snap.callout == ("P2 WRONG!" if english else "P2 不正解！"), "%s: two stacked callouts" % tag)
	check(float(snap.danger) > 0.7, "%s: danger vignette" % tag)
	var newest: Rect2 = snap.rects.get("callout_0", Rect2())
	var older: Rect2 = snap.rects.get("callout_1", Rect2())
	check(newest.size.x > 0.0 and older.size.x > 0.0 and not newest.intersects(older), "%s: callouts do not overlap" % tag)
	check_inside(snap, "callout_0")
	check_inside(snap, "callout_1")
	await capture("09_callouts_danger_" + tag)
	hud.set_danger(0.0)
	await advance(1.3)
	check(hud.get_debug_snapshot().callouts.is_empty(), "%s: callouts expire" % tag)
	hud.callout("BOTH WRONG! PUMPS ON" if english else "全員不正解！ 排水ポンプ作動", BLUE, 1.6)
	await advance(0.45)
	snap = hud.get_debug_snapshot()
	check_inside(snap, "callout_0")
	await capture("10_both_wrong_" + tag)
	await advance(1.3)
	hud.callout("TO THE LADDERS! TAP FORWARD" if english else "出口のハシゴへ！ 前進キー連打", YELLOW)
	await advance(0.5)
	snap = hud.get_debug_snapshot()
	check_inside(snap, "callout_0")
	await capture("11_ladder_" + tag)
	hud.callout("P2 OUT!" if not english else "P1 OUT!", OUT_RED)
	await advance(0.5)
	await capture("12_out_" + tag)
	hud.hide_all()
	await advance(0.5)
	snap = hud.get_debug_snapshot()
	check(snap.callouts.is_empty(), "%s: hide_all clears the run HUD" % tag)
	# 2.3: winner title.
	var winner := 2 if english else 1
	hud.set_letterbox(1.0)
	hud.show_winner(winner)
	await advance(0.6)
	snap = hud.get_debug_snapshot()
	check(snap.winner.visible and snap.winner.title == "P%d WIN!" % winner and snap.winner.sub == "SUDDEN DEATH", "%s: winner title" % tag)
	check_inside(snap, "winner")
	check_inside(snap, "winner_sub")
	await capture("13_winner_" + tag)
	await advance(1.5)
	check(hud.get_debug_snapshot().winner.visible, "%s: winner stays until hidden" % tag)
	hud.hide_all()
	await advance(0.5)
	snap = hud.get_debug_snapshot()
	check(not snap.winner.visible and not snap.letterbox.visible, "%s: winner and letterbox fade out" % tag)


## Frame sequences of the slams and wipes (motion evidence, seq/*.png).
func motion_strip() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "seq"))
	hud.setup(false)
	hud.hide_all(true)
	use_backdrop("draw")
	hud.show_cut_in()
	var clock := 0.0
	var scales: Array[float] = []
	for at: float in [0.04, 0.12, 0.18, 0.22, 0.25, 0.3, 0.38, 0.5, 1.95, 2.05, 2.15, 2.22]:
		await advance(at - clock)
		clock = at
		var rect: Rect2 = hud.get_debug_snapshot().rects.get("cut_in", Rect2())
		scales.append(rect.size.x)
		await capture("seq/cut_in_%04d" % int(at * 1000.0))
	# The text slams in large, undershoots and settles (AE verdict curve).
	check(scales[1] > scales[7] * 1.4, "cut-in text starts large (%.0f px vs %.0f px)" % [scales[1], scales[7]])
	check(scales[4] < scales[7], "cut-in text undershoots at the impact")
	await advance(0.1)
	check(not hud.get_debug_snapshot().cut_in.visible, "cut-in gone after its wipe-out")
	use_backdrop("cistern")
	hud.set_letterbox(1.0)
	hud.show_winner(1)
	clock = 0.0
	for at: float in [0.05, 0.12, 0.16, 0.22, 0.32, 0.45, 0.7]:
		await advance(at - clock)
		clock = at
		await capture("seq/winner_%04d" % int(at * 1000.0))
	hud.hide_all(true)
	hud.callout("P1 SAFE!", GREEN)
	clock = 0.0
	for at: float in [0.03, 0.08, 0.14, 0.24, 0.5, 1.0, 1.1]:
		await advance(at - clock)
		clock = at
		await capture("seq/callout_%04d" % int(at * 1000.0))
	hud.hide_all(true)
	await advance(0.1)


func aspect_pass(window: Vector2i, tag: String) -> void:
	get_tree().root.size = window
	await frames(8)
	hud.setup(false)
	hud.hide_all(true)
	use_backdrop("cistern")
	hud.callout("P1 SAFE!", GREEN)
	hud.set_danger(0.5)
	await advance(0.5)
	var snap := hud.get_debug_snapshot()
	check_inside(snap, "callout_0")
	await capture("20_run_" + tag)
	hud.hide_all(true)
	use_backdrop("shaft")
	hud.set_depth_meter(1.0, 34.0, true)
	hud.show_cut_in()
	await advance(0.5)
	snap = hud.get_debug_snapshot()
	check_inside(snap, "depth_meter")
	check_inside(snap, "cut_in")
	await capture("21_cut_in_depth_" + tag)
	hud.hide_all(true)
	use_backdrop("cistern")
	hud.set_letterbox(1.0)
	hud.show_rule_card(2.0)
	await advance(1.0)
	snap = hud.get_debug_snapshot()
	check_inside(snap, "rule_card")
	check(not (snap.rects.rule_card as Rect2).intersects(snap.rects.letterbox_bottom), "%s: rule card clears the bottom bar" % tag)
	await capture("22_rule_card_" + tag)
	hud.hide_all(true)
	hud.show_winner(2)
	await advance(0.6)
	check_inside(hud.get_debug_snapshot(), "winner")
	await capture("23_winner_" + tag)
	hud.hide_all(true)
	await advance(0.1)


## The HUD runs on real time: 0.5x slow motion must not slow it down.
func check_real_time() -> void:
	hud.hide_all(true)
	use_backdrop("cistern")
	hud.debug_manual_clock = false
	Engine.time_scale = 0.5
	await frames(2)
	var start_clock := float(hud.get_debug_snapshot().clock)
	var start_usec := Time.get_ticks_usec()
	var scaled := 0.0
	hud.callout("SLOW-MO 0.5x", GREEN, 1.0)
	while Time.get_ticks_usec() - start_usec < 600000:
		await get_tree().process_frame
		scaled += get_process_delta_time()
	var real := float(Time.get_ticks_usec() - start_usec) / 1000000.0
	var hud_elapsed := float(hud.get_debug_snapshot().clock) - start_clock
	extra["real_time"] = {"real": real, "hud": hud_elapsed, "scaled_delta_sum": scaled}
	check(absf(hud_elapsed - real) < 0.1, "HUD clock follows real time under time_scale 0.5 (hud %.3f s, real %.3f s)" % [hud_elapsed, real])
	check(scaled < real * 0.75, "scaled process delta really was slowed (%.3f s)" % scaled)
	check(hud.get_debug_snapshot().callouts.size() == 1, "1.0 s callout still up after 0.6 s real")
	while Time.get_ticks_usec() - start_usec < 1150000:
		await get_tree().process_frame
	check(hud.get_debug_snapshot().callouts.is_empty(), "1.0 s callout gone after 1.15 s real (not 2.0 s scaled)")
	Engine.time_scale = 1.0
	hud.debug_manual_clock = true


## A click goes through every HUD element to the control underneath.
func check_mouse_passthrough() -> void:
	var button := Button.new()
	button.text = "behind"
	button.position = Vector2(540.0, 330.0)
	button.size = Vector2(200.0, 100.0)
	button.pressed.connect(func() -> void: button_presses += 1)
	add_child(button)
	move_child(button, 1)
	hud.show_rule_card(2.0)
	hud.set_letterbox(1.0)
	hud.set_danger(1.0)
	hud.flash(1.0, 5.0)
	hud.callout("P1 SAFE!", GREEN, 3.0)
	await advance(0.6)
	await frames(2)
	var at := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await frames(2)
	await frames(2)
	check(button_presses == 1, "click passes through the HUD to the button underneath")
	button.queue_free()
	hud.hide_all(true)


func check_hide_all() -> void:
	hud.show_cut_in()
	hud.show_shout("サドンデス！")
	hud.show_rule_card(2.0)
	hud.set_countdown("3")
	hud.callout("P1 SAFE!", GREEN)
	hud.set_danger(1.0)
	hud.set_letterbox(1.0)
	hud.set_depth_meter(1.0, 20.0, true)
	hud.show_winner(1)
	await advance(0.3)
	hud.hide_all(true)
	await advance(STEP)
	var snap := hud.get_debug_snapshot()
	var any := false
	for key in ["cut_in", "depth_meter", "letterbox", "shout", "rule_card", "countdown", "winner"]:
		any = any or bool(snap[key].visible)
	check(not any and snap.callouts.is_empty() and float(snap.danger) == 0.0 and float(snap.flash) == 0.0, "hide_all(true) clears every element")


# ------------------------------------------------------------------ helpers

func advance(seconds: float) -> void:
	var left := seconds
	while left > 0.0001:
		var step := minf(STEP, left)
		hud.debug_step(step)
		left -= step
	await frames(1)


func frames(count: int) -> void:
	for index in range(count):
		await get_tree().process_frame


func viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func check_inside(snap: Dictionary, key: String) -> void:
	var rect: Rect2 = snap.rects.get(key, Rect2())
	var bounds := Rect2(Vector2.ZERO, viewport_size()).grow(1.0)
	check(rect.size.x > 0.0 and bounds.encloses(rect), "%s inside the %dx%d view (%s)" % [key, int(bounds.size.x - 2.0), int(bounds.size.y - 2.0), rect])


func capture(tag: String) -> void:
	await frames(1)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := OUT + tag + ".png"
	image.save_png(path)
	var snap := hud.get_debug_snapshot()
	snap.erase("rects")
	shots.append({"tag": tag, "size": [image.get_width(), image.get_height()], "snapshot": snap})


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func use_backdrop(key: String) -> void:
	backdrop.texture = textures.get(key)


func _build_backdrops() -> void:
	var cistern := _load_shot(CISTERN_SHOT)
	if cistern != null:
		# Paint out the milestone-1 HUD captured in that frame.
		cistern.fill_rect(Rect2i(440, 8, 400, 92), Color(0.018, 0.018, 0.02))
	textures["cistern"] = ImageTexture.create_from_image(cistern if cistern != null else _gradient(Color(0.05, 0.05, 0.05), Color(0.2, 0.19, 0.16)))
	var draw := _load_shot(DRAW_SHOT)
	textures["draw"] = ImageTexture.create_from_image(draw if draw != null else _gradient(Color(0.45, 0.65, 0.9), Color(0.5, 0.5, 0.55)))
	textures["shaft"] = ImageTexture.create_from_image(_shaft())


func _load_shot(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.load_from_file(absolute)
	if image != null:
		image.convert(Image.FORMAT_RGB8)
	return image


func _gradient(top: Color, bottom: Color) -> Image:
	var image := Image.create(16, 90, false, Image.FORMAT_RGB8)
	for y in range(90):
		image.fill_rect(Rect2i(0, y, 16, 1), top.lerp(bottom, float(y) / 89.0))
	return image


## Stand-in for the yellow-lamp shaft: dark concrete, sodium lamps converging below.
func _shaft() -> Image:
	var size := Vector2i(192, 108)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var lamps: Array[Vector2] = []
	for ring in range(7):
		var depth := float(ring) / 6.0
		var y := lerpf(-6.0, 92.0, 1.0 - pow(1.0 - depth, 1.8))
		var spread := lerpf(120.0, 18.0, depth)
		for side in [-1.0, -0.35, 0.35, 1.0]:
			lamps.append(Vector2(96.0 + float(side) * spread, y))
	for y in range(size.y):
		for x in range(size.x):
			var p := Vector2(float(x), float(y))
			var wall := 0.03 + 0.03 * (1.0 - absf(float(x) - 96.0) / 96.0) * (1.0 - float(y) / 108.0)
			var light := 0.0
			for lamp in lamps:
				light += 3.2 / (1.0 + p.distance_squared_to(lamp) * 0.9) + 0.06 / (1.0 + p.distance_squared_to(lamp) * 0.02)
			var abyss := 1.0 - 0.7 * exp(-pow((float(x) - 96.0) / 30.0, 2.0) - pow((float(y) - 100.0) / 22.0, 2.0))
			var color := Color(wall, wall * 0.92, wall * 0.8) + Color(1.0, 0.62, 0.15) * light
			image.set_pixel(x, y, (color * abyss).clamp())
	return image


func finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"renderer": RenderingServer.get_current_rendering_method(), "shots": shots, "extra": extra}
	var file := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SUDDEN_DEATH_HUD_RUNTIME " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
